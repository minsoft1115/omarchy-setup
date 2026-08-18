fkill() {
  local selected pid
  selected="$(ps -ef | grep "$USER" | awk '{print $2, $8}' | fzf --height 40% --layout=reverse --border)" || return
  pid="$(awk '{print $1}' <<< "$selected")"
  [ -n "$pid" ] && kill "$@" "$pid"
}
