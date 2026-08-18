#!/usr/bin/env bash
#
# install-workspaces-widget.sh — install this repo's workspaces bar widget
#                                into the running Omarchy shell
# ==============================================================================
# Usage:
#   ./install-workspaces-widget.sh status     Show current state (default)
#   ./install-workspaces-widget.sh install    Copy source into Omarchy and use it
#   ./install-workspaces-widget.sh revert     Go back to the stock Omarchy widget
#   ./install-workspaces-widget.sh remove     Revert, then delete the installed copy
#   ./install-workspaces-widget.sh diff       source vs installed, source vs stock
#   ./install-workspaces-widget.sh --help     This help
#
# Options:
#   --no-restart    Skip the shell restart (install files now, restart later)
#
# Every action is idempotent: re-running is safe, and anything already done is
# reported as "skipped".
#
# Layout:
#   source (edit here)  ./minsoft1115.workspaces/     tracked in this repo
#   installed copy      ~/.config/omarchy/plugins/minsoft1115.workspaces/
#   Hyprland binding    ./hypr/workspace-peek.lua  ->  ~/.config/hypr/
#
# The widget also ships a Super-hold peek overlay, and that half needs a
# Hyprland keybinding: a GlobalShortcut only registers a name, the compositor
# decides what triggers it. So install lays down the Lua fragment and adds one
# require line to ~/.config/hypr/hyprland.lua, between markers so it can be
# taken back out exactly. revert removes the line; remove deletes the fragment.
#
#   install copies the source into place. It is a copy, not a symlink: Omarchy's
#   plugin watcher (inotifywait -r) does not follow symlinks, so a linked plugin
#   never reports its edits to the shell.
#
#   After editing the widget, run install again to reinstall and restart.
#
# Why swapping and reverting are safe:
#   The manifest carries omarchy.clonedFrom = "omarchy.workspaces". The shell
#   reads that and replaces the stock entry in the bar layout in place, then
#   restores it in place when the clone is disabled. The widget keeps its
#   position in the bar and shell.json never needs to be hand-edited.
#     swap:   omarchy plugin enable  minsoft1115.workspaces
#     revert: omarchy plugin disable minsoft1115.workspaces
#
# Why the shell is restarted:
#   Edits to QML file contents are NOT picked up by
#   "omarchy-shell shell rescanPlugins" (verified on Omarchy 4.0); a full
#   "omarchy restart shell" is required. Layout changes in shell.json, on the
#   other hand, do hot-reload, so revert needs no restart.
#
# Why there is a pause between copying and restarting:
#   The install target is watched by Omarchy with inotify, so the copy itself
#   kicks off an in-process plugin reload. "omarchy restart shell" then kills
#   the shell (quickshell kill) — and killing it mid-reload races quickshell's
#   IPC handler teardown: IpcHandler::updateRegistration() dynamic_casts a
#   registry that is already being destroyed and segfaults. Two coredumps on
#   quickshell 0.3.0 were traced to exactly this. So the copy is allowed to
#   settle before the restart is requested. Tune with SETTLE_SECONDS.
#
# Notes:
#   - Ids starting with "omarchy." are rejected by the shell; that namespace is
#     reserved for first-party plugins.
#   - /usr/share/omarchy/ is never touched. The stock widget always stays put.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Settings — pre-set any of these in the environment to override
# ==============================================================================
: "${TS:=$(date +%s)}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"

PLUGIN_ID="${PLUGIN_ID:-minsoft1115.workspaces}"
STOCK_ID="${STOCK_ID:-omarchy.workspaces}"
SRC_DIR="${SRC_DIR:-$SCRIPT_DIR/$PLUGIN_ID}"
PLUGINS_DIR="${PLUGINS_DIR:-$HOME/.config/omarchy/plugins}"
SHELL_JSON="${SHELL_JSON:-$HOME/.config/omarchy/shell.json}"
# Stock widget sources, used by `diff`. Only consulted if the catalog lookup fails.
FALLBACK_DIR="${FALLBACK_DIR:-/usr/share/omarchy/shell/plugins/bar/widgets}"
# How long to let the inotify-triggered plugin reload finish before restarting.
SETTLE_SECONDS="${SETTLE_SECONDS:-2}"

# Hyprland side: the keybinding that drives the Super-hold peek overlay.
HYPR_DIR="${HYPR_DIR:-$HOME/.config/hypr}"
HYPR_MAIN="${HYPR_MAIN:-$HYPR_DIR/hyprland.lua}"
BIND_NAME="${BIND_NAME:-workspace-peek}"
BIND_SRC="${BIND_SRC:-$SCRIPT_DIR/hypr/$BIND_NAME.lua}"
BIND_DST="$HYPR_DIR/$BIND_NAME.lua"
BIND_BEGIN="-- workspaces-widget:begin"
BIND_END="-- workspaces-widget:end"

