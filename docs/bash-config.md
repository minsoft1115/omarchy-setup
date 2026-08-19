# install-bash-config.sh

> [omarchy-setup](../README.ko.md) 의 스크립트 중 하나.

저장소의 alias·function 파일을 `~/.config/minsoft1115/bash/` 로 복사하고, `~/.bashrc` 가
그것들을 읽게 만든다.

**모든 동작이 idempotent** — 여러 번 실행해도 안전하며, 이미 된 항목은 `skipped` 로 표시된다.

## 무엇이 들어오나

| 파일 | 내용 |
|---|---|
| `bash/aliases.sh` | `cat` → `bat -p` (하이라이팅), `grep` → `rg` |
| `bash/fhistory.sh` | `fhistory` — **Alt-R** 로 히스토리를 fzf 로 골라 **실행하지 않고 프롬프트에 채워 넣는다**. 목록은 `history` 순서 그대로 두고 커서만 최적 매치로 이동한다 (`--raw` + `best`). Ctrl-Y 로 명령 복사. Ctrl-R 은 fzf 기본 위젯에 그대로 둔다 |
| `bash/fkill.sh` | `fkill` — 내 프로세스를 fzf 로 골라 종료. `fkill -9` 처럼 시그널 전달 가능 |
| `bash/fsearch.sh` | `fsearch` — 파일 내용 검색(rg)을 fzf 로 훑어보기. `fsearch TODO` / `fsearch md TODO`, Enter 로 `$EDITOR`, Ctrl-Y 로 경로 복사 |
| `bash/gdiff.sh` | `gdiff` — `git diff` 를 `delta` 로 넘긴다. 인자는 그대로 전달 |
| `bash/zz-pkg-guards.sh` | **선택** — `pacman`·`yay` 를 실행하기 전에 대신 쓸 omarchy 명령을 제시하고 **정말 실행할지 물어본다**. 조회 명령은 묻지 않는다 |

---

## 요구 사항

- `bash`
- 의존 도구는 `install` 이 **`omarchy pkg` 로 먼저 깐다** — `git-delta`(명령은 `delta`),
  `bat`, `ripgrep`(명령은 `rg`), `fzf`, `gum`(패키지 가드가 묻는 메뉴). 이미 있으면 건너뛴다
- `omarchy` 가 없으면 경고만 하고 셸 파일 설치는 계속한다. **`pacman` 을 직접 부르지 않는다**
- 선택 파일 질문에는 `gum` 을 쓴다. 없으면 `[y/N]` 로 묻는다

`Ctrl-Y` 로 클립보드에 넣는 동작은 `wl-clipboard` 의 `wl-copy` 를 쓴다.

---

## 사용법

여러 스크립트를 한 번에 돌리려면 [`install.sh`](install.md) 를 쓴다.

```bash
./scripts/install-bash-config.sh status     # 지금 상태 (기본 동작)
./scripts/install-bash-config.sh install    # 복사 + ~/.bashrc 에서 로드
./scripts/install-bash-config.sh remove     # 로더 제거 + 설치본 삭제
./scripts/install-bash-config.sh diff       # 소스 vs 설치본
```

| 옵션 | 하는 일 |
|---|---|
| `--skip-packages` | 패키지는 건드리지 않고 파일만 설치 |
| `--with-optional` | 선택 파일을 묻지 않고 설치 |
| `--no-optional` | 묻지 않고 제외 (이미 깔린 것도 회수) |

### status 출력 예

```
source (edit here) : /path/to/repo/bash (present)
installed copy     : ~/.config/minsoft1115/bash (present)
in sync with source: yes
loaded by .bashrc  : yes
dependencies       : git-delta(ok) bat(ok) ripgrep(ok) fzf(ok) gum(ok)
optional files     : zz-pkg-guards.sh(installed)
```

---

## 지금 쓰는 셸에 반영하기

프로세스는 **자기를 실행한 셸을 바꿀 수 없다.** 그래서 실행만으로는 지금 열려 있는 터미널에
alias 가 생기지 않는다. 새로 여는 터미널은 그냥 적용된다.

