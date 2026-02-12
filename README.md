# NRIME

macOS용 올인원 입력기. 한국어, 영어, 일본어를 **하나의 입력 소스**로 처리합니다.

- 입력 소스 전환 없이 단축키로 즉시 언어 변경
- 완전 오프라인 동작
- 일본어 변환은 [Google Mozc](https://github.com/google/mozc) 엔진 사용 (BSD 라이선스)

## 설치

### 요구 사항

- macOS 13.0 (Ventura) 이상
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### 빌드 및 설치

```bash
git clone https://github.com/NR2BJ/NRIME.git
cd NRIME
bash Tools/install.sh
```

설치 후 NRIME이 메뉴바에 나타납니다.
나타나지 않으면 로그아웃/로그인 후 **시스템 설정 → 키보드 → 입력 소스 → 편집 → +** 에서 NRIME을 추가하세요.

### 제거

```bash
# 입력기 및 설정 앱 삭제
rm -rf ~/Library/Input\ Methods/NRIME.app
rm -rf ~/Library/Input\ Methods/NRIMESettings.app

# Mozc 엔진 데이터 삭제 (변환 학습, 사용자 사전 등)
rm -rf ~/Library/Application\ Support/Mozc

# NRIME 설정 삭제
defaults delete group.com.nrime.inputmethod 2>/dev/null
```

로그아웃/로그인하면 완전히 제거됩니다.

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
1. 로마지 타이핑 → 히라가나로 실시간 표시
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
| General | 단축키 변경, 인라인 모드 표시 ON/OFF |
| Japanese | F6-F10 키 설정, Caps Lock/Shift 동작, 구두점 스타일 |
| Per-App | 앱별로 마지막 사용 언어 기억 (화이트리스트/블랙리스트) |
| About | 버전 정보 |

## 호환성

- **키 리매핑 프로그램**: Karabiner-Elements, BetterTouchTool 등과 충돌 없음 (키 입력 감시용 CGEventTap 미사용)
- **원격 데스크톱**: 정상 동작
- **비밀번호 필드**: 자동으로 감지하여 시스템에 위임

## 라이선스

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
