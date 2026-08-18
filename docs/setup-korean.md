# setup-korean.sh

> [omarchy-setup](../README.md) 의 스크립트 중 하나.

한글 입력(fcitx5 + hangul)을 한 번에 세팅한다. 갓 설치한 머신에서 실행하면 패키지 설치부터
키 재바인딩까지 끝나고, 이미 구성된 머신에서는 `--light` 로 키 설정만 다시 입힐 수 있다.

**모든 단계가 idempotent** — 여러 번 실행해도 안전하며, 이미 적용된 항목은 `건너뜀` 으로 표시된다.

## 이 스크립트가 해결하는 것

| 문제 | 해결 |
|---|---|
| 한/영 전환키가 없음 | 오른쪽 Alt 를 한/영 키로 (`korean:ralt_hangul`) |
| `Control+space` 가 tmux prefix 와 충돌 | fcitx5 트리거에서 `Control+space` 제거, `Hangul` 만 유지 |
| Super+Space 메뉴가 한글 상태로 열려 검색이 안 됨 | 메뉴 실행 전 영문으로 강제 전환하는 래퍼로 재바인딩 |
| fcitx5 가 두 번 뜸 | XDG 자동시작을 `Hidden=true` 로 억제 (omarchy 기본 autostart 가 담당) |

---

## 요구 사항

- Omarchy (또는 Arch 계열 + Hyprland)
- **Hyprland 0.55 이상** — Lua 설정(`.lua`)이 0.55 에서 도입됐다. 그 미만이면 hypr 관련
  단계(6, 8)만 안내와 함께 건너뛰고 fcitx5 설정은 그대로 진행한다
- `bash`, `git`
- 패키지 설치 단계에서 `omarchy` 또는 `pacman` — 없으면 그 단계만 건너뛰고 계속 진행한다
- `--full` 모드는 `sudo` 가 필요할 수 있다 (`pacman -S` 경로일 때)

`hyprctl` 이 없는 환경(Hyprland 세션 밖)에서도 실행은 되며, 설정 파일만 기록하고
"재로그인 후 적용됨" 을 알린다.

---

## 설치

여러 스크립트를 한 번에 돌리려면 [`install.sh`](install.md) 를 쓰면 된다. 이 스크립트만
쓰려면 아래처럼 한다.

### 1. clone 해서 실행 (권장)

```bash
git clone https://github.com/minsoft1115/omarchy-setup.git
cd omarchy-setup
./scripts/setup-korean.sh
```

### 2. 스크립트만 받아서 실행 — 이제 안 된다

Hyprland 설정을 `hypr/` 폴더의 Lua 조각으로 넣기 때문에 **저장소가 함께 있어야 한다.**
스크립트 하나만 받으면 조각을 못 찾고 그 단계를 건너뛴다.

> 파이프로 바로 실행(`curl ... | bash`)하는 방법은 일부러 적지 않았다.
> 이 스크립트는 `~/.config/hypr`, `~/.config/fcitx5` 를 수정하고 sudo 를 쓸 수 있으므로
> 내용을 확인한 뒤 실행하는 편이 낫다.

---

## 사용법

```
$ ./scripts/setup-korean.sh --help
setup-korean.sh — Omarchy 한글 입력(fcitx5 + hangul) 세팅
==============================================================================
사용법:
  ./scripts/setup-korean.sh            전체 세팅 (갓 설치한 머신용, 패키지 설치 포함)
  ./scripts/setup-korean.sh --light    가벼운 재적용 (패키지/sudo 없이 키 설정만)
  ./scripts/setup-korean.sh remove     되돌리기 (이 스크립트가 만든 것만)
  ./scripts/setup-korean.sh --help     도움말

모두 idempotent — 여러 번 실행해도 안전하며, 이미 된 항목은 "건너뜀" 으로 표시.
==============================================================================
```

### 전체(`--full`, 기본) 단계

1. fcitx5 + 한글 패키지 설치 (`fcitx5`, `fcitx5-hangul`, `fcitx5-configtool`, `fcitx5-gtk`, `fcitx5-qt`)
2. IM 환경변수 → `~/.config/environment.d/fcitx.conf`
3. XDG 자동시작 중복 방지 → `~/.config/autostart/org.fcitx.Fcitx5.desktop`
4. fcitx5 프로필 (keyboard-us + hangul, 기본 IM=hangul)
5. fcitx5 단축키 — `Control+space` 제거, `Hangul` 유지
6. 오른쪽 Alt = 한/영 (`input.lua` 의 `kb_options` 에 `korean:ralt_hangul` 추가)
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
[+] 설치: /home/user/.config/minsoft1115/hypr/korean-input.lua
[+] 백업: /home/user/.config/hypr/hyprland.lua.bak.1763251200
[+] hyprland.lua 에 require 추가: require("minsoft1115.hypr.korean-input")
[+] 7) 래퍼 작성: /home/user/.local/bin/omarchy-latin-launch
[+] 8) Super+Space / Super+Alt+Space 재바인딩 (영문 먼저)
[+] 설치: /home/user/.config/minsoft1115/hypr/korean-bindings.lua
[+] 바인딩 (SUPER+SPACE: omarchy-menu toggle / SUPER+ALT+SPACE: omarchy-menu toggle apps)
[+] hyprland.lua 에 require 추가: require("minsoft1115.hypr.korean-input") require("minsoft1115.hypr.korean-bindings")
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
[+] korean-input.lua: 이미 최신 — 건너뜀
[+] hyprland.lua: require 블록 이미 최신 — 건너뜀
[+] korean-bindings.lua: 이미 최신 — 건너뜀
```

이미 세팅된 머신에서 `--light` 를 돌리면 이렇게 끝난다 (실제 출력).
설정 파일은 건드리지 않으므로 백업도 새로 생기지 않고, fcitx5 재시작도 하지 않는다.

```
$ ./scripts/setup-korean.sh --light
[+] korean-input.lua: 이미 최신 — 건너뜀
[+] hyprland.lua: require 블록 이미 최신 — 건너뜀
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
| `~/.config/hypr/hyprland.lua` | 마커로 감싼 `require` 줄 2개 (**Omarchy 파일 중 손대는 유일한 곳**) |
| `~/.config/minsoft1115/hypr/korean-input.lua` | `kb_options` 에 `korean:ralt_hangul` (저장소에서 복사) |
| `~/.config/minsoft1115/hypr/korean-bindings.lua` | SPACE 계열 바인딩 재설정 (템플릿에서 생성) |
| `~/.local/bin/omarchy-latin-launch` | 영문-우선 실행 래퍼 (신규 생성) |

