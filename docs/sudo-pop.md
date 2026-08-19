# install-sudo-pop.sh

> [omarchy-setup](../README.ko.md) 의 스크립트 중 하나.

[sudo-pop](https://github.com/minsoft1115/sudo-pop) 을 소스에서 빌드해 설치한다.
sudo 비밀번호를 터미널이 아니라 **팝업 창**에서 받는 도구다 — 터미널의 stdin/stdout/stderr 는
그대로 실제 명령에 닿으므로 `pacman` 의 `[Y/n]` 도, 전체화면 `vim` 도 평소대로 동작한다.

**모든 동작이 idempotent** — 여러 번 돌려도 안전하고, 이미 된 것은 `skipped` 로 표시된다.

```
$ sudo pacman -Syu
   → 화면 가운데에 비밀번호 창이 뜨고, 입력하면 pacman 이 하던 대로 이어진다
```

---

## 이 스크립트가 다른 것들과 다른 점

**소스가 이 저장소에 없다.** 나머지 세 스크립트는 저장소 안의 파일을 복사하지만, sudo-pop 은
자기 저장소를 갖고 있고 Rust 로 **빌드**해야 한다. 그래서 이 스크립트는 복사가 아니라
clone + 빌드를 한다.

```
소스(빌드도 여기서)  ~/.local/share/minsoft1115/sudo-pop     git clone, main 브랜치
바이너리             ~/.local/bin/sudo-pop
```

### 왜 clone 인가 — upstream 의 curl 한 줄이 아니라

sudo-pop 은 `curl ... | bash` 설치기를 갖고 있고 그걸 그대로 써도 된다. 하지만 이 저장소의
체크리스트는 **"깔려 있나 / 최신인가"** 를 빌드하지 않고 답할 수 있어야 한다. 빌드는 몇 분이
걸리므로 "돌려 보면 안다" 는 답이 될 수 없다.

그런데 **sudo-pop 에는 `--version` 이 없다.** `--init`·`--uninit` 이 아닌 인자는 전부 sudo 로
넘어가므로 `sudo-pop --version` 은 sudo 를 실행한다. 바이너리에게 물어볼 수가 없다.

체크아웃이 그 답을 커밋 id 로 준다. 빌드한 커밋을 적어 두고, 체크아웃·upstream 과 비교한다.
실제 빌드는 여전히 **upstream 의 install.sh** 가 한다 — 체크아웃 안에서 실행하면 그 체크아웃을
빌드하고 아무것도 내려받지 않는다.

**`main` 고정이다.** sudo-pop 에는 아직 태그가 없어서 `--ref` 는 유효한 값이 하나뿐인 손잡이다.

---

## 요구 사항

| | |
|---|---|
| Hyprland | 0.56 이상 (팝업 창 규칙이 Lua 설정 기준) |
| sudo | askpass(`-A`) 지원. 1.9.17 에서 확인 |
| `cc` | C 링커. **없으면 실패한다** — `omarchy pkg add base-devel` |
| Rust | `cargo`, 없으면 `mise` 가 `mise.toml` 의 핀을 보고 받아 온다 |
| `git` | clone 과 상태 판정(`git ls-remote`) |

`mise` 는 **Omarchy 기본 패키지**(`omarchy-base.packages`)라 갓 깐 머신에 이미 있다. 그래서
Rust 를 따로 설치하지 않는다. 반면 `cc` 는 없으면 그 자리에서 멈춘다 — `base-devel` 은 그룹이고
설치에 sudo 가 필요한데, 하필 sudo 를 갈아 끼우려는 참에 남의 sudo 를 대신 부를 이유가 없다.

---

## 사용법

여러 스크립트를 한 번에 돌리려면 [`install.sh`](install.md) 를 쓴다.

```bash
./scripts/install-sudo-pop.sh status     # 지금 상태 (기본 동작)
./scripts/install-sudo-pop.sh install    # clone/pull → 빌드 → 설치 → --init
./scripts/install-sudo-pop.sh remove     # upstream 의 --uninstall 에 맡긴다
```

| 옵션 | 하는 일 |
|---|---|
| `--force` | 체크아웃이 이미 설치된 커밋과 같아도 다시 빌드 |
| `--purge` | `remove` 와 함께 쓰면 소스 clone(빌드 트리 포함)까지 삭제 |
| `--prefix <경로>` | 바이너리 위치 (기본 `~/.local/bin`) |

### status 출력 예

```
source (built here): ~/.local/share/minsoft1115/sudo-pop (main @ 9ac7629, 1.2G with the build tree)
upstream main      : 9ac7629 (checkout is current)
binary             : ~/.local/bin/sudo-pop (present, built from 9ac7629)
on PATH            : yes
shell alias        : ~/.config/minsoft1115/bash/sudo-pop.sh (present)
window rules       : ~/.config/minsoft1115/hypr/sudo-pop.lua (present), required by hyprland.lua
build tools        : cc(ok) rust(cargo)
```

`upstream` 줄만 네트워크를 쓴다 (5초 타임아웃). 못 닿으면 그렇게 적고 넘어간다.

---

## 무엇이 설치되나

| 경로 | 누가 쓰나 |
|---|---|
| `~/.local/share/minsoft1115/sudo-pop/` | 이 스크립트 (clone + 빌드 트리) |
| `~/.local/bin/sudo-pop` | upstream install.sh |
| `~/.config/minsoft1115/bash/sudo-pop.sh` | `sudo-pop --init` — `alias sudo='sudo-pop'` |
| `~/.config/minsoft1115/hypr/sudo-pop.lua` | `sudo-pop --init` — 팝업 창 규칙 (float·center·화면 공유 제외) |
| `~/.config/hypr/hyprland.lua` | `sudo-pop --init` — `-- sudo-pop:begin/end` 마커로 감싼 require 한 줄 |
| `$XDG_RUNTIME_DIR/sudo-pop/askpass` | sudo-pop 실행 시 (0700, sudo 가 exec 하는 심볼릭 링크) |
| `~/.local/state/minsoft1115/sudo-pop.rev` | 이 스크립트 — **빌드한 커밋** |

설정은 전부 sudo-pop 자신이 쓴다. 이 스크립트가 따로 만드는 건 `.rev` 하나뿐이다.

---

## 상태 판정

`install.sh` 체크리스트의 세 상태를 이렇게 정한다.

| 상태 | 조건 |
|---|---|
| `not installed` | 바이너리나 `sudo-pop.sh` 가 없음 |
| `installed / outdated` | `.rev` 가 없거나(= 손으로 깐 바이너리), `.rev` 가 upstream `main` 과 다름 |
| `installed / latest` | `.rev` 가 upstream 과 같음 |

- **`.rev` 가 없으면 `outdated`** 다. upstream 의 curl 설치기로 깔았거나 손으로 빌드한
  바이너리는 어느 커밋에서 나왔는지 알 길이 없고, 알 수 있는 상태로 만드는 방법은 한 번
  다시 빌드하는 것뿐이다. 재빌드가 싫으면 체크리스트에서 그 줄만 해제하면 된다
- **네트워크가 없으면 `latest`** 로 본다. 모르는 것을 추측해서 몇 분짜리 빌드를 권하지 않는다
- 체크아웃이 upstream 보다 뒤처져 있어도 `install` 이 어차피 `git pull` 부터 한다

`install` 은 **체크아웃 HEAD 와 `.rev` 가 같고 바이너리가 있으면 빌드를 건너뛴다.**
그때 설정 파일 중 빠진 게 있으면 `--init` 만 다시 돌린다 (예: bash 단계를 `remove` 했다가
다시 깐 경우). `--force` 로 강제 빌드할 수 있다.

---

## 다른 스텝과 겹치는 것

`~/.config/minsoft1115/bash/` 와 `~/.bashrc` 의 로더 블록을 [bash 설정](bash-config.md)과
**같이 쓴다.** 양쪽 다 이미 그걸 알고 있다.

| | |
|---|---|
| 로더 마커 | 양쪽이 **완전히 같은 블록**(`# minsoft1115-bash:begin`)을 쓰고, 있으면 건드리지 않는다 |
| `install-bash-config.sh` | 자기가 깐 파일을 `.installed` 에 적고 **그 목록만** 지운다 → `sudo-pop.sh` 는 `left alone` |
| `sudo-pop --uninit` | 자기 파일 두 개와 자기 마커만 지우고 **로더 블록은 남긴다** |
| `zz-pkg-guards.sh` | 로드 시점의 `alias sudo=...` 를 넘겨받아 호출한다 — 그 alias 가 곧 sudo-pop 이다. 파일명 `zz-` 접두사가 sudo-pop.sh **뒤에** 로드되게 만든다 |

`install.sh` 에서 실행 순서가 `bash-config` → `sudo-pop` 인 것도 이것 때문이다. 제거는 역순이라
**`sudo-pop --uninit` 이 bash 로더가 사라지기 전에** 돈다.

---

## 제거

`remove` 는 **upstream 의 `install.sh --uninstall` 을 부른다.** 설치를 그쪽에 맡겼으니 제거도
같은 곳이 맞고, 그쪽이 이쪽보다 더 안다.

```bash
./scripts/install-sudo-pop.sh remove
```

| upstream 의 `--uninstall` | |
|---|---|
| 순서 | `--uninit` 먼저, 바이너리 삭제는 그다음 |
| 바이너리가 이미 없으면 | 같은 파일들을 직접 지운다 (`$PREFIX` 에 없으면 PATH 에서도 찾는다) |
| `-- sudo-pop:begin` 만 있고 `end` 가 없으면 | **건드리지 않고 경고만** 한다 — 설정을 먹느니 마커 한 줄이 남는 게 낫다 |
| `$XDG_RUNTIME_DIR/sudo-pop` | 지운다. 남으면 없는 바이너리를 가리키는 링크가 된다 |
| `~/.bashrc` 의 로더 블록 | 남긴다 (공유물) |

이 스크립트가 그 뒤에 하는 건 `.rev` 삭제와 clone 처리(`--purge`)뿐이다.

**체크아웃이 없을 때만** 직접 지운다 — clone 을 `--purge` 로 날린 뒤 같은 명령을 또 부른
경우다. 그때도 순서(`--uninit` → 삭제), 짝 없는 마커, 런타임 링크까지 같은 규칙을 따른다.

---

## 알아둘 것

**`--uninit` 전에 바이너리를 지우면 안 된다.** alias 만 남고 가리키는 파일이 없어져
`sudo` 가 "command not found" 가 된다. 이미 그렇게 됐다면 `--uninstall` 이 수습한다 —
물어볼 바이너리가 없으면 자기가 파일을 지운다.

탈출구는 이렇다.

```bash
command sudo whoami      # alias 도 함수도 안 거친다
/usr/bin/sudo whoami     # 셸 정의를 아예 안 거친다
```

`\sudo` 는 **믿을 수 없다** — 백슬래시는 alias 만 막고 함수는 못 막는데,
`zz-pkg-guards.sh` 가 `sudo` 를 함수로 만든다 ([bash-config.md](bash-config.md#sudo-pacman-을-잡는-법--그리고-그-대가)).

**이미 열려 있는 셸은 그대로다.** 새 터미널부터 적용되고, 지금 셸에 넣으려면 `source ~/.bashrc`.

**빌드 트리는 크다.** clone 은 `remove` 후에도 남는다 (`--purge` 로 지운다). 남겨 두면
다음 업데이트가 증분 빌드라 훨씬 빠르다.

**보안 도구가 아니라 편의 도구다.** 내 사용자로 도는 악성 코드는 alias 도 바이너리도
바꿀 수 있다. 막아 주는 것은 코어덤프·스왑·화면 공유·로그로 비밀번호가 **흘러나가는** 쪽이다.
자세한 건 [sudo-pop README](https://github.com/minsoft1115/sudo-pop) 참고.
