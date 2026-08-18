# fhistory - fzf history search that fills the prompt instead of running the command
#
# Display order matches `history` (oldest on top, newest at the bottom); pinned with --no-sort.
# When you type a query the order stays put and only the CURSOR jumps to the best-scoring match:
# --raw keeps non-matching lines on screen (dimmed) and the `best` action moves the cursor to
# the highest-scoring one. Without --raw, fzf drops non-matching lines and `best` degrades to
# `first` -- the two flags only make sense together.
#
# Bound to Alt-R. Enter fills the command line; you press Enter yourself to run it.
# Ctrl-Y copies the selected command to the clipboard.

fhistory() {
  local selected tmp rc
  tmp="$(mktemp)" || return
  history > "$tmp"

  selected="$(
    fzf --tac --raw --no-sort \
      --query="$READLINE_LINE" \
      --bind 'result:best' \
      --bind "ctrl-y:execute-silent(printf %s {} | sed -E 's/^[[:space:]]*[0-9]+\*?[[:space:]]+//' | wl-copy)" \
      < "$tmp"
  )"
  rc=$?
  rm -f "$tmp"
  [ $rc -eq 0 ] && [ -n "$selected" ] || return

  # Strip the leading history number column, keep the command only
  selected="$(printf %s "$selected" | sed -E 's/^[[:space:]]*[0-9]+\*?[[:space:]]+//')"

  if [ -n "${READLINE_LINE+x}" ]; then
    # Invoked via Alt-R (bind -x): replace the current line, put the cursor at the end
    READLINE_LINE="$selected"
    READLINE_POINT=${#READLINE_LINE}
  else
    # Invoked by typing `fhistory` as a command: that prompt line is already consumed,
    # so inject into the NEXT prompt via the terminal's DSR (\e[5n) reply as a readline macro.
    local esc=${selected//\\/\\\\}   # escape backslashes
    esc=${esc//\"/\\\"}                # escape double quotes
    bind '"\e[0n": "'"$esc"'"' 2>/dev/null
    printf '\e[5n'
  fi
}

# Bind Alt-R in interactive shells only (Ctrl-R is left to fzf's own widget)
if [[ $- == *i* ]]; then
  bind -x '"\er": fhistory' 2>/dev/null
fi
