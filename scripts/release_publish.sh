#!/usr/bin/env bash
# release_publish.sh — cut a version, push it, watch CI, verify the result.
#
# Usage: scripts/release_publish.sh VERSION [OPTIONS]
#   VERSION          semver, no leading v (e.g. 1.2.0 or 1.2.0-beta.1)
#   --skip-tests     skip `make ci` (the tag still triggers real CI)
#   --yes            don't ask before pushing
#   --no-watch       push, then exit without waiting on CI
#   --dry-run        run every check and print the plan; no git writes, no push
#   -h | --help
#
# Env: RELEASE_BRANCH (default dev), REMOTE (default origin)
#
# Wraps scripts/release.sh — which does the version bumps, changelogs, commits
# and tags — with the guards it lacks. In particular release.sh runs
# `git add -A` in every submodule, so this refuses to start on a dirty tree:
# otherwise unrelated work in progress silently becomes part of the release.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/dev/lib.sh
source "$REPO_ROOT/scripts/dev/lib.sh"   # also sets -euo pipefail

RELEASE_BRANCH="${RELEASE_BRANCH:-dev}"
REMOTE="${REMOTE:-origin}"
GHCR_BASE="ghcr.io/yavmarto/neuromorphictoolkit"
WORKFLOWS=("Release Docker Images" "Release Desktop Apps")

VERSION=""
SKIP_TESTS=false
ASSUME_YES=false
NO_WATCH=false
DRY_RUN=false

PYTHON3="$(find_python3)" || { echo "error: no python3 found" >&2; exit 1; }

log()   { printf '==> %s\n' "$*"; }
warn()  { printf '==> WARNING: %s\n' "$*" >&2; }
die()   { printf '\nerror: %s\n' "$*" >&2; exit 1; }
phase() { printf '\n─── %s %s\n' "$*" "$(printf '─%.0s' $(seq 1 $((60 - ${#1}))))"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-tests) SKIP_TESTS=true ;;
    --yes|-y)     ASSUME_YES=true ;;
    --no-watch)   NO_WATCH=true ;;
    --dry-run)    DRY_RUN=true ;;
    -h|--help)    sed -n '2,18p' "$0"; exit 0 ;;
    -*)           die "unknown option: $1 (see --help)" ;;
    *)            [ -z "$VERSION" ] || die "VERSION given twice: '$VERSION' and '$1'"
                  VERSION="$1" ;;
  esac
  shift
done

[ -n "$VERSION" ] || die "VERSION is required. Example: $0 1.2.0"

submodule_paths() {
  git -C "$REPO_ROOT" config -f .gitmodules --get-regexp path | awk '{print $2}'
}

