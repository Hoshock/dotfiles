#!/bin/bash
set -eu

TEMPLATE_SOURCE="$HOME/Projects/Hoshock-CFn-Suite/cfn/tmpl/tmpl-data-stock"

if [ $# -ne 2 ]; then
    echo "Usage: $0 <destination_path> <directory_name>"
    echo "Example: $0 ./cfn my-data-processor"
    exit 1
fi

DEST_PATH="$1"
DIR_NAME="$2"
TARGET_DIR="${DEST_PATH}/${DIR_NAME}"

if [ -e "$TARGET_DIR" ]; then
    echo "Error: ${TARGET_DIR} already exists"
    exit 1
fi

if [ ! -d "$TEMPLATE_SOURCE" ]; then
    echo "Error: Template source not found: ${TEMPLATE_SOURCE}"
    exit 1
fi

mkdir -p "$DEST_PATH"
cp -r "$TEMPLATE_SOURCE" "$TARGET_DIR"

echo "Created: ${TARGET_DIR}"
echo ""
echo "Next steps:"
echo "  1. Edit template.yaml - Set SNS topic ARN"
echo "  2. Edit src/app/lambda_function.py - Implement record_handler"
echo "  3. Edit cfn_params/*.json - Set parameters"
