#!/usr/bin/env bash
#
# setup-korean.sh — Omarchy 한글 입력(fcitx5 + hangul) 세팅
# ==============================================================================
# 사용법:
#   ./scripts/setup-korean.sh            전체 세팅 (갓 설치한 머신용, 패키지 설치 포함)
#   ./scripts/setup-korean.sh --light    가벼운 재적용 (패키지/sudo 없이 키 설정만)
#   ./scripts/setup-korean.sh remove     되돌리기 (이 스크립트가 만든 것만)
#   ./scripts/setup-korean.sh --help     도움말
#
# 모두 idempotent — 여러 번 실행해도 안전하며, 이미 된 항목은 "건너뜀" 으로 표시.
#
# remove 가 지우는 것:
#   hyprland.lua 의 마커 블록, ~/.config/minsoft1115/hypr 의 조각,
#   영문-우선 래퍼, IM 환경변수 파일, XDG 자동시작 억제 파일.
#
# remove 가 건드리지 않는 것:
#   fcitx5 의 config/profile — 우리가 만든 게 아니라 고친 것이라, 되돌리면
#   한글 입력 자체가 사라질 수 있다. 백업 위치만 알려 준다. TriggerKeys 와
#   프로필까지 백업에서 되돌리려면 'remove --fcitx'.
#   설치한 패키지도 그대로 둔다.
#
# 전체(--full, 기본) 단계:
#   1. fcitx5 + 한글 패키지 설치            (sudo 필요할 수 있음)
#   2. IM 환경변수
#   3. XDG 자동시작 중복 방지
#   4. fcitx5 프로필 (keyboard-us + hangul)
#   5. fcitx5 단축키 (Control+space 제거, Hangul 유지)
#   6. 오른쪽 Alt = 한/영
#   7. 영문-우선 실행 래퍼
#   8. Super+Space / Super+Alt+Space 재바인딩 (메뉴를 영문으로 열기)
#   9. 적용 (Hyprland reload / fcitx5 재시작)
#
# 가벼운(--light) 단계: 5, 6, 9 만 수행.
#   이미 한글 입력이 구성된 시스템에서 아래만 재적용할 때 사용:
#     - 오른쪽 Alt = 한/영 키
#     - fcitx5 Control+space 트리거 제거 (tmux 충돌 해소)
#   패키지 설치도 sudo 도 건드리지 않는다.
#
# Hyprland 설정은 Lua(.lua) 형식만 다룬다. Lua 설정은 Hyprland 0.55 부터라서
# 그 미만이면 hypr 관련 단계(6, 8)만 메시지와 함께 건너뛴다 (fcitx5 쪽은 그대로 진행).
# fcitx5 자동시작 자체는 omarchy 기본 autostart 가 담당하므로 여기서 만들지 않음.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# 인자 파싱
# ==============================================================================
MODE=full
RESTORE_FCITX=0

# 헤더 주석 블록을 그대로 쓴다 (3번째 줄부터 주석이 끝나는 곳까지).
# 줄 번호를 박아 두면 헤더에 한 줄만 늘어도 도움말이 잘린다.
usage() {
  awk 'NR<3{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --light|-l) MODE=light ;;
    --full)     MODE=full ;;
    remove)     MODE=remove ;;
    --fcitx)    RESTORE_FCITX=1 ;;
    --help|-h)  usage; exit 0 ;;
    *)          echo "알 수 없는 옵션: $1 (--help 참고)" >&2; exit 2 ;;
  esac
  shift
done

