#!/usr/bin/env bash
#
# install-sudo-pop.sh — build and install sudo-pop, the popup for privileged prompts
# ==============================================================================
# Usage:
#   ./scripts/install-sudo-pop.sh status     Show current state (default)
#   ./scripts/install-sudo-pop.sh install    Clone or update, build, install, --init
#   ./scripts/install-sudo-pop.sh remove     --uninit first, then delete the binary
#   ./scripts/install-sudo-pop.sh --help     This help
#
# Options:
#   --force         Rebuild even when the checkout is already what is installed
#   --purge         With remove, delete the source clone as well
#   --prefix DIR    Where the binary goes (default ~/.local/bin)
#
# Every action is idempotent: re-running is safe, and anything already done is
# reported as "skipped".
#
# sudo-pop lives in its own repository, so unlike the other installers here
# there is no source folder to copy from -- there is a build:
#
#   source (built here)  ~/.local/share/minsoft1115/sudo-pop   git clone, branch main
#   binary               ~/.local/bin/sudo-pop
#   what --init writes   ~/.config/minsoft1115/bash/sudo-pop.sh   alias sudo='sudo-pop'
#                        ~/.config/minsoft1115/hypr/sudo-pop.lua  popup window rules
#                        ~/.config/hypr/hyprland.lua              one require line
#                        ~/.config/systemd/user/sudo-pop-agent.service  the polkit agent
#
# Why a clone and not the upstream curl one-liner:
#   Building takes minutes, so "is it current" has to be answerable without
#   building to find out -- and sudo-pop has no --version to ask (every argument
#   that is not --init/--uninit is passed through to sudo). A checkout answers
#   it with a commit id: the one that was built is recorded, and compared
#   against the checkout and against upstream. Upstream's own install.sh is
#   still what does the work; run from inside a checkout it builds that checkout
#   and downloads nothing.
#
# Pinned to main. sudo-pop has no tags yet, and --ref would be a knob with one
# valid value.
#
# Removing is handed to the same install.sh, which has an --uninstall. It runs
# --uninit before deleting the binary -- the alias outlives the file it points
# at, and a sudo that is "command not found" is a bad afternoon -- and takes the
# same files out by hand when the binary is already gone. It also removes the
# askpass symlink under $XDG_RUNTIME_DIR, which nothing here would have known
# about. Only when the checkout itself is missing does this script do it, and
# then only what it can be sure of.
#
# The shared snippet loader in ~/.bashrc is left alone either way -- the
# bash-config step owns it, and other tools sit in the same folder.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Settings — pre-set any of these in the environment to override
# ==============================================================================
: "${TS:=$(date +%s)}"

REPO_URL="${SUDO_POP_REPO_URL:-https://github.com/minsoft1115/sudo-pop.git}"
BRANCH="${SUDO_POP_BRANCH:-main}"
SRC_DIR="${SUDO_POP_SRC:-$HOME/.local/share/minsoft1115/sudo-pop}"
PREFIX="${SUDO_POP_PREFIX:-$HOME/.local/bin}"

# The commit the installed binary was built from. sudo-pop cannot be asked, so
# it is written down here -- next to the state Omarchy keeps, not in ~/.config,
# because it is a record and not something anyone edits.
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/minsoft1115}"
REV_FILE="$STATE_DIR/sudo-pop.rev"

# What `sudo-pop --init` writes. Only consulted to report state and to clean up
# after a binary that was deleted before it could --uninit itself.
CONF_DIR="${CONF_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}}"
BASH_SNIPPET="$CONF_DIR/minsoft1115/bash/sudo-pop.sh"
HYPR_SNIPPET="$CONF_DIR/minsoft1115/hypr/sudo-pop.lua"
# The polkit agent runs as a systemd user unit; --init installs and enables it.
UNIT="sudo-pop-agent.service"
UNIT_FILE="$CONF_DIR/systemd/user/$UNIT"
HYPR_MAIN="${HYPR_MAIN:-$CONF_DIR/hypr/hyprland.lua}"
HYPR_BEGIN="-- sudo-pop:begin"
HYPR_END="-- sudo-pop:end"

BIN="$PREFIX/sudo-pop"
FORCE=0
PURGE=0

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

backup() { [ -f "$1" ] || return 0; cp -a "$1" "$1.bak.$TS"; log "backed up: $1.bak.$TS"; }

