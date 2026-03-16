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

## 2026-03-17 01:30 JST | Claude Code (Opus 4.6)

- 범위: Korean/Japanese 엔진 — Electron 앱에서 Shift+Enter, Cmd+A 패스스루 최종 수정
- 무엇을 했는지:
  - Shift+Enter: CGEvent repost 방식의 race condition 해결 → async `insertText("\n")` 방식으로 전환
  - Cmd+A/C/V/X/Z: `NSApp.sendAction` 방식 실패 → tagged CGEvent repost 방식으로 전환
  - 두 엔진 모두 동일 패턴 적용
- 어떻게 수정했는지:
  - **Shift+Enter 근본 원인**: macOS `StandardKeyBinding.dict`에 Shift+Return 바인딩 없음 → Chromium `interpretKeyEvents:`가 `insertText:"\n"` 경로를 탐 → `oldHasMarkedText` true일 때 fake VKEY_PROCESSKEY(0xE5) 생성 → 텍스트 유실
  - **Shift+Enter 해결**: key event를 아예 보내지 않고, 텍스트 확정 후 10ms 딜레이를 두고 `client.insertText("\n")` 호출 + return true. 딜레이는 Chromium IPC 처리 시간 확보 (5ms 이하 race condition, 10ms 안정)
  - **Cmd+key 해결**: `commitComposing` 후 `CGEvent.post(tap: .cghidEventTap)` + repost tag. `performKeyEquivalent:` 경로는 `oldHasMarkedText` 문제 없음
  - `commitComposingExplicitly`, `commitAndSendAction`, `selectorForModifierKey` 삭제 → `commitAndRepostEvent` 통합
- 수정 파일:
  - `NRIME/Engine/Korean/KoreanEngine.swift` — Shift+Enter async insertText, Cmd+key CGEvent repost, 불필요 메서드 삭제
  - `NRIME/Engine/Japanese/JapaneseEngine.swift` — 동일 패턴 적용 (composing/converting 양쪽)
  - `README.md` — Electron/Chromium 대응 기술 문서 추가
- 검증: Electron 앱(Claude for Desktop)에서 한글/일본어 Shift+Enter, Cmd+A 정상 동작 확인
- 메모:
  - 딜레이 최적값 탐색: 1ms(항상 실패) → 5ms(간헐 실패) → 10ms(안정) → 20ms(안정, 눈에 띄는 딜레이) → 50ms(안정, 딜레이 큼). 10ms 채택
  - 다른 IME(Squirrel, fcitx5, Mozc)는 "commit + return false" 패턴 자체를 쓰지 않음. 내부 처리 + return true가 Electron 호환의 정석

## 2026-03-16 18:50 JST | Claude Code (Opus 4.6)

- 범위: Codex 미커밋 최적화 5건 재구현 + 키 이벤트 패스스루 버그 수정 + 일본어 후보창 수정
- 무엇을 했는지:
  1. Codex가 커밋하지 않은 최적화 5건 재구현 (SettingsModels 공유 타입, UserDictionary 백그라운드 저장, LoginRestore nil 소스 처리, DetailedKeyLogging 진단 도구, CandidatePanel은 이미 커밋됨)
  2. Shift+Enter, Cmd+A 등 조합 중 modifier 키 조합이 확정만 하고 앱에 전달되지 않는 버그 수정
  3. 일본어 라이브 변환 상태에서 Space로 후보창이 열리지 않는 버그 수정
- 어떻게 수정했는지:
  - **핵심 원인**: IMKit은 `handle()` 내에서 `client.insertText()` 호출 후 `return false`로는 원본 키 이벤트를 호스트 앱에 전달하지 않음 (특히 Electron 앱)
  - **해결 (tagged CGEvent repost)**: 새 `KeyEventReposter` 유틸리티 추가. CGEvent를 생성 시 `eventSourceUserData`에 센티넬 값(0x4E52494D45 = "NRIME")을 태깅. `handle()` 최상단에서 태그 확인 → 즉시 `return false` → IMKit이 앱에 전달
  - 이전 접근법(cgEvent.copy() repost)은 재전송된 이벤트가 다시 엔진 로직을 타면서 일부 앱에서 실패. 태그 방식은 엔진 로직을 완전히 우회하므로 확실하게 패스스루
  - KoreanEngine: modifier 키(Cmd/Ctrl/Opt) composing 중 → commitComposing + KeyEventReposter.repost + return true. Shift+Enter도 동일 패턴으로 단순화
  - JapaneseEngine: 동일 패턴. composing/converting 모두 처리. 기존 `repostShiftEnter(keyCode:)` 삭제
  - JapaneseEngine `triggerMozcConversion`: 라이브 변환 경로에서 `.converting` 전환 시, `currentCandidateStrings`이 비어있으면 Space를 Mozc에 추가 전송하여 후보 리스트 채움
- 수정 파일:
  - `NRIME/System/KeyEventReposter.swift` — 새 파일, 태그된 CGEvent 재전송 유틸리티
  - `NRIME/Controller/NRIMEInputController.swift` — handle() 최상단에 태그 체크 추가
  - `NRIME/Engine/Korean/KoreanEngine.swift` — modifier repost + Shift+Enter 단순화
  - `NRIME/Engine/Japanese/JapaneseEngine.swift` — modifier repost, repostShiftEnter 삭제, triggerMozcConversion 라이브 변환 경로 수정
  - `Shared/SettingsModels.swift` — 새 파일, 공유 타입 정의
  - `NRIME/State/Settings.swift` — detailedKeyLoggingEnabled 추가, 중복 타입 제거
  - `NRIMESettings/SettingsStore.swift` — detailedKeyLoggingEnabled 추가, 중복 타입 제거
  - `NRIMESettings/UserDictionaryManager.swift` — 백그라운드 저장 + mozc 재시작 디바운스
  - `NRIMESettings/GeneralTab.swift` — Detailed Key Logging 토글 추가
  - `NRIME/System/DeveloperLogger.swift` — logKeyEvent, logSelector 추가
  - `Shared/LoginRestorePolicy.swift` — stabilizationDuration 30초, shouldAttemptRestore nil 처리
  - `NRIMERestoreHelper/LoginRestoreController.swift` — shouldAttemptRestore 사용
- 검증: 147 tests passed, Debug 빌드 성공
- 메모:
  - CGEvent.post(tap: .cghidEventTap)는 Accessibility 권한 필요. 입력기는 보통 자동 허용되지만 권한 없으면 조용히 실패
  - `eventSourceUserData` 태그 방식은 IMKit 엔진 로직을 완전히 우회 → 기존 untagged repost 대비 확실한 패스스루
  - 일본어 후보창: `peekConversion()`은 Mozc를 CONVERSION 상태로 둠. 사용자 Space 시 추가 Space 전송으로 candidate window를 열어야 함

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
    - 릴리스 커밋/태그 `v1.0.2^{}`는 `4717d29`를 가리켰고, 이후 `worklog.md` 갱신 커밋으로 `main`은 한 커밋 앞서게 됨
    - GitHub release asset digest와 로컬 PKG SHA-256 일치 (`75e5b19d77fa19a48997f3a7b8630c22ee773965366129ebddd3a31f91a8801c`)
- 메모:
  - 이번 업로드로 공개 `v1.0.2` 릴리스는 로그인 직후 입력 소스 복원 helper가 포함된 PKG로 바뀌었다.
  - 실제 체감 확인은 이 상태에서 로그아웃/로그인 1회만 보면 된다. 개발자 모드를 켜면 helper 시도도 동일한 로컬 로그 파일에 남는다.
  - `main`은 협업 기록을 남기기 위해 릴리스 태그보다 한 커밋 앞설 수 있다. 배포 산출물은 `v1.0.2` 태그 기준이다.

## 2026-03-13 04:33 JST | Codex (GPT-5)

- 범위:
  - 로그인 직후 ABC 노출 시간 단축
- 무엇을 했는지:
  - 로그인 후 잠깐 `ABC`가 보였다가 NRIME로 바뀌는 체감을 줄이기 위해, login restore helper 실행 경로와 첫 복구 시점을 더 앞당겼다.
- 어떻게 수정했는지:
  - helper가 시작되자마자 `attemptRestore(after: 0)`를 한 번 즉시 실행하도록 바꿨다.
  - LaunchAgent는 더 이상 `/usr/bin/open`을 거치지 않고 helper 앱의 실제 실행 파일을 직접 실행하도록 바꿨다.
  - 변경 후 `Tools/install.sh`를 다시 실행해 현재 사용자 설치본의 LaunchAgent와 helper를 즉시 갱신했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/LoginRestoreController.swift`
  - `/Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.loginrestore.plist`
  - `/Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `bash -n /Users/nr2bj/Documents/NRIME/Tools/install.sh`
    - `plutil -lint /Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.loginrestore.plist`
    - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - 결과:
    - 설치 스크립트 문법 정상
    - LaunchAgent plist 형식 정상
    - 로컬 설치 경로의 login restore LaunchAgent가 helper 실행 파일 직접 호출 방식으로 갱신됨
- 메모:
  - 이전 구현은 LaunchAgent -> `open` -> helper -> `0.5초 후 첫 시도` 순서라 로그인 직후 ABC가 잠깐 보일 여지가 컸다.
  - 이번 변경은 그 지연을 줄이는 쪽이고, 필요하면 다음엔 LaunchAgent 시점 로그를 더 추가해 체감 시간을 수치로 확인할 수 있다.

## 2026-03-13 04:51 JST | Codex (GPT-5)

- 범위:
  - 로그인 직후 NRIME 자동 복구 안정화
  - NRIME 내부 EN/KO/JA 전환 기억 보강
- 무엇을 했는지:
  - 로그인 helper를 "즉시 1회 + 짧은 고정 재시도"에서 "초기 약 15초 동안 지속 감시/복구" 방식으로 바꿨다.
  - helper가 입력 소스 변경뿐 아니라 로그인 중 자동 실행 앱 launch/activate 타이밍에도 NRIME 복구를 다시 시도하게 했다.
  - NRIME 내부의 `직전 비영문 모드` 기억을 UserDefaults에 저장해서, 앱 재실행/로그인 이후에도 `Toggle English`가 마지막 비영문 모드로 복귀하도록 보강했다.
- 어떻게 수정했는지:
  - `Shared/LoginRestorePolicy.swift`를 추가해 로그인 복구 정책을 공통화했다. 현재 정책은 `0초부터 시작`, `0.5초 간격`, `15초 안정화 구간`, `1초 종료 유예`다.
  - `NRIMERestoreHelper/LoginRestoreController.swift`에서 scheduled attempt 목록을 만들고, `DistributedNotificationCenter`의 입력 소스 변경 알림과 `NSWorkspace`의 앱 launch/activate 알림을 구독하도록 바꿨다.
  - helper는 NRIME가 이미 선택된 상태면 대부분 조용히 통과하고, NRIME가 아닌 입력 소스일 때만 선택을 시도한다. developer mode가 켜져 있으면 trigger(`scheduled`, `input_source_changed`, `application_launched`, `application_activated`)와 bundle ID를 로그에 남긴다.
  - `NRIME/State/Settings.swift`에 `lastNonEnglishMode`를 추가했고, `NRIME/State/StateManager.swift`는 이 값을 읽어 초기화하고 비영문 모드 전환 시마다 갱신하도록 바꿨다. 덕분에 로그인 뒤 NRIME가 `.en`으로 잡혀도 내부 shortcut만으로 지난번 `한`/`あ`로 자연스럽게 돌아갈 수 있다.
  - `NRIMESettings/GeneralTab.swift` 설명 문구도 "초기 15초 로그인/깨우기 복구 + 이후 내부 shortcut 전환" 의도에 맞게 고쳤다.
  - 처음 helper 단독 빌드에서 `kTISNotifySelectedKeyboardInputSourceChanged` 심볼을 못 찾는 오류가 있었고, `Carbon` import를 추가해 바로 수정했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/LoginRestorePolicy.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/LoginRestoreController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/Settings.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/StateManager.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/GeneralTab.swift`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/LoginRestorePolicyTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/StateManagerTests.swift`
- 검증:
  - 실행 명령:
    - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIMERestoreHelper -destination 'platform=macOS' build`
  - 결과:
    - `117 tests, 0 failures`
    - `NRIMERestoreHelper` 단독 빌드 성공
    - 새 테스트 5개(`LoginRestorePolicyTests` 3, `StateManagerTests` 2) 추가 후 모두 통과
- 메모:
  - 이번 변경의 핵심 가정은 "로그인 직후 NRIME가 한 번 잡힌 뒤에도 startup apps가 다시 ABC를 잡을 수 있다"는 것이다. 그래서 helper를 오래 상주시킨 것이 아니라, 로그인 초반만 짧게 강하게 감시하도록 했다.
  - 내부 전환 최적화는 새로운 시스템 입력 소스를 더 만들지 않고, 기존 `Toggle English`/`Switch to Korean`/`Switch to Japanese` shortcut이 계속 중심이 되도록 유지했다.
  - 아직 실제 체감 검증은 로그아웃/로그인 1회가 필요하다. developer mode를 켜면 helper가 어느 trigger에서 NRIME를 되찾았는지 로컬 로그로 확인할 수 있다.

## 2026-03-13 04:55 JST | Codex (GPT-5)

- 범위:
  - `1.0.3` 릴리스 준비 및 배포
- 무엇을 했는지:
  - 로그인 초기 복구 안정화 변경을 새 패치 버전 `1.0.3`으로 묶기 위해 앱/설정/helper/PKG 메타데이터 버전을 올렸다.
  - 릴리스용 PKG를 다시 빌드해 `NRIME-1.0.3.pkg`를 생성했고, 해시까지 확인했다.
- 어떻게 수정했는지:
  - `NRIME/Resources/Info.plist`, `NRIMESettings/Info.plist`, `NRIMERestoreHelper/Info.plist`의 `CFBundleShortVersionString`/`CFBundleVersion`을 `1.0.3` / `4`로 맞췄다.
  - `project.yml`의 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`도 같은 값으로 올렸다.
  - `Tools/pkg/distribution.xml`의 component package 버전을 `1.0.3`으로 맞췄고, 내부 문서 `NRIME.md`의 About 탭 버전 설명도 갱신했다.
  - `Tools/build_pkg.sh`를 권한 있는 환경에서 실행해 새 release 산출물을 만들었다. sandbox에서는 SwiftPM/Xcode cache 경로 접근 제한 때문에 PKG 빌드가 실패해 escalation 후 재실행했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Resources/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/Tools/pkg/distribution.xml`
  - `/Users/nr2bj/Documents/NRIME/NRIME.md`
- 검증:
  - 실행 명령:
    - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
    - `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
    - `shasum -a 256 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.3.pkg`
  - 결과:
    - `117 tests, 0 failures`
    - `build/NRIME-1.0.3.pkg` 생성 완료
    - SHA-256: `7cf436ca5fd6a9ff4c49445e59df97f4e2aa3138becb86ae27aae2b003dce09e`
- 메모:
  - 이번엔 기존 `v1.0.2`를 덮어쓰기보다 새 `v1.0.3` 릴리스로 분리하는 편이 추적과 회귀 비교에 더 안전하다고 판단했다.
  - 다음 단계는 커밋, `v1.0.3` 태그, GitHub release 생성/업로드다.

## 2026-03-13 04:56 JST | Codex (GPT-5)

- 범위:
  - `1.0.3` 원격 배포 반영
- 무엇을 했는지:
  - 릴리스 커밋과 태그가 로컬에 만들어진 상태를 확인한 뒤, `main`과 `v1.0.3`를 원격에 올리고 GitHub release 자산 업로드까지 마무리하는 단계로 정리했다.
