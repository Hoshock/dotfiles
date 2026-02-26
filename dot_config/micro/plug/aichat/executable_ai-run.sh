#!/usr/bin/env bash
# ai-run.sh — non-interactive copilot query
# Usage: ai-run.sh <prompt_file> [model]
set -uo pipefail

LOG="/tmp/micro-aichat.log"
STDERR_TMP="/tmp/micro-ai-stderr.txt"
MODEL_FILE="/tmp/micro-ai-lastmodel.txt"

PROMPT_FILE="${1:-}"
MODEL="${2:-}"

if [[ -z "$PROMPT_FILE" || ! -f "$PROMPT_FILE" ]]; then
	echo "Error: invalid prompt file" >&2
	exit 1
fi

PROMPT=$(<"$PROMPT_FILE")

CMD=(copilot -p "$PROMPT" --allow-tool 'write')
if [[ -n "$MODEL" ]]; then
	CMD+=(--model "$MODEL")
fi

"${CMD[@]}" 2>"$STDERR_TMP"
EXIT_CODE=$?

# extract model name from copilot's usage stats in stderr
# line looks like: " claude-sonnet-4.6       42.5k in, ..."
awk '/Breakdown by AI model/{getline; print $1}' "$STDERR_TMP" >"$MODEL_FILE" 2>/dev/null || true
cat "$STDERR_TMP" >>"$LOG"

exit $EXIT_CODE
