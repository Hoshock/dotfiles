#!/bin/bash
set -eu

TEMPLATE_BASE="$HOME/Projects/Hoshock-CFn-Suite/tools/tmpl"

if [ $# -ne 3 ]; then
    echo "Usage: $0 <template_name> <destination_path> <directory_name>"
    exit 1
fi

TEMPLATE_NAME="$1"
DEST_PATH="$2"
DIR_NAME="$3"
TEMPLATE_SOURCE="${TEMPLATE_BASE}/${TEMPLATE_NAME}"
TARGET_DIR="${DEST_PATH}/${DIR_NAME}"

if [ -e "$TARGET_DIR" ]; then
    echo "Error: ${TARGET_DIR} already exists"
    exit 1
fi

if [ ! -d "$TEMPLATE_SOURCE" ]; then
    echo "Error: Template not found: ${TEMPLATE_NAME}"
    exit 1
fi

mkdir -p "$DEST_PATH"
cp -r "$TEMPLATE_SOURCE" "$TARGET_DIR"

echo "Created: ${TARGET_DIR}"