- 어떻게 수정했는지:
  - 먼저 `git status`, 최근 커밋, 태그 존재 여부, PKG 해시를 확인해 현재 배포 기준점이 `db5cbb2 Release 1.0.3`과 `build/NRIME-1.0.3.pkg`라는 점을 고정했다.
  - 그 다음 이 배포 절차 자체를 worklog에 남겨, 다른 에이전트가 "코드는 어느 커밋인지", "PKG는 어느 파일인지", "다음 남은 단계가 무엇인지"를 한 파일에서 바로 파악할 수 있게 했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `git status --short`
    - `git log --oneline -n 3`
    - `git tag --list 'v1.0.3'`
    - `shasum -a 256 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.3.pkg`
  - 결과:
    - 작업 트리 clean
    - 릴리스 커밋: `db5cbb2 Release 1.0.3`
    - 태그: `v1.0.3`
    - PKG SHA-256: `7cf436ca5fd6a9ff4c49445e59df97f4e2aa3138becb86ae27aae2b003dce09e`
- 메모:
  - 이 엔트리는 코드 수정이 아니라 배포 상태를 기록하는 용도다. 실제 원격 푸시와 GitHub release 업로드 결과는 다음 엔트리나 커밋 메시지로 이어서 추적하면 된다.

## 2026-03-13 05:02 JST | Codex (GPT-5)

- 범위:
  - `1.0.3` GitHub 배포 완료
- 무엇을 했는지:
  - `main` 브랜치와 `v1.0.3` 태그를 GitHub로 푸시했고, 새 GitHub release를 만들어 `NRIME-1.0.3.pkg`를 업로드했다.
- 어떻게 수정했는지:
  - 먼저 `main`을 푸시해 릴리스 준비 커밋과 worklog 커밋을 원격에 반영했다.
  - 이어서 주석 태그 `v1.0.3`를 푸시했고, 태그가 실제 릴리스 커밋 `db5cbb2 Release 1.0.3`을 가리키는 것을 확인했다.
  - 마지막으로 GitHub CLI로 `v1.0.3` release를 새로 생성하면서 `build/NRIME-1.0.3.pkg`를 자산으로 업로드했고, 릴리스 노트에는 로그인 초기 복구 강화와 내부 모드 기억 개선을 요약해 적었다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `git push origin main`
    - `git push origin v1.0.3`
    - `gh release create v1.0.3 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.3.pkg -R NR2BJ/NRIME ...`
  - 결과:
    - `origin/main` 최신 커밋: `270ec85 Update release worklog`
    - 태그 대상 커밋: `db5cbb2 Release 1.0.3`
    - 릴리스 URL: `https://github.com/NR2BJ/NRIME/releases/tag/v1.0.3`
    - 업로드 자산: `NRIME-1.0.3.pkg`
    - PKG SHA-256: `7cf436ca5fd6a9ff4c49445e59df97f4e2aa3138becb86ae27aae2b003dce09e`
- 메모:
  - `main`은 worklog 기록 때문에 릴리스 태그보다 한 커밋 앞서 있다. 실제 릴리스 코드는 `v1.0.3 -> db5cbb2`를 기준으로 보면 된다.
  - 이후 hotfix가 필요하면 `v1.0.3`를 덮어쓰지 말고 `1.0.4`로 올리는 편이 추적에 안전하다.

## 2026-03-13 13:43 JST | Codex (GPT-5)

- 범위:
  - 설정 UI 버전 표기 자동화
  - 앱/PKG 버전 소스 단일화
- 무엇을 했는지:
  - 설정 UI가 `1.0.2`처럼 뒤처진 값을 보일 수 있던 원인을 추적했고, 버전 값을 `project.yml` 한 군데에서만 관리하도록 정리했다.
  - `NRIME`, `NRIMESettings`, `NRIMERestoreHelper`, PKG 파일명이 모두 같은 버전 값을 자동으로 따라오도록 빌드 경로를 수정했다.
- 어떻게 수정했는지:
  - 확인 결과 `AboutTab.swift`는 이미 `Bundle.main`에서 버전을 읽고 있었고, 문제는 UI 문자열이 아니라 번들 메타데이터 소스가 여러 군데로 갈라져 있던 구조였다.
  - `project.yml`의 공통 `settings.base`에 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`을 두고, 각 타깃 `Info.plist`는 하드코딩 숫자 대신 `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`을 읽도록 바꿨다.
  - `Tools/build_pkg.sh`는 더 이상 소스 `Info.plist`에서 버전을 읽지 않고, 실제로 빌드된 `NRIME.app`의 `Info.plist`에서 버전을 읽도록 바꿨다. 그래서 PKG 이름과 component package 버전도 빌드 산출물과 자동 동기화된다.
  - `Tools/pkg/distribution.xml`은 `__VERSION__` placeholder를 두고, PKG 빌드 시점에 `sed`로 실제 버전을 주입하도록 정리했다.
  - 추가로 디버깅 과정에서 로컬 `build/Debug/NRIMESettings.app`가 여전히 `1.0.2`였음을 확인했고, 이번 수정 후 `Debug`/`Release` 모두 `1.0.3 (4)`로 맞춰지는 것을 검증했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Resources/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/Info.plist`
  - `/Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
  - `/Users/nr2bj/Documents/NRIME/Tools/pkg/distribution.xml`
- 검증:
  - 실행 명령:
    - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIMESettings -configuration Debug SYMROOT=/Users/nr2bj/Documents/NRIME/build build`
    - `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
    - `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Users/nr2bj/Documents/NRIME/build/Debug/NRIMESettings.app/Contents/Info.plist`
    - `/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Users/nr2bj/Documents/NRIME/build/Debug/NRIMESettings.app/Contents/Info.plist`
    - `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Users/nr2bj/Documents/NRIME/build/Release/NRIMESettings.app/Contents/Info.plist`
    - `/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Users/nr2bj/Documents/NRIME/build/Release/NRIMESettings.app/Contents/Info.plist`
    - `shasum -a 256 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.3.pkg`
  - 결과:
    - 전체 테스트 `117 tests, 0 failures`
    - `build/Debug/NRIMESettings.app`: `1.0.3`, build `4`
    - `build/Release/NRIMESettings.app`: `1.0.3`, build `4`
    - 새 PKG SHA-256: `0fc481b1fa840b0671f655cc6a55ad141bf79f3c8414c43987e615653a5ef9dc`
- 메모:
  - 이번 수정은 "설정 UI 문자열 수정"이 아니라 버전 메타데이터 공급 경로를 단일화한 것이다. 다음부터는 버전을 올릴 때 `project.yml`의 공통 버전만 바꾸면 UI와 PKG가 같이 따라온다.
  - 현재 설치되어 있는 로컬 `NRIMESettings.app`가 예전 빌드면 About 탭은 계속 옛 버전을 보여줄 수 있으므로, 실제 표시를 바꾸려면 새 설치본으로 한 번 덮어써야 한다.

## 2026-03-13 13:50 JST | Codex (GPT-5)

- 범위:
  - 동일 버전 `1.0.3` 재배포 준비
- 무엇을 했는지:
  - 버전 자동화 수정이 들어간 현재 작업 트리를 다시 검증하고, 같은 `1.0.3` 릴리스에 덮어쓸 새 PKG 산출물을 확정했다.
- 어떻게 수정했는지:
  - `xcodegen generate` 후 전체 테스트를 다시 돌려 회귀가 없는지 확인했다.
  - `Tools/build_pkg.sh`로 새 `NRIME-1.0.3.pkg`를 빌드하고, 내부 `NRIMESettings.app` 버전이 실제로 `1.0.3` / build `4`로 찍히는지 확인했다.
  - 이번 재배포는 버전 문자열을 올리지 않고 같은 `v1.0.3` 태그와 릴리스 자산만 최신 빌드로 교체하는 전략이다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
    - `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
    - `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Users/nr2bj/Documents/NRIME/build/Release/NRIMESettings.app/Contents/Info.plist`
    - `/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Users/nr2bj/Documents/NRIME/build/Release/NRIMESettings.app/Contents/Info.plist`
    - `shasum -a 256 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.3.pkg`
  - 결과:
    - 전체 테스트 `117 tests, 0 failures`
    - `NRIMESettings.app` version: `1.0.3`
    - `NRIMESettings.app` build: `4`
    - 새 PKG SHA-256: `4c3f2e864f8f201812eb20aa14e367ae4008c64c67cf263e9d3a10e98630c27c`
- 메모:
  - 이전 공개 `1.0.3` 자산과 이번 자산의 해시는 다르다. 사용자에게 노출되는 버전명은 같지만, 설정 앱 버전 표기와 PKG 버전 동기화는 이번 빌드가 맞는 상태다.

## 2026-03-13 13:51 JST | Codex (GPT-5)

- 범위:
  - `v1.0.3` 동일 버전 재배포 완료
- 무엇을 했는지:
  - `Fix version metadata sync` 커밋을 원격 `main`에 푸시하고, 기존 `v1.0.3` 태그를 새 커밋으로 강제 이동시킨 뒤 GitHub 릴리스의 `NRIME-1.0.3.pkg` 자산을 새 빌드로 교체했다.
- 어떻게 수정했는지:
  - 버전 메타데이터 단일화 변경을 하나의 커밋으로 묶고, `git tag -fa v1.0.3`로 같은 버전 태그를 새 커밋 `9aa7bcd`로 옮겼다.
  - `git push origin main` 후 `git push origin --force v1.0.3`로 원격 반영했고, `gh release upload ... --clobber`로 기존 PKG 자산을 덮어썼다.
  - 마지막으로 `gh release view`로 릴리스 자산 digest가 로컬 빌드 해시와 일치하는 것을 확인했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `git push origin main`
    - `git push origin --force v1.0.3`
    - `gh release upload v1.0.3 /Users/nr2bj/Documents/NRIME/build/NRIME-1.0.3.pkg -R NR2BJ/NRIME --clobber`
    - `gh release view v1.0.3 -R NR2BJ/NRIME --json tagName,name,url,targetCommitish,assets`
  - 결과:
    - `main` 최신 릴리스 커밋: `9aa7bcd Fix version metadata sync`
    - `v1.0.3` 대상 커밋: `9aa7bcd`
    - GitHub release URL: `https://github.com/NR2BJ/NRIME/releases/tag/v1.0.3`
    - 업로드 자산: `NRIME-1.0.3.pkg`
    - GitHub asset digest: `sha256:4c3f2e864f8f201812eb20aa14e367ae4008c64c67cf263e9d3a10e98630c27c`
- 메모:
  - 같은 `1.0.3` 버전명을 유지한 채 공개 자산만 교체했으므로, 이미 받아간 초기 `1.0.3` 빌드와 현재 GitHub `1.0.3`은 내부적으로 다를 수 있다.
  - 이번 시점부터는 `v1.0.3` 기준으로 설정 UI도 `Bundle.main`에서 읽은 `1.0.3`을 정확히 표시해야 한다.

## 2026-03-13 14:23 JST | Codex (GPT-5)

- 범위:
  - 설정 백업/복원 기능
  - 한자 후보 선택 기억
  - 설정 앱 UI
  - 공통 설정 직렬화 모델
  - 관련 테스트 추가
- 무엇을 했는지:
  - 설정 앱에서 현재 NRIME 설정을 JSON으로 export/import할 수 있는 경로를 추가했다.
  - export/import 대상에 단축키, 일본어 키 설정, per-app 모드 설정, 개발자 모드, 마지막 비영문 모드, 한자 후보 선택 기억까지 포함시켰다.
  - 한글 한자 변환에서 사용자가 직전에 고른 한자를 기억해서, 다음 동일 음절 변환 시 그 후보가 먼저 보이도록 했다.
