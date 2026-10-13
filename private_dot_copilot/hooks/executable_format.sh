#!/bin/bash

# Copilot CLI variant of ~/.claude/hooks/format.sh. The only difference is how
# the edited path is read: Copilot's edit/create tools send `path` (not
# `file_path`), and the camelCase payload carries it in `toolArgs`, which may be
# a JSON string.
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '
    (.toolArgs | if type == "string" then (fromjson? // {}) else . end) as $args
    | .tool_input.file_path // .tool_input.path // $args.path // $args.file_path // empty')

# Skip if no file path or file doesn't exist
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

EXT="${FILE_PATH##*.}"

case "$EXT" in
html | json)
    prettier --write --ignore-path /dev/null "$FILE_PATH" 2>/dev/null || true
    ;;
lua)
    stylua "$FILE_PATH" 2>/dev/null || true
    ;;
md)
    prettier --write --ignore-path /dev/null "$FILE_PATH" 2>/dev/null || true
    ;;
nix)
    nixfmt "$FILE_PATH" 2>/dev/null || true
    ;;
py)
    # ruff check --fix (e.g. COM812) and ruff format can each trigger a change
    # the other only reacts to on the next pass, so loop until stable.
    prev=""
    for _ in 1 2 3; do
        ruff check --fix "$FILE_PATH" 2>/dev/null || true
        ruff format "$FILE_PATH" 2>/dev/null || true
        cur=$(cat "$FILE_PATH")
        [ "$cur" = "$prev" ] && break
        prev="$cur"
    done
    ;;
sh | bash)
    shfmt -i 4 -w "$FILE_PATH" 2>/dev/null || true
    ;;
yaml | yml)
    prettier --write --ignore-path /dev/null "$FILE_PATH" 2>/dev/null || true
    ;;
esac

exit 0
