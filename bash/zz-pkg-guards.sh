# Ask before pacman or yay runs, and name the omarchy command that replaces it.
#
# On Omarchy packages go in and out through omarchy, and reaching past it leaves
# the machine in a state omarchy did not put it in. This file used to answer
# pacman and yay with a reminder and refuse to run them, which was the wrong
# trade: there is always the one time you do mean pacman, and a wall makes you
# retype the whole line with `command` in front of it. So it asks instead, with
# the omarchy command one keypress away.
#
#   $ sudo pacman -S ripgrep
#   Omarchy manages packages on this machine.
#   > omarchy pkg add ripgrep
#     run as typed: sudo pacman -S ripgrep
#     cancel
#
#   pacman -S <pkg>     ->  omarchy pkg add <pkg>
#   pacman -R <pkg>     ->  omarchy pkg drop <pkg>
#   pacman -Syu         ->  omarchy update
#   yay -S <pkg>        ->  omarchy pkg aur add <pkg>
#   yay                 ->  omarchy pkg aur install   (picker)
#
# Read-only operations are never asked about. `pacman -Q`, `-Ss`, `-Si`, `-Ql`
# and friends change nothing, need no root, and have no omarchy command worth
# naming -- and being stopped on the way to a query was most of what made the
# refusing version tiresome.
#
# Nothing is asked when omarchy is not installed either: the question only makes
# sense on a machine omarchy manages, and this file goes inert everywhere else.
#
# Why sudo is a function here:
#   Catching `sudo pacman` needs something that sees the word after sudo. The
#   old file used `alias sudo='sudo '` -- a trailing space is what makes bash
#   expand the next word as an alias too -- but a menu does not fit in an alias,
#   and sudo cannot call a shell function. So sudo becomes a function that hands
#   everything except pacman and yay straight through.
#
#   Aliases are expanded before functions are looked up, so an `alias sudo=...`
#   loaded after this file would shadow that function and the guard would never
#   run. sudo-pop installs exactly that (`alias sudo='sudo-pop'`). This file is
#   therefore named to sort last -- the loader sources the folder in filename
#   order -- and captures the alias rather than fighting it: whatever sudo meant
#   before is what the guard calls once the answer is yes. Neither file has to
#   know the other exists.
#
# Escape hatches: `command pacman`, `command yay`, `command sudo`. Backslash
# does not work on these -- `\pacman` only suppresses alias expansion, and these
# are functions.

# Whatever `sudo` meant before this file. Read now, while the alias still
# exists; dropped so the function below is reachable at all.
__pkg_guard_sudo=sudo
if [ -n "${BASH_ALIASES[sudo]+x}" ]; then
  __pkg_guard_sudo="${BASH_ALIASES[sudo]}"
  unalias sudo
fi

# Option letters, with the long spellings folded in, so that -Syu, -S -y -u and
# --sync --refresh --sysupgrade all come out as the same three letters. Only the
# options that decide what a command *does* are translated; the rest are dropped
# and end up in neither the answer nor the suggestion.
__pkg_guard_flags() {
  local out="" a
  for a in "$@"; do
    case "$a" in
      --sync)              out="${out}S" ;;
      --remove)            out="${out}R" ;;
      --query)             out="${out}Q" ;;
      --upgrade)           out="${out}U" ;;
      --files)             out="${out}F" ;;
      --deptest)           out="${out}T" ;;
      --refresh)           out="${out}y" ;;
      --sysupgrade)        out="${out}u" ;;
      --search)            out="${out}s" ;;
      --info)              out="${out}i" ;;
      --list)              out="${out}l" ;;
      --groups)            out="${out}g" ;;
      --print|--print-format) out="${out}p" ;;
      --version)           out="${out}V" ;;
      --help)              out="${out}h" ;;
      --*)                 ;;
      -?*)                 out="${out}${a#-}" ;;
      *)                   ;;
    esac
  done
  printf '%s' "$out"
}

# The package names on the line. Options that take a separate word for their
# value would otherwise have that word read as a package.
__pkg_guard_operands() {
  local out="" a skip=0
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in
      --config|--dbpath|--root|--cachedir|--gpgdir|--hookdir|--logfile|--arch|--sysroot|--ignore|--ignoregroup|--assume-installed|--overwrite|--print-format|--color)
        skip=1 ;;
      -*) ;;
      *)  out="$out $a" ;;
    esac
  done
  printf '%s' "${out# }"
}

