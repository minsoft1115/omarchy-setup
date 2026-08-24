# mcat - cat that renders markdown
# Usage:
#   mcat <file> [file...]   # markdown goes through glow, anything else bat
#   ... | mcat              # renders the stream as markdown
#
# Both renderers page only when the output is a terminal, so `mcat x.md | head`
# still behaves like cat. Renderer flags are not passed through -- call glow or
# bat directly when you need them.

mcat() {
  # Nothing named: render whatever is on stdin, which is the only thing there
  # is to render. A terminal on stdin means nothing was piped in either.
  if [ $# -eq 0 ]; then
    if [ -t 0 ]; then
      echo "Usage: mcat <file> [file...]"
      return 1
    fi
    if command -v glow >/dev/null 2>&1; then
      glow -p -
    else
      bat --paging=always -l md
    fi
    return
  fi

  local f lower
  for f in "$@"; do
    if [ ! -f "$f" ]; then
      echo "mcat: not a file: $f" >&2
      return 1
    fi
    lower="${f,,}"
    case "$lower" in
      *.md | *.markdown)
        if command -v glow >/dev/null 2>&1; then
          # The file arrives on stdin, not as an argument: glow renders piped
          # input in preference to a named file, so `... | mcat x.md` would
          # otherwise render the pipe and never open x.md.
          glow -p - < "$f"
        else
          bat --paging=always -- "$f"
        fi
        ;;
      *) bat --paging=always -- "$f" ;;
    esac || return
  done
}
