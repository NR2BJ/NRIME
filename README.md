# NRIME

한국어 | [English](README.en.md) | [日本語](README.ja.md)

macOS용 올인원 입력기. 한국어, 영어, 일본어를 **하나의 입력 소스**로 처리합니다.

- 입력 소스 전환 없이 단축키로 즉시 언어 변경
- 입력과 변환은 모두 이 Mac 안에서 처리 (입력한 내용은 밖으로 나가지 않음, 네트워크는 GitHub 업데이트 확인에만 사용)
- Electron 앱 완전 지원 (VS Code, Slack, Discord 등)
- 일본어 변환은 [Google Mozc](https://github.com/google/mozc) 엔진 기반 (BSD 라이선스)
- 백그라운드 프로세스 없음 (LaunchAgent 미사용)

## 설치

[Releases](https://github.com/NR2BJ/NRIME/releases) 페이지에서 최신 `.pkg`를 다운로드하여 설치합니다.

설치 후 메뉴바에 NRIME 아이콘이 나타납니다.
보이지 않으면 로그아웃/로그인 후 **시스템 설정 → 키보드 → 입력 소스 → 편집 → +** 에서 NRIME을 추가하세요.

## 기능

### 언어 전환

두 단축키로 언어를 바꿉니다. 둘 다 설정에서 자유롭게 변경하거나 **비활성화**할 수 있습니다.

| 기능 | 기본 단축키 |
|------|------------|
| 영어 전환 (영어 ↔ 이전 언어) | `Right Shift` 탭 |
| 비영어 모드 전환 (한국어 ↔ 일본어) | `Shift + Space` |

### 한국어

두벌식 자판. 한자 변환: 조합 중 `Option + Enter` (또는 텍스트 선택 후 `Option + Enter`)

### 일본어

로마자 입력 → 히라가나 조합 → `Space`로 한자 변환

```
nihongo → にほんご → Space → 日本語
```

변환 중: `↑↓` 이동, `1-9` 직접 선택, `Enter` 확정, `Escape` 취소

<details>
<summary>변환 키 상세</summary>

| 키 | 기능 |
|----|------|
| Space / Tab | 변환 시작 (조합 중 — 각각 설정에서 ON/OFF 가능) |
| ↑ / ↓ | 후보 탐색 |
| ← / → | 문절 이동 (문절이 하나면 후보 페이지 넘김) |
| Shift + ← / → | 문절 길이 조절 |
| 1 – 9 | 번호로 후보 확정 |
| Tab | 후보 펼치기 / 접기 (후보창이 떠 있을 때) |
| Enter | 변환 확정 |
| Escape | 변환 취소 |

</details>

### 추가 기능

- **인라인 모드 표시**: 모드를 바꿀 때 입력 커서(또는 마우스 커서) 근처에 현재 입력 모드 표시
- **일본어 사용자 사전**: 읽기·단어·품사를 직접 등록해 변환 후보에 추가 (일본어 탭 → 사용자 사전)
- **자동 업데이트**: 정보 탭에서 GitHub Releases 기반 업데이트 확인 및 설치 (정식/베타 채널 선택)
- **설정 UI 다국어**: 한국어/영어/일본어 (정보 탭에서 변경, 바로 적용)
- **설정 내보내기/가져오기**: JSON 백업으로 설정 이동
- **개발자 모드**: 진단 로그 출력 (로컬 전용, 업로드 없음)
- **ABC 입력 소스 전환 방지**: 시스템이 ABC로 전환하는 것을 방지
- **암호 입력 시 영문 자판으로 전환**: 암호 입력란처럼 macOS가 보안 입력을 켠 동안 영문(ABC) 자판으로 바꿨다가, 끝나면 되돌림 (기본 켜짐)
- **빠른 탭 전환 보정 (실험적)**: Shift 탭 직후 너무 빨리 타이핑해 쌍자음/대문자가 나오는 문제 보정 (기본 꺼짐)
- **Caps Lock으로 언어 전환**: Karabiner-Elements에서 Caps Lock → F18 매핑 시 언어 전환 키로 활용 가능

## 설정

메뉴바의 NRIME 아이콘 클릭으로 설정 앱을 엽니다.

### 일반 탭

| 섹션 | 내용 |
|------|------|
| 단축키 | 영어 전환, 비영어 모드 전환, 한자 변환 — 각각 기록(새 키 지정)/지우기(비활성화) 가능 |
| 탭 인식 시간 | 보조 키 단독 탭으로 인식하는 최대 시간 슬라이더 (0.1~0.5초) |
| 빠른 탭 전환 보정 (실험적) | Shift 탭 직후 빠르게 친 글자가 쌍자음/대문자로 나오는 문제 보정 (기본 꺼짐), 판정 시간 슬라이더 (30~80ms) |
| 표시 | 모드 전환 시 인라인 표시기 보기 (인디케이터 위치: 입력 커서 위치/마우스 커서 위치), ABC로 전환 방지, 암호 입력 시 영문 자판으로 전환, 후보 글꼴 크기 (12~24pt) |
| 입력기 권한 | 기기 제어 및 데이터 접근(macOS 26 이하: 손쉬운 사용) 허용 상태, 다시 확인 / 권한 요청, 시스템 설정 열기 — 조합 확정 뒤 ⌘+키나 Codex의 Shift+Enter를 앱에 다시 보낼 때 필요 |
| 개발자 | 개발자 모드 활성화 (진단 로그), 로그 열기/Finder에서 보기/로그 지우기 |
| 백업 및 복원 | 설정 내보내기 (JSON) / 가져오기 |

### 일본어 탭

위쪽에서 **설정**과 **사용자 사전** 페이지를 오갑니다.

**설정**

| 섹션 | 내용 |
|------|------|
| 변환 트리거 키 | Space, Tab — 조합 중 변환을 시작할 키 (각각 ON/OFF) |
| 키 동작 | Caps Lock 동작 — Caps Lock (기본)/가타카나로 변환/로마자로 변환 |
| 스페이스 | 스페이스 너비 — 반각 (U+0020)/전각 (U+3000), 조합 중이 아닐 때 적용 |
| 구두점 및 기호 | 구두점 스타일 — 일본어 (。、)/전각 서양식 (．，)/반각 서양식 (.,), 입력 예 미리보기, `/` 키 → `・` (나카구로), `\` 키 → `¥` (엔 기호) |
| 변환 엔진 (Mozc) | 지금 쓰는 Mozc 버전, 새 Mozc 확인·바로 적용 |
| 변환 이력 | Mozc 변환 이력 초기화 |
| 변환 단축키 | 변환 중 키 조작 가이드 표시 |

**사용자 사전**

| 항목 | 내용 |
|------|------|
| 단어 목록 | 읽기(히라가나)·단어·품사·코멘트, 검색 |
| 편집 | `+`로 추가, 더블 클릭으로 편집, `−`로 삭제 |
| 자동 학습 | 자동 학습된 변환은 목록에 나오지 않음 — 설정 페이지의 변환 이력 지우기로 초기화 |

### 정보 탭

| 섹션 | 내용 |
|------|------|
| 버전 | 현재 버전, GitHub 링크 |
| 자동 업데이트 | GitHub Releases에서 최신 버전 확인, 다운로드, 설치 |
| 업데이트 채널 | 정식/베타 (베타는 테스트 빌드를 먼저 받음) |
| 언어 | 설정 앱 UI 언어 변경 (한국어/English/日本語) |

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

**요구 사항:** macOS 13.0+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen), [bazelisk](https://github.com/bazelbuild/bazelisk) (`brew install bazelisk` — 일본어 변환 엔진 Mozc를 소스에서 빌드합니다. 처음 한 번은 몇 분 걸립니다)

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
| **Shift+Enter** | 텍스트 확정 → 다음 런루프 차례에 `client.insertText("\n")` + `return true` (Codex처럼 `\n`이 들어오면 메시지를 보내는 앱에는 Shift+Enter 키를 다시 보냄) |
| **Cmd+A/C/V/X/Z** | 텍스트 확정 → CGEvent repost via `.cghidEventTap` + `return true` |

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
<summary>기술 노트: Mozc 임베드</summary>

일본어 변환 엔진 Mozc는 입력기 프로세스 안에서 돕니다. Mozc를 라이브러리(`libnrime_mozc.dylib`, `Tools/mozc`)로 빌드해 입력기가 실행 중에 불러오고, 변환 명령은 Mozc 프로토콜(protobuf)을 함수 호출로 주고받습니다. 변환 한 번은 1ms 안팎입니다.
예전에는 `mozc_server`를 별도 프로세스로 띄우고 Mach IPC로 통신했지만, 서버가 멈추거나 재시작되는 동안 입력이 기다리는 문제가 있어 2026-09에 바꿨습니다.
Mozc 버전은 `Tools/mozc/MOZC_COMMIT`에 고정하고, 베타 릴리즈마다 최신 upstream 커밋으로 올립니다(`Tools/mozc/update.sh` — 빌드와 테스트를 통과해야 반영).
NRIME 새 버전 없이도 Mozc는 따로 업데이트됩니다. GitHub Actions(`.github/workflows/mozc-component.yml`)가 매주 upstream의 버전·데이터 변경을 확인해 빌드·테스트한 뒤 `mozc-<abi>-<날짜>-<커밋>` 프리릴리즈로 올립니다. 입력기가 하루 한 번 확인해 내려받고(SHA-256 검증), 다음 시작 때 씁니다(설정 > 일본어에서 바로 적용할 수도 있습니다). 새 엔진이 실패하면 앱에 든 엔진으로 돌아갑니다.

</details>

## 라이선스

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
