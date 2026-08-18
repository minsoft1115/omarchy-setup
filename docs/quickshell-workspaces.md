# Omarchy 4.0 — Quickshell workspaces 표시 방식

> [omarchy-setup](../README.md) 참고 문서. 스크립트가 아니라 **현재 시스템이 어떻게 동작하는지**에 대한 조사 기록이다.

조사 대상 시스템: Omarchy `4.0.0-1`, Quickshell `0.3.0` (AUR `quickshell-git`), Hyprland, 단일 모니터 `eDP-1`.

바에 보이는 `1 2 3 4 5` 워크스페이스 인디케이터가 **어디서 오고, 어떤 규칙으로 그려지고,
클릭하면 무슨 일이 일어나는지**를 소스까지 따라간 결과.

---

## 한 줄 요약

Omarchy 바는 별도 프로세스가 아니라 Quickshell 하나(`quickshell -n -p /usr/share/omarchy/shell`)로 돌고,
워크스페이스 표시는 그 안의 바 위젯 **`omarchy.workspaces`** 가 담당한다.
이 위젯은 Hyprland IPC 를 그대로 구독해서 **1~5번은 항상**, **6~10번은 존재할 때만** 그리고,
포커스된 워크스페이스는 숫자 대신 **네모 글리프**로, 창이 없는 워크스페이스는 **50% 투명도**로 그린다.

---

## 1. 어디에 정의되어 있나

### 바 레이아웃 (사용자 설정)

`~/.config/omarchy/shell.json` 의 `bar.layout.left` 첫 줄부터:

```json
"left": [
  { "id": "omarchy.menu" },
  { "id": "omarchy.workspaces" }
]
```

즉 현재 워크스페이스 인디케이터는 **바 왼쪽**, Omarchy 메뉴(◆) 바로 오른쪽에 붙어 있다.
이 파일은 `/usr/share/omarchy/config/omarchy/shell.json` 기본값과 **워크스페이스 항목에 관해서는 동일**하다
(= 이 부분은 아직 커스터마이즈하지 않은 상태).

`shell.json` 은 저장하면 **핫 리로드** 된다. 재시작 불필요.

### 위젯 구현 (패키지 소유, 수정 금지)

```
/usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml            ← 실제 렌더링 로직 (72줄)
/usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.manifest.json  ← 위젯 등록 정보
/usr/share/omarchy/shell/plugins/bar/Bar.qml                           ← 위젯을 담는 바 호스트
/usr/share/omarchy/shell/Ui/BarWidget.qml                              ← 모든 바 위젯의 베이스
/usr/share/omarchy/shell/Ui/WidgetButton.qml                           ← 숫자 하나 = 버튼 하나
/usr/share/omarchy/shell/Commons/Style.qml, Color.qml                  ← 크기·색 토큰
```

manifest 요약:

| 키 | 값 |
|---|---|
| `id` | `omarchy.workspaces` |
| `kinds` | `bar-widget` |
| `category` | `Compositor` |
| `allowMultiple` | `false` (바에 한 번만 배치 가능) |
| 설정 스키마 | **없음** — `shell.json` 항목에 넣을 수 있는 옵션 키가 하나도 없다 |

마지막 줄이 중요하다. 표시 규칙을 바꾸려면 설정이 아니라 **위젯을 복제해서 코드를 고쳐야 한다** (아래 6장).

---

## 2. 데이터는 어디서 오나

`Workspaces.qml` 은 Quickshell 이 제공하는 `Quickshell.Hyprland` 싱글턴만 읽는다.

```qml
import Quickshell.Hyprland

Hyprland.workspaces.values        // 현재 존재하는 워크스페이스 목록
Hyprland.focusedWorkspace         // 지금 포커스된 워크스페이스
workspace.toplevels.values        // 그 워크스페이스에 떠 있는 창 목록
```

