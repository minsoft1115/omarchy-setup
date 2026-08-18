# fsearch - Find In Files (interactive search with fzf)
# Usage:
#   fsearch <keyword>              # search all files
#   fsearch <extension> <keyword>  # search specific extension
#   fsearch --help

fsearch() {
  # Help
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << EOF
Usage:
  fsearch <keyword>              # search all files
  fsearch <extension> <keyword>  # search specific extension
  fsearch --help

Examples:
  fsearch TODO
  fsearch md TODO
  fsearch py error
  fsearch tsx useState
EOF
    return 0
  fi

  local ext word

  if [ $# -eq 0 ]; then
    echo "Usage: fsearch <keyword>  or  fsearch <extension> <keyword>"
    echo "Help:  fsearch --help"
    return 1
  elif [ $# -eq 1 ]; then
    # 확장자 생략 → 전체 파일 검색
    ext="*"
    word="$1"
  else
    ext="$1"
    word="$2"
  fi

  local files

  # Prefer ripgrep, fallback to find+grep
  if command -v rg >/dev/null 2>&1; then
    if [ "$ext" = "*" ]; then
      files=$(rg -l -i -- "$word" .)
    else
      files=$(rg -l -i --glob "*.${ext}" -- "$word" .)
    fi
  else
    if [ "$ext" = "*" ]; then
      files=$(find . -type f -exec grep -l -i "$word" {} \;)
    else
      files=$(find . -type f -name "*.${ext}" -exec grep -l -i "$word" {} \;)
    fi
  fi

  if [ -z "$files" ]; then
    echo "No results found"
    return 1
  fi

  echo "$files" | fzf \
    --preview "rg -i --color=always -C 5 -- \"$word\" {}" \
    --preview-window=right:60%:wrap \
    --header "Enter: open with editor | Ctrl-Y: copy path" \
    --bind "enter:execute(${EDITOR:-vim} {})" \
    --bind "ctrl-y:execute-silent(echo {} | xclip -selection clipboard 2>/dev/null || echo {} | pbcopy 2>/dev/null || echo {} | wl-copy 2>/dev/null)"
}
