# omarchy-setup

[Omarchy](https://omarchy.org) (Arch + Hyprland) 머신을 위한 셋업 스크립트 모음.

## setup-korean.sh

한글 입력(fcitx5 + hangul) 세팅 스크립트. 모든 단계가 idempotent 하므로 여러 번 실행해도 안전하다.

```bash
./setup-korean.sh            # 전체 세팅 (갓 설치한 머신용, 패키지 설치 포함)
./setup-korean.sh --light    # 가벼운 재적용 (패키지/sudo 없이 키 설정만)
./setup-korean.sh --help     # 도움말
```

### 전체(`--full`, 기본) 단계

1. fcitx5 + 한글 패키지 설치 (sudo 필요할 수 있음)
2. IM 환경변수
3. XDG 자동시작 중복 방지
4. fcitx5 프로필 (keyboard-us + hangul)
5. fcitx5 단축키 (Control+space 제거, Hangul 유지)
6. 오른쪽 Alt = 한/영
7. 영문-우선 실행 래퍼
8. Super+Space / Super+Alt+Space 재바인딩 (메뉴를 영문으로 열기)
9. 적용 (Hyprland reload / fcitx5 재시작)

### 가벼운(`--light`) 단계

5, 6, 9 만 수행. 이미 한글 입력이 구성된 시스템에서 아래만 재적용할 때 사용한다.

- 오른쪽 Alt = 한/영 키
- fcitx5 Control+space 트리거 제거 (tmux 충돌 해소)

패키지 설치도 sudo 도 건드리지 않는다.

### 참고

- Hyprland 설정은 신형(`.lua`) / 구형(`.conf`) 을 모두 지원 — 있는 쪽을 자동 판별한다.
- fcitx5 자동시작 자체는 omarchy 기본 autostart 가 담당하므로 이 스크립트에서 만들지 않는다.
