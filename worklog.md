# worklog

Purpose: Claude Code와 Codex가 동시에 작업할 때, 누가 언제 무엇을 어떻게 어디에 수정했는지 한 파일에서 바로 확인하기 위한 기록 파일.

## 기록 규칙

앞으로는 아래 형식으로 계속 누적:

```md
## YYYY-MM-DD HH:MM JST | 작성자

- 범위:
- 무엇을 했는지:
- 어떻게 수정했는지:
- 수정 파일:
- 검증:
- 메모:
```

주의:
- 이력은 요약이 아니라 실제 수정 의도를 남긴다.
- 가능한 한 `무엇`, `방법`, `파일`, `검증`을 같이 적는다.
- 다른 에이전트가 이어받을 수 있도록 상태 전이/런타임 가정도 메모에 남긴다.

## 2026-03-12 18:13 JST | Codex (GPT-5)

- 범위:
  - 입력기 코어 전반
  - 한글/일본어 엔진 상태 전이
  - 후보창 위치 계산
  - `NRIMEInputController` 경계 로직
  - 테스트 보강
- 무엇을 했는지:
  - 한글 한자 후보창에서 `Space` 후 원래 한글 조합이 뒤늦게 튀어나오는 상태 누수 문제를 수정했다.
  - 일본어 prediction에서 `↑/↓` 후 `Tab` 확정 대상이 화면 선택과 어긋나는 문제를 수정했다.
  - 일본어 변환 중 Mozc submit 실패 시 preedit가 사라지는 경로를 막았다.
  - live conversion commit에서 미완성 romaji tail이 사라지는 문제를 막았다.
  - `F6-F10` 변환 후 `Escape` 복원이 깨지는 경로를 수정했다.
  - synthetic Mozc fallback candidate를 제거해서 invalid candidate ID가 다시 Mozc로 전달되지 않게 했다.
  - Mozc 시작/연결 실패 시 입력기 이벤트 스레드 블로킹을 줄이는 방향으로 서버 매니저와 클라이언트를 정리했다.
  - 후보창과 인라인 인디케이터가 caret가 아니라 사실상 index `0` 근처에 뜨던 문제를 caret 기반 geometry로 바꿨다.
  - 컨트롤러 레벨 테스트 seam을 만들고, IMK 경계 동작 테스트를 추가했다.
  - shortcut down/up 시퀀스 테스트를 추가해서 modifier tap과 combo 동작을 검증했다.