- 어떻게 수정했는지:
  - `Shared/SettingsTransfer.swift`를 새로 만들어 App Group `UserDefaults`를 그대로 snapshot으로 캡처하고 JSON으로 encode/decode/apply하는 공통 전송 모델을 만들었다. 설정 앱과 입력기 프로세스가 같은 포맷을 공유하도록 shortcut / Japanese key config는 타입 복제 대신 raw `Data`로 옮기게 했다.
  - `Shared/HanjaSelectionStore.swift`를 새로 만들어 `(hangul, hanja)` 쌍을 최근순으로 저장하는 경량 저장소를 추가했다. 동일 hangul의 새 선택이 들어오면 이전 선택을 교체하고, 최대 개수를 넘으면 오래된 엔트리를 잘라낸다.
  - `NRIMESettings/SettingsStore.swift`에 `reloadFromDefaults()`, `exportSettingsInteractively()`, `importSettingsInteractively()`를 추가했다. import 후에는 `@Published` 값을 defaults에서 다시 읽어 UI와 런타임 상태를 즉시 맞춘다.
  - `NRIMESettings/GeneralTab.swift`에 `Backup & Restore` 섹션을 추가하고 `NSSavePanel` / `NSOpenPanel` 기반 export/import 버튼과 결과 메시지를 연결했다.
  - `NRIME/Engine/Korean/KoreanEngine.swift`에서 한자 후보를 보여주기 직전에 저장된 선호 한자를 후보 맨 앞으로 재정렬하게 했고, `NRIME/Controller/NRIMEInputController.swift`에서 실제 한자 확정 시 선택한 후보를 기억하도록 연결했다.
  - `project.yml`에 새 shared 파일들을 `NRIME`와 `NRIMESettings` 둘 다 포함시키도록 추가해, 설정 앱과 입력기 본체가 같은 snapshot/selection-memory 구현을 공유하게 했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/SettingsTransfer.swift`
  - `/Users/nr2bj/Documents/NRIME/Shared/HanjaSelectionStore.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/SettingsStore.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/GeneralTab.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/HanjaSelectionStoreTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/SettingsTransferTests.swift`
- 검증:
  - 실행 명령:
    - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `122 tests, 0 failures`
    - `SettingsTransferTests` 추가 2개 통과
    - `HanjaSelectionStoreTests` 추가 3개 통과
- 메모:
  - settings export/import는 현재 App Group defaults 기반이라, 파일 하나로 다른 맥에 설정을 옮기거나 베타테스트용 재현 환경을 공유하기 좋다.
  - snapshot schema는 `1`로 시작했다. 나중에 키 구조를 바꾸면 decode 시점에 schema 분기를 추가하면 된다.
  - 한자 선택 기억은 "최근 1개 우선" 전략만 넣었다. 아직 frequency 기반 정렬이나 여러 후보 히스토리 merge는 하지 않았다.
  - import는 기존 설정을 merge하지 않고 snapshot 기준으로 덮어쓴다. optional blob이 비어 있으면 기존 `japaneseKeyConfig`/shortcut/한자 기억 데이터도 지우는 동작이 의도다.

## 2026-03-13 14:27 JST | Codex (GPT-5)

- 범위:
  - 로컬 설치 검증
  - 현재 작업 트리 배포 준비
- 무엇을 했는지:
  - 방금 추가한 설정 backup/restore와 한자 선택 기억 변경이 실제 설치 스크립트 기준으로도 정상 빌드/설치되는지 확인했다.
- 어떻게 수정했는지:
  - `Tools/install.sh`를 현재 작업 트리 기준으로 실행해서 `NRIME.app`, `NRIMESettings.app`, `NRIMERestoreHelper.app` 빌드와 사용자 라이브러리 설치, LaunchAgent 설치, 입력 소스 활성화까지 끝까지 통과시켰다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - 결과:
    - `NRIME`, `NRIMESettings`, `NRIMERestoreHelper` 빌드 성공
    - `/Users/nr2bj/Library/Input Methods` 설치 성공
    - login restore LaunchAgent 설치 성공
    - 선택된 입력 소스: `com.nrime.inputmethod.app.en`
- 메모:
  - install 스크립트 출력 기준으로 현재 로컬 환경에는 새 빌드가 이미 설치된 상태다.

## 2026-03-13 14:31 JST | Codex (GPT-5)

- 범위:
  - 후보창/인라인 인디케이터 위치 보정
  - 멀티 모니터 geometry 안정화
- 무엇을 했는지:
  - 일본어 후보창과 인라인 인디케이터가 caret 근처가 아니라 화면 구석으로 밀릴 수 있던 위치 계산을 수정했다.
- 어떻게 수정했는지:
  - `TextInputGeometry`에 caret rect가 속한 실제 스크린 frame을 고르는 helper를 추가했다. 이제 `NSScreen.main`이 아니라 caret rect와 교차하거나 가장 가까운 screen frame을 고른다.
  - `CandidatePanel`은 선택된 screen frame 기준으로 X/Y를 클램프하도록 바꾸고, 아래로 배치했을 때 화면 하단을 넘으면 caret 위쪽으로 올리는 fallback도 넣었다.
  - `InlineIndicator`도 같은 screen selection helper를 사용하도록 바꿔, 다른 모니터에서 메인 화면 기준으로 위치가 튀지 않게 했다.
  - `TextInputGeometryTests`에 screen frame 선택 로직 회귀 테스트 2개를 추가했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/InlineIndicator.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `124 tests, 0 failures`
    - `TextInputGeometryTests` 4개 통과
- 메모:
  - 사용자 보고 증상인 "모니터 왼쪽 아래로 튄다"는 의도한 변경이 아니었고, 이번 수정으로 현재 포커스된 caret가 있는 화면 기준으로 다시 붙는 쪽이 맞다.

## 2026-03-14 01:40 JST | Codex (GPT-5)

- 범위:
  - 일본어/한자 후보창 caret anchor 안정화
  - 잘못된 `selectedRange`/원점 좌표 방어
- 무엇을 했는지:
  - 일본어 후보창과 한자 후보창이 일부 앱에서 계속 모니터 왼쪽 아래로 붙는 문제를 다시 추적하고, 공통 caret geometry 로직을 보수적으로 바꿨다.
- 어떻게 수정했는지:
  - `TextInputGeometry`에서 IME 조합 중에는 `selectedRange`보다 `markedRange`를 먼저 anchor 후보로 쓰도록 순서를 바꿨다. 후보창은 조합 문자열에 붙는 게 맞기 때문에, 마크된 조합이 살아 있는 동안에는 그 위치를 우선 신뢰한다.
  - `firstRect(forCharacterRange:)`와 `attributes(...lineHeightRectangle:)`가 `(0,0)` 근처의 placeholder rect를 돌려주는 경우를 방지하기 위해, 화면의 좌하단 코너에 사실상 고정된 rect는 usable caret rect로 보지 않도록 했다. 이런 경우 후보창은 잘못된 코너 좌표 대신 이후 fallback 경로를 타게 된다.
  - developer mode가 켜져 있을 때 `firstRect`/`attributes` rect를 왜 채택하거나 거부했는지 `DeveloperLogger`에 남기도록 했다. 다음에 특정 앱에서 또 튀면 로그만으로도 어떤 anchor가 들어왔는지 바로 확인할 수 있다.
  - `TextInputGeometryTests`에 `markedRange` 우선, attributes fallback, 원점 rect 거부 회귀 테스트를 추가했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `128 tests, 0 failures`
    - `TextInputGeometryTests` 8개 통과
- 메모:
  - 이번 수정 가정은 "일부 앱이 조합 중에도 `selectedRange`를 0이나 문서 시작점처럼 반환하고, 그 결과 후보창이 실제 marked text가 아닌 문서 시작점/코너에 붙는다"는 것이다.
  - 그래도 동일 증상이 남으면 다음엔 developer mode 로그에서 `geometry` subsystem을 보고, 해당 앱이 `firstRect` 자체를 어떤 값으로 주는지 확인하면 된다.

## 2026-03-14 01:51 JST | Codex (GPT-5)

- 범위:
  - 후보창 수평 anchor 보정
  - 재설치/재시작 직후 초기 mode 복원 안정화
- 무엇을 했는지:
  - 일본어/한자 후보창이 현재 글자보다 오른쪽으로 멀게 붙는 체감을 줄이도록 수평 anchor 계산을 다듬었다.
  - 재설치 직후 NRIME가 영어 `.en` 입력 소스로 선택되어도 내부 mode가 바로 일본어로 복원되는 문제를 per-app 복원 경로에서 막았다.
- 어떻게 수정했는지:
  - `TextInputGeometry`에 후보창/인라인 인디케이터용 X anchor helper를 추가했다. 좁은 caret rect는 약간 왼쪽으로 당기고, 폭이 넓은 marked rect는 trailing edge 쪽에 더 가깝게 붙도록 분기했다.
  - `CandidatePanel`과 `InlineIndicator`는 새 anchor helper를 사용하고, caret rect를 못 얻었을 때는 이미 떠 있는 panel의 기존 origin을 유지하도록 바꿨다. mouse fallback을 타더라도 X를 조금 왼쪽으로 보정하고 developer log에 기록한다.
  - `StateManager.activateApp`는 프로세스 시작 후 첫 활성화에서는 저장된 per-app 비영문 mode를 바로 복원하지 않도록 했다. 그래서 install/restart 직후 `.en`이 선택된 상태에서 곧바로 `あ`로 튀는 경로를 막는다.
  - `StateManagerTests`에 초기 activation skip / 이후 activation restore 테스트를 추가했고, `TextInputGeometryTests`에 candidate anchor helper 테스트를 추가했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/InlineIndicator.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/StateManager.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/StateManagerTests.swift`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `132 tests, 0 failures`
- 메모:
  - 재설치 후 일본어로 시작한 증상은 `lastNonEnglishMode`보다 per-app restore가 원인일 가능성이 더 높다.
  - 후보창이 여전히 멀리 뜨면 developer mode 로그의 `geometry` 항목에서 mouse fallback이 실제로 발생했는지 먼저 보면 된다.

## 2026-03-14 01:58 JST | Codex (GPT-5)

- 범위:
  - 후보창 caret anchor 정밀화
  - 조합 전체 rect 반환 앱 대응
- 무엇을 했는지:
  - 후보창이 여전히 현재 글자보다 오른쪽으로 멀리 뜨는 증상을 다시 좁혀서, `firstRect`가 zero-length caret 요청에도 조합 전체 폭 rect를 돌려주는 앱을 별도 처리했다.
- 어떻게 수정했는지:
  - `TextInputGeometry`가 `markedRange` 안에 포함되는 `selectedRange`를 우선 caret anchor 후보로 쓰도록 바꿨다. `selectedRange`가 실제 조합 caret을 가리키는 앱에서는 이제 marked range 끝 전체 대신 그 지점을 먼저 시도한다.
  - `firstRect`가 multi-character `actualRange`와 넓은 rect를 돌려주면, 그 rect는 바로 채택하지 않고 attributes line-height rect를 먼저 시도하도록 바꿨다. 그래도 attributes가 없으면 그 넓은 rect를 deferred fallback으로만 사용한다.
  - 테스트용 mock client에 `firstRect`의 `actualRange` 응답을 주입할 수 있게 만들고, "zero-length caret 요청인데 조합 전체 rect가 반환되는" 회귀 테스트를 추가했다.
  - 최신 수정 후 다시 사용자 라이브러리의 `NRIME.app`/`NRIMESettings.app`/`NRIMERestoreHelper.app`를 직접 교체 설치하고 `.en` input source를 재선택했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `134 tests, 0 failures`
  - 설치:
    - 최신 Debug 빌드를 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - 입력 소스 재선택 결과: `com.nrime.inputmethod.app.en`
- 메모:
  - 이번 수정의 핵심 가정은 "일부 앱이 caret rect가 아니라 조합 전체 rect를 `firstRect`로 주고 있다"는 것이다.
  - 그래도 후보창이 오른쪽으로 멀면 developer mode 로그의 `geometry` 항목에서 `Skipped wide firstRect in favor of attributes anchor` 또는 `Using deferred firstRect fallback`가 찍히는지 먼저 확인하면 된다.

## 2026-03-14 03:23 JST | Codex (GPT-5)

- 범위:
  - 후보창 수평 정렬 회귀 수정
- 무엇을 했는지:
  - 후보창을 caret 끝 기준으로 붙이던 최근 수정이 오히려 오른쪽으로 치우친다는 사용자 피드백을 반영해, 후보창과 인디케이터의 anchor 기준을 분리했다.
- 어떻게 수정했는지:
  - `CandidatePanel`은 이제 `TextInputGeometry.candidateAnchorRect(for:)`를 사용한다. 이 helper는 marked text가 있으면 조합 시작점 쪽 rect를 우선 사용하고, 없을 때만 caret rect로 fallback한다.
  - `InlineIndicator`는 계속 caret 기준을 유지해서 현재 입력 위치 표시만 담당하게 했다.
  - 기존 `candidateAnchorX` 보정은 제거하고, 후보창 X는 anchor rect의 `minX`를 그대로 쓰도록 되돌렸다. 후보창은 composition start 아래에 붙고, 인디케이터만 caret 끝을 따른다.
  - `TextInputGeometryTests`도 후보창 anchor 기준을 새 설계에 맞게 바꿨다.
  - 최신 Debug 빌드를 다시 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치하고 `.en` 입력 소스를 재선택했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `134 tests, 0 failures`
  - 설치:
    - 최신 Debug 빌드를 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - 입력 소스 재선택 결과: `com.nrime.inputmethod.app.en`
- 메모:
  - 사용자 피드백 기준으로 후보창은 "caret 끝"보다 "조합 텍스트 옆"에 붙는 쪽이 자연스럽다.
  - 이후 남는 문제는 수평 anchor 자체보다 각 앱이 marked range rect를 얼마나 정확하게 주는지의 차이일 가능성이 크다.

## 2026-03-14 03:26 JST | Codex (GPT-5)

- 범위:
  - 후보창 anchor 우선순위 재조정
- 무엇을 했는지:
  - 후보창이 여전히 오른쪽으로 치우친다는 추가 피드백에 맞춰, 후보창 전용 anchor 계산을 다시 줄였다. 핵심은 marked text 전체 rect보다 "marked text 시작 문자"의 line-height rect를 최우선으로 쓰는 것이다.
- 어떻게 수정했는지:
  - `TextInputGeometry.candidateAnchorRect(for:)`가 이제 marked range가 있을 때 `attributes(forCharacterIndex: markedRange.location)`를 먼저 사용한다.
  - 그 다음에만 `firstRect`를 시작 위치(`length 0`, `length 1`) 기준으로 시도하고, 마지막 fallback으로 marked range 전체 bounding rect를 사용한다.
  - developer log에도 candidate anchor가 어느 단계에서 결정됐는지 남기도록 했다.
  - 테스트 mock에 요청 range별 `firstRect` 응답을 주입할 수 있게 해서, start rect unavailable → bounding rect fallback 경로도 테스트로 고정했다.
  - 최신 Debug 빌드를 다시 `/Users/nr2bj/Library/Input Methods`에 직접 설치하고 `.en` 입력 소스를 재선택했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `135 tests, 0 failures`
  - 설치:
    - 최신 Debug 빌드를 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - 입력 소스 재선택 결과: `com.nrime.inputmethod.app.en`
- 메모:
  - 이제 후보창 위치는 "marked text 시작 문자 line-height rect"를 우선하므로, 이전 회귀보다 훨씬 예전 느낌에 가까워져야 한다.
  - 그래도 아직 오른쪽이면 그 시점에는 앱이 start character line-height rect조차 넓게 주는 사례라서, 다음 단계는 AX fallback 검토가 맞다.

## 2026-03-14 03:28 JST | Codex (GPT-5)

- 범위:
  - 후보창 위치 회귀 롤백
- 무엇을 했는지:
  - 후보창이 최근 수정 이후 더 오른쪽으로 치우친다는 피드백에 따라, 후보창 전용 anchor 실험을 되돌리고 원래 덜 나빴던 `caretRect(for:)` 경로로 복귀시켰다.
- 어떻게 수정했는지:
  - `CandidatePanel`은 다시 `TextInputGeometry.caretRect(for:)`를 사용하도록 되돌렸다.
  - `TextInputGeometry.candidateAnchorRect(for:)`와 그에 딸린 후보창 전용 테스트/Mock 분기는 제거했다.
  - 즉, 최근에 추가했던 후보창 전용 start-anchor 실험은 걷어내고, 화면 선택/코너 방어/선택범위-표시범위 처리 같은 공통 caret 안정화만 남겼다.
  - 최신 Debug 빌드를 다시 `/Users/nr2bj/Library/Input Methods`에 직접 설치하고 `.en` 입력 소스를 재선택했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `132 tests, 0 failures`
  - 설치:
    - 최신 Debug 빌드를 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - 입력 소스 재선택 결과: `com.nrime.inputmethod.app.en`
- 메모:
  - 최근 후보창 전용 anchor 실험은 사용감 기준으로 명백한 회귀였다.
  - 다음 단계는 새 anchor를 더 추가하는 게 아니라, 현재 상태를 기준선으로 놓고 실제 앱 로그를 보고 최소 수정만 더하는 쪽이 맞다.

## 2026-03-14 03:30 JST | Codex (GPT-5)

- 범위:
  - 후보창 X 미세 보정
- 무엇을 했는지:
  - 후보창 위치를 다시 기준선으로 되돌린 뒤에도 약간 오른쪽이라는 피드백이 남아서, 후보창 X만 소폭 왼쪽으로 미세 조정했다.
- 어떻게 수정했는지:
  - `CandidatePanel.caretOrigin`에서 `x`를 `lineHeightRect.minX - 6`으로 조정했다.
  - 즉, 최근의 실험적인 anchor 분기는 제거한 상태를 유지하면서, 수평 위치만 6px 왼쪽으로 당겼다.
  - 최신 Debug 빌드를 다시 `/Users/nr2bj/Library/Input Methods`에 직접 설치하고 `.en` 입력 소스를 재선택했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `132 tests, 0 failures`
  - 설치:
    - 최신 Debug 빌드를 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - 입력 소스 재선택 결과: `com.nrime.inputmethod.app.en`
- 메모:
  - 현재 기준선은 `caretRect(for:) + 6px left nudge`다.
  - 이 상태에서도 약간 오른쪽이면, 다음 조정은 큰 로직 변경이 아니라 2~4px 단위 보정 문제로 보는 게 맞다.

## 2026-03-14 03:33 JST | Codex (GPT-5)

- 범위:
  - 후보창 위치 회귀 축소
- 무엇을 했는지:
  - 후보창이 입력 필드 첫 부분에 고정되고 글자를 가리는 증상에 맞춰, 최근에 넣었던 `wide firstRect -> attributes 우선` 규칙을 제거했다.
- 어떻게 수정했는지:
  - `TextInputGeometry.caretRect(for:)`가 다시 "usable한 `firstRect`를 우선 사용하고, unusable할 때만 `attributes`로 fallback" 하도록 단순화했다.
  - 즉, 최근 회귀를 만든 `shouldPreferAttributesRect` / deferred fallback 분기를 걷어내고, 남겨둘 가치가 있는 방어만 유지했다:
    - `(0,0)` 코너 pinned rect 거부
    - off-screen / zero rect 거부
    - geometry decision developer log
  - `CandidatePanel`의 X 위치도 최근 6px 왼쪽 실험을 제거하고 원래 `lineHeightRect.origin.x`로 복귀시켰다.
  - 최신 Debug 빌드를 다시 `/Users/nr2bj/Library/Input Methods`에 직접 설치하고 실행 중이던 `NRIME` 프로세스를 내려 새 코드가 뜨게 했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `132 tests, 0 failures`
  - 설치:
    - DerivedData Debug 산출물을 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - LaunchAgent 재로딩
    - 실행 중이던 `NRIME` 프로세스 재시작 유도(`pkill -x NRIME`)
