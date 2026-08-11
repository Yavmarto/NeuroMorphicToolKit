#!/usr/bin/env bash
# Shared helpers for developer orchestration scripts.

nmtk_compose_image_reference() {
  local python_bin="$1" service="$2"
  "$python_bin" -c '
import json
import sys

service_name = sys.argv[1]
config = json.load(sys.stdin)
services = config.get("services") or {}
service = services.get(service_name)
if not isinstance(service, dict):
    raise SystemExit(f"Compose service is missing: {service_name}")

image = str(service.get("image") or "").strip()
if not image:
    project = str(config.get("name") or "").strip()
    if not project:
        raise SystemExit("Compose project name is missing")
    image = f"{project}-{service_name}"
print(image)
' "$service"
}

nmtk_local_uncommitted_paths() {
  local repo_root="$1" root_changes submodule inner path
  root_changes="$({
    git -C "$repo_root" diff --name-only
    git -C "$repo_root" diff --name-only --cached
  } 2>/dev/null || true)"
  printf '%s\n' "$root_changes"

  # The parent repository reports a dirty submodule as only its directory
  # name. Expand the nested diff so module selection and runtime classification
  # can distinguish backend code from an excluded Flutter frontend.
  while IFS= read -r submodule; do
    [ -n "$submodule" ] || continue
    inner="$({
      git -C "$repo_root/$submodule" diff --name-only
      git -C "$repo_root/$submodule" diff --name-only --cached
    } 2>/dev/null || true)"
    [ -n "$inner" ] || continue
    while IFS= read -r path; do
      [ -n "$path" ] && printf '%s/%s\n' "$submodule" "$path"
    done <<< "$inner"
  done < <(
    git -C "$repo_root" submodule foreach --quiet --recursive \
      'printf "%s\n" "$sm_path"' 2>/dev/null || true
  )
}
