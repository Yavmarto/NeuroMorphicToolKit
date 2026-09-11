# Task: Multi-Repo Git Stash Manager with Date and Batch Removal

## Overview
Create a script that lists all stashes with dates across all repositories in the monorepo (root + submodules) and provides a simple ability to batch remove them.

## Requirements
1. Discover all managed repos (root repo + git submodules).
2. Query stashes with ISO timestamp, relative time, and stash message.
3. Formatted display with index numbers, repo name, date, and description.
4. Batch removal capability:
   - Drop all
   - Drop by selected indices / ranges (`1,3-5`)
   - Drop by repository (`--repo` or `repo:<name>`)
   - Drop by age (`--older-than <days>`)
   - Interactive prompt and CLI flags (`--dry-run`, `--yes`, etc.)
   - Drop in descending order per repository to prevent stash index shifting.