- 메모:
  - 이번 수정의 의도는 "새 기준점을 더 똑똑하게 찾기"가 아니라, 실제 사용감이 괜찮았던 `firstRect` 경로를 되살리되 코너 고정 버그만 막는 것이다.
  - 이 상태에서도 여전히 입력 필드 첫 부분에 붙으면, 다음 의심 지점은 `selectedRange`/`markedRange` 우선순위 쪽이다.

## 2026-03-14 03:43 JST | Codex (GPT-5)

- 범위:
  - 후보창 오른쪽 경계 정렬 개선
- 무엇을 했는지:
  - 사용자가 올린 스크린샷 기준으로, 후보창 위치가 랜덤한 게 아니라 "입력 위치가 화면 오른쪽에 가까워질수록 패널이 통째로 왼쪽으로 밀려 caret와 멀어지는" 패턴임을 확인하고 정렬 방식을 바꿨다.
- 어떻게 수정했는지:
  - `TextInputGeometry.panelOriginX(for:panelWidth:within:)`를 추가했다.
  - 새 규칙은 다음과 같다:
    - 오른쪽 공간이 충분하면 기존처럼 anchor의 왼쪽(`anchorRect.minX`)부터 패널을 연다.
    - 오른쪽 공간이 부족하면, 단순 clamp 대신 패널의 오른쪽이 anchor의 오른쪽(`anchorRect.maxX`)에 맞도록 왼쪽으로 펼친다.
  - `CandidatePanel.caretOrigin`은 이제 화면 경계에서 단순 clamp하지 않고 위 helper를 사용한다.
  - 관련 회귀를 막기 위해 "공간 충분" / "오른쪽 부족" 케이스를 테스트로 추가했다.
  - 최신 Debug 빌드를 다시 `/Users/nr2bj/Library/Input Methods`에 직접 설치하고 `NRIME` 프로세스를 재시작했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `134 tests, 0 failures`
  - 설치:
    - DerivedData Debug 산출물을 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - LaunchAgent 재로딩
    - 실행 중이던 `NRIME` 프로세스 재시작 유도(`pkill -x NRIME`)
- 메모:
  - 지금 증상은 caret 추적 자체보다 "화면 오른쪽 경계에서의 패널 배치 전략" 문제가 더 컸다.
  - 이 수정 뒤에도 어색하면 다음 의심 지점은 수평 위치가 아니라 세로 기준(`below/above`) 또는 anchor source(`selectedRange` vs `markedRange`)다.

## 2026-03-14 03:46 JST | Codex (GPT-5)

- 범위:
  - 후보창 겹침/중구난방 배치 보정
- 무엇을 했는지:
  - 사용자가 올린 여러 스크린샷을 기준으로, 문제를 단순한 오른쪽 경계 처리로 보지 않고 "앱이 zero-length caret 요청에 이상하게 큰 rect를 줄 때 후보창이 중구난방으로 튀는 것"까지 같이 보정했다.
- 어떻게 수정했는지:
  - `MockTextInputClient`가 range별 `firstRect` 응답을 줄 수 있게 확장했다. 이걸로 zero-length 요청은 넓은 rect, length-1 요청은 작은 glyph rect를 주는 앱 동작을 테스트로 재현할 수 있게 했다.
  - `TextInputGeometry.caretRect(for:)`는 이제 `usable`하더라도 너무 넓은 zero-length / single-character `firstRect`는 즉시 채택하지 않고 한 번 defer한다.
    - 기준: `rect.width > 40`이고, 요청 range가 zero-length이거나 평균 문자 폭이 비정상적으로 큰 경우
  - defer한 뒤 다음 후보 range(예: `length: 1`, `markedRange`)에서 더 작은 rect가 나오면 그걸 우선 사용한다.
  - `panelOriginX`는 패널이 더 이상 글자를 덮지 않도록 기본적으로 `anchorRect.maxX + 2`에 붙고, 오른쪽 공간이 부족하면 `anchorRect.minX - panelWidth - 2` 쪽으로 왼쪽 전개한다.
  - 최신 Debug 빌드를 다시 `/Users/nr2bj/Library/Input Methods`에 직접 설치하고 `NRIME` 프로세스를 재시작했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/TextInputGeometryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 실행 명령:
    - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과:
    - 전체 테스트 `135 tests, 0 failures`
  - 설치:
    - DerivedData Debug 산출물을 `/Users/nr2bj/Library/Input Methods`에 직접 복사 설치
    - LaunchAgent 재로딩
    - 실행 중이던 `NRIME` 프로세스 재시작 유도(`pkill -x NRIME`)
- 메모:
  - 이번 수정의 핵심 가정은 "브라우저/웹 앱이 zero-length caret 요청에 큰 line/input-field rect를 줄 수 있다"는 것이다.
  - 이 상태에서도 여전히 불안정하면 다음 단계는 추정 보정보다 geometry 로그를 실제 앱 기준으로 읽고 `selectedRange`/`markedRange`/`firstRect actualRange` 조합을 좁히는 쪽이 맞다.

## 2026-03-14 23:30 JST | Claude Code (Opus 4.6)

- 범위:
  - 후보창(CandidatePanel) 및 인라인 인디케이터의 커서 위치 계산 로직 전면 재설계
- 무엇을 했는지:
  - Electron 앱(Codex, Claude Desktop 등)에서 후보창이 실제 커서 위치와 동떨어진 곳에 표시되는 문제 수정
  - 다른 오픈소스 IME(Squirrel/RIME, AquaSKK, Fcitx5, 구름입력기) 코드를 분석하여 positioning 전략 비교
  - 기존 Codex(GPT-5)의 비례 추정/narrowing 접근을 폐기하고, Squirrel/AquaSKK 스타일의 `attributes(forCharacterIndex:)` 폴백 방식으로 전환
- 어떻게 수정했는지:
  - `TextInputGeometry.caretRect(for:)` 완전 재작성:
    1. `firstRect` 우선 시도 — 정상 앱에서는 정확한 좌표 반환. `shouldDeferSuspiciousFirstRect`로 width > 40 rect 거부
    2. 폴백 1: `attributes(forCharacterIndex: caretIndex)` — caret 위치의 lineHeightRectangle 사용
    3. 폴백 2: `attributes(forCharacterIndex: 0)` — Squirrel/AquaSKK/Fcitx5가 공통으로 사용하는 방식. Electron에서 cursor-specific 쿼리 실패 시에도 올바른 Y/height 반환
  - 이전 Codex 수정의 `deferredSuspiciousRect`/`narrowSuspiciousRect`/비례추정 로직 전부 제거
  - `CandidatePanel.swift`: X 위치를 `panelOriginX(maxX + gap)` 대신 `origin.x` 기준 left-align으로 변경
  - 테스트 3개 추가, 불필요해진 테스트 2개 제거
- 수정 파일:
  - `NRIME/System/TextInputGeometry.swift` — caretRect 전면 재작성
  - `NRIME/UI/CandidatePanel.swift` — 후보창 X좌표 left-align
  - `NRIMETests/TextInputGeometryTests.swift` — Electron 시나리오 테스트 추가/정리
- 검증:
  - 테스트 전체 통과 확인 (xcodebuild test)
  - 사용자 실기기 테스트 진행 중 (Electron 앱 환경)
- 메모:
  - 핵심 발견: Squirrel, AquaSKK, Fcitx5 모두 `attributes(forCharacterIndex: 0)`를 주요 폴백으로 사용. `firstRect`는 보조적으로만 활용하거나 아예 사용 안 함
  - 구름입력기는 `IMKCandidates`(Apple 내장)를 사용하여 positioning을 직접 제어하지 않음
  - 어떤 IME도 Accessibility API를 positioning에 사용하지 않음
  - `attributes(0)` 폴백은 정확한 X좌표를 보장하진 않지만, 올바른 Y좌표와 line height를 제공하여 후보창이 최소한 입력 라인 근처에 표시됨
  - 이전 Codex의 비례 추정 방식이 실패한 이유: monospace 가정 부정확 + field rect의 origin.x가 텍스트 시작점과 다를 수 있음

## 2026-03-14 23:45 JST | Claude Code (Opus 4.6)

- 범위:
  - 버전 1.0.4 릴리즈 + 전체 타겟 버전 동기화 체계 수정
- 무엇을 했는지:
  - `project.yml`에서 `MARKETING_VERSION`을 `1.0.4`, `CURRENT_PROJECT_VERSION`을 `5`로 변경
  - NRIMESettings, NRIMERestoreHelper의 Info.plist가 project.yml 버전을 자동으로 상속하도록 수정
  - 기존에는 NRIMESettings/Info.plist에 `1.0` 하드코딩, NRIMERestoreHelper/Info.plist에 `1.0` 하드코딩 → 설정 UI에서 버전이 `1.0`으로 고정 표시되던 문제
- 어떻게 수정했는지:
  - `project.yml`의 NRIMESettings, NRIMERestoreHelper 타겟 `info.properties`에 `CFBundleShortVersionString: "$(MARKETING_VERSION)"`, `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"` 추가
  - xcodegen이 `GENERATE_INFOPLIST_FILE: true` + `info.path` 조합에서 plist를 재생성하므로, Info.plist 직접 수정 대신 project.yml의 `info.properties`에 선언하는 방식 채택
  - `NRIMESettings/SettingsStore.swift`의 fallback 버전 문자열도 `1.0.3` → `1.0.4`로 업데이트
- 수정 파일:
  - `project.yml` — MARKETING_VERSION 1.0.3→1.0.4, CURRENT_PROJECT_VERSION 4→5, Settings/RestoreHelper info.properties에 버전 변수 추가
  - `NRIMESettings/Info.plist` — xcodegen 재생성으로 `$(MARKETING_VERSION)` 적용
  - `NRIMERestoreHelper/Info.plist` — xcodegen 재생성으로 `$(MARKETING_VERSION)` 적용
  - `NRIMESettings/SettingsStore.swift` — fallback 버전 문자열 업데이트
- 검증:
  - `xcodebuild test`: 138 tests, 0 failures
  - `bash Tools/build_pkg.sh`: `build/NRIME-1.0.4.pkg` (23MB) 정상 생성
  - `gh release create v1.0.4`: https://github.com/NR2BJ/NRIME/releases/tag/v1.0.4
