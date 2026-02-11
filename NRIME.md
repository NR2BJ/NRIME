# NRIME — All-in-One Input Method for macOS

> macOS에서 입력 소스 전환 없이 한/영/일을 하나의 입력기로 처리하는 올인원 입력기
> 완전 오프라인, 단일 입력 소스, 제로 딜레이 전환

---

## 1. 아키텍처 개요

```
┌─────────────────────────────────────────────────┐
│                macOS (InputMethodKit)            │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │       NRIMEInputController (이벤트 라우터)  │  │
│  │                                           │  │
│  │  1. SecureInputDetector → 보안 필드 감지    │  │
│  │  2. CandidatePanel → 후보 네비게이션       │  │
│  │  3. ShortcutHandler → 단축키 감지          │  │
│  │  4. Engine Routing → 모드별 엔진 분기       │  │
│  │         │                                 │  │
│  │  ┌──────┼──────────┬──────────┐           │  │
│  │  ▼      ▼          ▼          ▼           │  │
│  │ English Korean   Japanese   StateManager  │  │
│  │ Engine  Engine   Engine     (모드 관리)     │  │
│  │         │          │                      │  │
│  │         ▼          ▼                      │  │
│  │    HangulAutomata  RomajiComposer         │  │
│  │    HanjaConverter  MozcConverter          │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌──────────────────┐  ┌──────────────────────┐ │
│  │  Mozc Server      │  │  NRIMESettings       │ │
│  │  (별도 프로세스)    │  │  (SwiftUI 설정 앱)    │ │
│  │  Mach Port IPC    │  │  App Group로 설정 공유 │ │
│  └──────────────────┘  └──────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### 프로젝트 구성

| 타겟 | Bundle ID | 역할 |
|------|-----------|------|
| NRIME | `com.nrime.inputmethod.app` | IME 본체 (InputMethodKit) |
| NRIMESettings | `com.nrime.settings` | SwiftUI 설정 앱 |
| NRIMETests | — | 유닛 테스트 (86개) |

### 시스템 등록

- macOS에 **단일 입력 소스**로 등록 (smRoman 기반)
- 내부적으로 InputMode 3개 선언 (`com.nrime.en`, `com.nrime.ko`, `com.nrime.ja`)
- 키 처리는 `IMKInputController.handleEvent(_:)`로만 수행 — **CGEventTap 미사용**
- `main.swift` + `NRIMEApplication` (커스텀 NSApplication 서브클래스) 사용 (`@main` 불가)

---

## 2. 이벤트 처리 파이프라인

**파일**: `NRIME/Controller/NRIMEInputController.swift`

`handle()` 메서드의 4단계 처리 흐름:

```
NSEvent 수신
  │
  ├─ 1. SecureInputDetector → 보안 필드면 return false (시스템에 위임)
  │
  ├─ 2. CandidatePanel 표시 중 → handleCandidateNavigation()
  │     ├─ ↑↓: moveUp/moveDown
  │     ├─ ←→: pageUp/pageDown
  │     ├─ 1-9: 번호 직접 선택
  │     ├─ Enter: selectCurrentCandidate()
  │     ├─ Escape: 패널 닫기 + 변환 취소
  │     └─ 기타: 패널 닫기 → routeEvent()
  │
  ├─ 3. 일본어 변환 상태 → japaneseEngine.handleEvent() 직접 전달
  │
  └─ 4. routeEvent()
        ├─ ShortcutHandler.handleEvent() → 단축키 매칭 시 소비
        └─ 현재 모드 엔진으로 분기
            ├─ .english → EnglishEngine (passthrough)
            ├─ .korean → KoreanEngine
            └─ .japanese → JapaneseEngine
