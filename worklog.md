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

## 2026-03-17 03:00 JST | Claude Code (Opus 4.6)

- 범위: Korean/Japanese 엔진 — async closure 안전성 개선
- 무엇을 했는지:
  - Shift+Enter async 클로저에서 `client` (IMKTextInput) 참조 안전성 개선
  - 불필요한 `[self]` 캡처 제거, `replacementRange()` 호출 대신 `NSRange(location: NSNotFound, length: 0)` 직접 전달
  - 코드 감사 수행: CGEvent 권한, race condition, stale client 위험 평가
- 어떻게 수정했는지:
  - `client`를 `let capturedClient = client`로 로컬 변수에 캡처하여 closure에서 명시적 참조
  - `[self]` 제거 — closure 내에서 `self` 참조 불필요 (replacementRange 호출 제거)
  - CGEvent.post(tap: .cghidEventTap) 권한 문제: `.cgAnnotatedSessionEventTap`은 Electron에서 무시됨 (이전 검증), `.cghidEventTap` 유지가 최선. IME는 /Library/Input Methods/ 설치 시 자동 권한 부여
- 수정 파일:
  - `NRIME/Engine/Korean/KoreanEngine.swift` — Shift+Enter async closure 수정
  - `NRIME/Engine/Japanese/JapaneseEngine.swift` — composing/converting Shift+Enter async closure 수정 (2곳)
- 검증: 코드 리뷰 기반 (빌드/테스트는 사용자 환경에서 수행)
- 메모:
  - IMKTextInput은 NSProxy 기반 — stale 참조 시 crash 대신 조용히 무시됨 (IMKit 프레임워크 보호)
  - 10ms 딜레이 내에 input source 전환이 일어날 확률은 극히 낮으나, 방어적 코딩으로 대비
  - 권한 팝업은 개발 중(Xcode 실행) 시에만 발생. PKG 설치 시 자동 허용

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

## 2026-03-23 06:40 JST | Claude Code

- 범위: Shift+Enter/Cmd+A Electron 대응, LaunchAgent 수정, 디버그 제거, 일본어 변환 디버깅
- 무엇을 했는지:
  - 이전 세션에서 Shift+Enter(async insertText("\n") 10ms delay)와 Cmd+A(tagged CGEvent repost) 대응 완료 (Korean/Japanese 양쪽)
  - LaunchAgent plist에 `SuccessfulExit: true` 추가 — launchd가 RestoreHelper를 재시작하지 않도록
  - `detailedKeyLoggingEnabled` 제거 (Settings.swift, SettingsStore.swift, GeneralTab.swift, DeveloperLogger.swift)
  - Bridging Header에서 미사용 PSN 래퍼 제거 시도
  - install.sh, postinstall에 TISDisableInputSource 중복 입력소스 정리 로직 추가
  - ~/Library/Input Methods/ 구버전 제거 (시스템 경로와 중복 방지)
  - 일본어 변환(Mozc) 실패 디버깅: feedHiragana → sendKey nil → createSession nil → Mach IPC 실패 확인
  - MozcClient.ensureSession에서 createSession 실패 시 서버 재시작 후 재시도 로직 추가
- 어떻게 수정했는지:
  - KoreanEngine/JapaneseEngine: Shift+Enter → commitComposing + async insertText("\n") 10ms delay + return true
  - KoreanEngine/JapaneseEngine: Cmd+key → commitAndRepostEvent (CGEvent with repostTag) + return true
  - NRIMEInputController: repostTag 감지 시 return false (패스스루)
  - LaunchAgent: KeepAlive.SuccessfulExit = true 추가
  - MozcClient.ensureSession: createSession 실패 → MozcServerManager.shared.restartServer() → 재시도
- 수정 파일:
  - NRIME/Engine/Korean/KoreanEngine.swift
  - NRIME/Engine/Japanese/JapaneseEngine.swift
  - NRIME/Engine/Japanese/Mozc/MozcClient.swift
  - NRIME/Engine/Japanese/Mozc/MozcConverter.swift
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift
  - NRIME/Controller/NRIMEInputController.swift
  - NRIME/State/Settings.swift
  - NRIME/State/ShortcutHandler.swift
  - NRIME/State/StateManager.swift
  - NRIME/System/TextInputGeometry.swift
  - NRIMESettings/SettingsStore.swift
  - NRIMESettings/GeneralTab.swift
  - Tools/pkg/com.nrime.inputmethod.loginrestore.plist
  - Tools/pkg/postinstall
  - Tools/install.sh
- 검증:
  - 한글 Shift+Enter, Cmd+A: 정상 확인 (사용자 테스트)
  - 일본어 Shift+Enter, Cmd+A: 정상 확인 (사용자 테스트)
  - 10ms delay 안정성 확인 (1ms/5ms 실패, 10ms 안정)
  - 일본어 변환(Mozc): feedOk=false 지속 — createSession Mach IPC nil 반환. 서버 재시작 로직 추가했으나 아직 미해결.
- 메모:
  - Mozc 변환 실패 근본 원인: bootstrap_look_up으로 포트는 찾지만(reachable=true), 실제 mach_msg가 실패. stale port 또는 서버가 IPC 준비 안 된 상태.
  - ensureSession에서 restartServer 후 재시도하도록 수정했으나, 여전히 createSession nil 반환 — 추가 디버깅 필요.
  - ~/Library/Input Methods/와 /Library/Input Methods/ 양쪽 설치 시 중복 입력소스 발생. PKG 설치만 사용 권장.
  - CGEvent.post(tap: .cghidEventTap)는 Accessibility 권한 필요 — IME는 보통 자동 허용되지만 권한 없으면 조용히 실패.
  - 인디케이터 위치 문제: AX API를 최우선으로 올리면 정확하지만 느려짐(1초+). 타임아웃 또는 비동기 처리 필요.

## 2026-03-23 12:00 JST | Claude Code

- 범위: mozc_server IPC 디버깅 (일본어 변환 불가 원인 추적)
- 무엇을 했는지:
  1. mozc_server의 Mach IPC 구조체 분석 — C와 Swift의 struct layout 비교 확인 (size=48, data offset=28 일치)
  2. C 테스트 프로그램으로 직접 OOL IPC 테스트 → 성공 (response 11 bytes)
  3. NRIME 내부에서는 실패 확인: `recv OK size=0` (빈 응답) 또는 `recv failed kr=268451843` (타임아웃)
  4. `launch_msg()` deprecated API → macOS 26.4에서 type 9 반환 → SessionWatchDog 크래시 확인
  5. mozc mach_ipc.cc의 `IsServerRunning`을 bootstrap_look_up 방식으로 패치, mozc_server 재빌드
  6. MozcServerManager에 debugLog 추가 (NSLog가 입력기 프로세스에서 안 보여서 파일 로그로 전환)
  7. mozc_server stderr를 /tmp/nrime-mozc-server.log로 리다이렉트
- 어떻게 수정했는지:
  - /tmp/mozc_build/src/ipc/mach_ipc.cc: `DefaultClientMachPortManager::IsServerRunning` — launch_msg() → bootstrap_look_up
  - MozcServerManager.swift: debugLog 메서드 추가, prepareServerForUse/serverBinaryPath에 파일 로그 추가
  - MozcServerManager.swift: process.standardError를 /tmp/nrime-mozc-server.log로 리다이렉트
- 수정 파일:
  - /tmp/mozc_build/src/ipc/mach_ipc.cc (mozc 소스 패치)
  - NRIME/Resources/mozc_server (재빌드된 바이너리)
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift
- 검증: C 테스트로 OOL IPC 성공 확인, NRIME 내부에서는 여전히 실패 — 추가 디버깅 진행 중
- 메모:
  - 핵심 미스터리: 같은 mozc_server 바이너리에 같은 OOL 메시지를 보내는데 C에서는 성공, NRIME에서는 실패
  - 가능한 원인: 1) NRIME이 서버를 제대로 못 띄움(serverBinaryPath nil?) 2) stale port에 연결 3) 서버 초기화 미완료 시 연결
  - `serverAvail=false`인데 machCall의 bootstrap_look_up은 포트를 찾음 → stale port 가능성 높음
  - postinstall에 mozc lock 파일 정리 추가됨

## 2026-03-24 01:35 JST | Claude Code

- 범위: mozc_server IPC 디버깅 — 일본어 변환 불가 근본 원인 추적 (계속)
- 무엇을 했는지:
  1. MozcServerManager에 debugLog 추가 → Bundle path, binary path 확인 완료
  2. MozcClient의 machCall을 atomic send/recv로 변경 (C 테스트와 동일 패턴)
  3. 여전히 실패 — `machCall: failed kr=268451843` (MACH_RCV_TIMED_OUT)
  
- 시도한 모든 방법과 결과:

  ### 시도 1: launch_msg() 패치 (IsServerRunning)
  - mozc mach_ipc.cc의 `DefaultClientMachPortManager::IsServerRunning` 수정
  - launch_msg() → bootstrap_look_up 방식으로 변경
  - 결과: watchdog 크래시는 해결, 하지만 IPC 자체가 실패

  ### 시도 2: MozcClient machCall — 분리된 send/recv
  - Swift에서 MACH_SEND_MSG와 MACH_RCV_MSG를 별도 호출
  - 결과: `recv OK size=0` (빈 응답) 또는 `recv failed kr=268451843` (타임아웃)

  ### 시도 3: MozcClient machCall — atomic send/recv
  - C 테스트와 동일하게 MACH_SEND_MSG|MACH_RCV_MSG 단일 호출로 변경
  - 결과: 여전히 `failed kr=268451843` 타임아웃

  ### 시도 4: C 테스트 프로그램 직접 IPC
  - /tmp/test_ool.c — OOL Mach message로 createSession 전송
  - 결과: **수동으로 서버 띄웠을 때는 성공** (response 11 bytes), NRIME이 띄운 서버에는 실패

  ### 시도 5: struct layout 비교
  - C와 Swift의 MachIPCSendMessage/MachIPCReceiveMessage 크기/오프셋 비교
  - 결과: 완벽히 일치 (send=48, recv=56, data offset=28)

  ### 시도 6: protobuf 스키마 비교  
  - NRIME의 commands.pb.swift vs mozc 소스의 commands.proto
  - 결과: 동일 (CommandType enum 값 일치)

- 핵심 발견:
  1. **수동 터미널에서 mozc_server 실행 → C 테스트 IPC 성공**
  2. **NRIME(입력기 프로세스)에서 mozc_server 실행 → IPC 실패**
  3. 서버 바이너리 경로 확인됨: `/Library/Input Methods/NRIME.app/Contents/Resources/mozc_server`
  4. 서버가 시작 후 곧 종료 (ps에 프로세스 없음, 서버 로그에 크래시 흔적 없음)
  5. mozc_server stderr 로그: 초기화 에러(history.db, config1.db 없음, sem_open 실패) — 이건 정상 first-run 동작
  6. **NRIME이 띄운 mozc_server의 Mach port를 터미널에서 찾을 수 없음 (lookup failed: 1102)**
     → 입력기 프로세스의 bootstrap namespace가 사용자 세션과 다를 가능성

- 미해결 문제점:
  1. **Bootstrap namespace 차이**: IMKit 입력기 프로세스에서 fork된 서버가 사용자 세션의 bootstrap namespace와 분리되어 있을 수 있음. 터미널에서 띄운 서버는 사용자 세션에 등록되어 C 테스트가 성공하지만, NRIME에서 띄운 서버는 입력기의 namespace에 등록되어 다른 프로세스에서 접근 불가.
  2. **서버 무음 종료**: 서버가 크래시 로그 없이 사라짐. watchdog가 여전히 문제일 수 있음 (patched IsServerRunning이 입력기 namespace에서 잘 동작하는지 미확인)
  3. **recv OK size=0 패턴**: 일부 시도에서 서버가 빈 응답을 반환 — 서버가 요청을 받았으나 처리 실패(초기화 미완료?)

- 수정 파일:
  - NRIME/Engine/Japanese/Mozc/MozcClient.swift (machCall atomic send/recv)
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift (debugLog 추가, stderr 리다이렉트)
  - /tmp/mozc_build/src/ipc/mach_ipc.cc (IsServerRunning 패치)
  - NRIME/Resources/mozc_server (재빌드 바이너리)

- 검증: 모든 시도 실패. C 프로그램 수동 테스트만 성공.

- 다음 에이전트를 위한 제안:
  1. **LaunchAgent로 서버 시작**: NRIME 프로세스가 아닌 LaunchAgent(사용자 세션)에서 mozc_server를 시작하면 bootstrap namespace 문제를 우회할 수 있음
  2. **Unix domain socket IPC**: Mach port 대신 Unix socket 사용 — namespace 문제 없음
  3. **원본 mozc_server 바이너리 복원**: .gitignore에 있어서 git에 없음. 이전 PKG나 백업에서 복구 가능한지 확인
  4. **macOS 26.4 변경점 조사**: launch_msg() 외에 Mach port 관련 변경이 있었는지 Apple 릴리스 노트 확인
  5. **서버 종료 원인 추적**: MozcServerManager의 terminationHandler에 exit status와 signal 번호 로깅 추가. `process.terminationReason`도 확인
  6. **입력기 namespace에서의 bootstrap_check_in 확인**: 서버가 포트 등록에 성공하는지 서버 측 로그 추가 필요

## 2026-03-24 01:45 JST | Codex

- 범위: 일본어 변환 후보창 미표시 문제의 1차 복구. Mozc 서버 기동 경로와 후보창 fallback 표시 경로를 같이 정리.
- 무엇을 했는지:
  - 일본어 후보창이 안 뜨는 직접 원인을 다시 추적한 결과, 후보창 UI보다 `mozc_server` 세션 생성/가시성 문제가 더 크다고 판단했다.
  - `MozcServerManager`에 사용자 세션 LaunchAgent 기반 기동 경로를 추가해서, IMK 프로세스 child process로 직접 띄우지 못할 때 `launchctl bootstrap/kickstart`로 사용자 GUI 세션에서 mozc_server를 띄우도록 보강했다.
  - 동시에 일본어 변환이 preedit만 있고 `currentCandidateStrings`가 비어 있는 경우에도 후보창이 완전히 숨지지 않도록 `candidateDisplayStrings` fallback을 추가했다.
  - install/pkg/uninstall 스크립트에도 `com.nrime.inputmethod.mozcserver` LaunchAgent 설치/정리 경로를 추가해 배포 경로와 런타임 경로가 맞도록 정리했다.
- 어떻게 수정했는지:
  - `MozcServerManager.swift`
    - `launchServerViaLaunchAgent()`를 추가해 `~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist` 또는 `/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist`가 있으면 `launchctl bootstrap` 후 `kickstart -k`를 시도하도록 했다.
    - 기존 direct child-process launch는 fallback으로 남겨 두고, `restartServer()`/`prepareServerForUse()`/`killStaleServers()`/`shutdownServer()`가 LaunchAgent 경로도 같이 정리하도록 바꿨다.
  - `JapaneseEngine.swift`
    - `candidateDisplayStrings`를 추가해서 `currentCandidateStrings`가 없더라도 `currentPreedit`가 있으면 표시용 후보 1개를 만들게 했다.
    - `showCandidateWindow()`가 이 fallback을 사용하고, 빈 경우에는 숨기도록 바꿨다.
  - `NRIMEInputController.swift`
    - prediction/number-key/highlight/일반 갱신 경로가 더 이상 raw `currentCandidateStrings`만 보지 않고 `japaneseEngine.candidateDisplayStrings`를 사용하게 정리했다.
  - 스크립트/패키징
    - `Tools/install.sh`에 사용자용 `com.nrime.inputmethod.mozcserver.plist` 생성/bootout/bootstrap 추가.
    - `Tools/pkg/com.nrime.inputmethod.mozcserver.plist` 추가.
    - `Tools/build_pkg.sh`, `Tools/pkg/postinstall`, `Tools/uninstall.sh`에 새 LaunchAgent 반영.