# ==============================================================================
# 설정값 — 환경변수로 미리 지정하면 그 값을 존중
# ==============================================================================
: "${TS:=$(date +%s)}"
FCITX_DIR="${FCITX_DIR:-$HOME/.config/fcitx5}"
FCITX_CONF="${FCITX_CONF:-$FCITX_DIR/config}"
FCITX_PROFILE="${FCITX_PROFILE:-$FCITX_DIR/profile}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
# 조각 원본은 저장소 루트의 hypr/ 에 있고, 이 스크립트는 scripts/ 에 있다
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"
# 저장소의 Lua 조각들 → 사용자 폴더로 복사/생성하고, hyprland.lua 에는 require 만 넣는다
FRAG_SRC="${FRAG_SRC:-$REPO_DIR/hypr}"
FRAG_DIR="${FRAG_DIR:-$HOME/.config/minsoft1115/hypr}"
FRAG_MODULE="minsoft1115.hypr"
HYPR_MAIN_LUA="${HYPR_MAIN_LUA:-$HOME/.config/hypr/hyprland.lua}"
MARK_BEGIN="-- setup-korean:begin"
MARK_END="-- setup-korean:end"
# 예전 방식(input.lua / bindings.lua 에 직접 append)으로 깔린 흔적을 찾을 때 쓴다
LEGACY_INPUT_LUA="${LEGACY_INPUT_LUA:-$HOME/.config/hypr/input.lua}"
LEGACY_BIND_LUA="${LEGACY_BIND_LUA:-$HOME/.config/hypr/bindings.lua}"
OMARCHY_DEFAULTS="${OMARCHY_DEFAULTS:-/usr/share/omarchy/default/hypr}"
# Lua 설정을 지원하는 최소 Hyprland 버전 (0.55 에서 도입)
HYPR_LUA_MIN="${HYPR_LUA_MIN:-0.55.0}"
HYPR_LUA_OK=""
# hyprctl 로 현재 값을 못 읽을 때 쓰는 Omarchy 기본 kb_options
KB_OPTIONS_FALLBACK="${KB_OPTIONS_FALLBACK:-compose:caps,shift:both_capslock_cancel}"
LATIN_WRAPPER="${LATIN_WRAPPER:-omarchy-latin-launch}"   # ~/.local/bin (PATH 에 있음)
FCITX_WAS_RUNNING=0

PKGS=(fcitx5 fcitx5-hangul fcitx5-configtool fcitx5-gtk fcitx5-qt)
ENV_FILE="$HOME/.config/environment.d/fcitx.conf"
XDG_AUTOSTART="$HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
WRAPPER="$HOME/.local/bin/$LATIN_WRAPPER"

log()    { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn()   { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
backup() { [ -f "$1" ] || return 0; cp -a "$1" "$1.bak.$TS"; log "백업: $1.bak.$TS"; }

# ==============================================================================
# 공통 함수
# ==============================================================================

# ------------------------------------------------------------------------------
# 현재 적용 중인 kb_options 를 얻는다 (korean:ralt_hangul 은 제거한 "베이스" 값).
#   Lua 설정에서는 kb_options 를 지정하면 Omarchy 기본값이 통째로 교체되므로,
#   기본값을 그대로 유지하려면 현재 값을 읽어서 함께 적어 줘야 한다.
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Hyprland 가 Lua 설정을 지원하는 버전인지 (0.55+). 결과는 한 번만 판정해 캐시한다.
#   0 = 지원(또는 확인 불가 — 진행), 1 = 미지원(hypr 단계 건너뜀)
#
# 버전 문자열은 "Hyprland 0.56.2 built from ..." 처럼 나오며, -git 빌드나
# 두 자리 버전(0.55)도 있어 3자리로 맞춘 뒤 sort -V 로 비교한다.
# ------------------------------------------------------------------------------
hypr_lua_ok() {
  if [ -n "$HYPR_LUA_OK" ]; then
    [ "$HYPR_LUA_OK" = yes ]; return
  fi

  local v
  v="$(hyprctl version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"

  if [ -z "$v" ]; then
    warn "Hyprland 버전을 못 읽음 (세션 밖?) — Lua 설정 기준으로 계속 진행"
    HYPR_LUA_OK=yes
    return 0
  fi

  # 0.55 -> 0.55.0 (sort -V 는 0.55 를 0.55.0 보다 작게 본다)
  case "$v" in
    *.*.*) ;;
    *) v="$v.0" ;;
  esac

  if [ "$(printf '%s\n%s\n' "$HYPR_LUA_MIN" "$v" | sort -V | head -1)" = "$HYPR_LUA_MIN" ]; then
    HYPR_LUA_OK=yes
    return 0
  fi

  warn "Hyprland $v — Lua 설정은 $HYPR_LUA_MIN 이상에서만 쓸 수 있다 (이 버전은 hyprland.conf 방식)."
  warn "  → Hyprland 를 올린 뒤(omarchy update) 다시 실행하거나,"
  warn "    input.conf 에 'kb_options = ...,korean:ralt_hangul' 을 직접 넣어야 한다."
  warn "  fcitx5 설정은 그대로 진행한다."
  HYPR_LUA_OK=no
  return 1
}