- 메모:
  - 앞으로 버전 올릴 때 `project.yml`의 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`만 수정하면 NRIME, NRIMESettings, NRIMERestoreHelper 전부 자동 반영됨
  - xcodegen이 `info.properties`를 plist에 merge하므로, Info.plist 직접 편집은 xcodegen 실행 시 덮어씌워짐에 주의

## 2026-03-15 00:00 JST | Claude Code (Opus 4.6)

- 범위: HanjaConverter SQLite 바인딩
- 무엇을 했는지: sqlite3_bind_text에서 SQLITE_STATIC(nil) 대신 SQLITE_TRANSIENT 사용하도록 수정
- 어떻게 수정했는지:
  - 파일 상단에 `private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)` 추가
  - `withCString` 클로저를 제거하고 `sqlite3_bind_text(statement, 1, hangul, -1, SQLITE_TRANSIENT)`로 직접 바인딩
  - SQLITE_TRANSIENT는 SQLite가 문자열을 내부적으로 복사하므로 메모리 안전성 향상
- 수정 파일:
  - `NRIME/Engine/Korean/HanjaConverter.swift`
- 검증: 코드 리뷰 완료, 빌드 미실행
- 메모: Swift String은 sqlite3_bind_text에 직접 전달 가능 (자동 C 문자열 변환). SQLITE_TRANSIENT 사용 시 SQLite가 즉시 복사하므로 수명 문제 없음.

## 2026-03-15 00:05 JST | Claude Code (Opus 4.6)

- 범위: NRIME/Engine/Korean/HangulAutomata.swift
- 무엇을 했는지: force-unwrap (`!`) 3건을 `guard let`으로 교체하여 런타임 크래시 방지
- 어떻게 수정했는지:
  - L134 `jamo.onsetIndex!` → `guard let onsetIdx = jamo.onsetIndex else { flush(); return }`
  - L189 `jamo.nucleusIndex!` → `guard let nucleusIdx = jamo.nucleusIndex else { flush(); return }`
  - L324 `Unicode.Scalar(scalar)!` → `guard let unicodeScalar = Unicode.Scalar(scalar) else { return "?" }`
- 수정 파일: `NRIME/Engine/Korean/HangulAutomata.swift`
- 검증: 코드 리뷰 완료, 기존 로직 변경 없음
- 메모: onsetIndex/nucleusIndex는 타입 시스템상 consonant→onsetIndex, vowel→nucleusIndex가 항상 존재해야 하지만, Optional 타입이므로 방어적 처리 추가. fallback은 현재 composing 상태를 flush하고 빈 결과 반환.

## 2026-03-15 00:10 JST | Claude Code (Opus 4.6)

- 범위: Mozc IPC 세션 관리
- 무엇을 했는지: resetSession()에 서버측 세션 삭제 추가, MozcConverter deinit에서 공유 서버 종료 제거
- 어떻게 수정했는지:
  - MozcClient.resetSession(): 로컬 상태 초기화 전에 DELETE_SESSION을 서버에 best-effort로 전송 (실패 무시)
  - MozcConverter.deinit: serverManager.shutdownServer() 호출 제거 — 여러 converter가 존재할 때 첫 번째 해제가 공유 서버를 죽이는 소유권 위반 수정
- 수정 파일: NRIME/Engine/Japanese/Mozc/MozcClient.swift, NRIME/Engine/Japanese/Mozc/MozcConverter.swift
- 검증: 코드 리뷰 완료, deleteSession() 패턴과 동일한 sessionQueue.sync 사용
- 메모: resetSession()은 에러 복구용이므로 서버 통신 실패를 무시함. shutdownServer()는 앱 종료 시 별도로 호출되어야 함.

## 2026-03-15 00:15 JST | Claude Code (Opus 4.6)

- 범위: KoreanEngine, JapaneseEngine 버그 수정
- 무엇을 했는지:
  1. KoreanEngine `applyResult`에서 committed 후 composing이 비어있을 때 marked text 미클리어 버그 수정
  2. JapaneseEngine `commitComposing()`, `commitLiveConversion()`에서 `capsLockKatakanaActive` 미리셋 버그 수정
- 어떻게 수정했는지:
  1. `else if result.committed.isEmpty` → `else`로 변경하여 committed 후에도 marked text 클리어
  2. 두 메서드 내 `shiftKatakanaActive = false` 다음에 `capsLockKatakanaActive = false` 추가
- 수정 파일:
  - `NRIME/Engine/Korean/KoreanEngine.swift`
  - `NRIME/Engine/Japanese/JapaneseEngine.swift`
- 검증: 코드 리뷰 완료, 빌드 미실행
- 메모: 기존 KoreanEngine 조건은 committed가 비어있을 때만 marked text 클리어 → committed 텍스트 존재 시 잔여 marked text 남는 문제.

## 2026-03-15 00:20 JST | Claude Code (Opus 4.6)

- 범위: CandidatePanel 다크모드 대응
- 무엇을 했는지: layer?.backgroundColor에 CGColor를 직접 설정하면 다크/라이트 모드 전환 시 색상이 갱신되지 않는 버그 수정
- 어떻게 수정했는지:
  - 컨테이너 뷰를 AppearanceAwareContainerView (NSView 서브클래스)로 교체, viewDidChangeEffectiveAppearance()에서 배경색과 border색 재적용
  - CandidateRowView에 _isSelected 상태 저장 + viewDidChangeEffectiveAppearance() 오버라이드 추가
  - CandidateGridCellView에 동일하게 _isSelected 상태 저장 + viewDidChangeEffectiveAppearance() 오버라이드 추가
  - updateListDisplay()/updateGridDisplay()의 중복 container.layer?.backgroundColor 설정 제거 (컨테이너가 자체 관리)
- 수정 파일: NRIME/UI/CandidatePanel.swift
- 검증: xcodebuild Debug 빌드 성공
- 메모: NSColor의 cgColor는 호출 시점의 정적 값이므로 appearance 변경 시 반드시 재적용 필요. NSPanel.backgroundColor = .clear는 투명 설정이므로 별도 처리 불요.

## 2026-03-15 00:25 JST | Claude Code (Opus 4.6)

- 범위: 코드 정리 및 소규모 버그 수정 (5건)
- 무엇을 했는지:
  1. Settings.swift에서 deprecated된 `UserDefaults.synchronize()` 호출 및 `synchronize()` 메서드 제거
  2. JapaneseTab.swift에서 `pkill -f "mozc_server"` → `pkill mozc_server`로 변경 (무관한 프로세스 kill 방지)
  3. GeneralTab.swift와 JapaneseTab.swift에 중복된 `keyCodeName` 함수를 KeyCodeNames.swift로 추출
  4. TextInputGeometry.swift의 `isUsableCaretRect`에서 `rect.width > 0` → `rect.width >= 0` 변경 (zero-width caret 허용)
  5. install.sh의 빌드 설정을 `-configuration Debug` → `-configuration Release`로 변경
- 어떻게 수정했는지:
  - Settings.swift: `synchronize()` 메서드 전체 삭제 (deprecated API)
  - JapaneseTab.swift: pkill arguments에서 `-f` 플래그 제거
  - KeyCodeNames.swift: 새 파일 생성, file-level `func keyCodeName` 정의. 양쪽 파일에서 기존 private 함수 삭제
  - TextInputGeometry.swift: 비교 연산자 `>` → `>=` 변경
  - install.sh: BUILD_DIR 경로와 3개 xcodebuild 호출 모두 Release로 변경
- 수정 파일:
  - NRIME/State/Settings.swift
  - NRIMESettings/JapaneseTab.swift
  - NRIMESettings/GeneralTab.swift
  - NRIMESettings/KeyCodeNames.swift (신규)
  - NRIME/System/TextInputGeometry.swift
  - Tools/install.sh
- 검증: 코드 리뷰 완료, 빌드 미실행
- 메모: KeyCodeNames.swift는 NRIMESettings 디렉토리에 있으므로 project.yml의 기존 `path: NRIMESettings` 소스 설정으로 자동 포함됨. xcodegen generate 필요.

## 2026-03-15 00:30 JST | Claude Code (Opus 4.6)

- 범위: Mozc IPC 클라이언트 및 서버 매니저 스레드 안전성
- 무엇을 했는지: MozcClient와 MozcServerManager의 공유 상태를 다중 스레드에서 안전하게 접근하도록 동기화 추가
- 어떻게 수정했는지:
  - MozcClient: `sessionQueue` (serial DispatchQueue, label: `com.nrime.mozc.session`) 추가. `sessionId`/`hasSession` 모든 read/write를 `sessionQueue.sync { }` 로 보호
  - MozcServerManager: `serverProcessLock` (NSLock) 추가. `serverProcess` 모든 read/write를 `withLock { }` 로 보호 — prewarmServer, ensureServerRunning, shutdownServer, killStaleServers, launchServer, terminationHandler 모두 적용
  - terminationHandler: 기존 `DispatchQueue.main.async` 제거 → `serverProcessLock.withLock` 으로 교체 (어떤 스레드에서든 안전)
- 수정 파일:
  - `NRIME/Engine/Japanese/Mozc/MozcClient.swift`
  - `NRIME/Engine/Japanese/Mozc/MozcServerManager.swift`
- 검증: 코드 리뷰 완료, 빌드 미실행
- 메모: MozcClient의 call()/machCall()은 sessionId/hasSession에 접근하지 않으므로 별도 동기화 불필요. MozcServerManager의 terminationHandler는 Process 내부 스레드에서 호출되므로 main dispatch 대신 lock 동기화가 적합.

## 2026-03-15 00:35 JST | Claude Code (Opus 4.6)

- 범위: InputSourceRecovery 로직 버그 + 스레드 안전성
- 무엇을 했는지:
  1. `pollInputSource()`가 `self.userInitiatedSwitch`를 무시하고 `false` 하드코딩하던 버그 수정
  2. 멀티스레드 접근 보호를 위한 동기화 추가
- 어떻게 수정했는지:
  - `pollInputSource()` 내 `shouldRecoverInputSource(userInitiatedSwitch: false)` → `shouldRecoverInputSource(userInitiatedSwitch: self.userInitiatedSwitch)`
  - `stateQueue` (serial DispatchQueue, label: `com.nrime.inputsource.state`) 추가
  - `userInitiatedSwitch`, `consecutiveRecoveries`, `lastRecoveryTime` 3개 프로퍼티를 underscore backing store + computed property 패턴으로 변경, 모든 read/write를 `stateQueue.sync` 보호
- 수정 파일:
  - `NRIME/System/InputSourceRecovery.swift`
- 검증: 코드 리뷰 완료
- 메모: 기존에는 사용자가 의도적으로 다른 입력소스로 전환해도 3초마다 NRIME으로 강제 복구 시도하는 버그 존재. DistributedNotificationCenter가 임의 스레드에서 콜백 호출할 수 있으므로 동기화 필수.

## 2026-03-15 00:45 JST | Claude Code (Opus 4.6)

- 범위: 전체 코드 리뷰 기반 안정성 개선 — 통합 검증
- 무엇을 했는지:
  - 4개 병렬 에이전트로 전체 코드베이스 리뷰 (Core/System, UI/Settings, Tests/Infra, Data/Resources)
  - 8개 병렬 에이전트로 발견된 이슈 일괄 수정
  - xcodegen 재생성, 138 tests 0 failures 확인, Release 빌드 및 설치 완료
- 수정 요약 (총 20건):
  - CRITICAL 5건: SQLite TRANSIENT, force-unwrap 3건, MozcClient 스레드, 다크모드
  - HIGH 5건: InputSourceRecovery 버그+스레드, MozcServerManager 스레드, marked text, UI 블로킹, install.sh Release
  - MEDIUM 5건: capsLock 리셋, 세션 누수, deinit 소유권, synchronize() 제거, pkill 안전
  - LOW 5건: keyCodeName 중복 추출, TextInputGeometry zero-width, 기타
- 수정 파일 (총 14개):
  - `NRIME/Engine/Korean/HanjaConverter.swift`
  - `NRIME/Engine/Korean/HangulAutomata.swift`
  - `NRIME/Engine/Korean/KoreanEngine.swift`
  - `NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `NRIME/Engine/Japanese/Mozc/MozcClient.swift`
  - `NRIME/Engine/Japanese/Mozc/MozcConverter.swift`
  - `NRIME/Engine/Japanese/Mozc/MozcServerManager.swift`
  - `NRIME/System/InputSourceRecovery.swift`
  - `NRIME/System/TextInputGeometry.swift`
  - `NRIME/State/Settings.swift`
  - `NRIME/UI/CandidatePanel.swift`
  - `NRIMESettings/JapaneseTab.swift`
  - `NRIMESettings/GeneralTab.swift`
  - `NRIMESettings/KeyCodeNames.swift` (신규)
  - `Tools/install.sh`
- 검증:
  - `xcodegen generate` 성공
  - `xcodebuild test`: 138 tests, 0 failures
  - `bash Tools/install.sh` (Release 빌드): 성공, 설치 완료
- 메모:
  - 기능 변경 없음, 순수 버그/안정성/코드 품질 개선
  - 테스트 커버리지 갭 (KoreanEngine, JapaneseEngine, Settings, CandidatePanel)은 별도 작업으로 후속 진행 필요
  - ja.lproj 로케일, Info.plist CharacterRepertoire 등 미수정 항목은 기능 추가에 해당하므로 이번 범위 제외

## 2026-03-15 00:50 JST | Claude Code (Opus 4.6)

- 범위: KeyCodeNames.swift 유실 복구 + 입력소스 등록 깨짐 해결
- 무엇을 했는지:
  - `git stash`로 최적화 코드를 일시 되돌렸을 때 untracked 신규 파일 `KeyCodeNames.swift`가 stash에 포함되지 않아 유실됨
  - `git stash pop` 후 NRIMESettings 빌드 실패 (`cannot find 'keyCodeName' in scope`) → NRIMESettings.app 누락 → 번들 구조 불완전 → macOS가 입력소스를 grayed out 처리
  - `KeyCodeNames.swift` 재생성으로 빌드 정상화
  - 반복적인 kill/reinstall/logout 사이클로 macOS HIToolbox 입력소스 등록이 손상됨 → 수동 HIToolbox 정리 후 클린 설치로 해결
- 어떻게 수정했는지:
  - git HEAD의 원본 `keyCodeName` 함수를 기반으로 `NRIMESettings/KeyCodeNames.swift` 재생성 (internal file-level function)
  - uninstall 시 `com.apple.HIToolbox`의 `AppleEnabledInputSources`, `AppleSelectedInputSources`, `AppleInputSourceHistory`에서 NRIME 엔트리 수동 제거
  - 클린 설치 + 로그아웃/로그인으로 TIS 프레임워크 캐시 갱신
- 수정 파일:
  - `NRIMESettings/KeyCodeNames.swift` (재생성)
- 검증:
  - xcodebuild: BUILD SUCCEEDED
  - 로그아웃/로그인 후 NRIME 정상 선택 및 사용 가능 확인
- 메모:
  - `git stash`는 untracked 파일을 포함하지 않음 — 신규 파일은 `git stash -u` 사용 필요
  - macOS 입력소스가 grayed out 될 때: HIToolbox defaults 정리 + 클린 설치 + 로그아웃/로그인으로 복구
  - `preventABCSwitch` 설정이 uninstall 시 초기화됨 — 재설치 후 수동으로 다시 활성화 필요

## 2026-03-14 15:24 JST | Codex

- 범위: InputSourceRecovery/Mozc 동시성 보강 + 후속 리뷰 대응
- 무엇을 했는지:
  - review finding 1, 3, 4를 실제 코드로 보강했다.
  - `InputSourceRecovery`는 throttle 상태 전이를 한 크리티컬 섹션으로 묶었고, `MozcClient`/`MozcServerManager`는 check-and-create / check-and-launch 경로를 직렬화했다.
  - finding 2(`TextInputGeometry`의 `attributes(forCharacterIndex: 0)` 폴백)는 이번 턴에서 의도적으로 보류하고, 다른 에이전트와 논의할 수 있도록 현재 판단 기준을 정리했다.
- 어떻게 수정했는지:
  - `InputSourceRecovery.swift`
    - `RecoveryThrottleState` / `RecoveryThrottleDecision`를 추가해 recovery throttle 판정을 순수 함수 `evaluateRecoveryThrottle(...)`로 분리했다.
    - `recoverInputSource()`가 `lastRecoveryTime`/`consecutiveRecoveries`를 각각 따로 읽고 쓰지 않도록 `beginRecoveryAttempt(at:)`에서 한 번에 계산/반영하게 바꿨다.
    - halt 후 5초 뒤 reset도 `resetRecoveryThrottle()`를 통해 같은 state queue에서 초기화하도록 정리했다.
  - `MozcClient.swift`
    - `sessionCreationLock`을 추가했다.
    - `ensureSession()`은 `hasSession`을 한 번 확인한 뒤, 세션 생성 lock을 잡고 다시 확인한 다음에만 `createSession()`을 호출하게 바꿨다. 이중 확인으로 동시 호출 시 중복 세션 생성 경쟁을 막는다.
  - `MozcServerManager.swift`
    - `launchQueue`를 추가했다.
    - `prepareServerForUse()`를 만들어 `isServerReachable()` 확인, `serverProcess?.isRunning` 확인, `killStaleServers()`, `launchServer()`까지를 한 직렬 큐에서 실행하도록 묶었다.
    - `prewarmServer()`, `ensureServerRunning()`, `restartServer()` 모두 이 준비 경로를 통해 서버 시작 경합을 줄이게 했다.
  - `InputSourceRecoveryTests.swift`
    - recovery throttle이 window 내 증가, window 밖 reset, limit 도달 halt를 기대한 방식으로 계산하는지 테스트 3개를 추가했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcServerManager.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: 141 tests, 0 failures
- 메모:
  - `TextInputGeometry`의 `attributes(forCharacterIndex: 0)` 폴백은 이번 턴에서 건드리지 않았다. 이건 단순 경쟁 조건 수정이 아니라 Electron 앱 대응 전략 전체를 다시 정해야 하는 문제라서, 다른 에이전트와 설계 판단을 맞춘 뒤 수정하는 편이 안전하다고 봤다.
  - 현재 판단은 `index 0` 폴백이 Y/line-height를 구하는 데는 유용할 수 있지만, X anchor까지 그대로 신뢰하면 원래 후보창 위치 버그를 재도입할 위험이 크다는 쪽이다.

## 2026-03-15 16:31 JST | Codex

- 범위: InputSourceRecovery 장시간 실행 후 ABC 고착 방지
- 무엇을 했는지:
  - 사용자가 “맥을 오래 켜두면 ABC로 돌아간다”는 증상을 말한 뒤 `InputSourceRecovery`와 `NRIMEInputController`를 다시 추적했다.
  - 원인 후보를 `deactivateServer`가 매번 `userInitiatedSwitch = true`를 켜고, 이 플래그가 입력 소스 변경 알림이 없으면 오래 남아 recovery를 영구적으로 막는 경로로 정리했다.
  - 이 stale suppression을 자동 만료시키고, NRIME가 다시 활성화되면 즉시 해제되도록 보강했다.
- 어떻게 수정했는지:
  - `NRIME/System/InputSourceRecovery.swift`
    - `_userInitiatedSwitchExpiresAt`와 `userInitiatedSwitchGracePeriod`(5초)를 추가했다.
    - `userInitiatedSwitch` getter는 읽을 때 만료 여부를 확인해 오래된 suppression을 자동 해제한다.
    - `pollInputSource()`와 `inputSourceChanged(_:)`는 suppression 상태를 한 번만 snapshot으로 읽어 decision/logging에 일관되게 사용한다.
    - `resolveUserInitiatedSwitch(now:isActive:expiresAt:)` helper를 추가해 expiry 로직을 테스트 가능하게 분리했다.
  - `NRIME/Controller/NRIMEInputController.swift`
    - `activateServer(_:)` 진입 시 `InputSourceRecovery.shared.userInitiatedSwitch = false`로 stale suppression을 즉시 해제한다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: 144 tests, 0 failures
- 메모:
  - 이번 수정의 핵심은 “ABC로 바뀌는 것 자체”보다 “그 뒤 복구가 안 붙는 이유”를 제거하는 데 있다.
  - 장시간 실행 후 ABC 고착은 secure input이나 앱 전환 자체보다, user-initiated suppression이 stale 상태로 남는 경로와 더 잘 맞는다.

## 2026-03-16 04:10 JST | Codex

- 범위:
  - `InputSourceRecovery`의 KVM/세션 복귀 경계 보강
  - recovery 판단 테스트 보강
