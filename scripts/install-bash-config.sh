#!/usr/bin/env bash
#
# install-bash-config.sh — install this repo's bash aliases and functions
#                          into the interactive shell
# ==============================================================================
# Usage:
#   ./scripts/install-bash-config.sh status     Show current state (default)
#   ./scripts/install-bash-config.sh install    Copy the files and load them from ~/.bashrc
#   ./scripts/install-bash-config.sh remove     Drop the loader and delete the copies
#   ./scripts/install-bash-config.sh diff       source vs installed
#   ./scripts/install-bash-config.sh --help     This help
#
# Options:
#   --skip-packages   Do not touch packages, only install the files
#   --with-optional   Answer yes to every optional file, without asking
#   --no-optional     Answer no, and remove any optional file already installed
#
# Every action is idempotent: re-running is safe, and anything already done is
# reported as "skipped".
#
# Dependencies:
#   The aliases and functions call out to tools that are not part of a base
#   Arch install, so install puts them in first — nothing is more annoying than
#   an alias that only fails once you type it. They go in through
#   "omarchy pkg add", which is itself a no-op for packages already present, and
#   through nothing else -- no direct pacman call. No omarchy on the box is a
#   warning, not an error: the shell files still install and the aliases that
#   need no extra tool keep working.
#
#     git-delta   the `delta` pager, used by gdiff
#     bat         `cat` with syntax highlighting
#     ripgrep     the `rg` search used by fsearch
#     fzf         the picker behind fkill and fsearch
#
#   Package name and command are not always the same word -- git-delta installs
#   `delta`, ripgrep installs `rg` -- which is why presence is asked about by
#   package name and never with command -v.
#
# Layout:
#   source (edit here)  ./bash/*.sh
#   installed copy      ~/.config/minsoft1115/bash/*.sh
#   loader              ~/.bashrc, between markers
#
# Optional files:
#   Some files are a matter of taste rather than part of the set, so install
#   asks about them one at a time (gum confirm, or a plain y/N read without it)
#   and describes each one with its own first comment line. Anything already
#   installed is kept without asking again -- a prompt that reappears on every
#   run is a prompt people stop reading. With no terminal to ask at, they are
#   skipped rather than guessed at.
#
#     pkg-guards.sh   pacman/yay/sudo guards, which Omarchy also ships
#
# The loader is a loop over the installed folder rather than one source line per
# file, so adding a file to ./bash/ later needs an install and nothing else —
# ~/.bashrc never has to change again.
#
# It is appended to the end of ~/.bashrc, after Omarchy sources its own bash rc.
# Later definitions win, which is what makes overriding a stock alias possible.
#
# On sourcing:
#   A process cannot change the environment of the shell that started it, so
#   running this script can never load the aliases into the terminal you ran it
#   from. New shells pick them up on their own. To get them into the shell you
#   are sitting in, source the script instead of executing it:
#
#     source ./scripts/install-bash-config.sh install
#
#   which installs and then reloads ~/.bashrc in place. Executing it normally
#   does everything except that last step, and says so.
#
# Safety:
#   - Every source file is syntax-checked (bash -n) before it is installed. A
#     broken rc file would otherwise break every new shell.
#   - After installing, an interactive shell is started to confirm ~/.bashrc
#     still loads cleanly.
#   - ~/.bashrc is backed up as *.bak.<timestamp> before it is edited.
# ==============================================================================

# Sourced? Then hand the actual work to a child process — nothing this script
# defines leaks into the caller that way — and keep only the one step a child
# can never do: reloading the shell you are sitting in.
if (return 0 2>/dev/null); then
  msb_rc="${MSB_BASHRC:-$HOME/.bashrc}"
  msb_status=0
  MSB_CALLER_RELOADS=1 bash "${BASH_SOURCE[0]}" "$@" || msb_status=$?
  if [ "$msb_status" = 0 ]; then
    # shellcheck source=/dev/null
    . "$msb_rc" && printf '\033[1;32m[+]\033[0m %s\n' "reloaded $msb_rc into this shell"
    msb_status=$?
  fi
  unset msb_rc
  return "$msb_status"