- 어떻게 수정했는지:
  - 한글 한자 관련:
    - 후보창 종료 전에 원문 한글 조합을 복원하도록 정리했다.
    - `Space`는 후보창만 닫지 않고 원래 한글 처리 경로로 다시 보내도록 바꿨다.
  - 일본어 관련:
    - commit 실패 시 현재 preedit 또는 원래 히라가나를 fallback으로 commit하도록 했다.
    - live conversion commit에서 표시 문자열과 실제 commit 문자열이 어긋나지 않게 pending tail을 포함하도록 했다.
    - function-key 변환 경로에서도 원래 히라가나를 저장하도록 했다.
    - 실제 Mozc 후보만 다루도록 fallback candidate 생성을 제거했다.
  - 위치 계산 관련:
    - 공통 geometry 유틸을 추가하고 `selectedRange`, `markedRange`, `firstRect(forCharacterRange:)`를 우선 사용하게 했다.
    - 실패 시에만 `attributes(forCharacterIndex:)` fallback으로 내려가게 했다.
  - 컨트롤러/테스트 관련:
    - `NRIMEInputController`에 debug-only 테스트 seam과 helper를 추가했다.
    - `commitComposition`, `deactivateServer`, mouse-click commit, shortcut routing을 테스트 가능한 구조로 분리했다.
    - 테스트가 로컬 사용자 설정값에 의존하지 않도록 shortcut 설정을 테스트 안에서 고정하고 복구하게 했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcConverter.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcServerManager.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/App/AppDelegate.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/InlineIndicator.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MozcConverterTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/ShortcutHandlerTests.swift`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - `107 tests, 0 failures`
- 메모:
  - 이 엔트리는 이번 세션에서 Codex가 수행한 입력기 코어 작업을 한 번에 요약한 것이다.
  - 세부 수정별 정확한 분 단위 시각은 따로 분리 기록하지 않았고, 현재 시점 기준으로 정리했다.
  - unit test가 늘었지만 `InputMethodKit` 실제 런타임과 앱별 포커스 전이는 여전히 실앱 검증이 필요하다.
  - `Finder`까지 입력이 안 되는 문제는 코드 버그일 수도 있지만, 재설치 후 로그아웃/로그인을 하지 않아 입력 소스 등록/세션이 꼬였을 가능성도 높다.

### 파일별 상세

#### `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`

- 추가:
  - `testingClientOverride`
  - `resolvedClient()`
  - `handleCommitComposition(_:)`
  - `handleDeactivateServer(_:)`
  - `commitCompositionForTesting(sender:)`
  - `deactivateServerForTesting(sender:)`
  - `commitOnMouseClickForTesting()`
  - `previewHanjaSourceIfNeeded(client:)`
- 정리:
  - 기존에는 `self.client()`에 직접 의존하던 경로가 많았는데, 테스트와 focus-loss 상황에서 불안정했다.
  - commit/deactivate 로직을 override 내부에 뭉쳐 두지 않고 helper로 분리해서 테스트 가능하게 만들었다.
  - 한자 후보창 닫힘 경로에서 원문 미복원 상태가 남지 않도록 `Escape`, `Space`, grid/list 전환에 복원 경로를 넣었다.
- 삭제가 생긴 이유:
  - 기능 삭제가 아니라, override 안에 섞여 있던 로직을 helper로 재배치하면서 중복/직접 접근 코드가 줄었다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`

- 추가:
  - `HanjaSource` enum
  - `hanjaSource` 상태
  - `restoreHanjaSource(client:)`
  - `clearHanjaSession()`
- 정리:
  - 한자 후보창을 열 때 원문이 조합 중 텍스트인지, 선택된 텍스트인지 따로 저장하게 했다.
  - 후보 프리뷰만 바뀐 상태에서 `Escape`나 `Space`가 들어오면 원문을 복원할 수 있게 했다.
  - 한자 후보가 비어 있을 때도 세션 상태가 남지 않게 정리했다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`

- 추가:
  - `currentPredictionSelectionIndex()`
  - `conversionFallbackText(preedit:originalHiragana:)`
  - `liveConversionCommitText(convertedText:composedKana:flushedText:)`
- 정리:
  - prediction 후보 확정 시 panel selection과 engine focused index가 다를 수 있던 부분을 panel 우선으로 맞췄다.
  - conversion submit 실패 시 텍스트를 잃지 않도록 fallback 경로를 넣었다.
  - live conversion commit이 표시 문자열과 실제 commit 문자열이 다르지 않도록 pending tail을 합치게 했다.
  - `F6-F10` 경로는 변환 시작 전에 원본 히라가나를 저장하고, 실패 시 converter 상태를 리셋하게 했다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcConverter.swift`

- 추가:
  - `prepareForConversion(hiragana:)`
- 정리:
  - per-conversion 상태 초기화와 원본 히라가나 저장을 한 메서드로 묶었다.
  - 후보가 없는 경우 `currentFocusedIndex`가 이전 상태를 끌고 가지 않게 했다.
  - synthetic fallback candidate 생성 코드를 제거했다.
