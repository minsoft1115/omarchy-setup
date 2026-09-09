#!/usr/bin/env bash
#
# install-lsp.sh — language servers plus Grok and Claude CLIs
# ==============================================================================
# Usage:
#   ./scripts/install-lsp.sh status     Show current state (default)
#   ./scripts/install-lsp.sh install    Install binaries, wire Grok and Claude
#   ./scripts/install-lsp.sh remove     Take back what this step added
#   ./scripts/install-lsp.sh diff       source vs installed Grok lsp.json
#   ./scripts/install-lsp.sh --help     This help
#
# Every action is idempotent: re-running is safe, and anything already done is
# reported as "skipped".
#
# Omarchy 4.0+ is required: mise and `omarchy pkg add` are stock there, and
# those are two of the three install channels. The third is `dotnet tool`.
#
# What install does, in order:
#   1. omarchy pkg add clang (clangd lives in that package). clang is never
#      recorded as ours — it is a compiler, and remove must not drop it.
#      rust-analyzer used to be a pacman package too; that pulled extra/rust
#      as a second toolchain next to mise. It now comes from rustup
#      (mise rust). A leftover pacman rust-analyzer this step once installed
#      is dropped on the next install, with the unused rust/rust-src/lld
#      deps.
#   2. mise use -g for runtimes (node, go, dotnet) and the LSP tools. A
#      tool already on PATH is left alone and not written into
#      ~/.config/mise/config.toml.
#   2b. Grok and Claude usable the Omarchy way: `omarchy-mise-install`
#      writes ~/.local/bin/{claude,grok} wrappers (Super key / PATH), then
#      mise actually installs the packages so the first launch is not a
#      download. The default coding agent is not changed — both stay
#      launchable; `omarchy default agent` is the user's pick.
#   3. dotnet tool install -g roslyn-language-server (Grok) and csharp-ls
#      (Claude's official csharp-lsp plugin). Symlinks land in ~/.local/bin
#      so a shell without ~/.dotnet/tools on PATH still finds them.
#   4. ~/.grok/lsp.json from lsp/lsp.json, with __HOME__ expanded, and
#      lsp_tools = true in ~/.grok/config.toml (other keys are kept).
#   5. Claude official LSP plugins, so Claude Code actually starts the
#      servers. basedpyright provides the pyright-langserver the pyright
#      plugin calls.
#
# Layout:
#   source (edit here)  ./lsp/lsp.json
#   Grok config         ~/.grok/lsp.json
#   Grok feature flag   ~/.grok/config.toml  ([features] lsp_tools only)
#   ownership ledger    ~/.local/state/minsoft1115/lsp/
#
# Removing takes back the ledger — mise keys this step added (including
# rust, if rust-analyzer needed a toolchain and none was on PATH), a leftover
# pacman rust-analyzer if the old step installed it, the two dotnet tools
# if we installed them, ~/.local/bin symlinks this step created, the Claude
# plugins we enabled, lsp.json if it still matches, and lsp_tools if we
# turned it on. clang is never dropped. node, go, rust, and a mise tool
# that were already on PATH were never recorded and stay. An lsp.json that
# differs from the source was edited by hand and is left alone.
#
# Channels, one per server:
#   omarchy pkg add     clangd (clang)
#   mise / rustup       rust-analyzer (rustup component on mise rust)
#   mise                basedpyright, bash-language-server, typescript,
#                       typescript-language-server, gopls, lua-language-server,
#                       marksman, plus grok and claude CLIs
#   dotnet tool         roslyn-language-server, csharp-ls
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Settings — pre-set any of these in the environment to override
# ==============================================================================
: "${TS:=$(date +%s)}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"

