#!/usr/bin/env bash
#
# install.sh — pick what to set up on this machine, then run it
# ==============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh | bash
#   ./install.sh                 Pick from a checklist (everything preselected)
#   ./install.sh --all           Run everything, no questions
#   ./install.sh --only korean,bash
#   ./install.sh --remove        Take things back out (nothing preselected)
#   ./install.sh --list          Show what is available and its current state
#   ./install.sh --help          This help
#
# Options:
#   --all              Select everything without asking
#   --only <a,b,c>     Select these by name (see --list)
#   --guards / --no-guards
#                      Answer the optional pkg-guards question up front, so the
#                      bash step does not stop to ask
#   --dir <path>       Where the repo lives (default ~/.local/share/minsoft1115/omarchy-setup)
#   --dry-run          Show what would run, run nothing
#   --purge            With --remove, delete the clone as the very last step
#
# Removing runs the steps in reverse and starts with nothing selected: an
# install picked wrong is fixed by running it again, an uninstall picked wrong
# is not. What each step takes back out is its own business -- the Korean one
# deliberately leaves the fcitx5 config it edited alone; see its --help.
#
# The clone is kept, not thrown away. Every script here installs *from* the
# repo: the bash aliases, the widget source, and the Hyprland fragments all have
# their editable copy in it, and re-running an installer is how an edit reaches
# the system. Deleting it after the first run would leave a system nobody can
# update. Re-running this pulls the latest and offers the same list.
#
# Piped from curl, this clones the repo and then re-runs itself from the clone
# with the terminal reattached: a script arriving on stdin has no keyboard
# behind it, and the checklist would read an immediate EOF and select nothing.
# ==============================================================================
set -uo pipefail

REPO_URL="${REPO_URL:-https://github.com/minsoft1115/omarchy-setup.git}"
CLONE_DIR="${CLONE_DIR:-$HOME/.local/share/minsoft1115/omarchy-setup}"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
head_() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# A controlling terminal has to be opened to know it is there: /dev/tty exists
# and tests readable even in a session that has none, and only the open fails.
have_tty() {
  { exec 3<>/dev/tty; } 2>/dev/null || return 1
  exec 3>&-
}

# ==============================================================================
# The steps. Order here is the order they run in, whatever order they were
# picked in: the widget restarts the Omarchy shell, so it goes last and does not
# blink the bar out from under the steps that follow.
# ==============================================================================
STEP_NAMES=(korean bash widget)

step_label() {
  case "$1" in
    korean) echo "Korean input — right Alt switches 한/영, Omarchy menu opens in Latin" ;;
    bash)   echo "Bash config — Alt-R history picker, fzf search and kill, delta diffs" ;;
    widget) echo "Workspaces bar — hold Super to see which apps are where before switching" ;;
  esac
}

# Cheap file checks rather than parsing each script's status output: a one-word
# hint in a menu is not worth coupling this to another script's wording.
step_state() {
  case "$1" in
    korean)
      [ -f "$HOME/.config/minsoft1115/hypr/korean-input.lua" ] \
        && grep -qF -e "-- setup-korean:begin" "$HOME/.config/hypr/hyprland.lua" 2>/dev/null \
        && { echo installed; return; } ;;
    bash)
      grep -qF -e "# minsoft1115-bash:begin" "$HOME/.bashrc" 2>/dev/null \
        && { echo installed; return; } ;;
    widget)
      [ -f "$HOME/.config/omarchy/plugins/minsoft1115.workspaces/manifest.json" ] \
        && { echo installed; return; } ;;
  esac
  echo "not installed"
}

step_run() {
  case "$1" in
    korean) bash "$REPO_DIR/scripts/setup-korean.sh" ;;
    bash)   bash "$REPO_DIR/scripts/install-bash-config.sh" install $GUARDS_FLAG ;;
    widget) bash "$REPO_DIR/scripts/install-workspaces-widget.sh" install ;;
  esac
}

step_remove() {
  case "$1" in
    korean) bash "$REPO_DIR/scripts/setup-korean.sh" remove ;;
    bash)   bash "$REPO_DIR/scripts/install-bash-config.sh" remove ;;
    widget) bash "$REPO_DIR/scripts/install-workspaces-widget.sh" remove ;;
  esac
}

