#!/usr/bin/env bash
#
# install-ccstatusline.sh — Claude Code status line with usage gauges
# ==============================================================================
# Usage:
#   ./scripts/install-ccstatusline.sh status     Show current state (default)
#   ./scripts/install-ccstatusline.sh install    Install and register everything
#   ./scripts/install-ccstatusline.sh remove     Take it back out (see below)
#   ./scripts/install-ccstatusline.sh diff       source vs installed config
#   ./scripts/install-ccstatusline.sh --help     This help
#
# Options:
#   --keep-package    On remove, leave the npm package installed
#
# Every action is idempotent: re-running is safe, and anything already done is
# reported as "skipped".
#
# What install does, in order:
#   1. npm install -g ccstatusline (skipped when the binary already resolves),
#      then `mise reshim` so the shim appears on machines where node is
#      mise-managed — which is every stock Omarchy box
#   2. copies the widget config into place
#   3. registers the binary as Claude Code's statusLine command in
#      ~/.claude/settings.json (merged with jq — the rest of the file is kept)
#
# Layout:
#   source (edit here)  ./ccstatusline/settings.json
#   installed copy      ~/.config/ccstatusline/settings.json
#   registration        ~/.claude/settings.json  (.statusLine key only)
#
# The config draws two lines: model / git branch / context gauge on the first,
# session gauge / 5h-reset countdown / weekly gauge / weekly-reset countdown on
# the second. ccstatusline re-reads it on every refresh, so config edits apply
# live; the settings.json registration is only read when a Claude Code session
# starts.
#
# ccstatusline rewrites the installed copy itself: opening its TUI normalizes
# the file and update notices add transient keys. The copy then drifts from the
# source through no edit of anyone's and the state reads "outdated". `diff`
# shows what changed — accept wanted changes INTO the repo file rather than
# reinstalling over them and ping-ponging.
#
# Removing: the statusLine entry is deleted only when it points at
# ccstatusline — someone else's status line command is not ours to remove. The
# installed config is backed up and deleted when it still matches the source
# (the pre-install state is "no file"); one that differs was tuned by hand or
# through the TUI, and is left alone with a pointer at the backups. The npm
# package serves nothing but this status line, so remove uninstalls it too —
# --keep-package leaves it.
#
# Dependencies: node/npm (Omarchy manages node through mise) and jq (ships
# with Omarchy). Both are required, not installed: a box without node is not
# going to run a node status line well anyway.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Settings — pre-set any of these in the environment to override
# ==============================================================================
: "${TS:=$(date +%s)}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
# The source lives in the repo root; this script sits in scripts/.
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"

SRC="${CCSTATUSLINE_SRC:-$REPO_DIR/ccstatusline/settings.json}"
DST_DIR="${CCSTATUSLINE_DST_DIR:-$HOME/.config/ccstatusline}"
DST="$DST_DIR/settings.json"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

NPM_PKG=ccstatusline
MISE_SHIM="$HOME/.local/share/mise/shims/ccstatusline"
KEEP_PACKAGE=0

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

# The mise shim first: it survives node version switches, where the versioned
# install path underneath it does not.
resolve_bin() {
  if [ -x "$MISE_SHIM" ]; then echo "$MISE_SHIM"; return 0; fi
  command -v "$NPM_PKG" 2>/dev/null
}

# What ~/.claude/settings.json currently points its statusLine at, if anything.
registered_cmd() {
  [ -f "$CLAUDE_SETTINGS" ] || return 0
  jq -r '.statusLine.command // empty' "$CLAUDE_SETTINGS" 2>/dev/null
}

reshim() { command -v mise >/dev/null 2>&1 && mise reshim >/dev/null 2>&1 || true; }

