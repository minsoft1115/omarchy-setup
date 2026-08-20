#!/usr/bin/env bash
#
# install-lazygit.sh — install this repo's lazygit config
# ==============================================================================
# Usage:
#   ./scripts/install-lazygit.sh status     Show current state (default)
#   ./scripts/install-lazygit.sh install    Copy the config into place
#   ./scripts/install-lazygit.sh remove     Take it back out (see below)
#   ./scripts/install-lazygit.sh diff       source vs installed
#   ./scripts/install-lazygit.sh --help     This help
#
# Options:
#   --skip-packages   Do not touch packages, only install the file
#
# Every action is idempotent: re-running is safe, and anything already done is
# reported as "skipped".
#
# Layout:
#   source (edit here)  ./lazygit/config.yml
#   installed copy      ~/.config/lazygit/config.yml
#
# Unlike the other configs in this repo this is not a fragment in our own
# namespace: lazygit reads one config path and has no include mechanism, so the
# whole file is copied. That is safe on Omarchy because the target is a file
# Omarchy ships EMPTY — there is nothing of anyone else's to merge with, only
# to back up. (An LG_CONFIG_FILE merge was considered and rejected: an
# environment variable exported from bashrc only reaches a lazygit started
# from an interactive shell, not one started from a keybinding.)
#
# lazygit rewrites this file itself when it finds a key an update has renamed
# (measured on 0.64: git.pagers -> git.diffRenderers, pager -> command). The
# installed copy then drifts from the source through no edit of anyone's and
# the state reads "outdated". The right move is to accept the rename INTO the
# repo file — `diff` shows it — not to reinstall the old key and ping-pong.
#
# Removing: the target belongs to Omarchy (it ships it empty), so remove does
# not delete the file. An installed copy that still matches the source is
# backed up and emptied — the pre-install state. One that differs was edited
# by hand or migrated by lazygit, and deciding for it is not this script's
# call: it is left alone with a pointer at the backups.
#
# Dependencies: lazygit itself, and git-delta — the config renders diffs
# through delta. They go in with "omarchy pkg add", a no-op for packages
# already present; no omarchy on the box is a warning, not an error.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Settings — pre-set any of these in the environment to override
# ==============================================================================
: "${TS:=$(date +%s)}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
# The source lives in the repo root; this script sits in scripts/.
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"

SRC="${LAZYGIT_SRC:-$REPO_DIR/lazygit/config.yml}"
DST_DIR="${LAZYGIT_DST_DIR:-$HOME/.config/lazygit}"
DST="$DST_DIR/config.yml"

# Arch package names, space separated. Presence is asked about by package name,
# never with command -v — git-delta installs `delta`.
PACKAGES="${LAZYGIT_PACKAGES:-lazygit git-delta}"
SKIP_PACKAGES=0

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

backup() { [ -f "$1" ] || return 0; cp -a "$1" "$1.bak.$TS"; log "backed up: $1.bak.$TS"; }

# Reuse the header comment block (from line 3 to the first non-comment line).
usage() { awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

# ==============================================================================
# Helpers
# ==============================================================================
in_sync() { cmp -s "$SRC" "$DST"; }

# Per-package present/missing, for status. One package at a time because
# "omarchy pkg missing" answers for a whole list with a single yes or no.
packages_status() {
  command -v omarchy >/dev/null 2>&1 || { echo "unknown (no omarchy)"; return 0; }
  local out="" pkg state
  for pkg in $PACKAGES; do
    omarchy pkg missing "$pkg" >/dev/null 2>&1 && state=MISSING || state=ok
    out="$out $pkg($state)"
  done
  printf '%s' "${out# }"
}

install_packages() {
  if [ "$SKIP_PACKAGES" = 1 ]; then
    log "packages: skipped (--skip-packages)"
    return 0
  fi
  if ! command -v omarchy >/dev/null 2>&1; then
    warn "omarchy not found — install these yourself: $PACKAGES"
    return 0
  fi
  # shellcheck disable=SC2086
  if omarchy pkg missing $PACKAGES; then
    log "packages: installing $PACKAGES"
    # shellcheck disable=SC2086
    omarchy pkg add $PACKAGES || warn "package install failed — continuing"
  else
    log "packages: $PACKAGES already installed — skipped"
  fi
}

# ==============================================================================
# Actions
# ==============================================================================
do_install() {
  [ -f "$SRC" ] || die "source missing: $SRC (run from a clone of the repo)"
  install_packages
  if in_sync; then
    log "installed copy already current — skipped"
  else
    mkdir -p "$DST_DIR"
    backup "$DST"
    cp -a "$SRC" "$DST"
    log "installed: $SRC -> $DST"
  fi
  log "done. lazygit reads it on its next start."
}

do_remove() {
  if [ ! -f "$DST" ]; then
    log "nothing at $DST — skipped"
  elif [ ! -s "$DST" ]; then
    log "$DST is already empty (the pre-install state) — skipped"
  elif in_sync; then
    # Ours, unchanged: back it up and put back what Omarchy ships — an empty
    # file. Restoring the newest backup instead would be wrong after a second
    # install: that backup is just our previous version.
    backup "$DST"
    : >"$DST"
    log "emptied $DST — that is what Omarchy ships"
  else
    # Edited by hand or migrated by lazygit. Same rule as the Korean step's
    # fcitx config: a file someone changed is not ours to decide about.
    warn "installed copy differs from the source (hand-edited, or migrated by lazygit) — left alone"
    ls -1t "$DST".bak.* 2>/dev/null | head -1 | sed 's/^/      newest backup: /' || true
  fi
  log "done. packages are left alone."
}

do_diff() {
  [ -f "$SRC" ] || die "source missing: $SRC"
  if [ ! -f "$DST" ]; then
    echo "--- not installed ($DST)"
  elif in_sync; then
    log "installed copy matches the source"
  else
    diff -u "$DST" "$SRC" || true
  fi
}

do_status() {
  echo "source (edit here) : $SRC ($([ -f "$SRC" ] && echo present || echo missing))"
  echo "installed copy     : $DST ($([ -s "$DST" ] && echo present || echo "missing or empty"))"
  echo "in sync with source: $(in_sync && echo yes || echo no)"
  echo "dependencies       : $(packages_status)"
}

# ==============================================================================
# Entry point
# ==============================================================================
ACTION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-packages) SKIP_PACKAGES=1 ;;
    --help|-h|help) usage; exit 0 ;;
    -*)             echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    *)              [ -z "$ACTION" ] || { echo "only one action allowed: $ACTION, $1" >&2; exit 2; }
                    ACTION="$1" ;;
  esac
  shift
done

case "${ACTION:-status}" in
  install|setup|apply|sync) do_install ;;
  remove|uninstall)         do_remove ;;
  diff)                     do_diff ;;
  status)                   do_status ;;
  *) echo "unknown action: $ACTION (see --help)" >&2; exit 2 ;;
esac