# True when the command cannot change the system. Bare `pacman` prints its usage
# and is one of those; bare `yay` is the interactive picker and is not.
#
# "No operation we recognise" is not the same as "no operation": a line made
# only of long options this file does not translate would otherwise read as the
# bare command and run unasked. Only an empty argument list is the bare command;
# anything else we cannot name is asked about.
__pkg_guard_readonly() {
  local tool="$1" flags
  shift
  [ "$#" -eq 0 ] && { [ "$tool" = pacman ] && return 0; return 1; }
  flags="$(__pkg_guard_flags "$@")"

  case "$flags" in
    "")               return 1 ;;
    *Q*|*T*|*V*|*h*)  return 0 ;;
    # -Ss search, -Si info, -Sl list, -Sg groups, -Sp print: all just read the
    # sync database. -Sy, -Sw and -Sc do touch the machine.
    *S*) case "$flags" in *s*|*i*|*l*|*g*|*p*) return 0 ;; esac
         return 1 ;;
    # -F is a file query unless it is refreshing its database first.
    *F*) case "$flags" in *y*) return 1 ;; esac
         return 0 ;;
  esac
  return 1
}

# The omarchy command that does what was typed, or nothing when there is no
# single command that says it.
__pkg_guard_suggest() {
  local tool="$1" flags pkgs
  shift
  flags="$(__pkg_guard_flags "$@")"
  pkgs="$(__pkg_guard_operands "$@")"

  case "$flags" in
    *R*) [ -n "$pkgs" ] && printf 'omarchy pkg drop %s' "$pkgs"; return 0 ;;
    *u*) printf 'omarchy update'; return 0 ;;
  esac

  case "$tool" in
    pacman)
      case "$flags" in
        *S*) [ -n "$pkgs" ] && printf 'omarchy pkg add %s' "$pkgs" ;;
      esac ;;
    yay)
      case "$flags" in
        *S*) [ -n "$pkgs" ] && printf 'omarchy pkg aur add %s' "$pkgs" ;;
        "")  printf 'omarchy pkg aur install' ;;
      esac ;;
  esac
}

# The terminal's width. COLUMNS is what an interactive shell keeps up to date;
# stty answers when it is not set, and 80 is the last resort.
__pkg_guard_cols() {
  local rows cols=""
  if [ "${COLUMNS:-0}" -gt 20 ] 2>/dev/null; then
    printf '%s' "$COLUMNS"
    return 0
  fi
  read -r rows cols < <(stty size </dev/tty 2>/dev/null)
  case "$cols" in
    ''|*[!0-9]*) printf '80' ;;
    *)           [ "$cols" -gt 20 ] && printf '%s' "$cols" || printf '80' ;;
  esac
}

# Put the question on the controlling terminal and answer with one of:
# omarchy, typed, cancel.
#
# The question goes to /dev/tty rather than stdin, and having no terminal at all
# means running what was typed: an alias-and-function file is only ever loaded
# by an interactive shell, so the case is rare, and a prompt nobody can see is
# not a reason to fail a command.
__pkg_guard_ask() {
  local suggested="$1" typed="$2" choice reply
  local header="Omarchy manages packages on this machine."

  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    printf 'typed'
    return 0
  fi
  exec 3>&-

  if command -v gum >/dev/null 2>&1; then
    if [ -n "$suggested" ]; then
      # gum cuts a row at the terminal width less the two columns the cursor
      # takes, and cuts it silently -- no ellipsis, so a long package list ends
      # mid-word with nothing to say more was there. The row you did not type is
      # the one that has to be readable, so when it does not fit it goes into
      # the header too, wrapped by us: a header keeps the newlines it is given,
      # while a row never wraps. (Measured: at 60 columns a row survives to 58
      # characters and is cut from 59 on.)
      local cols
      cols="$(__pkg_guard_cols)"
      if [ "${#suggested}" -gt "$((cols - 2))" ]; then
        header="$header
$(printf '%s\n' "$suggested" | fold -s -w "$((cols - 4))" | sed 's/^/  /')"
      fi

      choice="$(gum choose --header "$header" \
        "$suggested" "run as typed: $typed" "cancel" </dev/tty 2>/dev/tty)" || choice=""
      case "$choice" in
        "$suggested")        printf 'omarchy' ;;
        "run as typed: "*)   printf 'typed' ;;
        *)                   printf 'cancel' ;;
      esac
      return 0
    fi
    if gum confirm "$header