이 싱글턴은 Quickshell 이 Hyprland 의 **IPC 이벤트 소켓(socket2)** 을 물고 있다가 갱신한다.
폴링이 아니라 이벤트 푸시라서, 워크스페이스를 바꾸는 순간 바가 즉시 따라온다.
QML 프로퍼티 바인딩이라 `values` 가 바뀌면 목록·투명도·글리프가 알아서 재평가된다.

즉 **바가 상태를 따로 들고 있지 않다.** 진실은 항상 Hyprland 쪽에 있고 바는 거울일 뿐이다.
`hyprctl workspaces -j` 로 보는 것과 바에 보이는 것이 어긋날 수 없는 구조다.

---

## 3. 어떤 워크스페이스가 보이나

`workspaceIds()` 함수가 전부다:

```qml
function workspaceIds() {
  var ids = [1, 2, 3, 4, 5]                              // ← 하드코딩된 상시 노출 베이스라인
  var values = Hyprland.workspaces.values

  for (var i = 0; i < values.length; i++) {
    var id = values[i].id
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  ids.sort(function(left, right) { return left - right })
  return ids
}
```

정리하면:

| 워크스페이스 | 바에 보이나 | 비고 |
|---|---|---|
| 1 ~ 5 | **항상 보인다** | 비어 있어도 자리를 차지한다 (하드코딩) |
| 6 ~ 10 | **존재할 때만** | 창을 하나라도 보내면 나타나고, 비면 사라진다 |
| 11 번 이상 | 절대 안 보인다 | `id <= 10` 필터에 걸림 |
| special (scratchpad 등) | 절대 안 보인다 | Hyprland 가 special 에 **음수 ID** 를 주므로 `id > 0` 에 걸림 |
| 이름 있는 워크스페이스 | ID 가 1~10 이면 보이되 **이름은 안 나온다** | 항상 숫자/글리프만 그린다 |

`SUPER + S` 로 여는 scratchpad 는 `special:scratchpad` 라서 **바에 아무 흔적도 남지 않는다.**
스크래치패드에 창을 숨겨두면 바만 봐서는 알 수 없다는 뜻 — 실사용에서 헷갈리기 쉬운 지점이다.

### 현재 이 머신의 실제 상태

```
$ hyprctl workspaces -j
[{ "id": 1, "name": "1", "monitor": "eDP-1", "windows": 1, ... }]
```

존재하는 워크스페이스는 1번 하나뿐. 그래서 바에는:

```
[󱓻] [2] [3] [4] [5]
 ↑    └── 3개 다 불투명도 0.5 (창 없음)
 └─ 포커스 → 숫자 대신 글리프, 불투명도 1
```

---

## 4. 각 칸이 어떻게 그려지나

칸 하나는 `WidgetButton` 이고, 상태 판정은 세 줄이다:

```qml
readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
readonly property bool focused:  Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

text:    focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))   // U+F14FB
opacity: occupied || focused ? 1 : 0.5
```

### 라벨

| 상태 | 그려지는 것 |
|---|---|
| 포커스됨 | `U+F14FB` — Nerd Font 의 채워진 둥근 사각형(`square-rounded`) 글리프 `󱓻` |
| 10번 워크스페이스 | 문자 `0` (키바인딩 `SUPER + 0` 과 맞춤) |
| 그 외 | 워크스페이스 번호 그대로 |

포커스된 칸은 **숫자가 사라지고 네모로 바뀐다.** 번호 대신 위치로 읽으라는 디자인이다.
`󱓻` 는 서로게이트 페어이고 실제 코드포인트는 `U+F14FB` — Nerd Font 가 깔려 있지 않으면
여기가 두부(􏿽)로 보인다. 바 폰트는 fontconfig 의 monospace 바인딩을 그대로 따라간다
(`Style.font.family` 기본값이 `"monospace"`).

### 밝기

- 창이 있거나(`occupied`) 포커스면 → 불투명도 **1**
- 둘 다 아니면 → 불투명도 **0.5**

그래서 "비어 있는 워크스페이스"와 "창이 들어 있는 워크스페이스"가 밝기로 구분된다.
전환 시 140ms `OutCubic` 페이드가 붙는다 (`WidgetButton` 의 `Behavior on opacity`).

