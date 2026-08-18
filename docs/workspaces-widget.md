# install-workspaces-widget.sh

> [omarchy-setup](../README.md) 의 스크립트 중 하나.

Omarchy 바의 워크스페이스 인디케이터를 이 저장소가 들고 있는 버전으로 바꾸고,
Super 를 누르고 있으면 각 워크스페이스에 뭐가 떠 있는지 보여 주는 팝업을 추가한다.

**모든 동작이 idempotent** — 여러 번 실행해도 안전하며, 이미 된 항목은 `skipped` 로 표시된다.

## 무엇이 바뀌나

### 바

포커스된 워크스페이스를 Omarchy 원본처럼 글리프로 덮지 않고 **숫자 그대로** 둔다.

```
[1] 2  3  4  5     ← 1번: 살짝 둥근 사각형 배경 + 굵은 숫자 (배경색으로 반전)
                      2번: 창 있음 (밝게)  /  3~5번: 비어 있음 (흐리게)
```

포커스 표시는 강조색이 아니라 **반전**이다 — 박스를 바의 본문색(`bar.text`)으로 채우고
숫자를 배경색(`bar.background`)으로 뒤집는다. 테마의 `bar.active` 는 쓰지 않는다.

### Super 홀드 미리보기

**Super 를 0.25초 이상 누르고 있으면** 팝업이 뜨고, 떼면 닫힌다.

```
[1]  ▸ alacritty  user@host: ~/projects
     ▸ alacritty  nvim README.md
 2   ◉ chromium   Example Domain
```

- 창이 있는 워크스페이스만 나온다
- 창은 **최근 포커스 순** (`focusHistoryID`)
- 앱 아이콘은 데스크톱 항목에서 찾아 붙인다
- 여러 모니터를 써도 **포커스된 모니터에만** 뜬다

---

## 요구 사항

- Omarchy 4.x (Quickshell 셸)
- `jq`, `hyprctl`
- Hyprland 세션이 떠 있어야 한다 (셸 IPC 와 `hyprctl reload` 를 쓴다)

`hyprctl` 이 없으면 위젯만 설치하고 키 바인딩은 건너뛴다.

---

## 사용법

```bash
./install-workspaces-widget.sh status     # 지금 어느 위젯을 쓰는지 (기본 동작)
./install-workspaces-widget.sh install    # 저장소 → OS 설치 + 바에 적용 + 키 바인딩
./install-workspaces-widget.sh revert     # Omarchy 기본 위젯으로 원복
./install-workspaces-widget.sh remove     # 원복 + 설치본 삭제
./install-workspaces-widget.sh diff       # 소스 vs 설치본, 소스 vs Omarchy 원본
```

옵션:

| 옵션 | 하는 일 |
|---|---|
| `--no-restart` | 셸 재시작 생략 (파일만 깔고 나중에 직접 재시작) |

위젯 코드를 고쳤으면 `install` 을 다시 돌리면 된다.

### status 출력 예

```
source (edit here) : /path/to/repo/minsoft1115.workspaces (present)
installed copy     : ~/.config/omarchy/plugins/minsoft1115.workspaces (present)
in sync with source: yes
known to the shell : yes
currently in use   : minsoft1115.workspaces  (bar.layout.left)
Hyprland binding   : installed, required by hyprland.lua, Super_L bound
```

---

## 구성

```
minsoft1115.workspaces/     Quickshell 플러그인 (바 위젯 + 셸 서비스)
├── manifest.json           kinds: ["bar-widget", "service"]
├── Workspaces.qml          바 위젯 — 숫자 렌더 + 팝업 소유
├── PeekService.qml         셸 서비스 — 단축키 등록 + 팝업 제어
├── PeekCard.qml            팝업 레이아웃
└── PeekModel.js            창 목록 모델
hypr/workspace-peek.lua     Hyprland 키 바인딩
```

소스는 저장소에 있고, 스크립트가 **복사해서** 설치한다.

| 소스 | 설치 위치 |
|---|---|
| `minsoft1115.workspaces/` | `~/.config/omarchy/plugins/minsoft1115.workspaces/` |
| `hypr/workspace-peek.lua` | `~/.config/hypr/workspace-peek.lua` + `hyprland.lua` 에 require 한 줄 |

심볼릭 링크가 아니라 복사인 이유는 Omarchy 의 플러그인 감시자(`inotifywait -r`)가
링크를 따라가지 않아서다 — 링크로 걸면 편집이 셸에 전달되지 않는다.

---

## 안전성

- 교체·원복 모두 **바에서의 위치가 유지**되고 `shell.json` 을 손으로 고칠 필요가 없다
- Omarchy 원본은 `/usr/share/omarchy/` 에 그대로 있어 훼손되지 않는다
- `hyprland.lua` 에 넣는 require 줄은 `-- workspaces-widget:begin/end` 마커로 감싸므로
  **정확히 그 줄만** 빠진다
- `hyprland.lua` · `shell.json` 은 고치기 전에 `*.bak.<타임스탬프>` 로 백업한다

`install` → `revert` 왕복 후 `shell.json` 에 잔여 키가 남지 않고, `Super_L` 바인딩과
`hyprland.lua` 마커도 완전히 사라지는 것을 확인했다.

---

## 튜닝

고친 뒤 `install` 을 다시 돌리면 반영된다.

### 팝업 — `minsoft1115.workspaces/PeekService.qml`

| 값 | 현재 | 하는 일 |
|---|---|---|
| `openDelayMs` | 250ms | 팝업이 뜨기까지 눌러야 하는 시간 |
| `safetyTimeoutMs` | 5000ms | 닫기 요청이 안 올 때의 강제 자동 닫기 |

### 팝업 모양 — `minsoft1115.workspaces/PeekCard.qml`

| 값 | 현재 | 하는 일 |
|---|---|---|
| `titleMaxWidth` | `space(460)` | 제목 최대 폭, 넘으면 말줄임 |
| `iconSize` | `space(14)` | 앱 아이콘 크기 |

### 바 — `minsoft1115.workspaces/Workspaces.qml`

| 값 | 현재 | 하는 일 |
|---|---|---|
| `focusRadius` | `space(2)` | 포커스 박스 모서리 둥글기 (`0` 이면 각짐) |
| `focusInsetY` / `focusInsetX` | `space(5)` / `space(1)` | 포커스 박스 여백 (= 박스 크기) |
| `focusFillColor` | `bar.barForeground` | 포커스 박스 채움색 |
| `boldWhenFocused` | `true` | 포커스된 숫자 굵게 |
| `emptyOpacity` | `0.32` | 창 없는 워크스페이스 흐림 정도 |

---

## 알아둘 것

**QML 을 고치면 셸 재시작이 필요하다.** `omarchy-shell shell rescanPlugins` 로는 파일 내용
변경이 반영되지 않아서, `install` 이 알아서 `omarchy restart shell` 을 한다.

**Super 를 누른 채 다른 키를 누르면** Hyprland 가 뗌 이벤트를 주지 않는다. 팝업은 워크스페이스
변경·창 전환을 감지해 스스로 닫고, 그래도 안 닫히면 5초 뒤 강제로 닫힌다.

더 깊은 내용:

- [워크스페이스 위젯이 그려지는 방식](quickshell-workspaces.md) — Omarchy 원본 조사
- [Super 홀드 미리보기 설계와 실측](workspace-peek-design.md) — 키 바인딩 동작, 함정들