- 삭제가 생긴 이유:
  - fallback candidate 두 개를 합성하던 분기가 통째로 빠졌다.
  - 이 삭제는 기능 축소가 아니라 invalid candidate ID 전파를 막기 위한 정리다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcServerManager.swift`

- 추가:
  - `shared` singleton
  - background `warmupQueue`
  - `prewarmServer()`
  - `waitUntilReachable(timeout:)`
- 정리:
  - 기존에는 입력 이벤트 처리 경로에서 기다리는 시간이 길었다.
  - 이제 앱 시작 시 미리 서버를 띄우고, 입력 중에는 오래 기다리지 않도록 fail-fast 쪽으로 바꿨다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`

- 변경:
  - Mach IPC timeout을 `1000ms -> 250ms`로 줄였다.
- 이유:
  - 서버 stall 시 host app key handling까지 오래 묶이는 시간을 줄이기 위해서다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/App/AppDelegate.swift`

- 추가:
  - 앱 시작 시 `MozcServerManager.shared.prewarmServer()`
- 이유:
  - 첫 일본어 변환 시 startup penalty를 줄이기 위해서다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`

- 새 파일:
  - caret 위치 계산 공통 유틸
- 역할:
  - `selectedRange`
  - `markedRange`
  - `firstRect(forCharacterRange:)`
  - `attributes(forCharacterIndex:) fallback`
  순서로 caret rect를 찾는다.
- 이유:
  - 후보창과 인디케이터가 항상 첫 글자 기준으로 뜨던 문제를 UI 컴포넌트마다 중복 수정하지 않고 공통 레이어에서 처리하기 위해서다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`

- 정리:
  - 위치 계산을 `TextInputGeometry.caretRect(for:)` 기반으로 바꿨다.
  - list/grid 레이아웃 계산을 다시 배치하면서 panel frame, page label, stackView frame 설정을 좀 더 일관되게 정리했다.
- 삭제가 크게 보이는 이유:
  - 기존 레이아웃 계산 블록을 없앤 게 아니라, 같은 계산을 더 앞쪽/공통 위치로 옮기면서 diff상 삭제가 커 보인다.
  - `attributes(forCharacterIndex: 0, ...)` 직접 호출 블록이 제거됐다.
  - 중복되던 list/grid 레이아웃 계산 코드가 재배치되면서 삭제량이 커졌다.

#### `/Users/nr2bj/Documents/NRIME/NRIME/UI/InlineIndicator.swift`

- 정리:
  - 위치 계산을 `TextInputGeometry.caretRect(for:)`로 교체했다.
- 삭제가 생긴 이유:
  - 기존의 직접 caret 조회 로직이 공통 유틸로 대체됐다.

#### `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`

- 추가 테스트:
  - settings app bypass
  - Korean composition -> mode switch commit
  - Korean `Space` commit
  - Japanese `Enter` commit
  - Hanja open -> `Escape`
  - Hanja open -> `Space`
  - `deactivateServer` path
  - mouse click commit path
- 정리:
  - 테스트가 사용자 로컬 shortcut 설정에 흔들리지 않게 기본 shortcut을 저장/복구하게 했다.

#### `/Users/nr2bj/Documents/NRIME/NRIMETests/ShortcutHandlerTests.swift`

- 추가 테스트:
  - modifier-only tap
  - modifier + combo
  - combo 후 key-up에서 tap 미발동
  - reset 후 pending modifier state 제거
- 정리:
  - 실제 `NSEvent`를 만들어서 down/up 시퀀스를 검증한다.
  - 로컬 환경 설정값에 의존하지 않도록 shortcut/tap threshold를 테스트 안에서 고정한다.

#### `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`

- 목적:
  - submit fallback
  - live conversion commit tail
  - function-key conversion 관련 회귀를 막기 위한 테스트 추가

#### `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`

- 목적:
  - 한자 후보창 관련 원문 복원과 `Space` 처리 회귀 방지

#### `/Users/nr2bj/Documents/NRIME/NRIMETests/MozcConverterTests.swift`

- 목적:
  - synthetic candidate 제거 후 converter 상태와 candidate extraction이 기대대로 유지되는지 검증

#### `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`

- 목적:
  - caret 위치 계산이 `selectedRange`와 `markedRange`를 우선적으로 잘 쓰는지 검증

#### `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`

- 역할:
  - controller/engine 테스트에서 IMK client를 대신하는 mock
  - marked text, inserted text, selected range, first rect 호출 등을 검증 가능하게 제공

### 삭제가 컸던 변경 요약

- `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - 이유: caret 조회 로직 교체 + 레이아웃 계산 블록 재배치
- `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcConverter.swift`
  - 이유: synthetic fallback candidate 생성 분기 제거