```

### selectCurrentCandidate()

후보 선택 시 모드별 처리:
- **Korean**: 한자 문자열 추출 → `insertText(replacementRange: NSNotFound)` — marked text를 한자로 교체
- **Japanese**: Mozc에 candidate index 전달 → submit → committed text 삽입 → conversion state 종료

---

## 3. 상태 관리

### StateManager (`NRIME/State/StateManager.swift`)

싱글턴으로 현재 입력 모드를 관리:
- `currentMode`: `.english` / `.korean` / `.japanese`
- `previousNonEnglishMode`: 영어 토글 시 복귀 대상 기억
- `toggleEnglish()`: 현재 모드 ↔ 영어 순환
- `switchTo(_)`: 특정 모드로 직접 전환
- 콜백: `onModeChanged`, `onStatusIconUpdate`

### InputMode (`NRIME/State/InputMode.swift`)

```swift
enum InputMode {
    case english   // label: "EN", icon: "icon_en"
    case korean    // label: "한", icon: "icon_ko"
    case japanese  // label: "あ", icon: "icon_ja"
}
```

### 앱별 모드 기억

- `activateServer()` 시 해당 앱의 저장된 모드 복원
- `deactivateServer()` 시 현재 모드 저장
- 화이트리스트/블랙리스트 방식으로 대상 앱 필터링
- `Settings.perAppSavedModes` 딕셔너리에 `[bundleId: mode.rawValue]` 저장

---

## 4. 단축키 시스템

**파일**: `NRIME/State/ShortcutHandler.swift`

### 3가지 단축키 유형

| 유형 | 예시 | 감지 방법 |
|------|------|-----------|
| 조합키 단독 탭 | Right Shift 탭 | flagsChanged에서 press→release 시간 측정 (`tapThreshold` 이내) |
| 조합키+일반키 | Right Shift+1 | keyDown에서 modifier+keyCode 조합 매칭 |
| 일반키 단독 | Caps Lock, F13 | keyDown에서 modifier 없이 keyCode 매칭 |

### 기본 단축키

| 기능 | 기본값 |
|------|--------|
| 영어 토글 | Right Shift 탭 |
| 한국어 전환 | Right Shift + 1 |
| 일본어 전환 | Right Shift + 2 |
| 한자 변환 | Option + Enter |

모든 단축키는 설정 앱에서 변경 가능. 좌/우 조합키 구분 지원.

### 탭 판정 로직 (조합키 단독 탭)

1. `flagsChanged`에서 modifier key down → `activeModifierKeyCode`, `modifierDownTime` 기록
2. 다른 키가 눌리면 → `modifierWasUsedAsCombo = true` (탭 무효화)
3. 해당 modifier key up → 경과 시간 < `tapThreshold`이고 콤보 미사용이면 → 탭으로 처리

---

## 5. 엔진 상세

### 5-1. English Engine (`NRIME/Engine/EnglishEngine.swift`)

- 모든 키 이벤트에 `return false` → 시스템에 위임 (passthrough)

### 5-2. Korean Engine (`NRIME/Engine/Korean/`)

**KoreanEngine.swift** — 한글 입력 + 한자 변환 통합 관리

**HangulAutomata.swift** — 유한 상태 머신(FSM) 기반 두벌식 오토마타:

```
상태 전이:
.empty → .onset → .onsetNucleus → .onsetNucleusCompound
                                → .onsetNucleusCoda → .onsetNucleusCompoundCoda
```

- `onset`(19종), `nucleus`(21종), `coda`(28종, 0=없음) 인덱스 추적
- 복합 모음/복합 종성 지원 (backspace 분리를 위한 first 값 기억)
- `input(jamo:)` → `HangulResult(committed:, composing:)` 반환
- `deleteBackward()` → 상태 단계적 역행
- ㄸ, ㅃ, ㅉ은 종성 불가 — 자동으로 커밋 후 새 초성 시작

**JamoTable.swift** — keyCode → 자모 매핑:
- `event.characters` 대신 하드웨어 keyCode 사용 (Electron 등 호환)
- Shift 상태에 따라 쌍자음/복합모음 구분

**HanjaConverter.swift** — SQLite 한자 사전:
- `hanja.db`에서 `SELECT hanja, meaning FROM hanja WHERE hangul = ? ORDER BY frequency DESC LIMIT 50`
- 조합 중 텍스트 또는 드래그 선택 텍스트에 대해 변환
- 선택 텍스트 한자 변환 시: `setMarkedText`로 먼저 변환 → CandidatePanel 표시 (Enter 전송 문제 방지)

### 5-3. Japanese Engine (`NRIME/Engine/Japanese/`)

2단계 상태 머신:

```
.composing (romaji 입력)  ←→  .converting (Mozc 변환)
```

**Composing 상태:**

1. 키 입력 → `charForKeyCode(keyCode)` → 소문자 알파벳 (하드웨어 keyCode 기반)
2. `RomajiComposer.input(char)` → 로마지→히라가나 변환
3. `setMarkedText`로 인라인 표시

**Converting 상태:**

1. Space/↓ → `triggerMozcConversion()` → 히라가나를 Mozc에 전송
2. Mozc가 preedit segments + candidates 반환
3. CandidatePanel 표시, ↑↓로 네비게이션
4. Enter → 확정, Escape → 취소

**RomajiComposer.swift:**
- `composedKana`: 완성된 가나 문자열
- `pendingRomaji`: 아직 미확정 로마지
- 정확 매칭 → 촉음(っ) → 접두사 매칭 순서로 해결
- `flush()` 시 끝의 "n"을 "ん"으로 변환

**Caps Lock / Shift 동작:**
- `capsLockAction` 설정: `.capsLock`(기본) / `.katakana` / `.romaji`
- `shiftKeyAction` 설정: `.none`(기본) / `.katakana` / `.romaji`
- `.katakana`: 입력 시 히라가나→가타카나 실시간 변환 표시, 커밋 시에도 가타카나로 확정
- `.romaji`: 로마지→가나 변환 바이패스, 알파벳 직접 입력
- `.capsLock`(기본): Caps Lock은 시스템 기본 동작

**일본어 IME 키 (설정 가능):**

| 키 | 기본 | 기능 |
|----|------|------|
| F6 | 0x61 | 히라가나 변환 |
| F7 | 0x62 | 전각 가타카나 |
| F8 | 0x64 | 반각 가타카나 |
| F9 | 0x65 | 전각 로마지 |
| F10 | 0x6D | 반각 로마지 |

**구두점/기호 (설정 가능):**
- `.` → `。`(일본식) 또는 `．`(서양식)
- `,` → `、` 또는 `，`
- `/` → `・`(나카구로) — 토글 가능
- `¥` → `¥`(엔 기호) — 토글 가능

---

## 6. Mozc 통합

### 프로세스 구조

```
NRIME (IME 본체)
  │  Mach Port IPC (Protobuf)
  ▼
