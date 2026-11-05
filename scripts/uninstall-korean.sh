#!/usr/bin/env bash
#
# uninstall-korean.sh — 이 저장소의 이전 한글 설정만 제거
#
# 사용법:
#   ./scripts/uninstall-korean.sh --dry-run   제거 대상 확인 (변경 없음)
#   ./scripts/uninstall-korean.sh             제거 + Hyprland reload/검증
#   ./scripts/uninstall-korean.sh --no-reload  파일만 정리
#
# fcitx5 config/profile, 패키지, 서비스, Omarchy의 한국어 키보드 배열은 유지한다.
# --fcitx 같은 백업 복원 옵션은 없다. 현재 정상 동작하는 한글 입력을 보존한다.
# 제거할 파일은 *.bak.<timestamp>, 위젯은 *.bak.<timestamp>.tar.gz로 백업한다.
# --config-dir DIR / --bin-dir DIR: 기본 ~/.config / ~/.local/bin 대신 사용할 경로.
# 원본: old/korean/scripts/setup-korean.sh의 run_remove 및 관련 함수.
set -euo pipefail

DRY_RUN=0
NO_RELOAD=0
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_DIR="$HOME/.local/bin"
TS="$(date +%Y%m%d%H%M%S%N)"
HYPR_CHANGED=0
SHELL_CHANGED=0

usage() { awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }
die() { printf '[x] %s\n' "$*" >&2; exit 1; }
log() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

