#!/usr/bin/env bash
#
# install.sh — pick what to set up on this machine, then run it
# ==============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh | bash
#   ./install.sh                 Pick from a checklist (everything preselected)
#   ./install.sh --all           Run everything, no questions
#   ./install.sh --only korean,bash-config
#   ./install.sh --remove        Take things back out (nothing preselected)
#   ./install.sh --list          Show what is available and its current state
#   ./install.sh --help          This help
#
# Options:
#   --all              Select everything without asking
#   --only <a,b,c>     Select these by name (see --list)
#   --guards / --no-guards
#                      Answer the bash step's optional zz-pkg-guards.sh question
#                      advance. Without either, that step asks for itself -- and
#                      only when the file is not already installed
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
# sudo-pop is the one step whose source is not in this repo -- it has its own,
# and its step clones and builds that one the same way. It is a Rust build, so
# it takes minutes where the others take a second.
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
#
# sudo-pop sits after bash-config, which puts it before bash-config in the
# reverse order removal uses -- and that is the order that matters. Its --uninit
# has to run while the snippet loader bash-config owns is still in ~/.bashrc.
# ==============================================================================
STEP_NAMES=(korean bash-config sudo-pop workspaces)

# No commas in these: gum takes the preselected set as one comma-separated
# string matched against the option text, so a comma inside a label splits it
# and the match silently fails.
step_label() {
  case "$1" in
    korean)      echo "Korean input — right Alt for 한/영 · Omarchy menu opens in Latin" ;;
    bash-config) echo "Bash config — Alt-R history picker · fzf search and kill · delta diffs" ;;
    sudo-pop)    echo "sudo-pop — privileged password prompts in a popup · polkit agent + sudo router · built from source" ;;
    workspaces)  echo "Workspaces bar — hold Super to see which apps are where before switching" ;;
  esac
}

# Three states, because "installed" alone cannot say whether a git pull left
# anything to re-apply. Compared against the repo directly rather than by
# parsing each script's status output: a hint in a menu is not worth coupling
# this to another script's wording.
#
#   "not installed" / "installed / outdated" / "installed / latest"
#
# The first half answers "is it there", the second "is it current". Saying only
# the second one made an install look like it did nothing: a step that was
# already current still read "up to date" afterwards, with no word for the fact
# that it is installed at all.
FRAG_DIR="$HOME/.config/minsoft1115/hypr"
BASH_DST="$HOME/.config/minsoft1115/bash"
PLUGIN_DST="$HOME/.config/omarchy/plugins/minsoft1115.workspaces"
# sudo-pop lives in its own repository, so there is nothing here to compare a
# copy against -- see step_state.
SUDO_POP_URL="https://github.com/minsoft1115/sudo-pop.git"
SUDO_POP_BIN="$HOME/.local/bin/sudo-pop"
SUDO_POP_SNIPPET="$BASH_DST/sudo-pop.sh"
SUDO_POP_REV="${XDG_STATE_HOME:-$HOME/.local/state}/minsoft1115/sudo-pop.rev"