- `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - 이유: 테스트 가능한 helper 구조로 분리하면서 기존 직접 처리 코드 정리

이 세 파일은 “기능을 빼서 줄어든 것”보다는 “불안정하거나 중복된 기존 구조를 치우면서 줄어든 것”에 가깝다.

## 2026-03-12 18:20 JST | Codex (GPT-5)

- 범위:
  - 입력 소스 복구 로직
  - `InputSourceRecovery`
  - 관련 테스트 추가
- 무엇을 했는지:
  - `preventABCSwitch`가 꺼져 있어도 입력 소스 변경 알림 경로에서 NRIME로 강제 복구하던 문제를 수정했다.
  - `userInitiatedSwitch`가 주석과 달리 실제 suppress 역할을 하지 못하던 문제를 수정했다.
  - secure input 상태에서는 입력 소스 복구를 시도하지 않도록 막았다.
  - 복구 대상 입력 소스를 bundle 전체의 첫 항목이 아니라 명시적인 `.en` 입력 소스로 고정했다.
- 어떻게 수정했는지:
  - `InputSourceRecovery.shouldRecoverInputSource(...)`라는 결정 로직을 분리했다.
  - 복구 조건을 다음 순서로 명확히 정리했다:
    - 사용자 의도적 전환이면 복구하지 않음
    - `preventABCSwitch`가 꺼져 있으면 복구하지 않음
    - secure input이면 복구하지 않음
    - 현재 소스가 NRIME가 아닐 때만 복구
  - `inputSourceChanged(_:)`와 polling 경로 모두 같은 결정 로직을 쓰게 했다.
  - 복구 시 `kTISPropertyInputSourceID = com.nrime.inputmethod.app.en`로 직접 조회하게 바꿨다.
  - 소스가 비활성 상태면 `TISEnableInputSource` 후 선택하도록 보강했다.
  - `InputSourceRecoveryTests.swift`를 추가하고 Xcode 프로젝트를 다시 생성해 테스트 파일이 실제 실행되도록 반영했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME.xcodeproj/project.pbxproj`
- 검증:
  - 실행 명령:
    - `xcodegen generate`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - `112 tests, 0 failures`
  - 추가 확인:
    - `InputSourceRecoveryTests` 5개가 실제로 실행됨
- 메모:
  - 이 문제는 특히 “Prevent switching to ABC”가 꺼져 있을 때도 입력 소스가 다시 NRIME로 붙는 증상과 연결될 수 있다.
  - Finder 같은 기본 앱에서 입력이 이상해 보였던 현상 일부도 이 경로 영향일 가능성이 있다.
  - 다만 재설치 후 로그아웃/로그인을 하지 않은 세션 꼬임 가능성은 여전히 별개로 남아 있다.

## 2026-03-12 18:36 JST | Codex (GPT-5)

- 범위:
  - 개발자 모드
  - 로컬 전용 디버그 로그
  - 설정 앱 로그 접근
- 무엇을 했는지:
  - 사용자 토글 가능한 `Developer Mode`를 추가했다.
  - 입력기 쪽에 로컬 파일 기반 개발자 로그를 추가했다.
  - 설정 앱에서 로그를 직접 열고, Finder에서 보고, 지울 수 있게 했다.
  - 로그가 로컬 전용이며 자동 업로드되지 않는다는 안내를 UI에 명시했다.
  - 로그에는 typed text를 남기지 않고, 앱/모드/입력 소스/라이프사이클 메타데이터만 남기게 했다.