# ==============================================================================
# Actions
# ==============================================================================
do_install() {
  [ -f "$SRC" ] || die "source missing: $SRC (run from a clone of the repo)"
  command -v jq >/dev/null 2>&1 || die "jq is required to edit $CLAUDE_SETTINGS"

  # 1. the binary
  local bin
  bin="$(resolve_bin || true)"
  if [ -n "$bin" ]; then
    log "package: $NPM_PKG already installed ($bin) — skipped"
  else
    command -v npm >/dev/null 2>&1 || die "npm not found — install node first (Omarchy: mise use -g node@lts)"
    log "package: npm install -g $NPM_PKG"
    npm install -g "$NPM_PKG" || die "npm install failed"
    reshim
    bin="$(resolve_bin || true)"
    [ -n "$bin" ] || die "installed, but no ccstatusline on PATH or in $MISE_SHIM"
  fi

  # 2. the widget config
  if in_sync; then
    log "installed config already current — skipped"
  else
    mkdir -p "$DST_DIR"
    backup "$DST"
    cp -a "$SRC" "$DST"
    log "installed: $SRC -> $DST"
  fi

  # 3. the Claude Code registration
  local current
  current="$(registered_cmd)"
  if [ "$current" = "$bin" ]; then
    log "statusLine already registered — skipped"
  else
    case "$current" in
      "")               ;;
      *ccstatusline*)   log "statusLine points at another ccstatusline path — repointing to $bin" ;;
      *)                warn "replacing an existing statusLine command: $current (kept in the backup)" ;;
    esac
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    [ -f "$CLAUDE_SETTINGS" ] || printf '{}\n' >"$CLAUDE_SETTINGS"
    backup "$CLAUDE_SETTINGS"
    local tmp
    tmp="$(mktemp "$CLAUDE_SETTINGS.XXXXXX")"
    jq --arg cmd "$bin" '.statusLine = {type: "command", command: $cmd}' \
      "$CLAUDE_SETTINGS" >"$tmp" || { rm -f "$tmp"; die "jq failed to edit $CLAUDE_SETTINGS"; }
    mv "$tmp" "$CLAUDE_SETTINGS"
    log "registered statusLine in $CLAUDE_SETTINGS"
  fi

  log "done. new Claude Code sessions show it; ones already open need a restart."
}

do_remove() {
  command -v jq >/dev/null 2>&1 || die "jq is required to edit $CLAUDE_SETTINGS"

  # Registration first: with it gone the binary and config are inert.
  local current
  current="$(registered_cmd)"
  case "$current" in
    "")
      log "no statusLine registered — skipped" ;;
    *ccstatusline*)
      backup "$CLAUDE_SETTINGS"
      local tmp
      tmp="$(mktemp "$CLAUDE_SETTINGS.XXXXXX")"
      jq 'del(.statusLine)' "$CLAUDE_SETTINGS" >"$tmp" || { rm -f "$tmp"; die "jq failed to edit $CLAUDE_SETTINGS"; }
      mv "$tmp" "$CLAUDE_SETTINGS"
      log "removed the statusLine entry from $CLAUDE_SETTINGS" ;;
    *)
      warn "statusLine points at something that is not ccstatusline ($current) — left alone" ;;
  esac

  # The config. Pre-install state is "no file", so a copy that is still ours
  # is backed up and deleted; an edited one is not ours to decide about.
  if [ ! -f "$DST" ]; then
    log "nothing at $DST — skipped"
  elif in_sync; then
    backup "$DST"
    rm -f "$DST"
    rmdir "$DST_DIR" 2>/dev/null || true
    log "removed $DST"
  else
    warn "installed config differs from the source (tuned by hand or through the TUI) — left alone"
    ls -1t "$DST".bak.* 2>/dev/null | head -1 | sed 's/^/      newest backup: /' || true
  fi

  # The package.
  if [ "$KEEP_PACKAGE" = 1 ]; then
    log "package: kept (--keep-package)"
  elif [ -z "$(resolve_bin || true)" ]; then
    log "package: not installed — skipped"
  elif ! command -v npm >/dev/null 2>&1; then
    warn "npm not found — remove the package yourself: npm uninstall -g $NPM_PKG"
  else
    log "package: npm uninstall -g $NPM_PKG"
    npm uninstall -g "$NPM_PKG" || warn "npm uninstall failed — continuing"
    reshim
  fi

  log "done. Claude Code sessions already open keep the status line until they restart."
}

do_diff() {
  [ -f "$SRC" ] || die "source missing: $SRC"
  if [ ! -f "$DST" ]; then
    echo "--- not installed ($DST)"
  elif in_sync; then
    log "installed config matches the source"
  else
    diff -u "$DST" "$SRC" || true
  fi
}

do_status() {
  local bin current
  bin="$(resolve_bin || true)"
  current="$(registered_cmd)"
  echo "source (edit here) : $SRC ($([ -f "$SRC" ] && echo present || echo missing))"
  echo "installed config   : $DST ($([ -f "$DST" ] && echo present || echo missing))"
  echo "in sync with source: $(in_sync && echo yes || echo no)"
  echo "binary             : ${bin:-missing}"
  case "$current" in
    "")             echo "statusLine entry   : not registered" ;;
    *ccstatusline*) echo "statusLine entry   : registered ($current)" ;;
    *)              echo "statusLine entry   : something else ($current)" ;;
  esac
}

# ==============================================================================
# Entry point
# ==============================================================================
ACTION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep-package) KEEP_PACKAGE=1 ;;
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