SRC="${LSP_SRC:-$REPO_DIR/lsp/lsp.json}"
GROK_HOME="${GROK_HOME:-$HOME/.grok}"
DST="$GROK_HOME/lsp.json"
GROK_TOML="$GROK_HOME/config.toml"
STATE_DIR="${LSP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/minsoft1115/lsp}"
MISE_ADDED="$STATE_DIR/mise-added"
PKG_ADDED="$STATE_DIR/pkg-added"
DOTNET_ADDED="$STATE_DIR/dotnet-added"
DOTNET_LINKS="$STATE_DIR/dotnet-links"
CLAUDE_ADDED="$STATE_DIR/claude-plugins-added"
GROK_FLAG="$STATE_DIR/grok-lsp-tools-set"
WRAPPERS_ADDED="$STATE_DIR/wrappers-added"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
DOTNET_TOOLS="${DOTNET_TOOLS:-$HOME/.dotnet/tools}"

PACKAGES="${LSP_PACKAGES:-clang}"
# clang is a compiler; never pkg-drop it. rust-analyzer stays in PKG_OWNED
# so remove/migrate can still drop a leftover pacman copy this step used to add.
PKG_OWNED="${LSP_PKG_OWNED:-rust-analyzer}"

# spec@version. A binary already on PATH skips mise use, so this does not
# rewrite an existing global pin.
MISE_RUNTIMES=(
  node@latest
  go@latest
  dotnet@latest
)
MISE_LSPS=(
  lua-language-server@latest
  marksman@latest
  npm:basedpyright@latest
  npm:bash-language-server@latest
  npm:typescript@latest
  npm:typescript-language-server@latest
  go:golang.org/x/tools/gopls@v0.23.0
)
# Omarchy's own wrappers. First field is the mise package, second the
# command name dropped into ~/.local/bin (omarchy-mise-install args).
AI_AGENTS=(
  "claude claude"
  "npm:@xai-official/grok grok"
)

DOTNET_PKGS=(roslyn-language-server csharp-ls)
CLAUDE_PLUGINS=(clangd-lsp rust-analyzer-lsp pyright-lsp gopls-lsp lua-lsp typescript-lsp csharp-lsp)
CLAUDE_MARKETPLACE="${CLAUDE_MARKETPLACE:-anthropics/claude-plugins-official}"

# Commands this step installs. install.sh does not parse this list — its
# "is it current" check is the json file, the two wrappers, and lsp_tools.
LSP_BINS=(
  clangd
  rust-analyzer
  basedpyright-langserver
  bash-language-server
  typescript-language-server
  gopls
  lua-language-server
  marksman
  roslyn-language-server
  csharp-ls
)
AI_BINS=(claude grok)

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

backup() { [ -f "$1" ] || return 0; cp -a "$1" "$1.bak.$TS"; log "backed up: $1.bak.$TS"; }

usage() { awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

# ==============================================================================
# Helpers
# ==============================================================================
require_omarchy_4() {
  if ! command -v omarchy >/dev/null 2>&1; then
    warn "omarchy not found — Omarchy 4.0+ is required for pkg add and mise"
    return 0
  fi
  local ver major
  ver="$(omarchy version 2>/dev/null || true)"
  major="${ver%%.*}"
  case "$major" in
    ''|*[!0-9]*) warn "could not parse omarchy version ($ver) — continuing" ;;
    *)
      if [ "$major" -lt 4 ]; then
        die "Omarchy 4.0+ required (found: $ver)"
      fi
      ;;
  esac
}

# The csharp log directory is machine-local. The committed file holds
# __HOME__; install writes the expanded copy, and in_sync expands the
# source the same way so the two stay comparable.
expand_lsp_json() {
  python3 -c 'import os, pathlib, sys
src = pathlib.Path(sys.argv[1])
sys.stdout.write(src.read_text().replace("__HOME__", os.environ["HOME"]))' "$1"
}

in_sync() {
  [ -f "$DST" ] || return 1
  [ -f "$SRC" ] || return 1
  expand_lsp_json "$SRC" | cmp -s - "$DST"
}

