#!/usr/bin/env bash
# CEL-343: rotate deployment secrets (C-2) and scripts/.env Mission Control key (M-4).
# C-1 Grafana and Jules keys waived per board (2026-09-17) — not in use.
# ponytail: one script; upgrade path is per-host targets if deploy topology splits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_HOST="${REMOTE_HOST:-moosebun2@192.168.2.90}"
DEPLOY_DIR="${DEPLOY_DIR:-~/nmtk-deploy}"
SSH_OPTS="${SSH_OPTS:--o ConnectTimeout=12 -o BatchMode=yes}"
LOCAL_ONLY=0
SKIP_REMOTE=0

usage() {
  cat <<'EOF'
Usage: scripts/rotate_leaked_credentials.sh [--local-only] [--skip-remote]

Rotates credentials flagged in CEL-329 / CEL-343 before public publish:
  C-2  .nmtk/deployment_secrets.json on REMOTE_HOST (regenerates values, keeps refs)
  M-4  scripts/.env MISSION_CONTROL_API_KEY on this machine

Waived (board 2026-09-17): C-1 Grafana admin password, Jules API keys.

Environment:
  REMOTE_HOST                    default moosebun2@192.168.2.90
  DEPLOY_DIR                     default ~/nmtk-deploy
  NEW_MISSION_CONTROL_API_KEY    optional; auto-generated when unset

Examples:
  scripts/rotate_leaked_credentials.sh --local-only
  REMOTE_HOST=moosebun2@192.168.2.90 scripts/rotate_leaked_credentials.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only) LOCAL_ONLY=1; shift ;;
    --skip-remote) SKIP_REMOTE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

rand_mc_key() { printf 'mc_%s' "$(openssl rand -hex 24)"; }

update_env_kv() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
out: list[str] = []
seen = False
for line in lines:
    if not line or line.lstrip().startswith("#") or "=" not in line:
        out.append(line)
        continue
    k, _ = line.split("=", 1)
    if k.strip() == key:
        out.append(f'{key}="{value}"')
        seen = True
    else:
        out.append(line)
if not seen:
    out.append(f'{key}="{value}"')
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

rotate_scripts_env() {
  local env_file="$ROOT/scripts/.env"
  if [[ ! -f "$env_file" ]]; then
    echo "M-4: scripts/.env not present — skip"
    return 0
  fi
  local backup="${env_file}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp "$env_file" "$backup"
  echo "M-4: rotating scripts/.env (Jules keys removed per board waiver)"

  local new_mc="${NEW_MISSION_CONTROL_API_KEY:-$(rand_mc_key)}"
  update_env_kv "$env_file" "MISSION_CONTROL_API_KEY" "$new_mc"
  echo "M-4: rotated MISSION_CONTROL_API_KEY"

  chmod 600 "$env_file" 2>/dev/null || true
  rm -f "$backup"
  echo "M-4: removed transient backup (old secrets not kept on disk)"
}

ssh_ok() {
  ssh $SSH_OPTS "$REMOTE_HOST" 'echo ok' >/dev/null 2>&1
}

rotate_remote_deployment_secrets() {
  echo "C-2: regenerating deployment_secrets.json on $REMOTE_HOST"
  ssh $SSH_OPTS "$REMOTE_HOST" "bash -s" -- "$DEPLOY_DIR" <<'REMOTE'
set -euo pipefail
deploy_dir="$1"
candidates=(
  "${deploy_dir}/.nmtk/deployment_secrets.json"
  "${HOME}/.nmtk/deployment_secrets.json"
)
target=""
for path in "${candidates[@]}"; do
  if [[ -f "$path" ]]; then
    target="$path"
    break
  fi
done
if [[ -z "$target" ]]; then
  echo "C-2: no deployment_secrets.json found on host — skip (may be fresh install)"
  exit 0
fi
python3 - "$target" <<'PY'
import json
import secrets
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(data, dict) or not data:
    raise SystemExit("C-2: deployment_secrets.json is empty or invalid")
rotated = {ref: secrets.token_urlsafe(24) for ref in data}
path.write_text(json.dumps(rotated, indent=2, sort_keys=True) + "\n", encoding="utf-8")
path.chmod(0o600)
print(f"C-2: rotated {len(rotated)} secret ref(s) in {path}")
PY
REMOTE
}

verify_local() {
  local env_file="$ROOT/scripts/.env"
  [[ -f "$env_file" ]] || return 0
  python3 - "$env_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
keys = {}
for line in path.read_text(encoding="utf-8").splitlines():
    if not line or line.lstrip().startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    keys[k.strip()] = v.strip().strip('"')
for retired in ("JULES_API_KEY", "JULES_API_KEY_F"):
    if retired in keys and keys[retired]:
        raise SystemExit(f"M-4 verify failed: {retired} should be removed")
required = ["MISSION_CONTROL_API_KEY"]
missing = [k for k in required if not keys.get(k)]
if missing:
    raise SystemExit(f"M-4 verify failed: missing {missing}")
if not keys["MISSION_CONTROL_API_KEY"].startswith("mc_"):
    raise SystemExit("M-4 verify failed: MISSION_CONTROL_API_KEY format")
print("M-4 verify: OK (Jules keys absent)")
PY
}

verify_remote() {
  ssh $SSH_OPTS "$REMOTE_HOST" "bash -s" -- "$DEPLOY_DIR" <<'REMOTE'
set -euo pipefail
deploy_dir="$1"
found=0
for path in "${deploy_dir}/.nmtk/deployment_secrets.json" "${HOME}/.nmtk/deployment_secrets.json"; do
  if [[ -f "$path" ]]; then
    count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$path")
    echo "C-2 verify: $path has $count ref(s)"
    found=1
  fi
done
if [[ "$found" == "0" ]]; then
  echo "C-2 verify: no deployment_secrets.json on host (nothing to rotate)"
fi
echo "C-2 verify: OK"
REMOTE
}

main() {
  rotate_scripts_env
  verify_local

  if [[ "$LOCAL_ONLY" == "1" || "$SKIP_REMOTE" == "1" ]]; then
    echo "Remote rotation skipped (--local-only or --skip-remote)"
    return 0
  fi

  if ! ssh_ok; then
    echo "error: cannot SSH to $REMOTE_HOST (needs dev LAN / VPN)" >&2
    exit 2
  fi

  rotate_remote_deployment_secrets
  verify_remote
  echo "CEL-343 rotation complete (no secret values logged)"
}

main "$@"
