#!/usr/bin/env bash
# move-issues-to-archive.sh
#
# Finds every `issues/` directory in the repo (root + submodules),
# moves all files inside it to a sibling `issues-archive/` directory,
# and creates that archive directory when it does not already exist.
#
# Usage: bash scripts/move-issues-to-archive.sh [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[DRY RUN] No files will be moved."
fi

moved=0
skipped_empty=0
skipped_exists=0

while IFS= read -r issues_dir; do
    # Count files (non-recursive, top level only)
    file_count=$(find "$issues_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')

    if [[ "$file_count" -eq 0 ]]; then
        echo "skip (empty)  : $issues_dir"
        ((skipped_empty++)) || true
        continue
    fi

    parent_dir="$(dirname "$issues_dir")"
    archive_dir="$parent_dir/issues-archive"

    if [[ ! -d "$archive_dir" ]]; then
        echo "create archive: $archive_dir"
        $DRY_RUN || mkdir -p "$archive_dir"
    fi

    while IFS= read -r file; do
        filename="$(basename "$file")"
        dest="$archive_dir/$filename"

        if [[ -e "$dest" ]]; then
            echo "  skip (exists): $filename  ->  $archive_dir/"
            ((skipped_exists++)) || true
        else
            echo "  move         : $filename  ->  $archive_dir/"
            $DRY_RUN || mv "$file" "$dest"
            ((moved++)) || true
        fi
    done < <(find "$issues_dir" -maxdepth 1 -type f | sort)

done < <(find "$REPO_ROOT" \
    -not -path '*/.git/*' \
    -type d \
    -name "issues" \
    | sort)

echo ""
echo "Summary:"
echo "  moved         : $moved"
echo "  skipped empty : $skipped_empty"
echo "  skipped exists: $skipped_exists"
$DRY_RUN && echo "  (dry-run — no changes written)"
