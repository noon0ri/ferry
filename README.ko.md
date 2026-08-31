# Ferry

[English](README.md) · **한국어**

흩어져 있는 Claude Code 세션을 메뉴바 한 곳에 모아 보여주고, 클릭 한 번으로 다시 여는 macOS 앱.

## 왜 만들었나

Claude Code 세션은 프로젝트 폴더별로 흩어져 있다. `claude --resume`은 현재 디렉토리 기준으로만
목록을 보여주고, 그 목록은 UUID와 타임스탬프뿐이라 어떤 대화였는지 알아보기 어렵다.

그래서 터미널 창을 닫지 못하게 된다. 주 1회씩만 돌아가는 세션이어도, 닫으면 다시 찾기가
번거로워 열어둔 채로 쌓인다. Ferry는 그 창들을 닫을 수 있게 하는 것이 목표다.

## 하는 일

- `~/.claude/projects/`의 모든 세션을 작업 폴더별로 묶어서 보여준다
- 세션 제목은 로그에 이미 기록된 것을 읽는다. UUID가 아니라 "3D 아이콘 세트 만들기"처럼 보인다
- 클릭하면 Terminal에서 해당 폴더로 이동해 `claude --resume`을 실행한다
- **이미 그 세션의 터미널이 열려 있으면 새 창을 열지 않고 그 창을 앞으로 가져온다**
- 점이 그 차이를 미리 알려준다. 초록이면 열려 있는 창으로, 회색이면 새 창
- 그룹 행에 마우스를 올리면 나타나는 `+`로 그 폴더에서 **새 세션을 시작**한다
- 우클릭으로 이름 변경, 삭제, **다른 그룹으로 이동** (그룹 우클릭은 새 세션)
- 목록은 3초마다 갱신된다

이름을 바꾸면 Claude Code가 쓰는 것과 같은 형식으로 저장되므로, `claude --resume` 목록과
터미널 타이틀에도 그 이름이 나타난다. 이름이 두 군데로 갈라지지 않는다.

삭제는 세션 로그와 서브에이전트 로그를 함께 휴지통으로 옮긴다. 서브에이전트 로그가 로그
본체보다 10~30배 큰 경우가 흔해서, 확인 창에 둘을 합친 용량을 보여준다.

세션을 다른 그룹으로 옮기면 다음 재개 때 그 폴더에서 열린다. 아직 세션이 없는 폴더도
"다른 폴더…"로 고를 수 있다. 자동 메모리는 프로젝트 디렉토리 단위라 따라가지 않으며,
옮기기 전에 몇 개가 남는지 알려준다.

열려 있는 창을 찾는 방법은 tty다. 같은 프로젝트에 세션이 여러 개인 것이 보통이라 경로로는
창을 구분할 수 없다. 다만 tty 번호는 재사용되므로, 그 tty의 세션 리더 프로세스(pid와 시작
시각)를 지문으로 함께 기록한다. 확인은 sysctl 한 번이라 AppleScript도 권한도 필요 없다.

## 요구 사항

macOS 14 이상. Intel과 Apple Silicon 모두 지원한다(유니버설 빌드).

## 설치

### 다운로드 (Xcode 불필요)