지금 이 셸에도 바로 넣으려면 실행 대신 **source** 한다.

```bash
source ./scripts/install-bash-config.sh install
```

source 로 부르면 실제 작업은 자식 프로세스에 넘기고(변수·함수가 호출자에 새지 않는다)
마지막 `source ~/.bashrc` 만 호출자 셸에서 한다. 그냥 실행하면 그 사실을 알려 준다.

---

## 로더

`~/.bashrc` 끝에 마커로 감싼 블록이 들어간다. 파일마다 source 줄을 적는 대신 **폴더를 훑는
루프**라, 나중에 `bash/` 에 파일을 추가해도 `install` 만 다시 돌리면 되고 `~/.bashrc` 는 다시
안 고친다.

```bash
# minsoft1115-bash:begin
for __minsoft1115_rc in "$HOME/.config/minsoft1115/bash"/*.sh; do
  [ -r "$__minsoft1115_rc" ] && . "$__minsoft1115_rc"
done
unset __minsoft1115_rc
# minsoft1115-bash:end
```

Omarchy 가 자기 bash rc 를 읽은 **뒤에** 붙으므로, 같은 이름이면 이쪽이 이긴다.

### fzf 에 맡긴 것

`fhistory` 는 "목록 순서는 그대로, 커서만 최적 매치로" 를 fzf 기본 기능으로 한다.

```bash
fzf --tac --raw --no-sort --bind 'result:best'
```

`--raw` 는 매치되지 않는 줄도 흐리게 **화면에 남기고**, `best` 액션이 그중 최고 점수 항목으로
커서를 옮긴다. **둘은 같이 써야 의미가 있다** — `--raw` 없이는 fzf 가 비매치 줄을 걸러 내므로
`best` 가 `first` 와 같아진다 (man 에도 그렇게 적혀 있다). 실측으로도 `--raw` 없이는 첫 줄로,
있으면 실제 매치 줄로 커서가 갔다.

### 로드 순서가 규칙을 하나 만든다

파일은 **이름순**으로 로드되고, bash 는 **함수 본문을 읽는 시점에 alias 를 펼친다.**
그래서 `aliases.sh` 가 먼저 로드되면, 뒤에 오는 함수 파일 안의 명령까지 alias 로 치환된다.

`fkill.sh` 의 `ps -ef | grep "$USER"` 는 실제로 `rg "$USER"` 로 박혀 들어간다. 의도한 게
아니라면 함수 안에서 `command grep` 을 쓰면 된다. (`find -exec grep` 처럼 명령 위치가 아닌
자리는 영향받지 않는다.)

순서를 강제하고 싶으면 접두사를 붙이면 된다. `zz-pkg-guards.sh` 가 그렇게 해서 **맨 나중에**
로드된다 — 다른 파일이 건 `alias sudo=...` 를 넘겨받아야 하는데, 그러려면 그 alias 가 이미
존재해야 하기 때문이다. 숫자 접두사(`10-`)로는 안 된다. 숫자가 글자보다 먼저 정렬되므로
`sudo-pop.sh` 뒤로 갈 수 없다.

---

## 선택 파일

`zz-pkg-guards.sh` 는 Omarchy 가 이미 비슷한 alias 를 갖고 있어서, `install` 이 **설치할지
물어본다.**

```
┌ Install zz-pkg-guards.sh?
│ Ask before pacman or yay runs, and name the omarchy command that replaces it.
│   Yes    No
```

- 질문 문구는 **그 파일의 첫 주석 줄**을 그대로 쓴다 — 설명이 두 군데로 갈라지지 않는다
- **이미 설치돼 있으면 다시 묻지 않는다.** 매번 뜨는 프롬프트는 안 읽고 넘기게 된다
- 질문은 stdin 이 아니라 **`/dev/tty` 에** 한다. 출력을 파이프로 넘겨도 질문은 사람 앞에 뜨고,
  제어 터미널이 아예 없으면(cron·훅) 건너뛴다