write_lsp_json() {
  local tmp
  tmp="$(mktemp "$DST.XXXXXX")"
  expand_lsp_json "$SRC" >"$tmp"
  mv "$tmp" "$DST"
}

record() {
  local file="$1" name="$2"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -qxF "$name" "$file"; then
    return 0
  fi
  printf '%s\n' "$name" >>"$file"
}

recorded() {
  [ -f "$1" ] && grep -qxF "$2" "$1"
}

unrecord() {
  local file="$1" name="$2" tmp
  [ -f "$file" ] || return 0
  tmp="$(mktemp)"
  grep -vxF "$name" "$file" >"$tmp" || true
  if [ -s "$tmp" ]; then
    mv "$tmp" "$file"
  else
    rm -f "$file" "$tmp"
  fi
}

# The binary a mise tool spec is supposed to put on PATH. Specs are
# name@version; the @version is stripped before this is called.
mise_bin() {
  case "$1" in
    lua-language-server)            echo lua-language-server ;;
    marksman)                       echo marksman ;;
    npm:basedpyright)               echo basedpyright-langserver ;;
    npm:bash-language-server)       echo bash-language-server ;;
    npm:typescript)                 echo tsc ;;
    npm:typescript-language-server) echo typescript-language-server ;;
    go:golang.org/x/tools/gopls)    echo gopls ;;
    node)                           echo node ;;
    rust)                           echo rustc ;;
    rust-analyzer)                  echo rust-analyzer ;;
    go)                             echo go ;;
    dotnet)                         echo dotnet ;;
    claude)                         echo claude ;;
    npm:@xai-official/grok)         echo grok ;;
    *)                              echo "${1##*:}" ;;
  esac
}

reshim() { command -v mise >/dev/null 2>&1 && mise reshim >/dev/null 2>&1 || true; }

