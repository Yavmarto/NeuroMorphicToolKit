#!/bin/bash

# Script to create GitHub issues from markdown files in submodule 'issues' directories

for dir in */ ; do
    if [ -d "${dir}issues" ]; then
        echo "Processing repository: $dir"
        cd "$dir" || continue

        # Check if the directory is a git repository
        if git rev-parse --git-dir > /dev/null 2>&1; then
            for md_file in issues/*.md; do
                if [ -f "$md_file" ]; then
                    # Use the filename without the .md extension as the title
                    title=$(basename "$md_file" .md)
                    # Replace underscores and hyphens with spaces for a cleaner title
                    clean_title=$(echo "$title" | tr '_-' ' ')

                    echo "  Creating issue '$clean_title' from $md_file..."
                    # Only uncomment the line below if you actually want to publish the issues to GitHub
                    gh issue create --title "$clean_title" --body-file "$md_file"
                fi
            done
        else
            echo "  Skipping: $dir is not a git repository."
        fi
        cd ..
    fi
done

echo "Done."
