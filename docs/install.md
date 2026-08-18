# install.sh

> [omarchy-setup](../README.md) 의 진입점. 개별 스크립트는 `scripts/` 에 있다.

clone 부터 선택 설치까지 한 번에 한다. 개별 스크립트를 직접 돌려도 되고, 이건 그것들을
묶어 주는 얇은 층이다.

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh | bash
```

내용을 먼저 보고 싶으면 두 단계로:

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/install.sh -o install.sh
less install.sh
bash install.sh
```

---

## 흐름

```
curl | bash
 └─ clone → ~/.local/share/minsoft1115/omarchy-setup   (있으면 git pull --ff-only)
     └─ 터미널을 다시 붙여 clone 안의 자신을 exec
         └─ gum 체크리스트
             └─ 고른 것들을 고정 순서로 실행 → 요약
```

**터미널을 다시 붙이는 게 핵심이다.** 파이프로 들어온 스크립트는 stdin 이 키보드가 아니라서,
그대로 두면 체크리스트가 EOF 를 읽고 아무것도 선택되지 않는다. 그래서 clone 이 끝나면
`exec bash "$CLONE/install.sh" ... < /dev/tty` 로 넘긴다.

---

## 체크리스트

```
What should be set up? (space toggles, enter confirms)
> [ ] [up to date]     Korean input — right Alt for 한/영 · Omarchy menu opens in Latin
  [✓] [needs update]   Bash config — Alt-R history picker · fzf search and kill · delta diffs
  [✓] [up to date]     └─ pkg-guards — answer pacman/yay with the omarchy command
  [✓] [not installed]  Workspaces bar — hold Super to see which apps are where before switching
```

- 상태는 **세 가지**다.

  | 상태 | 뜻 | 기본 선택 |
  |---|---|---|
  | `not installed` | 설치된 적 없음 | ✓ |
  | `needs update` | 설치돼 있지만 저장소 쪽이 다름 (`git pull` 뒤) | ✓ |
  | `up to date` | 저장소와 같음 | — |

  전부 `up to date` 면 헤더가 `Everything is up to date — pick anything to re-apply` 로 바뀐다.
  판정은 저장소 파일과 설치본을 **직접 비교**한다. 각 스크립트의 `status` 출력을 파싱하지
  않는다 — 메뉴에 한 단어 띄우자고 남의 문구에 묶일 이유가 없다.

- **`pkg-guards` 는 bash 항목의 하위 토글**로 같이 뜬다. 이건 "할 일" 이 아니라 **원하는
  상태**라, 설치돼 있으면 체크된 채로 시작한다. 체크하고 진행하면 `--with-optional`,
  해제하고 진행하면 `--no-optional`(이미 깔린 것도 회수)이 하위 스크립트로 넘어간다
- 체크 표시는 `[✓]` / `[ ]` 로 그린다. gum 기본값인 `✓` 와 `•` 는 한눈에 구분되지 않는다
- 라벨에 **콤마를 쓰면 안 된다.** gum 은 미리 선택할 항목을 콤마로 구분된 한 문자열로 받아
  옵션 텍스트와 대조하므로, 라벨 안의 콤마가 그 목록을 쪼개 매칭이 조용히 실패한다
- 고른 순서와 무관하게 **실행 순서는 고정**이다: 한글 → bash → 위젯.
  위젯이 `omarchy restart shell` 로 바를 재시작하므로 마지막이다
- `gum` 이 없으면 항목별 `[Y/n]` 로 묻는다
- **물어볼 터미널이 아예 없으면 거부한다.** CI·cron·프로비저닝 스크립트처럼 보는 사람이 없는
  곳에서 동의를 넘겨짚지 않는다. 그런 환경에서는 `--all` 이나 `--only` 로 명시해야 한다

```
[x] no terminal to ask at — say what you want with --all or --only korean,bash,widget
```

### 미리 답해 두는 질문

[선택 파일 `pkg-guards.sh`](bash-config.md#선택-파일) 는 위 체크리스트의 하위 항목으로 함께
답한다. 그래야 하위 스크립트가 설치 도중에 멈추지 않는다. `--guards` / `--no-guards` 로
아예 물어보지 않게 할 수도 있다.

---

## 옵션

| 옵션 | 하는 일 |
|---|---|
| `--all` | 묻지 않고 전부 |
| `--only korean,bash` | 이름으로 지정 |
| `--guards` / `--no-guards` | pkg-guards 답을 미리 정함 |
| `--list` | 설치 가능한 것과 현재 상태만 출력 |
| `--dry-run` | 무엇이 돌지만 보여 주고 실행 안 함 |
| `--remove` | 되돌리기 (아래) |
| `--purge` | `--remove` 와 함께 쓰면 마지막에 clone 까지 삭제 |
| `--dir <경로>` | clone 위치 변경 |

```bash
./install.sh --list
./install.sh --only widget
./install.sh --all --no-guards
```

---

## 되돌리기

```bash
./install.sh --remove
```

- 같은 체크리스트가 **전부 해제된 상태**로 뜬다. 설치는 잘못 골라도 다시 돌리면 되지만
  제거는 아니다
- **설치의 역순**으로 진행한다 (위젯 → bash → 한글)
- 끝나면 `~/.config/minsoft1115/` 가 비었을 때 정리한다
- 물어볼 터미널이 없으면 **거부한다** (설치와 같다)

무엇을 지우는지는 각 스크립트가 정한다. 특히 한글 쪽은 **fcitx5 설정을 일부러 남긴다** —
[docs/setup-korean.md](setup-korean.md) 참고.

`--purge` 는 clone 까지 지운다. 실행 중인 스크립트 파일을 지우면 bash 가 나머지를 못 읽으므로,
`exec` 로 프로세스를 갈아탄 뒤 지운다.

---

## clone 을 남기는 이유

세 스크립트 모두 **저장소에서 설치한다** — alias·function 소스, 위젯 QML 소스, Hyprland Lua
조각이 전부 저장소에 있고, 고친 뒤 다시 돌리는 게 반영 방법이다. 첫 실행 후 지우면 갱신
경로가 사라진다. 그래서 임시 폴더가 아니라 고정 위치에 두고 남긴다.

```
~/.local/share/minsoft1115/omarchy-setup
```

다시 실행하면 `git pull --ff-only` 부터 한다. fast-forward 가 안 되면 경고만 하고 있는 그대로
쓴다 — 로컬에서 고쳐 둔 것을 덮지 않기 위해서다.

---

## 실패 처리

한 단계가 실패해도 **나머지는 계속**하고, 끝에 요약이 나온다.

```
== Summary ==
  korean ok
  bash FAILED
  widget ok
```

전형적인 실패는 패키지 설치 단계에서 sudo 비밀번호를 못 받는 경우다. 그때도 설정 파일 설치는
진행되므로, 패키지만 따로 깔고 다시 돌리면 나머지는 전부 `skipped` 로 지나간다.
