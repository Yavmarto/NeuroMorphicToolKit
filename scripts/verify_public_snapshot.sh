#!/usr/bin/env bash
# CEL-459-B public-snapshot drift gate.
#
# Re-runs the checks in `scripts/publish_public_snapshot.sh --verify-only` on a
# checked-out public tree and fails when any forbidden pattern is present:
#   * an absolute macOS home path
#   * the employer mail domain
#   * a tracked "current tasks/" file
#   * dotenv content (any dotenv variant)
#   * ".nmtk/" content, including the deployment secrets file
#
# Usage:
#   scripts/verify_public_snapshot.sh [TARGET_DIR]   # default: current repo
#
# Run it on the public clone before pushing:
#   bash scripts/verify_public_snapshot.sh .
#
# Or install it as a pre-push hook in the public clone:
#   ln -sf ../../scripts/verify_public_snapshot.sh .git/hooks/pre-push
#
# Exit codes: 0 = clean, 1 = drift found, 2 = bad invocation.
set -uo pipefail

TARGET="${1:-.}"
if [[ ! -d "$TARGET/.git" ]]; then
  echo "error: $TARGET is not a git working tree" >&2
  exit 2
fi
cd "$TARGET"

# Build the forbidden literals without committing them.
USER_ROOT="$(printf '/%s/' Users)"
EMPLOYER_RE="$(printf 'response\\.%s' nl)"

fail=0
flag() { printf 'GATE FAIL: %s\n' "$*" >&2; fail=1; }

echo "== gate 1: forbidden paths in reachable history =="
history_paths="$(git log --all --pretty=format: --name-only --diff-filter=A 2>/dev/null | sort -u)"
for p in '.env' '.nmtk/deployment_secrets.json' 'nmtk/neuro_toolkit/deployment_state.json'; do
  if printf '%s\n' "$history_paths" | grep -qx "$p"; then
    flag "forbidden path in reachable history: $p"
  fi
done

echo "== gate 2: forbidden paths tracked at HEAD =="
tracked="$(git ls-files)"
if printf '%s\n' "$tracked" | grep -qE '(^|/)\.env(\..*)?$'; then
  flag ".env* tracked at HEAD"; printf '%s\n' "$tracked" | grep -E '(^|/)\.env(\..*)?$' >&2
fi
if printf '%s\n' "$tracked" | grep -qE '(^|/)\.nmtk/'; then
  flag ".nmtk/ content tracked at HEAD"; printf '%s\n' "$tracked" | grep -E '(^|/)\.nmtk/' >&2
fi
ct_count="$(git ls-files 'current tasks' | wc -l | tr -d ' ')"
if [[ "$ct_count" != "0" ]]; then
  flag "current tasks/ tracked at HEAD ($ct_count file(s))"
fi

echo "== gate 3: employer identity =="
meta_count="$(git log --all --format='%ae%n%ce' 2>/dev/null | grep -c "$EMPLOYER_RE" || true)"
if [[ "${meta_count:-0}" != "0" ]]; then
  flag "employer identity in commit metadata ($meta_count)"
fi
if git grep -lI -e "$EMPLOYER_RE" -- . 2>/dev/null; then
  flag "employer identity in tracked content"
fi

echo "== gate 4: absolute home paths in tracked content =="
if git grep -lI "$USER_ROOT" -- . \
  ":(exclude)scripts/verify_public_snapshot.sh" \
  ":(exclude)scripts/publish_public_snapshot.sh" 2>/dev/null; then
  flag "absolute home path in tracked content"
fi

echo "== gate 5: canonical publish_public_snapshot.sh --verify-only =="
if [[ -f scripts/publish_public_snapshot.sh ]]; then
  if ! bash scripts/publish_public_snapshot.sh . --verify-only; then
    flag "publish_public_snapshot.sh --verify-only reported drift"
  fi
else
  echo "note: scripts/publish_public_snapshot.sh not present; skipped canonical verifier"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "PUBLIC SNAPSHOT GATE FAILED" >&2
  exit 1
fi
echo "PUBLIC SNAPSHOT GATE OK"
exit 0