fi

set -euo pipefail

# ==============================================================================
# Settings — pre-set any of these in the environment to override
# ==============================================================================
: "${TS:=$(date +%s)}"
MSB_SCRIPT="${BASH_SOURCE[0]}"
MSB_SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$MSB_SCRIPT")")" && pwd)"
# Sources live in the repo root; this script sits in scripts/.
MSB_REPO_DIR="$(dirname -- "$MSB_SCRIPT_DIR")"
# Set when we were started by the sourced path above, which reloads afterwards.
: "${MSB_CALLER_RELOADS:=0}"

MSB_SRC_DIR="${MSB_SRC_DIR:-$MSB_REPO_DIR/bash}"
MSB_DST_DIR="${MSB_DST_DIR:-$HOME/.config/minsoft1115/bash}"
MSB_BASHRC="${MSB_BASHRC:-$HOME/.bashrc}"
MSB_BEGIN="# minsoft1115-bash:begin"
MSB_END="# minsoft1115-bash:end"

# Arch package names, space separated. The binary a package provides is not
# always its name -- git-delta installs `delta` -- so presence is asked about by
# package, never by command.
MSB_PACKAGES="${MSB_PACKAGES:-git-delta bat ripgrep fzf}"
MSB_SKIP_PACKAGES=0

# Files install asks about instead of just installing. Space separated names,
# matched against ./bash/. Anything not listed here is installed unconditionally.
MSB_OPTIONAL="${MSB_OPTIONAL:-pkg-guards.sh}"
# Set by --with-optional / --no-optional to answer without asking.
MSB_OPTIONAL_ANSWER=""

msb_log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
msb_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
msb_die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; return 1; }

msb_backup() {
  [ -f "$1" ] || return 0
  cp -a "$1" "$1.bak.$TS"
  msb_log "backed up: $1.bak.$TS"
}

# Reuse the header comment block (from line 3 to the first non-comment line).
msb_usage() { awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$MSB_SCRIPT"; }

# ==============================================================================
# Helpers
# ==============================================================================

# Source file names, without the directory. Empty if there are none.
msb_source_files() {
  [ -d "$MSB_SRC_DIR" ] || return 0
  find "$MSB_SRC_DIR" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort
}

msb_installed_files() {
  [ -d "$MSB_DST_DIR" ] || return 0
  find "$MSB_DST_DIR" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort
}

msb_loader_present() {
  [ -f "$MSB_BASHRC" ] && grep -qF -e "$MSB_BEGIN" "$MSB_BASHRC"
}

msb_is_optional() {
  local name
  for name in $MSB_OPTIONAL; do
    [ "$name" = "$1" ] && return 0
  done
  return 1
}

# A file describes itself with its first line, so the prompt says what the file
# is for without this script carrying a second copy of that text.
msb_file_description() {
  local first
  first="$(head -n 1 "$1")"
  case "$first" in
    '#'*) printf '%s' "${first###}" | sed 's/^ *//' ;;
    *)    printf '%s' "optional shell file" ;;
  esac
}

# ------------------------------------------------------------------------------
# Decide whether an optional file goes in. Only ever called while installing --
# status must never put a prompt on screen.
# ------------------------------------------------------------------------------
msb_want_optional() {
  local name="$1" desc reply

  case "$MSB_OPTIONAL_ANSWER" in
    yes) return 0 ;;
    no)  return 1 ;;
  esac

  # Already installed: keep it, and do not ask again. A prompt that comes back
  # every single run is one people answer without reading.
  [ -f "$MSB_DST_DIR/$name" ] && return 0

  desc="$(msb_file_description "$MSB_SRC_DIR/$name")"

  # Ask on the controlling terminal, not on stdin: piping this script's output
  # somewhere should not silently turn the question into a no. Having no
  # controlling terminal at all -- cron, a hook, a CI step -- is the real case
  # where nothing can be asked, and that is what this detects.
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    msb_warn "optional: $name skipped — no terminal to ask at (use --with-optional)"
    return 1
  fi
  exec 3>&-

  if command -v gum >/dev/null 2>&1; then
    if gum confirm "Install $name?