### 색

여기가 의외인 부분: **워크스페이스 위젯은 색을 전혀 바꾸지 않는다.**
`WidgetButton.active` 는 기본값 `false` 이고 위젯이 이걸 건드리지 않으므로,
모든 칸이 항상 테마의 바 전경색 하나로만 그려진다.

현재 테마 기준 (`~/.local/state/omarchy/current/theme/shell.toml`):

| 토큰 | 값 | 이 위젯에서의 쓰임 |
|---|---|---|
| `bar.text` | `#a9b1d6` | **모든 칸의 글자색** (포커스 포함) |
| `bar.active` | `#f7768e` | 워크스페이스 위젯은 **안 씀** (녹화·알림 같은 위젯 전용) |
| `bar.background` | `#1a1b26` | 바 배경 |

즉 포커스 표시는 **색이 아니라 글리프 + 불투명도**로만 이루어진다.
"활성 워크스페이스를 강조색으로 칠하고 싶다"면 테마를 아무리 고쳐도 안 되고, 위젯 코드를 고쳐야 한다.

### 크기와 간격

`GridLayout` 하나에 `Repeater` 로 칸을 찍는다.

| 항목 | 가로 바 (현재) | 세로 바 |
|---|---|---|
| 배치 | 1행 × N열 | N행 × 1열 |
| 칸 너비 | `Style.space(20)` = **20px** | `barSize` |
| 칸 높이 | `barSize` = **26px** | 내용에 맞춤 |
| 칸 사이 간격 | `Style.space(1)` = **1px** | `Style.space(2)` |
| 위젯 뒤 여백 | `Style.spaceReal(1.5)` = **1.5px** | 0 |

이 숫자들은 고정값이 아니라 테마 토큰에서 파생된다:

- `barSize` = `[bar] size-horizontal` (현재 `26`) × `fontScale`
- `fontScale` = `[font] base-size / 12` (현재 `12/12` = **1.0**)
- `Style.space(px)` = `px` × `spacingScale` × `fontScale` (현재 `1.0` × `1.0`)

`[bar] scale-with-font = true`, `[spacing] scale-with-font = true` 이므로
**테마의 `base-size` 만 올려도 바 높이·칸 너비·간격이 통째로 같이 커진다.**
글꼴만 키우고 칸은 그대로 두려면 `[bar] scale-with-font = false` 를 쓰면 된다.

(모니터 `scale = 1.25` 는 Qt 논리 픽셀 위에 별도로 곱해지는 값이라 위 계산과는 층이 다르다.)

---

## 5. 클릭하면 무슨 일이 일어나나

```qml
function focusWorkspace(id) {
  if (!root.bar) return
  root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
}
```

- `WidgetButton` 의 `MouseArea` 는 **좌·우·가운데 버튼을 전부** 받는데,
  위젯은 버튼 종류를 구분하지 않는다 → **어느 버튼으로 눌러도 그냥 해당 워크스페이스로 이동**한다.
- 실행 경로는 QML → `bar.run()` → `Util.execDetached()` → `hyprctl dispatch` 프로세스.
  즉 바가 Hyprland 를 직접 호출하는 게 아니라 **CLI 를 한 번 거친다.**
- 인자는 Omarchy 4.0 의 Lua 스타일 디스패치(`hl.dsp.focus({ workspace = "3" })`)이고, `shellQuote` 로 감싼다.
- 마우스를 올리면 커서가 손 모양이 되지만 **툴팁은 안 뜬다** (`tooltipText` 가 비어 있음).
- 휠 스크롤은 위젯이 처리하지 않는다. 다만 Hyprland 쪽 `SUPER + 휠` 바인딩이 워크스페이스를 넘긴다.

### 바 밖에서 표시를 바꾸는 것들 (키바인딩)

`/usr/share/omarchy/default/hypr/bindings/tiling.lua` 기준:

| 키 | 동작 |
|---|---|
| `SUPER + 1`~`0` | 해당 워크스페이스로 이동 (`0` = 10번) |
| `SUPER + SHIFT + 1`~`0` | 창을 그 워크스페이스로 옮기고 따라감 |
| `SUPER + SHIFT + ALT + 1`~`0` | 창만 조용히 옮김 (따라가지 않음) |
| `SUPER + TAB` / `SUPER + SHIFT + TAB` | 다음 / 이전 워크스페이스 (`e+1` / `e-1`) |
| `SUPER + CTRL + TAB` | 직전 워크스페이스 |
| `SUPER + 휠` | 워크스페이스 순환 |
| `SUPER + S` | scratchpad 토글 — **바에는 안 나타남** |

참고로 Omarchy 기본값은 워크스페이스 전환 애니메이션을 꺼둔다
(`looknfeel.lua`: `hl.animation({ leaf = "workspaces", enabled = false })`).
그래서 전환이 즉각적으로 느껴지고, 바 쪽 페이드(140ms)만 눈에 띈다.

---

## 6. 멀티 모니터에서의 동작 (지금은 안 보이는 함정)

`Bar.qml` 은 바를 화면마다 하나씩 만든다:

```qml
Variants {
  model: Quickshell.screens
  delegate: Component { BarPanel { required property var modelData; screen: modelData } }
}
```

따라서 **워크스페이스 위젯도 모니터 수만큼 인스턴스가 생긴다.**
그런데 포커스 판정은:

```qml
Hyprland.focusedWorkspace.id === modelData
```

`Hyprland.focusedWorkspace` 는 **모니터별 활성 워크스페이스가 아니라 전역 포커스 워크스페이스 하나**다.
모니터별 활성 워크스페이스(`monitor.activeWorkspace`)를 쓰지 않는다.

**결과:** 모니터를 두 대 이상 붙이면 모든 모니터의 바가 **같은 칸 하나**를 포커스로 표시한다.
2번 모니터가 실제로 워크스페이스 3을 띄우고 있어도, 포커스가 1번 모니터에 있으면
2번 모니터 바도 1번 워크스페이스를 강조한다. 표시되는 목록도 모니터 구분 없이 전부 동일하다.

현재 이 머신은 `eDP-1` 단일 모니터라 증상이 드러나지 않는다.
외부 모니터를 붙일 계획이라면 미리 알아둘 것.

---

## 7. 바꾸고 싶다면

`shell.json` 에 넣을 수 있는 워크스페이스 옵션은 **없다.** 선택지는 두 가지다.

### (a) 위치만 옮기기 — 설정으로 가능

```bash
omarchy bar move omarchy.workspaces --section right
```

또는 `~/.config/omarchy/shell.json` 의 `bar.layout` 에서 항목을 직접 옮긴다 (저장 즉시 반영).

### (b) 표시 규칙 바꾸기 — 위젯 복제 필요

이 저장소가 복제본을 하나 들고 있다. 소스는 저장소 안에 있고,
[`install-workspaces-widget.sh`](../install-workspaces-widget.sh) 가 그걸 현재 OS 에 설치한다.

```
소스(편집 대상)  ./minsoft1115.workspaces/                       ← git 로 관리
설치본           ~/.config/omarchy/plugins/minsoft1115.workspaces/
```

```bash
./install-workspaces-widget.sh install   # 소스를 설치하고 바에 적용
./install-workspaces-widget.sh revert    # Omarchy 기본 위젯으로 원복
./install-workspaces-widget.sh status    # 지금 어느 쪽을 쓰는지
./install-workspaces-widget.sh diff      # 소스 vs 설치본, 소스 vs 원본
```

위젯을 고쳤으면 `install` 을 다시 돌리면 된다.

복제본은 바 위젯만이 아니라 **셸 서비스**도 함께 등록해서, Super 를 누르고 있으면
각 워크스페이스의 창 목록을 띄운다 — [Super 홀드 미리보기](workspace-peek-design.md) 참고.

#### 현재 복제본이 바꾼 것