# ---------------------------------------------------------------------------
phase_1_guards() {
  phase "1/8 Safety checks"

  # Semver, checked here as well as in release.sh so we fail before any work.
  if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    die "'$VERSION' is not semver (x.y.z or x.y.z-suffix). Do not include a leading 'v'."
  fi
  log "Version $VERSION → tag v$VERSION"

  command -v gh >/dev/null 2>&1 || die "the gh CLI is required (brew install gh)"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run: gh auth login"
  log "gh authenticated"

  # Dirty-tree check. release.sh does `git add -A` per submodule, so anything
  # uncommitted — including untracked files — would be swept into the release
  # commit. Blocking is the point, not an inconvenience.
  local dirty=() repo status
  for repo in "." $(submodule_paths); do
    status="$(git -C "$REPO_ROOT/$repo" status --porcelain)"
    [ -n "$status" ] && dirty+=("$repo")
  done
  if [ ${#dirty[@]} -gt 0 ]; then
    printf '\nerror: uncommitted changes in: %s\n' "${dirty[*]}" >&2
    printf 'release.sh runs "git add -A" in each repo, so this would become part\n' >&2
    printf 'of the release commit. Commit, stash, or gitignore it first.\n\n' >&2
    for repo in "${dirty[@]}"; do
      printf '  --- %s ---\n' "$repo" >&2
      git -C "$REPO_ROOT/$repo" status --short | sed 's/^/  /' >&2
    done
    exit 1
  fi
  log "Working trees clean (root + $(submodule_paths | wc -l | tr -d ' ') submodules)"

  # Branch check.
  local wrong=() branch
  for repo in "." $(submodule_paths); do
    branch="$(git -C "$REPO_ROOT/$repo" rev-parse --abbrev-ref HEAD)"
    [ "$branch" = "$RELEASE_BRANCH" ] || wrong+=("$repo (on $branch)")
  done
  [ ${#wrong[@]} -eq 0 ] \
    || die "not on '$RELEASE_BRANCH': ${wrong[*]}. Set RELEASE_BRANCH= to override."
  log "All repos on '$RELEASE_BRANCH'"

  # Tag must not already exist, locally or on any remote.
  local existing=()
  for repo in "." $(submodule_paths); do
    if git -C "$REPO_ROOT/$repo" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
      existing+=("$repo (local)")
    fi
    if [ -n "$(git -C "$REPO_ROOT/$repo" ls-remote --tags "$REMOTE" "refs/tags/v$VERSION" 2>/dev/null)" ]; then
      existing+=("$repo ($REMOTE)")
    fi
  done
  [ ${#existing[@]} -eq 0 ] \
    || die "tag v$VERSION already exists in: ${existing[*]}. Pick a new version."
  log "Tag v$VERSION is free everywhere"
}

# ---------------------------------------------------------------------------
phase_2_preflight() {
  phase "2/8 Pre-flight gates"
  cd "$REPO_ROOT" || die "cannot cd to $REPO_ROOT"

  # The app ships hash-pinned copies of the compose files. Nothing in CI checks
  # this (only scripts/run_launcher_guardrails.sh does), so a stale bundle would
  # ship silently — hard fail.
  if ! "$PYTHON3" scripts/sync_flutter_deployment_assets.py --check; then
    die "Flutter deployment bundle is stale. Run:
    python3 scripts/sync_flutter_deployment_assets.py
  then commit the result and rerun."
  fi

  log "Checking third-party notices..."
  make notices-check || die "THIRD_PARTY_NOTICES.md is stale — run 'make notices' and commit."

  if $SKIP_TESTS; then
    warn "skipping local tests (--skip-tests); CI will still run on the tag"
  else
    log "Running the full local CI suite (skip with --skip-tests)..."
    make ci || die "local CI failed — nothing was tagged."
  fi
}

# ---------------------------------------------------------------------------
phase_3_cut() {
  phase "3/8 Bump, changelog, commit, tag"
  if $DRY_RUN; then
    log "would run: scripts/release.sh $VERSION"
    log "  (bumps every submodule + core pubspecs, regenerates changelogs,"
    log "   commits 'chore(release): $VERSION', tags v$VERSION in each repo)"
    return 0
  fi
  bash "$REPO_ROOT/scripts/release.sh" "$VERSION"
}

# ---------------------------------------------------------------------------
phase_4_confirm() {
  phase "4/8 Review what will be published"

  local repo
  for repo in $(submodule_paths) "."; do
    local name="$repo"
    [ "$repo" = "." ] && name="(root)"
    if git -C "$REPO_ROOT/$repo" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null 2>&1; then
      printf '  %-22s %s  tag v%s\n' "$name" \
        "$(git -C "$REPO_ROOT/$repo" rev-parse --short HEAD)" "$VERSION"
    else
      printf '  %-22s %s  (no tag — unchanged this release)\n' "$name" \
        "$(git -C "$REPO_ROOT/$repo" rev-parse --short HEAD)"
    fi
  done

  cat <<EOF

Pushing this will:
  • push commits + tags to $REMOTE/$RELEASE_BRANCH (submodules first, then root)
  • trigger "Release Docker Images" → 14 images to $GHCR_BASE
    tagged latest, $VERSION, and sha, each stamped NMTK_VERSION=$VERSION
  • trigger "Release Desktop Apps" → a PUBLIC GitHub Release with installers

This is not easily reversible.
EOF

  if $DRY_RUN; then
    log "DRY RUN — stopping before push."
    return 1
  fi
  if $ASSUME_YES; then
    log "Proceeding without confirmation (--yes)"
    return 0
  fi
  printf '\nPush and publish v%s? [y/N] ' "$VERSION"
  local reply=""
  read -r reply || true
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) die "aborted. Local commits and tags remain — delete them with:
    git tag -d v$VERSION   (and in each submodule)
    git reset --hard HEAD~1" ;;
  esac
}

# ---------------------------------------------------------------------------
phase_5_push() {
  phase "5/8 Push"
  # Submodules first: the root commit records their SHAs, so pushing root first
  # would publish a pointer to objects the remote does not have yet.
  log "Pushing submodules..."
  git -C "$REPO_ROOT" submodule foreach \
    "git push $REMOTE HEAD:$RELEASE_BRANCH --follow-tags"
  log "Pushing root..."
  git -C "$REPO_ROOT" push "$REMOTE" "HEAD:$RELEASE_BRANCH" --follow-tags
  log "Pushed."
}

# ---------------------------------------------------------------------------
# Find the run a tag push triggered. headBranch is the tag name for tag pushes.
find_run_id() {
  local workflow="$1" deadline=$((SECONDS + 120))
  while [ $SECONDS -lt $deadline ]; do
    local id
    id="$(gh run list --workflow "$workflow" --limit 30 \
            --json databaseId,headBranch \
            --jq "[.[] | select(.headBranch==\"v$VERSION\")] | first | .databaseId" \
          2>/dev/null || true)"
    if [ -n "$id" ] && [ "$id" != "null" ]; then
      printf '%s\n' "$id"
      return 0
    fi
    sleep 5
  done
  return 1
}

phase_6_watch() {
  phase "6/8 Watch CI"
  if $NO_WATCH; then
    log "Skipping (--no-watch). Follow along with: gh run list"
    return 0
  fi

  local workflow id
  for workflow in "${WORKFLOWS[@]}"; do
    log "Locating '$workflow' for v$VERSION..."
    if ! id="$(find_run_id "$workflow")"; then
      warn "no run found for '$workflow' within 120s — check 'gh run list' manually"
      continue
    fi
    log "  run $id — watching"
    if gh run watch "$id" --exit-status; then
      log "  '$workflow' succeeded"
    else
      warn "'$workflow' did not succeed. Logs: gh run view $id --log-failed"
      FAILED_WORKFLOWS+=("$workflow")
    fi
  done
}

# ---------------------------------------------------------------------------
phase_7_verify() {
  phase "7/8 Verify"

  if gh release view "v$VERSION" >/dev/null 2>&1; then
    log "GitHub Release v$VERSION exists (this is what the app reads to detect updates)"
  else
    warn "no GitHub Release for v$VERSION yet — 'Release Desktop Apps' creates it."
    warn "  Until it lands the app falls back to the raw tag; see the race note below."
  fi

  if docker info >/dev/null 2>&1; then
    log "Checking the version stamp on the published image..."
    if docker manifest inspect "$GHCR_BASE/suite-api:$VERSION" >/dev/null 2>&1; then
      log "  $GHCR_BASE/suite-api:$VERSION is published"
    else
      warn "  $GHCR_BASE/suite-api:$VERSION not found in GHCR"
    fi
  else
    log "Docker daemon not reachable — skipping the GHCR image check."
    log "  Verify by hand with:"
    log "    docker run --rm $GHCR_BASE/suite-api:$VERSION printenv NMTK_VERSION"
  fi
}

# ---------------------------------------------------------------------------
phase_8_report() {
  phase "8/8 Done"
  if [ ${#FAILED_WORKFLOWS[@]} -gt 0 ]; then
    warn "these workflows did not succeed: ${FAILED_WORKFLOWS[*]}"
    warn "Do NOT announce this release until they are green — end users would"
    warn "pull a :latest that was never rebuilt."
    return 1
  fi
  cat <<EOF
Release v$VERSION is published.

  End users: the app's Backend Setup screen now shows
  "Backend update available — $VERSION". One tap updates in place.

A note on timing: UpdateService reads /releases but falls back to /tags, and the
tag existed the moment it was pushed. So the in-app badge can appear before the
images finish building. It does not break anything — the app deploys :latest, so
an early tap installs the PREVIOUS release, reports success, and leaves the badge
showing. Both workflows are green now, so it is safe to announce.
EOF
}

# ---------------------------------------------------------------------------
FAILED_WORKFLOWS=()

phase_1_guards
phase_2_preflight
phase_3_cut
if ! phase_4_confirm; then
  # Only reachable on --dry-run; a real abort exits inside phase_4_confirm.
  log "Dry run complete — no commits, tags, or pushes were made."
  exit 0
fi
phase_5_push
phase_6_watch
phase_7_verify
phase_8_report
