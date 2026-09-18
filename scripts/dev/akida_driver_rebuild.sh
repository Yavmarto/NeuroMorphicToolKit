#!/usr/bin/env bash
# Rebuilds the out-of-tree akida-pcie (akida_dw_edma) kernel module for the
# currently running kernel and registers it with DKMS, so the next kernel
# upgrade on this host rebuilds the module automatically instead of silently
# leaving the AKD1000 card unbound (see CEL-374).
#
# Usage (as root, on the rig itself):
#   sudo ./akida_driver_rebuild.sh --install-for <account>
#
# --install-for also grants <account> a scoped NOPASSWD sudo rule for the
# installed copy of this script only (mirrors app_managed_update.sh), so a
# future kernel bump can be repaired without an interactive root session:
#   sudo /usr/local/libexec/nmtk-akida-driver-rebuild

set -euo pipefail

HELPER_VERSION="1"
HELPER_SOURCE="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
TESTING="${NMTK_AKIDA_REBUILD_TESTING:-0}"
if [ "$TESTING" = "1" ]; then
  INSTALLED_HELPER="${NMTK_AKIDA_REBUILD_INSTALLED_HELPER:-/usr/local/libexec/nmtk-akida-driver-rebuild}"
  SUDOERS_FILE="${NMTK_AKIDA_REBUILD_SUDOERS_FILE:-/etc/sudoers.d/nmtk-akida-driver-rebuild}"
else
  INSTALLED_HELPER="/usr/local/libexec/nmtk-akida-driver-rebuild"
  SUDOERS_FILE="/etc/sudoers.d/nmtk-akida-driver-rebuild"
fi
default_src_dir() {
  local home=""
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    home="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
  fi
  [ -n "$home" ] || home="$HOME"
  printf '%s\n' "$home/akida_dw_edma"
}
SRC_DIR="${NMTK_AKIDA_SRC_DIR:-$(default_src_dir)}"
DKMS_NAME="akida-dw-edma"
DKMS_VERSION="1.0"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if [ "${1:-}" = "--version" ]; then
  printf 'nmtk-akida-driver-rebuild %s\n' "$HELPER_VERSION"
  exit 0
fi

if [ "$TESTING" != "1" ] && [ "$(id -u)" -ne 0 ]; then
  fail "driver rebuild requires administrator access"
fi

install_passwordless_helper() {
  local caller="$1" sudoers_dir sudoers_tmp
  case "$caller" in
    *[!a-zA-Z0-9_.-]*|'') fail "invalid account name: $caller" ;;
  esac
  if [ "$TESTING" != "1" ] && ! id "$caller" >/dev/null 2>&1; then
    fail "account $caller does not exist"
  fi
  case "$INSTALLED_HELPER" in
    /*) ;;
    *) fail "the installed helper path must be absolute" ;;
  esac

  install -d -m 0755 "$(dirname "$INSTALLED_HELPER")"
  install -m 0755 "$HELPER_SOURCE" "$INSTALLED_HELPER"

  sudoers_dir="$(dirname "$SUDOERS_FILE")"
  install -d -m 0755 "$sudoers_dir"
  sudoers_tmp="$(mktemp "$sudoers_dir/.nmtk-akida-driver-rebuild.XXXXXX")"
  printf '%s ALL=(root) NOPASSWD: %s\n' "$caller" "$INSTALLED_HELPER" >"$sudoers_tmp"
  chmod 0440 "$sudoers_tmp"
  if [ "$TESTING" != "1" ]; then
    visudo -cf "$sudoers_tmp" >/dev/null || {
      rm -f -- "$sudoers_tmp"
      fail "could not validate the scoped driver-rebuild permission"
    }
  fi
  install -m 0440 "$sudoers_tmp" "$SUDOERS_FILE"
  rm -f -- "$sudoers_tmp"
  printf '==> Future kernel bumps can be repaired via: sudo %s\n' "$INSTALLED_HELPER"
}

if [ "${1:-}" = "--install-for" ]; then
  [ "$#" -ge 2 ] || fail "--install-for needs an account name"
  install_passwordless_helper "$2"
  shift 2
fi

[ -d "$SRC_DIR" ] || fail "driver source not found at $SRC_DIR (set NMTK_AKIDA_SRC_DIR)"

KVER="$(uname -r)"
printf '==> Preparing build tooling for kernel %s\n' "$KVER"
apt-get update -qq
apt-get install -y -qq build-essential dkms "linux-headers-$KVER"

if [ ! -f "$SRC_DIR/dkms.conf" ]; then
  cat >"$SRC_DIR/dkms.conf" <<EOF
PACKAGE_NAME="$DKMS_NAME"
PACKAGE_VERSION="$DKMS_VERSION"
BUILT_MODULE_NAME[0]="akida-pcie"
DEST_MODULE_LOCATION[0]="/kernel/drivers"
AUTOINSTALL="yes"
EOF
fi

DKMS_TREE_DIR="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"
if [ ! -d "$DKMS_TREE_DIR" ]; then
  mkdir -p "$DKMS_TREE_DIR"
  rsync -a --exclude='.git' "$SRC_DIR"/ "$DKMS_TREE_DIR"/
fi

if [ -z "$(dkms status "$DKMS_NAME/$DKMS_VERSION" 2>/dev/null)" ]; then
  dkms add -m "$DKMS_NAME" -v "$DKMS_VERSION"
fi
dkms build -m "$DKMS_NAME" -v "$DKMS_VERSION" -k "$KVER" --force
dkms install -m "$DKMS_NAME" -v "$DKMS_VERSION" -k "$KVER" --force

depmod -a "$KVER"
modprobe akida-pcie

if [ -f "$SRC_DIR/99-akida-pcie.rules" ]; then
  install -m 0644 "$SRC_DIR/99-akida-pcie.rules" /etc/udev/rules.d/99-akida-pcie.rules
  udevadm control --reload-rules
  udevadm trigger
fi

grep -q '^akida_pcie' /etc/modules 2>/dev/null || echo akida_pcie >>/etc/modules

grep -q '^akida_pcie' <(lsmod) || fail "akida-pcie failed to load for kernel $KVER"
printf '==> akida-pcie bound for kernel %s. DKMS will rebuild it on future kernel updates.\n' "$KVER"