while (( $# )); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-reload) NO_RELOAD=1 ;;
    --config-dir|--bin-dir)
      flag=$1
      (( $# >= 2 )) && [[ -n $2 && $2 != --* ]] || die "$flag 경로 필요"
      case "$flag" in
        --config-dir) CONF_DIR=$2 ;;
        --bin-dir) BIN_DIR=$2 ;;
      esac
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "알 수 없는 옵션: $1 (--help 참고)" ;;
  esac
  shift
done
command -v python3 >/dev/null || die 'python3 필요'

HYPR_MAIN_LUA="$CONF_DIR/hypr/hyprland.lua"
FRAG_DIR="$CONF_DIR/minsoft1115/hypr"
WRAPPER="$BIN_DIR/omarchy-latin-launch"
SHELL_JSON="$CONF_DIR/omarchy/shell.json"
PLUGIN_ID=minsoft1115.fcitx
PLUGIN_DST="$CONF_DIR/omarchy/plugins/$PLUGIN_ID"
OMARCHY_ROOT="${OMARCHY_PATH:-/usr/share/omarchy}"

backup() {
  cp -a -- "$1" "$1.bak.$TS"
  log "백업: $1.bak.$TS"
}

remove_file() {
  [[ -e $1 || -L $1 ]] || return 0
  if (( DRY_RUN )); then
    log "제거 예정: $1"
  else
    backup "$1"
    rm -f -- "$1"
    log "삭제: $1"
  fi
}

# 원래 제거 함수처럼 마커 블록과 그 앞의 빈 줄 하나만 제거한다.
# 끝 마커가 없으면 파일 끝까지 지우지 않고 실패한다.
remove_hypr_block() {
  [[ -f $HYPR_MAIN_LUA ]] || return 0
  local changed
  changed=$(python3 - "$HYPR_MAIN_LUA" "$TS" "$DRY_RUN" <<'PY'
import pathlib, shutil, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
lines = text.splitlines(keepends=True)
out = []
inside = False
for line in lines:
    marker = line.rstrip('\r\n')
    if marker == '-- setup-korean:begin':
        if inside:
            raise SystemExit('중첩된 setup-korean 마커: 수동 확인 필요')
        inside = True
        if out and not out[-1].strip():
            out.pop()
    elif marker == '-- setup-korean:end':
        if not inside:
            raise SystemExit('시작 없는 setup-korean 마커: 수동 확인 필요')
        inside = False
    elif not inside:
        out.append(line)
if inside:
    raise SystemExit('끝없는 setup-korean 마커: 수동 확인 필요')
updated = ''.join(out)
if updated != text:
    if sys.argv[3] != '1':
        shutil.copy2(p, str(p) + '.bak.' + sys.argv[2])
        p.write_text(updated)
    print('changed')
PY
  )
  if [[ $changed == changed ]]; then
    HYPR_CHANGED=1
    log "setup-korean require 블록 제거$([[ $DRY_RUN == 1 ]] && echo ' 예정' || true): $HYPR_MAIN_LUA"
  fi
}

# 셸이 실행 중이지 않거나 플러그인을 이미 잊은 경우도 정리할 수 있도록
# 해당 ID만 설정에서 제거한다. 다른 위젯과 공식 입력 상태 표시는 보존한다.
remove_fcitx_widget() {
  local changed
  if [[ -f $SHELL_JSON ]]; then
    changed=$(python3 - "$SHELL_JSON" "$PLUGIN_ID" "$TS" "$DRY_RUN" <<'PY'
import json, pathlib, shutil, sys
p, plugin = pathlib.Path(sys.argv[1]), sys.argv[2]
data = json.loads(p.read_text())
before = json.dumps(data)
def keep(item):
    return (item.get('id') if isinstance(item, dict) else item) != plugin
layout = (data.get('bar') or {}).get('layout') or {}
for section, items in layout.items():
    if isinstance(items, list):
        layout[section] = [item for item in items if keep(item)]
for key in ('plugins', 'disabledPlugins'):
    if isinstance(data.get(key), list):
        data[key] = [item for item in data[key] if keep(item)]
if json.dumps(data) != before:
    if sys.argv[4] != '1':
        shutil.copy2(p, str(p) + '.bak.' + sys.argv[3])
        p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('changed')
PY
    )
    if [[ $changed == changed ]]; then
      SHELL_CHANGED=1
      log "바의 $PLUGIN_ID 등록 제거$([[ $DRY_RUN == 1 ]] && echo ' 예정' || true)"
    fi
  fi
  [[ -e $PLUGIN_DST || -L $PLUGIN_DST ]] || return 0
  [[ ! -L $PLUGIN_DST && -d $PLUGIN_DST ]] || { warn "위젯 경로가 디렉터리가 아님 — 보존: $PLUGIN_DST"; return 0; }
  if (( DRY_RUN )); then
    log "위젯 백업 및 제거 예정: $PLUGIN_DST"
  else
    tar -czf "$PLUGIN_DST.bak.$TS.tar.gz" -C "$(dirname "$PLUGIN_DST")" "$PLUGIN_ID"
    rm -rf -- "$PLUGIN_DST"
    SHELL_CHANGED=1
    log "위젯 삭제 (백업: $PLUGIN_DST.bak.$TS.tar.gz)"
  fi
}

# 공유 경로는 이전 설치기가 쓴 내용 그대로인 경우만 회수한다.
remove_shared_files() {
  local env_file="$CONF_DIR/environment.d/fcitx.conf"
  local autostart="$CONF_DIR/autostart/org.fcitx.Fcitx5.desktop"
  if [[ -f $env_file ]]; then
    if [[ -f $OMARCHY_ROOT/default/environment.d/10-omarchy-fcitx.conf ]] &&
       cmp -s "$env_file" <(printf 'INPUT_METHOD=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\nSDL_IM_MODULE=fcitx\n'); then
      remove_file "$env_file"
    else
      warn "수정된 파일이거나 공식 IM 환경변수가 없음 — 보존: $env_file"
    fi
  fi
  if [[ -f $autostart ]]; then
    if [[ -f $OMARCHY_ROOT/config/autostart/org.fcitx.Fcitx5.desktop ]]; then
      log "Omarchy도 사용하는 자동시작 억제 설정 유지: $autostart"
    elif cmp -s "$autostart" <(printf '[Desktop Entry]\nHidden=true\n'); then
      remove_file "$autostart"
    else
      warn "수정된 자동시작 설정 — 보존: $autostart"
    fi
  fi
}

remove_hypr_block
remove_file "$FRAG_DIR/korean-input.lua"
remove_file "$FRAG_DIR/korean-bindings.lua"

# 마커 없이 input.lua/bindings.lua를 직접 수정했던 더 오래된 설치는 자동 추정하지 않는다.
if grep -qF 'omarchy-latin-launch' "$CONF_DIR/hypr/bindings.lua" 2>/dev/null; then
  warn "기존 bindings.lua가 래퍼를 참조함 — 래퍼 보존, 수동 정리 필요"
elif [[ -f $WRAPPER ]]; then
  if grep -qF '# fcitx5 입력을 영문으로 강제 전환한 뒤 지정한 명령 실행' "$WRAPPER"; then
    remove_file "$WRAPPER"
  else
    warn "이전 설치기의 래퍼인지 확인 불가 — 보존: $WRAPPER"
  fi
fi
if grep -qF 'korean:ralt_hangul' "$CONF_DIR/hypr/input.lua" 2>/dev/null; then
  warn 'input.lua의 마커 없는 korean:ralt_hangul 설정은 수동 정리 필요'
fi

remove_shared_files
remove_fcitx_widget

if (( ! DRY_RUN && ! NO_RELOAD )); then
  if (( HYPR_CHANGED )); then
    if command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1; then
      errors=$(hyprctl configerrors) || die 'Hyprland 오류 조회 실패'
      [[ -z ${errors//[[:space:]]/} ]] || die "Hyprland 설정 오류: $errors"
      log 'Hyprland reload 및 configerrors 검사 완료'
    else
      warn 'Hyprland reload 불가 — 세션에서 hyprctl reload 후 hyprctl configerrors 확인 필요'
    fi
  fi
  if (( SHELL_CHANGED )) && command -v omarchy-shell >/dev/null; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || warn '셸 플러그인 재검색 불가 — 재로그인 시 반영'
  fi
fi
log 'fcitx5 config/profile·패키지·서비스·공식 키보드 배열은 유지됩니다.'
if (( DRY_RUN )); then
  log 'dry-run 완료 — 변경 없음'
else
  log '이전 한글 설정 정리 완료. 환경변수 변경은 재로그인 후 반영됩니다.'
fi
