#!/bin/bash
set -euo pipefail

# 公開から COOLDOWN_DAYS 日経っていないリリースは入れない (サプライチェーン攻撃対策)
COOLDOWN_DAYS="${COOLDOWN_DAYS:-7}"
until=$(date -u -v-"${COOLDOWN_DAYS}"d +%Y-%m-%dT%H:%M:%SZ)

# bun
# curl -fsSL https://bun.com/install | bash

# rustup: 本体は初回だけ入れ、toolchain はクールタイムを過ぎた stable に固定する
if ! command -v rustup >/dev/null; then
    curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain none
    . "$HOME/.cargo/env"
fi
rustup set auto-self-update disable
rust_version=$(gh api 'repos/rust-lang/rust/releases?per_page=20' \
    --jq "[.[] | select((.prerelease | not) and .published_at < \"${until}\")][0].tag_name")
rustup toolchain install "${rust_version}"
rustup default "${rust_version}"

# claude code: stable チャンネル (約 1 週間遅れ) を入れる。以降の自動更新も settings.json の autoUpdatesChannel で stable
curl -fsSL https://claude.ai/install.sh | bash -s stable

# codex cli: 公式インストーラーを、公開から COOLDOWN_DAYS 日経った最新リリースに固定して入れる。
# ~/.local/bin が PATH にあればインストーラーはシェルの設定ファイルを書き換えない。
# 更新チェックは dot_codex/modify_config.toml で無効にしている
codex_version=$(gh api 'repos/openai/codex/releases?per_page=30' \
    --jq "[.[] | select((.prerelease | not) and (.draft | not) and (.tag_name | startswith(\"rust-v\")) and .published_at < \"${until}\")][0].tag_name // \"\" | ltrimstr(\"rust-v\")")
if [[ ! "${codex_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "codex: クールタイムを過ぎたリリースが見つからない: '${codex_version}'" >&2
    exit 1
fi
codex_current=$("$HOME/.local/bin/codex" --version 2>/dev/null | awk '{print $2}' || true)
if [[ "${codex_current}" != "${codex_version}" ]]; then
    curl -fsSL https://chatgpt.com/codex/install.sh |
        PATH="$HOME/.local/bin:$PATH" CODEX_NON_INTERACTIVE=1 sh -s -- --release "${codex_version}"
fi

# copilot cli は nix (home-manager) で入れる。flake のクールタイムが効く