- 선택 파일을 뺀 상태도 `in sync: yes` 로 본다 — 그건 차이가 아니라 선택이다

---

## 패키지 가드 (`zz-pkg-guards.sh`)

Omarchy 에서 패키지는 omarchy 를 통해 드나든다. 그걸 지나쳐 pacman 을 직접 부르면 omarchy 가
만들지 않은 상태가 남는다. 그렇다고 **막아 버리면** 진짜로 pacman 이 필요한 순간마다
`command pacman ...` 으로 줄 전체를 다시 쳐야 한다. 그래서 막지 않고 **묻는다.**

```
$ sudo pacman -S ripgrep
Omarchy manages packages on this machine.
> omarchy pkg add ripgrep
  run as typed: sudo pacman -S ripgrep
  cancel
```

- 커서는 **권장안에 놓인 채로 뜬다** — 그대로 Enter 면 omarchy 명령이 실행된다. 1행에 뜨는
  문자열이 곧 실행되는 **완본 명령**이다 (보여줄 때와 실행할 때 같은 값을 쓴다)
- 제안이 터미널 폭보다 길면 **헤더에 접어서 한 번 더** 띄운다. `gum` 은 행을 폭에서 자르는데
  말줄임표가 붙지 않아, 패키지가 여러 개일 때 뒤쪽이 소리 없이 사라진다. 실측: 폭 60에서
  행은 58자까지 살고 59자부터 잘리며, **헤더는 우리가 넣은 줄바꿈을 지킨다**
- Esc 또는 `cancel` 은 아무것도 실행하지 않고 종료 코드 130
- `gum` 이 없으면 같은 세 답을 번호로 묻는다. 물어볼 터미널이 아예 없으면 **친 대로 실행**한다 —
  이 파일은 대화형 셸에서만 로드되므로 드문 경우고, 아무도 못 보는 질문 때문에 명령을
  실패시킬 이유는 없다
- **omarchy 가 없는 머신에서는 통째로 비활성**이다. 물어볼 근거가 그 명령들이라서다

### 무엇을 무엇으로 바꿔 제안하나

| 친 것 | 제안 |
|---|---|
| `pacman -S <pkg>` | `omarchy pkg add <pkg>` |
| `pacman -R <pkg>` / `-Rns` | `omarchy pkg drop <pkg>` |
| `pacman -Syu` / `-Su` | `omarchy update` |
| `yay -S <pkg>` | `omarchy pkg aur add <pkg>` |
| `yay` (인자 없음) | `omarchy pkg aur install` (피커) |

짧은 묶음(`-Syu`)과 긴 옵션(`--sync --refresh --sysupgrade`)을 같은 것으로 읽는다.
`pacman -U ./x.pkg.tar.zst` 처럼 대응하는 omarchy 명령이 없으면 제안 없이 **실행할지만**
묻는다 (`gum confirm`).

### 조회는 묻지 않는다

`pacman -Q`, `-Qi`, `-Ss`, `-Si`, `-Sl`, `-Sg`, `-Sp`, `-T`, `-V`, 인자 없는 `pacman`,
`yay -Ss` … 는 시스템을 바꾸지 않고 root 도 필요 없다. 그대로 통과시킨다. 예전 버전이
성가셨던 이유의 대부분이 **조회하러 가는 길에 막히는 것**이었다.

`-Sy`, `-Sw`, `-Sc` 는 조회가 아니다. `-F` 는 `-Fy` 로 DB 를 갱신할 때만 묻는다.

### `sudo pacman` 을 잡는 법 — 그리고 그 대가

`sudo` 뒤의 단어까지 보려면 뭔가가 `sudo` 를 가로채야 한다. 예전 파일은 `alias sudo='sudo '`
였다 — alias 값이 공백으로 끝나면 bash 가 **다음 단어도 alias 로 펼친다.** 하지만 메뉴는
alias 한 줄에 안 들어가고, **sudo 는 셸 함수를 실행할 수 없다.** 그래서 `sudo` 자체를 함수로
만들고, pacman·yay 가 아닌 것은 그대로 넘긴다.

