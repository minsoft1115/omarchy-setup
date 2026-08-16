#!/usr/bin/env bash
#
# setup-korean.sh — Omarchy 한글 입력(fcitx5 + hangul) 세팅
# ==============================================================================
# 사용법:
#   ./setup-korean.sh            전체 세팅 (갓 설치한 머신용, 패키지 설치 포함)
#   ./setup-korean.sh --light    가벼운 재적용 (패키지/sudo 없이 키 설정만)
#   ./setup-korean.sh --help     도움말
#
# 모두 idempotent — 여러 번 실행해도 안전하며, 이미 된 항목은 "건너뜀" 으로 표시.
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
# Hyprland 설정은 신형(.lua) / 구형(.conf) 을 모두 지원 — 있는 쪽을 자동 판별.
# fcitx5 자동시작 자체는 omarchy 기본 autostart 가 담당하므로 여기서 만들지 않음.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# 인자 파싱
# ==============================================================================
MODE=full

usage() {
  sed -n '3,31p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --light|-l) MODE=light ;;
    --full)     MODE=full ;;
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
HYPR_INPUT="${HYPR_INPUT:-$HOME/.config/hypr/input.conf}"
HYPR_INPUT_LUA="${HYPR_INPUT_LUA:-$HOME/.config/hypr/input.lua}"
HYPR_BIND="${HYPR_BIND:-$HOME/.config/hypr/bindings.conf}"
HYPR_BIND_LUA="${HYPR_BIND_LUA:-$HOME/.config/hypr/bindings.lua}"
OMARCHY_DEFAULTS="${OMARCHY_DEFAULTS:-/usr/share/omarchy/default/hypr}"
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
# 오른쪽 Alt = 한/영 키 (Hyprland kb_options: korean:ralt_hangul)
#   Lua 설정(신형)이 있으면 input.lua, 아니면 input.conf(구형) 를 편집.
# ------------------------------------------------------------------------------
apply_ralt_hangul() {
  if [ -f "$HYPR_INPUT_LUA" ]; then
    apply_ralt_hangul_lua
  elif [ -f "$HYPR_INPUT" ]; then
    apply_ralt_hangul_conf
  else
    warn "input.lua / input.conf 둘 다 없음 — kb_options 건너뜀"
  fi
}

apply_ralt_hangul_lua() {
  if grep -q 'korean:ralt_hangul' "$HYPR_INPUT_LUA"; then
    log "kb_options: input.lua 에 이미 korean:ralt_hangul — 건너뜀"; return 0
  fi
  local base; base="$(hypr_base_kb_options)"
  # 비라틴 레이아웃이면 Omarchy 가 grp:alts_toggle 을 넣는데, 이는 양쪽 Alt 를
  # 레이아웃 전환에 쓰므로 오른쪽 Alt = 한/영 과 충돌한다.
  case ",$base," in
    *,grp:alts_toggle,*) warn "kb_options 에 grp:alts_toggle 있음 — 오른쪽 Alt 가 충돌할 수 있음" ;;
  esac
  backup "$HYPR_INPUT_LUA"
  cat >> "$HYPR_INPUT_LUA" <<EOF

-- 오른쪽 Alt = 한/영 키 (fcitx5 hangul 전환 트리거).
-- kb_options 는 통째로 교체되므로 Omarchy 기본값도 함께 적어 둠.
hl.config({
  input = {
    kb_options = "$base,korean:ralt_hangul",
  },
})
EOF
  log "input.lua 에 kb_options 추가: $base,korean:ralt_hangul"
}