포커스된 워크스페이스를 **숫자로** 보여 준다 (원본은 숫자를 지우고 글리프만 그린다).

```
[1] 2  3  4  5     ← 1번: 살짝 둥근 사각형 배경 + 굵은 숫자 (포커스)
                      2번: 창 있음 (밝게)  /  3~5번: 비어 있음 (흐리게)
```

- 숫자는 항상 표시. 10번은 `SUPER+0` 에 맞춰 `0`
- 포커스 표시는 **강조색이 아니라 반전** — 박스를 바의 본문색(`bar.text`)으로 채우고
  숫자를 배경색(`bar.background`)으로 뒤집는다. 테마의 `bar.active` 는 쓰지 않는다
- 포커스된 숫자만 **bold**
- 빈 워크스페이스 불투명도를 원본 `0.5` 에서 **`0.32`** 로 낮춰, 창이 있는 워크스페이스와의
  대비를 키웠다 (`emptyOpacity`)
- 튜닝 값은 파일 상단 프로퍼티로 뽑아 뒀다:

| 프로퍼티 | 현재 | 하는 일 |
|---|---|---|
| `focusInsetY` / `focusInsetX` | `space(5)` / `space(1)` | 포커스 박스 여백 (= 박스 크기) |
| `focusRadius` | `space(2)` | 모서리 둥글기. `0` 이면 각지고 `height/2` 면 알약 |
| `focusFillColor` | `bar.barForeground` | 박스 채움색 |
| `focusedTextColor` | `bar.background` | 박스 위 숫자색 (반전) |
| `boldWhenFocused` | `true` | 포커스된 숫자 굵게 |
| `emptyOpacity` | `0.32` | 창 없는 워크스페이스 불투명도 |

구현에서 걸린 두 가지:

- `WidgetButton` 에는 **배경 개념이 없다** (`Text` + `MouseArea` 뿐). 사용처에서 넣은 자식은
  라벨보다 나중에 추가되어 위에 덮이므로, 박스 `Rectangle` 에 `z: -1` 을 줘야 한다
- `WidgetButton` 은 **`font.bold` 를 노출하지 않는다.** 그래서 `labelVisible: false` 로 기본
  라벨을 끄고 숫자를 직접 그린다. 크기·클릭·툴팁은 그대로 `WidgetButton` 이 담당한다

#### 교체·원복이 왜 안전한가

복제본 매니페스트에 `omarchy.clonedFrom = "omarchy.workspaces"` 가 들어간다.
`PluginRegistry.setEnabled()` 는 이 값을 보고 바 레이아웃에서 원본 항목을 **제자리 교체**하고,
비활성화 시 `restoreCloneSource()` 가 같은 자리에 원본을 **제자리 복원**한다
(`services/PluginRegistry.qml`). 그래서:

- 바에서의 **위치(섹션·순서)가 보존**된다
- `shell.json` 을 손으로 편집할 필요가 없다
- 원본 `omarchy.workspaces` 는 `/usr/share/omarchy/` 에 그대로 있으므로 훼손 자체가 불가능하다

실제로 `install` → `revert` 왕복 후 `shell.json` 은 **교체 전과 완전히 동일**했다 (잔여 키 없음).

#### 실측으로 확인한 함정 세 개

**1. QML 편집은 `rescanPlugins` 로 반영되지 않는다.**
`omarchy-shell shell rescanPlugins` 는 내부적으로 `reloadPlugins()` → `Qt.clearComponentCache()`
까지 부르지만, 실제로 파일을 고쳐 넣고 호출해도 화면은 그대로였다 (포커스 라벨을 `X` 로
바꿔 놓고 확인). **`omarchy restart shell` 이 필요하다.** 그래서 스크립트의 `install` 은
파일이 바뀌었을 때 셸을 재시작한다.
반대로 `shell.json` 레이아웃 변경(교체/원복)은 핫 리로드되므로 `revert` 에는 재시작이 없다.