step_state() {
  local f name rev remote
  case "$1" in
    korean)
      [ -f "$FRAG_DIR/korean-input.lua" ] \
        && grep -qF -e "-- setup-korean:begin" "$HOME/.config/hypr/hyprland.lua" 2>/dev/null \
        || { echo "not installed"; return; }
      # korean-bindings.lua is generated per machine, so only the copied one is
      # comparable; a stale generated file is caught by re-running the step.
      cmp -s "$REPO_DIR/hypr/korean-input.lua" "$FRAG_DIR/korean-input.lua" \
        || { echo "installed / outdated"; return; }
      ;;
    bash-config)
      grep -qF -e "# minsoft1115-bash:begin" "$HOME/.bashrc" 2>/dev/null \
        || { echo "not installed"; return; }
      for f in "$REPO_DIR"/bash/*.sh; do
        name="${f##*/}"
        # An optional file that was declined is a choice, not a difference.
        [ -f "$BASH_DST/$name" ] || { [ "$name" = "zz-pkg-guards.sh" ] && continue
                                      echo "installed / outdated"; return; }
        cmp -s "$f" "$BASH_DST/$name" || { echo "installed / outdated"; return; }
      done
      ;;
    sudo-pop)
      [ -x "$SUDO_POP_BIN" ] && [ -f "$SUDO_POP_SNIPPET" ] \
        || { echo "not installed"; return; }
      # Nothing in this repo to compare against, and sudo-pop has no --version
      # to ask -- anything that is not --init/--uninit is passed through to
      # sudo. So its installer writes down the commit it built, and that is
      # what gets compared against upstream. One network round trip, ~0.5s.
      rev="$(cat "$SUDO_POP_REV" 2>/dev/null || true)"
      [ -n "$rev" ] || { echo "installed / outdated"; return; }
      remote="$(timeout 5 git ls-remote "$SUDO_POP_URL" main 2>/dev/null | awk 'NR==1{print $1}')"
      # Offline, the honest answer is "no idea", and a rebuild takes minutes.
      # Not a reason to preselect one on a guess.
      [ -z "$remote" ] || [ "$remote" = "$rev" ] || { echo "installed / outdated"; return; }
      ;;
    workspaces)
      [ -f "$PLUGIN_DST/manifest.json" ] || { echo "not installed"; return; }
      diff -r -q "$REPO_DIR/minsoft1115.workspaces" "$PLUGIN_DST" >/dev/null 2>&1 \
        || { echo "installed / outdated"; return; }
      cmp -s "$REPO_DIR/hypr/workspace-peek.lua" "$FRAG_DIR/workspace-peek.lua" \
        || { echo "installed / outdated"; return; }
      ;;
  esac
  echo "installed / latest"
}

# The command a step is, as a string: run it, or print it for --dry-run. One
# definition means the dry run cannot drift from what actually happens.
step_cmd() {
  case "$1" in
    korean)      echo "scripts/setup-korean.sh" ;;
    bash-config) echo "scripts/install-bash-config.sh install${GUARDS_FLAG:+ $GUARDS_FLAG}" ;;
    sudo-pop)    echo "scripts/install-sudo-pop.sh install" ;;
    workspaces)  echo "scripts/install-workspaces-widget.sh install" ;;
  esac
}

step_run() {
  # shellcheck disable=SC2046
  ( cd "$REPO_DIR" && bash $(step_cmd "$1") )
}

step_remove_cmd() {
  case "$1" in
    korean)      echo "scripts/setup-korean.sh remove" ;;
    bash-config) echo "scripts/install-bash-config.sh remove" ;;
    sudo-pop)    echo "scripts/install-sudo-pop.sh remove" ;;
    workspaces)  echo "scripts/install-workspaces-widget.sh remove" ;;
  esac
}

step_remove() {
  # shellcheck disable=SC2046
  ( cd "$REPO_DIR" && bash $(step_remove_cmd "$1") )
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
  #
  # No terminal at all is left to the copy in the clone to complain about. It is
  # not turned into "install everything": a pipe with nobody watching -- CI, a
  # cron line, a provisioning script -- is the last place to guess consent.
  if have_tty; then
    exec bash "$CLONE_DIR/install.sh" "$@" </dev/tty
  fi
  exec bash "$CLONE_DIR/install.sh" "$@"
}

