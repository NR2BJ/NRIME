# NRIME 마스터플랜 v2.1

> **프로젝트 목표**: macOS에서 입력 소스 전환 없이 한/영/일을 하나의 입력기로 처리하는 올인원 입력기
> **핵심 원칙**: 완전 오프라인, 단일 입력 소스, 제로 딜레이 전환

---

## 1. 아키텍처

```
┌─────────────────────────────────────────────────┐
│                macOS (InputMethodKit)            │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │         NRIME (단일 입력 소스)          │  │
│  │                                           │  │
│  │  ┌─────────────┐                          │  │
│  │  │ StateManager │ ← 언어 모드 관리         │  │
│  │  │  (뇌/컨트롤러) │   앱별 모드 기억         │  │
│  │  └──────┬──────┘   단축키 처리             │  │
│  │         │                                 │  │
│  │  ┌──────┼──────────────┬──────────┐       │  │
│  │  ▼      ▼              ▼          ▼       │  │
│  │ English  Korean      Japanese   Inline    │  │
│  │ Engine   Engine      Engine     Indicator │  │
│  │ (Pass-   (Swift      (Mozc      (캐럿 근처  │  │
│  │  through) 자체구현)    IPC)       팝업)     │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Mozc Server (별도 프로세스)                  │  │
│  │  - 앱 번들에 내장, 필요시에만 기동             │  │
│  │  - Unix Domain Socket / XPC 통신            │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Companion App (별도 프로세스)                │  │
│  │  - SwiftUI 설정 창                          │  │
│  │  - 메뉴바 아이콘 클릭으로 직접 실행            │  │
│  │  - UserDefaults(suiteName:)으로 설정 공유    │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### 시스템 등록 방식

- macOS에는 **단 하나의 입력 소스**로 등록 (smRoman 기반)
- 내부적으로 InputMode를 여러 개 선언 (`com.nrime.en`, `com.nrime.ko`, `com.nrime.ja`)
  - 외부에서 보이는 입력 소스는 하나지만, 앱별 언어 모드 기억이 가능해짐
- 키 처리는 오직 `IMKInputController.handleEvent(_:)` 로만 수행
  - **CGEventTap (전역 키 후킹) 절대 사용 금지** → 키 리매핑/모니터링 프로그램과 충돌 방지

---

## 2. 엔진 상세

### 2-1. English Engine (Passthrough)

- 키 코드를 그대로 `insertText`로 전달
- Secure Input (비밀번호) 모드 처리:
  - `NSTextInputClient` 보안 모드 감지 + `IsSecureEventInputEnabled()` (Carbon) 이중 체크
  - 보안 모드 진입 시 내부 로직 무시, 순수 Passthrough
- Secure Input 및 입력 소스 자동 복귀는 내부적으로만 처리 (사용자에게 설정 노출하지 않음)

### 2-2. Korean Engine (Swift 자체 구현)

- **지원 배열**: 두벌식
- **핵심 로직**: 유한 상태 머신(FSM) 기반 한글 오토마타
  - 초성 → +중성 → +종성 → 다음 글자 초성 분리 등 상태 전이
  - Swift로 수백 줄 규모, 외부 의존성 없음
- **한자 변환**: 한글→한자 매핑 테이블을 SQLite DB로 관리
  - 설정에서 지정한 단축키 입력 시 `IMKCandidates` (macOS 기본 후보창) 호출
- **포커스 이동 시**: `deactivateServer` 에서 조합 중인 글자 강제 commit (구름 입력기 버그 방지)

### 2-3. Japanese Engine (Mozc IPC)

- **Mozc Server를 별도 프로세스로 실행**, 앱 번들에 바이너리 내장
- **통신**: Unix Domain Socket 또는 XPC
  - 입력기 → Mozc: 변환 요청 (로마자 → 히라가나 → 한자 변환)
  - Mozc → 입력기: 변환 후보 리스트 반환
- **크래시 격리**: Mozc가 죽어도 입력기 본체는 영향 없음, 자동 재시작
- **리소스**: 유휴 시 CPU 0%, 메모리 약 30~50MB, 일본어 미사용 시 미기동
- **빌드**: Bazel로 Mac용 정적 빌드 (일회성), BSD 라이선스로 재배포 가능

**일본어 입력 흐름:**
1. 로마자 입력 → 히라가나 실시간 변환 (인라인 표시)
2. Space → Mozc에 변환 요청 → 후보 표시
3. Enter → 확정
4. 화살표 키 → 문절(文節) 단위 이동 (Mozc 세그먼트 API 활용)

**모드 전환 (일본어 내부):**
- Caps Lock: 가타카나 고정 모드 토글
- 기타 세부 전환은 설정에서 커스텀 가능

---

## 3. 단축키 시스템

### 기본 구조

| 기능 | 기본값 | 설명 |
|------|--------|------|
| 영어 토글 | Right Shift 탭 | 현재 언어 ↔ 영어 전환 (순환 아님) |
| 한국어 전환 | Right Shift + 1 | 한국어 즉시 전환 |
| 일본어 전환 | Right Shift + 2 | 일본어 즉시 전환 |

위 기본값은 모두 사용자가 Companion App에서 자유롭게 변경 가능.

### 완전 커스텀 단축키

- **어떤 키 조합이든 제한 없이 수용** (Right Shift+A, Caps Lock, F13, Right Ctrl 등)
- **좌/우 조합키 구분 필수** (`NSEvent.modifierFlags` rawValue로 좌/우 판별)
  - 예: Left Shift와 Right Shift를 별개 키로 인식
- GUI에서 "단축키 입력" 필드 클릭 → 원하는 키 누르면 그대로 등록되는 방식

### 임계값 자동 판별

설정한 단축키의 유형에 따라 임계값 필요 여부를 자동으로 판별:

| 단축키 유형 | 예시 | 임계값 | 이유 |
|---|---|---|---|
| 조합키 단독 탭 | Right Shift, Right Ctrl, Right Cmd | ✅ 필요 (슬라이더 활성화) | 조합키+다른키 동작과 구분 필요 |
| 조합키+일반키 | Right Shift+A, Ctrl+Space | ❌ 불필요 (숨김) | 조합이 명확하여 판정 불필요 |
| 일반키 단독 | Caps Lock, F13 | ❌ 불필요 (숨김) | 조합키가 아니므로 판정 불필요 |

- 임계값 슬라이더: 0.1~0.5초, 기본 0.2초
- "조합키 단독 탭" 유형일 때만 자동으로 슬라이더가 나타남

### 탭 판정 로직 (조합키 단독 탭 유형일 때)

1. KeyDown 시 타임스탬프 기록
2. KeyDown 후 다른 키가 눌리면 → 즉시 "조합 키 사용"으로 확정 (입력기가 이벤트 소비 안 함)
3. 해당 키의 KeyUp만 단독으로 오고, 경과 시간 < 임계값이면 → 탭으로 처리 (언어 전환)

---

## 4. UX 기능

### 4-1. 인라인 표시 (Inline Indicator)

- 언어 전환 시 캐럿(커서) 근처에 작은 팝업 표시 ("한" / "EN" / "あ")
- 0.5초 후 페이드아웃
- `NSWindow(level: .floating, ignoresMouseEvents: true)` 로 구현
- 설정에서 ON/OFF 가능

### 4-2. 메뉴바 아이콘

- 통합 아이콘 하나 (현재 언어에 따라 아이콘/텍스트 변경)
- **클릭 시 바로 Companion App (설정 창) 실행** (드롭다운 메뉴 없음)

---

## 5. 설정 (Companion App)

별도 SwiftUI 앱으로 구현. 입력기 프로세스와 분리되어 안정성에 영향 없음.
설정값은 `UserDefaults(suiteName:)` (App Group)으로 공유.

### 탭 구성

#### 탭 1: 일반
- **단축키 설정**
  - 영어 토글 키 (기본: Right Shift 탭)
  - 한국어 전환 키 (기본: Right Shift + 1)
  - 일본어 전환 키 (기본: Right Shift + 2)
  - 한자 변환 키 (기본: Option + Enter)
  - 각 항목: 클릭 → 키 입력으로 등록, 좌/우 조합키 구분 표시
  - 조합키 단독 탭 유형 감지 시 임계값 슬라이더 자동 표시 (0.1~0.5초)
- **인라인 표시 ON/OFF** (기본: ON)

#### 탭 2: 일본어
- 가타카나 전환 키 설정
- Mozc 사용자 사전 관리
- 예측 변환 ON/OFF

#### 탭 3: 앱별 언어 모드
- **기능 ON/OFF 토글** (기본: OFF)
- **모드 선택**: 화이트리스트 / 블랙리스트
  - 화이트리스트: 선택한 앱에서만 언어 모드 기억
  - 블랙리스트: 선택한 앱을 제외하고 모두 기억
- **앱 목록 관리**: 추가/삭제, 앱 선택 UI

#### 탭 4: 정보
- 버전 정보
- 업데이트 확인 (Sparkle)
- 사용법 간단 안내

---

## 6. 안정성 및 호환성

### Secure Input (비밀번호 필드) — 내부 처리

- `NSTextInputClient` 보안 모드 + `IsSecureEventInputEnabled()` 이중 감지
- 감지 시 모든 내부 로직 바이패스, 키 코드 그대로 Passthrough
- 사용자에게 설정으로 노출하지 않음

### 입력 소스 자동 복귀 — 내부 처리

- `DistributedNotificationCenter`에서 `kTISNotifySelectedKeyboardInputSourceChanged` 구독
- 다른 입력 소스로 변경 감지 시 `TISSelectInputSource`로 복귀
- 연속 크래시 시 중단 안전장치 포함
- 사용자에게 설정으로 노출하지 않음

### 키 리매핑/모니터링 프로그램 호환

- **CGEventTap 미사용**이 핵심
- `IMKInputController.handleEvent(_:)`로 들어오는 NSEvent만 처리
- 키 리매핑 프로그램(Karabiner, BetterTouchTool, Keyboard Maestro 등)이 키를 변환해서 보내도, 입력기는 "결과물"만 받으므로 충돌 없음
- 원격 데스크톱 앱과도 동일한 원리로 호환
- Right Shift+1 등의 단축키는 `handleEvent` 내에서 처리 후 이벤트를 소비하므로, 시스템에 !/@등이 전달되지 않음

---

## 7. 개발 로드맵 (Phase)

### Phase 1: 기반 구축 — "안 죽는 영어 입력기"
- Xcode 프로젝트 생성 (Input Method 템플릿)
- Info.plist 설정 (단일 입력 소스, InputMode 선언)
- Secure Input Passthrough 구현
- 이벤트 기반 입력 소스 복귀 구현
- **목표**: 시스템에서 제거되지 않고, 영어 입력이 완벽히 되는 상태

### Phase 2: 한국어 엔진
- Swift 한글 오토마타 (두벌식 FSM) 구현
- 한자 변환 (SQLite DB + IMKCandidates)
- 포커스 이동 시 강제 commit
- 기본 단축키로 한/영 전환
- **목표**: 한/영 전환이 완벽히 되는 입력기 (이것만으로도 실사용 가능)

### Phase 3: 모드 전환 및 UX
- StateManager 완성 (3개 국어)
- 단축키 시스템 구현 (커스텀 단축키, 좌/우 구분, 임계값 자동 판별)
- 인라인 표시 (Inline Indicator)
- 메뉴바 아이콘 (클릭 → 설정 앱 실행)
- 앱별 언어 모드 기억 (화이트리스트/블랙리스트)

### Phase 4: 일본어 엔진 (Mozc)
- Mozc Mac 빌드 (Bazel, 일회성)
- IPC 통신 레이어 (Unix Domain Socket / XPC)
- Swift ↔ Objective-C++ ↔ C++ 브릿지
- 로마자→히라가나 변환, 변환 후보 UI
- 가타카나 모드, 문절 이동
- Mozc 프로세스 자동 기동/종료/크래시 복구

### Phase 5: Companion App (설정)
- SwiftUI 설정 창 구현 (4개 탭)
- App Group UserDefaults 연동
- 단축키 커스텀 UI (키 입력 캡처, 좌/우 구분 표시, 임계값 자동 판별)
- 앱별 모드 기억 UI (화이트리스트/블랙리스트)
- Mozc 사용자 사전 관리 UI

### Phase 6: 마무리 및 배포
- 전체 통합 테스트
- Companion App에 Sparkle 프레임워크 탑재 (자동 업데이트)
- 설치/제거 스크립트
- README 및 사용 가이드

---

## 8. 기술 스택 요약

| 구분 | 기술 |
|------|------|
| 메인 언어 | Swift |
| Mozc 브릿지 | Objective-C++ |
| 프레임워크 | InputMethodKit (macOS SDK) |
| 한국어 엔진 | Swift 자체 구현 (FSM 오토마타) |
| 일본어 엔진 | Google Mozc (BSD, IPC 별도 프로세스) |
| 한자 DB | SQLite |
| 설정 앱 | SwiftUI (Companion App) |
| 자동 업데이트 | Sparkle |
| 빌드 도구 | Xcode (메인), Bazel (Mozc) |
| 네트워크 | 불필요 (완전 오프라인) |

---

## 9. 예상 결과물

- **메뉴바**: 아이콘 하나 (현재 언어에 따라 변경, 클릭 시 설정 앱 실행)
- **속도**: 단축키 누르는 순간 딜레이 없이 즉시 전환
- **안정성**: 비밀번호 입력 시 시스템 개입 없음, 재부팅 후에도 유지
- **한국어**: 순정 두벌식과 동일한 타이핑 경험 + 한자 변환
- **일본어**: Google 일본어 입력 수준의 변환 품질, 완전 오프라인
- **단축키**: 어떤 키 조합이든 자유롭게 설정, 좌/우 조합키 구분
- **설정**: macOS 네이티브 느낌의 SwiftUI 설정 앱
- **호환성**: Karabiner, BetterTouchTool 등 키 리매핑 프로그램과 충돌 없음
