# omarchy-setup

[Omarchy](https://omarchy.org) (Arch + Hyprland) 머신을 새로 깔았을 때 돌리는 셋업 스크립트 모음.

각 스크립트는 **독립 실행**되고 **idempotent** 하다 — 여러 번 돌려도 안전하며,
이미 적용된 항목은 `건너뜀` 으로 표시된다. 기존 설정 파일은 고치기 전에
`*.bak.<타임스탬프>` 로 백업한다.

```
install.sh                 진입점 — clone + 선택 설치
scripts/                   개별 설치 스크립트
minsoft1115.workspaces/    Quickshell 플러그인 소스 (바 위젯 + 셸 서비스)
hypr/                      Hyprland Lua 조각 (설치 시 ~/.config/minsoft1115/hypr/ 로)
bash/                      alias·function 소스 (설치 시 ~/.config/minsoft1115/bash/ 로)
docs/                      스크립트 문서와 조사 기록
```

---

## 한 줄로 전부 (install.sh)

clone 부터 선택 설치까지 한 번에 한다.

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh | bash
```

내용을 먼저 보고 싶으면 두 단계로:

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh -o install.sh
less install.sh
bash install.sh
```

저장소를 `~/.local/share/minsoft1115/omarchy-setup` 에 clone(있으면 pull)한 뒤,
**터미널을 다시 붙여** 자기 자신을 그 clone 에서 실행한다 — 파이프로 들어온 스크립트는
stdin 이 키보드가 아니라서 체크리스트가 그대로 EOF 를 읽고 아무것도 선택되지 않는다.

그다음 `gum` 체크리스트가 뜬다 (스페이스로 토글, Enter 로 확정):

```
What should be set up? (space toggles, enter confirms)
> [ ] [up to date]     Korean input — right Alt for 한/영 · Omarchy menu opens in Latin
  [✓] [needs update]   Bash config — Alt-R history picker · fzf search and kill · delta diffs
  [✓] [up to date]     └─ pkg-guards — answer pacman/yay with the omarchy command
  [✓] [not installed]  Workspaces bar — hold Super to see which apps are where before switching
```

- 상태가 **세 가지**다. 저장소 파일과 설치본을 **바이트 단위로 비교**해서 판정한다 —
  `git pull` 로 저장소가 앞섰거나 소스를 직접 고쳤으면 `needs update` 가 된다

  | 상태 | 뜻 | 기본 선택 |
  |---|---|---|
  | `not installed` | 설치된 적 없음 | ✓ |
  | `needs update` | 설치본이 저장소와 다름 | ✓ |
  | `up to date` | 저장소와 같음 | — |

  **할 일이 있는 것만 기본 선택**된다. 이미 최신인 걸 다시 돌릴 이유가 없다
- `pkg-guards` 는 bash 항목의 **하위 토글**이라 규칙이 다르다. 체크 = "이 파일을 원한다" 라서
  **설치돼 있으면 체크된 채로**, **설치돼 있지 않으면 체크 없이** 시작한다 (기본은 설치 안 함).
  체크된 채로 진행하면 설치·갱신되고, 해제하고 진행하면 회수된다
- 고른 순서와 무관하게 **실행 순서는 고정**이다 (`korean` → `bash-config` → `workspaces`).
  워크스페이스 위젯이 셸을 재시작하므로 마지막이다
- 하나가 실패해도 나머지는 계속하고, 끝에 요약이 나온다

**clone 은 지우지 않는다.** 세 스크립트 모두 저장소에서 설치하고(alias·위젯 소스·Hyprland 조각),
고친 뒤 다시 돌리는 게 반영 방법이라 지우면 갱신 경로가 사라진다. 다시 실행하면 pull 부터 한다.

| 옵션 | 하는 일 |
|---|---|
| `--all` | 묻지 않고 전부 |
| `--only korean,bash-config` | 이름으로 지정 (`--list` 의 첫 열) |
| `--guards` / `--no-guards` | pkg-guards 답을 미리 정함 |
| `--list` | 설치 가능한 것과 현재 상태만 출력 |
| `--dry-run` | 무엇이 돌지만 보여 주고 실행 안 함 |
| `--dir <경로>` | clone 위치 변경 |
| `--remove` | 되돌리기. 같은 체크리스트가 **전부 해제된 상태**로 뜨고 설치의 역순으로 진행 |
| `--purge` | `--remove` 와 함께 쓰면 마지막에 clone 까지 삭제 |

설치는 잘못 골라도 다시 돌리면 되지만 제거는 아니라서, `--remove` 는 기본 선택이 없다.

자세한 내용은 [docs/install.md](docs/install.md) 참고.

---

# 개별 스크립트

`install.sh` 없이 하나만 돌려도 된다. 전부 저장소 안에서 실행한다 — 소스(`bash/`, `hypr/`,
`minsoft1115.workspaces/`)를 읽어 설치하기 때문이다.

```bash
git clone https://github.com/minsoft1115/omarchy-setup.git
cd omarchy-setup
```

`install.sh` 를 이미 한 번 돌렸다면 clone 이 `~/.local/share/minsoft1115/omarchy-setup` 에 있다.

---

## setup-korean.sh

fcitx5 + hangul 을 설치·설정해서 한글 입력을 쓸 수 있게 만든다.
오른쪽 Alt 를 한/영 키로 잡고, tmux 와 충돌하는 `Control+space` 트리거를 없애고,
Super+Space 메뉴가 항상 영문으로 열리게 한다.

```bash
./scripts/setup-korean.sh
```

이미 세팅된 머신에 키 설정만 다시 입히려면 (패키지·sudo 안 건드림):

```bash
./scripts/setup-korean.sh --light
```

되돌리려면 (이 스크립트가 만든 것만 — fcitx5 설정은 그대로 둔다):

```bash
./scripts/setup-korean.sh remove
```

Hyprland 설정은 **원본 파일을 고치지 않는다.** Lua 조각을 `~/.config/minsoft1115/hypr/` 에
두고, `hyprland.lua` 에 마커로 감싼 `require` 줄만 넣는다 (`install-workspaces-widget.sh` 와 같은 방식).

자세한 내용은 [docs/setup-korean.md](docs/setup-korean.md) 참고.

---

## install-bash-config.sh

저장소의 `bash/` 안에 있는 alias·function 파일을 `~/.config/minsoft1115/bash/` 로 복사하고,
`~/.bashrc` 가 그것들을 읽게 만든다. 로더는 파일 하나씩 적는 대신 **폴더를 훑는 루프**라,
나중에 `bash/` 에 파일을 추가해도 `install` 만 다시 돌리면 되고 `~/.bashrc` 는 다시 안 건드린다.

### 뭐가 들어오나

| 파일 | 내용 |
|---|---|
| `bash/aliases.sh` | `cat` → `bat -p` (하이라이팅), `grep` → `rg` |
| `bash/fhistory.sh` | `fhistory` — **Alt-R** 로 히스토리를 fzf 로 골라 **실행하지 않고 프롬프트에 채워 넣는다** (실행은 직접 Enter). 목록은 `history` 순서 그대로 있고, 검색어를 쳐도 **줄이 사라지거나 재정렬되지 않은 채 커서만** 최적 매치로 간다. Ctrl-Y 로 명령 복사. Ctrl-R 은 fzf 기본 위젯에 그대로 둔다 |
| `bash/fkill.sh` | `fkill` — 내 프로세스 목록을 fzf 로 골라 종료. `fkill -9` 처럼 시그널을 넘길 수 있다 |
| `bash/fsearch.sh` | `fsearch` — 파일 내용 검색(rg)을 fzf 로 훑어보기. `fsearch TODO` / `fsearch md TODO` (확장자 한정), Enter 로 `$EDITOR` 열기, Ctrl-Y 로 경로 복사 |
| `bash/gdiff.sh` | `gdiff` — `git diff` 를 `delta` 로 넘겨 본다. 인자는 그대로 전달 |
| `bash/pkg-guards.sh` | **선택** — `pacman`·`yay` 를 실행 대신 안내로 막고(`omarchy pkg add` / `omarchy pkg drop` / `omarchy pkg aur add` / `omarchy update`), `sudo` 뒤에 공백을 둬 `sudo pacman` 도 걸리게 한다 |

`pkg-guards.sh` 는 Omarchy 가 이미 비슷한 것을 갖고 있어서 **설치할지 물어본다** — 이 스크립트를
직접 돌리면 `gum confirm` 으로, `install.sh` 로 돌리면 체크리스트의 하위 행으로 답한다.
Omarchy 기본 rc 다음에 로드되므로 같은 이름이면 이쪽이 이기고, 로드 순서는 **파일명 순**이다.
의존 도구(`git-delta`, `bat`, `ripgrep`, `fzf`)는 `install` 이 **`omarchy pkg` 로 먼저 깐다.**

```bash
./scripts/install-bash-config.sh install
```

프로세스는 자기를 실행한 셸을 바꿀 수 없다. 새 터미널은 그냥 적용되고, **지금 쓰고 있는
셸에도 바로 넣고 싶으면 실행 대신 source** 하면 된다.

```bash
source ./scripts/install-bash-config.sh install
```

되돌리려면:

```bash
./scripts/install-bash-config.sh remove
```

자세한 내용은 [docs/bash-config.md](docs/bash-config.md) 참고.

---

## install-workspaces-widget.sh

**어느 워크스페이스로 갈지 정하기 전에, 거기 뭐가 떠 있는지 먼저 보는 것**이 목적이다.
Super 를 누르고 있으면 창이 있는 워크스페이스와 그 창 목록이 뜬다. 번호만 보고 기억에 의존해
왔다 갔다 하던 걸 없앤다. 덤으로 포커스된 워크스페이스도 글리프 대신 **숫자 그대로** 둔다.

![워크스페이스 위젯과 Super 홀드 미리보기](screenshots/workspaces-widget.png)

바에서 1번은 포커스(반전된 숫자), 2번은 창 있음, 3~5번은 비어 있어 흐리게 나온다.
Super 를 누르고 있으면 아래 팝업이 떠서 각 워크스페이스의 창 목록을 보여 준다.

Quickshell 플러그인과 Hyprland 키 바인딩을 함께 설치한다.

```bash
./scripts/install-workspaces-widget.sh install
```

되돌리려면:

```bash
./scripts/install-workspaces-widget.sh revert
```

자세한 내용은 [docs/workspaces-widget.md](docs/workspaces-widget.md) 참고.

---

## 문서

| 문서 | 내용 |
|---|---|
| [docs/install.md](docs/install.md) | `install.sh` — 부트스트랩, 체크리스트, 되돌리기 |
| [docs/setup-korean.md](docs/setup-korean.md) | `setup-korean.sh` — 단계별 동작, 건드리는 파일, 문제 해결 |
| [docs/bash-config.md](docs/bash-config.md) | `install-bash-config.sh` — 로더 구조, 선택 파일, 로드 순서 함정 |
| [docs/workspaces-widget.md](docs/workspaces-widget.md) | `install-workspaces-widget.sh` — 무엇이 바뀌나, 구성, 튜닝 |

### 참고 기록

스크립트는 아니고, Omarchy 가 어떻게 굴러가는지 조사해 둔 기록.

| 문서 | 내용 |
|---|---|
| [docs/quickshell-workspaces.md](docs/quickshell-workspaces.md) | Omarchy 4.0 바의 워크스페이스 인디케이터가 그려지는 방식 — 데이터 출처, 표시 규칙, 클릭 동작, 커스터마이즈 지점 |
| [docs/workspace-peek-design.md](docs/workspace-peek-design.md) | Super 홀드 미리보기의 설계와 실측 기록 — 키 바인딩 동작, release 유실, 팝업 크기 계산에서 틀렸던 것들 |