Run it anyway?  $typed" </dev/tty >/dev/tty 2>&1; then printf 'typed'; else printf 'cancel'; fi
    return 0
  fi

  # No gum: the same three answers, typed out.
  {
    printf '%s\n' "$header"
    [ -n "$suggested" ] && printf '  1) %s\n' "$suggested"
    printf '  2) run as typed: %s\n  3) cancel\n' "$typed"
    printf '> '
  } >/dev/tty
  read -r reply </dev/tty
  case "$reply" in
    1)  [ -n "$suggested" ] && printf 'omarchy' || printf 'cancel' ;;
    2)  printf 'typed' ;;
    "") [ -n "$suggested" ] && printf 'omarchy' || printf 'cancel' ;;
    *)  printf 'cancel' ;;
  esac
}

# __pkg_guard <tool> <n> [sudo words...] [tool args...]
#
# n is how many words of the line belong to sudo (its own options, not the sudo
# word itself), or -1 when the tool was typed without sudo. That number is what
# lets "run as typed" put back the exact line, options and all.
__pkg_guard() {
  local tool="$1" n="$2"
  shift 2

  local -a pre=()
  if [ "$n" -gt 0 ]; then
    pre=("${@:1:$n}")
    shift "$n"
  fi
  local via=1
  [ "$n" -lt 0 ] && via=0

  # The line to run when the answer is "as typed", built once. The captured sudo
  # goes in unquoted on purpose: it may be an alias body of more than one word.
  local -a line=("$tool" "$@")
  [ "$via" = 1 ] && line=($__pkg_guard_sudo ${pre[@]+"${pre[@]}"} "$tool" "$@")

  # Not an omarchy machine: no opinion to have.
  if ! command -v omarchy >/dev/null 2>&1; then
    command "${line[@]}"
    return
  fi

  # Nothing to ask about: a query changes nothing.
  if __pkg_guard_readonly "$tool" "$@"; then
    command "${line[@]}"
    return
  fi

  local suggested typed="" word
  suggested="$(__pkg_guard_suggest "$tool" "$@")"

  # The line as it was typed, rebuilt in order: sudo, its options, the tool, the
  # rest. Only ever shown, never run -- running it uses the words themselves.
  [ "$via" = 1 ] && typed="sudo"
  for word in ${pre[@]+"${pre[@]}"} "$tool" "$@"; do
    typed="${typed:+$typed }$word"
  done

  local answer
  answer="$(__pkg_guard_ask "$suggested" "$typed")"
  # Nothing to suggest means there is no such answer to give.
  [ -n "$suggested" ] || [ "$answer" = cancel ] || answer=typed

  case "$answer" in
    omarchy)
      # Package names carry no spaces, so splitting the suggestion into words is
      # enough to run it. omarchy asks for root itself -- never under sudo here.
      local -a cmd=($suggested)
      command "${cmd[@]}"
      ;;
    typed)
      command "${line[@]}"
      ;;
    *)
      printf 'cancelled\n' >&2
      return 130
      ;;
  esac
}

pacman() { __pkg_guard pacman -1 "$@"; }
yay()    { __pkg_guard yay    -1 "$@"; }

# sudo's own options come before the command, and some of them take a separate
# word, so the command being run is the first word that is neither. Anything
# else is handed to the real sudo untouched.
sudo() {
  local i=1 skip=0 word tool=""
  for word in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; i=$((i + 1)); continue; fi
    case "$word" in
      -u|-g|-p|-C|-r|-t|-T|-U|-h|--user|--group|--prompt|--close-from|--role|--type|--command-timeout|--other-user|--host)
        skip=1 ;;
      --) i=$((i + 1)); tool="${*:$i:1}"; break ;;
      -*) ;;
      *)  tool="$word"; break ;;
    esac
    i=$((i + 1))
  done

  case "$tool" in
    pacman|yay) __pkg_guard "$tool" "$((i - 1))" "${@:1:$((i - 1))}" "${@:$((i + 1))}" ;;
    *)          command $__pkg_guard_sudo "$@" ;;
  esac
}