- 어떻게 수정했는지:
  - 입력기 프로세스:
    - `developerModeEnabled` 설정 키를 추가했다.
    - `DeveloperLogger`를 추가해서 App Group 컨테이너 아래 `Library/Logs/NRIME/developer.log`에 기록하게 했다.
    - 로그 파일이 없으면 헤더와 함께 생성하고, 파일 크기가 커지면 회전되게 했다.
  - 로깅 포인트:
    - 앱 시작
    - 모드 전환
    - `activateServer` / `deactivateServer`
    - shortcut action
    - mouse click commit
    - input source recovery 시작/정지/판단/복구 성공/실패
  - 설정 앱:
    - `General` 탭에 `Developer` 섹션을 추가했다.
    - `Enable Developer Mode`
    - `Open Log`
    - `Reveal in Finder`
    - `Clear Log`
    - 로그 경로 표시
  - 프로젝트:
    - 새 파일 반영을 위해 `xcodegen generate`를 다시 실행했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/DeveloperLogger.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/Settings.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/StateManager.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/App/AppDelegate.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/SettingsStore.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/GeneralTab.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/DeveloperLogTools.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME.xcodeproj/project.pbxproj`
- 검증:
  - 실행 명령:
    - `xcodegen generate`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - `112 tests, 0 failures`
- 메모:
  - 이 기능은 “개발자가 몰래 로그를 가져간다”는 오해를 줄이기 위한 구조를 의도했다.
  - 로그는 로컬 파일만 사용하고, 사용자가 직접 열어볼 수 있게 했다.
  - typed text는 자동 기록 대상에서 제외했다.

## 2026-03-13 00:03 JST | Codex (GPT-5)

- 범위:
  - 로그인/부팅 직후 입력 소스 복구
  - `preventABCSwitch` 기능 확장
- 무엇을 했는지:
  - `Prevent switching to ABC`가 켜져 있으면, 단순히 런타임 중 다른 입력 소스로 바뀌었을 때만이 아니라 로그인/부팅 직후에도 NRIME를 다시 선택하도록 확장했다.
  - 설정 설명 문구도 로그인/깨우기 복원까지 포함하도록 업데이트했다.
- 어떻게 수정했는지:
  - `InputSourceRecovery.startMonitoring()`에서 시작 직후 복구 체크를 예약하도록 바꿨다.
  - 짧은 지연 3회(`0.5s`, `2.0s`, `5.0s`)로 재시도하게 해서, 로그인 직후 시스템이 입력 소스를 늦게 확정하는 경우를 흡수하게 했다.
  - 각 시도는 기존 복구 조건을 그대로 재사용한다.
    - `preventABCSwitch`가 켜져 있어야 함
    - secure input이 아니어야 함
    - 현재 소스가 NRIME가 아니어야 함
  - 개발자 로그에는 startup recovery가 `triggered`됐는지 `skipped`됐는지도 남기게 했다.
  - 설정 앱 설명은 “다른 입력 소스 선택 시 복귀”에서 “login / wake 후에도 복원 시도”까지 포함하도록 수정했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/GeneralTab.swift`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - `112 tests, 0 failures`
- 메모:
  - 이 변경은 “로그인 후 ABC로 바뀌어 있어서 사용자가 수동으로 NRIME를 다시 고르는 번거로움”을 줄이기 위한 것이다.
  - 단, NRIME 프로세스 자체가 로그인 후 아예 시작되지 않는 환경이라면 이 복구 코드도 실행되지 않으므로, 그 경우는 별도의 launch/login 전략이 필요하다.

## 2026-03-13 00:13 JST | Codex (GPT-5)

- 범위:
  - `1.0.2` 릴리스 준비
  - Settings 앱 버전 표기 정합성
  - PKG 빌드 스크립트 안정화
  - GitHub 푸시 전 검증
