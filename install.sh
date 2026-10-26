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

# copilot cli と codex cli は nix (home-manager) で入れる。flake のクールタイムが効く