- 무엇을 했는지:
  - 사용자가 KVM 스위치로 다른 컴퓨터에 갔다 돌아오면 `ABC`로 바뀐 뒤 NRIME로 복구되지 않는 증상을 보고했다.
  - 기존 recovery는 `input source changed`, `didWake`, 3초 polling 정도만 보고 있었는데, KVM 복귀는 일반 sleep/wake와 다르게 `session active`나 `screens wake` 경계만 발생하고 입력 소스 ID가 잠시 `nil`로 흔들릴 수 있다고 판단했다.
  - 그래서 resume 계열 이벤트를 더 넓게 감시하고, 복귀 직후에만 `unknown source`도 복구 대상으로 간주할 수 있게 보강했다.
- 어떻게 수정했는지:
  - `NRIME/System/InputSourceRecovery.swift`
    - `NSWorkspace.screensDidWakeNotification`, `NSWorkspace.sessionDidBecomeActiveNotification`을 추가로 감시하게 했다.
    - wake/session 복귀 시 `scheduleResumeRecoveryChecks(reason:)`를 통해 `0.2s`, `1.0s`, `3.0s` 지연으로 recovery poll을 여러 번 다시 시도하게 했다.
    - `pollInputSource(reason:allowUnknownSourceRecovery:)`를 도입해, 일반 polling은 기존처럼 현재 source ID가 명확히 non-NRIME일 때만 복구하고, resume 직후 재시도에서는 source ID가 `nil`이어도 복구를 허용할 수 있게 분리했다.
    - recovery 로그에 `reason`, `currentSourceID`, `allowUnknownSourceRecovery`를 남기도록 했다.
  - `NRIMETests/InputSourceRecoveryTests.swift`
    - `shouldTreatSourceAsRecoverable` helper에 대해 `nil source + 일반 polling`, `nil source + resume recovery`, `NRIME source + resume recovery` 케이스를 추가했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `147 tests, 0 failures`
- 메모:
  - 이번 수정은 “왜 ABC로 바뀌는가” 자체를 완전히 없애기보다는, KVM 전환처럼 입력 소스 변경 알림이 빠질 수 있는 경계에서 recovery가 놓치지 않도록 트리거를 넓힌 것이다.
  - 사용자가 developer log를 켜고 같은 상황을 다시 재현하면 `InputSourceRecovery`의 `reason=session_did_become_active` / `reason=screens_did_wake` / `currentSourceID=nil` 여부를 바로 확인할 수 있다.

## 2026-03-16 04:43 JST | Codex

- 범위:
  - 설정 모델 공통화 1단계
  - 설정 앱/입력기 간 타입 drift 제거
- 무엇을 했는지:
  - 입력기와 설정 앱에 중복 정의돼 있던 `ShortcutConfig`, `JapaneseKeyConfig`, 관련 enum들을 공용 파일로 합쳤다.
  - 테스트와 런타임 참조도 새 공용 타입을 기준으로 정리했다.
  - 설정 export 파일명에 쓰이던 버전 fallback 하드코딩(`1.0.4`)도 제거했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/Shared/SettingsModels.swift`를 추가해 공용 설정 타입을 정의했다.
  - `/Users/nr2bj/Documents/NRIME/project.yml`에서 `NRIME`와 `NRIMESettings` 타깃이 이 파일을 함께 포함하도록 바꿨다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/Settings.swift`에서 중복 정의를 제거하고 공용 타입을 사용하도록 정리했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/SettingsStore.swift`에서도 중복 정의를 제거하고 공용 타입을 사용하도록 정리했다.
  - `ShortcutHandler` 및 관련 테스트에서 `Settings.ShortcutConfig` 같은 옛 참조를 공용 `ShortcutConfig`로 교체했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/SettingsModels.swift`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/Settings.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/SettingsStore.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/ShortcutHandler.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/ShortcutHandlerTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/SettingsTransferTests.swift`
- 검증:
  - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `147 tests, 0 failures`
- 메모:
  - 이 단계는 다음 후보창/엔진 리팩터링 전에 타입 드리프트를 막는 기반 정리다.
  - 아직 설치/커밋/푸시는 하지 않았다. 다음 단계 묶음까지 본 뒤 진행하는 편이 자연스럽다.

## 2026-03-16 04:47 JST | Codex

- 범위:
  - 후보창 갱신 구조 정리 2단계
  - 일본어 후보창 표시 갱신 경로 중복 축소
- 무엇을 했는지:
  - 후보 목록이 그대로인 상태에서 highlight만 바뀌는 경우 `CandidatePanel.show()`가 매번 전체 레이아웃 캐시를 깨고 다시 그리던 경로를 정리했다.
  - 일본어 변환 중 후보창 갱신 로직이 컨트롤러 안에 여러 군데 복제돼 있던 것을 한 helper로 모았다.
  - 후보창 리렌더/위치 재계산이 실제로 줄어드는지 확인하는 테스트를 추가했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`에서 `show()`가 visible 상태의 동일 후보 목록을 다시 받을 때는 width cache와 rendered page cache를 유지하도록 바꿨다.
  - 같은 후보 목록에서는 `candidatesChanged`, `fontChanged`, `pageChanged`만 따로 계산해서, selection-only update는 highlight만 갱신하고 panel reposition도 생략하도록 정리했다.
  - debug 전용 metrics(`cacheRefreshCount`, `fullRenderCount`, `repositionCount`)를 넣어 selection-only update와 page change를 테스트로 검증할 수 있게 했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`에 `refreshJapaneseCandidatePanel(client:)` helper를 추가하고 prediction/number selection/highlight sync 이후 후보창 갱신을 모두 이 경로로 통합했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/CandidatePanelTests.swift`를 추가해 selection-only update, page change, candidate list change 각각이 cache/render/reposition에 어떻게 반영되는지 고정했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/UI/CandidatePanel.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/CandidatePanelTests.swift`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
- 검증:
  - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `150 tests, 0 failures`
- 메모:
  - 이 단계는 후보창 위치 계산 자체를 다시 바꾼 것이 아니라, 같은 후보 목록을 repeated `show()`로 덮어쓰면서 캐시를 매번 초기화하던 구조를 줄인 것이다.
  - 사용자 수동 확인은 아직 필수 아니다. 다음 단계에서 일본어 엔진/컨트롤러 책임 분리를 진행하고, 실제 후보창 위치나 런타임 체감에 영향이 큰 시점이 오면 그때만 짧게 확인을 부탁드리면 된다.

## 2026-03-16 04:54 JST | Codex

- 범위:
  - 일본어 엔진/컨트롤러 책임 분리 3단계
  - 컨트롤러의 Mozc 내부 접근 축소
- 무엇을 했는지:
  - 컨트롤러가 일본어 후보 상태와 Mozc 선택/하이라이트/submit을 직접 다루던 경로를 줄이고, 일본어 엔진의 공개 메서드로 되돌렸다.
  - 일본어 엔진 내부에서 반복되던 transient state 정리도 helper로 묶어, conversion/composing 경계에서 상태 초기화가 조금 더 일관되게 되도록 정리했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`에 `CandidatePanelState`, `candidatePanelState`, `selectConversionCandidate`, `highlightConversionCandidate`, `commitConversionSelection`을 추가했다.
  - 컨트롤러는 더 이상 `japaneseEngine.mozcConverter.selectCandidateByIndex(...)`, `highlightCandidateByIndex(...)`, `submit()`를 직접 호출하지 않고, 엔진 API를 통해 conversion 결과를 반영하도록 바꿨다.
  - 일본어 엔진에서 반복되던 `liveConversionActive`, `liveConvertedText`, katakana flags 초기화는 `clearTransientInputState()`로 모았다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `150 tests, 0 failures`
- 메모:
  - 이번 단계는 후보 상태와 Mozc IPC를 모두 엔진 안으로 완전히 숨긴 것은 아니지만, 최소한 컨트롤러가 후보 선택/하이라이트/submit 세부를 직접 조합하던 구조는 줄였다.
  - 다음 일본어 버그 수정부터는 `NRIMEInputController`보다 `JapaneseEngine` 경계에서 먼저 손보면 되는 비율이 더 높아졌다.

## 2026-03-16 04:54 JST | Codex

- 범위:
  - ABC 제한/입력 소스 복구 정책 정리 4단계
  - 이벤트별 중복 판단 제거
- 무엇을 했는지:
  - `InputSourceRecovery`가 startup/wake/session-active/poll/input-source-changed마다 거의 같은 recovery 판단식을 반복하던 구조를 policy evaluation 중심으로 정리했다.
  - resume/startup/poll/input-source-changed는 이제 공통 `RecoveryPolicyEvaluation`을 통해 같은 기준으로 recovery 여부를 결정한다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`에 `RecoveryPolicyEvaluation`과 `evaluateRecoveryPolicy(...)`를 추가했다.
  - startup/resume 쪽은 `scheduleRecoveryChecks(...)`와 `handleRecoverySignal(...)`로 통합해, delay/reason/unknown-source 허용 여부만 이벤트마다 넘기도록 바꿨다.
  - input source changed도 같은 policy evaluation을 쓰도록 바꾸고, 로그 metadata는 `metadata(from:extra:)` helper로 공통화했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`에 policy evaluation 테스트를 추가해 unknown source resume 처리와 suppression inputs를 고정했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `152 tests, 0 failures`
- 메모:
  - 이번 단계는 recovery trigger를 더 공격적으로 늘린 게 아니라, 이미 있던 trigger들이 어떤 정책으로 복구를 시도하는지 한 곳에서 설명할 수 있게 만드는 정리다.
  - 사용자가 각 단계마다 수동 확인할 필요는 없고, 실제 런타임 재현이 필요한 건 후보창 위치나 KVM 복귀처럼 UI/시스템 경계가 얽힌 상황일 때만 따로 보면 된다.

## 2026-03-16 05:01 JST | Codex

- 범위:
  - 설정 앱 일본어 사용자 사전 저장 경로 정리
  - 설치 스크립트 build configuration 정리
- 무엇을 했는지:
  - 사용자 사전 저장이 메인 스레드에서 protobuf serialize, 파일 쓰기, `pkill mozc_server`, `waitUntilExit()`를 한 번에 수행하던 경로를 background save + debounced restart로 바꿨다.
  - 설치 스크립트가 여전히 `Debug` 빌드를 기준으로 설치하던 부분을 `Release`로 바로잡았다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/UserDictionaryManager.swift`에 `SaveSnapshot`, `saveQueue`, `scheduleMozcRestart()`를 추가했다.
  - `save()`는 현재 UI 상태를 snapshot으로 잡은 뒤 background queue에서 protobuf를 serialize/write 하도록 바꿨고, 실패 시에만 main queue로 `lastError`를 반영하도록 정리했다.
  - 연속 편집 시 `mozc_server`를 매번 즉시 재시작하지 않도록 0.4초 debounce를 넣었다.
  - `/Users/nr2bj/Documents/NRIME/Tools/install.sh`는 `build/Release`와 `-configuration Release`를 쓰도록 바꿨다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/UserDictionaryManager.swift`
  - `/Users/nr2bj/Documents/NRIME/Tools/install.sh`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIMESettings -destination 'platform=macOS' build`
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `NRIMESettings build succeeded`, `152 tests, 0 failures`
- 메모:
  - 설정 앱 빌드와 입력기 테스트를 처음 병렬로 돌렸을 때 DerivedData build DB lock이 한 번 발생했지만, 순차 재실행에서는 문제 없이 통과했다. 코드 문제라기보다 같은 DerivedData를 동시에 잡은 실행 순서 문제였다.
  - 아직 남은 구조부채로는 `TextInputGeometry`의 `attributesAtZero` fallback 판단과 `JapaneseEngine` 내부의 candidate panel 직접 제어가 있다. 둘 다 바로 손댈 수는 있지만, 사용자 체감과 회귀 가능성을 같이 봐야 하는 영역이다.

## 2026-03-16 05:14 JST | Codex

- 범위:
  - 일본어 후보창 상태 소유권을 엔진에서 컨트롤러 쪽으로 더 정리
  - prediction 후보 처리의 패널 의존성 축소
- 무엇을 했는지:
  - 일본어 후보창 갱신을 `refreshJapaneseCandidatePanel(client:)` 한 경로로 더 모아서, commit/mouse click/shortcut/mode routing마다 패널 숨김/갱신이 제각각이던 부분을 줄였다.
  - prediction 후보 선택/닫기 경로를 컨트롤러가 먼저 처리하고, 엔진은 `commitPredictionSelection(...)` / `dismissPrediction()` API로만 상태를 바꾸도록 정리했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`에서 일본어 변환/예측 상태 처리 뒤마다 `refreshJapaneseCandidatePanel(client:)`를 호출하도록 보강했다.
  - `routeEvent`, `commitComposition`, `activateServer`, `commitOnMouseClick`, shortcut mode switch 경로에서도 일본어 엔진 상태가 바뀌면 같은 패널 refresh 경로로 정리했다.
  - prediction 상태에서는 `Tab`, 숫자키, `Up/Down`, `Escape`, `Enter`, `Space`, `Backspace`를 컨트롤러가 먼저 다루고, commit은 `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`의 `commitPredictionSelection(at:client:)`로 넘기도록 바꿨다.
  - `JapaneseEngine`에서는 prediction 전용 panel 조작(`NSApp.candidatePanel`)과 `currentPredictionSelectionIndex()`를 제거하고, `dismissPrediction()`을 엔진 상태 API로 승격했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `152 tests, 0 failures`
- 메모:
  - 이번 단계는 후보창 위치 계산(`TextInputGeometry`) 자체를 다시 건드린 게 아니라, 엔진 상태 변화와 패널 갱신 책임을 분리해 이후 회귀 면적을 줄이려는 정리다.
  - 사용자가 방금 확인한 후보창 위치가 크게 나쁘지 않은 상태라, `attributesAtZero` fallback 같은 geometry 정책은 이 단계에선 일부러 건드리지 않았다. 그쪽은 체감 안정성이 흔들릴 수 있어서 다음에 별도 판단으로 다루는 편이 안전하다.

## 2026-03-16 05:43 JST | Codex

- 범위:
  - `InputSourceRecovery` 예약 신호 구조 정리
  - 앱 재시작 경로의 메인 스레드 blocking 제거