hypr_base_kb_options() {
  local v=""
  if command -v hyprctl >/dev/null 2>&1; then
    v="$(hyprctl getoption input:kb_options 2>/dev/null | sed -n 's/^str:[[:space:]]*//p' | head -1)"
  fi
  [ -n "$v" ] || v="$KB_OPTIONS_FALLBACK"
  # 이미 들어 있으면 중복 방지를 위해 떼어 낸다
  printf '%s' "$v" | sed -E 's/(^|,)korean:ralt_hangul/\1/g; s/,,+/,/g; s/^,//; s/,$//'
}

# ------------------------------------------------------------------------------
# Lua 조각 하나를 사용자 폴더에 설치. 내용이 같으면 건드리지 않는다.
#   install_fragment <파일명> [원본경로]   원본 생략 시 $FRAG_SRC/<파일명>
# ------------------------------------------------------------------------------
install_fragment() {
  local name="$1" src="${2:-$FRAG_SRC/$1}"
  [ -f "$src" ] || { warn "조각 파일 없음: $src (저장소를 clone 해서 실행해야 한다)"; return 1; }
  mkdir -p "$FRAG_DIR"
  if cmp -s "$src" "$FRAG_DIR/$name"; then
    log "$name: 이미 최신 — 건너뜀"
  else
    cp -a "$src" "$FRAG_DIR/$name"
    log "설치: $FRAG_DIR/$name"
  fi
}

# ------------------------------------------------------------------------------
# hyprland.lua 의 마커 블록을 "설치된 조각들" 과 일치시킨다.
#   원본 설정 파일(input.lua / bindings.lua)은 건드리지 않고, 여기 한 곳에만
#   require 를 넣는다. 블록을 통째로 다시 쓰는 방식이라 조각이 늘거나 줄어도
#   따라가고, 지울 때는 마커 사이만 지우면 정확히 사라진다.
#   Omarchy 기본값 뒤에 로드돼야 이기므로 파일 끝에 붙인다.
# ------------------------------------------------------------------------------
sync_hypr_requires() {
  [ -f "$HYPR_MAIN_LUA" ] || { warn "$HYPR_MAIN_LUA 없음 — require 추가 건너뜀"; return 0; }

  local want="" name current
  for name in korean-input korean-bindings; do
    [ -f "$FRAG_DIR/$name.lua" ] && want="${want}require(\"$FRAG_MODULE.$name\")"$'\n'
  done
  want="${want%$'\n'}"

  current="$(sed -n "/^$MARK_BEGIN$/,/^$MARK_END$/p" "$HYPR_MAIN_LUA" | sed '1d;$d')"
  if [ "$current" = "$want" ]; then
    log "hyprland.lua: require 블록 이미 최신 — 건너뜀"; return 0
  fi

  backup "$HYPR_MAIN_LUA"
  if grep -qF -e "$MARK_BEGIN" "$HYPR_MAIN_LUA"; then
    sed -i "/^$MARK_BEGIN$/,/^$MARK_END$/d" "$HYPR_MAIN_LUA"
    # 블록이 남긴 빈 줄 정리 (반복 실행해도 파일 끝이 벌어지지 않게)
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HYPR_MAIN_LUA"
  fi
  [ -n "$want" ] || { log "hyprland.lua: 넣을 require 없음 — 블록 제거"; return 0; }

  printf '\n%s\n%s\n%s\n' "$MARK_BEGIN" "$want" "$MARK_END" >> "$HYPR_MAIN_LUA"
  log "hyprland.lua 에 require 추가: $(printf '%s' "$want" | tr '\n' ' ')"
}

