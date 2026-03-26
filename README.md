# NRIME

한국어 | [English](README.en.md) | [日本語](README.ja.md)

macOS용 올인원 입력기. 한국어, 영어, 일본어를 **하나의 입력 소스**로 처리합니다.

- 입력 소스 전환 없이 단축키로 즉시 언어 변경
- 완전 오프라인 동작 (네트워크 불필요)
- Electron 앱 완전 지원 (VS Code, Slack, Discord 등)
- 일본어 변환은 [Google Mozc](https://github.com/google/mozc) 엔진 기반 (BSD 라이선스)
- 백그라운드 프로세스 없음 (LaunchAgent 미사용)

## 설치

[Releases](https://github.com/NR2BJ/NRIME/releases) 페이지에서 최신 `.pkg`를 다운로드하여 설치합니다.

설치 후 메뉴바에 NRIME 아이콘이 나타납니다.
보이지 않으면 로그아웃/로그인 후 **시스템 설정 → 키보드 → 입력 소스 → 편집 → +** 에서 NRIME을 추가하세요.

## 기능

### 언어 전환

두 가지 방식을 지원하며, 모든 단축키는 설정에서 자유롭게 변경하거나 **비활성화**할 수 있습니다.
선택 방식만, 토글 방식만, 또는 둘 다 조합하여 사용 가능합니다.

**선택 방식** — 원하는 언어로 바로 전환

| 기능 | 기본 단축키 |
|------|------------|
| 한국어 전환 | `Right Shift + 1` |
| 일본어 전환 | `Right Shift + 2` |

**토글 방식** — 영어 ↔ 비영어 간 전환

| 기능 | 기본 단축키 |
|------|------------|
| 영어 ↔ 이전 언어 토글 | `Right Shift` 탭 |
| 비영어 모드 토글 (한↔일) | (미설정 — 설정에서 지정) |

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
| ← / → | 문절 이동 |
| Shift + ← / → | 문절 크기 조정 |
| F6 | 히라가나 |
| F7 | 전각 가타카나 |
| F8 | 반각 가타카나 |
| F9 | 전각 로마지 |
| F10 | 반각 로마지 |
| Tab | 예측 변환 선택 |

</details>

### 추가 기능

- **Shift 더블 탭 → CapsLock 토글**: 간격 슬라이더로 조절 가능 (0.15~0.6초)
- **Shift+Enter 딜레이**: Electron 앱 호환을 위한 딜레이 조정 (기본 15ms, 5~50ms)
- **앱별 언어 기억**: 앱마다 마지막 사용 언어를 자동 기억 (화이트리스트/블랙리스트 모드)
- **인라인 모드 표시**: 커서 근처에 현재 입력 모드 표시
- **자동 업데이트**: About 탭에서 GitHub Releases 기반 업데이트 확인 및 설치
- **설정 UI 다국어**: 한국어/영어/일본어 (About 탭에서 변경, 재시작 필요)
- **설정 내보내기/가져오기**: JSON 백업으로 설정 이동
- **개발자 모드**: 진단 로그 출력 (로컬 전용, 업로드 없음)
- **ABC 입력 소스 전환 방지**: 시스템이 ABC로 전환하는 것을 방지
- **Caps Lock으로 언어 전환**: Karabiner-Elements에서 Caps Lock → F18 매핑 시 언어 전환 키로 활용 가능

## 설정

메뉴바의 NRIME 아이콘 클릭으로 설정 앱을 엽니다.

### General 탭

| 섹션 | 내용 |
|------|------|
| 단축키 | 영어 토글, 비영어 토글, 한국어 전환, 일본어 전환, 한자 변환 — 각각 커스텀 녹화/비활성화 가능 |
| 탭 임계값 | Modifier-only 탭 인식 시간 슬라이더 (0.1~0.5초) |
| Shift 더블 탭 → CapsLock | 더블 탭 인식 간격 조정 (0.15~0.6초) |
| Shift+Enter 딜레이 | Electron 앱 호환 딜레이 (5~50ms) |
| 표시 | 인라인 모드 표시, ABC 전환 방지, 후보창 폰트 크기, 변환 트리거 키 (Space/Tab/↓) |
| 개발자 모드 | 진단 로그 ON/OFF, 로그 열기/파인더에서 보기/지우기 |
| 백업 및 복원 | 설정 내보내기 (JSON) / 가져오기 |

### Japanese 탭

| 섹션 | 내용 |
|------|------|
| 변환 키 | 히라가나/전각 가타카나/반각 가타카나/전각 로마지/반각 로마지 키 커스텀 녹화 |
| 키 동작 | Caps Lock 동작 (기본/가타카나/로마지), Shift 키 동작 (없음/가타카나/로마지) |
| 스페이스 | 반각/전각 스페이스 선택 |
| 구두점 | 일본식 (。、) / 서양식 (．，), `/` → `・` 매핑, `¥` 키 → `¥` 매핑 |
| 입력 기능 | 라이브 변환, 예측 변환 |
| 변환 이력 | Mozc 변환 이력 초기화 |
| 변환 단축키 | 변환 중 키 조작 가이드 표시 |

### Per-App 탭

| 섹션 | 내용 |
|------|------|
| 앱별 언어 기억 | ON/OFF 토글 |
| 모드 | 화이트리스트 (선택한 앱만 기억) / 블랙리스트 (선택한 앱 제외) |
| 앱 목록 | 앱 추가/제거 (파일 선택) |

### About 탭

| 섹션 | 내용 |
|------|------|
| 자동 업데이트 | GitHub Releases에서 최신 버전 확인, 다운로드, 설치 |
| 언어 설정 | 설정 앱 UI 언어 변경 (한국어/English/日本語) |

## 호환성

| 환경 | 상태 |
|------|------|
| 네이티브 macOS 앱 | ✓ 정상 동작 |
| Electron 앱 (VS Code, Slack, Discord 등) | ✓ 정상 동작 |
| 키 리매핑 (Karabiner, BetterTouchTool) | ✓ 충돌 없음 |
| 비밀번호 필드 | ✓ 자동 감지, 시스템에 위임 |
| 원격 데스크톱 | ✓ 정상 동작 |
| 백그라운드 프로세스 | 없음 (LaunchAgent 미사용) |

## 제거

```bash
bash Tools/uninstall.sh
```

로그아웃/로그인하면 완전히 제거됩니다.

<details>
<summary>수동 제거</summary>

```bash
# 1. 프로세스 종료
killall NRIME NRIMESettings NRIMERestoreHelper mozc_server 2>/dev/null

# 2. 이전 버전 LaunchAgent 정리
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist 2>/dev/null
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist 2>/dev/null

# 3. 앱 삭제
rm -rf ~/Library/Input\ Methods/NRIME.app
rm -rf ~/Library/Input\ Methods/NRIMESettings.app
rm -rf ~/Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -rf /Library/Input\ Methods/NRIME.app
sudo rm -rf /Library/Input\ Methods/NRIMESettings.app
sudo rm -rf /Library/Input\ Methods/NRIMERestoreHelper.app

# 4. 이전 버전 LaunchAgent 파일 삭제
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist
rm -f ~/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist
rm -f ~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist

# 5. 설정 삭제
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null
rm -f ~/Library/Preferences/com.nrime.inputmethod.app.plist
rm -f ~/Library/Preferences/com.nrime.settings.plist
rm -f ~/Library/Preferences/group.com.nrime.inputmethod.plist

# 6. Mozc 데이터 및 로그 삭제
rm -rf ~/Library/Application\ Support/Mozc
rm -rf ~/Library/Application\ Support/NRIME

# 7. 캐시 및 컨테이너 삭제
rm -rf ~/Library/Caches/com.nrime.inputmethod.app
rm -rf ~/Library/Caches/com.nrime.settings
rm -rf ~/Library/Group\ Containers/group.com.nrime
```

> NRIMERestoreHelper와 LaunchAgent는 이전 버전에서 사용되었으며, 현재 버전에서는 설치되지 않습니다.
> 이전 버전에서 업그레이드한 경우 위 명령으로 잔여 파일을 정리할 수 있습니다.

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
| **Shift+Enter** | 텍스트 확정 → 설정 가능한 딜레이(기본 15ms) → `client.insertText("\n")` + `return true` |
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

<details>
<summary>기술 노트: Mozc IPC (Swift Mach IPC → C shim)</summary>

Swift로 Mach OOL IPC를 직접 구현했으나 빈 응답이 반환되는 문제가 발생했습니다.
원인이 bitfield 패킹인지 포인터 수명 문제인지 확정되지 않아, upstream mozc `mach_ipc.cc`와 동일한 구조의 C shim (`nrime_mozc_ipc.c`)으로 해결했습니다.
mozc_server는 LaunchAgent 없이 필요 시 자식 프로세스로 on-demand 실행됩니다.

</details>

## 라이선스

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