- 무엇을 했는지:
  - Settings 앱 번들 버전과 문서 버전을 `1.0.2` 기준으로 맞췄다.
  - PKG 빌드 스크립트가 `xcodebuild` 실패를 숨기고 stale 산출물을 패키징할 수 있던 문제를 수정했다.
  - `NRIMESettings` 릴리스 빌드 실패 원인을 잡아 새 `NRIME-1.0.2.pkg`를 다시 만들었다.
  - 전체 테스트를 다시 실행해서 릴리스 직전 상태를 확인했다.
- 어떻게 수정했는지:
  - `NRIMESettings/Info.plist`의 `CFBundleShortVersionString`, `CFBundleVersion`을 `1.0.2` / `3`으로 맞췄다.
  - `NRIME.md`의 Settings 앱 버전 설명을 `v1.0.2`로 갱신했다.
  - `Tools/build_pkg.sh`에서 `set -euo pipefail`을 적용하고, `xcodebuild ... | grep ... || true` 형태로 빌드 실패를 삼키던 파이프라인을 제거했다.
  - PKG 재빌드 중 `NRIMESettings/DeveloperLogTools.swift`에서 `NSBeep()` 사용 때문에 릴리스 빌드가 막히는 것을 확인했고, `NSSound.beep()`로 바꿔 빌드 호환성을 맞췄다.
  - 수정 후 `bash Tools/build_pkg.sh`를 다시 실행해 `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.2.pkg`를 새로 생성했고, 샌드박스에서 막히는 재빌드는 권한 있는 환경으로 다시 돌려 최종 산출물을 갱신했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/NRIME.md`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/DeveloperLogTools.swift`
  - `/Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - `build/NRIME-1.0.2.pkg` 생성 완료 (`2026-03-13 00:15:35 JST`, `23M`)
    - `112 tests, 0 failures`
- 메모:
  - 이전 `build_pkg.sh`는 `xcodebuild`가 sandbox/cache 권한 문제로 실패해도 마지막에 PKG를 만들어 버릴 수 있었기 때문에, 릴리스 산출물 신뢰성이 낮았다. 이번 수정으로 그 경로를 차단했다.
  - `DeveloperLogTools.swift`는 디버그 로그 UI 추가 이후 처음으로 `Release` 스킴에서 검증됐고, 이번에 릴리스 빌드 호환성까지 맞췄다.
  - 다음 에이전트가 릴리스를 이어받을 때는 `build/pkg-build.log`와 `build/nrimesettings-release.log`를 보면 실패 원인 추적 이력을 바로 확인할 수 있다.

## 2026-03-13 00:19 JST | Codex (GPT-5)

- 범위:
  - Git 커밋/태그 푸시
  - GitHub 릴리스 자산 동기화
- 무엇을 했는지:
  - 현재 작업 트리를 `Release 1.0.2` 커밋으로 묶어 `main`에 푸시했다.
  - 기존 원격 `v1.0.2` 태그가 한 커밋 뒤를 가리키고 있던 것을 확인하고, 최신 릴리스 커밋으로 강제 갱신했다.
  - 로컬에서 다시 빌드한 `NRIME-1.0.2.pkg`를 GitHub `v1.0.2` 릴리스 자산에 덮어써서 현재 산출물과 맞췄다.
- 어떻게 수정했는지:
  - `git add -A && git commit -m "Release 1.0.2"`로 릴리스 커밋 `c91c877`을 생성했다.
  - `git push origin main v1.0.2` 중 태그 충돌이 발생해, 원격 `v1.0.2`가 기존 커밋 `7cb7239`를 가리키는 것을 별도 fetch로 확인했다.
  - 의도적으로 `git push --force origin v1.0.2`를 사용해 태그를 최신 릴리스 커밋 기준으로 맞췄다.
  - `gh release upload v1.0.2 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.2.pkg --clobber -R NR2BJ/NRIME`로 릴리스 자산을 갱신했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/.git` (commit/tag state)
  - GitHub remote `origin/main`
  - GitHub release tag `v1.0.2`
  - GitHub release asset `NRIME-1.0.2.pkg`