# ------------------------------------------------------------------------------
# 예전 버전이 input.lua / bindings.lua 에 직접 덧붙여 둔 블록 알림.
#   마커 없이 append 된 것이라 자동으로 지우면 사용자가 직접 쓴 줄까지 건드릴 수
#   있다. 그래서 지우지 않고 위치만 알려 준다. 남아 있어도 동작은 한다 —
#   kb_options 조각은 이미 들어 있으면 건드리지 않고, 바인딩은 같은 값으로 다시
#   덮어쓸 뿐이다.
# ------------------------------------------------------------------------------
warn_legacy_blocks() {
  local found=0
  [ -f "$LEGACY_INPUT_LUA" ] && grep -q 'korean:ralt_hangul' "$LEGACY_INPUT_LUA" && {
    warn "$LEGACY_INPUT_LUA 에 예전 방식으로 추가된 kb_options 가 있다"; found=1; }
  [ -f "$LEGACY_BIND_LUA" ] && grep -q "$LATIN_WRAPPER" "$LEGACY_BIND_LUA" && {
    warn "$LEGACY_BIND_LUA 에 예전 방식으로 추가된 SPACE 바인딩이 있다"; found=1; }
  [ "$found" = 1 ] && warn "  → 이제 $FRAG_DIR 쪽이 담당한다. 위 블록은 직접 지워도 된다 (백업: *.bak.*)"
  return 0
}

# ------------------------------------------------------------------------------
# 오른쪽 Alt = 한/영 키 (Hyprland kb_options: korean:ralt_hangul)
#   조각을 설치하고 hyprland.lua 에 require 만 남긴다. 값 계산은 조각이 로드될
#   때 hl.get_config 로 하므로 여기서 박아 넣지 않는다.
# ------------------------------------------------------------------------------
apply_ralt_hangul() {
  hypr_lua_ok || return 0

  # 비라틴 레이아웃이면 Omarchy 가 grp:alts_toggle 을 넣는데, 이는 양쪽 Alt 를
  # 레이아웃 전환에 쓰므로 오른쪽 Alt = 한/영 과 충돌한다.
  case ",$(hypr_base_kb_options)," in
    *,grp:alts_toggle,*) warn "kb_options 에 grp:alts_toggle 있음 — 오른쪽 Alt 가 충돌할 수 있음" ;;
  esac

  install_fragment korean-input.lua || return 0
  sync_hypr_requires
}

# ------------------------------------------------------------------------------
# Omarchy 기본 바인딩에서 특정 키의 명령 문자열을 추출.
#   예: omarchy_default_bind_cmd "SUPER + SPACE"  ->  omarchy-menu toggle
#   버전마다 명령이 다르므로(구: omarchy-launch-walker) 하드코딩 대신 읽어 온다.
# ------------------------------------------------------------------------------
omarchy_default_bind_cmd() {
  local line f
  for f in "$OMARCHY_DEFAULTS"/bindings/*.lua "$OMARCHY_DEFAULTS"/bindings.lua; do
    [ -f "$f" ] || continue
    line="$(grep -F "o.bind(\"$1\"," "$f" 2>/dev/null | head -1)" || true
    [ -n "$line" ] || continue
    # 마지막 따옴표 문자열 = 실행 명령
    printf '%s' "$line" | sed -E 's/.*,[[:space:]]*"([^"]*)"[[:space:]]*\).*/\1/'
    return 0
  done
  return 1
}