# ==============================================================================
# Bootstrap: get a clone, then hand over to the copy inside it
# ==============================================================================
SELF="${BASH_SOURCE[0]:-}"
REPO_DIR=""
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
  REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$SELF")")" && pwd)"
  # A directory holding this file but not the installers is not the repo.
  [ -d "$REPO_DIR/scripts" ] || REPO_DIR=""
fi

bootstrap() {
  command -v git >/dev/null 2>&1 || die "git is required to fetch the repo"

  if [ -d "$CLONE_DIR/.git" ]; then
    log "updating $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only --quiet \
      || warn "could not fast-forward — using the clone as it is"
  else
    log "cloning into $CLONE_DIR"
    mkdir -p "$(dirname "$CLONE_DIR")"
    git clone --quiet "$REPO_URL" "$CLONE_DIR" || die "clone failed"
  fi

  # Re-run from the clone with a real terminal on stdin. Without this the
  # checklist gets EOF from the curl pipe and selects nothing.
  if have_tty; then
    exec bash "$CLONE_DIR/install.sh" "$@" </dev/tty
  fi
  warn "no terminal available — running everything unattended"
  exec bash "$CLONE_DIR/install.sh" --all "$@"
}

# ==============================================================================
# Arguments
# ==============================================================================
SELECT_ALL=0
ONLY=""
GUARDS_FLAG=""
GUARDS_ANSWERED=0
LIST_ONLY=0
DRY_RUN=0
REMOVE=0
PURGE=0

usage() { awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${SELF:-$0}"; }

ARGS=("$@")
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)         SELECT_ALL=1 ;;
    --only)        shift; ONLY="${1:-}" ;;
    --only=*)      ONLY="${1#*=}" ;;
    --guards)      GUARDS_FLAG="--with-optional"; GUARDS_ANSWERED=1 ;;
    --no-guards)   GUARDS_FLAG="--no-optional";   GUARDS_ANSWERED=1 ;;
    --dir)         shift; CLONE_DIR="${1:-$CLONE_DIR}" ;;
    --dir=*)       CLONE_DIR="${1#*=}" ;;
    --list)        LIST_ONLY=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --remove)      REMOVE=1 ;;
    --purge)       PURGE=1 ;;
    --help|-h)     usage; exit 0 ;;
    *)             echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$REPO_DIR" ] || bootstrap "${ARGS[@]}"

if [ "$LIST_ONLY" = 1 ]; then
  for name in "${STEP_NAMES[@]}"; do
    printf '  %-8s %-14s %s\n' "$name" "[$(step_state "$name")]" "$(step_label "$name")"
  done
  exit 0
fi

# ==============================================================================
# Pick
# ==============================================================================
selected=()

if [ "$REMOVE" = 1 ]; then
  VERB="remove"
  PRESELECT=""
  MENU_HEADER="What should be removed? (space toggles, enter confirms)"
else
  VERB="install"
  PRESELECT='*'
  MENU_HEADER="What should be set up? (space toggles, enter confirms)"
fi

if [ "$SELECT_ALL" = 1 ]; then
  selected=("${STEP_NAMES[@]}")
elif [ -n "$ONLY" ]; then
  IFS=',' read -r -a selected <<<"$ONLY"
  for name in "${selected[@]}"; do
    case " ${STEP_NAMES[*]} " in
      *" $name "*) ;;
      *) die "unknown step: $name (see --list)" ;;
    esac
  done
