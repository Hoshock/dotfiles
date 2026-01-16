---
name: ncpd-tool-init
description: Python tool templates for standalone scripts. Use when scaffolding new Python tool projects.
---

# NCPD Tool Templates

This skill helps you scaffold Python tool projects for standalone scripts and utilities.

## Available Templates

| Template    | Description                              | Details                            |
| ----------- | ---------------------------------------- | ---------------------------------- |
| tmpl-python | StateMachine batch executor with uv/ruff | [tmpl-python.md](./tmpl-python.md) |

## Usage

1. Read the template details via the links above
2. Run the shell script in `scripts/` to copy the template:

```bash
~/.claude/skills/ncpd-tool-init/scripts/scaffold.sh <template_name> <destination_path> <directory_name>
```