# ------------------------------------------------------------------------------
# 메뉴/런처를 영문 상태로 열기 — 기존 바인딩을 래퍼로 감싸 재바인딩.
#   저장소의 korean-bindings.lua.in 을 템플릿으로 쓰고, 키별 실제 명령만 여기서
#   채워 조각 파일을 만든다. 명령은 Omarchy 기본 바인딩에서 읽어 오므로 버전이
#   바뀌어도 따라간다 — 그래서 이 조각만 정적 복사가 아니라 생성이다.
# ------------------------------------------------------------------------------
apply_latin_launch_bindings() {
  hypr_lua_ok || return 0

  local tpl="$FRAG_SRC/korean-bindings.lua.in"
  [ -f "$tpl" ] || { warn "템플릿 없음: $tpl (저장소를 clone 해서 실행해야 한다)"; return 0; }

  local menu apps
  menu="$(omarchy_default_bind_cmd 'SUPER + SPACE' || true)"
  apps="$(omarchy_default_bind_cmd 'SUPER + ALT + SPACE' || true)"
  if [ -z "$menu" ] && [ -z "$apps" ]; then
    warn "Omarchy 기본 SPACE 바인딩을 못 찾음 — 바인딩 재설정 건너뜀"; return 0
  fi

  local lines=""
  if [ -n "$menu" ]; then
    lines="${lines}hl.unbind(\"SUPER + SPACE\")"$'\n'
    lines="${lines}o.bind(\"SUPER + SPACE\", \"Omarchy menu (EN first)\", \"$LATIN_WRAPPER $menu\")"$'\n'
  fi
  if [ -n "$apps" ]; then
    lines="${lines}hl.unbind(\"SUPER + ALT + SPACE\")"$'\n'
    lines="${lines}o.bind(\"SUPER + ALT + SPACE\", \"Apps menu (EN first)\", \"$LATIN_WRAPPER $apps\")"$'\n'
  fi

  # 템플릿의 __BINDINGS__ 한 줄을 생성한 줄들로 교체
  local generated="$FRAG_DIR/.korean-bindings.lua.new"
  mkdir -p "$FRAG_DIR"
  awk -v repl="$lines" '{ if ($0 == "__BINDINGS__") printf "%s", repl; else print }' "$tpl" > "$generated"

  install_fragment korean-bindings.lua "$generated"
  rm -f "$generated"
  log "바인딩 (SUPER+SPACE: ${menu:-생략} / SUPER+ALT+SPACE: ${apps:-생략})"
  sync_hypr_requires
}

# ------------------------------------------------------------------------------
# fcitx5 TriggerKeys 가 이미 정리됐는지 (Control+space 없고 Hangul 있음) → 0=정리됨
#   config 파일이 없으면 "정리 필요"(1) 로 간주.
# ------------------------------------------------------------------------------
fcitx_triggerkeys_clean() {
  [ -f "$FCITX_CONF" ] || return 1
  ! grep -qiE '^[0-9]+[[:space:]]*=[[:space:]]*Control\+space' "$FCITX_CONF" \
    && awk '/^\[Hotkey\/TriggerKeys\]/{f=1;next} /^\[/{f=0} f' "$FCITX_CONF" \
       | grep -qi '=[[:space:]]*Hangul[[:space:]]*$'
}

