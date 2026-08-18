# omarchy-setup

[Omarchy](https://omarchy.org) (Arch + Hyprland) 머신을 새로 깔았을 때 돌리는 셋업 스크립트 모음.

각 스크립트는 **독립 실행**되고 **idempotent** 하다 — 여러 번 돌려도 안전하며,
이미 적용된 항목은 `건너뜀` 으로 표시된다. 기존 설정 파일은 고치기 전에
`*.bak.<타임스탬프>` 로 백업한다.

---

## setup-korean.sh

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

## install-workspaces-widget.sh

바의 워크스페이스 인디케이터를 포커스된 워크스페이스도 **숫자로** 보여 주는 버전으로 바꾸고,
**Super 를 누르고 있으면** 각 워크스페이스에 뭐가 떠 있는지 보여 주는 팝업을 추가한다.

![워크스페이스 위젯과 Super 홀드 미리보기](screenshots/workspaces-widget.png)

바에서 1번은 포커스(반전된 숫자), 2번은 창 있음, 3~5번은 비어 있어 흐리게 나온다.
Super 를 누르고 있으면 아래 팝업이 떠서 각 워크스페이스의 창 목록을 보여 준다.

저장소를 clone 한 뒤 실행한다 (Quickshell 플러그인과 Hyprland 키 바인딩을 함께 설치한다):

```bash
git clone https://github.com/minsoft1115/omarchy-setup.git
cd omarchy-setup
./install-workspaces-widget.sh install
```

되돌리려면:

```bash
./install-workspaces-widget.sh revert
```

자세한 내용은 [docs/workspaces-widget.md](docs/workspaces-widget.md) 참고.

---

## 참고 문서

스크립트는 아니고, Omarchy 가 어떻게 굴러가는지 조사해 둔 기록.

| 문서 | 내용 |
|---|---|
| [docs/quickshell-workspaces.md](docs/quickshell-workspaces.md) | Omarchy 4.0 바의 워크스페이스 인디케이터가 그려지는 방식 — 데이터 출처, 표시 규칙, 클릭 동작, 커스터마이즈 지점 |
| [docs/workspace-peek-design.md](docs/workspace-peek-design.md) | Super 홀드 미리보기의 설계와 실측 기록 — 키 바인딩 동작, release 유실, 팝업 크기 계산에서 틀렸던 것들 |