$desc" </dev/tty >/dev/tty 2>&1; then return 0; else return 1; fi
  fi

  printf 'install %s? (%s) [y/N] ' "$name" "$desc" >/dev/tty
  read -r reply </dev/tty
  case "$reply" in
    [yY]*) return 0 ;;
    *)     return 1 ;;
  esac
}

# Per-package present/missing, for status. Asked one package at a time because
# "omarchy pkg missing" answers for a whole list with a single yes or no, which
# cannot say which of them is the missing one.
msb_packages_status() {
  [ -n "$MSB_PACKAGES" ] || { echo "none required"; return 0; }
  command -v omarchy >/dev/null 2>&1 || { echo "unknown (no omarchy)"; return 0; }

  local out="" pkg state
  for pkg in $MSB_PACKAGES; do
    omarchy pkg missing "$pkg" >/dev/null 2>&1 && state=MISSING || state=ok
    out="$out $pkg($state)"
  done
  printf '%s' "${out# }"
}

msb_in_sync() {
  local files f inst
  files="$(msb_source_files)"
  [ -n "$files" ] || return 1

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$MSB_DST_DIR/$f" ]; then
      # A declined optional file is a choice, not a difference.
      msb_is_optional "$f" && continue
      return 1
    fi
    cmp -s "$MSB_SRC_DIR/$f" "$MSB_DST_DIR/$f" || return 1
  done <<<"$files"

  while IFS= read -r inst; do
    [ -n "$inst" ] || continue
    printf '%s\n' "$files" | grep -qxF -- "$inst" || return 1
  done <<<"$(msb_installed_files)"
  return 0
}

# ------------------------------------------------------------------------------
# Refuse to install anything that would break every new shell. A syntax error in
# a file sourced from ~/.bashrc is exactly that kind of mistake, and it is only
# noticed once every terminal has stopped working.
# ------------------------------------------------------------------------------
msb_check_source() {
  [ -d "$MSB_SRC_DIR" ] || { msb_die "source folder missing: $MSB_SRC_DIR"; return 1; }

  local files f
  files="$(msb_source_files)"
  [ -n "$files" ] || { msb_die "no *.sh files in $MSB_SRC_DIR"; return 1; }

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    bash -n "$MSB_SRC_DIR/$f" || { msb_die "syntax error in $MSB_SRC_DIR/$f"; return 1; }
  done <<<"$files"
}

# ------------------------------------------------------------------------------
# The installed folder is a managed copy, so it mirrors the source exactly:
# files that are gone from the repo are removed here too, or they would keep
# being sourced forever.
# ------------------------------------------------------------------------------
msb_sync_files() {
  mkdir -p "$MSB_DST_DIR"

  local files f copied=0
  files="$(msb_source_files)"

  while IFS= read -r f; do
    [ -n "$f" ] || continue

    if msb_is_optional "$f" && ! msb_want_optional "$f"; then
      if [ -f "$MSB_DST_DIR/$f" ]; then
        rm -f "$MSB_DST_DIR/$f"
        msb_log "optional: removed $f"
      else
        msb_log "optional: $f left out"
      fi
      continue
    fi

    if cmp -s "$MSB_SRC_DIR/$f" "$MSB_DST_DIR/$f"; then continue; fi
    cp -a "$MSB_SRC_DIR/$f" "$MSB_DST_DIR/$f"
    copied=$((copied + 1))
  done <<<"$files"

  if [ "$copied" = 0 ]; then
    msb_log "installed copy already current — skipped"
  else
    msb_log "installed: $MSB_SRC_DIR -> $MSB_DST_DIR"
    msb_installed_files | sed 's/^/      /'
  fi

  local stale
  while IFS= read -r stale; do
    [ -n "$stale" ] || continue
    printf '%s\n' "$files" | grep -qxF -- "$stale" && continue
    rm -f "$MSB_DST_DIR/$stale"
    msb_log "removed stale copy: $stale (gone from the repo)"
  done <<<"$(msb_installed_files)"
}