# ------------------------------------------------------------------------------
# fcitx5 TriggerKeys: Control+space 제거, Hangul 트리거 보장 (config 없으면 생성)
# ------------------------------------------------------------------------------
apply_fcitx_triggerkeys() {
  mkdir -p "$FCITX_DIR"
  # 신규 설치: 최소 설정만 작성 (나머지는 fcitx5 기본값)
  if [ ! -f "$FCITX_CONF" ]; then
    cat > "$FCITX_CONF" <<'EOF'
[Hotkey]
EnumerateWithTriggerKeys=True
ModifierOnlyKeyTimeout=250

[Hotkey/TriggerKeys]
0=Zenkaku_Hankaku
1=Hangul

[Behavior]
ActiveByDefault=False
ShareInputState=No
EOF
    log "fcitx5 config 신규 작성 (트리거: Zenkaku_Hankaku, Hangul)"
    return 0
  fi
  if fcitx_triggerkeys_clean; then
    log "fcitx5 config: 이미 정리됨 (Control+space 없음, Hangul 있음) — 건너뜀"
    return 0
  fi
  backup "$FCITX_CONF"
  # TriggerKeys 섹션을 단일 패스로 재작성:
  #   - Control+space 제거, Hangul 없으면 추가, 인덱스 0,1,.. 로 정렬(값은 보존)
  awk '
    function emit(   k) {
      if (!hangul) v[n++] = "Hangul"
      for (k = 0; k < n; k++) print k "=" v[k]
      print ""                       # 섹션 구분 빈 줄
      n = 0; hangul = 0; delete v
    }
    /^\[/ {
      if (inTK) emit()
      inTK = ($0 == "[Hotkey/TriggerKeys]")
      print; next
    }
    inTK {
      if ($0 ~ /^[0-9]+[[:space:]]*=/) {
        val = $0; sub(/^[0-9]+[[:space:]]*=[[:space:]]*/, "", val)
        if (val ~ /^Control\+space[[:space:]]*$/) next    # Ctrl+Space 제거
        if (val ~ /^Hangul[[:space:]]*$/) hangul = 1
        v[n++] = val; next
      }
      next                            # 섹션 내 빈줄/주석은 정리(엔트리는 emit 에서 출력)
    }
    { print }
    END { if (inTK) emit() }
  ' "$FCITX_CONF" > "$FCITX_CONF.tmp" && mv "$FCITX_CONF.tmp" "$FCITX_CONF"
  log "fcitx5 config 패치 (Control+space 제거, Hangul 유지)"
}

# ------------------------------------------------------------------------------
# Hyprland 리로드 + 설정 오류 검증
# ------------------------------------------------------------------------------
reload_hyprland() {
  if ! command -v hyprctl >/dev/null 2>&1; then
    warn "hyprctl 없음 (Hyprland 세션 밖) — 재로그인 후 적용됨"; return 0
  fi
  hyprctl reload >/dev/null 2>&1 && log "Hyprland reload" || warn "hyprctl reload 실패 (계속 진행)"
  local errs; errs="$(hyprctl configerrors 2>/dev/null || true)"
  [ -z "${errs//[[:space:]]/}" ] && log "configerrors: 없음" || warn "configerrors: $errs"
}

# ------------------------------------------------------------------------------
# fcitx5 안전 종료 (설정 편집 전). 원래 실행 여부를 FCITX_WAS_RUNNING 에 기록.
# ------------------------------------------------------------------------------
stop_fcitx5() {
  pgrep -x fcitx5 >/dev/null 2>&1 || return 0
  FCITX_WAS_RUNNING=1
  ( fcitx5-remote -e >/dev/null 2>&1 || pkill -x fcitx5 || true )
  local i
  for i in 1 2 3 4 5 6 7 8; do pgrep -x fcitx5 >/dev/null 2>&1 || break; sleep 0.25; done
  log "fcitx5 임시 종료 (설정 안전 반영용)"
}

# ------------------------------------------------------------------------------
# fcitx5 시작 (원래 실행 중이었거나 Hyprland 세션이면)
# ------------------------------------------------------------------------------
start_fcitx5() {
  command -v fcitx5 >/dev/null 2>&1 || return 0
  if [ "${FCITX_WAS_RUNNING:-0}" -eq 1 ] || pgrep -x Hyprland >/dev/null 2>&1; then
    # 서브셸 자체의 stdout/stderr 도 닫는다. 안쪽 명령만 /dev/null 로 보내면
    # 서브셸과 그 자식이 부모의 파이프를 계속 물고 있어서, 출력을 파이프로 받는
    # 실행(| tee, | grep)이 끝나지 않고 멈춘 것처럼 보인다.
    ( command -v uwsm-app >/dev/null 2>&1 && uwsm-app -- fcitx5 --disable notificationitem \
      || fcitx5 -d --disable notificationitem ) >/dev/null 2>&1 &
    log "fcitx5 시작"
  fi
}

# ==============================================================================
# 가벼운 모드 — 패키지/sudo 없이 키 설정만 재적용
# ==============================================================================
# ------------------------------------------------------------------------------
# 되돌리기. 이 스크립트가 만든 파일만 지운다 — 고쳐 놓은 남의 파일(fcitx5
# config/profile)은 --fcitx 를 줘야 백업에서 되돌린다.
# ------------------------------------------------------------------------------
remove_file() {
  [ -e "$1" ] || { log "없음 — 건너뜀: $1"; return 0; }
  rm -f "$1"
  log "삭제: $1"
}

restore_newest_backup() {
  local target="$1" newest
  newest="$(ls -1t "$target".bak.* 2>/dev/null | head -1)"
  [ -n "$newest" ] || { warn "백업 없음 — 건너뜀: $target"; return 0; }
  cp -a "$newest" "$target"
  log "복원: $newest -> $target"
}

run_remove() {
  # 1) hyprland.lua 의 require 블록
  if [ -f "$HYPR_MAIN_LUA" ] && grep -qF -e "$MARK_BEGIN" "$HYPR_MAIN_LUA"; then
    backup "$HYPR_MAIN_LUA"
    sed -i "/^$MARK_BEGIN$/,/^$MARK_END$/d" "$HYPR_MAIN_LUA"
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HYPR_MAIN_LUA"
    log "hyprland.lua 에서 require 블록 제거"
  else
    log "hyprland.lua: require 블록 없음 — 건너뜀"
  fi

  # 2) Lua 조각
  remove_file "$FRAG_DIR/korean-input.lua"
  remove_file "$FRAG_DIR/korean-bindings.lua"
  rmdir "$FRAG_DIR" 2>/dev/null && log "빈 폴더 정리: $FRAG_DIR"

  # 3) 우리가 새로 만든 파일들
  remove_file "$WRAPPER"
  remove_file "$ENV_FILE"
  remove_file "$XDG_AUTOSTART"

  # 4) fcitx5 는 기본적으로 손대지 않는다
  if [ "$RESTORE_FCITX" = 1 ]; then
    restore_newest_backup "$FCITX_CONF"
    restore_newest_backup "$FCITX_PROFILE"
    stop_fcitx5
    start_fcitx5
  else
    warn "fcitx5 설정은 그대로 뒀다 (Control+space 트리거, hangul 프로필)."
    warn "  되돌리려면: $0 remove --fcitx   또는 백업을 직접 복원"
    ls -1t "$FCITX_CONF".bak.* 2>/dev/null | head -1 | sed 's/^/      /' || true
  fi

  reload_hyprland

  echo
  log "완료. 재로그인하면 IM 환경변수까지 빠진다. 패키지는 그대로 두었다."
}

run_light() {
  warn_legacy_blocks                      # 예전 방식으로 깔린 흔적이 있으면 알림
  apply_ralt_hangul                       # 오른쪽 Alt = 한/영

  # fcitx5 config 는 변경이 필요할 때만 종료→편집→시작 (불필요한 재시작 방지)
  if fcitx_triggerkeys_clean; then
    log "fcitx5 config: 이미 정리됨 — 재시작 불필요"
  else
    stop_fcitx5                           # 편집 전 안전 종료 (편집 후 되쓰기 방지)
    apply_fcitx_triggerkeys               # Control+space 제거 / Hangul 유지
    start_fcitx5
  fi

  reload_hyprland

  echo
  log "완료. 오른쪽 Alt 로 한/영 전환하세요. (이미 열린 창은 재실행 필요할 수 있음)"
}

# ==============================================================================
# 전체 모드 — 갓 설치한 머신을 현재 세팅 상태로
# ==============================================================================
run_full() {
  # ----------------------------------------------------------------------------
  # 1) 패키지 설치
  # ----------------------------------------------------------------------------
  log "1) 패키지 확인/설치: ${PKGS[*]}"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg add "${PKGS[@]}"        # 이미 있으면 무시, 없으면 설치
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm "${PKGS[@]}"
  else
    warn "omarchy/pacman 를 못 찾음 — 패키지 설치를 건너뜀 (수동 설치 필요)"
  fi

  # ----------------------------------------------------------------------------
  # 2) IM 환경변수  (Wayland 권장: GTK_IM_MODULE 은 일부러 설정하지 않음)
  # ----------------------------------------------------------------------------
  mkdir -p "$(dirname "$ENV_FILE")"
  local ENV_CONTENT
  read -r -d '' ENV_CONTENT <<'EOF' || true
INPUT_METHOD=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
EOF
  if [ -f "$ENV_FILE" ] && diff -q <(printf '%s\n' "$ENV_CONTENT") "$ENV_FILE" >/dev/null 2>&1; then
    log "2) 환경변수: 이미 동일 — 건너뜀"
  else
    backup "$ENV_FILE"
    printf '%s\n' "$ENV_CONTENT" > "$ENV_FILE"
    log "2) 환경변수 작성: $ENV_FILE (반영은 재로그인 후)"
  fi

  # ----------------------------------------------------------------------------
  # 3) XDG 자동시작 중복 방지 (omarchy 가 이미 fcitx5 를 띄움)
  # ----------------------------------------------------------------------------
  if [ -f /etc/xdg/autostart/org.fcitx.Fcitx5.desktop ]; then
    mkdir -p "$(dirname "$XDG_AUTOSTART")"
    if [ -f "$XDG_AUTOSTART" ] && grep -qx 'Hidden=true' "$XDG_AUTOSTART"; then
      log "3) 자동시작 중복 방지: 이미 설정됨 — 건너뜀"
    else
      printf '[Desktop Entry]\nHidden=true\n' > "$XDG_AUTOSTART"
      log "3) 자동시작 중복 방지: $XDG_AUTOSTART (Hidden=true)"
    fi
  else
    log "3) /etc/xdg/autostart 에 fcitx5 없음 — 중복 방지 불필요"
  fi

  # fcitx5 프로필/설정을 안전하게 쓰기 위해 실행 중이면 잠시 종료
  stop_fcitx5

  # ----------------------------------------------------------------------------
  # 4) fcitx5 프로필 — hangul 그룹이 없으면 작성
  # ----------------------------------------------------------------------------
  if [ -f "$FCITX_PROFILE" ] && grep -q '^Name=hangul' "$FCITX_PROFILE"; then
    log "4) fcitx5 프로필: hangul IM 이미 존재 — 건너뜀"
  else
    backup "$FCITX_PROFILE"
    cat > "$FCITX_PROFILE" <<'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=hangul

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=hangul
# Layout
Layout=

[GroupOrder]
0=Default
EOF
    log "4) fcitx5 프로필 작성: keyboard-us + hangul (기본 IM=hangul)"
  fi

  # ----------------------------------------------------------------------------
  # 5) fcitx5 단축키  /  6) 오른쪽 Alt = 한/영
  # ----------------------------------------------------------------------------
  log "5) fcitx5 단축키 (Control+space 제거 / Hangul 유지)"
  apply_fcitx_triggerkeys
  log "6) 오른쪽 Alt = 한/영 (kb_options: korean:ralt_hangul)"
  warn_legacy_blocks
  apply_ralt_hangul

  # ----------------------------------------------------------------------------
  # 7) 영문-우선 실행 래퍼
  # ----------------------------------------------------------------------------
  mkdir -p "$(dirname "$WRAPPER")"
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# fcitx5 입력을 영문으로 강제 전환한 뒤 지정한 명령 실행
set -euo pipefail
if command -v fcitx5-remote >/dev/null 2>&1; then
  fcitx5-remote --check >/dev/null 2>&1 && fcitx5-remote -c >/dev/null 2>&1 || true
fi
[ "\$#" -eq 0 ] && { echo "$LATIN_WRAPPER: 실행할 명령이 없습니다" >&2; exit 2; }
exec "\$@"
EOF
  chmod +x "$WRAPPER"
  log "7) 래퍼 작성: $WRAPPER"

  # ----------------------------------------------------------------------------
  # 8) Super+Space / Super+Alt+Space 재바인딩 (영문 먼저)
  # ----------------------------------------------------------------------------
  log "8) Super+Space / Super+Alt+Space 재바인딩 (영문 먼저)"
  apply_latin_launch_bindings

  # ----------------------------------------------------------------------------
  # 9) 적용
  # ----------------------------------------------------------------------------
  reload_hyprland
  start_fcitx5

  echo
  log "완료. 완전 반영을 위해 한 번 로그아웃/로그인 권장 (환경변수 적용)."
  log "이후: 오른쪽 Alt = 한/영, Super+Space·Super+Alt+Space 는 영문으로 시작."
}

# ==============================================================================
case "$MODE" in
  light)  run_light ;;
  full)   run_full ;;
  remove) run_remove ;;
esac