여기서 걸리는 게 **alias 가 함수보다 먼저 펼쳐진다**는 점이다. 이 파일 뒤에 로드되는
`alias sudo=...` 가 있으면 함수는 영영 불리지 않는다. sudo-pop 이 정확히 그걸 깐다
(`alias sudo='sudo-pop'`). 실측:

| 정의 순서 | `sudo pacman -Syu` 가 부르는 것 |
|---|---|
| 함수 먼저 → alias 나중 | **alias** |
| alias 를 `${BASH_ALIASES[sudo]}` 로 받아 두고 `unalias` → 함수 정의 | 함수 (받아 둔 `sudo-pop` 을 호출) |

그래서 이 파일은 이름이 `zz-` 로 시작한다. 로드 시점에 alias 를 넘겨받아 지우고, 답이 예일
때 **넘겨받은 것**을 부른다. sudo-pop 은 자기가 감싸였다는 걸 몰라도 되고, 없어도 된다.

대가가 하나 있다. **`\sudo` 로는 더 이상 원래 sudo 에 닿지 않는다** — 백슬래시는 alias 만
막고 함수는 못 막는다. `pacman`·`yay` 도 마찬가지다.

```bash
command sudo whoami      # 원래 sudo (sudo-pop 을 깔았다면 sudo-pop)
command pacman -Syu      # 가드 없이 pacman
/usr/bin/sudo whoami     # 어떤 셸 정의도 거치지 않는다
```

---

## 안전성

- 설치 전에 `bash -n` 으로 **모든 소스 파일을 문법 검사**한다. `~/.bashrc` 가 읽는 파일이
  깨지면 새로 여는 터미널이 전부 망가지고, 보통 모든 터미널이 죽은 뒤에야 알아차린다
- 설치 후 `bash --rcfile <파일> -i` 로 대화형 셸을 한 번 띄워 정상 로드되는지 확인한다
  (긴 옵션이 먼저 와야 한다 — `bash -i --rcfile` 은 거부된다)
- `~/.bashrc` 는 고치기 전에 `*.bak.<타임스탬프>` 로 백업
- 저장소에서 지운 파일은 다음 `install` 때 설치본에서도 정리된다 — 단 **이 스크립트가 깐
  것만** (아래)

`install` → `remove` 왕복 후 `~/.bashrc` 가 **원본과 바이트 단위로 동일**한 것을 확인했다.

---

## 알아둘 것

`remove` 는 로더와 설치본을 지우지만, **이미 열려 있는 셸은 로드해 둔 정의를 그대로 갖고
있다.** `source ~/.bashrc` 로도 안 사라진다 — 이미 정의된 함수는 남는다. 그 터미널만 새로
열면 된다.

`~/.config/minsoft1115/` 상위 폴더는 남긴다. 다른 것도 같은 네임스페이스를 쓴다
([Hyprland 조각](setup-korean.md)이 그렇다).

### 설치 폴더는 우리 것만이 아니다

`~/.config/minsoft1115/bash/` 에는 다른 도구도 조각을 넣는다 — sudo-pop 이 `--init` 으로
`sudo-pop.sh` 를 거기 깐다. 그래서 **깐 파일 목록을 `.installed` 에 적어 두고**, 지우는
것은 그 목록에 있는 것만으로 제한한다. 목록에 없는 파일은 이렇게만 말하고 놔둔다.

```
[+] left alone: sudo-pop.sh (not installed by this script)
```

`remove` 도 마찬가지다. 폴더째 `rm -rf` 하지 않고 목록에 적힌 것만 지운 뒤, 비었을 때만
폴더를 없앤다. 예전에는 저 두 동작이 **`install` 을 돌릴 때마다 sudo-pop 의 alias 를
지웠다** — 그리고 그 alias 는 지금 패키지 가드가 넘겨받아 쓰는 바로 그것이다.

`.installed` 는 점으로 시작해서 로더의 `*.sh` 글롭에 걸리지 않는다.