else
  # The menu shows a sentence per step; the name is recovered from the position,
  # so the labels never have to double as identifiers.
  labels=()
  for name in "${STEP_NAMES[@]}"; do
    labels+=("$(printf '%-14s %s' "[$(step_state "$name")]" "$(step_label "$name")")")
  done

  if command -v gum >/dev/null 2>&1 && have_tty; then
    # Options go in as arguments, not on stdin: stdin is the terminal here, and
    # gum needs it for the keyboard.
    # --selected is left off entirely when nothing should start selected;
    # passing it empty is not the same thing to gum.
    gum_args=(choose --no-limit --header="$MENU_HEADER")
    [ -n "$PRESELECT" ] && gum_args+=(--selected="$PRESELECT")
    chosen="$(gum "${gum_args[@]}" "${labels[@]}" </dev/tty)" || chosen=""
  elif have_tty; then
    warn "gum not available — asking one by one"
    chosen=""
    for i in "${!labels[@]}"; do
      if [ "$REMOVE" = 1 ]; then
        printf 'remove? %s  [y/N] ' "${labels[$i]}" >/dev/tty
        read -r reply </dev/tty || reply=""
        case "$reply" in [yY]*) chosen="$chosen${labels[$i]}"$'\n' ;; esac
      else
        printf '%s  [Y/n] ' "${labels[$i]}" >/dev/tty
        read -r reply </dev/tty || reply=""
        case "$reply" in [nN]*) ;; *) chosen="$chosen${labels[$i]}"$'\n' ;; esac
      fi
    done
  elif [ "$REMOVE" = 1 ]; then
    die "no terminal to ask at — name what to remove with --only, or pass --all"
  else
    warn "no terminal to ask at — selecting everything (use --only to narrow)"
    chosen="$(printf '%s\n' "${labels[@]}")"
  fi

  [ -n "${chosen//[$'\n\t ']/}" ] || { log "nothing selected — done"; exit 0; }

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    for i in "${!labels[@]}"; do
      [ "$line" = "${labels[$i]}" ] && selected+=("${STEP_NAMES[$i]}")
    done
  done <<<"$chosen"
fi

# Fixed order, whatever order they came back in. Removing goes the other way,
# so the shell restart the widget triggers happens first rather than after the
# steps that still had work to do.
order=("${STEP_NAMES[@]}")
if [ "$REMOVE" = 1 ]; then
  order=()
  for (( i=${#STEP_NAMES[@]}-1; i>=0; i-- )); do order+=("${STEP_NAMES[$i]}"); done
fi

ordered=()
for name in "${order[@]}"; do
  for pick in "${selected[@]}"; do
    [ "$name" = "$pick" ] && { ordered+=("$name"); break; }
  done
done
selected=("${ordered[@]}")

# ==============================================================================
# The one question a sub-script would otherwise stop to ask
# ==============================================================================
if [ "$GUARDS_ANSWERED" = 0 ] && [ "$REMOVE" = 0 ]; then
  case " ${selected[*]} " in
    *" bash "*)
      if command -v gum >/dev/null 2>&1 && have_tty; then
        if gum confirm "Also guard pacman and yay?
Answers them with the matching omarchy command instead of running. Omarchy ships
its own version of these, so this is optional." </dev/tty >/dev/tty 2>&1; then
          GUARDS_FLAG="--with-optional"
        else
          GUARDS_FLAG="--no-optional"
        fi
      fi
      ;;
  esac
fi

# ==============================================================================
# Run
# ==============================================================================
results=()
for name in "${selected[@]}"; do
  head_ "$(step_label "$name")"
  if [ "$DRY_RUN" = 1 ]; then
    log "dry run — would $VERB the $name step"
    results+=("$name skipped (dry run)")
    continue
  fi
  if { [ "$REMOVE" = 1 ] && step_remove "$name"; } || { [ "$REMOVE" = 0 ] && step_run "$name"; }; then
    results+=("$name ok")
  else
    results+=("$name FAILED")
    warn "$name failed — continuing with the rest"
  fi
done

head_ "Summary"
for line in "${results[@]}"; do
  case "$line" in
    *FAILED) printf '\033[1;31m  %s\033[0m\n' "$line" ;;
    *)       printf '\033[1;32m  %s\033[0m\n' "$line" ;;
  esac
done

echo
if [ "$REMOVE" = 1 ]; then
  rmdir "$HOME/.config/minsoft1115" 2>/dev/null && log "cleaned up empty $HOME/.config/minsoft1115"
  case " ${selected[*]} " in
    *" bash "*) log "shells already open keep what they loaded until they restart" ;;
  esac
  if [ "$PURGE" = 1 ] && [ "$DRY_RUN" = 0 ]; then
    log "deleting the clone at $REPO_DIR"
    # exec so this process stops reading the script file it is about to delete.
    exec bash -c 'rm -rf -- "$1"' _ "$REPO_DIR"
  fi
  log "repo kept at $REPO_DIR (--purge deletes it)"
else
  log "repo kept at $REPO_DIR — edit there and re-run an installer to apply"
  case " ${selected[*]} " in
    *" bash "*) log "for the shell you are in right now: source ~/.bashrc" ;;
  esac
fi