- 무엇을 했는지:
  - startup/resume/timer 복구 신호를 문자열/불리언 인자 조합 대신 `ScheduledRecoverySignal` 모델로 묶고, 모니터링 세대가 바뀐 뒤 늦게 도착한 예약 recovery가 실행되지 않게 막았다.
  - 메뉴의 `Restart NRIME`가 `killall` 완료를 메인 스레드에서 기다리던 경로를 background 작업으로 옮겨 UI 정지를 줄였다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`에 `ScheduledRecoveryReason`, `ScheduledRecoverySignal`, `ScheduledRecoveryPlan`, `scheduledSignals(for:)`, `shouldRunScheduledSignal(...)`를 추가했다.
  - wake/session-active/startup 스케줄링은 이제 plan -> signal 배열로 변환한 뒤 공통 `handleRecoverySignal(_:)`로 처리한다.
  - `recoveryScheduleGeneration`을 두고 `startMonitoring()/stopMonitoring()`에서 세대를 갱신해, 이전 세션에서 예약된 `asyncAfter` recovery가 나중에 잘못 실행되지 않게 했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`에 signal plan과 generation gating 테스트를 추가했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/App/AppDelegate.swift`는 `restartApp()`에서 `killall` + `waitUntilExit()`를 background queue로 옮기고, 종료만 main queue에서 수행하게 바꿨다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/InputSourceRecovery.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/InputSourceRecoveryTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/App/AppDelegate.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `154 tests, 0 failures`
- 메모:
  - 이번 단계는 recovery 로직을 더 공격적으로 만든 게 아니라, 예약된 recovery 신호가 어떤 정책으로 실행되는지 더 설명 가능하게 정리한 쪽이다.
  - 후보창 위치(`TextInputGeometry`)는 최근 체감이 괜찮아진 상태라 이번 턴에서도 일부러 손대지 않았다. geometry는 회귀 위험이 커서 지금처럼 안정성이 보이는 동안엔 별도 기준으로 다루는 편이 낫다.

## 2026-03-16 05:48 JST | Codex

- 범위:
  - `TextInputGeometry` fallback 정책을 동작 유지형 구조로 정리
  - 설정 앱의 Mozc 재시작 보조 경로 정리
- 무엇을 했는지:
  - 후보창 위치 계산을 다시 바꾸지는 않고, 현재 fallback 순서(`firstRect` -> `attributes(caret)` -> `attributes(0)`)를 helper 단위로 분해해서 읽기 쉽게 정리했다.
  - 사용자 사전 저장 뒤 Mozc를 재시작할 때 background queue 안에서 `pkill` 종료까지 기다리던 부분을 fire-and-forget으로 낮췄다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`에 `FirstRectLookup`, `firstUsableCaretRect(for:)`, `firstRectLookup(for:range:)`, `attributesCaretRect(...)`, range dedupe helper를 추가했다.
  - `caretRect(for:)` 본문은 이제 precise firstRect, caret index attributes, index 0 attributes fallback을 helper 호출 순서로만 표현되게 정리했다.
  - `firstRect`는 처음엔 lookup을 한 번에 materialize했다가 테스트 seam(`lastFirstRectRange`)을 깨서, 다시 lazy lookup으로 돌려 원래 관찰 가능 동작을 유지했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/UserDictionaryManager.swift`의 `restartMozcServer()`는 `Process().executableURL` 기반 fire-and-forget으로 바꿨다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/TextInputGeometry.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/UserDictionaryManager.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `154 tests, 0 failures`
- 메모:
  - 이번 단계는 geometry 동작 변경이 목적이 아니라, 현재 안정적으로 보이는 정책을 코드에서 더 설명 가능하게 만든 쪽이다.
  - `attributesAtZero` fallback 자체는 아직 남겨뒀다. 이건 사용 체감과 직결되는 정책이라, 다음에 손댄다면 로그/재현 기준으로 별도 검토하는 편이 안전하다.

## 2026-03-16 06:57 JST | Codex

- 범위:
  - 로그인 직후 NRIME 자동 복구 helper
  - 로그인 복구 정책 테스트 보강
- 무엇을 했는지:
  - 재부팅 후 입력 소스가 `ABC`에 머무를 수 있는 경로를 줄이기 위해, 로그인 helper가 `currentInputSourceID() == nil`인 초기 부팅 상태도 복구 대상으로 보게 수정했다.
  - 로그인 후 뒤늦게 시작되는 앱이 `ABC`를 다시 잡는 경우를 덜 놓치도록 helper의 stabilization window를 늘렸다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/Shared/LoginRestorePolicy.swift`에 `shouldAttemptRestore(currentSourceID:allowUnknownSourceRecovery:)`를 추가해, login helper가 `nil` source를 기본적으로 recoverable로 취급하도록 했다.
  - 같은 파일에서 `stabilizationDuration`을 `15.0 -> 30.0`으로 늘려 로그인 초기 앱/세션 정착 구간을 더 오래 감시하게 했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/LoginRestoreController.swift`는 더 이상 `currentSourceIsNonNRIME()`에 직접 의존하지 않고, 위 정책 함수로 복구 여부를 판단하게 바꿨다. 로그 메타데이터는 `nil`일 때만 `unknown`으로 표시하게 정리했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/LoginRestorePolicyTests.swift`에 `nil` source 복구, NRIME source skip, ABC source 복구 테스트를 추가했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/LoginRestorePolicy.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMERestoreHelper/LoginRestoreController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/LoginRestorePolicyTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIMERestoreHelper -destination 'platform=macOS' build`
  - 결과: `157 tests, 0 failures`, `NRIMERestoreHelper build succeeded`
- 메모:
  - 로컬 LaunchAgent 경로와 helper 실행 파일은 정상으로 보였다. 이번 이슈는 설치 경로 불일치보다, 로그인 초반에 TIS current source가 `nil`로 보이면서 helper가 가장 중요한 첫 시도를 건너뛰는 쪽이 더 유력했다.
  - 이 수정은 로그아웃 없이도 새 helper를 다시 설치/재시작하면 적용되지만, 실제 reboot 복구는 한 번 다시 재현해봐야 닫힌다.

## 2026-03-16 07:41 JST | Codex

- 범위:
  - `Shift+Enter` 조합 확정 후 줄바꿈 재주입 경로
  - 한글/일본어 엔진 회귀 테스트 보강
- 무엇을 했는지:
  - 조합 중 `Shift+Enter`가 글자만 확정하고 줄바꿈이 빠지는 회귀를 줄이기 위해, 한글/일본어 엔진의 재주입 로직을 공통 helper로 통일했다.
  - 재주입 자체가 다시 빠지지 않도록 한글/일본어 엔진 테스트를 추가했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/Shared/ShiftEnterReposter.swift`를 새로 추가해, `Shift+Enter`를 `cgAnnotatedSessionEventTap` + `privateState`로 재주입하도록 공통화했다.
  - helper는 IMK marked text 정리가 끝나기 전에 newline이 삼켜지는 경우를 줄이기 위해 `0.01s` 지연 후 재주입하게 했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`는 기존 inline CGEvent 코드를 제거하고 공통 helper를 쓰게 바꿨다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`도 별도 `cghidEventTap` 재주입 구현을 제거하고 같은 helper를 쓰게 바꿨다. 이제 Korean/Japanese가 서로 다른 경로를 타지 않는다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`, `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`에 `Shift+Enter`가 commit과 repost 요청을 함께 내는지 검증하는 회귀 테스트를 추가했다.
  - `/Users/nr2bj/Documents/NRIME/project.yml`에 새 shared helper를 포함시켰고 `xcodegen generate`로 프로젝트를 재생성했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/ShiftEnterReposter.swift`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`
- 검증:
  - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `159 tests, 0 failures`
- 메모:
  - 이번 수정은 “어느 엔진에서만 다시 깨지는” 상황을 줄이기 위한 구조 정리 성격도 있다. 이전에는 Korean은 `cgAnnotatedSessionEventTap`, Japanese는 `cghidEventTap`로 갈라져 있었고, 그 차이가 회귀를 숨길 수 있었다.
  - 실제 체감은 일부 앱의 텍스트뷰 구현에 영향받을 수 있으니, 설치 후 한 번만 실사용 앱에서 `Shift+Enter`를 다시 확인하는 게 좋다.

## 2026-03-16 07:42 JST | Codex

- 범위:
  - 로컬 런타임 반영
- 무엇을 했는지:
  - `Shift+Enter` 공통 repost 수정과 최신 코드를 현재 맥의 입력기 설치본에 반영했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/Tools/install.sh`를 실행해 Release 빌드의 `NRIME.app`, `NRIMESettings.app`, `NRIMERestoreHelper.app`, LaunchAgent를 다시 설치했다.
  - 설치 후 활성 입력 소스를 `com.nrime.inputmethod.app.en`으로 다시 선택했다.
- 수정 파일:
  - 코드 수정 없음 (설치 반영)
- 검증:
  - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - 결과: 설치 완료, LaunchAgent 재설치 완료, `.en` input source 재선택 완료
- 메모:
  - 지금부터 사용자가 보는 증상은 방금 수정한 로컬 코드 기준이다. 이전 턴까지는 테스트만 돌고 설치가 안 된 시점이 잠깐 있었다.

## 2026-03-16 07:48 JST | Codex

- 범위:
  - 조합 중 modifier 단축키 재주입 경로
  - 일본어 변환 후보창 표시 fallback
  - 로컬 런타임 재설치
- 무엇을 했는지:
  - `Shift+Enter`뿐 아니라 `Command-A`처럼 조합 중 modifier 단축키가 "확정만 되고 원래 단축키 동작이 사라지는" 문제를 같은 원인으로 보고, 한글/일본어 엔진 모두 공통 재주입 helper를 통해 원래 키 조합을 다시 보내도록 정리했다.
  - 일본어 변환 중 Mozc가 real candidate list를 주지 않는 경우에도 후보창이 아예 사라지지 않도록, preedit만 있는 converting 상태에서 표시용 fallback candidate를 만들었다.
  - 위 수정이 실제 증상 확인 대상인 로컬 설치본에도 반영되도록 최신 Release 빌드를 다시 설치했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/Shared/ShiftEnterReposter.swift`는 역할이 너무 좁아 삭제하고, `/Users/nr2bj/Documents/NRIME/Shared/KeyEventReposter.swift`로 교체했다. 새 helper는 keyCode와 modifierFlags를 그대로 받아 `cgAnnotatedSessionEventTap`에 재주입하고, 테스트용 debug hook도 제공한다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`에서는 조합 중 `command/control/option` 입력이 오면 먼저 commit/clearMarkedText를 한 뒤 원래 key event를 `KeyEventReposter`로 재주입하고 `true`를 반환하게 바꿨다. `Shift+Enter`도 같은 helper를 타도록 통일했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`에서도 composing/converting 상태의 `command/control/option`을 같은 방식으로 처리하도록 바꿨다. prediction이 떠 있으면 먼저 닫고 commit한 뒤 원래 단축키를 다시 보내게 했다.
  - 같은 파일의 `candidatePanelState`는 real candidates가 비어 있어도 converting 상태의 preedit가 남아 있으면 joined preedit 문자열 하나를 표시용 후보로 만들어, 후보창이 완전히 nil이 되지 않도록 보강했다. 이 fallback은 표시용일 뿐 invalid Mozc candidate ID를 다시 도입하지 않는다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`, `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`에는 `Shift+Enter`와 `Command-A`가 commit + repost를 함께 요청하는지 확인하는 회귀 테스트를 추가했다.
  - `/Users/nr2bj/Documents/NRIME/project.yml`은 새 shared helper가 양쪽 target에 포함되도록 갱신했고, 마지막으로 `/Users/nr2bj/Documents/NRIME/Tools/install.sh`를 실행해 최신 코드를 설치본에 반영했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/KeyEventReposter.swift`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/Tools/install.sh` (실행만 함, 코드 수정 아님)
- 검증:
  - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `161 tests, 0 failures`
  - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - 결과: 설치 완료, LaunchAgent 재설치 완료, `.en` input source 재선택 완료
- 메모:
  - 이번 증상은 `Shift+Enter`만의 문제가 아니라, 조합 중 modifier shortcut 전반이 "commit은 되는데 원래 key action은 앱에 안 도착하는" 공통 경계 문제로 봤다. 그래서 `Shift+Enter` 전용 helper를 넓혀 generic modified-key repost로 바꿨다.
  - 일본어 후보창 누락은 최근 fake Mozc candidate 제거 이후, real candidate list가 없는 converting 응답에서 panel state가 nil이 되는 경로가 생긴 것으로 판단했다. 그래서 표시용 fallback을 panel state 쪽에만 추가했고, Mozc selection/highlight ID 경로는 그대로 보수적으로 유지했다.

## 2026-03-16 07:58 JST | Codex

- 범위:
  - 조합 중 `Shift+Enter` / `Command-A` command forwarding 방식 전환
  - 일본어 변환 후보창 상태 로그 보강
  - 로컬 설치 반영
- 무엇을 했는지:
  - CGEvent 재주입에 의존하던 조합 중 modifier shortcut 처리를, 앱의 텍스트 시스템 command를 직접 호출하는 방식으로 바꿨다.
  - `Shift+Enter`는 `insertLineBreak:`, `Command-A`는 `selectAll:`로 직접 전달되게 정리했다.
  - 일본어 후보창이 안 뜬다는 런타임 제보를 좁히기 위해, Space 변환 시 Mozc conversion 결과와 panel state를 남기는 로그를 추가했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/Shared/TextInputCommandForwarder.swift`를 추가해, key event를 selector로 매핑한 뒤 Objective-C `doCommandBySelector:`를 호출하도록 만들었다. `Shift+Enter -> insertLineBreak:`, `Command-A -> selectAll:`만 우선 안정 경로로 다룬다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`는 조합 중 `command/control/option`과 `Shift+Enter`에서 먼저 조합을 commit한 뒤, 가능하면 `TextInputCommandForwarder`로 command를 보내고, 매핑되지 않는 경우에만 기존 `KeyEventReposter` fallback을 쓰게 바꿨다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`도 같은 방식으로 바꿨고, `triggerMozcConversion*` 경로마다 `converted`, `candidateCount`, `hasPreedit`, `preeditText`를 남기는 debug log를 추가했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`는 `doCommandBySelector:`를 기록할 수 있게 확장했고, `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`, `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`는 더 이상 repost 자체를 기대하지 않고 selector forwarding을 검증하도록 업데이트했다.
  - `/Users/nr2bj/Documents/NRIME/project.yml`을 갱신하고 `xcodegen generate`, `xcodebuild test`, `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`까지 수행해 실제 설치본에도 반영했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/TextInputCommandForwarder.swift`
  - `/Users/nr2bj/Documents/NRIME/project.yml`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/MockTextInputClient.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`
- 검증:
  - `xcodegen generate --spec /Users/nr2bj/Documents/NRIME/project.yml --project /Users/nr2bj/Documents/NRIME`
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `161 tests, 0 failures`
  - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - 결과: 설치 완료, LaunchAgent 재설치 완료, `.en` input source 재선택 완료
- 메모:
  - 이번 수정은 “키를 다시 쏘면 앱이 알아서 처리하겠지”라는 가정을 버리고, Cocoa 텍스트 시스템이 원래 기대하는 command selector를 직접 보내는 쪽으로 바꾼 것이다.
  - 일본어 후보창은 코드상 panel state가 살아 있어야 하는데도 런타임에서 안 보인다고 해서, 다음 단계에서는 `Developer Mode` 로그에 남는 `JapaneseEngine triggerMozcConversion*` metadata를 기준으로 conversion 자체가 실패하는지, panel state만 빠지는지를 구분하는 게 핵심이다.

## 2026-03-16 08:05 JST | Codex

- 범위:
  - 상세 키 로깅 옵션 추가
  - 컨트롤러/엔진/command forwarding 로그 포인트 보강
  - 로컬 설치 반영
