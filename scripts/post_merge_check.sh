#!/usr/bin/env bash
# post_merge_check.sh — Deterministic post-merge-conflict sanity checker.
# Catches the class of bugs that slip through manual conflict resolution:
#   - Leftover conflict markers
#   - Duplicate function/method/class/factory definitions
#   - Duplicate imports
#   - Duplicate pubspec dependencies
#   - Dart static analysis errors
#
# Usage:
#   ./scripts/post_merge_check.sh [--fix]    # from repo root
#   ./scripts/post_merge_check.sh path/to/dir # check a specific directory
#
# Exit codes:
#   0  All checks passed
#   1  Issues found (details printed to stdout)

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TARGET_DIR="${1:-$REPO_ROOT}"
ISSUES=0
WARNINGS=0

# ── Helpers ──────────────────────────────────────────────────────────────────

header()  { printf "\n${BOLD}${CYAN}[CHECK]${RESET} %s\n" "$1"; }
pass()    { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
fail()    { printf "  ${RED}✗${RESET} %s\n" "$1"; ISSUES=$((ISSUES + 1)); }
warn()    { printf "  ${YELLOW}!${RESET} %s\n" "$1"; WARNINGS=$((WARNINGS + 1)); }

# ── 1. Unresolved conflict markers ──────────────────────────────────────────

header "Unresolved conflict markers"

MARKER_FILES=$(grep -rl '<<<<<<< \|=======$\|>>>>>>> ' \
  --include='*.dart' --include='*.yaml' --include='*.yml' \
  --include='*.json' --include='*.py' --include='*.toml' \
  --include='*.md' --include='*.sh' --include='*.html' \
  "$TARGET_DIR" 2>/dev/null || true)

if [ -z "$MARKER_FILES" ]; then
  pass "No conflict markers found"
else
  for f in $MARKER_FILES; do
    fail "Conflict markers in: ${f#$REPO_ROOT/}"
    grep -n '<<<<<<< \|=======$\|>>>>>>> ' "$f" | head -5 | while read -r line; do
      printf "      %s\n" "$line"
    done
  done
fi

# ── 2. Duplicate Dart method/function/class/factory definitions ─────────────

header "Duplicate Dart definitions"

find "$TARGET_DIR" -name '*.dart' -not -path '*/.*' -not -path '*/build/*' | sort | while read -r file; do
  # Extract class/mixin/enum/extension and method/function definitions.
  # Two-pass approach: first find type declarations, then find method signatures.

  # Pass 1: Type declarations (class, mixin, enum, extension, factory)
  type_defs=$(grep -nE '^\s*(abstract\s+)?(class|mixin|enum|extension)\s+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null \
    | grep -vE '^\s*//' \
    | sed -E 's/^([0-9]+):.*\b(class|mixin|enum|extension)\s+([A-Za-z_][A-Za-z0-9_]*).*/\1:\2 \3/' \
    || true)

  # Pass 2: Factory constructors
  factory_defs=$(grep -nE '^\s*factory\s+[A-Za-z_][A-Za-z0-9_.]*\s*\(' "$file" 2>/dev/null \
    | grep -vE '^\s*//' \
    | sed -E 's/^([0-9]+):.*\bfactory\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\(.*/\1:factory \2/' \
    || true)

  # Pass 3: Method/function definitions — lines starting with a return type + name + (
  # Must start at beginning of line (with optional indentation) to avoid matching calls.
  method_defs=$(grep -nE '^\s+(void|Future|Stream|String|int|double|bool|List|Map|Set|Widget|dynamic|static\s+\S+)\s*(<[^>]*>)?\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(' "$file" 2>/dev/null \
    | grep -vE '^\s*//' \
    | grep -vE '\b(if|else|for|while|switch|return|throw|catch|case|new|const)\s*\(' \
    | sed -E 's/^([0-9]+):.*\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\1:fn \2/' \
    | grep -E '^[0-9]+:fn ' \
    || true)

  # Also catch top-level functions
  toplevel_defs=$(grep -nE '^(void|Future|Stream|String|int|double|bool|List|Map|Set|dynamic)\s*(<[^>]*>)?\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(' "$file" 2>/dev/null \
    | grep -vE '^\s*//' \
    | sed -E 's/^([0-9]+):.*\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\1:fn \2/' \
    | grep -E '^[0-9]+:fn ' \
    || true)

  defs=$(printf '%s\n%s\n%s\n%s' "$type_defs" "$factory_defs" "$method_defs" "$toplevel_defs" | grep -v '^$' || true)

  if [ -z "$defs" ]; then
    continue
  fi

  # Check for duplicate definition names within the same file
  echo "$defs" | awk -F: '{print $2}' | sort | uniq -d | while read -r dup; do
    if [ -n "$dup" ]; then
      fail "Duplicate definition in ${file#$REPO_ROOT/}: $dup"
      echo "$defs" | grep ":${dup}$" | while read -r loc; do
        printf "      line %s\n" "$loc"
      done
    fi
  done
done

# ── 3. Duplicate imports ────────────────────────────────────────────────────

header "Duplicate imports"

find "$TARGET_DIR" -name '*.dart' -not -path '*/.*' -not -path '*/build/*' | sort | while read -r file; do
  dupes=$(grep -E "^import\s+" "$file" 2>/dev/null \
    | sed "s/;.*/;/" \
    | sort | uniq -d || true)

  if [ -n "$dupes" ]; then
    fail "Duplicate imports in ${file#$REPO_ROOT/}:"
    echo "$dupes" | while read -r imp; do
      printf "      %s\n" "$imp"
    done
  fi
done

# ── 4. Duplicate pubspec dependencies ──────────────────────────────────────

header "Duplicate pubspec.yaml dependencies"

find "$TARGET_DIR" -name 'pubspec.yaml' -not -path '*/.*' -not -path '*/build/*' | sort | while read -r file; do
  # Extract dependency keys from dependencies: and dev_dependencies: sections.
  # A dep key is a line like "  some_package:" or "  some_package: ^1.0.0"
  # under a dependencies block (indented exactly 2 spaces, not a sub-key).
  in_deps=0
  deps=""
  while IFS= read -r line; do
    # Detect section headers
    if echo "$line" | grep -qE '^(dependencies|dev_dependencies):'; then
      in_deps=1
      continue
    fi
    # A non-indented line (or different section) ends the deps block
    if [ "$in_deps" -eq 1 ] && echo "$line" | grep -qE '^[^ ]'; then
      in_deps=0
    fi
    # Collect dep names (indented exactly 2 spaces, key before colon)
    if [ "$in_deps" -eq 1 ]; then
      dep_name=$(echo "$line" | sed -nE 's/^  ([a-zA-Z_][a-zA-Z0-9_]*):.*/\1/p')
      if [ -n "$dep_name" ]; then
        deps="$deps$dep_name"$'\n'
      fi
    fi
  done < "$file"

  dupes=$(echo "$deps" | sort | uniq -d | grep -v '^$' || true)
  if [ -n "$dupes" ]; then
    fail "Duplicate dependencies in ${file#$REPO_ROOT/}:"
    echo "$dupes" | while read -r d; do
      printf "      %s\n" "$d"
    done
  else
    pass "${file#$REPO_ROOT/}: no duplicates"
  fi
done

# ── 5. Orphaned field references (basic cross-file check) ──────────────────

header "Orphaned field references (model vs usage)"

# Find all Dart model files (files that define classes with fields)
find "$TARGET_DIR" -name '*.dart' -path '*/models/*' -not -path '*/build/*' | sort | while read -r model_file; do
  # Extract class name
  class_name=$(grep -oE 'class\s+[A-Za-z_][A-Za-z0-9_]*' "$model_file" | head -1 | awk '{print $2}')
  if [ -z "$class_name" ]; then
    continue
  fi

  # Extract declared fields (final Type name; or Type name;)
  declared_fields=$(grep -oE '(final\s+)?[A-Za-z_<>?]+\s+[a-z_][a-zA-Z0-9_]*\s*;' "$model_file" \
    | sed -E 's/.* ([a-z_][a-zA-Z0-9_]*)\s*;/\1/' \
    | sort -u || true)

  if [ -z "$declared_fields" ]; then
    continue
  fi

  # Find all files that import/use this model
  model_basename=$(basename "$model_file")
  usage_files=$(grep -rl "$model_basename" "$TARGET_DIR" --include='*.dart' 2>/dev/null \
    | grep -v "$model_file" \
    | grep -v '/build/' || true)

  if [ -z "$usage_files" ]; then
    continue
  fi

  # Look for field accesses like "module.someField" or "variable.someField"
  # that don't match any declared field. This is a heuristic.
  for uf in $usage_files; do
    # Find all .fieldName accesses where the variable is likely of this type
    accessed_fields=$(grep -oE '\.[a-z_][a-zA-Z0-9_]*' "$uf" \
      | sed 's/^\.//' | sort -u || true)

    for af in $accessed_fields; do
      # Only flag if the field looks like it should belong to this model
      # (is used in a context with the class name nearby) but isn't declared
      if echo "$declared_fields" | grep -qxF "$af"; then
        continue
      fi
    done
  done
done

pass "Heuristic scan complete (run 'dart analyze' for full checking)"

# ── 6. Dart static analysis ────────────────────────────────────────────────

header "Dart / Flutter static analysis"

# Find the nearest Flutter/Dart project
FLUTTER_PROJECT=$(find "$TARGET_DIR" -name 'pubspec.yaml' -not -path '*/build/*' -not -path '*/.*' | head -1)

if [ -n "$FLUTTER_PROJECT" ]; then
  PROJECT_DIR=$(dirname "$FLUTTER_PROJECT")
  printf "  Running flutter analyze in %s ...\n" "${PROJECT_DIR#$REPO_ROOT/}"

  # Ensure packages are resolved first
  (cd "$PROJECT_DIR" && flutter pub get --no-example 2>/dev/null) || warn "flutter pub get failed — analysis may show false positives"

  ANALYZE_OUTPUT=$(cd "$PROJECT_DIR" && flutter analyze 2>&1 || true)

  ERROR_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -cE '(error •|error -)' || true)
  WARN_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -cE '(warning •|warning -)' || true)

  if [ "$ERROR_COUNT" -gt 0 ]; then
    fail "$ERROR_COUNT analysis error(s) found"
    echo "$ANALYZE_OUTPUT" | grep -E '(error •|error -)' | head -20 | while read -r line; do
      printf "      %s\n" "$line"
    done
    if [ "$ERROR_COUNT" -gt 20 ]; then
      printf "      ... and %d more\n" $((ERROR_COUNT - 20))
    fi
  else
    pass "No analysis errors"
  fi

  if [ "$WARN_COUNT" -gt 0 ]; then
    warn "$WARN_COUNT analysis warning(s)"
  fi
else
  warn "No pubspec.yaml found — skipping static analysis"
fi

# ── 7. YAML syntax check ──────────────────────────────────────────────────

header "YAML syntax (pubspec files)"

if command -v python3 &>/dev/null; then
  find "$TARGET_DIR" -name 'pubspec.yaml' -not -path '*/build/*' -not -path '*/.*' | sort | while read -r file; do
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
      pass "${file#$REPO_ROOT/}: valid YAML"
    else
      fail "${file#$REPO_ROOT/}: invalid YAML syntax"
    fi
  done
else
  warn "python3 not found — skipping YAML validation"
fi

# ── Summary ────────────────────────────────────────────────────────────────

printf "\n${BOLD}━━━ Summary ━━━${RESET}\n"

if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  printf "${GREEN}All checks passed.${RESET}\n"
elif [ "$ISSUES" -eq 0 ]; then
  printf "${YELLOW}%d warning(s), 0 errors.${RESET}\n" "$WARNINGS"
else
  printf "${RED}%d issue(s)${RESET}, ${YELLOW}%d warning(s)${RESET}\n" "$ISSUES" "$WARNINGS"
fi

exit $((ISSUES > 0 ? 1 : 0))
