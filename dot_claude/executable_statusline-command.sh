#!/bin/sh
input=$(cat)
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
if [ -n "$remaining" ]; then
  printf "Context remaining: %s%%" "$remaining"
else
  printf "Context: --"
fi
