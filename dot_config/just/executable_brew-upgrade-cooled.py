#!/usr/bin/env python3
"""brew upgrade に公開後のクールタイムを設ける。

Homebrew にはネイティブのクールタイムがないため、outdated な formula / cask ごとに
tap リポジトリで定義ファイル (ruby_source_path) が最後に変更された日時を GitHub API で調べ、
cooldown 日数より前のものだけを upgrade する。依存先・依存元に保留中のものがあれば一緒に保留する
(brew upgrade はそれらも巻き込んで upgrade するため)。
"""

import argparse
import datetime
import json
import os
import subprocess

ENV = {**os.environ, "HOMEBREW_NO_AUTO_UPDATE": "1"}


def brew_json(*args: str) -> dict:
    out = subprocess.run(
        ["brew", *args], env=ENV, check=True, capture_output=True, text=True
    )
    return json.loads(out.stdout)


def last_changed(tap: str, path: str) -> datetime.datetime | None:
    # homebrew/core -> homebrew/homebrew-core, manaflow-ai/cmux -> manaflow-ai/homebrew-cmux
    user, repo = tap.split("/")
    out = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{user}/homebrew-{repo}/commits?path={path}&per_page=1",
            "--jq",
            ".[0].commit.committer.date",
        ],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0 or not out.stdout.strip():
        return None
    return datetime.datetime.fromisoformat(out.stdout.strip().replace("Z", "+00:00"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--skip", nargs="*", default=[], help="アプリ自身の自動更新に任せる cask"
    )
    args = parser.parse_args()
    cutoff = datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=args.days)

    subprocess.run(["brew", "update", "--quiet"], check=True)
    # auto_updates な cask もアプリ側の自動更新を止めて brew で更新するので含める
    outdated = brew_json("outdated", "--json=v2", "--greedy-auto-updates")
    installed = brew_json("info", "--json=v2", "--installed")

    # outdated の name は tap 付きのこともあるので full_name / name の両方で引けるようにする
    items: dict[str, dict] = {}
    for f in installed["formulae"]:
        item = {
            "kind": "formula",
            "name": f["full_name"],
            "tap": f["tap"],
            "path": f.get("ruby_source_path"),
            "deps": set(f["dependencies"]),
        }
        items[f["full_name"]] = items[f["name"]] = item
    for c in installed["casks"]:
        item = {
            "kind": "cask",
            "name": c["full_token"],
            "tap": c["tap"],
            "path": c.get("ruby_source_path"),
            "deps": set(c.get("depends_on", {}).get("formula", [])),
            "no_check": c.get("sha256") == "no_check",
        }
        items[c["full_token"]] = items[c["token"]] = item

    targets: dict[str, dict] = {}
    for o in outdated["formulae"] + outdated["casks"]:
        if o.get("pinned"):
            continue
        item = items[o["name"]]
        if item["name"] in args.skip or item.get("no_check"):
            # sha256 :no_check の cask は定義の日付と関係なく配布元の最新版を落とすので、クールタイムをかけられない
            print(f"{'skip':<18} cask     {item['name']}")
            continue
        changed = (
            last_changed(item["tap"], item["path"])
            if item["tap"] and item["path"]
            else None
        )
        status = "ok" if changed and changed <= cutoff else "hold"
        targets[item["name"]] = {
            **item,
            "version": o["current_version"],
            "changed": changed,
            "status": status,
        }

    def closure(name: str) -> set[str]:
        seen, stack = set(), [name]
        while stack:
            for d in items.get(stack.pop(), {"deps": set()})["deps"]:
                if d not in seen:
                    seen.add(d)
                    stack.append(items[d]["name"] if d in items else d)
        return seen

    # 依存先・依存元に hold があれば、upgrade で巻き込まないよう自分も hold にする
    changed_any = True
    while changed_any:
        changed_any = False
        held = {n for n, t in targets.items() if t["status"] == "hold"}
        for name, t in targets.items():
            if t["status"] != "ok":
                continue
            if closure(name) & held or any(name in closure(h) for h in held):
                t["status"] = "hold (dependency)"
                changed_any = True

    for name, t in sorted(targets.items()):
        changed = t["changed"].strftime("%Y-%m-%d") if t["changed"] else "unknown"
        print(
            f"{t['status']:<18} {t['kind']:<8} {name} {t['version']} (changed {changed})"
        )

    for kind in ("formula", "cask"):
        names = [
            n for n, t in targets.items() if t["kind"] == kind and t["status"] == "ok"
        ]
        if names and not args.dry_run:
            subprocess.run(
                # --greedy: auto_updates な cask も upgrade する
                [
                    "brew",
                    "upgrade",
                    f"--{kind}",
                    *(["--greedy"] if kind == "cask" else []),
                    *names,
                ],
                env=ENV,
                check=True,
            )


if __name__ == "__main__":
    main()
