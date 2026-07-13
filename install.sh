#!/bin/bash
set -euo pipefail

# bun
# curl -fsSL https://bun.com/install | bash

# rustup
curl https://sh.rustup.rs -sSf | sh

# claude code
curl -fsSL https://claude.ai/install.sh | bash

# copilot cli
curl -fsSL https://gh.io/copilot-install | bash

# codex cli
curl -fsSL https://chatgpt.com/codex/install.sh | sh
