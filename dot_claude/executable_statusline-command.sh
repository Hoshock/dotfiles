#!/bin/sh
input=$(cat)

# Context remaining
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
if [ -n "$remaining" ]; then
	context="Context: ${remaining}%"
else
	context="Context: --"
fi

# Git repo / branch / worktree info
repo_info=""
branch=$(git branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
	toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
	if [ -n "$toplevel" ]; then
		wt_dir=$(basename "$toplevel")
		repo_name=$(basename "$(dirname "$toplevel")")
		branch_as_dir=$(echo "$branch" | tr '/' '-')
		if [ "$wt_dir" = "$branch_as_dir" ] && [ "$wt_dir" != "$repo_name" ]; then
			# Worktree: repo/worktree (branch)
			repo_info="${repo_name}/${wt_dir} (${branch})"
		else
			# Normal repo: repo (branch)
			repo_info="${wt_dir} (${branch})"
		fi
	fi
fi

# Output
if [ -n "$repo_info" ]; then
	printf "%s | %s" "$repo_info" "$context"
else
	printf "%s" "$context"
fi