- 수정 파일:
  - /Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcServerManager.swift
  - /Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/JapaneseEngine.swift
  - /Users/nr2bj/Documents/NRIME/NRIME/Controller/NRIMEInputController.swift
  - /Users/nr2bj/Documents/NRIME/Tools/install.sh
  - /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh
  - /Users/nr2bj/Documents/NRIME/Tools/pkg/postinstall
  - /Users/nr2bj/Documents/NRIME/Tools/uninstall.sh
  - /Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.mozcserver.plist
- 검증:
  - `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test`
  - 결과: `158 tests, 0 failures`
  - `bash -n /Users/nr2bj/Documents/NRIME/Tools/install.sh`
  - `bash -n /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`
  - `bash -n /Users/nr2bj/Documents/NRIME/Tools/pkg/postinstall`
  - `bash -n /Users/nr2bj/Documents/NRIME/Tools/uninstall.sh`
  - `plutil -lint /Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.mozcserver.plist`
- 메모:
  - 이번 수정은 아직 로컬 코드 단계다. 실제 효과를 보려면 새 LaunchAgent가 설치되어야 하므로 `Tools/install.sh` 재실행 또는 PKG 재설치가 필요하다.
  - `/tmp`에서 수동으로 `mozc_server`를 띄워 본 로그는 `ProcessMutex open() failed`와 Abseil deadlock 경고가 있었는데, 이 셸 샌드박스의 파일 쓰기 제한 영향도 섞여 있을 수 있다. 그래서 이번에는 그 수동 child-process 경로를 근본 원인으로 단정하지 않고, 실제 사용자 세션 LaunchAgent 경로를 우선 추가했다.
  - 여전히 남는 리스크는 `launchctl`로 뜬 mozc_server가 실제로 `org.mozc.inputmethod.Japanese.Converter.session`을 사용자 GUI bootstrap namespace에 등록하는지 런타임에서 재확인해야 한다는 점이다. 그래도 기존 child-process 경로보다 namespace mismatch를 피할 가능성이 높다.
## 2026-03-24 01:50 JST | Codex

- 범위: PKG 빌드 및 시스템 경로 설치 시도
- 무엇을 했는지: 최신 코드 기준으로 배포용 PKG를 다시 빌드했고, `/Library/Input Methods` 기준 설치를 진행했다.
- 어떻게 수정했는지: `Tools/build_pkg.sh`를 실행해 `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`를 생성했다. 이후 `installer`는 루트 권한이 필요해 실패했고, GUI 관리자 인증이 가능한 `osascript ... with administrator privileges` 경로로 설치를 재시도했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh` 성공, 산출물 `NRIME-1.0.6.pkg` 생성 확인
- 메모: 시스템 PKG 설치는 관리자 인증이 필요하다. 현재 세션에서는 AppleScript 관리자 인증 창 승인 여부에 따라 설치가 완료된다. 설치 기준은 `pkg`만 사용하고 `install.sh` 경로와 혼용하지 않는다.
## 2026-03-24 01:53 JST | Codex

- 범위: PKG 설치 반영 여부 및 Mozc 런타임 상태 확인
- 무엇을 했는지: 시스템 설치본이 실제로 최신 버전인지 확인했고, 일본어 후보창 미표시 문제의 런타임 원인을 `LaunchAgent` 상태와 서버 로그로 좁혔다.
- 어떻게 수정했는지: `/Library/Input Methods/NRIME.app` 버전과 설치 시각, `/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist` 존재 여부, `launchctl print gui/$(id -u)/com.nrime.inputmethod.mozcserver`, `/tmp/nrime-mozc-server.log`를 확인했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: 설치본 버전 `1.0.6 (7)` 확인, `com.nrime.inputmethod.pkg` 설치 확인, `com.nrime.inputmethod.mozcserver`가 `Segmentation fault: 11`로 죽고 `state = not running`인 것 확인
- 메모: 현재 문제는 설치 누락이 아니라 Mozc 서버 런타임 크래시다. 후보창 미표시는 패널 표시 로직보다 서버 프로세스가 유지되지 못하는 쪽이 우선 원인이다.
## 2026-03-24 01:59 JST | Codex

- 범위: Mozc LaunchAgent 안정화 및 PKG 재빌드
- 무엇을 했는지: `mozc_server`가 설치 누락이 아니라 LaunchAgent 실행 정책 문제로 불안정했던 것을 확인하고, foreground 실행/자동 기동/자동 재시작 기준으로 LaunchAgent 정의를 보강했다. 현재 세션에서도 사용자 LaunchAgent를 통해 새 정책을 바로 적용했다.
- 어떻게 수정했는지: `Tools/pkg/com.nrime.inputmethod.mozcserver.plist`와 `Tools/install.sh`의 Mozc LaunchAgent에 `--nodetach`, `RunAtLoad`, `KeepAlive`를 추가했다. `Tools/pkg/postinstall`에는 `~/Library/Application Support/Mozc` 생성과 `launchctl kickstart`를 더해 설치 직후 서버가 즉시 뜨도록 했다. 이후 `~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist`를 같은 정책으로 작성해 현재 로그인 세션에 bootstrap/kickstart했고, `launchctl print`에서 `state = running`, `arguments = ... --nodetach`, `dynamic endpoints = org.mozc.inputmethod.Japanese.Converter.session`를 확인했다. 마지막으로 `Tools/build_pkg.sh`로 PKG를 다시 빌드했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.mozcserver.plist`, `/Users/nr2bj/Documents/NRIME/Tools/install.sh`, `/Users/nr2bj/Documents/NRIME/Tools/pkg/postinstall`, `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `plutil -lint /Users/nr2bj/Documents/NRIME/Tools/pkg/com.nrime.inputmethod.mozcserver.plist`, `bash -n /Users/nr2bj/Documents/NRIME/Tools/install.sh`, `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh`, `launchctl print gui/$(id -u)/com.nrime.inputmethod.mozcserver`, `ps ... mozc_server`
- 메모: 현재 세션은 시스템 LaunchAgent 대신 사용자 LaunchAgent(`~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist`)가 우선 적용된 상태다. 시스템 설치본에도 같은 정책이 들어간 PKG는 이미 재빌드됐지만, `/Library/LaunchAgents` 쪽 반영은 PKG 재설치 후에 일치한다.
## 2026-03-24 02:13 JST | Codex

- 범위: 일본어 변환 후보 미표시 원인 추적, MozcClient IPC 수정, PKG 재설치
- 무엇을 했는지: `mozc_server`가 살아 있어도 일본어 변환 후보가 뜨지 않는 원인을 추가 추적했고, 실제 원인이 `MozcClient.createSession()` 실패라는 것을 `/tmp/nrime-debug.log`로 확인했다. 이후 `MozcClient`의 Mach IPC 구현을 upstream Mozc macOS 클라이언트 방식에 맞춰 `send -> receive` 분리 흐름으로 수정했고, 테스트 통과 후 PKG를 재빌드/재설치했다.
- 어떻게 수정했는지: `MozcClient.machCall`의 기존 combined `MACH_SEND_MSG | MACH_RCV_MSG` 경로를 걷어내고, Mozc 원본 `src/ipc/mach_ipc.cc` 흐름처럼 요청 송신 후 reply port에서 최대 2회 응답 수신하는 구조로 바꿨다. 그 뒤 `xcodebuild test`로 전체 테스트를 돌렸고, `Tools/build_pkg.sh`로 `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`를 다시 생성했다. 마지막으로 관리자 인증 설치를 통해 시스템 PKG를 업그레이드했고, `/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist`가 `--nodetach`, `RunAtLoad`, `KeepAlive`를 포함한 상태로 반영된 것을 확인했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`, `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test` -> `158 tests, 0 failures`, `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh` 성공, `installer -pkg /tmp/NRIME-1.0.6.pkg -target /` 성공, `plutil -p /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist`, `launchctl print gui/$(id -u)/com.nrime.inputmethod.mozcserver`
- 메모: 시스템 설치는 새 PKG로 올라갔고, 현재 세션에서는 사용자 LaunchAgent(`~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist`)가 우선 적용된 상태다. 핵심 런타임 가정은 이제 `mozc_server` 생존 문제가 아니라, 수정된 `MozcClient` IPC 경로가 실제 일본어 변환 요청을 정상 응답으로 받는지다. 후보창이 여전히 안 뜨면 다음은 `triggerMozcConversion -> updateFromOutput -> panel.show` 사이의 최신 런타임 로그를 다시 확인해야 한다.

## 2026-03-24 02:22 JST | Codex

- 범위: 일본어 Mozc IPC 세션 생성 경로 안정화, 시스템 PKG 재빌드/재설치
- 무엇을 했는지: 일본어 후보창이 뜨지 않는 문제를 패널 UI가 아니라 `MozcClient.createSession()` 응답 타임아웃으로 다시 좁혔고, 세션 생성/초기 설정만 더 긴 timeout을 쓰도록 바꿨다. 이후 Release 기준 PKG를 다시 빌드하고 시스템 설치본(`/Library/Input Methods`)에 업그레이드 설치했다.
- 어떻게 수정했는지: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`에서 단일 `250ms` timeout을 없애고 일반 RPC용 `750ms`, 세션 생성/`SET_REQUEST`용 `5000ms` timeout을 분리했다. `call(_:)`가 `Input.CommandType`에 따라 timeout을 고르도록 바꾸고, debug log에도 실제 사용 timeout을 남기게 했다. 설치는 `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`를 빌드한 뒤 `/tmp/NRIME-1.0.6.pkg`로 복사해 `installer -pkg ... -target /`로 시스템 업그레이드했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test` -> `158 tests, 0 failures`; `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh` 성공; `installer -pkg /tmp/NRIME-1.0.6.pkg -target /` -> `The upgrade was successful.`; `/Library/Input Methods/NRIME.app` 버전 `1.0.6 (7)` 확인; `launchctl print gui/$(id -u)/com.nrime.inputmethod.mozcserver`에서 사용자 LaunchAgent 경로로 `state = running`, endpoint 활성화 확인.
- 메모: 아직 일본어 후보창이 실제로 복구됐는지는 사용자 런타임 확인이 필요하다. 현재 남은 핵심 가설은 `createSession` 응답이 늦게 오는데 기존 timeout이 너무 짧아 self-restart loop를 만든 것이었고, 이번 수정은 그 가설을 직접 겨냥한다. 현재 세션은 사용자 LaunchAgent(`/Users/nr2bj/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist`)가 활성 경로다.

## 2026-03-24 02:28 JST | Codex

- 범위: 일본어 Mozc Mach IPC 요청 버퍼 안정화, 최신 시스템 PKG 재설치
- 무엇을 했는지: `createSession`이 여전히 응답을 못 받는 상황을 Swift `Data` 기반 OOL Mach 버퍼 수명 문제까지 의심하고, 요청 데이터를 VM-backed 메모리로 보내도록 `MozcClient`를 보강했다. 그 뒤 최신 `1.0.6` PKG를 다시 시스템 설치본에 업그레이드 설치하고, `mozc_server`를 kickstart해서 최신 바이너리/LaunchAgent 상태를 현재 세션에 반영했다.
- 어떻게 수정했는지: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`의 `machCall(request:timeout:)`에서 `Data.withUnsafeBytes` 포인터를 직접 OOL descriptor에 넘기던 경로를 걷어내고, `vm_allocate`로 확보한 Mach VM 영역에 요청 바이트를 복사한 뒤 그 주소를 `mach_msg_ool_descriptor_t.address`로 쓰도록 바꿨다. 요청 송수신 후에는 `vm_deallocate`로 해제되게 정리했다. 이후 `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`를 다시 빌드하고 `/tmp/NRIME-1.0.6.pkg`로 복사해 관리자 인증 설치로 시스템 업그레이드했다. 설치 직후 `launchctl kickstart -k gui/$(id -u)/com.nrime.inputmethod.mozcserver`를 실행했고, 현재 로그인 세션의 사용자 LaunchAgent가 최신 시스템 설치본의 `mozc_server --nodetach`를 가리키며 `state = running`, dynamic endpoint 활성 상태인 것을 다시 확인했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`, `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test` -> `158 tests, 0 failures`; `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh` 성공; `osascript -e 'do shell script "installer -pkg /tmp/NRIME-1.0.6.pkg -target /" with administrator privileges'` -> `The upgrade was successful.`; `launchctl print gui/$(id -u)/com.nrime.inputmethod.mozcserver`에서 `state = running`, `program = /Library/Input Methods/NRIME.app/Contents/Resources/mozc_server`, endpoint 활성화 확인.
- 메모: 현재까지는 `mozc_server` 생존 자체는 안정화됐고, 남은 핵심 가설은 최신 설치본에서도 `createSession` 응답이 계속 타임아웃되는지 여부다. 사용자가 다시 재현했는데도 후보창이 안 뜨면, 다음 단계는 새 `/tmp/nrime-debug.log`에서 `createSession`/`SET_REQUEST`가 여전히 `MACH_RCV_TIMED_OUT`인지 확인하고, 그렇다면 Swift Mach 메시지 right/descriptor 구성을 upstream C 구현과 더 직접적으로 맞추는 쪽으로 가야 한다.

## 2026-03-24 02:32 JST | Codex