# Strip a trailing @version, but keep npm:@scope/name intact.
spec_name() {
  local spec="$1" ver
  ver="${spec##*@}"
  case "$ver" in
    */*) printf '%s' "$spec" ;;
    "$spec") printf '%s' "$spec" ;;
    *)   printf '%s' "${spec%@*}" ;;
  esac
}

# The Omarchy agent wrapper at ~/.local/bin/$cmd is a script that runs
# `mise use -g` on first launch. command -v finding it does not mean the
# package behind it is installed.
is_local_bin_wrapper() {
  local bin="$1" found dest
  found="$(command -v "$bin" 2>/dev/null || true)"
  dest="$LOCAL_BIN/$bin"
  [ -n "$found" ] || return 1
  [ -f "$dest" ] || return 1
  grep -qF 'mise use -g' "$dest" || return 1
  [ "$found" = "$dest" ] || [ "$(readlink -f -- "$found")" = "$(readlink -f -- "$dest")" ]
}

mise_pkg_installed() {
  command -v mise >/dev/null 2>&1 || return 1
  mise where "$1" >/dev/null 2>&1
}

install_mise_spec() {
  local spec="$1" name bin
  name="$(spec_name "$spec")"
  bin="$(mise_bin "$name")"
  if command -v "$bin" >/dev/null 2>&1 && ! is_local_bin_wrapper "$bin"; then
    log "mise: $name already on PATH ($bin) — skipped"
    return 0
  fi
  if mise_pkg_installed "$name"; then
    log "mise: $name already installed — skipped"
    return 0
  fi
  if ! command -v mise >/dev/null 2>&1; then
    warn "mise not found — install $spec yourself"
    return 0
  fi
  log "mise: use -g $spec"
  if mise use -g --yes "$spec"; then
    reshim
    record "$MISE_ADDED" "$name"
  else
    warn "mise use $spec failed — continuing"
  fi
}

# Same wrapper omarchy-mise-install writes. Used when that helper is
# missing, so a box without it still gets `claude` / `grok` on PATH.
write_agent_wrapper() {
  local pkg cmd dest
  pkg="$1"
  cmd="$2"
  dest="$LOCAL_BIN/$cmd"
  mkdir -p "$LOCAL_BIN"
  cat >"$dest" <<EOF
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet "$pkg" || exit 1
exec mise x "$pkg" -- "$cmd" "\$@"
EOF
  chmod +x "$dest"
}

# Make one coding agent launchable the way Omarchy does, then install the
# package now so the wrapper's first run is not a download.
ensure_ai_agent() {
  local pkg="$1" cmd="$2" dest had=0
  dest="$LOCAL_BIN/$cmd"
  [ -x "$dest" ] && had=1

  if [ "$had" = 1 ]; then
    log "agent: $cmd wrapper already at $dest — skipped"
  elif command -v omarchy-mise-install >/dev/null 2>&1; then
    log "agent: omarchy-mise-install $pkg $cmd"
    if omarchy-mise-install "$pkg" "$cmd"; then
      record "$WRAPPERS_ADDED" "$cmd"
    else
      warn "omarchy-mise-install $cmd failed — continuing"
    fi
  else
    log "agent: writing $dest (no omarchy-mise-install)"
    write_agent_wrapper "$pkg" "$cmd"
    record "$WRAPPERS_ADDED" "$cmd"
  fi

  install_mise_spec "$pkg@latest"
}

# Drop a pacman package only when it was installed as a dependency and
# nothing requires it anymore — the extra/rust toolchain that used to
# come in with extra/rust-analyzer.
drop_if_orphan_dep() {
  local p="$1" reason req
  command -v omarchy >/dev/null 2>&1 || return 0
  omarchy pkg missing "$p" >/dev/null 2>&1 && return 0
  reason="$(LC_ALL=C pacman -Qi "$p" 2>/dev/null | awk -F': *' '/^Install Reason/{print $2}')"
  req="$(LC_ALL=C pacman -Qi "$p" 2>/dev/null | awk -F': *' '/^Required By/{print $2}')"
  case "$reason" in *dependency*) ;; *) return 0 ;; esac
  case "$req" in *None*) ;; *) return 0 ;; esac
  log "packages: dropping unused $p (came in with pacman rust-analyzer)"
  omarchy pkg drop "$p" || warn "omarchy pkg drop $p failed — continuing"
}

# The old step installed extra/rust-analyzer, which pulls extra/rust as a
# second toolchain next to mise. Drop that copy and the unused deps.
drop_pacman_rust_analyzer() {
  command -v omarchy >/dev/null 2>&1 || return 0
  if omarchy pkg missing rust-analyzer >/dev/null 2>&1; then
    unrecord "$PKG_ADDED" rust-analyzer
    return 0
  fi
  log "packages: dropping pacman rust-analyzer (rust-analyzer now comes from mise/rustup)"
  if omarchy pkg drop rust-analyzer; then
    drop_if_orphan_dep rust-src
    drop_if_orphan_dep rust
    drop_if_orphan_dep lld
    unrecord "$PKG_ADDED" rust-analyzer
  else
    warn "omarchy pkg drop rust-analyzer failed — re-run install from a terminal to finish"
  fi
}

ensure_rust_analyzer() {
  if command -v rust-analyzer >/dev/null 2>&1; then
    log "mise: rust-analyzer already on PATH — skipped"
    return 0
  fi
  install_mise_spec rust@latest
  reshim
  if command -v rustup >/dev/null 2>&1; then
    log "rustup: component add rust-analyzer"
    rustup component add rust-analyzer \
      || warn "rustup component add rust-analyzer failed — continuing"
  elif command -v mise >/dev/null 2>&1; then
    log "mise: use -g rust-analyzer@latest (no rustup)"
    install_mise_spec rust-analyzer@latest
  else
    warn "no rustup or mise — install rust-analyzer yourself"
  fi
}

run_dotnet() {
  if command -v dotnet >/dev/null 2>&1; then
    dotnet "$@"
  elif command -v mise >/dev/null 2>&1; then
    mise exec -- dotnet "$@"
  else
    return 1
  fi
}

dotnet_has() {
  run_dotnet tool list -g 2>/dev/null | awk 'NR>2 {print $1}' | grep -qxF "$1"
}

link_dotnet_tool() {
  local name="$1" src dest
  src="$DOTNET_TOOLS/$name"
  dest="$LOCAL_BIN/$name"
  if [ ! -e "$src" ]; then
    warn "dotnet tool $name installed but $src is missing — no symlink"
    return 0
  fi
  mkdir -p "$LOCAL_BIN"
  if [ -L "$dest" ] && [ "$(readlink -f -- "$dest")" = "$(readlink -f -- "$src")" ]; then
    log "symlink: $dest already points at $src — skipped"
    return 0
  fi
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    warn "symlink: $dest exists and is not a symlink — left alone"
    return 0
  fi
  ln -sfn "$src" "$dest"
  record "$DOTNET_LINKS" "$name"
  log "symlink: $dest -> $src"
}

unlink_dotnet_tool() {
  local name="$1" dest src
  dest="$LOCAL_BIN/$name"
  src="$DOTNET_TOOLS/$name"
  [ -L "$dest" ] || return 0
  if [ "$(readlink -f -- "$dest")" = "$(readlink -f -- "$src")" ] ||
     [ "$(readlink -- "$dest")" = "$src" ]; then
    rm -f "$dest"
    log "removed symlink $dest"
  else
    warn "symlink $dest does not point at $src — left alone"
  fi
}

bins_status() {
  local out="" b state
  for b in "${LSP_BINS[@]}" "${AI_BINS[@]}"; do
    command -v "$b" >/dev/null 2>&1 && state=ok || state=MISSING
    out="$out $b($state)"
  done
  printf '%s' "${out# }"
}

packages_status() {
  command -v omarchy >/dev/null 2>&1 || { echo "unknown (no omarchy)"; return 0; }
  local out="" pkg state
  for pkg in $PACKAGES; do
    omarchy pkg missing "$pkg" >/dev/null 2>&1 && state=MISSING || state=ok
    out="$out $pkg($state)"
  done
  printf '%s' "${out# }"
}

grok_lsp_tools_on() {
  [ -f "$GROK_TOML" ] && grep -Eq '^[[:space:]]*lsp_tools[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$GROK_TOML"
}

# Returns 0 if we changed the file, 1 if it was already true.
set_grok_lsp_tools() {
  python3 - "$GROK_TOML" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
p.parent.mkdir(parents=True, exist_ok=True)
text = p.read_text() if p.exists() else ""
if re.search(r"(?m)^[ \t]*lsp_tools[ \t]*=[ \t]*true[ \t]*$", text):
    sys.exit(1)
if re.search(r"(?m)^[ \t]*lsp_tools[ \t]*=", text):
    p.write_text(re.sub(r"(?m)^[ \t]*lsp_tools[ \t]*=[ \t]*.*$", "lsp_tools = true", text))
    sys.exit(0)
if re.search(r"(?m)^\[features\][ \t]*$", text):
    p.write_text(re.sub(r"(?m)^\[features\][ \t]*$", "[features]\nlsp_tools = true", text, count=1))
    sys.exit(0)
if text and not text.endswith("\n"):
    text += "\n"
p.write_text(text + "\n[features]\nlsp_tools = true\n")
PY
}

unset_grok_lsp_tools() {
  python3 - "$GROK_TOML" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
if not p.exists():
    sys.exit(0)
text = p.read_text()
new = re.sub(r"(?m)^[ \t]*lsp_tools[ \t]*=[ \t]*.*$", "lsp_tools = false", text)
if new != text:
    p.write_text(new)
PY
}

claude_plugin_installed() {
  local id="$1" json
  command -v claude >/dev/null 2>&1 || return 1
  json="$(claude plugin list --json 2>/dev/null || true)"
  [ -n "$json" ] || return 1
  printf '%s' "$json" | jq -e --arg id "$id" '
    [.. | strings] | any(. == $id or startswith($id + "@"))
  ' >/dev/null 2>&1
}

ensure_claude_marketplace() {
  command -v claude >/dev/null 2>&1 || return 1
  if claude plugin marketplace list 2>/dev/null | grep -q 'claude-plugins-official'; then
    return 0
  fi
  log "claude: adding marketplace $CLAUDE_MARKETPLACE"
  claude plugin marketplace add "$CLAUDE_MARKETPLACE" --scope user \
    || warn "could not add the Claude plugin marketplace — plugin installs may fail"
}

# ==============================================================================
# Actions
# ==============================================================================
do_install() {
  [ -f "$SRC" ] || die "source missing: $SRC (run from a clone of the repo)"
  command -v python3 >/dev/null 2>&1 || die "python3 is required to expand $SRC"
  require_omarchy_4

  # 1. Arch packages
  if [ "${SKIP_PACKAGES:-0}" = 1 ]; then
    log "packages: skipped (--skip-packages)"
  elif ! command -v omarchy >/dev/null 2>&1; then
    warn "omarchy not found — install these yourself: $PACKAGES"
  else
    local pkg
    for pkg in $PACKAGES; do
      if ! omarchy pkg missing "$pkg" >/dev/null 2>&1; then
        log "packages: $pkg already installed — skipped"
        continue
      fi
      log "packages: installing $pkg"
      if omarchy pkg add "$pkg"; then
        case " $PKG_OWNED " in
          *" $pkg "*) record "$PKG_ADDED" "$pkg" ;;
        esac
      else
        warn "omarchy pkg add $pkg failed — continuing"
      fi
    done
  fi

  # The previous revision of this step pkg-added extra/rust-analyzer, which
  # pulled extra/rust as a second toolchain. Move off that copy.
  if recorded "$PKG_ADDED" rust-analyzer && [ "${SKIP_PACKAGES:-0}" != 1 ]; then
    drop_pacman_rust_analyzer
  fi

  # 2. mise: runtimes and LSP servers
  local spec
  for spec in "${MISE_RUNTIMES[@]}" "${MISE_LSPS[@]}"; do
    install_mise_spec "$spec"
  done
  ensure_rust_analyzer
  reshim

  # 2b. Grok and Claude: Omarchy wrappers + the packages behind them
  local agent_pkg agent_cmd
  for spec in "${AI_AGENTS[@]}"; do
    agent_pkg="${spec%% *}"
    agent_cmd="${spec##* }"
    ensure_ai_agent "$agent_pkg" "$agent_cmd"
  done
  reshim

  # 3. dotnet tools + ~/.local/bin links
  local tool
  for tool in "${DOTNET_PKGS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1 || dotnet_has "$tool"; then
      log "dotnet: $tool already installed — skipped"
      link_dotnet_tool "$tool"
      continue
    fi
    if ! run_dotnet --info >/dev/null 2>&1; then
      warn "dotnet not found — install $tool yourself: dotnet tool install -g $tool"
      continue
    fi
    log "dotnet: tool install -g $tool"
    if run_dotnet tool install -g "$tool"; then
      record "$DOTNET_ADDED" "$tool"
      link_dotnet_tool "$tool"
    else
      warn "dotnet tool install $tool failed — continuing"
    fi
  done
  mkdir -p "$HOME/.local/state/roslyn-language-server"

  # 4. Grok: lsp.json + lsp_tools
  mkdir -p "$GROK_HOME"
  if in_sync; then
    log "Grok lsp.json already current — skipped"
  else
    backup "$DST"
    write_lsp_json
    log "installed: $SRC -> $DST"
  fi
  if grok_lsp_tools_on; then
    log "Grok lsp_tools already true — skipped"
  else
    backup "$GROK_TOML"
    if set_grok_lsp_tools; then
      mkdir -p "$STATE_DIR"
      : >"$GROK_FLAG"
      log "enabled lsp_tools in $GROK_TOML"
    else
      log "Grok lsp_tools already true — skipped"
    fi
  fi

  # 5. Claude official LSP plugins
  if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not on PATH — skip plugin install (re-run after mise finishes)"
  else
    ensure_claude_marketplace
    local plug
    for plug in "${CLAUDE_PLUGINS[@]}"; do
      if claude_plugin_installed "$plug"; then
        log "claude plugin: $plug already installed — skipped"
        continue
      fi
      log "claude plugin: install $plug"
      if claude plugin install "$plug" -s user -y; then
        record "$CLAUDE_ADDED" "$plug"
      else
        warn "claude plugin install $plug failed — continuing"
      fi
    done
  fi

  log "done. grok and claude are on PATH via ~/.local/bin; Grok reads lsp.json on its next start; Claude Code sessions already open need a restart."
}

do_remove() {
  local name dest

  # Claude plugins we enabled
  if [ -f "$CLAUDE_ADDED" ] && command -v claude >/dev/null 2>&1; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      log "claude plugin: uninstall $name"
      claude plugin uninstall "$name" -y \
        || warn "claude plugin uninstall $name failed — continuing"
    done <"$CLAUDE_ADDED"
    rm -f "$CLAUDE_ADDED"
  elif [ -f "$CLAUDE_ADDED" ]; then
    warn "claude CLI missing — left plugins listed in $CLAUDE_ADDED"
  else
    log "claude plugins: nothing this step recorded — skipped"
  fi

  # Grok lsp.json
  if [ ! -f "$DST" ]; then
    log "nothing at $DST — skipped"
  elif in_sync; then
    backup "$DST"
    rm -f "$DST"
    log "removed $DST"
  else
    warn "installed lsp.json differs from the source (hand-edited) — left alone"
    ls -1t "$DST".bak.* 2>/dev/null | head -1 | sed 's/^/      newest backup: /' || true
  fi

  # lsp_tools only if we turned it on
  if [ -f "$GROK_FLAG" ]; then
    backup "$GROK_TOML"
    unset_grok_lsp_tools
    rm -f "$GROK_FLAG"
    log "set lsp_tools = false in $GROK_TOML"
  else
    log "Grok lsp_tools: not flipped by this step — skipped"
  fi

  # Symlinks this step created, including for a tool that was already there.
  if [ -f "$DOTNET_LINKS" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      unlink_dotnet_tool "$name"
    done <"$DOTNET_LINKS"
    rm -f "$DOTNET_LINKS"
  fi

  # dotnet tools we installed
  if [ -f "$DOTNET_ADDED" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      unlink_dotnet_tool "$name"
      if command -v dotnet >/dev/null 2>&1 || command -v mise >/dev/null 2>&1; then
        log "dotnet: tool uninstall $name"
        run_dotnet tool uninstall -g "$name" \
          || warn "dotnet tool uninstall $name failed — continuing"
      else
        warn "dotnet not found — remove $name yourself"
      fi
    done <"$DOTNET_ADDED"
    rm -f "$DOTNET_ADDED"
  else
    log "dotnet tools: nothing this step recorded — skipped"
  fi

  # Wrappers we created. Stock Omarchy ones are not on the ledger.
  if [ -f "$WRAPPERS_ADDED" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      dest="$LOCAL_BIN/$name"
      if [ -f "$dest" ] && grep -qF 'mise use -g' "$dest"; then
        rm -f "$dest"
        log "removed agent wrapper $dest"
      else
        log "agent wrapper $dest not ours or already gone — skipped"
      fi
    done <"$WRAPPERS_ADDED"
    rm -f "$WRAPPERS_ADDED"
  else
    log "agent wrappers: nothing this step recorded — skipped"
  fi

  # mise tools we added
  if [ -f "$MISE_ADDED" ] && command -v mise >/dev/null 2>&1; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      log "mise: unuse -g $name"
      mise unuse -g --yes "$name" \
        || warn "mise unuse $name failed — continuing"
    done <"$MISE_ADDED"
    reshim
    rm -f "$MISE_ADDED"
  elif [ -f "$MISE_ADDED" ]; then
    warn "mise not found — left tools listed in $MISE_ADDED"
  else
    log "mise: nothing this step recorded — skipped"
  fi

  # Leftover pacman rust-analyzer from the old step. clang is never dropped.
  if [ -f "$PKG_ADDED" ]; then
    if command -v omarchy >/dev/null 2>&1; then
      if recorded "$PKG_ADDED" rust-analyzer; then
        drop_pacman_rust_analyzer
      fi
      if [ -f "$PKG_ADDED" ]; then
        while IFS= read -r name; do
          [ -n "$name" ] || continue
          [ "$name" = rust-analyzer ] && continue
          case " $PKG_OWNED " in
            *" $name "*)
              log "packages: dropping $name"
              omarchy pkg drop "$name" \
                || warn "omarchy pkg drop $name failed — continuing"
              ;;
            *)
              warn "packages: $name is not owned by this step — left installed"
              ;;
          esac
        done <"$PKG_ADDED"
      fi
    else
      warn "omarchy not found — left packages listed in $PKG_ADDED"
    fi
    rm -f "$PKG_ADDED"
  else
    log "packages: nothing this step recorded — skipped"
  fi

  rmdir "$STATE_DIR" 2>/dev/null || true
  log "done. clang was left alone. mise tools this step recorded were unuse'd; anything already on PATH was not."
}

do_diff() {
  [ -f "$SRC" ] || die "source missing: $SRC"
  if [ ! -f "$DST" ]; then
    echo "--- not installed ($DST)"
  elif in_sync; then
    log "installed Grok lsp.json matches the source"
  else
    expand_lsp_json "$SRC" | diff -u "$DST" - || true
  fi
}

do_status() {
  echo "source (edit here) : $SRC ($([ -f "$SRC" ] && echo present || echo missing))"
  echo "Grok lsp.json      : $DST ($([ -f "$DST" ] && echo present || echo missing))"
  echo "in sync with source: $(in_sync && echo yes || echo no)"
  echo "Grok lsp_tools     : $(grok_lsp_tools_on && echo true || echo false)"
  echo "packages           : $(packages_status)"
  echo "binaries           : $(bins_status)"
  echo "AI wrappers        : claude($([ -x "$LOCAL_BIN/claude" ] && echo ok || echo MISSING)) grok($([ -x "$LOCAL_BIN/grok" ] && echo ok || echo MISSING))"
  if command -v claude >/dev/null 2>&1; then
    local plug extra=""
    for plug in "${CLAUDE_PLUGINS[@]}"; do
      if claude_plugin_installed "$plug"; then
        extra="$extra $plug(ok)"
      else
        extra="$extra $plug(MISSING)"
      fi
    done
    echo "Claude plugins     :${extra}"
  else
    echo "Claude plugins     : unknown (no claude CLI)"
  fi
  echo "ownership ledger   : $STATE_DIR"
}

# ==============================================================================
# Entry point
# ==============================================================================
SKIP_PACKAGES=0
ACTION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-packages) SKIP_PACKAGES=1 ;;
    --help|-h|help)  usage; exit 0 ;;
    -*)              echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    *)               [ -z "$ACTION" ] || { echo "only one action allowed: $ACTION, $1" >&2; exit 2; }
                     ACTION="$1" ;;
  esac
  shift
done

case "${ACTION:-status}" in
  install|setup|apply|sync) do_install ;;
  remove|uninstall)         do_remove ;;
  diff)                     do_diff ;;
  status)                   do_status ;;
  *) echo "unknown action: $ACTION (see --help)" >&2; exit 2 ;;
esac