DST_DIR="$PLUGINS_DIR/$PLUGIN_ID"
RESTART=1

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

backup() { [ -f "$1" ] || return 0; cp -a "$1" "$1.bak.$TS"; log "backed up: $1.bak.$TS"; }

# Reuse the header comment block (from line 3 to the first non-comment line).
usage() { awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required"; }

# ==============================================================================
# Helpers
# ==============================================================================

# ------------------------------------------------------------------------------
# Validate the source folder before anything gets installed, so a broken widget
# never reaches the shell.
# ------------------------------------------------------------------------------
check_source() {
  need jq
  [ -d "$SRC_DIR" ] || die "source folder missing: $SRC_DIR"
  [ -f "$SRC_DIR/manifest.json" ] || die "manifest missing: $SRC_DIR/manifest.json"

  jq -e . "$SRC_DIR/manifest.json" >/dev/null 2>&1 \
    || die "manifest is not valid JSON: $SRC_DIR/manifest.json"

  local id cloned
  id="$(jq -r '.id // ""' "$SRC_DIR/manifest.json")"
  [ "$id" = "$PLUGIN_ID" ] || die "manifest id is '$id', expected '$PLUGIN_ID'"
  case "$id" in
    omarchy.*) die "an id starting with 'omarchy.' is rejected by the shell (reserved namespace)" ;;
  esac

  cloned="$(jq -r '.omarchy.clonedFrom // ""' "$SRC_DIR/manifest.json")"
  [ "$cloned" = "$STOCK_ID" ] \
    || warn "clonedFrom is '$cloned', not '$STOCK_ID' — in-place swap/restore will not work"

  # Every declared entry point must actually exist.
  local ep
  while IFS= read -r ep; do
    [ -n "$ep" ] || continue
    [ -f "$SRC_DIR/$ep" ] || die "entry point file missing: $SRC_DIR/$ep"
  done < <(jq -r '.entryPoints // {} | .[]' "$SRC_DIR/manifest.json")
}

require_shell() {
  need omarchy-shell
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 \
    || die "cannot reach omarchy-shell (is it running? try 'omarchy restart shell')"
}

# ------------------------------------------------------------------------------
# Writing into the plugins directory makes Omarchy hot-reload the plugin. Wait
# for that reload to finish before asking the shell to restart, so the kill does
# not land in the middle of component creation (see the header for the crash).
# ------------------------------------------------------------------------------
settle_after_copy() {
  log "letting the plugin reload settle (${SETTLE_SECONDS}s)..."
  sleep "$SETTLE_SECONDS"
  local i
  for i in $(seq 1 25); do
    omarchy-shell shell ping >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  warn "shell did not answer ping before the restart — continuing anyway"
}

restart_shell() {
  if [ "$RESTART" = 0 ]; then
    warn "skipping shell restart (--no-restart) — run 'omarchy restart shell' to apply"
    return 0
  fi
  need omarchy
  log "restarting shell (QML changes only apply on restart)..."
  omarchy restart shell >/dev/null 2>&1 || die "shell restart failed"
  local i
  for i in $(seq 1 60); do
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 && { log "shell is back"; return 0; }
    sleep 0.2
  done
  warn "gave up waiting for the shell — check with 'omarchy restart shell'"
}

installed() { [ -f "$DST_DIR/manifest.json" ]; }

# Does the installed copy match the source?
in_sync() {
  installed || return 1
  diff -r -q "$SRC_DIR" "$DST_DIR" >/dev/null 2>&1
}

plugin_in_bar() {
  omarchy-plugin-list --json 2>/dev/null \
    | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null 2>&1
}

plugin_known() {
  omarchy-plugin-list --json 2>/dev/null \
    | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null 2>&1
}