- 범위: 일본어 입력 시 NRIME 재시작 원인 추적, MozcServerManager 재진입 크래시 수정, PKG 재빌드/설치
- 무엇을 했는지: 사용자가 “몇 번 입력 시도하면 NRIME가 재시작되는 것 같다”라고 보고한 현상을 크래시 리포트와 런타임 로그로 확인했고, 실제로 `NRIME.app`이 일본어 변환 경로에서 `MozcServerManager`의 serial queue 재진입 때문에 `dispatch_sync called on queue already owned by current thread`로 죽고 있음을 확인했다. 이를 막기 위해 launch queue 재진입 시에는 같은 큐에 다시 `sync`하지 않도록 가드를 넣었고, 최신 PKG를 다시 빌드해 시스템 설치본에 반영했다.
- 어떻게 수정했는지: `~/Library/Logs/DiagnosticReports/NRIME-2026-03-24-023015.ips`를 확인해 `EXC_BREAKPOINT`와 `BUG IN CLIENT OF LIBDISPATCH`가 `MozcServerManager.prepareServerForUse()` / `ensureServerRunning()` 경로에서 발생하는 것을 확인했다. 이후 `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcServerManager.swift`에 `DispatchSpecificKey`를 추가하고, `launchQueue.sync`를 직접 호출하던 경로를 `withLaunchQueue(_:)` helper로 감싸서 이미 `com.nrime.mozc.launch` 큐 위에 있을 때는 작업을 inline으로 실행하고 그렇지 않을 때만 `sync`하도록 바꿨다. 그 뒤 전체 테스트를 다시 돌렸고, `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`를 새로 생성해 `/tmp/NRIME-1.0.6.pkg` 경유 관리자 인증 설치로 시스템 업그레이드했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcServerManager.swift`, `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test` -> `158 tests, 0 failures`; `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh` 성공; `~/Library/Logs/DiagnosticReports/NRIME-2026-03-24-023015.ips`에서 원인 확인
- 메모: 이번 수정은 “일본어 입력 시 NRIME가 재시작되는” 루프를 만드는 입력기 본체 크래시를 직접 겨냥한다. 다만 일본어 후보 미표시의 근본 원인이 이것 하나뿐이라는 뜻은 아니고, 별개로 `mozc_server`가 `createSession` 응답을 빈 응답/타임아웃으로 돌리는 문제가 남아 있다. 즉 현재는 먼저 `NRIME.app` 크래시를 줄이는 단계이고, 그 다음 진짜 남는 문제는 `MozcClient` <-> `mozc_server` Mach IPC 호환성이다.

## 2026-03-24 02:36 JST | Codex

- 범위: `mozc_server` 요청 파싱 세그폴트 원인 축소, MozcClient OOL copy 정책 변경, 시스템 PKG 재설치
- 무엇을 했는지: 최신 크래시 리포트를 다시 확인해 `mozc_server`가 여전히 `SessionServer::Process -> ParseFromString` 경로에서 요청 바이트를 읽다가 `EXC_BAD_ACCESS`로 죽고 있음을 확인했다. 구조체 크기/레이아웃은 Swift와 upstream C가 같다는 것도 검증했고, 남은 유력 원인을 sender-owned OOL 버퍼의 수명/공유 방식으로 좁혔다. 그래서 작은 요청 payload는 `VIRTUAL_COPY` 대신 `PHYSICAL_COPY`로 보내도록 바꿨고, 최신 PKG를 다시 시스템 설치본에 업그레이드 설치했다.
- 어떻게 수정했는지: `~/Library/Logs/DiagnosticReports/mozc_server-2026-03-24-023358.ips`를 확인해 faulting thread가 `google::protobuf::MessageLite::ParseFromString` / `mozc::SessionServer::Process`에서 invalid address를 읽다 죽는 것을 확인했다. 동시에 `/tmp/mozc/src/ipc/mach_ipc.cc`와 Swift 구현의 구조체 크기를 비교해 `mach_msg_header_t`, `mach_msg_ool_descriptor_t`, send/receive message 크기가 모두 `24/16/48/56`으로 일치함을 검증했다. 그 뒤 `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`에서 `sendMessage.data.copy`를 `MACH_MSG_VIRTUAL_COPY`에서 `MACH_MSG_PHYSICAL_COPY`로 바꿔, tiny request(`CREATE_SESSION`는 2바이트)가 client timeout/재시작 후 sender-owned 메모리를 참조하지 않도록 했다. 마지막으로 `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`를 다시 빌드하고 `/tmp/NRIME-1.0.6.pkg` 경유 관리자 인증 설치로 시스템 업그레이드했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`, `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test` -> `158 tests, 0 failures`; Swift/C 크기 검증(`mach_msg_ool_descriptor_t`, send/receive struct) 일치 확인; `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh` 성공; `osascript -e 'do shell script "installer -pkg /tmp/NRIME-1.0.6.pkg -target /" with administrator privileges'` -> `The upgrade was successful.`
- 메모: 현재까지 정리된 사실은 두 갈래다. 첫째, `NRIME.app` 자체 재시작은 `MozcServerManager` 재진입 크래시였고 이번 턴에 직접 수정했다. 둘째, 일본어 후보 미표시는 여전히 `mozc_server`가 요청 파싱 중 죽거나 빈 응답/타임아웃을 만드는 문제가 핵심이다. 이번 `PHYSICAL_COPY` 변경은 그 후자에 대한 가장 직접적인 안전성 패치다. 만약 이후에도 `mozc_server`가 같은 크래시를 낸다면, 다음 단계는 OOL 자체를 더 버리고 C/ObjC shim으로 upstream `mach_ipc.cc`를 거의 그대로 붙이는 쪽이 가장 확실하다.

## 2026-03-24 02:42 JST | Codex