# ------------------------------------------------------------------------------
# Install the tools the shell files lean on. Only through omarchy: it decides
# where a package comes from and how it is installed, and going around it with a
# raw pacman call would put packages on the system it never asked for. Without
# omarchy this is a warning and nothing else.
#
# "omarchy pkg missing" answers for the whole list at once, so the common case
# -- everything already there -- costs one query and prints one line.
# ------------------------------------------------------------------------------
msb_install_packages() {
  if [ "$MSB_SKIP_PACKAGES" = 1 ]; then
    msb_log "packages: skipped (--skip-packages)"
    return 0
  fi
  [ -n "$MSB_PACKAGES" ] || return 0

  if ! command -v omarchy >/dev/null 2>&1; then
    msb_warn "omarchy not found — install these yourself: $MSB_PACKAGES"
    return 0
  fi

  # shellcheck disable=SC2086
  if omarchy pkg missing $MSB_PACKAGES; then
    msb_log "packages: installing $MSB_PACKAGES"
    # shellcheck disable=SC2086
    omarchy pkg add $MSB_PACKAGES || msb_warn "package install failed — continuing"
  else
    msb_log "packages: $MSB_PACKAGES already installed — skipped"
  fi
}

msb_add_loader() {
  if msb_loader_present; then
    msb_log ".bashrc already loads them — skipped"
    return 0
  fi

  [ -f "$MSB_BASHRC" ] || { msb_warn "$MSB_BASHRC does not exist — creating it"; : >"$MSB_BASHRC"; }
  msb_backup "$MSB_BASHRC"

  cat >>"$MSB_BASHRC" <<EOF

$MSB_BEGIN
for __minsoft1115_rc in "$MSB_DST_DIR"/*.sh; do
  [ -r "\$__minsoft1115_rc" ] && . "\$__minsoft1115_rc"
done
unset __minsoft1115_rc
$MSB_END
EOF
  msb_log "added the loader to $MSB_BASHRC"
}

msb_remove_loader() {
  msb_loader_present || { msb_log ".bashrc has no loader — skipped"; return 0; }
  msb_backup "$MSB_BASHRC"
  sed -i "/$MSB_BEGIN/,/$MSB_END/d" "$MSB_BASHRC"
  # Drop the blank line the block was padded with, so repeated install/remove
  # cycles do not slowly grow a gap at the end of the file.
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$MSB_BASHRC"
  msb_log "removed the loader from $MSB_BASHRC"
}

# ------------------------------------------------------------------------------
# Sourcing ~/.bashrc from a non-interactive shell proves nothing: Omarchy's rc
# returns early for those, before it ever reaches our block. So the check runs
# an interactive shell, which is the only one that loads what we installed.
# ------------------------------------------------------------------------------
msb_smoke_test() {
  local out status=0
  # Long options have to come first; "bash -i --rcfile ..." is rejected.
  out="$(bash --rcfile "$MSB_BASHRC" -i -c 'true' 2>&1)" || status=$?
  # Running without a terminal makes bash complain about job control. That says
  # nothing about the rc file, so it is dropped rather than reported.
  out="$(printf '%s' "$out" \
    | grep -Ev 'no job control in this shell|cannot set terminal process group|Inappropriate ioctl for device' \
    || true)"

  if [ "$status" != 0 ]; then
    msb_warn "an interactive shell exited with status $status after the change:"
    [ -z "$out" ] || printf '%s\n' "$out"
    return 0
  fi

  if [ -n "$out" ]; then
    msb_warn "an interactive shell printed this on startup:"
    printf '%s\n' "$out"
  else
    msb_log "interactive shells load cleanly"
  fi
}

# ==============================================================================
# Actions
# ==============================================================================
msb_do_install() {
  msb_check_source || return 1
  msb_install_packages
  msb_sync_files
  msb_add_loader
  msb_smoke_test
  msb_log "done. new shells have them already."
  [ "$MSB_CALLER_RELOADS" = 1 ] && return 0
  msb_warn "this shell is unchanged — run 'source $MSB_BASHRC'," \
           "or 'source $MSB_SCRIPT install' next time"
  return 0
}

msb_do_remove() {
  msb_remove_loader
  if [ -d "$MSB_DST_DIR" ]; then
    rm -rf "$MSB_DST_DIR"
    msb_log "deleted $MSB_DST_DIR"
  else
    msb_log "no installed copy — skipped"
  fi
  msb_log "done. open shells keep what they already loaded until they restart."
}

msb_do_diff() {
  local files f shown=0
  files="$(msb_source_files)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$MSB_DST_DIR/$f" ]; then
      echo "--- $f: not installed$(msb_is_optional "$f" && echo ' (optional, left out)')"
      shown=1
      continue
    fi
    if ! cmp -s "$MSB_SRC_DIR/$f" "$MSB_DST_DIR/$f"; then
      echo "--- $f: source vs installed"
      diff -u "$MSB_DST_DIR/$f" "$MSB_SRC_DIR/$f" || true
      shown=1
    fi
  done <<<"$files"
  [ "$shown" = 1 ] || msb_log "installed copy matches the source"
}

msb_optional_status() {
  [ -n "$MSB_OPTIONAL" ] || { printf 'none'; return 0; }
  local out="" name
  for name in $MSB_OPTIONAL; do
    if [ -f "$MSB_DST_DIR/$name" ]; then out="$out $name(installed)"
    else out="$out $name(left out)"; fi
  done
  printf '%s' "${out# }"
}

msb_do_status() {
  local files
  files="$(msb_source_files)"

  echo "source (edit here) : $MSB_SRC_DIR ($([ -d "$MSB_SRC_DIR" ] && echo present || echo missing))"
  echo "installed copy     : $MSB_DST_DIR ($([ -d "$MSB_DST_DIR" ] && echo present || echo missing))"
  echo "in sync with source: $(msb_in_sync && echo yes || echo no)"
  echo "loaded by .bashrc  : $(msb_loader_present && echo yes || echo no)"
  echo "dependencies       : $(msb_packages_status)"
  echo "optional files     : $(msb_optional_status)"

  if [ -n "$files" ]; then
    echo
    echo "source files:"
    printf '%s\n' "$files" | sed 's/^/  /'
  fi
}

# ==============================================================================
# Entry point
# ==============================================================================
msb_main() {
  local action=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skip-packages) MSB_SKIP_PACKAGES=1 ;;
      --with-optional) MSB_OPTIONAL_ANSWER=yes ;;
      --no-optional)   MSB_OPTIONAL_ANSWER=no ;;
      --help|-h|help) msb_usage; return 0 ;;
      -*)             echo "unknown option: $1 (see --help)" >&2; return 2 ;;
      *)              [ -z "$action" ] || { echo "only one action allowed: $action, $1" >&2; return 2; }
                      action="$1" ;;
    esac
    shift
  done

  case "${action:-status}" in
    install|setup|apply|sync) msb_do_install ;;
    remove|uninstall)         msb_do_remove ;;
    diff)                     msb_do_diff ;;
    status)                   msb_do_status ;;
    *) echo "unknown action: $action (see --help)" >&2; return 2 ;;
  esac
}

msb_main "$@"