mozc_server (별도 프로세스)
  - 앱 번들에 바이너리 내장
  - 일본어 미사용 시 미기동
  - 크래시 시 자동 재시작
```

### 구성 요소

**MozcServerManager.swift** — mozc_server 프로세스 생명주기 관리:
- `ensureServerRunning()`: 서버 미기동 시 Launch
- IPC 실패 시 서버 재시작 → 재연결
- 유휴 시 CPU 0%, 메모리 ~30-50MB

**MozcClient.swift** — 저수준 IPC:
- Mach Port로 protobuf 직렬화된 `Mozc_Commands_Command` 송수신
- `sendCommand(_:)` → `Mozc_Commands_Output` 반환

**MozcConverter.swift** — 고수준 변환 인터페이스:
- `feedHiragana(_:)`: 히라가나 문자를 하나씩 Mozc 세션에 전달
- `convert(hiragana:)`: 변환 트리거
- `sendKeyEvent(_:)`: 변환 중 키 이벤트 전달 (↑↓ 등)
- `submit()`: 현재 선택 확정, committed text 반환
- `updateFromOutput(_:)`: Mozc 출력에서 preedit/candidates/committed 추출
- `currentCandidateStrings`: CandidatePanel에 표시할 후보 목록

---

## 7. UI 컴포넌트

### CandidatePanel (`NRIME/UI/CandidatePanel.swift`)

IMKCandidates를 대체하는 커스텀 NSPanel:
- 페이지당 9개 후보 (1-9 번호 라벨 + 텍스트)
- 선택 하이라이트 (accent color 배경)
- 페이지 표시 ("1/3")
- 캐럿 근처에 자동 위치 조정
- 수동 frame 레이아웃 (Auto Layout 미사용 — 자기참조 제약 문제 방지)

**IMKCandidates 대신 커스텀 패널을 쓰는 이유:**
- IMKCandidates는 `update()` 호출 시 선택 인덱스를 무조건 0으로 리셋
- 선택 인덱스 설정 API 없음
- `interpretKeyEvents` 동작이 불투명하고 제어 불가

### InlineIndicator (`NRIME/UI/InlineIndicator.swift`)

모드 전환 시 캐럿 근처에 표시되는 부유 팝업:
- "EN" / "한" / "あ" 텍스트
- 0.5초 표시 후 0.3초 페이드아웃
- `NSWindow(level: .floating, ignoresMouseEvents: true)`
- 설정에서 ON/OFF 가능

---

## 8. 시스템 안정성

### Secure Input 감지 (`NRIME/System/SecureInputDetector.swift`)

- Carbon `IsSecureEventInputEnabled()` + NRIMESettings 앱 감지
- 보안 모드 진입 시 모든 내부 로직 바이패스, 순수 passthrough
- 사용자에게 설정 노출하지 않음

### 입력 소스 자동 복귀 (`NRIME/System/InputSourceRecovery.swift`)

- `kTISNotifySelectedKeyboardInputSourceChanged` 알림 구독
- 다른 입력 소스로 변경 감지 시 `TISSelectInputSource`로 NRIME 복귀
- 안전장치: 연속 5회 초과 시 중단, 최소 2초 간격

### 키 리매핑 프로그램 호환

- CGEventTap 미사용 → Karabiner, BetterTouchTool 등과 충돌 없음
- IMKInputController.handleEvent로 들어오는 NSEvent만 처리
- 리매핑 프로그램이 변환한 "결과물"을 받으므로 간섭 없음

---

## 9. 설정 앱 (NRIMESettings)

SwiftUI 기반 Companion App. 입력기와 별도 프로세스.
`UserDefaults(suiteName: "group.com.nrime.inputmethod")`로 설정 공유.

### 탭 구성

| 탭 | 내용 |
|----|------|
| General | 4개 단축키 레코더, 탭 임계값 슬라이더, 인라인 표시 토글 |
| Japanese | F6-F10 키 설정, Caps Lock/Shift 동작, 구두점 스타일, 기호 토글 |
| Per-App | 앱별 모드 기억 ON/OFF, 화이트리스트/블랙리스트, 앱 목록 관리 |
| About | 버전 정보 (v1.0.0), GitHub 링크 |

---

## 10. 빌드 및 설치

### 필수 의존성

| 구분 | 기술 |
|------|------|
| 메인 언어 | Swift 5.9 |
| 프레임워크 | InputMethodKit, Carbon |
| 한자 DB | SQLite3 (`libsqlite3.tbd`) |
| Mozc 통신 | SwiftProtobuf |
| 일본어 엔진 | Google Mozc (BSD 라이선스, 바이너리 번들) |
| 빌드 도구 | xcodegen + Xcode |

### 빌드 및 설치 명령

```bash
# 프로젝트 생성 + 빌드 + 설치
bash Tools/install.sh

