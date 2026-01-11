#!/bin/bash

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip if no file path or not a Python file
if [ -z "$FILE_PATH" ] || [[ ! "$FILE_PATH" =~ \.py$ ]]; then
    exit 0
fi

# Skip if file doesn't exist
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

IGNORE="ANN401,BLE,D,E501,EM,PD002,PD901,PLC01,PLR09,PLR2004,PTH123,TC"

ruff check --fix --line-length 160 --select ALL --ignore "$IGNORE" "$FILE_PATH" 2>/dev/null || true
ruff format --line-length 160 "$FILE_PATH" 2>/dev/null || true

exit 0
