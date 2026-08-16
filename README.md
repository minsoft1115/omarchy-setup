# omarchy-setup

[Omarchy](https://omarchy.org) (Arch + Hyprland) 머신을 위한 셋업 스크립트 모음.

---

## setup-korean.sh

한글 입력(fcitx5 + hangul)을 한 번에 세팅한다. 갓 설치한 머신에서 실행하면 패키지 설치부터
키 재바인딩까지 끝나고, 이미 구성된 머신에서는 `--light` 로 키 설정만 다시 입힐 수 있다.

**모든 단계가 idempotent** — 여러 번 실행해도 안전하며, 이미 적용된 항목은 `건너뜀` 으로 표시된다.

### 이 스크립트가 해결하는 것

| 문제 | 해결 |
|---|---|
| 한/영 전환키가 없음 | 오른쪽 Alt 를 한/영 키로 (`korean:ralt_hangul`) |
| `Control+space` 가 tmux prefix 와 충돌 | fcitx5 트리거에서 `Control+space` 제거, `Hangul` 만 유지 |
| Super+Space 메뉴가 한글 상태로 열려 검색이 안 됨 | 메뉴 실행 전 영문으로 강제 전환하는 래퍼로 재바인딩 |
| fcitx5 가 두 번 뜸 | XDG 자동시작을 `Hidden=true` 로 억제 (omarchy 기본 autostart 가 담당) |

---

## 요구 사항

- Omarchy (또는 Arch 계열 + Hyprland)
- `bash`, `git`
- 패키지 설치 단계에서 `omarchy` 또는 `pacman` — 없으면 그 단계만 건너뛰고 계속 진행한다
- `--full` 모드는 `sudo` 가 필요할 수 있다 (`pacman -S` 경로일 때)

`hyprctl` 이 없는 환경(Hyprland 세션 밖)에서도 실행은 되며, 설정 파일만 기록하고
"재로그인 후 적용됨" 을 알린다.

---

## 설치

### 1. clone 해서 실행 (권장)

```bash
git clone https://github.com/minsoft1115/omarchy-setup.git
cd omarchy-setup
./setup-korean.sh
```

### 2. 스크립트 하나만 받아서 실행

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/setup-korean.sh -o setup-korean.sh
less setup-korean.sh          # 실행 전에 한 번 읽어볼 것
bash setup-korean.sh
```

> 파이프로 바로 실행(`curl ... | bash`)하는 방법은 일부러 적지 않았다.
> 이 스크립트는 `~/.config/hypr`, `~/.config/fcitx5` 를 수정하고 sudo 를 쓸 수 있으므로
> 내용을 확인한 뒤 실행하는 편이 낫다.

---

## 사용법

```
$ ./setup-korean.sh --help
setup-korean.sh — Omarchy 한글 입력(fcitx5 + hangul) 세팅
==============================================================================
사용법:
  ./setup-korean.sh            전체 세팅 (갓 설치한 머신용, 패키지 설치 포함)
  ./setup-korean.sh --light    가벼운 재적용 (패키지/sudo 없이 키 설정만)
  ./setup-korean.sh --help     도움말

모두 idempotent — 여러 번 실행해도 안전하며, 이미 된 항목은 "건너뜀" 으로 표시.
==============================================================================
```

### 전체(`--full`, 기본) 단계

1. fcitx5 + 한글 패키지 설치 (`fcitx5`, `fcitx5-hangul`, `fcitx5-configtool`, `fcitx5-gtk`, `fcitx5-qt`)
2. IM 환경변수 → `~/.config/environment.d/fcitx.conf`
3. XDG 자동시작 중복 방지 → `~/.config/autostart/org.fcitx.Fcitx5.desktop`
4. fcitx5 프로필 (keyboard-us + hangul, 기본 IM=hangul)
5. fcitx5 단축키 — `Control+space` 제거, `Hangul` 유지
6. 오른쪽 Alt = 한/영 (`kb_options` 에 `korean:ralt_hangul` 추가)
7. 영문-우선 실행 래퍼 → `~/.local/bin/omarchy-latin-launch`
8. `Super+Space` / `Super+Alt+Space` 재바인딩 (메뉴를 영문으로 열기)
9. 적용 (Hyprland reload / fcitx5 재시작)

### 가벼운(`--light`) 단계

5, 6, 9 만 수행한다. 이미 한글 입력이 구성된 시스템에서 아래만 재적용할 때 쓴다.

- 오른쪽 Alt = 한/영 키
- fcitx5 `Control+space` 트리거 제거 (tmux 충돌 해소)

패키지 설치도 sudo 도 건드리지 않는다.

---

## 실행 출력

`--full` 실행 시 출력 예시 (초록 `[+]` 는 적용, 노랑 `[!]` 는 경고):

```
[+] 1) 패키지 확인/설치: fcitx5 fcitx5-hangul fcitx5-configtool fcitx5-gtk fcitx5-qt
[+] 2) 환경변수 작성: /home/user/.config/environment.d/fcitx.conf (반영은 재로그인 후)
[+] 3) 자동시작 중복 방지: /home/user/.config/autostart/org.fcitx.Fcitx5.desktop (Hidden=true)
[+] fcitx5 임시 종료 (설정 안전 반영용)
[+] 4) fcitx5 프로필 작성: keyboard-us + hangul (기본 IM=hangul)
[+] 5) fcitx5 단축키 (Control+space 제거 / Hangul 유지)
[+] 백업: /home/user/.config/fcitx5/config.bak.1763251200
[+] fcitx5 config 패치 (Control+space 제거, Hangul 유지)
[+] 6) 오른쪽 Alt = 한/영 (kb_options: korean:ralt_hangul)
[+] input.lua 에 kb_options 추가: compose:caps,shift:both_capslock_cancel,korean:ralt_hangul
[+] 7) 래퍼 작성: /home/user/.local/bin/omarchy-latin-launch
[+] 8) Super+Space / Super+Alt+Space 재바인딩 (영문 먼저)
[+] bindings.lua 재바인딩 (SUPER+SPACE: omarchy-menu toggle / SUPER+ALT+SPACE: omarchy-launch-walker)
[+] Hyprland reload
[+] configerrors: 없음
[+] fcitx5 시작