# 수동 빌드
xcodegen generate
xcodebuild -scheme NRIME -configuration Debug build SYMROOT="$(pwd)/build"

# 테스트
xcodebuild -scheme NRIMETests -configuration Debug test SYMROOT="$(pwd)/build"
```

### 파일 구조

```
NRIME/
├── App/
│   ├── main.swift               # NSApp 엔트리포인트
│   ├── NRIMEApplication.swift   # 커스텀 NSApplication (delegate in init)
│   └── AppDelegate.swift        # IMKServer, CandidatePanel, 메뉴바
├── Controller/
│   └── NRIMEInputController.swift  # 이벤트 라우터 (핵심)
├── Engine/
│   ├── EngineProtocol.swift     # InputEngine 프로토콜
│   ├── EnglishEngine.swift      # Passthrough
│   ├── Korean/
│   │   ├── KoreanEngine.swift   # 한글 입력 + 한자 변환
│   │   ├── HangulAutomata.swift # 두벌식 FSM 오토마타
│   │   ├── JamoTable.swift      # keyCode → 자모 매핑
│   │   └── HanjaConverter.swift # SQLite 한자 사전
│   └── Japanese/
│       ├── JapaneseEngine.swift # 로마지→히라가나→Mozc 변환
│       ├── RomajiComposer.swift # 로마지→히라가나 변환기
│       ├── Mozc/
│       │   ├── MozcClient.swift        # Mach Port IPC
│       │   ├── MozcConverter.swift     # 고수준 변환 인터페이스
│       │   └── MozcServerManager.swift # 서버 생명주기 관리
│       └── Proto/                      # Mozc protobuf 정의
├── State/
│   ├── StateManager.swift       # 입력 모드 관리 싱글턴
│   ├── InputMode.swift          # 모드 enum (EN/한/あ)
│   ├── Settings.swift           # App Group UserDefaults 설정
│   └── ShortcutHandler.swift    # 3유형 단축키 감지
├── System/
│   ├── SecureInputDetector.swift    # 비밀번호 필드 감지
│   └── InputSourceRecovery.swift    # 입력 소스 자동 복귀
└── UI/
    ├── CandidatePanel.swift     # 커스텀 NSPanel 후보창
    └── InlineIndicator.swift    # 모드 전환 팝업

NRIMESettings/
├── NRIMESettingsApp.swift   # SwiftUI 앱 엔트리포인트
├── SettingsStore.swift      # ObservableObject (App Group 연동)
├── SettingsView.swift       # TabView 컨테이너
├── GeneralTab.swift         # 단축키, 인라인 표시
├── JapaneseTab.swift        # 일본어 키 설정
├── PerAppTab.swift          # 앱별 모드 기억
└── AboutTab.swift           # 버전, GitHub 링크
```
