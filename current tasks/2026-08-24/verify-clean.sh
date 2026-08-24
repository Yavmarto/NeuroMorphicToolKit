#!/usr/bin/env bash
# Pre-publication verification. Read-only — safe to run any time.
# Usage:  bash "current tasks/2026-08-24/verify-clean.sh"
cd "$(git rev-parse --show-toplevel)" || exit 1
REPOS=(. Neurobench Neurochip Neurohub Neurosense Neurosim neurocnl)
fail=0

echo "======================================================"
echo " 1. SECRET FILES IN HISTORY  (must be empty)"
echo "======================================================"
for r in "${REPOS[@]}"; do
  hits=$(git -C "$r" log --all --pretty=format: --name-only --diff-filter=A 2>/dev/null | sort -u \
    | grep -Ex '\.env|\.nmtk/deployment_secrets\.json' )
  if [ -n "$hits" ]; then echo "  FAIL $r:"; echo "$hits" | sed 's/^/        /'; fail=1
  else echo "  ok   $r"; fi
done

echo
echo "======================================================"
echo " 2. AUTHOR / COMMITTER ADDRESSES  (no response.nl)"
echo "======================================================"
for r in "${REPOS[@]}"; do
  n=$(git -C "$r" log --all --format='%ae%n%ce' 2>/dev/null | sort -u | grep -c 'response\.nl' || true)
  if [ "$n" -gt 0 ]; then
    echo "  FAIL $r: $n address(es) still on employer domain"
    git -C "$r" log --all --format='%ae%n%ce' | sort -u | grep 'response\.nl' | sed 's/^/        /'
    fail=1
  else echo "  ok   $r"; fi
done

echo
echo "======================================================"
echo " 3. DISTINCT IDENTITIES REMAINING (superproject)"
echo "======================================================"
git log --all --format='%aN <%aE>' | sort | uniq -c | sort -rn | head -15

echo
echo "======================================================"
echo " 4. TRACKED AT HEAD  (must be empty)"
echo "======================================================"
for r in "${REPOS[@]}"; do
  hits=$(git -C "$r" ls-files | grep -Ex '\.env|\.nmtk/deployment_secrets\.json' || true)
  [ -n "$hits" ] && { echo "  FAIL $r: $hits"; fail=1; } || echo "  ok   $r"
done

echo
echo "======================================================"
echo " 5. GITIGNORE COVERAGE"
echo "======================================================"
git check-ignore -v .env .nmtk/deployment_secrets.json 2>/dev/null || { echo "  FAIL: not ignored"; fail=1; }

echo
echo "======================================================"
echo " 6. PERSONAL / INTERNAL DIRECTORIES STILL TRACKED"
echo "======================================================"
for d in "current tasks" NMTK_SIDE logs recordings workspaces .impeccable paper; do
  n=$(git ls-files "$d" 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] && echo "  REVIEW  $d: $n tracked files" || echo "  ok      $d: none"
done

echo
[ "$fail" -eq 0 ] && echo "RESULT: all automated checks passed." \
                  || echo "RESULT: FAILURES ABOVE — do not publish yet."
exit $fail
