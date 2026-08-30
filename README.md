# Ferry

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
- 60초 이내에 활동이 있었던 세션은 초록 점으로 표시된다
- 우클릭으로 이름 변경과 삭제

이름을 바꾸면 Claude Code가 쓰는 것과 같은 형식으로 저장되므로, `claude --resume` 목록과
터미널 타이틀에도 그 이름이 나타난다. 이름이 두 군데로 갈라지지 않는다.

삭제는 세션 로그와 서브에이전트 로그를 함께 휴지통으로 옮긴다. 서브에이전트 로그가 로그
본체보다 10~30배 큰 경우가 흔해서, 확인 창에 둘을 합친 용량을 보여준다.

## 요구 사항

macOS 14 이상. Intel과 Apple Silicon 모두 지원한다(유니버설 빌드).

## 설치

```bash
git clone https://github.com/noon0ri/ferry.git
cd ferry
./Scripts/bundle.sh
open build/Ferry.app
```

계속 쓰려면 `build/Ferry.app`을 `/Applications`으로 옮긴다.

### 빌드 환경이 없는 Mac에 설치하기

Xcode가 없는 기기라면 빌드된 앱을 그대로 복사해도 된다. 시스템 프레임워크만 쓰므로
별도 의존성이 없다.

```bash
# 빌드가 되는 기기에서
ditto -c -k --keepParent build/Ferry.app Ferry.zip
```

받는 기기에서 압축을 풀면 Gatekeeper가 막는다. 애드혹 서명이라 개발자를 확인할 수 없기
때문이다. 다음 중 하나로 푼다.

```bash
xattr -d com.apple.quarantine /Applications/Ferry.app
```

또는 Finder에서 앱을 우클릭 → 열기 → 다시 한 번 열기. 자동화 권한은 기기마다 따로
받으므로 새 기기에서 처음 세션을 클릭할 때 다시 묻는다.

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

## 동작 방식

`~/.claude/projects/`의 세션 로그를 읽는다. **쓰는 곳은 두 군데뿐이다** — 이름 변경(로그 끝에
한 줄 덧붙임)과 삭제(휴지통으로 이동). 그 외에는 어떤 파일도 건드리지 않는다.

세션 로그는 JSON Lines이고, 필요한 것은 네 가지다. 사용자가 붙인 이름(`custom-title`),
자동 생성 제목(`ai-title`), 작업 폴더(`cwd`), git 브랜치.

두 가지가 성능을 좌우한다.

**로그 파일은 20MB를 넘기도 한다.** 팝오버를 열 때마다 전부 읽을 수는 없으므로 파일 끝
256KB만 읽는다. 제목 레코드는 세션 진행 중 반복 기록되어 파일 뒤쪽에 있기 때문에 대개
꼬리에서 찾을 수 있고, 못 찾은 경우에만 전체를 읽는다.

**꼬리를 Swift `String`으로 만들면 안 된다.** 256KB를 문자열로 변환해 `split`하는 것만으로
전체 스캔 시간의 절반 이상이 소모된다(측정: split 단독 ~94ms/23파일). grapheme cluster 인지
처리 비용이다. `Data` 바이트 위에서 필요한 줄만 찾아 파싱한다.

그룹핑 키는 로그 안의 `cwd` 값이다. 디렉토리 이름(`-Users-me-Codes-my-project`)은 원래 경로로
디코딩할 수 없다. 하이픈이 경로 구분자인지 이름에 포함된 하이픈인지 구분할 방법이 없고,
공백이 든 폴더 이름도 흔하다.

실측(세션 23개 기준): 첫 스캔 92ms, 이후 갱신 1ms. mtime이 바뀐 파일만 다시 읽는다.

## 개발

```bash
swift test      # 49개
swift build
swift run FerryApp
```

- `Sources/FerryCore` — UI 없는 로직. 로그 파싱, 폴더 순회, 명령 생성, 이름 변경, 삭제
- `Sources/FerryApp` — 메뉴바 UI
- `Scripts/bundle.sh` — 실행 파일을 `.app` 번들로 포장

설계 근거는 [`docs/superpowers/specs/`](docs/superpowers/specs/), 고치지 않기로 한 것들과 그
이유는 [`docs/known-issues.md`](docs/known-issues.md)에 있다.

## 라이선스

[MIT](LICENSE)