- 무엇을 했는지:
  - 기존 Developer Mode가 lifecycle/복구 위주 로그만 남겨서 `Shift+Enter`, `Command-A`, 일본어 변환 시 어떤 키가 실제로 들어왔는지 보이지 않던 문제를 해결하기 위해, 별도 `Detailed Key Logging` 토글을 추가했다.
  - 이 토글이 켜져 있을 때만 keyCode, modifierFlags, characters, charactersIgnoringModifiers, command selector forwarding, 일본어 panel refresh 경로를 기록하도록 했다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/Settings.swift`와 `/Users/nr2bj/Documents/NRIME/NRIMESettings/SettingsStore.swift`에 `detailedKeyLoggingEnabled`를 추가했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/GeneralTab.swift`의 Developer 섹션에 `Enable Detailed Key Logging` 토글과 민감정보 경고 문구를 추가했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/DeveloperLogger.swift`에 `logKeyEvent(...)`, `logSelector(...)`를 추가해 상세 키 로그를 별도 게이트로 제어하게 했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`는 `handle`, `handleJapaneseConversion`, `handleJapanesePrediction`, `routeEvent.shortcutHandled`, `refreshJapaneseCandidatePanel.show/hide`를 로그에 남기도록 했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`, `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`는 엔진 진입 키 이벤트를 남기도록 했고, `/Users/nr2bj/Documents/NRIME/Shared/TextInputCommandForwarder.swift`는 `insertLineBreak:` / `selectAll:` forwarding selector를 기록하도록 했다.
  - 마지막으로 `xcodebuild test`와 `/Users/nr2bj/Documents/NRIME/Tools/install.sh`를 실행해 실제 설치본에 반영했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/State/Settings.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/SettingsStore.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMESettings/GeneralTab.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/System/DeveloperLogger.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/Shared/TextInputCommandForwarder.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `161 tests, 0 failures`
  - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - 결과: 설치 완료, LaunchAgent 재설치 완료, `.en` input source 재선택 완료
- 메모:
  - Developer Mode만 켜면 기존처럼 비교적 안전한 로컬 진단 로그만 남고, 실제 입력 문자까지 포함한 로그는 `Detailed Key Logging`을 추가로 켰을 때만 남는다.
  - 다음 재현에서는 `Controller handle`, `KoreanEngine handleEvent`, `JapaneseEngine handleEvent`, `TextInputCommandForwarder forward`, `Controller refreshJapaneseCandidatePanel.*`, `JapaneseEngine triggerMozcConversion*` 줄만 보면 `Shift+Enter`/`Command-A`/일본어 후보창 경로를 거의 바로 좁힐 수 있다.

## 2026-03-16 08:15 JST | Codex

- 범위:
  - Korean/Japanese 조합 중 `Shift+Enter` / `Command-A` passthrough 수정
  - 관련 엔진 테스트 갱신
- 무엇을 했는지:
  - `Shift+Enter`, `Command-A` 같은 조합 중 호스트 앱 단축키가 `조합 확정만 되고 원래 동작은 안 되는` 문제를 수정했다.
  - 기존 `doCommandBySelector:` forwarding보다, IME는 조합만 비동기로 확정하고 원래 key event는 앱이 직접 처리하게 넘기는 방식으로 바꿨다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`에 `commitComposingForPassthrough`를 추가해, 조합 문자열을 flush하고 marked text를 즉시 비운 뒤 `DispatchQueue.main.async`로만 commit하게 했다. `command/control/option` 및 `Shift+Enter`는 이 경로를 탄 뒤 `false`를 반환해서 호스트 앱이 원래 shortcut/newline을 처리하게 했다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`에는 composing/converting/live-conversion을 모두 커버하는 `commitForPassthroughShortcut`를 추가했다. 이 함수는 conversion submit fallback까지 포함한 실제 commit 텍스트를 계산하고 marked text를 먼저 비운 뒤 비동기로 insertText 한다. `Shift+Enter`와 `command/control/option` 경로는 이 함수를 쓰고 `false`를 반환하도록 정리했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`, `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`는 더 이상 selector forwarding을 기대하지 않고, `비동기 commit + event passthrough(false)`를 검증하도록 바꿨다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `161 tests, 0 failures`
- 메모:
  - developer log에서는 `TextInputCommandForwarder.forward`가 실제로 호출됐는데도 Codex/Electron에서 `insertLineBreak:` / `selectAll:`가 반영되지 않았다. 그래서 이번엔 host가 원래 키를 직접 처리하도록 설계를 바꿨다.
  - 이 변경은 설치만 하면 적용되고, 로그아웃/로그인은 필요 없다.

## 2026-03-16 08:30 JST | Codex

- 범위:
  - 한글/일본어 조합 중 `Shift+Enter`, `Command-A` 같은 호스트 명령 전달 경로
  - 실제 설치본 반영
- 무엇을 했는지:
  - 최근 `CGEvent` 재주입 방식이 Codex/Electron 계열 앱에서 `Shift+Enter`가 조합 텍스트를 데리고 줄바꿈되거나, `Command-A`가 조합만 확정되고 실제 명령은 수행되지 않는 회귀를 만든 정황이 있어서 해당 경로를 다시 정리했다.
  - `KoreanEngine`과 `JapaneseEngine` 모두 조합/변환 중 단축키를 만나면 marked text를 먼저 같은 range에 동기 commit하고, 그 다음 원래 key event는 호스트 앱이 직접 처리하도록 `false`를 반환하는 방식으로 되돌렸다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`에서 `command/control/option` 및 `Shift+Enter` 경로를 `commitComposingForShortcut`으로 통일하고, 기존 `repost` 경로를 제거했다. commit 시에는 `client.markedRange()`가 살아 있으면 그 range를 replacement range로 우선 사용해 marked text를 같은 위치에서 정리하도록 바꿨다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`에서도 동일하게 `commitForShortcutPassThrough`로 정리했다. composing/live conversion/converting 상태를 각각 동기 commit한 뒤 원래 키는 호스트가 처리하게 했다.
  - 관련 회귀 테스트를 `repost` 기대에서 `host handles original event` 기대값으로 바꿨다.
  - 최신 빌드로 `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`를 실행해 실제 `/Users/nr2bj/Library/Input Methods/NRIME.app` 설치본까지 갱신했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/KoreanEngineTests.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/JapaneseEngineTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `161 tests, 0 failures`
  - `bash /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - 결과: Release 빌드 설치 및 입력 소스 `com.nrime.inputmethod.app.en` 재선택 완료
- 메모:
  - 이번 수정은 `doCommandBySelector:`도, `CGEvent` 재주입도 Codex/Electron 런타임에서 안정적이지 않다는 전제 위에서, “IME는 조합만 확실히 끝내고 원래 명령은 호스트가 직접 처리하게 둔다”는 더 보수적인 방향으로 돌아간 것이다.
  - 아직 일본어 후보창/한자 후보창이 동일하게 안 뜬다는 보고는 남아 있으므로, 다음 단계는 shortcut 회귀가 실제로 사라졌는지 먼저 확인한 뒤 `triggerMozcConversion`과 `hanjaConvert` shortcut 경로를 각각 분리해서 보강하는 쪽이 맞다.
## 2026-03-16 08:39 JST | Codex

- 범위: 조합 중 `Shift+Enter` / `Command-A` passthrough 경로 재구성
- 무엇을 했는지: 한글/일본어 엔진 내부에서 shortcut을 `false`로 넘겨 host가 처리하게 두던 경로를 더 이상 믿지 않고, 컨트롤러가 조합 상태를 먼저 닫은 뒤 원래 키를 synthetic repost로 다시 보내는 구조로 바꿨다.
- 어떻게 수정했는지: `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`에 `handleCompositionShortcutPassthrough`를 추가해 `Shift+Enter`와 `Command-A`를 엔진 라우팅 전에 가로채도록 했다. 한글/일본어 엔진은 `commitForShortcutPassThrough(client:)`를 외부에서 호출 가능하게 열고, marked text를 비운 뒤 Objective-C `unmarkText` selector까지 호출해 호스트 텍스트 시스템에서 조합 종료를 더 명시적으로 처리하게 했다. `/Users/nr2bj/Documents/NRIME/Shared/KeyEventReposter.swift`는 event source를 `.hidSystemState`, post tap을 `.cghidEventTap`으로 바꾸고 딜레이를 20ms로 늘려 실제 하드웨어 입력에 더 가깝게 repost되도록 조정했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`, `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`, `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`, `/Users/nr2bj/Documents/NRIME/Shared/KeyEventReposter.swift`, `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`
- 검증: `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test` (`163 tests, 0 failures`)
- 메모: 이번 수정은 shortcut passthrough만 겨냥했다. 일본어 후보창/한자 후보창 누락은 별도 경로라 아직 여기서 해결했다고 보지 않는다. 실런타임에서 여전히 같은 증상이면, 다음엔 `developer.log`에 `compositionShortcutPassthrough`와 repost 이후 들어오는 실제 key trace를 대조해 host가 synthetic event를 어떻게 소비하는지 확인해야 한다.

## 2026-03-16 09:15 JST | Codex

- 범위:
  - 한글/일본어 조합 중 `Shift+Enter` / `Command-A` shortcut commit 경로
  - 삭제처럼 보이던 passthrough 회귀 보정
- 무엇을 했는지:
  - `Shift+Enter`와 `Command-A`가 조합 중인 글자를 확정하는 대신 지워버리는 것처럼 보이던 경로를 다시 좁혀서 수정했다.
  - 원인은 shortcut용 commit helper가 "marked text를 비울 때 쓴 replacement range"를 "확정 텍스트를 다시 넣을 때도" 그대로 재사용하던 점으로 봤다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`의 `commitForShortcutPassThrough(client:)`에서, marked text는 여전히 `activeReplacementRange(for:)`로 비우되 실제 확정 텍스트는 `replacementRange()` (`NSNotFound`)로 삽입하게 바꿨다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`의 `commitForShortcutPassThrough(client:)`도 같은 방식으로 정리했다.
  - 이렇게 해서 IMK/Electron 계열 호스트가 "조합 범위를 치환"으로 받아들여 텍스트를 지우는 쪽으로 오해할 가능성을 줄였다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Korean/KoreanEngine.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `163 tests, 0 failures`
- 메모:
  - 이 수정은 shortcut passthrough에서 "조합 종료"와 "확정 텍스트 삽입"의 replacement semantics를 분리한 것이다. 모의 클라이언트 테스트만으로는 잘 안 보였지만, 실제 로그 기준으로는 삭제/백스페이스처럼 보이는 런타임 증상과 가장 잘 맞는 지점이었다.
  - 일본어 후보창/한자 후보창 누락은 여전히 별도 경로다. 이번 엔트리는 shortcut commit 삭제 회귀만 다룬다.

## 2026-03-16 09:23 JST | Codex

- 범위:
  - 조합 중 `Shift+Enter` / `Command-A` passthrough 전달 방식
  - 컨트롤러 레벨 shortcut passthrough 테스트 기대값 정리
- 무엇을 했는지:
  - "지워지진 않지만 확정만 되고 원래 shortcut/newline 동작은 사라지는" 상태에 맞춰, synthetic repost 자체를 다시 걷어냈다.
  - 이제 컨트롤러는 조합만 먼저 끝내고, 원래 key event는 host app이 그대로 처리하도록 돌려놓았다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`의 `handleCompositionShortcutPassthrough`에서 `KeyEventReposter.repost(...)` 호출을 제거하고 `false`를 반환하게 바꿨다.
  - 이 변경으로 `Shift+Enter`와 `Command-A`는 조합 중일 때만 "조합 commit 후 host가 원래 event 처리" 경로를 타고, 조합이 없을 때는 기존처럼 원래 앱 동작을 그대로 쓴다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`는 더 이상 repost debug hook을 쓰지 않고, 컨트롤러가 `false`를 반환해 host가 이벤트를 처리하는 계약을 검증하도록 업데이트했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `163 tests, 0 failures`
- 메모:
  - 지금 단계에서는 `CGEvent` synthetic repost보다 host가 원래 key event를 직접 처리하게 두는 쪽이 더 보수적이고 설명 가능하다.
  - 이 변경은 shortcut passthrough만 다룬다. 일본어 후보창/한자 후보창 누락은 여전히 별도 경로로 남아 있다.

## 2026-03-16 09:29 JST | Codex

- 범위:
  - 조합 중 `Shift+Enter` / `Command-A` passthrough의 command 전달 방식
  - `TextInputCommandForwarder`의 Objective-C selector 호출 경로 보정
- 무엇을 했는지:
  - 조합을 확정한 뒤 줄바꿈/전체선택이 이어지지 않던 원인을 다시 좁혀서, command forwarding 자체가 잘못된 방식으로 selector를 넘기고 있던 부분을 수정했다.
  - 컨트롤러는 다시 shortcut passthrough를 직접 consume하고, host client의 `doCommandBySelector:`를 정확한 시그니처로 호출하도록 되돌렸다.
- 어떻게 수정했는지:
  - `/Users/nr2bj/Documents/NRIME/Shared/TextInputCommandForwarder.swift`에서 `perform(..., with:)`로 `SEL`을 넘기던 경로를 제거했다. 대신 Objective-C runtime에서 `doCommandBySelector:` IMP를 꺼내 `@convention(c) (AnyObject, Selector, Selector) -> Void` 시그니처로 직접 호출하게 바꿨다.
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`의 `handleCompositionShortcutPassthrough`는 조합 commit 후 `TextInputCommandForwarder.forward(...)`가 성공하면 `true`를 반환하도록 조정했다.
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`는 다시 controller-level 계약을 `확정 + selector 전달`로 되돌리고, 비동기 dispatch가 끝난 뒤 `insertLineBreak:` / `selectAll:`가 실제로 기록됐는지 확인하도록 업데이트했다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/Shared/TextInputCommandForwarder.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift`
  - `/Users/nr2bj/Documents/NRIME/NRIMETests/NRIMEInputControllerTests.swift`
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `163 tests, 0 failures`
- 메모:
  - 이번 수정은 "host가 원래 key event를 알아서 처리하길 기대"하는 경로가 Codex/Electron에서 안정적이지 않다는 전제 위에서, IMK가 제공하는 `doCommandBySelector:` 경로를 정확한 ABI로 호출하는 쪽으로 되돌린 것이다.
  - 이전 `perform(..., with:)` 방식은 selector 자체를 object 인자로 넘기고 있어서 실제 `SEL` 전달과는 달랐다. 이번엔 그 점을 바로잡았다.
  - 일본어 후보창/한자 후보창 누락은 여전히 별도 경로다. 이번 엔트리는 shortcut passthrough만 다룬다.

## 2026-03-16 09:32 JST | Codex

- 범위:
  - 조합 중 `Shift+Enter` / `Command-A` passthrough 런타임 상태 기록
  - Electron 계열 앱별 실제 동작 편차 메모
- 무엇을 했는지:
  - 이번 주기 마지막 상태를 worklog에 남겼다. 테스트는 통과했지만, 실제 사용자 런타임에서는 `Shift+Enter` / `Command-A`가 여전히 "조합 확정만 하고 원래 명령은 실행되지 않는" 케이스가 남아 있다.
  - 사용자 보고 기준으로 Electron 계열 앱마다 증상이 달랐고, 어떤 앱은 확정만 되고, 어떤 앱은 글자를 지우고 줄바꿈이 되기도 했다.
- 어떻게 수정했는지:
  - 추가 코드 수정 없이, 현재까지 시도한 두 경로를 실패 사례로 정리했다.
  - 실패 경로 1: `KeyEventReposter` 기반 synthetic repost. 일부 런타임에서 원래 key event와 다르게 소비되거나 삭제처럼 보이는 회귀가 있었다.
  - 실패 경로 2: `TextInputCommandForwarder` 기반 `doCommandBySelector:` forwarding. ABI 호출 자체는 바로잡았고 테스트에서도 selector 전달은 검증됐지만, 실제 Electron 계열 앱에서는 여전히 `확정만` 되고 `insertLineBreak:` / `selectAll:`가 기대대로 이어지지 않는 경우가 남았다.
- 수정 파일:
  - `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증:
  - 사용자 수동 확인 결과 기준: 한글/일본어 조합 중 `Shift+Enter`, `Command-A`가 여전히 실제 앱에서 완전히 해결되지 않았다.
  - 최신 자동 테스트 기준은 직전 엔트리와 동일하게 `163 tests, 0 failures`였다.
- 메모:
  - 다음 작업자는 이 문제를 "IME 내부 상태 정리"가 아니라 "IMK -> host command 전달이 앱별로 어떻게 소비되는지" 문제로 보고 다시 접근하는 게 맞다.
  - 특히 Electron 계열은 앱마다 동작이 달라서, 한 가지 passthrough 전략으로 모두 맞추기 어려운 상태다.
  - 후보창(일본어/Mozc, 한자) 누락 문제와 이 shortcut passthrough 문제는 분리해서 봐야 한다.
  - 이번 엔트리는 사용자 요청에 따라 현 상태를 기록하고 작업을 마무리하기 위한 정리다.