# Reuse the header comment block (from line 3 to the first non-comment line).
usage() { awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

# ==============================================================================
# Preflight
# ==============================================================================

# A C linker is not optional and not something to install on someone's behalf:
# base-devel is a group, it needs sudo, and sudo is the thing being replaced.
require_toolchain() {
  command -v git >/dev/null 2>&1 || die "'git' is required"
  command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
    || die "no C linker found (cc) — install it first:  omarchy pkg add base-devel"
  # cargo directly, or mise, which reads the rust version pinned in mise.toml.
  # Omarchy ships mise in its base packages, so this is rarely the failing one.
  command -v cargo >/dev/null 2>&1 || command -v mise >/dev/null 2>&1 \
    || die "no Rust toolchain — install mise (omarchy pkg add mise) or rustup"
}

builder() {
  if command -v cargo >/dev/null 2>&1; then echo "cargo"
  elif command -v mise >/dev/null 2>&1; then echo "mise"
  else echo "none"; fi
}

# ==============================================================================
# Helpers
# ==============================================================================
have_clone()  { [ -d "$SRC_DIR/.git" ]; }
installed()   { [ -x "$BIN" ]; }
conf_present() { [ -f "$BASH_SNIPPET" ] && [ -f "$HYPR_SNIPPET" ] && [ -f "$UNIT_FILE" ]; }

hypr_block_present() {
  [ -f "$HYPR_MAIN" ] && grep -qF -e "$HYPR_BEGIN" "$HYPR_MAIN"
}

on_path() {
  case ":${PATH:-}:" in *":$PREFIX:"*) return 0 ;; *) return 1 ;; esac
}

# True when the Omarchy shell's own polkit agent holds this session's seat, in
# which case sudo-pop's agent is installed but stays dormant (one agent per
# session). Its plugin lives inside the shell, so it is not a process to pgrep.
omarchy_polkit_enabled() {
  command -v omarchy-plugin-list >/dev/null 2>&1 || return 1
  if command -v jq >/dev/null 2>&1; then
    [ "$(omarchy-plugin-list --json 2>/dev/null \
         | jq -r '.[]|select(.id=="omarchy.polkit")|.enabled' 2>/dev/null)" = "true" ]
  else
    omarchy-plugin-list --json 2>/dev/null | tr -d ' \n' \
      | grep -q '"id":"omarchy.polkit","[^}]*"enabled":true'
  fi
}

# Commit currently checked out, and the one the installed binary came from.
local_rev()  { have_clone && git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || true; }
built_rev()  { [ -f "$REV_FILE" ] && cat "$REV_FILE" 2>/dev/null || true; }

# Upstream tip. Costs a network round trip (~0.5s), so it is only ever asked for
# by `status`; an offline machine gets an empty answer rather than a failure.
remote_rev() {
  timeout 5 git ls-remote "$REPO_URL" "$BRANCH" 2>/dev/null | awk 'NR==1{print $1}'
}

short() { [ -n "${1:-}" ] && printf '%.7s' "$1" || printf '?'; }

# ------------------------------------------------------------------------------
# Get the checkout to the tip of main. A clone that cannot fast-forward is used
# as it is rather than reset: someone editing sudo-pop locally is the one case
# where this script must not throw work away.
# ------------------------------------------------------------------------------
sync_clone() {
  if have_clone; then
    local branch
    branch="$(git -C "$SRC_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    [ "$branch" = "$BRANCH" ] \
      || warn "checkout is on '$branch', not '$BRANCH' — using it as it is"
    log "updating $SRC_DIR"
    git -C "$SRC_DIR" pull --ff-only --quiet \
      || warn "could not fast-forward — using the checkout as it is"
  else
    log "cloning sudo-pop into $SRC_DIR"
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --quiet --branch "$BRANCH" "$REPO_URL" "$SRC_DIR" || die "clone failed"
  fi
  [ -f "$SRC_DIR/install.sh" ] || die "$SRC_DIR has no install.sh — is this the right repo?"
}

# ------------------------------------------------------------------------------
# Hand the build to upstream's own installer. Run from inside a checkout it
# builds that checkout, installs the binary and runs --init; it downloads
# nothing and never uses sudo.
# ------------------------------------------------------------------------------
run_upstream_install() {
  log "building sudo-pop (a few minutes the first time)"
  bash "$SRC_DIR/install.sh" --prefix "$PREFIX" || die "the sudo-pop installer failed"
}