layout_section_of() {
  [ -f "$SHELL_JSON" ] || return 0
  jq -r --arg id "$1" '
    .bar.layout // {} | to_entries[]
    | .key as $section
    | .value[]? | select((.id // .) == $id) | $section
  ' "$SHELL_JSON" 2>/dev/null | head -1
}

wait_for_registry() {
  local i
  for i in $(seq 1 40); do plugin_known && return 0; sleep 0.05; done
  return 1
}

wait_for_bar() {
  local want="$1" i
  for i in $(seq 1 40); do
    if [ "$want" = "in" ]; then plugin_in_bar && return 0
    else plugin_in_bar || return 0
    fi
    sleep 0.05
  done
  return 1
}

# ------------------------------------------------------------------------------
# Hyprland binding: a Lua fragment plus one require line in hyprland.lua. The
# markers make the line removable without touching anything the user wrote.
# ------------------------------------------------------------------------------
bind_line_present() {
  [ -f "$HYPR_MAIN" ] && grep -qF -e "$BIND_BEGIN" "$HYPR_MAIN"
}

bind_installed() { [ -f "$BIND_DST" ]; }

bind_active() {
  hyprctl binds 2>/dev/null | grep -q "key: Super_L"
}

install_binding() {
  command -v hyprctl >/dev/null 2>&1 || { warn "hyprctl not found — skipping the Hyprland binding"; return 0; }
  [ -f "$BIND_SRC" ] || { warn "binding source missing: $BIND_SRC — skipping"; return 0; }
  [ -f "$HYPR_MAIN" ] || { warn "$HYPR_MAIN not found — skipping the Hyprland binding"; return 0; }

  local changed=0
  if [ -f "$BIND_DST" ] && cmp -s "$BIND_SRC" "$BIND_DST"; then
    log "Hyprland binding fragment already current"
  else
    cp -aL "$BIND_SRC" "$BIND_DST"
    log "installed: $BIND_SRC -> $BIND_DST"
    changed=1
  fi

  if bind_line_present; then
    log "hyprland.lua already requires the binding"
  else
    backup "$HYPR_MAIN"
    printf '\n%s\nrequire("hypr.%s")\n%s\n' "$BIND_BEGIN" "$BIND_NAME" "$BIND_END" >>"$HYPR_MAIN"
    log "added require(\"hypr.$BIND_NAME\") to $HYPR_MAIN"
    changed=1
  fi

  [ "$changed" = 1 ] || return 0
  hyprctl reload >/dev/null 2>&1 || warn "hyprctl reload failed"
  local errors
  errors="$(hyprctl configerrors 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
  [ -z "$errors" ] || warn "Hyprland reported config errors:"$'\n'"$errors"
}

remove_binding_line() {
  bind_line_present || { log "hyprland.lua has no binding line — skipped"; return 0; }
  backup "$HYPR_MAIN"
  sed -i "/$BIND_BEGIN/,/$BIND_END/d" "$HYPR_MAIN"
  # Drop the blank line the block was padded with, so repeated
  # install/revert cycles do not slowly grow a gap at the end of the file.
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HYPR_MAIN"
  log "removed the require line from $HYPR_MAIN"
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1
}

# Source directory of the stock widget, for `diff`.
upstream_dir() {
  local d=""
  if command -v omarchy-plugin-catalog >/dev/null 2>&1; then
    d="$(omarchy-plugin-catalog 2>/dev/null \
      | jq -r --arg id "$STOCK_ID" '.[] | select(.id == $id) | .sourceDir' 2>/dev/null || true)"
  fi
  [ -n "$d" ] && printf '%s' "$d" || printf '%s' "$FALLBACK_DIR"
}

# ==============================================================================
# install — copy the source into Omarchy and put it on the bar
# ==============================================================================
do_install() {
  check_source

  local changed=0 copied=0
  if in_sync; then
    log "installed copy matches source — nothing to copy"
  else
    installed && log "installed copy differs from source — reinstalling"
    # Swap the whole directory so deleted files are reflected too. Assemble in a
    # staging dir first so the shell never sees a half-written plugin.
    mkdir -p "$PLUGINS_DIR"
    local stage
    stage="$(mktemp -d "$PLUGINS_DIR/.install.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$stage'" EXIT
    cp -aL "$SRC_DIR/." "$stage/"
    rm -rf "$DST_DIR"
    mv "$stage" "$DST_DIR"
    trap - EXIT
    changed=1
    copied=1
    log "installed: $SRC_DIR -> $DST_DIR"
    find "$DST_DIR" -type f -printf '      %P\n' | sort
  fi

  require_shell
  wait_for_registry || die "the shell did not pick up '$PLUGIN_ID' — check the manifest"

  if plugin_in_bar; then
    log "already on the bar — skipping enable"
  else
    local where; where="$(layout_section_of "$STOCK_ID")"
    [ -n "$where" ] || warn "$STOCK_ID is not in the bar layout — inserting at the default spot"
    backup "$SHELL_JSON"
    omarchy-plugin-enable "$PLUGIN_ID" >/dev/null \
      || die "enable failed — try 'omarchy plugin enable $PLUGIN_ID' by hand"
    wait_for_bar in || die "shell.json was not updated"
    log "swapped: $STOCK_ID -> $PLUGIN_ID${where:+ ($where section, position kept)}"
    changed=1
  fi

  if [ "$changed" = 1 ]; then
    [ "$copied" = 1 ] && settle_after_copy
    restart_shell
  else
    log "nothing changed — skipping shell restart"
  fi

  install_binding

  log "done. hold Super to peek. to undo: $(basename "$0") revert"
}

# ==============================================================================
# revert — go back to the stock Omarchy widget
# ==============================================================================
do_revert() {
  need jq
  require_shell

  remove_binding_line

  if ! plugin_known; then
    log "$PLUGIN_ID is not registered (already on the stock widget) — skipped"
    return 0
  fi
  if ! plugin_in_bar; then
    log "already on the stock widget — skipped"
    return 0
  fi

  backup "$SHELL_JSON"
  omarchy-plugin-disable "$PLUGIN_ID" >/dev/null \
    || die "disable failed — try 'omarchy plugin disable $PLUGIN_ID' by hand"
  wait_for_bar out || die "shell.json was not updated"

  local where; where="$(layout_section_of "$STOCK_ID")"
  # Layout changes in shell.json hot-reload, so no restart is needed here.
  log "reverted: $PLUGIN_ID -> $STOCK_ID${where:+ ($where section, position kept)}"
  log "the installed copy stays at $DST_DIR (run install to use it again)"
}

# ==============================================================================
# remove — revert, then delete the installed copy
# ==============================================================================
do_remove() {
  do_revert
  if ! installed; then
    log "no installed copy — skipped"
    return 0
  fi
  if bind_installed; then
    rm -f "$BIND_DST"
    log "deleted: $BIND_DST"
  fi
  rm -rf "$DST_DIR"
  log "deleted: $DST_DIR (the source at $SRC_DIR is untouched)"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
}

# ==============================================================================
# diff — source vs installed copy, and source vs the stock widget
# ==============================================================================
do_diff() {
  need jq
  [ -d "$SRC_DIR" ] || die "source folder missing: $SRC_DIR"

  echo "### source vs installed copy ###"
  if ! installed; then
    echo "  not installed ($DST_DIR)"
  elif in_sync; then
    echo "  identical — the installed copy is current"
  else
    diff -r -u "$SRC_DIR" "$DST_DIR" || true
    echo "  -> run 'install' to sync"
  fi

  echo
  echo "### source vs stock widget ($STOCK_ID) ###"
  local up ep any=0
  up="$(upstream_dir)"
  while IFS= read -r ep; do
    [ -n "$ep" ] || continue
    if [ -f "$up/$ep" ]; then
      diff -u "$up/$ep" "$SRC_DIR/$ep" && continue
      any=1
    else
      echo "  not present upstream: $ep"; any=1
    fi
  done < <(jq -r '.entryPoints // {} | .[]' "$SRC_DIR/manifest.json")
  [ "$any" = 0 ] && echo "  identical (no functional change)"
}

# ==============================================================================
# status — where things currently stand
# ==============================================================================
do_status() {
  need jq
  echo "source (edit here) : $SRC_DIR $([ -d "$SRC_DIR" ] && echo '(present)' || echo '(missing)')"
  echo "installed copy     : $DST_DIR $(installed && echo '(present)' || echo '(missing)')"
  if installed; then
    echo "in sync with source: $(in_sync && echo 'yes' || echo 'no — run install')"
  fi
  echo "known to the shell : $(plugin_known && echo 'yes' || echo 'no')"

  local sec_mine sec_stock
  sec_mine="$(layout_section_of "$PLUGIN_ID")"
  sec_stock="$(layout_section_of "$STOCK_ID")"
  if [ -n "$sec_mine" ]; then
    echo "currently in use   : $PLUGIN_ID  (bar.layout.$sec_mine)"
  elif [ -n "$sec_stock" ]; then
    echo "currently in use   : $STOCK_ID  (bar.layout.$sec_stock, Omarchy stock)"
  else
    echo "currently in use   : (no workspaces widget in the bar layout)"
  fi

  echo "Hyprland binding   : $(bind_installed && echo 'installed' || echo 'not installed')\
$(bind_line_present && echo ', required by hyprland.lua' || echo ', not required by hyprland.lua')\
$(bind_active && echo ', Super_L bound' || echo ', Super_L NOT bound')"

  if [ -d "$SRC_DIR" ]; then
    echo
    echo "source files:"
    find "$SRC_DIR" -type f -printf '  %P\n' | sort
  fi
}

# ==============================================================================
# Argument parsing
# ==============================================================================
ACTION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-restart)   RESTART=0 ;;
    --help|-h|help) usage; exit 0 ;;
    -*)             echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    *)              [ -z "$ACTION" ] || { echo "only one action allowed: $ACTION, $1" >&2; exit 2; }
                    ACTION="$1" ;;
  esac
  shift
done

case "${ACTION:-status}" in
  install|use|apply|sync) do_install ;;
  revert|restore|off)     do_revert ;;
  remove|uninstall)       do_remove ;;
  diff)                   do_diff ;;
  status)                 do_status ;;
  *) echo "unknown action: $ACTION (see --help)" >&2; exit 2 ;;
esac
