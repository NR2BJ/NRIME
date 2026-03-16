# NRIME

한국어 | [English](README.en.md) | [日本語](README.ja.md)

macOS용 올인원 입력기. 한국어, 영어, 일본어를 **하나의 입력 소스**로 처리합니다.

- 입력 소스 전환 없이 단축키로 즉시 언어 변경
- 완전 오프라인 동작 (네트워크 불필요)
- 일본어 변환은 [Google Mozc](https://github.com/google/mozc) 엔진 사용 (BSD 라이선스)
- Electron 앱 완전 지원 (VS Code, Slack, Discord, Claude for Desktop 등)

## 설치

### PKG 설치 (권장)

[Releases](https://github.com/NR2BJ/NRIME/releases) 페이지에서 최신 `.pkg` 파일을 다운로드하여 더블클릭으로 설치합니다.

설치 후 NRIME이 메뉴바에 나타납니다.
나타나지 않으면 로그아웃/로그인 후 **시스템 설정 → 키보드 → 입력 소스 → 편집 → +** 에서 NRIME을 추가하세요.

### 소스 빌드 설치

<details>
<summary>개발자용</summary>

**요구 사항:**
- macOS 13.0 (Ventura) 이상
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
git clone https://github.com/NR2BJ/NRIME.git
cd NRIME
bash Tools/install.sh
```

PKG 빌드:
```bash
bash Tools/build_pkg.sh
# 결과: build/NRIME-<version>.pkg
```

</details>

### 제거

```bash
bash Tools/uninstall.sh
```

로그아웃/로그인하면 완전히 제거됩니다.

<details>
<summary>수동 제거</summary>

```bash
killall NRIME NRIMESettings mozc_server 2>/dev/null
sudo rm -rf ~/Library/Input\ Methods/NRIME.app ~/Library/Input\ Methods/NRIMESettings.app \
  /Library/Input\ Methods/NRIME.app /Library/Input\ Methods/NRIMESettings.app
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null
rm -rf ~/Library/Application\ Support/Mozc \
  ~/Library/Caches/com.nrime.inputmethod.app \
  ~/Library/Caches/com.nrime.settings \
  ~/Library/Group\ Containers/group.com.nrime
```

</details>

## 기본 단축키

| 기능 | 기본 단축키 |
|------|------------|
| 영어 ↔ 이전 언어 토글 | `Right Shift` 탭 |
| 한국어 전환 | `Right Shift + 1` |
| 일본어 전환 | `Right Shift + 2` |
| 한자 변환 | `Option + Enter` |

모든 단축키는 설정 앱에서 변경할 수 있습니다. 좌/우 Shift, Ctrl, Option, Cmd를 각각 구분합니다.

## 사용법

### 영어

시스템 키보드와 동일하게 동작합니다 (passthrough).

### 한국어

두벌식 자판. 입력 중인 글자는 밑줄로 표시되며, 다음 글자 입력 시 자동 확정됩니다.

**한자 변환:**
- 조합 중인 글자에서 `Option + Enter` → 후보창 표시
- 또는 텍스트를 드래그로 선택한 뒤 `Option + Enter`
- `↑↓` 이동, `1-9` 번호 선택, `Enter` 확정

### 일본어

로마지 입력 → 히라가나 실시간 변환 → Space로 한자 변환.

```
입력: nihongo → にほんご → Space → 日本語
```

**변환 흐름:**
1. 로마지 타이핑 → 히라가나로 실시간 표시 (라이브 변환 지원)
2. `Space` 또는 `↓` → 변환 후보 표시
3. `↑↓` 로 후보 이동, `1-9`로 직접 선택
4. `Enter` 확정, `Escape` 취소

**Shift / Caps Lock 동작 (설정에서 변경 가능):**

| 설정 | 동작 |
|------|------|
| Katakana | 해당 키를 누른 상태에서 타이핑하면 가타카나로 입력 |
| Romaji | 해당 키를 누른 상태에서 타이핑하면 로마지 직접 입력 |

**변환 키 (조합 중 사용):**

| 키 | 기능 |
|----|------|
| F6 | 히라가나 |
| F7 | 전각 가타카나 |
| F8 | 반각 가타카나 |
| F9 | 전각 로마지 |
| F10 | 반각 로마지 |

## 설정

메뉴바의 NRIME 아이콘을 클릭하면 설정 앱이 열립니다.

| 탭 | 내용 |
|----|------|
| General | 단축키 변경, 인라인 모드 표시 ON/OFF, 진단 로그 |
| Japanese | F6-F10 키 설정, Caps Lock/Shift 동작, 구두점 스타일, 라이브 변환 |
| Per-App | 앱별로 마지막 사용 언어 기억 (화이트리스트/블랙리스트) |
| About | 버전 정보 |

## 호환성

| 환경 | 상태 |
|------|------|
| 네이티브 macOS 앱 (Safari, TextEdit, Notes 등) | 정상 동작 |
| Electron 앱 (VS Code, Slack, Discord, Claude for Desktop) | 정상 동작 (워크어라운드 적용) |
| 키 리매핑 (Karabiner-Elements, BetterTouchTool) | 충돌 없음 (CGEventTap 미사용) |
| 원격 데스크톱 | 정상 동작 |
| 비밀번호 필드 | 자동 감지, 시스템에 위임 |

## 기술 노트: Electron/Chromium IME 워크어라운드

<details>
<summary>IME 개발자용 참고 자료</summary>

Electron/Chromium 기반 앱에서 IME 조합 중 modifier+key 입력 시 텍스트가 유실되는 문제의 원인과 해결 방법입니다. 이 워크어라운드는 네이티브 앱에서도 동일하게 적용되며 부작용 없습니다.

### 근본 원인

**Shift+Enter**: macOS `StandardKeyBinding.dict`에 Shift+Return 바인딩이 없습니다. Return은 `insertNewline:`으로 매핑되지만, Shift+Return은 매핑이 없어서 Chromium의 `interpretKeyEvents:`가 `doCommandBySelector:` 대신 `insertText:"\n"`을 호출합니다. 이때 Chromium 내부의 `oldHasMarkedText` 추적 로직이 해당 이벤트를 IME 조합 이벤트로 오판하여 fake `VKEY_PROCESSKEY`(0xE5)를 생성하고, 확정된 텍스트가 유실됩니다.

**Cmd+key**: `performKeyEquivalent:` 경로를 타기 때문에 IMKit에서 `return false`로는 이벤트를 앱에 전달할 수 없습니다.

### 해결 방법

| 상황 | 방법 | 이유 |
|------|------|------|
| **Shift+Enter** | 텍스트 확정 후 10ms 딜레이를 두고 `client.insertText("\n")`, `return true` | key event를 보내지 않으므로 `interpretKeyEvents:` 경로를 완전 회피. 딜레이는 Chromium IPC 처리 시간 확보용 (5ms 이하 race condition, 10ms 안정) |
| **Cmd+A/C/V/X/Z** | 텍스트 확정 후 tagged CGEvent repost via `.cghidEventTap`, `return true` | `eventSourceUserData`에 repost tag를 설정하여 컨트롤러가 재진입을 감지하고 `return false`로 통과시킴. `performKeyEquivalent:` 경로는 `oldHasMarkedText` 문제 없음 |

### 시도했지만 실패한 접근법

| 접근법 | 결과 | 이유 |
|--------|------|------|
| `insertText + return false` | 텍스트 유실 + 줄바꿈 | Chromium `oldHasMarkedText` 오판 |
| `setMarkedText("") + insertText + return false` | 텍스트 유실 + 줄바꿈 | 동일 원인 |
| `flush() only + return false` | 텍스트 유실 + 스페이스 | composing text 미확정 |
| `insertText(text + "\n")` | 커서 고착 | Chromium 내부 상태 불일치 |
| `CGEvent.post(.cgAnnotatedSessionEventTap)` | 확정만, 동작 없음 | Electron이 해당 탭의 이벤트 무시 |
| `CGEventPostToPSN` | 확정만, 동작 없음 | Electron이 PSN 직접 전달 무시 |
| `NSAppleScript (System Events)` | 권한 오류 -1743 | IME 프로세스에서 Automation TCC 불가 |
| `NSApp.sendAction(selectAll:)` | 확정만, 동작 없음 | IME 프로세스의 responder chain으로 전달됨 |
| 동기 `client.insertText("\n")` | 확정만, 줄바꿈 없음 | Chromium이 IPC 배치 처리로 무시 |

### 다른 IME들의 접근

Squirrel(RIME), fcitx5-macos, Google Mozc 등 다른 macOS IME들은 "commit + return false" 패턴을 사용하지 않습니다. 키를 내부에서 처리하고 `return true`를 반환하거나, 처리하지 않는 키는 조합 없이 `return false`를 반환합니다.

</details>

## 라이선스

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