# ==============================================================================
# install — clone or update, build if the commit moved, wire it up
# ==============================================================================
do_install() {
  require_toolchain
  sync_clone

  local head built
  head="$(local_rev)"
  built="$(built_rev)"

  if [ "$FORCE" = 0 ] && installed && [ -n "$head" ] && [ "$head" = "$built" ]; then
    log "sudo-pop $(short "$head") is already installed — skipping the build"
    # The binary can be current while its config is not: --init writes into
    # ~/.config, and a bash-config remove or a hand-edited hyprland.lua takes
    # part of it away without the binary noticing.
    if conf_present && hypr_block_present; then
      log "shell alias and window rules already in place — skipped"
    else
      log "re-running sudo-pop --init (some of what it writes is missing)"
      "$BIN" --init
    fi
  else
    if installed && [ -n "$built" ]; then
      log "installed $(short "$built") -> building $(short "$head")"
    fi
    run_upstream_install
    installed || die "the installer produced no binary at $BIN"
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$head" >"$REV_FILE"
    log "recorded the built commit: $(short "$head") -> $REV_FILE"
  fi

  on_path || warn "$PREFIX is not on PATH — the sudo alias will not resolve"
  command -v hyprctl >/dev/null 2>&1 \
    || warn "hyprctl not found — the popup window rules are Hyprland-specific"

  if ! systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
    if omarchy_polkit_enabled; then
      warn "the polkit agent is installed but not running: omarchy.polkit holds the seat."
      warn "to hand it to sudo-pop:  omarchy plugin disable omarchy.polkit && $BIN --init"
      warn "(the sudo router works regardless; this only affects run0 and other polkit prompts)"
    else
      warn "the polkit agent unit is not active — check: systemctl --user status $UNIT"
    fi
  fi

  log "done. new shells get it; for this one: source ~/.bashrc"
  log "to undo: $(basename "$0") remove"
}

# ==============================================================================
# remove — hand it to upstream's --uninstall
# ==============================================================================

# Only reached when there is no checkout to ask. Upstream knows more than this
# does -- the runtime symlink, a begin marker with no end -- so this stays the
# fallback and never the path.
remove_by_hand() {
  if installed; then
    # --uninit before rm: the binary is what knows where its files went.
    log "running sudo-pop --uninit"
    "$BIN" --uninit || warn "--uninit failed — removing its files directly instead"
    rm -f "$BIN"
    log "deleted: $BIN"
  else
    log "no binary at $BIN — removing its files directly"
  fi

  # The systemd user unit --init enables. Left behind it would keep restarting
  # on a binary that is gone (Restart=on-failure), so stop and remove it.
  systemctl --user disable --now "$UNIT" >/dev/null 2>&1 || true
  if [ -f "$UNIT_FILE" ]; then
    rm -f "$UNIT_FILE"
    log "deleted: $UNIT_FILE"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi

  local f
  for f in "$BASH_SNIPPET" "$HYPR_SNIPPET"; do
    [ -f "$f" ] || continue
    rm -f "$f"
    log "deleted: $f"
  done

  if hypr_block_present; then
    if grep -qF -e "$HYPR_END" "$HYPR_MAIN"; then
      backup "$HYPR_MAIN"
      sed -i "/^$HYPR_BEGIN$/,/^$HYPR_END$/d" "$HYPR_MAIN"
      # Drop the blank line the block was padded with, so repeated cycles do not
      # slowly grow a gap at the end of the file.
      sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HYPR_MAIN"
      log "removed the window rules from $HYPR_MAIN"
      command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
    else
      # Same rule the binary follows: a stray marker line beats eating a config.
      warn "$HYPR_MAIN has $HYPR_BEGIN without $HYPR_END — left alone, remove it by hand"
    fi
  fi

  [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -e "$XDG_RUNTIME_DIR/sudo-pop" ] \
    && { rm -rf "$XDG_RUNTIME_DIR/sudo-pop"; log "deleted: $XDG_RUNTIME_DIR/sudo-pop"; }
  return 0
}