apply_ralt_hangul_conf() {
  if grep -qE '^\s*kb_options\s*=.*korean:ralt_hangul' "$HYPR_INPUT"; then
    log "kb_options: 이미 korean:ralt_hangul — 건너뜀"; return 0
  elif ! grep -qE '^\s*kb_options\s*=' "$HYPR_INPUT"; then
    warn "input.conf 에 'kb_options =' 라인 없음 — 건너뜀"; return 0
  fi
  backup "$HYPR_INPUT"
  sed -i -E 's|^(\s*kb_options\s*=\s*)([^#[:space:]]*)(.*)$|\1\2,korean:ralt_hangul\3|' "$HYPR_INPUT"
  # 값이 비어 있던 경우 생기는 선행 콤마 정리
  sed -i -E 's|^(\s*kb_options\s*=\s*),korean:ralt_hangul|\1korean:ralt_hangul|' "$HYPR_INPUT"
  log "kb_options 에 korean:ralt_hangul 추가"
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
#   Lua(신형) / conf(구형) 양쪽 지원.
# ------------------------------------------------------------------------------
apply_latin_launch_bindings() {
  if [ -f "$HYPR_BIND_LUA" ]; then
    apply_latin_launch_bindings_lua
  elif [ -f "$HYPR_BIND" ]; then
    apply_latin_launch_bindings_conf
  else
    warn "bindings.lua / bindings.conf 둘 다 없음 — 바인딩 재설정 건너뜀"
  fi
}

apply_latin_launch_bindings_lua() {
  if grep -q "$LATIN_WRAPPER" "$HYPR_BIND_LUA"; then
    log "바인딩: 이미 래퍼로 재설정됨 — 건너뜀"; return 0
  fi
  local menu apps
  menu="$(omarchy_default_bind_cmd 'SUPER + SPACE' || true)"
  apps="$(omarchy_default_bind_cmd 'SUPER + ALT + SPACE' || true)"
  if [ -z "$menu" ] && [ -z "$apps" ]; then
    warn "Omarchy 기본 SPACE 바인딩을 못 찾음 — 바인딩 재설정 건너뜀"; return 0
  fi
  backup "$HYPR_BIND_LUA"
  {
    printf '\n%s\n%s\n' \
      '-- 메뉴를 열기 전에 fcitx5 입력을 영문으로 강제 전환' \
      '-- (한글 상태로 메뉴가 열려 검색이 안 되는 문제 방지)'
    if [ -n "$menu" ]; then
      printf '%s\n%s\n' \
        "hl.unbind(\"SUPER + SPACE\")" \
        "o.bind(\"SUPER + SPACE\", \"Omarchy menu (EN first)\", \"$LATIN_WRAPPER $menu\")"
    fi
    if [ -n "$apps" ]; then
      printf '%s\n%s\n' \
        "hl.unbind(\"SUPER + ALT + SPACE\")" \
        "o.bind(\"SUPER + ALT + SPACE\", \"Apps menu (EN first)\", \"$LATIN_WRAPPER $apps\")"
    fi
  } >> "$HYPR_BIND_LUA"
  log "bindings.lua 재바인딩 (SUPER+SPACE: ${menu:-생략} / SUPER+ALT+SPACE: ${apps:-생략})"
}

apply_latin_launch_bindings_conf() {
  if grep -q "$LATIN_WRAPPER" "$HYPR_BIND"; then
    log "바인딩: 이미 래퍼로 재설정됨 — 건너뜀"; return 0
  fi
  backup "$HYPR_BIND"
  cat >> "$HYPR_BIND" <<EOF

# 메뉴/런처 열기 전에 fcitx5 입력을 영문으로 강제 전환 (한글 상태로 열리는 문제 방지)
# was: SUPER, SPACE = omarchy-launch-walker / SUPER ALT, SPACE = omarchy-menu
unbind = SUPER, SPACE
bindd = SUPER, SPACE, Launch apps (EN first), exec, $LATIN_WRAPPER omarchy-launch-walker
unbind = SUPER ALT, SPACE
bindd = SUPER ALT, SPACE, Omarchy menu (EN first), exec, $LATIN_WRAPPER omarchy-menu
EOF
  log "bindings.conf 에 SUPER+SPACE / SUPER+ALT+SPACE 재바인딩 추가"
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
    ( command -v uwsm-app >/dev/null 2>&1 && uwsm-app -- fcitx5 --disable notificationitem >/dev/null 2>&1 \
      || fcitx5 -d --disable notificationitem >/dev/null 2>&1 ) &
    log "fcitx5 시작"
  fi
}

# ==============================================================================
# 가벼운 모드 — 패키지/sudo 없이 키 설정만 재적용
# ==============================================================================
run_light() {
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
  light) run_light ;;
  full)  run_full ;;
esac
