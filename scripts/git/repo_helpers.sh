#!/usr/bin/env bash

list_managed_repos() {
  local root_dir="$1"
  local repo_dir=""
  local top_level=""
  local repo_name=""

  for repo_dir in "$root_dir"/*; do
    [[ -d "$repo_dir" ]] || continue

    if ! top_level="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null)"; then
      continue
    fi

    if [[ "$top_level" != "$repo_dir" ]]; then
      continue
    fi

    repo_name="$(basename "$repo_dir")"
    printf '%s\t%s\n' "$repo_name" "$repo_dir"
  done

  printf '(root)\t%s\n' "$root_dir"
}