**2. 복사 직후 셸을 재시작하면 quickshell 이 죽는다.**
설치 위치는 Omarchy 가 inotify 로 감시하므로 **복사 자체가 플러그인 핫 리로드를 유발**한다.
그 리로드가 컴포넌트를 다시 만드는 중에 `omarchy restart shell`(내부적으로 `quickshell kill`)이
종료 IPC 를 보내면 경합이 난다:

```
#4  __dynamic_cast
#5  qs::io::ipc::IpcHandler::updateRegistration()
#6  qs::io::ipc::IpcHandler::onPostReload()
#7  QQmlObjectCreator::finalize(...)
```

이미 파괴 중인 IPC 레지스트리를 `dynamic_cast` 하면서 SIGSEGV. quickshell 0.3.0 에서
코어덤프 2건으로 확인했다 (재시작 11회 중 2회 — 타이밍 의존적인 경합).
어차피 종료 중이던 프로세스라 실질 피해는 없지만, 매번 30MB 대 코어덤프가 쌓인다.
그래서 스크립트는 **복사 후 리로드가 가라앉을 때까지 기다렸다가** 재시작한다
(`SETTLE_SECONDS`, 기본 2초).

**3. 심볼릭 링크로 걸면 안 된다.**
`~/.config/omarchy/plugins/<id>` 를 저장소로 심볼릭 링크하면 **플러그인 발견까지는 된다**
(스캔이 `for sub in "$dir"/*/` 글롭이라 링크된 디렉터리도 잡힌다). 하지만 변경 감시가
`inotifywait -m -r` 이고 이건 링크를 따라가지 않아서, 저장소 파일을 고쳐도 셸이 모른다.
그래서 스크립트는 링크가 아니라 **복사**로 설치한다.

> **`omarchy.*` 는 쓸 수 없다.** 레지스트리가 서드파티 플러그인의 `omarchy.` 접두사 id 를
> 거부한다 — "id is reserved for first-party Omarchy plugins" (`PluginRegistry.qml`).
> 그래서 복제본 id 는 `minsoft1115.workspaces` 다. 참고로 `omarchy plugin clone` 은
> id 를 `$USER.<name>` 로 강제하므로(`<username>.workspaces`) 이름을 고르려면 이 스크립트를 쓴다.

복제 후 흔히 손대는 지점:

| 하고 싶은 것 | 고칠 곳 |
|---|---|
| 항상 보이는 칸을 1~5 대신 1~4 나 1~9 로 | `workspaceIds()` 의 `var ids = [1, 2, 3, 4, 5]` |
| 10번 초과 워크스페이스도 표시 | `id <= 10` 조건 |
| 포커스를 강조색으로 (반전 대신) | `active: focused` 추가 — `bar.active` 색이 적용된다 |
| 창 없는 칸을 아예 숨기기 | `opacity` 대신 `visible: occupied \|\| focused` |
| 모니터별 활성 워크스페이스 강조 (6장 문제) | `Hyprland.focusedWorkspace` → 해당 바 화면의 `monitor.activeWorkspace` 로 교체 |
| 창 개수 뱃지 표시 | `workspace.toplevels.values.length` 를 이미 읽고 있으므로 그대로 활용 |

**절대 `/usr/share/omarchy/` 아래를 직접 고치지 말 것** — 다음 `omarchy update` 에 날아간다.
읽는 것은 안전하고 권장된다.

---

## 8. 확인에 쓴 명령

```bash
omarchy version                                   # 4.0.0-1
quickshell --version                              # 0.3.0 (quickshell-git)
pgrep -af quickshell                              # quickshell -n -p /usr/share/omarchy/shell
cat ~/.config/omarchy/shell.json                  # 바 레이아웃 (사용자)
cat /usr/share/omarchy/config/omarchy/shell.json  # 바 레이아웃 (기본값)
cat /usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml
cat ~/.local/state/omarchy/current/theme/shell.toml   # 색·크기 토큰
hyprctl workspaces -j                             # 현재 존재하는 워크스페이스
hyprctl monitors -j                               # 모니터별 activeWorkspace
```

조사 시점: 2026-08-18.