[Releases](https://github.com/noon0ri/ferry/releases)에서 `Ferry.zip`을 받는다.
Intel과 Apple Silicon 모두에서 돌아가고, 시스템 프레임워크만 쓰므로 별도 의존성이 없다.

```bash
cd ~/Downloads && unzip Ferry.zip
mv Ferry.app /Applications/

# 인터넷에서 받은 앱은 Gatekeeper가 막는다. 아래 한 줄로 푼다.
xattr -d com.apple.quarantine /Applications/Ferry.app

open /Applications/Ferry.app
```

터미널이 꺼려지면 Finder에서 앱을 우클릭 → 열기 → 다시 한 번 열기로도 된다.

Gatekeeper가 막는 이유는 애드혹 서명이라 개발자를 확인할 수 없어서다. 유료 개발자 계정으로
공증(notarize)하면 이 단계가 사라지지만, 개인 도구라 하지 않았다.

### 소스에서 빌드

```bash
git clone https://github.com/noon0ri/ferry.git
cd ferry
./Scripts/bundle.sh
cp -R build/Ferry.app /Applications/
```

Xcode 26 이상이 필요하다(Swift 6.3). 빌드한 앱은 격리 속성이 붙지 않으므로 위의
`xattr` 단계가 필요 없다. 업데이트는 `git pull && ./Scripts/bundle.sh`.

### 업데이트

`releases/latest/download`는 항상 최신 릴리스를 가리키므로, 지금 어느 버전을 쓰든 아래가 그대로 통한다.

```bash
cd ~/Downloads
curl -L -o Ferry.zip https://github.com/noon0ri/ferry/releases/latest/download/Ferry.zip
pkill -x Ferry 2>/dev/null
unzip -o Ferry.zip
rm -rf /Applications/Ferry.app && mv Ferry.app /Applications/
xattr -dr com.apple.quarantine /Applications/Ferry.app
open /Applications/Ferry.app
```

먼저 종료하는 것이 중요하다. 실행 중에 번들만 바꾸면 다시 띄우기 전까지 옛 코드가 계속 돈다.
세션 이름·이동 예약·터미널 기록은 번들 식별자로 묶인 `UserDefaults`에 있어 업데이트에도 남는다.
세션 로그는 애초에 건드리지 않는다.

자동화 권한을 다시 물어볼 수 있다. 애드혹 서명은 빌드마다 서명 신원이 새로 생기고, 권한은
번들 식별자뿐 아니라 서명에도 묶이기 때문이다. 다시 묻는 것도, 묻지 않는 것도 모두 정상이다.

소스에서 빌드했다면 `git pull && ./Scripts/bundle.sh` 로 끝난다.

### 로그인 시 자동 실행

시스템 설정 → 일반 → 로그인 항목 에서 Ferry를 추가한다.

## 처음 실행할 때

세션을 처음 클릭하면 Terminal 제어 권한을 묻는다. 허용해야 재개가 동작한다. 거부하면 재개
명령이 클립보드에 복사되므로 터미널에 직접 붙여넣으면 된다. 권한은 시스템 설정 → 개인정보
보호 및 보안 → 자동화에서 바꿀 수 있다.

빌드할 때마다 권한을 다시 묻는다면 정상이다. `bundle.sh`는 애드혹 서명(`--sign -`)을 쓰는데,
macOS는 자동화 권한을 서명 신원에 묶어두므로 새로 빌드하면 신원이 바뀌어 권한이 초기화된다.

권한 대화상자가 아예 뜨지 않고 매번 클립보드로만 복사된다면 번들의 Info.plist에서
`NSAppleEventsUsageDescription`이 빠진 것이다. 다음으로 확인한다.

```bash
plutil -extract NSAppleEventsUsageDescription raw build/Ferry.app/Contents/Info.plist
```

## 개발

```bash
swift test      # 78개
swift build
./Scripts/bundle.sh
```

- `Sources/FerryCore` — UI 없는 로직. 로그 파싱, 폴더 순회, 명령 생성, 이름 변경, 삭제
- `Sources/FerryApp` — 메뉴바 UI
- `Scripts/bundle.sh` — 실행 파일을 `.app` 번들로 포장

로그를 어떻게 읽는지, 왜 문자열이 아니라 바이트를 다루는지, 열려 있는 창을 어떻게
식별하는지 — 그리고 거기 이르기까지 무엇이 어긋났는지는 [handoff.md](handoff.md)에 있다.
설계 문서는 [`docs/superpowers/specs/`](docs/superpowers/specs/), 고치지 않기로 한 것들은
[`docs/known-issues.md`](docs/known-issues.md)에 있다.

## 라이선스

[MIT](LICENSE)