기존 파일은 수정 전에 `*.bak.<타임스탬프>` 로 백업된다. 되돌리려면 백업을 덮어쓰면 된다.

```bash
ls ~/.config/hypr/*.bak.*  ~/.config/fcitx5/*.bak.*
```

### Hyprland 설정을 넣는 방식

`input.lua` · `bindings.lua` 를 직접 고치지 않는다. 저장소의 Lua 조각을
`~/.config/minsoft1115/hypr/` 로 복사하고, `hyprland.lua` 끝에 이 블록만 넣는다.

```lua
-- setup-korean:begin
require("minsoft1115.hypr.korean-input")
require("minsoft1115.hypr.korean-bindings")
-- setup-korean:end
```

`~/.config` 가 Hyprland 의 Lua `package.path` 에 있어서 점 표기 모듈명이 그대로 해석된다.
Omarchy 기본값 뒤에 로드되므로 여기 정의가 이긴다. 되돌리려면 **마커 사이만 지우면** 된다.

`korean-input.lua` 는 설치 시점 값을 박아 두지 않고 로드될 때
`hl.get_config("input.kb_options")` 로 현재 값을 읽어 옵션을 덧붙인다. 그래서 Omarchy 가
나중에 기본 `kb_options` 를 바꿔도 따라가고, 낡은 값이 설정 파일에 남지 않는다.

`korean-bindings.lua` 만 정적 복사가 아니라 **생성**이다 — 키에 걸린 실제 명령이 Omarchy
버전마다 달라서, 스크립트가 기본 바인딩에서 읽어 템플릿(`hypr/korean-bindings.lua.in`)의
자리표시자를 채운다.

예전 버전이 `input.lua` · `bindings.lua` 에 직접 덧붙여 둔 블록이 있으면 **위치만 알려 준다.**
마커 없이 append 된 것이라 자동으로 지우면 직접 쓴 줄까지 건드릴 수 있어서다. 남아 있어도
동작에는 문제가 없다.

Hyprland 설정은 **Lua(`.lua`) 형식만** 다룬다. 구형 `hyprland.conf` 방식은 지원하지 않는다.

실행 시 `hyprctl version` 으로 버전을 확인해서, `0.55` 미만이면 이렇게 알리고 hypr 단계만 건너뛴다.

```
[!] Hyprland 0.54.0 — Lua 설정은 0.55.0 이상에서만 쓸 수 있다 (이 버전은 hyprland.conf 방식).
[!]   → Hyprland 를 올린 뒤(omarchy update) 다시 실행하거나,
[!]     input.conf 에 'kb_options = ...,korean:ralt_hangul' 을 직접 넣어야 한다.
[!]   fcitx5 설정은 그대로 진행한다.
```

버전을 못 읽으면(Hyprland 세션 밖) 경고만 하고 Lua 기준으로 계속 진행한다.
대상 파일이 없을 때도 그 단계만 건너뛴다.

---

## 환경변수로 경로 바꾸기

기본 경로가 다른 환경이라면 실행 시 덮어쓸 수 있다.

```bash
FCITX_DIR=~/dotfiles/fcitx5 FRAG_DIR=~/dotfiles/minsoft1115/hypr ./scripts/setup-korean.sh --light
```

지원 변수: `FCITX_DIR`, `FCITX_CONF`, `FCITX_PROFILE`, `FRAG_SRC`, `FRAG_DIR`,
`HYPR_MAIN_LUA`, `OMARCHY_DEFAULTS`, `HYPR_LUA_MIN`, `KB_OPTIONS_FALLBACK`, `LATIN_WRAPPER`, `TS`

---

## 문제 해결

**오른쪽 Alt 가 안 먹는다**
`kb_options` 에 `grp:alts_toggle` 이 함께 있으면 충돌한다 (비라틴 레이아웃일 때 Omarchy 가 넣는다).
스크립트가 경고를 띄우며, 해당 항목을 `input.lua` 에서 제거해야 한다.

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

```bash
./scripts/setup-korean.sh remove
```

이 스크립트가 **만든 것만** 지운다 — `hyprland.lua` 의 마커 블록, `~/.config/minsoft1115/hypr`
의 조각, 영문-우선 래퍼, IM 환경변수 파일, XDG 자동시작 억제 파일.

**fcitx5 의 `config`·`profile` 은 건드리지 않는다.** 우리가 만든 게 아니라 고친 파일이고,
되돌리면 한글 입력 자체가 사라질 수 있어서다. 백업 위치만 알려 준다. TriggerKeys 와 프로필까지
가장 최근 백업으로 되돌리려면:

```bash
./scripts/setup-korean.sh remove --fcitx
```

설치한 패키지는 어느 쪽이든 그대로 둔다.