do_remove() {
  if [ -f "$SRC_DIR/install.sh" ]; then
    bash "$SRC_DIR/install.sh" --uninstall --prefix "$PREFIX" \
      || warn "the sudo-pop uninstaller reported a problem — check what is left with 'status'"
  else
    warn "no checkout at $SRC_DIR — taking out what is known here instead"
    remove_by_hand
  fi

  [ -f "$REV_FILE" ] && { rm -f "$REV_FILE"; log "deleted: $REV_FILE"; }
  rmdir "$STATE_DIR" 2>/dev/null || true

  if [ "$PURGE" = 1 ]; then
    [ -d "$SRC_DIR" ] && { rm -rf "$SRC_DIR"; log "deleted the source clone at $SRC_DIR"; }
  elif [ -d "$SRC_DIR" ]; then
    log "source clone kept at $SRC_DIR (--purge deletes it, build tree and all)"
  fi
}

# ==============================================================================
# status — where things currently stand
# ==============================================================================
do_status() {
  local head built remote size="" row
  head="$(local_rev)"
  built="$(built_rev)"
  # A printf template rather than padded literals: the branch name is part of
  # one of the labels, so the column cannot be baked into the strings.
  row() { printf '%-19s: %s\n' "$1" "$2"; }

  if have_clone; then
    [ -d "$SRC_DIR/target" ] && size=", $(du -sh "$SRC_DIR" 2>/dev/null | cut -f1) with the build tree"
    row "source (built here)" "$SRC_DIR ($BRANCH @ $(short "$head")${size})"
  else
    row "source (built here)" "$SRC_DIR (not cloned yet)"
  fi

  remote="$(remote_rev)"
  if [ -z "$remote" ]; then
    row "upstream $BRANCH" "(could not reach $REPO_URL)"
  elif [ -z "$head" ]; then
    row "upstream $BRANCH" "$(short "$remote")"
  elif [ "$remote" = "$head" ]; then
    row "upstream $BRANCH" "$(short "$remote") (checkout is current)"
  else
    row "upstream $BRANCH" "$(short "$remote") — newer than the checkout"
  fi

  if ! installed; then
    row "binary" "$BIN (missing)"
  elif [ -z "$built" ]; then
    row "binary" "$BIN (present, built from an unknown commit — run install)"
  elif [ -n "$head" ] && [ "$built" != "$head" ]; then
    row "binary" "$BIN (present, built from $(short "$built") — run install)"
  else
    row "binary" "$BIN (present, built from $(short "$built"))"
  fi

  row "on PATH" "$(on_path && echo 'yes' || echo "no — $PREFIX is not in PATH")"
  row "shell alias" "$BASH_SNIPPET $([ -f "$BASH_SNIPPET" ] && echo '(present)' || echo '(missing)')"
  row "window rules" "$HYPR_SNIPPET $([ -f "$HYPR_SNIPPET" ] && echo '(present)' || echo '(missing)')\
$(hypr_block_present && echo ', required by hyprland.lua' || echo ', NOT required by hyprland.lua')"

  row "agent" "$UNIT ($(systemctl --user is-active "$UNIT" 2>/dev/null || echo inactive) / $(systemctl --user is-enabled "$UNIT" 2>/dev/null || echo disabled))"
  if command -v omarchy-plugin-list >/dev/null 2>&1; then
    if omarchy_polkit_enabled; then
      row "omarchy.polkit" "enabled — it holds the polkit seat, so the agent stays dormant"
    else
      row "omarchy.polkit" "disabled — the sudo-pop agent can hold the seat"
    fi
  fi

  local cc_ok
  cc_ok="$( { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; } && echo ok || echo MISSING)"
  row "build tools" "cc($cc_ok) rust($(builder))"
}

# ==============================================================================
# Argument parsing
# ==============================================================================
ACTION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)        FORCE=1 ;;
    --purge)        PURGE=1 ;;
    --prefix)       shift; PREFIX="${1:?--prefix needs a directory}"; BIN="$PREFIX/sudo-pop" ;;
    --prefix=*)     PREFIX="${1#*=}"; BIN="$PREFIX/sudo-pop" ;;
    --help|-h|help) usage; exit 0 ;;
    -*)             echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    *)              [ -z "$ACTION" ] || { echo "only one action allowed: $ACTION, $1" >&2; exit 2; }
                    ACTION="$1" ;;
  esac
  shift
done

case "${ACTION:-status}" in
  install|update|upgrade) do_install ;;
  remove|uninstall)       do_remove ;;
  status)                 do_status ;;
  *) echo "unknown action: $ACTION (see --help)" >&2; exit 2 ;;
esac