- 검증:
  - 실행 명령:
    - `git push origin main v1.0.2`
    - `git push --force origin v1.0.2`
    - `gh release view v1.0.2 -R NR2BJ/NRIME --json tagName,name,assets`
    - `shasum -a 256 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.2.pkg`
  - 결과:
    - `origin/main` -> `c91c877`
    - `v1.0.2` -> 최신 릴리스 커밋으로 갱신 완료
    - GitHub release asset `NRIME-1.0.2.pkg`의 SHA-256이 로컬 파일과 일치함 (`1c09ca7cd7a02e8d16b18401d1010f9643618012e931c99eb08197e30c122918`)
- 메모:
  - 원격 `v1.0.2`는 기존 공개 릴리스에서 이미 사용 중이었기 때문에, 이번 작업은 태그 rewrite를 포함한다. 릴리스 히스토리를 엄격히 보존해야 하는 정책이 생기면 다음부터는 새 패치 버전 태그를 쓰는 편이 더 안전하다.
  - 현재 GitHub release asset은 로컬에서 검증한 PKG와 digest 기준으로 동일하다.

## 2026-03-13 04:17 JST | Codex (GPT-5)

- 범위:
  - 로그인 직후 입력 소스 자동 복원
  - PKG / 개발 설치 스크립트 동기화
- 무엇을 했는지:
  - 로그아웃/로그인 후에도 `Prevent switching to ABC`가 실제로 동작하도록, 입력기 프로세스가 아직 선택되지 않았어도 실행되는 전용 로그인 복원 helper를 추가했다.
  - PKG와 `Tools/install.sh`가 helper 앱과 LaunchAgent를 함께 설치하도록 바꿨다.
  - `Tools/uninstall.sh`와 postinstall도 helper/agent 정리에 맞춰 확장했다.