- 범위: 일본어 입력 지연 완화용 Mozc 재시도 backoff, 시스템 PKG 재설치
- 무엇을 했는지: 사용자가 “일본어 입력이 한 글자에 2초씩 걸릴 정도로 느리다”라고 보고한 현상을 최신 `/tmp/nrime-debug.log`로 확인했고, `createSession` 실패 때마다 `MozcClient.ensureSession()`이 즉시 `restartServer()`를 다시 돌면서 키 입력 스레드를 반복적으로 막고 있음을 확인했다. 그래서 일본어 후보 자체가 아직 안 뜨더라도, 실패 상태에서 매 키마다 5초 timeout + 서버 재시작을 반복하지 않도록 backoff/cooldown을 추가해 체감 지연을 먼저 줄였다. 이후 최신 PKG를 다시 빌드하고 시스템 설치본에 업그레이드 설치했다.
- 어떻게 수정했는지: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`에 `sessionRetryNotBefore`, `lastServerRestartAt`, `sessionFailureCooldown(2초)`, `serverRestartCooldown(5초)`를 추가했다. `ensureSession()`는 이제 최근 실패 직후 backoff 기간에는 즉시 `false`를 반환하고, 서버 재시작도 cooldown 안에서는 생략한다. `createSession()`이 다시 성공하면 backoff 상태를 해제하도록 했다. 이 변경은 일본어 변환 실패 상태에서 입력이 매번 `launchctl kill/bootstrap/kickstart`까지 가는 루프를 줄이는 데 목적이 있다. 이후 `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`를 다시 빌드하고 `/tmp/NRIME-1.0.6.pkg` 경유 관리자 인증 설치로 시스템 업그레이드했다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`, `/Users/nr2bj/Documents/NRIME/build/NRIME-1.0.6.pkg`, `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: `xcodebuild -project /Users/nr2bj/Documents/NRIME/NRIME.xcodeproj -scheme NRIME -destination 'platform=macOS' test` -> `158 tests, 0 failures`; `bash /Users/nr2bj/Documents/NRIME/Tools/build_pkg.sh` 성공; `osascript -e 'do shell script "installer -pkg /tmp/NRIME-1.0.6.pkg -target /" with administrator privileges'` 설치 진행
- 메모: 이 수정은 일본어 후보 미표시의 근본 원인을 해결한 건 아니고, 실패 상태에서 전체 입력기가 “미친 듯이 느려지는” 현상을 완화하기 위한 방어막이다. 최신 로그상 핵심 병목은 여전히 `createSession`의 `MACH_RCV_TIMED_OUT`/빈 응답과 그 뒤의 동기 재시작 루프다. 다음 근본 수정은 Swift Mach IPC를 더 만지는 것보다, upstream Mozc `mach_ipc.cc`를 C/ObjC shim으로 직접 붙여 request/response 경로를 동일하게 맞추는 쪽이 가장 가능성이 높다.

## 2026-03-24 02:54 JST | Codex

- 범위: 일본어 Mozc 연동 문제 재정리, 향후 개선 방향 메모
- 무엇을 했는지: 현재 일본어 후보 미표시/간헐적 극심한 입력 지연 문제를 다시 정리했고, 문제의 중심이 입력기 전체 Swift 구조가 아니라 `Mozc` 연동부에 있다는 판단과 그에 따른 개선 방향을 문서로 남겼다. 다른 에이전트가 이어받을 때 “무엇을 유지하고 무엇을 갈아엎을지”를 빠르게 판단할 수 있도록, 현재까지의 관찰과 권장 전략을 정리했다.
- 어떻게 수정했는지: 런타임 증거 기준으로 다음을 명시했다. `NRIME` 전체가 불안정한 것처럼 보이지만, 현재 가장 큰 문제는 `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcClient.swift`와 `/Users/nr2bj/Documents/NRIME/NRIME/Engine/Japanese/Mozc/MozcServerManager.swift` 주변에 집중되어 있다. 한글 조합/한자 후보/기본 모드 전환/대부분의 UI는 상대적으로 정상 범주에 있고, 일본어 후보 미표시와 지연은 `createSession` 타임아웃, 빈 응답, `mozc_server` 파싱 실패/세그폴트가 핵심이다. 따라서 개선 방향은 “입력기 전체를 C로 옮기는 것”이 아니라 “입력기 전체 Swift 유지 + Mozc IPC만 C/ObjC++ shim으로 분리”가 적절하다고 정리했다. 구체적으로는 upstream Mozc의 `src/ipc/mach_ipc.cc`를 거의 그대로 감싼 얇은 브리지를 두고, Swift `JapaneseEngine`은 그 브리지만 호출하도록 축소하는 방식을 추천한다. 현재 Swift `MozcClient`는 장기적으로 실험 브랜치나 별도 구현으로 유지할 수 있지만, 본선 안정화 경로에서는 우선순위를 낮추는 쪽이 맞다고 적었다.
- 수정 파일: `/Users/nr2bj/Documents/NRIME/worklog.md`
- 검증: 최신 런타임 로그(`/tmp/nrime-debug.log`, `/tmp/nrime-mozc-server.log`)와 크래시 리포트(`~/Library/Logs/DiagnosticReports/NRIME-2026-03-24-023015.ips`, `~/Library/Logs/DiagnosticReports/mozc_server-2026-03-24-023358.ips`)를 근거로 판단 정리
- 메모: 다른 에이전트와 상의할 때 핵심 질문은 세 가지다. 1) Swift `MozcClient`를 계속 보강할지, 2) upstream `mach_ipc.cc` 기반 shim으로 조기 전환할지, 3) 전환 전까지는 일본어 실패 시 입력기 전체 지연을 더 줄이기 위한 임시 완충책을 얼마나 둘지. 현재 Codex 판단은 2번이 가장 가능성이 높다.

## 2026-03-24 03:00 JST | Claude Code

- 범위: Mozc IPC를 C shim으로 교체 — upstream mach_ipc.cc와 동일한 C 구현
- 무엇을 했는지:
  1. `nrime_mozc_ipc.c` / `nrime_mozc_ipc.h` 생성 — upstream mozc `mach_ipc.cc`와 동일한 struct/flow를 순수 C로 구현
  2. MozcClient.swift의 `machCall` 메서드를 C shim (`nrime_mozc_call`) 호출로 교체
  3. NRIME-Bridging-Header.h에 `nrime_mozc_ipc.h` include 추가
  4. Swift의 MachIPCSendMessage/MachIPCReceiveMessage struct 제거 (더 이상 불필요)
- 어떻게 수정했는지:
  - C 구현이 upstream과 동일한 점: memset으로 struct 초기화, MACH_MSG_VIRTUAL_COPY, 분리된 send/recv, 2회 retry, vm_deallocate로 OOL 메모리 해제
  - Swift machCall은 이제 `request.withUnsafeBytes`로 포인터만 넘기고, C 함수가 malloc한 response를 Data로 복사 후 free
- 근거:
  - C 테스트 프로그램은 같은 mozc_server에 성공적으로 IPC 가능
  - Swift Mach IPC는 동일한 struct layout임에도 empty response/timeout 반복
  - C shim은 Swift-Mach IPC의 모든 미묘한 차이(bitfield 패킹, 포인터 수명, withUnsafeMutablePointer 등)를 제거
- 수정 파일:
  - NRIME/Engine/Japanese/Mozc/nrime_mozc_ipc.c (신규)
  - NRIME/Engine/Japanese/Mozc/nrime_mozc_ipc.h (신규)
  - NRIME/Engine/Japanese/Mozc/MozcClient.swift (machCall → C shim 호출)
  - NRIME/NRIME-Bridging-Header.h (include 추가)
- 검증: xcodegen generate + xcodebuild Release 빌드 성공
- 메모: 이 변경이 일본어 변환의 근본 해결이 될 가능성이 가장 높음. C 테스트가 성공했던 것과 동일한 코드 경로를 NRIME 내부에서 사용하므로.

## 2026-03-24 03:10 JST | Claude Code

- 범위: C shim 적용 후 커밋/푸시/PKG 릴리즈 + 해결 정리
- 무엇을 했는지:
  1. PKG 빌드: `NRIME-1.0.6.pkg` (27MB)
  2. 커밋: `66f38f5` — 19 files changed, 591 insertions(+), 174 deletions(-)
  3. 푸시: `83986bd..66f38f5 main -> main`
  4. GitHub 릴리즈 v1.0.6에 PKG 업로드
- 수정 파일: (커밋에 포함된 전체 목록)
  - NRIME/Engine/Japanese/Mozc/nrime_mozc_ipc.c (신규 — C Mach IPC shim)
  - NRIME/Engine/Japanese/Mozc/nrime_mozc_ipc.h (신규)
  - NRIME/Engine/Japanese/Mozc/MozcClient.swift (machCall → C shim)
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift (LaunchAgent, 재진입 수정, debugLog)
  - NRIME/Engine/Japanese/Mozc/MozcConverter.swift
  - NRIME/Engine/Japanese/JapaneseEngine.swift
  - NRIME/Controller/NRIMEInputController.swift
  - NRIME/Engine/Korean/KoreanEngine.swift
  - NRIME/NRIME-Bridging-Header.h
  - NRIME/State/Settings.swift, ShortcutHandler.swift, StateManager.swift
  - NRIME/System/TextInputGeometry.swift
  - NRIMESettings/SettingsStore.swift
  - Tools/build_pkg.sh, install.sh, pkg/postinstall, uninstall.sh
  - Tools/pkg/com.nrime.inputmethod.mozcserver.plist (신규)
- 검증: 일본어 にほんご → Tab → 후보 6개 정상 표시, `machCall: OK size=962` 등 성공 로그 확인
- 메모:
  - **근본 원인 확정**: Swift의 Mach OOL IPC가 동일한 struct layout임에도 empty response를 반환. C 구현으로 교체하자 즉시 해결.
  - **왜 Swift IPC가 실패했는가**: 정확한 원인은 미확정이나, `mach_msg_ool_descriptor_t`의 bitfield 패킹, `withUnsafeMutablePointer` 수명 관리, 또는 Swift runtime의 Mach message 처리 미묘한 차이 중 하나로 추정.
  - **향후 과제**: Swift-only Mach IPC를 별도 프로젝트에서 완성시키는 것은 나중에 진행 예정.

## 2026-03-24 00:00 JST | Claude Code

- 범위: Mozc IPC 및 엔진 전반의 ad-hoc 디버그 로깅 제거
- 무엇을 했는지: `/tmp/nrime-debug.log`에 기록하는 모든 ad-hoc 디버그 로깅을 제거함. `debugLog()` 헬퍼 메서드 3개 삭제, inline FileHandle 디버그 쓰기 블록 전부 삭제, 미사용 `mozcRunning` 더미 변수 삭제.
- 어떻게 수정했는지:
  - MozcClient.swift: `debugLog(_:)` 메서드 및 모든 호출 제거, `call()` 내 hex dump 제거
  - MozcServerManager.swift: `debugLog(_:)` 메서드 및 모든 호출 제거 (기존 NSLog lifecycle 로그는 유지)
  - MozcConverter.swift: `debugLog(_:)` 메서드 및 모든 호출 제거, `convert()` 내 inline FileHandle 디버그 쓰기 3곳 제거
  - JapaneseEngine.swift: `triggerMozcConversion()` 내 inline FileHandle 디버그 쓰기 2곳 및 미사용 `mozcRunning` 변수 제거
  - KoreanEngine.swift: `triggerHanjaConversion()` 내 inline FileHandle 디버그 쓰기 1곳 제거
- 수정 파일:
  - NRIME/Engine/Japanese/Mozc/MozcClient.swift
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift
  - NRIME/Engine/Japanese/Mozc/MozcConverter.swift
  - NRIME/Engine/Japanese/JapaneseEngine.swift
  - NRIME/Engine/Korean/KoreanEngine.swift
- 검증: grep으로 `debugLog` 및 `nrime-debug.log` 참조가 Engine 디렉토리 내에 0건임을 확인
- 메모:
  - NSLog 기반 lifecycle 로그(서버 시작/종료/실패)는 의도적으로 유지
  - DeveloperLogger 호출은 건드리지 않음 (정상적으로 게이트된 로깅)

## 2026-03-24 04:17 JST | Claude Code

- 범위: MozcClient, MozcServerManager, MozcConverter, JapaneseEngine, KoreanEngine, ShortcutHandler
- 무엇을 했는지: DeveloperLogger.shared.log() 호출을 주요 파일에 추가
- 어떻게 수정했는지:
  - MozcClient: createSession 성공/실패, ensureSession backoff/restart/final failure, machCall IPC 성공/실패 로깅
  - MozcServerManager: prepareServerForUse 경로별(reachable/alreadyRunning/launched/failed), launchServer binary path, launchServerViaLaunchAgent 성공/실패 로깅 (기존 NSLog 있는 곳은 중복 방지)
  - MozcConverter: convert 요청/결과, feedHiragana 실패 지점들 로깅
  - JapaneseEngine: triggerMozcConversion 트리거 및 변환 결과 후보 수 로깅
  - KoreanEngine: triggerHanjaConversion 트리거 및 후보 수 로깅
  - ShortcutHandler: performAction에서 어떤 shortcut이 triggered 됐는지 로깅
- 수정 파일:
  - NRIME/Engine/Japanese/Mozc/MozcClient.swift
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift
  - NRIME/Engine/Japanese/Mozc/MozcConverter.swift
  - NRIME/Engine/Japanese/JapaneseEngine.swift
  - NRIME/Engine/Korean/KoreanEngine.swift
  - NRIME/State/ShortcutHandler.swift
- 검증: xcodebuild Debug 빌드 성공
- 메모: 모든 로그는 Settings.shared.developerModeEnabled 게이트 뒤에 있어 프로덕션 성능 영향 없음. 사용자 입력 텍스트는 로깅하지 않음(hanja source 제외 — 기능 데이터).

## 2026-03-24 03:30 JST | Claude Code

- 범위: 코드 정리, DeveloperLogger 강화, Swift Mach IPC 문서, 릴리즈 정리
- 무엇을 했는지:
  1. **디버그 로깅 전체 제거**: 6개 파일에서 /tmp/nrime-debug.log 관련 ad-hoc 로깅 전부 삭제 (-85 lines)
  2. **DeveloperLogger 커버리지 확대**: MozcClient, MozcServerManager, MozcConverter, JapaneseEngine, KoreanEngine, ShortcutHandler에 개발자 모드 로그 추가 (+177 lines)
  3. **Swift Mach IPC 참고 문서**: `docs/swift-mach-ipc-notes.md` — 실패 원인, 시도 방법, 교훈 정리
  4. **GitHub 릴리즈 정리**: v1.0.5에서 1.0.6 PKG 제거, v1.0.6에만 최신 PKG 유지
  5. **.gitignore**: `default.profraw` 추가
- 커밋:
  - `bdb54d4` — Remove ad-hoc debug logging
  - `15b91e2` — Add DeveloperLogger coverage and Swift Mach IPC reference doc
- 수정 파일:
  - NRIME/Controller/NRIMEInputController.swift
  - NRIME/Engine/Japanese/JapaneseEngine.swift
  - NRIME/Engine/Japanese/Mozc/MozcClient.swift
  - NRIME/Engine/Japanese/Mozc/MozcConverter.swift
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift
  - NRIME/Engine/Korean/KoreanEngine.swift
  - NRIME/State/ShortcutHandler.swift
  - docs/swift-mach-ipc-notes.md (신규)
  - .gitignore
- 검증: Release 빌드 성공, PKG 빌드 성공 (27MB), GitHub 릴리즈 업로드 완료
- 메모:
  - DeveloperLogger 커버리지: Controller, InputSourceRecovery, StateManager, AppDelegate, CandidatePanel, Mozc*, JapaneseEngine, KoreanEngine, ShortcutHandler
  - 모든 로그는 Settings.shared.developerModeEnabled 게이트 뒤에 있음
  - Swift Mach IPC 참고 문서는 나중에 별도 프로젝트에서 Swift-only 구현 재도전 시 사용

## 2026-03-24 05:08 JST | Codex

- 범위: 전체 코드베이스 점검, 구조 부채/최적화 포인트 정리
- 무엇을 했는지:
  - 현재 코드 기준으로 입력기 전체를 다시 훑어보면서, 단순 버그가 아니라 앞으로 회귀/지연/복잡도 증가를 만들 가능성이 큰 부분들을 정리했다.
  - 특히 일본어 Mozc 연동부, 후보창 위치 계산, JapaneseEngine 상태 전이, NRIMEInputController 책임 집중도를 중심으로 점검했다.
- 어떻게 수정했는지:
  - 이번 턴에는 코드 수정 없이 리뷰만 수행했다.
  - 우선순위가 높은 구조 리스크를 아래처럼 정리했다.
    1. MozcServerManager는 여전히 killall / launchctl / waitUntilExit / sleep 같은 동기 작업을 입력 경계 가까이에서 수행하고 있어, 일본어 실패 시 키 입력 지연을 만들 가능성이 높다.
    2. MozcClient는 createSession 실패를 여전히 비싼 동기 경로로 처리하고 있어, 완충(backoff/cooldown)은 들어가도 첫 실패 비용 자체가 크다.
    3. TextInputGeometry는 AX fallback + attributes(forCharacterIndex: 0) fallback을 함께 쓰고 있어, 위치 정확도와 누적 지연 면에서 아직 리스크가 남아 있다.
    4. JapaneseEngine은 forceCommit / clearState / exitConversionState / revertToComposing / triggerMozcConversion 등 상태 정리 함수가 여러 군데 흩어져 있어, 일본어 기능 수정 시 회귀가 쉽게 생길 구조다.
    5. NRIMEInputController는 engine routing, candidate panel, 숫자 선택, 일본어 변환 분기까지 너무 많이 들고 있어, 후보창/단축키/Mozc 이슈가 한 파일에서 서로 얽히기 쉽다.
  - 현재 판단으로는, 가장 효과가 큰 정리 순서를 아래처럼 제안했다.
    1. Mozc IPC 경계를 안정된 shim 기준으로 고정
    2. JapaneseEngine 상태 전이/정리 함수 통합
    3. NRIMEInputController에서 일본어 후보창/선택 로직 분리
    4. TextInputGeometry의 AX/index0 fallback 정책 축소 또는 단순화
- 수정 파일:
  - worklog.md
- 검증:
  - 코드 수정은 하지 않았고, 현재 코드 상태를 정적 점검해 구조/성능/회귀 리스크를 정리했다.
- 메모:
  - 현재 가장 큰 기술 부채는 입력기 전체 Swift 구조가 아니라 Mozc 연동 경계와 그 주변 복구/후보/UI 책임 분산 문제로 보는 쪽이 맞다.
  - 후보창 위치는 최근 체감이 나쁘지 않더라도, TextInputGeometry의 fallback 정책은 여전히 설명 가능성과 정확도 면에서 재정리가 필요하다.
  - 다음 에이전트가 이어받는다면, 일본어 신규 기능 추가보다 Mozc 경계 안정화와 JapaneseEngine/InputController 책임 축소를 먼저 보는 편이 안전하다.

## 2026-03-24 05:20 JST | Claude Code

- 범위: Codex 코드 리뷰 결과에 대한 검토 및 판단
- 무엇을 했는지: Codex가 정리한 5가지 구조 리스크를 검토하고, 각각 수정 필요 여부를 판단함.
- 판단 결과:
  1. **MozcServerManager 동기 작업 지연** — 의도적, 현재 OK. backoff/cooldown(2초/5초)으로 이미 완화됨. 서버 정상 시 발생하지 않는 경로.
  2. **MozcClient createSession 첫 실패 비용** — 의도적, 현재 OK. 서버 살아있으면 750ms 안에 성공. 실패 후 backoff으로 반복 차단.
  3. **TextInputGeometry AX fallback** — 알려진 트레이드오프. AX-first는 1초+ 지연, IMK-first는 부정확. 현재 IMK→AX fallback 순서가 현실적 타협안. 향후 AX 비동기 캐싱으로 개선 가능.
  4. **JapaneseEngine 상태 정리 함수 분산** — 유효한 관찰이나 현재 동작에 문제 없음. 리팩토링 리스크가 더 큼.
  5. **NRIMEInputController 책임 과다** — 장기적 구조 개선 사항. 현재 동작하는 코드를 분리하면 회귀 위험만 높아짐.
- 결론: 5개 모두 유효한 구조 관찰이지만, **지금 당장 수정이 필요한 버그나 성능 이슈는 없음**. 장기 리팩토링 목록으로 유지.
- 수정 파일: worklog.md

## 2026-03-24 05:50 JST | Claude Code

- 범위: LaunchAgent 제거, 인디케이터 위치 개선, mozc on-demand 전환
- 무엇을 했는지:
  1. **LaunchAgent 전면 제거**: RestoreHelper + mozc_server LaunchAgent plist를 PKG/postinstall/build_pkg에서 제거. 백그라운드 항목 알림/설정 항목 완전 제거됨.
  2. **mozc_server on-demand**: NRIME이 직접 자식 프로세스로 시작. LaunchAgent 관련 코드(launchServerViaLaunchAgent, stopLaunchAgentServer, runLaunchCtl 등) 전부 삭제.
  3. **인디케이터 위치 대폭 개선** (다른 입력기 리서치 기반):
     - **마지막 성공 좌표 캐시** (fcitx5-macos 패턴): 모든 방법 실패 시 이전 위치 유지, (0,0) 점프 방지
     - **AX length:1**: macOS zero-length kAXBoundsForRange 버그 우회 (Apple 공식 버그)
     - **Electron AXEnhancedUserInterface**: 비-Apple 앱에 AX 트리 활성화 (Input Source Pro 패턴)
     - **WebKit AXSelectedTextMarkerRange**: Chromium 웹뷰 전용 커서 감지 (Input Source Pro 패턴)
     - **우선순위 변경**: firstRect → attributes → attributesAtZero → AX (AX는 느릴 수 있으므로 최후 수단)
  4. **postinstall**: 이전 버전 LaunchAgent plist 자동 정리 (업그레이드 호환)
  5. **README**: 수동 제거 명령 업데이트, "백그라운드 프로세스 없음" 호환성 추가
- 수정 파일:
  - NRIME/System/TextInputGeometry.swift (인디케이터 위치 전면 개선)
  - NRIME/Engine/Japanese/Mozc/MozcServerManager.swift (LaunchAgent 코드 제거)
  - Tools/build_pkg.sh (LaunchAgent plist 패키징 제거)
  - Tools/pkg/postinstall (mozc LaunchAgent 정리, 이전 버전 호환)
  - README.md
- 커밋: `9e258e4`
- 검증: Release 빌드 성공, PKG 빌드 27MB, GitHub v1.0.6 릴리즈 업로드
- 메모:
  - 인디케이터 리서치 소스: Input Source Pro (AX + Electron), fcitx5-macos (좌표 캐시), Squirrel (IMK attributes)
  - Accessibility 권한은 CGEvent.post (Cmd+A 패스스루) 때문에 여전히 필요 — 제거 불가
  - mozc on-demand: prewarm으로 첫 변환 지연 최소화, 서버 죽으면 ensureSession이 재시작
  - 이전 버전에서 업그레이드 시 postinstall이 old LaunchAgent plist를 자동 정리

## 2026-03-26 07:00 JST | Claude Code

- 범위: 인디케이터 위치, 메뉴바 아이콘, 캡스락/F18 조사
- 무엇을 했는지:
  1. **메뉴바 아이콘 복원**: 36x36@144dpi 생성 이미지가 non-HiDPI QHD 모니터에서 오버플로우. 원본 18x18로 복원. 고해상도 아이콘은 나중에 PDF 벡터로 재시도.
  2. **인디케이터 조합 중 점프 방지**: 조합 중(markedRange 활성)이면 위치 업데이트를 하지 않고 lastGoodResult 유지. 많은 앱이 조합 중 firstRect에서 입력필드 시작 위치를 반환하는 문제 우회.
  3. **attributesAtZero를 lastGoodResult에 저장하지 않음**: X좌표가 부정확한 결과가 이후 위치 검색을 오염시키는 것 방지.
  4. **FOCD 프로젝트 분석**: PopupFix는 인디케이터 위치가 아니라 macOS 한영 전환 팝업을 숨기는(30000,30000으로 이동) 코드. 인디케이터 위치 참고 불가.
  5. **캡스락 조사**: NRIME에 Caps Lock 처리 코드 없음. macOS가 시스템 레벨에서 먼저 가로챔. flagsChanged로 감지는 가능하나 LED 상태와 불일치 문제.
  6. **F18 전환 시 조합 글자 사라짐 조사**: wireUpShortcutHandler의 onAction에서 forceCommit을 이미 호출 중. 원인 미확정 — Karabiner가 보내는 F18 이벤트 타입 확인 필요.
- 수정 파일:
  - NRIME/Resources/icon_en.tiff, icon_ko.tiff, icon_ja.tiff (원본 복원)
  - NRIME/System/TextInputGeometry.swift (조합 중 위치 동결, attributesAtZero 캐시 방지)
  - NRIME/UI/InlineIndicator.swift (attributesAtZero 시 마우스 X fallback)
- 커밋: `4e060b6`
- 검증: Release 빌드 성공, 사용자 테스트 대기
- 메모:
  - F18 전환 시 글자 사라짐: forceCommit은 구현되어 있으나 실제 동작 확인 필요. Karabiner의 F18이 keyDown 대신 다른 이벤트 타입으로 올 가능성.
  - RShift 빠른 타이핑 시 쌍자음/대문자 입력: "등록된 모디파이어는 항상 전환 우선" 옵션 추가 가능.
  - 캡스락 지원: flagsChanged 감지 + LED 무시 방식으로 구현 가능하나 UX 검토 필요.

## 2026-03-26 07:13 JST | Claude Code

- 범위: 한글 forceCommit Electron 텍스트 삭제 버그 수정 시도, 인디케이터 위치 수정
- 무엇을 했는지:
  1. 한글 forceCommit에서 setMarkedText("") + insertText 패턴을 commitComposing() (insertText만) 으로 변경
  2. 목적: Electron oldHasMarkedText 문제 우회 (Shift+Enter 때와 동일한 패턴)
  3. 결과: **여전히 실패** — F18으로 한글 조합 중 전환 시 글자 사라짐. 일본어는 정상.
- 어떻게 수정했는지:
  - KoreanEngine.swift: forceCommit()이 commitComposing()을 호출하도록 변경
  - commitComposing()은 setMarkedText("") 없이 insertText만 호출
- 수정 파일: NRIME/Engine/Korean/KoreanEngine.swift
- 검증: 사용자 테스트 — 한글 조합 중 F18 전환 시 여전히 글자 사라짐
- 메모:
  - DeveloperLogger에서 shortcutAction이 정상 트리거되는 것 확인
  - 하지만 forceCommit 내부에서 실제로 insertText가 호출되는지, 어떤 텍스트가 전달되는지 로그 부재
  - 다음 단계: forceCommit에 DeveloperLogger 추가하여 실제 동작 확인 필요
  - 가설: F18 이벤트가 shortcutHandler를 통하지 않고 Korean engine의 handleEvent로 먼저 가서 조합을 깨뜨리는 것일 수 있음
  - 인디케이터: 조합 중 lastGoodResult 유지 로직 적용됨. 보이긴 하지만 여전히 입력필드 처음으로 감 — lastGoodResult가 처음부터 잘못된 위치를 캐싱한 것으로 추정

## 2026-03-26 07:26 JST | Claude Code

- 범위: 한글 forceCommit Electron 텍스트 삭제 버그 **해결**, 인디케이터 위치 개선
- 무엇을 했는지:
  1. **한글 forceCommit 수정 — 해결됨**: `setMarkedText("") + insertText` 패턴을 `commitComposing()` (insertText만) 으로 교체. Electron의 oldHasMarkedText 문제 완전 우회.
  2. forceCommit에 DeveloperLogger 추가 (디버깅용, 개발자 모드 게이트)
  3. 인디케이터 위치: 조합 중 lastGoodResult 유지로 점프 방지 확인됨
- 어떻게 수정했는지:
  - KoreanEngine.forceCommit(): 직접 flush+setMarkedText+insertText 대신 commitComposing() 호출
  - commitComposing()은 setMarkedText("") 없이 insertText만 호출 — Electron에서 안전
- 수정 파일: NRIME/Engine/Korean/KoreanEngine.swift
- 검증: 사용자 테스트 — F18으로 한글 조합 중 전환 시 글자 정상 확정됨
- 메모:
  - 근본 원인: Electron의 oldHasMarkedText — setMarkedText("") 직후 insertText 호출 시 텍스트 삭제
  - Shift+Enter 때와 동일한 패턴의 문제였음
  - 일본어는 원래 정상이었는데, JapaneseEngine.forceCommit도 동일 패턴(setMarkedText + insertText) 사용 중 — 향후 같은 문제 발생 가능성 있음
  - 인디케이터: Shift+Enter 후 윗줄 끝에 표시되는 잔여 이슈 있음 (lastGoodResult가 이전 줄 위치)

## 2026-03-26 07:39 JST | Claude Code

- 범위: 메뉴바 아이콘 고해상도, Caps Lock 지원, 전용 모디파이어 모드, Shift 더블탭
- 무엇을 했는지:
  1. **메뉴바 아이콘 런타임 렌더링**: TIFF 파일 삭제, NSImage를 런타임으로 생성. 시스템이 DPI 스케일링 자동 처리. isTemplate=true로 다크모드 대응.
  2. **Caps Lock 네이티브 지원**: OFF→ON 전환 시에만 한 번 실행 (이전: press+release 두 번 실행으로 깜빡임). Shift+CapsLock은 pass-through.
  3. **전용 모디파이어 모드(dedicatedModifierMode)**: 등록된 탭 단축키 모디파이어가 다른 키와 조합하지 않도록. RShift 빠른 타이핑 시 쌍자음/대문자 방지.
  4. **Shift 더블탭 → Caps Lock 토글**: CGEvent로 시스템 Caps Lock 전송. 0.3초 윈도우.
  5. **설정 UI 토글 추가**: "Dedicated switch key mode" 토글 + 설명 텍스트
- 수정 파일:
  - NRIME/App/AppDelegate.swift (런타임 아이콘 렌더링)
  - NRIME/State/InputMode.swift (iconName 프로퍼티 제거)
  - NRIME/Resources/icon_*.tiff (삭제)
  - NRIME/State/ShortcutHandler.swift (Caps Lock OFF→ON, Shift+CapsLock pass-through, 전용 모디파이어, 더블탭)
  - NRIME/State/Settings.swift (dedicatedModifierMode)
  - NRIME/Controller/NRIMEInputController.swift (routeEvent에서 모디파이어 strip)
  - NRIMESettings/SettingsStore.swift (dedicatedModifierMode)
  - NRIMESettings/GeneralTab.swift (토글 UI)
- 검증: 빌드 성공, 사용자 테스트 대기
- 메모:
  - 전용 모디파이어 모드: Command 키의 경우 조합 중일 때만 strip하도록 추가 조건 필요 (Cmd+A 등 보호)
  - Shift 더블탭 간격 조절 설정 추가 필요
  - 향후 과제: 다국어화(README, 설정 UI), 자동 업데이트(GitHub 릴리즈 감지)

## 2026-03-26 07:52 JST | Claude Code

- 범위: v1.0.7 릴리즈 — 아이콘 복구, Caps Lock 수정, 버전업
- 무엇을 했는지:
  1. TIFF 아이콘 복구 (git checkout 4e060b6에서 icon_en/ko/ja.tiff 복원)
  2. Caps Lock 언어전환 후 toggleCapsLock()으로 시스템 상태 되돌리기 추가
  3. 버전 1.0.7로 업 (project.yml: MARKETING_VERSION, CURRENT_PROJECT_VERSION)
  4. distribution.xml의 __VERSION__ 플레이스홀더 복원 (agent가 하드코딩한 것 수정)
  5. 커밋 f581a0e, 푸시, PKG 빌드, GitHub v1.0.7 릴리즈 생성
- 수정 파일:
  - NRIME/Resources/icon_en.tiff, icon_ko.tiff, icon_ja.tiff (복원)
  - NRIME/State/ShortcutHandler.swift (Caps Lock toggleCapsLock 추가)
  - project.yml (1.0.6→1.0.7, build 7→8)
  - Tools/pkg/distribution.xml (__VERSION__ 복원)
- 검증: PKG 빌드 성공 (27MB), GitHub 릴리즈 생성 완료
- 메모:
  - Caps Lock + Karabiner 조합에서 toggleCapsLock() CGEvent가 다시 Karabiner를 거쳐 충돌 가능
  - 네이티브 Caps Lock 지원은 CGEvent tap 레벨 가로채기가 필요 — 추후 과제
  - 입력소스 아이콘은 xcodegen이 NRIME/Resources 폴더를 자동 포함하므로 별도 project.yml 수정 불필요
  - build_pkg.sh의 distribution.xml은 __VERSION__ 플레이스홀더를 사용 — 하드코딩하면 안됨

## 2026-03-26 08:05 JST | Claude Code (Opus 4.6)

- 범위: dedicated modifier mode 기능 전체 제거
- 무엇을 했는지: dedicatedModifierMode 관련 코드 전부 삭제 (Settings, SettingsStore, GeneralTab, ShortcutHandler, NRIMEInputController)
- 어떻게 수정했는지:
  - Settings.swift: `dedicatedModifierMode` 프로퍼티 삭제
  - SettingsStore.swift: `_dedicatedModifierMode` 초기화, `@Published var dedicatedModifierMode`, load 코드 삭제
  - GeneralTab.swift: "Modifier Behavior" Section 전체 삭제
  - ShortcutHandler.swift: `shouldStripActiveModifier`, `activeModifierFlag` computed properties 삭제, keyDown에서 `!shouldStripActiveModifier` 예외 조건 제거
  - NRIMEInputController.swift: modifier flag stripping 블록 삭제, `var routedEvent = event` → `let routedEvent = event`
- 수정 파일: Settings.swift, SettingsStore.swift, GeneralTab.swift, ShortcutHandler.swift, NRIMEInputController.swift
- 검증: `xcodebuild -scheme NRIME -configuration Release` BUILD SUCCEEDED, grep으로 dedicatedModifier/exclusiveModifier/shouldStripActiveModifier/activeModifierFlag 잔여 참조 없음 확인
- 메모: 이 기능은 Shift+click 선택, Shift+arrow 텍스트 선택 등 일반 Shift 조합 키가 깨지는 문제로 제거됨

## 2026-03-26 08:18 JST | Claude Code (Opus 4.6)

- 범위: Tools/ scripts, PKG packaging
- 무엇을 했는지: RestoreHelper LaunchAgent 완전 제거 — macOS "Login Items & Extensions"에 NRIMERestoreHelper가 표시되지 않도록 함
- 어떻게 수정했는지:
  - build_pkg.sh: NRIMERestoreHelper 빌드/검증/서명/패키징 라인 제거
  - postinstall: loginrestore LaunchAgent bootstrap 섹션 → 양쪽 경로(/Library/LaunchAgents, ~/Library/LaunchAgents)에서 bootout + rm 하는 cleanup 섹션으로 교체
  - install.sh: loginrestore plist 생성/bootstrap 섹션 → 기존 plist 발견 시 bootout+rm cleanup으로 교체
  - uninstall.sh: 변경 없음 (이미 cleanup 코드 포함)
  - Tools/pkg/com.nrime.inputmethod.loginrestore.plist: 삭제
- 수정 파일: Tools/build_pkg.sh, Tools/pkg/postinstall, Tools/install.sh, Tools/pkg/com.nrime.inputmethod.loginrestore.plist (deleted)
- 검증: 코드 리뷰 — 구 버전에서 업그레이드 시 postinstall이 LaunchAgent를 적극 제거함
- 메모: NRIME 자체 InputSourceRecovery.swift가 입력 소스 복구를 처리하므로 RestoreHelper LaunchAgent 불필요

## 2026-03-26 08:31 JST | Claude Code

- 범위: 다국어화, 설정 UI 추가, 전용 모디파이어 제거, RestoreHelper LaunchAgent 제거, Shift+Enter 딜레이 설정화
- 무엇을 했는지:
  1. **전용 모디파이어 모드 완전 제거** (에이전트): Settings, SettingsStore, GeneralTab, ShortcutHandler, NRIMEInputController에서 dedicatedModifier 관련 코드 전부 삭제
  2. **RestoreHelper LaunchAgent 제거** (에이전트): build_pkg.sh, postinstall에서 loginrestore plist 패키징/부트스트랩 제거. postinstall에 이전 버전 LaunchAgent 정리 코드 추가
  3. **Shift 더블탭 간격 설정**: Settings.swift에 `doubleTapWindow` 추가, ShortcutHandler에서 하드코딩 0.3 → Settings에서 읽도록, SettingsStore + GeneralTab에 슬라이더 추가
  4. **Shift+Enter 딜레이 설정**: Settings.swift에 `shiftEnterDelay` 추가 (기본 15ms), KoreanEngine/JapaneseEngine에서 하드코딩 → Settings에서 읽도록, GeneralTab에 슬라이더 추가
  5. **README 다국어화**: README.en.md, README.ja.md를 한국어 README 기준으로 전면 갱신 (Electron 지원, 토글 방식, 백그라운드 프로세스 없음 등 반영)
  6. **설정 UI 다국어화 + 자동 업데이트**: 에이전트 병렬 실행 중
- 어떻게 수정했는지:
  - Shift+Enter 딜레이: 하드코딩 `0.015` → `Settings.shared.shiftEnterDelay`
  - 더블탭 간격: 하드코딩 `0.3` → `Settings.shared.doubleTapWindow`
  - 전용 모디파이어: `shouldStripActiveModifier`, `activeModifierFlag` 제거, `dedicatedModifierMode` 설정 제거
- 수정 파일:
  - NRIME/State/Settings.swift (doubleTapWindow, shiftEnterDelay 추가, dedicatedModifierMode 제거)
  - NRIME/State/ShortcutHandler.swift (doubleTapWindow → Settings, dedicatedModifier 코드 제거)
  - NRIME/Controller/NRIMEInputController.swift (modifier strip 코드 제거)
  - NRIME/Engine/Korean/KoreanEngine.swift (shiftEnterDelay → Settings)
  - NRIME/Engine/Japanese/JapaneseEngine.swift (shiftEnterDelay → Settings)
  - NRIMESettings/SettingsStore.swift (doubleTapWindow, shiftEnterDelay 추가, dedicatedModifierMode 제거)
  - NRIMESettings/GeneralTab.swift (더블탭 간격 슬라이더, Shift+Enter 딜레이 슬라이더 추가, 모디파이어 섹션 제거)
  - README.en.md, README.ja.md (전면 갱신)
  - Tools/build_pkg.sh, Tools/pkg/postinstall (RestoreHelper LaunchAgent 제거)
- 검증: NRIME + NRIMESettings 양쪽 빌드 성공
- 메모:
  - Shift+CapsLock은 keyCode 0x39에만 반응 — Karabiner F18 경유 시 Shift+F18은 별도 처리 필요
  - Shift 더블탭은 기본 활성화 (doubleTapWindow 기본값 0.3초)
  - 자동 업데이트/설정 UI 다국어화 에이전트는 아직 진행 중
  - Caps Lock 네이티브 지원과 전용 모디파이어 모드는 장기 과제로 분류

## 2026-03-26 08:44 JST | Claude Code (Opus 4.6)

- 범위: 자동 업데이트 시스템 구현
- 무엇을 했는지: GitHub Releases API 기반 자동 업데이트 매니저 및 Settings About 탭 UI 구현
- 어떻게 수정했는지:
  - `Shared/UpdateManager.swift` 신규 생성 — 싱글톤, GitHub API fetch (ETag 캐싱), 시맨틱 버전 비교, PKG 다운로드 (URLSessionDownloadDelegate 진행률), osascript installer 실행
  - `NRIMESettings/AboutTab.swift` 전면 갱신 — UpdateManager를 @StateObject로 연동, 상태별 UI (idle/checking/upToDate/available/downloading/readyToInstall/installing/error)
  - `project.yml` — NRIME, NRIMESettings 양쪽 targets에 Shared/UpdateManager.swift 추가
- 수정 파일:
  - Shared/UpdateManager.swift (신규)
  - NRIMESettings/AboutTab.swift (수정)
  - project.yml (수정)
- 검증: xcodegen generate + NRIME Release 빌드 성공 + NRIMESettings Release 빌드 성공
- 메모:
  - 24시간 간격 자동 체크 (UserDefaults suiteName: group.com.nrime.inputmethod)
  - 네트워크 오류 시 silent fail (IME 크래시 방지)
  - 외부 의존성 없음 (Sparkle 미사용)
  - GitHub unauthenticated API 60 req/hour 제한 — 24h 간격이면 충분

## 2026-03-26 08:57 JST | Claude Code (Opus 4.6)

- 범위: NRIMESettings 앱 국제화 (i18n)
- 무엇을 했는지: NRIMESettings 앱의 모든 하드코딩된 UI 문자열을 한국어/영어/일본어 3개 언어로 로컬라이즈
- 어떻게 수정했는지:
  - NRIMESettings/Resources/{ko,en,ja}.lproj/Localizable.strings 파일 생성 (약 120개 키)
  - GeneralTab, JapaneseTab, DictionaryTab, PerAppTab, AboutTab, SettingsView의 모든 하드코딩 문자열을 String(localized:) 또는 SwiftUI Text 자동 룩업으로 교체
  - AboutTab에 한국어/English/日本語 세그먼트 피커 추가 (AppStorage "appLanguage" 사용)
  - SettingsView에서 .environment(\.locale, Locale(identifier: appLanguage)) 적용
  - project.yml에 developmentLanguage: ko 추가
- 수정 파일:
  - NRIMESettings/Resources/ko.lproj/Localizable.strings (신규)
  - NRIMESettings/Resources/en.lproj/Localizable.strings (신규)
  - NRIMESettings/Resources/ja.lproj/Localizable.strings (신규)
  - NRIMESettings/GeneralTab.swift (수정)
  - NRIMESettings/JapaneseTab.swift (수정)
  - NRIMESettings/DictionaryTab.swift (수정)
  - NRIMESettings/PerAppTab.swift (수정)
  - NRIMESettings/AboutTab.swift (수정)
  - NRIMESettings/SettingsView.swift (수정)
  - NRIMESettings/NRIMESettingsApp.swift (수정)
  - project.yml (수정)
- 검증: xcodegen generate 성공 + NRIMESettings Release 빌드 성공 + lproj 파일 번들 포함 확인
- 메모:
  - 언어 선택은 AppStorage("appLanguage")에 저장, 기본값 "ko"
  - .environment(\.locale)로 SwiftUI Text 자동 룩업 적용
  - AboutTab의 UpdateManager 섹션 문자열은 영어 유지 (업데이트 UI는 향후 별도 로컬라이즈 가능)
  - JapaneseKeyRow의 description (ひらがな, 全角カタカナ 등)은 일본어 고유 용어라 번역하지 않음
  - ShortcutConfig.label과 modifier key label은 시스템 키 이름이라 번역하지 않음

## 2026-03-26 09:10 JST | Claude Code

- 범위: Shift 더블탭 미작동 원인 추적
- 무엇을 했는지: Left Shift 더블탭 CapsLock 토글이 안 되는 원인 조사
- 결과: 코드 로직은 정상. 설치된 바이너리가 최신 빌드와 다름 (MD5 불일치). 아직 새 빌드가 설치되지 않아서 안 된 것.
- 추가 발견: Shift+CapsLock은 Karabiner가 CapsLock을 F18로 변환하면 keyCode 0x39를 못 감지 — 장기 과제로 분류하고 제거 고려
- 수정 파일: 없음 (진단만)
- 메모: 다국어화 에이전트 + 자동 업데이트 에이전트 완료 후 전체 빌드/PKG/커밋/릴리즈 예정

## 2026-03-26 09:23 JST | Claude Code

- 범위: v1.0.7 최종 커밋/빌드/릴리즈
- 무엇을 했는지:
  1. 전체 빌드 (NRIME + NRIMESettings) 성공
  2. 커밋 `4789cfe` — 23 files changed, 1406 insertions(+), 441 deletions(-)
  3. 푸시 + PKG 빌드 (27MB) + GitHub v1.0.7 릴리즈 업로드
- 포함된 변경:
  - 설정 UI 다국어화 (ko/en/ja Localizable.strings + 언어 선택 피커)
  - 자동 업데이트 (UpdateManager.swift — GitHub API + PKG 다운로드/설치)
  - 전용 모디파이어 모드 제거
  - RestoreHelper LaunchAgent 제거 (백그라운드 항목 알림 해결)
  - Shift 더블탭 간격/Shift+Enter 딜레이 설정 UI
  - README 영어/일본어 갱신
  - Caps Lock 전환 후 시스템 상태 되돌리기
- 수정 파일: 위 커밋 참고 (23개)
- 검증: 양쪽 빌드 성공, PKG 빌드 성공, 릴리즈 업로드 완료

## 2026-03-26 09:36 JST | Claude Code

- 범위: Shift 더블탭 CapsLock 미작동 디버깅 + EN→A 변경
- 무엇을 했는지:
  1. Shift 더블탭 코드 로직 재확인 — 코드 자체는 정상이나 `toggleCapsLock()`이 CGEvent.post로 구현되어 Accessibility 권한 없으면 조용히 실패
  2. `toggleCapsLock()`을 IOKit `IOHIDSetModifierLockState`로 교체 — Accessibility 권한 불필요
  3. InputMode.english의 label을 "EN" → "A"로 변경
- 어떻게 수정했는지:
  - ShortcutHandler.swift: toggleCapsLock()을 CGEvent → IOKit으로 변경
  - InputMode.swift: english case label "EN" → "A"
- 수정 파일: NRIME/State/ShortcutHandler.swift, NRIME/State/InputMode.swift
- 검증: Release 빌드 성공
- 메모: 개발자 모드 로그로 "Double-Shift → toggling Caps Lock" 출력 여부 확인 가능. 안 찍히면 더블탭 감지 실패, 찍히면 IOKit 호출 문제.

## 2026-03-26 09:49 JST | Claude Code

- 범위: CapsLock 토글 수정, EN→A, 인디케이터 크기 동적화, PKG 릴리즈
- 무엇을 했는지:
  1. toggleCapsLock: IOHIDGetModifierLockState가 macOS 26.4에서 항상 false 반환 → 내부 상태 추적으로 변경
  2. EN → A: InputMode.english label, 메뉴바/인디케이터 모두 적용
  3. 인디케이터 크기: 1글자(A/한/あ)는 26x24, 2글자 이상은 36x24로 동적 조절
  4. 커밋 99cee67, 푸시, PKG 빌드, v1.0.7 릴리즈 업로드
- 수정 파일: ShortcutHandler.swift, InputMode.swift, InlineIndicator.swift
- 검증: 빌드 성공, Left Shift 더블탭 CapsLock 켜기/끄기 둘 다 동작 확인 (개발자 로그)
- 메모: IOHIDGetModifierLockState가 macOS 26.4에서 broken — launch_msg()처럼 deprecated API 문제일 가능성

## 2026-03-26 10:02 JST | Claude Code

- 범위: postinstall swift-frontend 알림 제거
- 무엇을 했는지: postinstall의 `swift -e` 인라인 스크립트를 미리 컴파일된 `enable_input_source` 바이너리로 교체
- 어떻게 수정했는지:
  - Tools/pkg/enable_input_source.swift 생성 (Carbon TISEnableInputSource 호출)
  - build_pkg.sh에서 `swiftc -O`로 빌드 시 컴파일하여 scripts/에 포함
  - postinstall에서 swift -e 대신 바이너리 직접 실행
- 수정 파일: Tools/pkg/postinstall, Tools/build_pkg.sh, Tools/pkg/enable_input_source.swift (신규), Tools/pkg/enable_input_source (컴파일된 바이너리)
- 검증: PKG 빌드 성공 (27MB)
- 메모: swift-frontend 알림은 macOS가 swift 컴파일러 실행을 감지해서 표시. 미리 컴파일하면 swift 호출 없음.

## 2026-03-26 10:15 JST | Claude Code

- 범위: RShift 연타 전환 개선
- 무엇을 했는지: 단축키로 등록된 Shift 키는 더블탭 CapsLock 감지에서 제외
- 어떻게 수정했는지: ShortcutHandler의 더블탭 체크에 `isKeyRegisteredAsShortcut` 가드 추가. 등록된 키면 `lastShiftTapTime` 기록도 건너뛰어 CapsLock 토글 불가.
- 수정 파일: NRIME/State/ShortcutHandler.swift
- 검증: Release 빌드 성공
- 메모: RShift=한영전환, LShift 더블탭=CapsLock 토글. 서로 간섭 안 함.

## 2026-03-26 10:28 JST | Claude Code

- 범위: Shift 더블탭 keyCode 매칭 + enable_input_source 제거
- 무엇을 했는지:
  1. 더블탭 CapsLock에 `lastShiftTapKeyCode == keyCode` 조건 추가 — LShift+LShift만 매칭, LShift→RShift는 더블탭 아님
  2. postinstall에서 enable_input_source 호출 완전 제거 — 미서명 바이너리가 TCC 권한 요청 팝업을 유발했음
  3. build_pkg.sh에서 enable_input_source 컴파일 단계도 제거
- 어떻게 수정했는지:
  - ShortcutHandler.swift: 더블탭 체크에 `lastShiftTapKeyCode == keyCode` 가드 추가
  - postinstall: enable_input_source 실행 → 주석으로 대체 (InputSourceRecovery가 처리)
  - build_pkg.sh: swiftc 컴파일 단계 제거
- 수정 파일: NRIME/State/ShortcutHandler.swift, Tools/pkg/postinstall, Tools/build_pkg.sh
- 검증: 빌드 성공, PKG 빌드 성공, v1.0.7 릴리즈 업로드
- 메모:
  - swift -e: swift-frontend 알림 유발 (매 설치마다)
  - 미리 컴파일된 바이너리: TCC 권한 요청 유발 (처음 1회)
  - 둘 다 제거하고 NRIME 자체의 InputSourceRecovery에 위임 — 알림 없음
  - 자동 업데이트 동일 버전 재업로드 감지 테스트 완료 (v1.0.8 더미 릴리즈 생성/삭제)

## 2026-03-26 10:41 JST | Claude Code (Opus 4.6)

- 범위: README.md, README.en.md, README.ja.md 전면 업데이트
- 무엇을 했는지: README 3개 파일을 현재 코드베이스 상태에 맞춰 전면 재작성
- 어떻게 수정했는지:
  - 기능 섹션 신설: 추가 기능 목록 (Shift 더블탭, 앱별 언어 기억, 자동 업데이트, 설정 백업 등)
  - 설정 테이블을 GeneralTab/JapaneseTab/PerAppTab/AboutTab 실제 UI 섹션에 맞춰 재구성
  - 수동 제거 명령을 uninstall.sh와 일치시킴 (Preferences plist, Application Support/NRIME 추가)
  - NRIMERestoreHelper/LaunchAgent을 "이전 버전 정리용"으로 명시
  - 호환성 테이블에 원격 데스크톱 추가, 체크마크 표시 통일
  - 변환 키 상세에 문절 이동/크기 조정/예측 선택 추가
  - Electron 워크어라운드 기술 노트에 "설정 가능한 딜레이" 반영
  - Mozc IPC 기술 노트 섹션 신설
  - detailedKeyLogging, dedicated modifier mode 참조 없음 확인
  - 3개 파일 구조/내용 동기화
- 수정 파일: README.md, README.en.md, README.ja.md
- 검증: grep으로 제거된 기능 참조 없음 확인, uninstall 명령 일치 확인, 3파일 섹션 구조 일치 확인
- 메모: 빌드 불필요 — 문서 전용 변경

## 2026-03-26 10:54 JST | Claude Code

- 범위: 설정 UI 언어 전환 미작동 수정
- 무엇을 했는지: `String(localized:)`가 SwiftUI의 `.environment(\.locale)` 무시하는 문제 해결
- 어떻게 수정했는지:
  - SettingsView.swift에 `L()` 헬퍼 함수 + `LocalizedBundle` 클래스 추가
  - `LocalizedBundle`이 선택된 언어의 `.lproj` 번들에서 직접 문자열을 읽음
  - 88개 `String(localized: "key")` → `L("key")` 일괄 교체 (GeneralTab, JapaneseTab, DictionaryTab, PerAppTab, AboutTab)
- 수정 파일: NRIMESettings/SettingsView.swift, GeneralTab.swift, JapaneseTab.swift, DictionaryTab.swift, PerAppTab.swift, AboutTab.swift
- 검증: NRIMESettings Release 빌드 성공
- 메모:
  - SwiftUI `Text("key")`는 `.environment(\.locale)` 자동 적용
  - `String(localized:)`는 Bundle.main의 시스템 로캘만 사용 → 앱 내 언어 전환 불가
  - `L()` 패턴은 macOS 앱에서 표준적인 언어 오버라이드 방식
  - PostToolUse hook이 정상 작동하여 worklog 리마인더 수신 확인

## 2026-03-26 11:07 JST | Claude Code

- 범위: 설정 UI 언어 전환 미작동 추가 수정 + 반각 서양식 구두점
- 무엇을 했는지:
  1. `.id(appLanguage)` 추가 — TabView에 언어 변경 시 전체 뷰 강제 재렌더링
  2. 49개 `Text("key")` → `Text(L("key"))` 일괄 교체 — SwiftUI 자동 로컬라이징과 L() 시스템 혼재로 일부만 번역되던 문제 해결
  3. 재시작 안내 메시지 제거 (L() 방식은 즉시 적용)
  4. 반각 서양식 구두점 `halfWidthWestern` (.,) 추가 — SettingsModels, JapaneseEngine, JapaneseTab, 3개 Localizable.strings
- 수정 파일: SettingsView.swift, AboutTab.swift, GeneralTab.swift, JapaneseTab.swift, DictionaryTab.swift, PerAppTab.swift, JapaneseEngine.swift, SettingsModels.swift, ko/en/ja Localizable.strings
- 검증: NRIME + NRIMESettings 빌드 성공
- 메모:
  - 근본 원인: SwiftUI `Text("key")`는 `.environment(\.locale)` 따르지만 `L()`은 `LocalizedBundle` 따름 → 두 시스템 타이밍 불일치
  - `.id(appLanguage)`로 언어 변경 시 전체 뷰 트리를 파괴/재생성하여 해결
  - 모든 로컬라이즈 문자열을 `L()`로 통일하여 일관성 확보

## 2026-03-26 11:20 JST | Claude Code

- 범위: 설정 UI 언어 전환 + 구두점 선택 미작동 수정
- 무엇을 했는지:
  1. LocalizedBundle을 ObservableObject로 변경, @Published revision 카운터 추가
  2. 각 탭(GeneralTab, JapaneseTab, DictionaryTab, PerAppTab, AboutTab)에 @ObservedObject lang 추가
  3. `let _ = lang.revision`으로 언어 변경 시 SwiftUI 재렌더링 트리거
  4. punctuation.fullWidthWestern 키가 Localizable.strings에 누락돼 있던 것 추가
  5. sed로 중첩 struct 안에 잘못 삽입된 코드 제거 후 정확한 위치에 재삽입
- 수정 파일: SettingsView.swift, GeneralTab.swift, JapaneseTab.swift, DictionaryTab.swift, PerAppTab.swift, AboutTab.swift, ko/en/ja Localizable.strings
- 검증: NRIMESettings 빌드 성공
- 메모:
  - SwiftUI `.id()` modifier만으로는 탭 콘텐츠가 재렌더링 안 됨 — ObservableObject + @Published가 필요
  - 구두점 저장 문제: 저장 자체는 코드상 정상, 설치된 빌드가 최신이 아닌 것으로 추정
  - sed로 `let _ = lang.revision`을 모든 `var body:` 뒤에 추가할 때 서브뷰의 body에도 들어가는 실수 → awk로 첫 번째만 매칭하도록 수정

## 2026-03-26 11:33 JST | Claude Code

- 범위: 자동 업데이트 무한 루프 수정
- 무엇을 했는지:
  1. PKG 설치 시 postinstall이 `killall NRIMESettings` → 설치 후 타임스탬프 저장 코드가 실행 안 됨
  2. 타임스탬프 저장을 다운로드 완료 시점으로 이동 (설치 전에 저장)
  3. 크기(size) 비교 → GitHub asset `updated_at` 타임스탬프 비교로 변경 (더 신뢰성 있음)
- 수정 파일: Shared/UpdateManager.swift
- 검증: 빌드 성공, PKG 업로드
- 메모: 같은 크기 파일을 다시 올려도 타임스탬프는 달라지므로 재업로드 감지 정확도 향상

## 2026-03-26 11:46 JST | Claude Code

- 범위: i18n 탭 동기화 + 탭 선택 유지
- 무엇을 했는지:
  1. `L()`이 매 호출마다 `syncWithUserDefaults()`로 현재 언어 확인 → bundle 자동 업데이트
  2. `.id(appLanguage)` 제거 → TabView 재생성 방지 → 언어 변경 시 정보탭에서 이동 안 함
  3. `ObservableObject` + `@Published revision`으로 각 탭이 재렌더링
- 수정 파일: NRIMESettings/SettingsView.swift
- 검증: 빌드 성공, PKG 업로드
- 메모:
  - `.id()` 변경 시 SwiftUI가 뷰를 재생성하면서 선택된 탭이 초기화되는 문제 있었음
  - `.id()` 없이 ObservableObject 방식만으로 충분 — `L()`이 매번 UserDefaults를 확인하므로
  - 구두점: 수동으로 defaults 변경 시 반각 작동 확인. 설정 UI 반영은 최신 빌드 설치 후 테스트 필요

## 2026-03-26 12:00 JST | Claude Code

- 범위: 구두점 크로스프로세스 동기화, Shift 더블탭 토글, 딜레이 상한
- 무엇을 했는지:
  1. japaneseKeyConfig 캐시에 2초 TTL 추가 — NRIMESettings에서 변경한 설정이 NRIME에 2초 내 반영
  2. shiftDoubleTapEnabled 토글 추가 (Settings, SettingsStore, GeneralTab, ShortcutHandler)
  3. Shift+Enter 딜레이 슬라이더 상한 0.05s (50ms) + round() 표시로 49→50 정확히 표시
- 어떻게 수정했는지:
  - Settings.swift: `_configCacheTime` 추가, getter에서 2초 경과 시 캐시 무효화
  - 이유: `UserDefaults.didChangeNotification`은 같은 프로세스에서만 발동, NRIMESettings(다른 프로세스)의 변경은 감지 못함
- 수정 파일: Settings.swift, SettingsStore.swift, GeneralTab.swift, ShortcutHandler.swift, ko/en/ja Localizable.strings
- 검증: 빌드 성공, PKG 업로드

## 2026-03-26 12:15 JST | Claude Code

- 범위: TextInputGeometry 조합 중 freeze가 후보창 위치를 파괴하는 버그 수정
- 무엇을 했는지:
  1. 조합 중 `lastGoodResult` 반환 로직이 인디케이터뿐 아니라 한자/일본어 후보창 위치까지 동결시키는 문제 발견
  2. `TextInputGeometry.caretRect()`에서 조합 freeze 로직 제거 — 후보창은 항상 현재 위치 필요
  3. `InlineIndicator.updatePosition()`에만 조합 중 freeze 적용 — 인디케이터만 안정화
- 어떻게 수정했는지:
  - TextInputGeometry.swift: `isComposing && lastGoodResult` 반환 블록 삭제
  - InlineIndicator.swift: `updatePosition()` 진입 시 `markedRange` 체크 → 조합 중이면 위치 업데이트 스킵
- 수정 파일:
  - NRIME/System/TextInputGeometry.swift
  - NRIME/UI/InlineIndicator.swift
- 검증: Release 빌드 성공
- 메모:
  - 근본 원인: `caretRect()`는 인디케이터와 후보창 양쪽에서 사용되는데, 조합 중 freeze를 공유 함수에 넣어서 후보창까지 영향 받음
  - 교훈: 공유 유틸리티 함수에 특정 컴포넌트의 UX 로직을 넣지 말 것

## 2026-03-26 13:00 JST | Claude Code

- 범위: combo 단축키 좌우 모디파이어 구분 3회 수정
- 무엇을 했는지:
  1. 시도 1: NX_DEVICE* raw side flags로 비교 → 전부 안 됨 (녹화된 modifiers.rawValue에 0x100 등 예상 외 비트 포함)
  2. 시도 2: side flags 체크 제거(revert) → 사용자가 좌우 구분 필수 요구
  3. 시도 3: raw flags 대신 `activeModifierKeyCode` vs `config.modifierKeyCode` keyCode 직접 비교 → 성공 (예상)
- 어떻게 수정했는지:
  - ShortcutHandler.checkModifierKeyCombo: raw bit 비교 대신 `config.modifierKeyCode == activeModifierKeyCode` 비교
  - `activeModifierKeyCode`는 handleFlagsChanged에서 modifier 누를 때 설정됨 (0x38=LShift, 0x3C=RShift 등)
  - `config.modifierKeyCode`는 설정 UI에서 녹화 시 저장됨
- 수정 파일: NRIME/State/ShortcutHandler.swift
- 검증: 빌드 성공, PKG v1.0.7 업로드
- 메모:
  - 근본 원인: `event.modifierFlags.rawValue`에 NX_DEVICE flags 외 추가 비트(0x100 등)가 포함되어 비트마스크 비교가 불안정
  - 교훈: macOS modifier flags의 raw value에는 문서화되지 않은 비트가 포함될 수 있음. keyCode 비교가 더 안정적
  - 커밋 3개: db6c83a(추가) → 0a472d6(revert) → 1525ce7(keyCode 방식)

## 2026-03-26 13:30 JST | Claude Code

- 범위: 인디케이터 표시 안 되는 근본 원인 수정
- 무엇을 했는지:
  1. fcitx5-macos, Squirrel 리서치 → 둘 다 `attributes()`를 주요 방식으로 사용, `firstRect`는 보조
  2. NRIME은 `firstRect`를 최우선으로 사용 → 많은 앱에서 실패
  3. `isUsableCaretRect`의 screenFrame containment + corner 체크가 유효한 위치도 거부
- 어떻게 수정했는지:
  - TextInputGeometry.caretRect 순서 변경: `attributes@caret → firstRect → attributes@0 → AX`
  - `isUsableCaretRect` → `isUsableRect`로 단순화: `height > 0 && !zero`만 체크 (screen containment/corner 체크 제거)
  - InlineIndicator: caretRect nil 시 raw `firstRect(0,0)` fallback 추가
- 수정 파일:
  - NRIME/System/TextInputGeometry.swift
  - NRIME/UI/InlineIndicator.swift
- 검증: Release 빌드 성공
- 메모:
  - 근본 원인: `screenFrame(containing:)` 실패 시 모든 위치가 거부됨 → caretRect nil → 인디케이터 안 뜸
  - fcitx5는 `attributes()` 하나만으로 충분히 동작, Squirrel은 `attributes(0)` 하나만 사용
  - 교훈: 과도한 필터링이 "아무것도 안 보이는" 상황을 만듦. 최소 검증이 더 안정적

## 2026-03-26 13:52 JST | Claude Code

- 범위: 인디케이터 표시 방식 변경 + 일렉트론 깜빡임 대응
- 무엇을 했는지:
  1. `updatePosition` 완전 제거 — 커서 추적 불필요, 전환 위치에 1초 표시 후 페이드
  2. 일렉트론 앱에서 인디케이터 깜빡임 대응: `show()` 후 50ms 딜레이로 위치 재확인
- 어떻게 수정했는지:
  - NRIMEInputController.swift: `updatePosition` 호출부 제거
  - InlineIndicator.swift: `updatePosition` 메서드 삭제, `show()` 내 50ms `asyncAfter`로 위치 재확인 추가
- 수정 파일:
  - NRIME/Controller/NRIMEInputController.swift
  - NRIME/UI/InlineIndicator.swift
- 검증: Release 빌드 성공, PKG v1.0.7 빌드/업로드 완료
- 메모:
  - 인디케이터가 일렉트론에서 깜빡이는 원인: IMKit이 첫 호출에서 stale 좌표 반환 → 화면 밖 표시 → 깜빡으로 보임
  - iTerm2/Firefox는 정상, 일렉트론만 문제 — Chromium의 IMKit 지원 한계
  - 이전 worklog 시간이 틀렸던 원인: `date` 명령으로 실시간 확인하지 않고 추정 시간 사용. 앞으로 `date` 명령으로 확인 후 기록.
## 2026-03-26 14:14 JST | Claude Code

- 범위: 인디케이터 위치 AX 최우선화 + Cmd+A Electron 딜레이 + CLAUDE.md 지침 수정
- 무엇을 했는지:
  1. TextInputGeometry.caretRect()를 AX API 최우선으로 변경. 기존 4단계(attributesAtCaret → firstRect → attributesAtZero → AX)를 2단계(AX → attributesAtZero)로 단순화
  2. commitAndRepostEvent에 shiftEnterDelay 적용 — Cmd+A 등 modifier+key 조합도 Electron에서 확정 후 딜레이 적용
  3. 인디케이터 show() 후 100ms 위치 재확인 (50ms에서 증가)
  4. isUsableRect에 (0,0) 거부 + 화면 밖 거부 추가 — Firefox 좌하단 깜빡임 방지
  5. updatePosition 완전 제거 — 전환 위치 고정, 커서 추적 불필요
  6. CLAUDE.md "순조로운 구현 생략" 조항 삭제 → 모든 수정에 worklog 필수
- 어떻게 수정했는지:
  - TextInputGeometry.swift: caretRect() 재작성 — AX → attributesAtZero → lastGoodResult
  - KoreanEngine.swift: commitAndRepostEvent에 Settings.shared.shiftEnterDelay 딜레이 적용
  - JapaneseEngine.swift: 동일 수정
  - InlineIndicator.swift: updatePosition 메서드 삭제, show() 내 100ms asyncAfter 재확인 추가
  - NRIMEInputController.swift: updatePosition 호출부 제거
  - CLAUDE.md: worklog 예외 조항 삭제
- 수정 파일:
  - NRIME/System/TextInputGeometry.swift
  - NRIME/Engine/Korean/KoreanEngine.swift
  - NRIME/Engine/Japanese/JapaneseEngine.swift
  - NRIME/UI/InlineIndicator.swift
  - NRIME/Controller/NRIMEInputController.swift
  - ~/.claude/CLAUDE.md
- 검증: Release 빌드 성공, PKG v1.0.7 빌드/업로드, git push 완료
- 메모:
  - AX 최우선화 이유: IMKit의 firstRect/attributes는 조합 없을 때(영어 모드) stale 위치 반환. AX는 실제 커서 위치를 직접 가져옴.
  - AX가 모드 전환 시 1회만 호출되므로 10ms 지연은 체감 불가
  - Squirrel/fcitx5는 AX 미사용, Input Source Pro만 AX 사용 — NRIME이 오픈소스 IME 중 유일하게 AX 활용
  - Cmd+A Electron 딜레이: Shift+Enter와 동일 원리 (oldHasMarkedText), 동일 설정값 공유

## 2026-03-26 14:18 JST | Claude Code

- 범위: commitAndRepostEvent 딜레이 되돌리기 (Cmd+A 복구)
- 무엇을 했는지: commitAndRepostEvent에 추가했던 shiftEnterDelay를 제거하고 원래의 DispatchQueue.main.async로 복원
- 어떻게 수정했는지: KoreanEngine.swift, JapaneseEngine.swift에서 asyncAfter(deadline: .now() + delay) → async로 변경
- 수정 파일: NRIME/Engine/Korean/KoreanEngine.swift, NRIME/Engine/Japanese/JapaneseEngine.swift
- 검증: Release 빌드 성공, PKG v1.0.7 빌드/업로드
- 메모: CGEvent repost는 시스템 이벤트 큐를 통하므로 insertText와 다른 경로. shiftEnterDelay(15ms)를 넣으면 오히려 Cmd+A가 깨짐. 원래 async(다음 run loop)가 정상 동작.

## 2026-03-26 14:22 JST | Claude Code

- 범위: 조합 중 인디케이터 좌하단 표시 수정
- 무엇을 했는지: caretRect()에서 조합 중(markedRange.length > 0)이면 AX 조회를 건너뛰고 lastGoodResult 반환
- 어떻게 수정했는지: TextInputGeometry.swift caretRect() 상단에 markedRange 체크 추가
- 수정 파일: NRIME/System/TextInputGeometry.swift
- 검증: Release 빌드 성공, PKG v1.0.7 업로드
- 메모: 조합 중 AX가 나쁜 좌표 반환하는 원인 — forceCommit 후 앱이 아직 commit을 처리하지 않은 상태에서 AX가 구 상태(조합 중) 기준으로 위치 반환

## 2026-03-26 14:40 JST | Claude Code

- 범위: Cmd+A 조합 중 전체선택 안 되는 문제 수정
- 무엇을 했는지: commitAndRepostEvent(CGEvent repost) 방식을 commitComposing + return false 방식으로 변경
- 어떻게 수정했는지: Korean/Japanese 엔진에서 Cmd/Ctrl/Option+key 처리 시 commitComposing 후 return false로 시스템에 이벤트 위임
- 수정 파일: NRIME/Engine/Korean/KoreanEngine.swift, NRIME/Engine/Japanese/JapaneseEngine.swift
- 검증: Release 빌드 성공, PKG v1.0.7 업로드
- 메모:
  - 이전 CGEvent repost 방식이 실패한 원인 미확정 — CGEvent.post(tap: .cghidEventTap)가 조용히 실패하거나 앱이 repost된 이벤트를 무시
  - 새 방식(return false)은 IMKit이 이벤트를 앱에 직접 전달 — performKeyEquivalent 경로도 커버되는지 테스트 필요
  - 만약 return false로도 안 되면, performKeyEquivalent 경로 문제. 그 경우 commitComposing 후 Shift+Enter처럼 asyncAfter로 insertText 대신 NSApp.sendAction 사용 고려

## 2026-03-26 14:45 JST | Claude Code

- 범위: Cmd+A 조합 중 전체선택 — CGEvent repost + 딜레이로 복원
- 무엇을 했는지:
  1. return false 시도 → 실패 (performKeyEquivalent 경로라 앱에 전달 안 됨)
  2. CGEvent repost + shiftEnterDelay로 복원 — commit 후 딜레이를 줘서 앱이 확정을 처리한 뒤 Cmd+A 수신
- 어떻게 수정했는지: KoreanEngine/JapaneseEngine에서 commitComposing 후 asyncAfter(delay) → CGEvent post
- 수정 파일: NRIME/Engine/Korean/KoreanEngine.swift, NRIME/Engine/Japanese/JapaneseEngine.swift
- 검증: Release 빌드 성공, PKG v1.0.7 업로드
- 메모:
  - 이전 세션에서는 CGEvent repost(딜레이 없음)로 동작했었음
  - 이번에는 딜레이 없는 CGEvent repost가 실패 — 원인 미확정
  - shiftEnterDelay(기본 15ms) 적용으로 앱이 commit 처리할 시간 확보
  - 테스트 필요: 이 방식으로 Cmd+A가 실제로 동작하는지 사용자 확인 대기

## 2026-03-26 14:52 JST | Claude Code

- 범위: Cmd+A Electron 전용 수정 — commitComposition에서 CGEvent repost
- 무엇을 했는지:
  1. 네이티브 앱(메모)에서는 조합 중 Cmd+A가 확정+전체선택 정상 동작 확인
  2. Electron 앱에서만 실패 — macOS가 commitComposition 호출 후 Cmd+A를 전달하지만 Electron의 oldHasMarkedText가 무시
  3. commitComposition에서 wasComposing + Cmd/Ctrl 감지 시 shiftEnterDelay 후 CGEvent repost 추가
- 어떻게 수정했는지: NRIMEInputController.handleCommitComposition에서 CGEvent(source: nil)로 현재 modifier/keyCode 감지, 딜레이 후 repost
- 수정 파일: NRIME/Controller/NRIMEInputController.swift
- 검증: build_pkg.sh 성공, PKG v1.0.7 업로드. 별도 xcodebuild는 캐시 문제로 실패(PKG에는 무관)
- 메모:
  - handle()에 Cmd+A가 도달하지 않음 확인 — macOS가 performKeyEquivalent를 commitComposition으로 먼저 처리
  - CGEvent(source: nil)로 현재 눌린 키의 keyCode를 가져오는 방식 — 정확한 키를 알 수 없을 수 있어 테스트 필요
  - Korean/Japanese 엔진의 commitAndRepostEvent는 이제 불필요할 수 있음 (commitComposition에서 처리하므로)

## 2026-03-26 15:12 JST | Claude Code

- 범위: Cmd+A Electron 해결 + 인디케이터 위치 딜레이
- 무엇을 했는지:
  1. Cmd+A: commitComposition에서 repost 시도 → wasComposing=false, currentEvent=nil로 실패 확인
  2. 새 접근: flagsChanged에서 Cmd/Ctrl down 감지 시 즉시 forceCommit (preemptive commit)
  3. 인디케이터: show() 호출에 shiftEnterDelay 딜레이 추가 — AX 조회 전 앱이 commit을 처리할 시간 확보
- 어떻게 수정했는지:
  - NRIMEInputController handle(): flagsChanged에서 Cmd/Ctrl + isComposing → forceCommit
  - NRIMEInputController onModeChanged: asyncAfter(delay) → show()
  - handleCommitComposition: repost 코드 전부 제거 (불필요해짐)
- 수정 파일: NRIME/Controller/NRIMEInputController.swift
- 검증: PKG v1.0.7 빌드/업로드. Cmd+A 동작 확인 (사용자)
- 메모:
  - preemptive commit 원리: Cmd 키 down 시점에 조합 확정 → Electron이 oldHasMarkedText 초기화 → Cmd+A 도착 시 정상 처리
  - commitComposition에서는 wasComposing=false (macOS가 먼저 composition 정리) + NSApp.currentEvent=nil (이벤트 루프 외부 호출)이라 repost 불가능했음
  - 인디케이터 딜레이도 동일 원리: commit 후 AX가 정확한 위치를 반환하려면 앱의 처리 시간 필요

## 2026-03-26 15:18 JST | Claude Code

- 범위: Firefox 조합 중 인디케이터 미표시 수정
- 무엇을 했는지: attributesAtZero의 isUsableRect 검증을 완화 — x=0 허용
- 어떻게 수정했는지: isUsableRect(zeroRect) 대신 !equalTo(.zero) && height > 0 직접 체크
- 수정 파일: NRIME/System/TextInputGeometry.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모: Firefox가 조합 중 (0,y) 반환 → isUsableRect의 x==0 거부에 걸림. attributesAtZero는 원래 X를 신뢰하지 않으므로 x=0이어도 통과시킴

## 2026-03-26 15:22 JST | Claude Code

- 범위: attributesAtZero X=0 시 lastGoodResult X 사용
- 무엇을 했는지: InlineIndicator에서 attributesAtZero의 X가 0일 때 lastGoodResult.rect의 X를 fallback으로 사용
- 어떻게 수정했는지: InlineIndicator.show()에서 attributesAtZero 분기에 lastGoodCaretRect 참조 추가, TextInputGeometry에 public accessor 추가
- 수정 파일: NRIME/UI/InlineIndicator.swift, NRIME/System/TextInputGeometry.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모: Firefox 조합 중 인디케이터 미표시 + Electron x=0 플래시 모두 이 경로. lastGoodResult가 nil이면 여전히 x=0. 사용자 피드백: Firefox 조합 중 여전히 불안정, X가 좌측 끝인 경우도 있음

## 2026-03-26 15:51 JST | Claude Code

- 범위: Firefox 조합 중 인디케이터 미표시 근본 수정
- 무엇을 했는지: caretRect()의 markedRange > 0 가드 제거
- 어떻게 수정했는지: TextInputGeometry.swift에서 markedRange 체크 블록 삭제, 딜레이 50ms→shiftEnterDelay 복원
- 수정 파일: NRIME/System/TextInputGeometry.swift, NRIME/Controller/NRIMEInputController.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모:
  - 근본 원인: forceCommit 후 Firefox가 markedRange를 즉시 0으로 안 바꿈 → 가드에 걸려 lastGoodResult(nil) 반환 → 인디케이터 미표시
  - 이 가드는 firstRect/attributes가 주요 방식이었을 때 필요했지만, AX 최우선인 지금은 불필요
  - 50ms 딜레이 테스트: 효과 없음 확인 — 문제는 타이밍이 아니라 가드 로직이었음
  - 이 가드 제거로 조합 중 AX가 (0,0)이나 stale 값을 줄 가능성 있음 → 모니터링 필요

## 2026-03-26 15:57 JST | Claude Code

- 범위: AX x=0 결과가 lastGoodResult를 오염시키는 문제 수정
- 무엇을 했는지: AX 결과의 x≤1이면 lastGoodResult에 저장하지 않도록 가드 추가
- 어떻게 수정했는지: TextInputGeometry.swift caretRect()에서 AX 결과 캐싱 조건에  추가
- 수정 파일: NRIME/System/TextInputGeometry.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모: Firefox가 AX에서 x=0 반환 → lastGoodResult에 저장 → 이후 모든 인디케이터가 왼쪽 끝에 표시. x>1 가드로 방지.

## 2026-03-26 15:45 JST | Claude Code

- 범위: AX x=0 결과가 lastGoodResult를 오염시키는 문제 수정
- 무엇을 했는지: AX 결과의 x가 1 이하이면 lastGoodResult에 저장하지 않도록 가드 추가
- 어떻게 수정했는지: TextInputGeometry.swift caretRect()에서 AX 결과 캐싱 조건에 x > 1 추가
- 수정 파일: NRIME/System/TextInputGeometry.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모: Firefox가 AX에서 x=0 반환하면 lastGoodResult에 저장되어 이후 모든 인디케이터가 왼쪽 끝에 표시. x>1 가드로 오염 방지.

## 2026-03-26 16:10 JST | Claude Code

- 범위: 인디케이터 로그 분석 결과 기반 AX/attributesAtZero 수정
- 무엇을 했는지:
  1. 개발자 로그로 근본 원인 확인: AX가 100% 실패 + attributesAtZero가 Y=79153 (화면 밖) 반환
  2. AX 타임아웃 10ms → 50ms (Firefox에서 10ms는 너무 짧아 매번 타임아웃)
  3. attributesAtZero에 화면 밖 좌표 거부 추가 (NSScreen.screens.contains intersects)
- 어떻게 수정했는지:
  - TextInputGeometry.swift: AXUIElementSetMessagingTimeout 0.01 → 0.05
  - TextInputGeometry.swift: attributesAtZero 검증에 zeroOnScreen 체크 추가
- 수정 파일: NRIME/System/TextInputGeometry.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모:
  - 로그 데이터: origin=(4, 79153) → Y가 79153px로 모든 모니터 밖 → 인디케이터가 화면 위로 사라짐
  - AX 실패 원인: 10ms 타임아웃. Firefox는 AX 응답이 10ms 이상 걸림
  - 50ms 타임아웃이 모드 전환당 1회만 호출되므로 체감 지연 없음
  - lastGoodResult가 계속 nil인 이유: AX 실패 → x=0 결과만 도착 → x>1 가드로 캐시 안 됨

## 2026-03-26 16:25 JST | Claude Code

- 범위: Firefox 조합 중 인디케이터 — attributesAtCaret 추가
- 무엇을 했는지: AX와 attributesAtZero 사이에 attributesAtCaret(fcitx5-macos 방식) 추가
- 어떻게 수정했는지: TextInputGeometry.caretRect()에 caretIndex 기반 attributes 조회 추가, 디버그 로그 포함
- 수정 파일: NRIME/System/TextInputGeometry.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모:
  - 로그 분석: Firefox에서 AX가 50ms 타임아웃에서도 100% 실패 (타임아웃 문제가 아닌 AX 자체 미지원 가능성)
  - 조합 중 attributesAtZero가 Y=79611 반환 (화면 밖) → 필터됨 → 인디케이터 미표시
  - 조합 후 attributesAtZero는 정상 (4271,883) → 인디케이터 정상 표시
  - attributesAtCaret는 markedRange 끝 위치를 조회 — 조합 중에도 정확한 위치 반환 가능
  - 파이프라인: AX → attributesAtCaret → attributesAtZero → lastGoodResult

## 2026-03-26 16:40 JST | Claude Code

- 범위: 인디케이터 위치 — forceCommit 전 좌표 캡처 + activateServer 캐시 리셋
- 무엇을 했는지:
  1. shortcutAction에서 forceCommit 전에 caretRect() 호출하여 조합 중 정확한 좌표 캡처
  2. 캡처한 좌표를 setLastGoodResult로 저장 → onModeChanged에서 show() 시 사용
  3. activateServer에서 resetCache() → 텍스트 필드 전환 시 stale 좌표 방지
  4. show() 딜레이 제거 — preCommit 좌표가 이미 정확
- 어떻게 수정했는지:
  - NRIMEInputController.swift: shortcutAction에 preCommitRect 캡처 + setLastGoodResult
  - NRIMEInputController.swift: activateServer에 TextInputGeometry.resetCache()
  - NRIMEInputController.swift: onModeChanged 딜레이 제거
  - TextInputGeometry.swift: resetCache(), setLastGoodResult() 추가
- 수정 파일: NRIME/Controller/NRIMEInputController.swift, NRIME/System/TextInputGeometry.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모:
  - 핵심 발견: 후보창은 조합 중에 호출되어 정확, 인디케이터는 forceCommit 후에 호출되어 stale
  - preCommit 캡처로 후보창과 동일한 타이밍에 좌표를 잡음
  - Firefox에서 attributesAtCaret가 x=4271 반환 (다른 모니터 좌표) — Firefox IMKit 좌표 자체가 부정확

## 2026-03-26 16:55 JST | Claude Code

- 범위: 인디케이터 속도 복구 + preCommit 캡처 최적화
- 무엇을 했는지:
  1. capturePreCommitPosition: AX 없이 attributesAtCaret만 사용 (즉시 반환)
  2. AX 타임아웃 50ms → 10ms 복원 (preCommit이 조합 케이스를 처리하므로)
  3. show()의 딜레이 이미 제거됨 (이전 커밋)
- 어떻게 수정했는지:
  - TextInputGeometry: capturePreCommitPosition() 신규 메서드 — IMKit 직접 호출만
  - TextInputGeometry: AX 타임아웃 0.05 → 0.01 복원
  - NRIMEInputController: shortcutAction에서 capturePreCommitPosition 사용
- 수정 파일: NRIME/System/TextInputGeometry.swift, NRIME/Controller/NRIMEInputController.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모:
  - 느려진 원인: caretRect() 풀 파이프라인(AX 50ms 타임아웃 포함)을 preCommit + show() 두 번 호출
  - capturePreCommitPosition은 attributesAtCaret 하나만 → ~0ms
  - show()는 lastGoodResult(preCommit에서 설정)를 우선 사용, AX는 fallback으로만

## 2026-03-26 17:05 JST | Claude Code

- 범위: Firefox 인디케이터 좌하단 표시 억제
- 무엇을 했는지: 인디케이터 최종 위치가 (20, 20) 이내면 표시 안 함 (위치 실패 판정)
- 어떻게 수정했는지: InlineIndicator.show()에서 origin.x < 20 && origin.y < 20 체크 추가, return으로 표시 안 함
- 수정 파일: NRIME/UI/InlineIndicator.swift
- 검증: PKG v1.0.7 빌드/업로드
- 메모:
  - Firefox 로그 분석: attributesAtCaret가 항상 (0,0,0,0) → 실패, attributesAtZero도 불안정
  - 한국어 모드에서 특히 실패 빈도 높음 (영어는 상대적으로 나음)
  - Firefox의 IMKit character-level 위치 지원 부재 확인 — 앱 쪽 한계
  - 이 수정은 잘못된 위치에 표시되는 것보다 안 보이는 게 낫다는 판단

## 2026-03-26 17:30 JST | Claude Code

- 범위: 인디케이터 + Shift+Enter 미해결 이슈 정리 및 마무리
- 무엇을 했는지: Firefox YouTube 댓글 등 contentEditable 에디터에서의 인디케이터 위치 및 Shift+Enter 동작 이슈를 정리
- 미해결 이슈:

  ### 1. 인디케이터 위치 — contentEditable 에디터 (YouTube 댓글 등)
  - 증상: Firefox YouTube 댓글에서 한국어 모드일 때 인디케이터 미표시 또는 화면 좌하단
  - 원인: `contentEditable` div 기반 커스텀 에디터가 IMKit의 `attributes(forCharacterIndex:)`에 (0,0,0,0) 반환
  - AX API도 Firefox에서 10ms/50ms 모두 100% 실패 (Firefox AX 미지원 or 타임아웃)
  - 같은 Firefox 내에서도 Perplexity(표준 textarea)는 정상, YouTube(contentEditable)만 실패
  - 현재 대응: origin이 (20,20) 이내면 표시 억제 (잘못된 위치에 뜨는 것보다 안 뜨는 게 나음)
  - 파이프라인: AX(10ms) → attributesAtCaret → attributesAtZero(화면밖거부) → lastGoodResult
  - preCommitCapture: forceCommit 전에 attributesAtCaret로 좌표 캡처 (AX 없이 즉시 반환)
  - activateServer에서 resetCache() → 텍스트 필드 전환 시 stale 좌표 방지

  ### 2. Shift+Enter — Firefox YouTube 댓글
  - 증상: 조합 중 Shift+Enter → 확정만 되고 줄바꿈 안 됨. 두 번째 Shift+Enter → 줄바꿈 2개
  - 원인: async `insertText("\n")` (Electron 워크어라운드)가 YouTube의 contentEditable에서 무시됨
  - 첫 번째 "\n"이 버퍼되었다가 두 번째 Enter에서 함께 실행
  - Electron에서는 async 방식이 필요하지만 Firefox/네이티브에서는 `return false`가 올바른 방식
  - 해결 방향: Chromium 기반 앱(번들 ID 패턴)만 async, 나머지는 return false. 또는 런타임 감지.

  ### 3. Cmd+A — Electron (해결됨)
  - preemptive commit (Cmd key flagsChanged에서 즉시 forceCommit) 방식으로 해결
  - macOS가 commitComposition 호출 시 wasComposing=false, NSApp.currentEvent=nil이라 repost 불가 → flagsChanged에서 선제 확정

  ### 4. 인디케이터 — Electron 첫 실행
  - NRIME 재시작 직후 Electron 앱에서 인디케이터 미표시
  - 비 Electron 앱 활성화 후 정상화 (IMKit 초기화 필요)
  - IMKit 구조적 한계 — 해결 방법 미확정

- 수정 파일: worklog.md
- 메모:
  - contentEditable 에디터의 IMKit 지원 부재는 NRIME만의 문제가 아닌 macOS IME 생태계 공통 과제
  - 구름 입력기도 YouTube 댓글에서 Shift+Enter 시 글자 사라짐 보고 있었음 (사용자 증언)
  - 향후 과제: 앱/사이트별 에디터 유형 감지 및 분기 처리

## 2026-03-26 23:08 JST | Claude Code

- 범위: PerApp Shift+Enter 실험 전체 롤백
- 무엇을 했는지: 59ba22c (Chromium 감지 + 자동 분기)로 롤백. PerApp Shift+Enter 드롭다운, 클립보드/CGEvent/NSEvent/doCommand/combined 등 13개 커밋 폐기.
- 왜: Codex 앱에서 어떤 방식도 "확정+줄바꿈"을 달성 못함 — Chromium의 oldHasMarkedText 구조적 한계. PerApp UI 복잡도 대비 실효성 없음.
- 최종 상태: Chromium → insertText("\n"), 나머지 → return false. 자동 감지. 설정 UI 변경 없음.
- 수정 파일: git reset --hard 59ba22c (13 commits reverted)
- 메모:
  - Codex에서 \n은 전송, \r은 공백, CGEvent/NSEvent/clipboard 전부 확정만
  - insertText("텍스트\n") 통합도 전송
  - setMarkedText + return false도 oldHasMarkedText 트리거
  - 결론: Chromium에서 "조합 확정 + 같은 이벤트로 키 전달"은 구조적으로 불가능
