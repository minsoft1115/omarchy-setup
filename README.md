# omarchy-setup

[Omarchy](https://omarchy.org) (Arch + Hyprland) 머신을 새로 깔았을 때 돌리는 셋업 스크립트 모음.

각 스크립트는 **독립 실행**되고 **idempotent** 하다 — 여러 번 돌려도 안전하며,
이미 적용된 항목은 `건너뜀` 으로 표시된다. 기존 설정 파일은 고치기 전에
`*.bak.<타임스탬프>` 로 백업한다.

---

## 스크립트

| 스크립트 | 하는 일 | 문서 |
|---|---|---|
| `setup-korean.sh` | 한글 입력(fcitx5 + hangul), 오른쪽 Alt = 한/영 | [문서](docs/setup-korean.md) |

---

### setup-korean.sh

fcitx5 + hangul 을 설치·설정해서 한글 입력을 쓸 수 있게 만든다.
오른쪽 Alt 를 한/영 키로 잡고, tmux 와 충돌하는 `Control+space` 트리거를 없애고,
Super+Space 메뉴가 항상 영문으로 열리게 한다.

```bash
curl -fsSL https://raw.githubusercontent.com/minsoft1115/omarchy-setup/main/setup-korean.sh -o /tmp/setup-korean.sh && bash /tmp/setup-korean.sh
```

이미 세팅된 머신에 키 설정만 다시 입히려면 (패키지·sudo 안 건드림):

```bash
bash /tmp/setup-korean.sh --light
```

자세한 내용은 [docs/setup-korean.md](docs/setup-korean.md) 참고.

---

## 전부 clone 해서 쓰기

```bash
git clone https://github.com/minsoft1115/omarchy-setup.git
cd omarchy-setup
./setup-korean.sh
```

실행 전에 내용을 확인하고 싶다면 (설정 파일을 고치고 sudo 를 쓸 수 있다):

```bash
less setup-korean.sh
```