- 어떻게 수정했는지:
  - 새 타깃 `NRIMERestoreHelper`를 추가하고, 로그인 시 `LaunchAgent`가 `/Library/Input Methods/NRIMERestoreHelper.app`를 백그라운드로 한 번 실행하게 만들었다.
  - helper는 App Group defaults에서 `preventABCSwitch`를 읽고, `0.5s / 2.0s / 5.0s` 지연으로 NRIME visible input source(`com.nrime.inputmethod.app.en`)를 재선택한 뒤 종료한다.
  - 입력 소스 선택 로직은 `Shared/InputSourceSelector.swift`로 분리해 `InputSourceRecovery`와 helper가 같은 TIS enable/select 경로를 쓰게 했다.
  - PKG 빌더는 이제 `NRIMERestoreHelper`를 함께 빌드하고, payload에 helper 앱과 `com.nrime.inputmethod.loginrestore.plist`를 포함한다.
  - 개발용 `Tools/install.sh`도 user-level LaunchAgent를 생성/bootstrp하도록 바꿔서 로컬 설치에서도 같은 경로를 검증할 수 있게 했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/Shared/InputSourceSelector.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/NRIMERestoreHelperApp.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/LoginRestoreController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/GeneralTab.swift`
  - `/Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
  - `/Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - `/Users/nr2bj/Documents/NRIME/Tools/pkg/postinstall`
  - `/Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.loginrestore.plist`
  - `/Users/nr2bj/Documents/NRIME/Tools/uninstall.sh`
- 검증:
  - 실행 명령:
    - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIMERestoreHelper -destination 'platform=macOS' build`
    - `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
    - `pkgutil --expand-full /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.2.pkg /tmp/nrime-pkg-expand`
    - `bash -n /Users/nr2bj/Documents/NRIME/Tools/install.sh && bash -n /Users/nr2bj/Documents/NRIME/Tools/uninstall.sh && bash -n /Users/nr2bj/Documents/NRIME/Tools/pkg/postinstall`
    - `plutil -lint /Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.loginrestore.plist`
  - 결과:
    - `112 tests, 0 failures`
    - `NRIMERestoreHelper` 단독 빌드 성공
    - PKG 안에 `Library/Input Methods/NRIMERestoreHelper.app` 포함 확인
    - PKG 안에 `Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist` 포함 확인
    - 설치/제거 스크립트 문법 및 LaunchAgent plist 형식 정상
- 메모:
  - 기존 `InputSourceRecovery`는 NRIME가 이미 실행 중일 때만 동작했다. 그래서 로그인 후 기본 입력 소스가 ABC면 복구 코드가 실행될 기회 자체가 없었다.
  - 이번 변경은 `Prevent switching to ABC`를 “런타임 중 복귀”에서 “로그인 직후 helper 기반 복귀”까지 확장한 것이다.
  - 실제 체감 검증은 설치 후 로그아웃/로그인 1회가 필요하다. 개발 모드를 켜면 helper 시도도 로컬 로그에 남는다.

## 2026-03-13 04:28 JST | Codex (GPT-5)

- 범위:
  - 실제 로컬 설치 반영
  - GitHub 배포 반영
- 무엇을 했는지:
  - 업데이트된 `Tools/install.sh`로 현재 로그인 계정에 NRIME, NRIMERestoreHelper, 로그인 복원 LaunchAgent를 실제 설치했다.
  - 변경을 `Add login restore helper` 커밋으로 푸시하고, `v1.0.2` 태그를 최신 커밋으로 다시 맞췄다.
  - GitHub `v1.0.2` 릴리스의 `NRIME-1.0.2.pkg`를 현재 빌드 산출물로 다시 업로드했다.
- 어떻게 수정했는지:
  - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`를 실행해 user-level `~/Library/Input Methods`와 `~/Library/LaunchAgents`에 새 helper/agent를 설치했다.
  - `git tag -fa v1.0.2 -m "v1.0.2" && git push origin main && git push --force origin v1.0.2`로 브랜치와 태그를 동기화했다.
  - `gh release upload v1.0.2 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.2.pkg --clobber -R NR2BJ/NRIME`로 릴리스 자산을 교체했다.
- 수정 파일:
  - `/Users/nr2bj/Library/Input Methods/NRIME.app`
  - `/Users/nr2bj/Library/Input Methods/NRIMERestoreHelper.app`
  - `/Users/nr2bj/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist`
  - GitHub remote `origin/main`
  - GitHub tag `v1.0.2`
  - GitHub release asset `NRIME-1.0.2.pkg`
- 검증:
  - 실행 명령:
    - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
    - `gh release view v1.0.2 -R NR2BJ/NRIME --json tagName,name,assets`
    - `shasum -a 256 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.2.pkg`
    - `git rev-parse HEAD origin/main v1.0.2^{}`
  - 결과:
    - 로컬 설치 경로에 `NRIME.app`, `NRIMERestoreHelper.app`, `com.nrime.inputmethod.loginrestore.plist` 생성 확인
    - `HEAD`, `origin/main`, `v1.0.2^{}` 모두 `4717d29`를 가리킴
    - GitHub release asset digest와 로컬 PKG SHA-256 일치 (`75e5b19d77fa19a48997f3a7b8630c22ee773965366129ebddd3a31f91a8801c`)
- 메모:
  - 이번 업로드로 공개 `v1.0.2` 릴리스는 로그인 직후 입력 소스 복원 helper가 포함된 PKG로 바뀌었다.
  - 실제 체감 확인은 이 상태에서 로그아웃/로그인 1회만 보면 된다. 개발자 모드를 켜면 helper 시도도 동일한 로컬 로그 파일에 남는다.