# ==============================================================================
# Arguments
# ==============================================================================
SELECT_ALL=0
ONLY=""
GUARDS_FLAG=""
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
    --guards)      GUARDS_FLAG="--with-optional" ;;
    --no-guards)   GUARDS_FLAG="--no-optional" ;;
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
  # The first column is the name --only takes; without saying so it reads as
  # noise next to the sentence that follows it.
  printf '%-12s %-22s %s\n' "name" "state" "what it does"
  for name in "${STEP_NAMES[@]}"; do
    printf '%-12s %-22s %s\n' "$name" "[$(step_state "$name")]" "$(step_label "$name")"
  done
  printf '\nuse with: %s --only %s\n' "${SELF##*/}" "$(printf %s "${STEP_NAMES[*]}" | tr ' ' ',')"
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
  # The menu shows a sentence per row; the name is recovered from the position,
  # so the labels never have to double as identifiers.
  #
  # Every checkbox here means the same thing: "run this now". The optional
  # pkg-guards file used to ride along as a sub-row meaning "I want this file",
  # and two meanings wearing one checkbox is one meaning too many: on a machine
  # with everything installed it showed up as the only thing selected. The bash
  # step asks about that file itself, and only when it is not already there.
  menu_names=()
  labels=()
  preselect=()
  todo=0
  for name in "${STEP_NAMES[@]}"; do
    state="$(step_state "$name")"
    menu_names+=("$name")
    labels+=("$(printf '%-22s %s' "[$state]" "$(step_label "$name")")")
    [ "$state" = "installed / latest" ] || { preselect+=("${labels[-1]}"); todo=$((todo + 1)); }
  done

  if [ "$REMOVE" = 1 ]; then
    preselect=()
  elif [ "$todo" -eq 0 ]; then
    MENU_HEADER="Everything is installed and current — pick anything to re-apply"
  fi

  if command -v gum >/dev/null 2>&1 && have_tty; then
    # Options go in as arguments, not on stdin: stdin is the terminal here, and
    # gum needs it for the keyboard.
    # Bracketed prefixes rather than gum's default dot/check: a lone ✓ against a
    # • is easy to miss at a glance, and a box reads as a checkbox even where the
    # terminal renders both in the same color.
    #
    # --selected is left off entirely when nothing should start selected;
    # passing it empty is not the same thing to gum.
    gum_args=(choose --no-limit --header="$MENU_HEADER"
              --selected-prefix="[✓] " --unselected-prefix="[ ] " --cursor-prefix="[ ] "
              --selected.foreground="2" --cursor.foreground="4")
    if [ "${#preselect[@]}" -gt 0 ]; then
      gum_args+=(--selected="$(printf '%s,' "${preselect[@]}" | sed 's/,$//')")
    fi
    chosen="$(gum "${gum_args[@]}" "${labels[@]}" </dev/tty)" || chosen=""
  elif have_tty; then
    warn "gum not available — asking one by one"
    chosen=""
    for i in "${!labels[@]}"; do
      # Default follows the same rule as the checklist's preselection.
      want=no
      for pre in ${preselect[@]+"${preselect[@]}"}; do
        [ "$pre" = "${labels[$i]}" ] && want=yes
      done
      if [ "$want" = yes ]; then
        printf '%s  [Y/n] ' "${labels[$i]}" >/dev/tty
        read -r reply </dev/tty || reply=""
        case "$reply" in [nN]*) ;; *) chosen="$chosen${labels[$i]}"$'\n' ;; esac
      else
        printf '%s  [y/N] ' "${labels[$i]}" >/dev/tty
        read -r reply </dev/tty || reply=""
        case "$reply" in [yY]*) chosen="$chosen${labels[$i]}"$'\n' ;; esac
      fi
    done
  else
    die "no terminal to ask at — say what you want with --all or --only $(printf %s "${STEP_NAMES[*]}" | tr ' ' ',')"
  fi

  [ -n "${chosen//[$'\n\t ']/}" ] || { log "nothing selected — done"; exit 0; }

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    for i in "${!labels[@]}"; do
      [ "$line" = "${labels[$i]}" ] && selected+=("${menu_names[$i]}")
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
# Run
# ==============================================================================
results=()
for name in "${selected[@]}"; do
  head_ "$(step_label "$name")"
  if [ "$DRY_RUN" = 1 ]; then
    if [ "$REMOVE" = 1 ]; then log "dry run — would run: $(step_remove_cmd "$name")"
    else                       log "dry run — would run: $(step_cmd "$name")"; fi
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
    *" bash-config "*|*" sudo-pop "*) log "shells already open keep what they loaded until they restart" ;;
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
    *" bash-config "*|*" sudo-pop "*) log "for the shell you are in right now: source ~/.bashrc" ;;
  esac
fi