[+] 완료. 완전 반영을 위해 한 번 로그아웃/로그인 권장 (환경변수 적용).
[+] 이후: 오른쪽 Alt = 한/영, Super+Space·Super+Alt+Space 는 영문으로 시작.
```

두 번째 실행부터는 대부분 `건너뜀` 으로 바뀐다:

```
[+] 4) fcitx5 프로필: hangul IM 이미 존재 — 건너뜀
[+] fcitx5 config: 이미 정리됨 (Control+space 없음, Hangul 있음) — 건너뜀
[+] kb_options: input.lua 에 이미 korean:ralt_hangul — 건너뜀
[+] 바인딩: 이미 래퍼로 재설정됨 — 건너뜀
```

이미 세팅된 머신에서 `--light` 를 돌리면 이렇게 끝난다 (실제 출력).
설정 파일은 건드리지 않으므로 백업도 새로 생기지 않고, fcitx5 재시작도 하지 않는다.

```
$ ./setup-korean.sh --light
[+] kb_options: input.lua 에 이미 korean:ralt_hangul — 건너뜀
[+] fcitx5 config: 이미 정리됨 — 재시작 불필요
[+] Hyprland reload
[+] configerrors: 없음

[+] 완료. 오른쪽 Alt 로 한/영 전환하세요. (이미 열린 창은 재실행 필요할 수 있음)
```

---

## 실행 후

1. **로그아웃 / 로그인 한 번** — `environment.d` 의 IM 환경변수는 세션 시작 시에만 읽힌다.
2. 오른쪽 Alt 로 한/영 전환.
3. `Super+Space`, `Super+Alt+Space` 는 항상 영문 상태로 열린다.

이미 열려 있던 창은 IM 환경변수를 물려받지 못했을 수 있으니 재실행이 필요할 수 있다.

---

## 건드리는 파일

| 경로 | 내용 |
|---|---|
| `~/.config/fcitx5/config` | TriggerKeys (Control+space 제거, Hangul 유지) |
| `~/.config/fcitx5/profile` | keyboard-us + hangul 그룹 |
| `~/.config/environment.d/fcitx.conf` | `INPUT_METHOD`, `QT_IM_MODULE`, `XMODIFIERS`, `SDL_IM_MODULE` |
| `~/.config/autostart/org.fcitx.Fcitx5.desktop` | `Hidden=true` (중복 실행 방지) |
| `~/.config/hypr/input.lua` 또는 `input.conf` | `kb_options` 에 `korean:ralt_hangul` |
| `~/.config/hypr/bindings.lua` 또는 `bindings.conf` | SPACE 계열 바인딩 재설정 |
| `~/.local/bin/omarchy-latin-launch` | 영문-우선 실행 래퍼 (신규 생성) |

기존 파일은 수정 전에 `*.bak.<타임스탬프>` 로 백업된다. 되돌리려면 백업을 덮어쓰면 된다.

```bash
ls ~/.config/hypr/*.bak.*  ~/.config/fcitx5/*.bak.*
```

Hyprland 설정은 신형(`.lua`) / 구형(`.conf`) 을 모두 지원하며, 있는 쪽을 자동 판별한다.

---

## 환경변수로 경로 바꾸기

기본 경로가 다른 환경이라면 실행 시 덮어쓸 수 있다.

```bash
FCITX_DIR=~/dotfiles/fcitx5 HYPR_BIND_LUA=~/dotfiles/hypr/bindings.lua ./setup-korean.sh --light
```

지원 변수: `FCITX_DIR`, `FCITX_CONF`, `FCITX_PROFILE`, `HYPR_INPUT`, `HYPR_INPUT_LUA`,
`HYPR_BIND`, `HYPR_BIND_LUA`, `OMARCHY_DEFAULTS`, `KB_OPTIONS_FALLBACK`, `LATIN_WRAPPER`, `TS`

---

## 문제 해결

**오른쪽 Alt 가 안 먹는다**
`kb_options` 에 `grp:alts_toggle` 이 함께 있으면 충돌한다 (비라틴 레이아웃일 때 Omarchy 가 넣는다).
스크립트가 경고를 띄우며, 해당 항목을 `input.lua` / `input.conf` 에서 제거해야 한다.

```bash
hyprctl getoption input:kb_options
```

**한글이 아예 입력되지 않는다**
로그아웃/로그인을 했는지 확인하고, IM 상태를 점검한다.

```bash
fcitx5-remote -check    # 실행 중인지
fcitx5-diagnose | less  # 환경변수/모듈 진단
```

**메뉴가 여전히 한글로 열린다**
래퍼가 PATH 에 있는지 확인한다.

```bash
command -v omarchy-latin-launch    # ~/.local/bin/omarchy-latin-launch 가 나와야 함
```

**설정을 되돌리고 싶다**
백업 파일을 복원한 뒤 리로드한다.

```bash
cp ~/.config/hypr/input.lua.bak.<타임스탬프> ~/.config/hypr/input.lua
hyprctl reload
```
