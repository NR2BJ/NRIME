# NRIME

한국어 | [English](README.en.md) | [日本語](README.ja.md)

macOS용 올인원 입력기. 한국어, 영어, 일본어를 **하나의 입력 소스**로 처리합니다.

- 입력 소스 전환 없이 단축키로 즉시 언어 변경
- 완전 오프라인 동작 (네트워크 불필요)
- Electron 앱 완전 지원 (VS Code, Slack, Discord 등)
- 일본어 변환은 [Google Mozc](https://github.com/google/mozc) 엔진 기반 (BSD 라이선스)

## 설치

[Releases](https://github.com/NR2BJ/NRIME/releases) 페이지에서 최신 `.pkg`를 다운로드하여 설치합니다.

설치 후 메뉴바에 NRIME 아이콘이 나타납니다.
보이지 않으면 로그아웃/로그인 후 **시스템 설정 → 키보드 → 입력 소스 → 편집 → +** 에서 NRIME을 추가하세요.

## 사용법

### 언어 전환

두 가지 방식을 지원합니다:

**선택 방식** — 원하는 언어로 바로 전환
| 기능 | 기본 단축키 |
|------|------------|
| 한국어 전환 | `Right Shift + 1` |
| 일본어 전환 | `Right Shift + 2` |

**토글 방식** — 영어 ↔ 비영어 간 전환
| 기능 | 기본 단축키 |
|------|------------|
| 영어 ↔ 이전 언어 토글 | `Right Shift` 탭 |
| 비영어 모드 토글 | (미설정 — 설정에서 지정) |

모든 단축키는 설정에서 변경하거나 **비활성화**할 수 있습니다. 선택 방식만, 토글 방식만, 또는 둘 다 사용할 수 있습니다.

### 한국어

두벌식 자판. 한자 변환: 조합 중 `Option + Enter` (또는 텍스트 선택 후 `Option + Enter`)

### 일본어

로마지 입력 → 히라가나 실시간 변환 → `Space`로 한자 변환

```
nihongo → にほんご → Space → 日本語
```

변환 중: `↑↓` 이동, `1-9` 직접 선택, `Enter` 확정, `Escape` 취소

<details>
<summary>변환 키 상세</summary>

| 키 | 기능 |
|----|------|
| Space / Tab / ↓ | 변환 후보 표시 (각각 설정에서 ON/OFF 가능) |
| F6 | 히라가나 |
| F7 | 전각 가타카나 |
| F8 | 반각 가타카나 |
| F9 | 전각 로마지 |
| F10 | 반각 로마지 |

</details>

## 설정

메뉴바의 NRIME 아이콘 클릭으로 설정 앱을 엽니다.

| 탭 | 내용 |
|----|------|
| General | 단축키 변경/비활성화, 인라인 모드 표시, 일본어 변환 트리거 선택 (Space/Tab/↓) |
| Japanese | Caps Lock/Shift 동작, 구두점 스타일, 라이브 변환, 전각 스페이스 |
| Per-App | 앱별 마지막 사용 언어 기억 |
| Developer | 진단 로그 (로컬 전용, 업로드 없음) |

## 호환성

| 환경 | 상태 |
|------|------|
| 네이티브 macOS 앱 | 정상 동작 |
| Electron 앱 (VS Code, Slack, Discord 등) | 정상 동작 |
| 키 리매핑 (Karabiner, BetterTouchTool) | 충돌 없음 |
| 비밀번호 필드 | 자동 감지, 시스템에 위임 |

## 제거

```bash
bash Tools/uninstall.sh
```

로그아웃/로그인하면 완전히 제거됩니다.

<details>
<summary>수동 제거</summary>

```bash
killall NRIME NRIMESettings NRIMERestoreHelper mozc_server 2>/dev/null

# LaunchAgent 제거
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist 2>/dev/null
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist 2>/dev/null

# 앱 삭제
rm -rf ~/Library/Input\ Methods/NRIME.app ~/Library/Input\ Methods/NRIMESettings.app ~/Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -rf /Library/Input\ Methods/NRIME.app /Library/Input\ Methods/NRIMESettings.app /Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist

# 설정/데이터 삭제
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null
rm -rf ~/Library/Application\ Support/Mozc ~/Library/Caches/com.nrime.inputmethod.app ~/Library/Caches/com.nrime.settings ~/Library/Group\ Containers/group.com.nrime
```

</details>

<details>
<summary>소스 빌드 (개발자용)</summary>

**요구 사항:** macOS 13.0+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/NR2BJ/NRIME.git
cd NRIME
bash Tools/build_pkg.sh
# 결과: build/NRIME-<version>.pkg
```

</details>

<details>
<summary>기술 노트: Electron/Chromium IME 워크어라운드</summary>

Electron/Chromium 기반 앱에서 IME 조합 중 modifier+key 입력 시 텍스트가 유실되는 문제의 원인과 해결 방법입니다. 이 워크어라운드는 네이티브 앱에서도 동일하게 적용되며 부작용 없습니다.

### 근본 원인

**Shift+Enter**: macOS `StandardKeyBinding.dict`에 Shift+Return 바인딩이 없어서, Chromium이 `insertText:"\n"`을 호출할 때 `oldHasMarkedText` 추적 로직이 IME 조합 이벤트로 오판하여 확정 텍스트를 유실시킵니다.

**Cmd+key**: `performKeyEquivalent:` 경로를 타기 때문에 IMKit에서 `return false`로는 이벤트를 앱에 전달할 수 없습니다.

### 해결 방법

| 상황 | 방법 |
|------|------|
| **Shift+Enter** | 텍스트 확정 → 10ms 딜레이 → `client.insertText("\n")` + `return true` |
| **Cmd+A/C/V/X/Z** | 텍스트 확정 → tagged CGEvent repost via `.cghidEventTap` + `return true` |

### 시도했지만 실패한 접근법

| 접근법 | 이유 |
|--------|------|
| `insertText + return false` | Chromium `oldHasMarkedText` 오판 |
| `setMarkedText("") + insertText + return false` | 동일 원인 |
| 동기 `insertText("\n")` | Chromium IPC 배치 처리로 무시 |
| `CGEvent.post(.cgAnnotatedSessionEventTap)` | Electron이 해당 탭의 이벤트 무시 |
| `CGEventPostToPSN` (deprecated) | Electron이 PSN 직접 전달 무시 |
| `NSAppleScript (System Events)` | IME에서 Automation TCC 불가 |

</details>

## 라이선스

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
