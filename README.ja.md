# NRIME

[한국어](README.md) | [English](README.en.md) | 日本語

macOS用オールインワン入力メソッド。韓国語・英語・日本語を**1つの入力ソース**で処理します。

- ショートカットで即座に言語変更（入力ソースの切り替え不要）
- 完全オフライン動作（ネットワーク不要）
- Electronアプリ完全対応（VS Code、Slack、Discordなど）
- 日本語変換は [Google Mozc](https://github.com/google/mozc) エンジンを使用（BSDライセンス）
- バックグラウンドプロセスなし（LaunchAgent未使用）

## インストール

[Releases](https://github.com/NR2BJ/NRIME/releases) ページから最新の `.pkg` をダウンロードしてインストールします。

インストール後、メニューバーにNRIMEアイコンが表示されます。
表示されない場合は、ログアウト/ログイン後 **システム設定 → キーボード → 入力ソース → 編集 → +** からNRIMEを追加してください。

## 機能

### 言語切り替え

2つの方式をサポートしています。すべてのショートカットは設定で変更・**無効化**可能です。
選択方式のみ、トグル方式のみ、または両方を組み合わせて使用できます。

**選択方式** — 指定した言語に直接切り替え

| 機能 | デフォルトショートカット |
|------|------------------------|
| 韓国語に切り替え | `Right Shift + 1` |
| 日本語に切り替え | `Right Shift + 2` |

**トグル方式** — 英語 ↔ 非英語間の切り替え

| 機能 | デフォルトショートカット |
|------|------------------------|
| 英語 ↔ 前の言語トグル | `Right Shift` タップ |
| 非英語モードトグル（韓↔日） | （未設定 — 設定で指定） |

### 韓国語

ドゥボルシク配列。漢字変換：入力中に `Option + Enter`（またはテキスト選択後に `Option + Enter`）

### 日本語

ローマ字入力 → ひらがなリアルタイム変換 → `Space` で漢字変換

```
nihongo → にほんご → Space → 日本語
```

変換中：`↑↓` で移動、`1-9` で直接選択、`Enter` で確定、`Escape` でキャンセル

<details>
<summary>変換キー詳細</summary>

| キー | 機能 |
|------|------|
| Space / Tab / ↓ | 変換候補表示（各キーON/OFF設定可能） |
| ← / → | 文節移動 |
| Shift + ← / → | 文節サイズ調整 |
| F6 | ひらがな |
| F7 | 全角カタカナ |
| F8 | 半角カタカナ |
| F9 | 全角ローマ字 |
| F10 | 半角ローマ字 |
| Tab | 予測変換選択 |

</details>

### その他の機能

- **Shiftダブルタップ → CapsLockトグル**：間隔スライダーで調整可能（0.15～0.6秒）
- **Shift+Enterディレイ**：Electronアプリ互換性のためのディレイ調整（デフォルト15ms、5～50ms）
- **アプリごとの言語記憶**：アプリごとに最後に使った言語を自動記憶（ホワイトリスト/ブラックリストモード）
- **インラインモード表示**：カーソル付近に現在の入力モードを表示
- **自動アップデート**：AboutタブからGitHub Releasesベースのアップデート確認・インストール
- **設定UI多言語対応**：韓国語/英語/日本語（Aboutタブで変更、再起動が必要）
- **設定エクスポート/インポート**：JSONバックアップで設定を移行
- **開発者モード**：診断ログ出力（ローカル専用、アップロードなし）
- **ABC入力ソース切り替え防止**：システムがABCに切り替えるのを防止
- **Caps Lockで言語切り替え**：Karabiner-ElementsでCaps Lock → F18マッピング時に言語切り替えキーとして活用可能

## 設定

メニューバーのNRIMEアイコンをクリックして設定アプリを開きます。

### Generalタブ

| セクション | 内容 |
|------------|------|
| ショートカット | 英語トグル、非英語トグル、韓国語切替、日本語切替、漢字変換 — 各カスタム録画/無効化可能 |
| タップ閾値 | Modifier-onlyタップ認識時間スライダー（0.1～0.5秒） |
| Shiftダブルタップ → CapsLock | ダブルタップ認識間隔調整（0.15～0.6秒） |
| Shift+Enterディレイ | Electronアプリ互換ディレイ（5～50ms） |
| 表示 | インラインモード表示、ABC切替防止、候補ウィンドウフォントサイズ、変換トリガーキー（Space/Tab/↓） |
| 開発者モード | 診断ログON/OFF、ログを開く/Finderで表示/クリア |
| バックアップ＆復元 | 設定エクスポート（JSON）/ インポート |

### Japaneseタブ

| セクション | 内容 |
|------------|------|
| 変換キー | ひらがな/全角カタカナ/半角カタカナ/全角ローマ字/半角ローマ字キーのカスタム録画 |
| キー動作 | Caps Lock動作（デフォルト/カタカナ/ローマ字）、Shiftキー動作（なし/カタカナ/ローマ字） |
| スペース | 半角/全角スペース選択 |
| 句読点 | 日本式（。、）/ 西洋式（．，）、`/` → `・` マッピング、`¥` キー → `¥` マッピング |
| 入力機能 | ライブ変換、予測変換 |
| 変換履歴 | Mozc変換履歴のクリア |
| 変換ショートカット | 変換中キー操作ガイド表示 |

### Per-Appタブ

| セクション | 内容 |
|------------|------|
| アプリごとの言語記憶 | ON/OFFトグル |
| モード | ホワイトリスト（選択したアプリのみ記憶）/ ブラックリスト（選択したアプリを除外） |
| アプリ一覧 | アプリの追加/削除（ファイルピッカー） |

### Aboutタブ

| セクション | 内容 |
|------------|------|
| 自動アップデート | GitHub Releasesから最新バージョン確認、ダウンロード、インストール |
| 言語設定 | 設定アプリUI言語の変更（韓国語/English/日本語） |

## 互換性

| 環境 | 状態 |
|------|------|
| ネイティブmacOSアプリ | ✓ 正常動作 |
| Electronアプリ（VS Code、Slack、Discordなど） | ✓ 正常動作 |
| キーリマッピング（Karabiner、BetterTouchTool） | ✓ 競合なし |
| パスワードフィールド | ✓ 自動検出、システムに委任 |
| リモートデスクトップ | ✓ 正常動作 |
| バックグラウンドプロセス | なし（LaunchAgent未使用） |

## アンインストール

```bash
bash Tools/uninstall.sh
```

ログアウト/ログインで完全に削除されます。

<details>
<summary>手動アンインストール</summary>

```bash
# 1. プロセス終了
killall NRIME NRIMESettings NRIMERestoreHelper mozc_server 2>/dev/null

# 2. 旧バージョンのLaunchAgent削除
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist 2>/dev/null
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist 2>/dev/null

# 3. アプリ削除
rm -rf ~/Library/Input\ Methods/NRIME.app
rm -rf ~/Library/Input\ Methods/NRIMESettings.app
rm -rf ~/Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -rf /Library/Input\ Methods/NRIME.app
sudo rm -rf /Library/Input\ Methods/NRIMESettings.app
sudo rm -rf /Library/Input\ Methods/NRIMERestoreHelper.app

# 4. 旧バージョンのLaunchAgentファイル削除
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist
rm -f ~/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist
rm -f ~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist

# 5. 設定削除
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null
rm -f ~/Library/Preferences/com.nrime.inputmethod.app.plist
rm -f ~/Library/Preferences/com.nrime.settings.plist
rm -f ~/Library/Preferences/group.com.nrime.inputmethod.plist

# 6. Mozcデータとログ削除
rm -rf ~/Library/Application\ Support/Mozc
rm -rf ~/Library/Application\ Support/NRIME

# 7. キャッシュとコンテナ削除
rm -rf ~/Library/Caches/com.nrime.inputmethod.app
rm -rf ~/Library/Caches/com.nrime.settings
rm -rf ~/Library/Group\ Containers/group.com.nrime
```

> NRIMERestoreHelperとLaunchAgentは旧バージョンで使用されており、現在のバージョンではインストールされません。
> 旧バージョンからアップグレードした場合、上記のコマンドで残存ファイルをクリーンアップできます。

</details>

<details>
<summary>ソースからビルド（開発者向け）</summary>

**必要環境:** macOS 13.0+、Xcode 15+、[xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/NR2BJ/NRIME.git
cd NRIME
bash Tools/build_pkg.sh
# 出力: build/NRIME-<version>.pkg
```

</details>

<details>
<summary>技術ノート：Electron/Chromium IMEワークアラウンド</summary>

Electron/Chromiumベースのアプリで、IME変換中にmodifier+key入力時にテキストが消失する問題の原因と解決方法です。このワークアラウンドはネイティブアプリでも同様に適用され、副作用はありません。

### 根本原因

**Shift+Enter**: macOSの `StandardKeyBinding.dict` にShift+Returnバインディングがないため、Chromiumが `insertText:"\n"` を呼び出す際に `oldHasMarkedText` 追跡ロジックがIME変換イベントと誤判定し、確定テキストを消失させます。

**Cmd+key**: `performKeyEquivalent:` パスを通るため、IMKitから `return false` ではイベントをアプリに渡すことができません。

### 解決方法

| 状況 | 方法 |
|------|------|
| **Shift+Enter** | テキスト確定 → 設定可能なディレイ（デフォルト15ms） → `client.insertText("\n")` + `return true` |
| **Cmd+A/C/V/X/Z** | テキスト確定 → tagged CGEvent repost via `.cghidEventTap` + `return true` |

### 試したが失敗したアプローチ

| アプローチ | 理由 |
|-----------|------|
| `insertText + return false` | Chromiumの `oldHasMarkedText` 誤判定 |
| `setMarkedText("") + insertText + return false` | 同じ原因 |
| 同期 `insertText("\n")` | ChromiumのIPCバッチ処理で無視 |
| `CGEvent.post(.cgAnnotatedSessionEventTap)` | Electronがそのタップのイベントを無視 |
| `CGEventPostToPSN` (deprecated) | ElectronがPSN直接配信を無視 |
| `NSAppleScript (System Events)` | IMEでAutomation TCCが利用不可 |

</details>

<details>
<summary>技術ノート：Mozc IPC（Swift Mach IPC → C shim）</summary>

SwiftでMach OOL IPCを直接実装しましたが、空の応答が返る問題が発生しました。
原因がbitfieldパッキングかポインタ寿命の問題か確定できず、upstream mozcの `mach_ipc.cc` と同じ構造のC shim（`nrime_mozc_ipc.c`）で解決しました。
mozc_serverはLaunchAgentなしで必要に応じて子プロセスとしてオンデマンド実行されます。

</details>

## ライセンス

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
