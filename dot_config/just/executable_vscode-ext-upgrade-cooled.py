#!/usr/bin/env python3
"""VS Code の拡張を公開後のクールタイム付きで更新する。

VS Code の extensions.autoUpdateDelay は trustedExtensionPublishers (microsoft / github / openai) の
拡張には効かないため、自動更新は止めてこのスクリプトで更新する。Marketplace から各バージョンの
公開日時を取り、cooldown 日数より前に出た stable 版のうち、この VS Code で動く最新のものを入れる。
"""

import argparse
import datetime
import json
import platform
import re
import subprocess

API = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
PLATFORMS = {
    None,
    "universal",
    "darwin-arm64" if platform.machine() == "arm64" else "darwin-x64",
}


def vtuple(v: str) -> tuple[int, ...]:
    return tuple(
        int(m.group()) if (m := re.match(r"\d+", p)) else 0
        for p in v.split("-")[0].split(".")
    )


def prop(version: dict, key: str) -> str | None:
    return next(
        (p["value"] for p in version.get("properties", []) if p["key"] == key), None
    )


def engine_ok(engine: str | None, code_version: tuple[int, ...]) -> bool:
    if not engine or engine.strip() == "*":
        return True
    return code_version >= vtuple(engine.lstrip("^>=~ "))


def query(ids: list[str]) -> list[dict]:
    body = {
        "filters": [
            {
                "criteria": [{"filterType": 8, "value": "Microsoft.VisualStudio.Code"}]
                + [{"filterType": 7, "value": i} for i in ids],
                "pageSize": len(ids),
            }
        ],
        "flags": 1 | 16,  # IncludeVersions | IncludeVersionProperties
    }
    # Python の urllib は社内 FortiSASE の CA を知らないので、キーチェーンを使う /usr/bin/curl で取る
    out = subprocess.run(
        [
            "/usr/bin/curl",
            "-fsS",
            "-X",
            "POST",
            API,
            "-H",
            "Content-Type: application/json",
            "-H",
            "Accept: application/json;api-version=7.2-preview.1",
            "-d",
            json.dumps(body),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)["results"][0]["extensions"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    cutoff = datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=args.days)

    code_version = vtuple(
        subprocess.run(
            ["code", "--version"], check=True, capture_output=True, text=True
        ).stdout.split()[0]
    )
    lines = subprocess.run(
        ["code", "--list-extensions", "--show-versions"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    installed = {
        line.rsplit("@", 1)[0].lower(): line.rsplit("@", 1)[1] for line in lines
    }

    for ext in query(list(installed)):
        ext_id = f"{ext['publisher']['publisherName']}.{ext['extensionName']}".lower()
        current = installed.get(ext_id)
        if current is None:
            continue
        candidate = None
        for v in ext["versions"]:
            published = datetime.datetime.fromisoformat(
                v["lastUpdated"].replace("Z", "+00:00")
            )
            if (
                v.get("targetPlatform") in PLATFORMS
                and prop(v, "Microsoft.VisualStudio.Code.PreRelease") != "true"
                and published <= cutoff
                and engine_ok(
                    prop(v, "Microsoft.VisualStudio.Code.Engine"), code_version
                )
                and (
                    candidate is None
                    or vtuple(v["version"]) > vtuple(candidate["version"])
                )
            ):
                candidate = v
        if candidate is None or vtuple(candidate["version"]) <= vtuple(current):
            continue
        print(
            f"upgrade {ext_id} {current} -> {candidate['version']} (published {candidate['lastUpdated'][:10]})"
        )
        if not args.dry_run:
            subprocess.run(
                [
                    "code",
                    "--install-extension",
                    f"{ext_id}@{candidate['version']}",
                    "--force",
                ],
                check=True,
            )


if __name__ == "__main__":
    main()
