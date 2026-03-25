# NRIME

[한국어](README.md) | [English](README.en.md) | 日本語

macOS用オールインワン入力メソッド。韓国語・英語・日本語を**1つの入力ソース**で処理します。

- ショートカットで即座に言語変更（入力ソースの切り替え不要）
- 完全オフライン動作（ネットワーク不要）
- Electronアプリ完全対応（VS Code、Slack、Discordなど）
- 日本語変換は [Google Mozc](https://github.com/google/mozc) エンジンを使用（BSDライセンス）

## インストール

[Releases](https://github.com/NR2BJ/NRIME/releases) ページから最新の `.pkg` をダウンロードしてインストールします。

インストール後、メニューバーにNRIMEアイコンが表示されます。
表示されない場合は、ログアウト/ログイン後 **システム設定 → キーボード → 入力ソース → 編集 → +** からNRIMEを追加してください。

## 使い方

### 言語切り替え

2つの方式をサポートしています：

**選択方式** — 指定した言語に直接切り替え
| 機能 | デフォルトショートカット |
|------|------------------------|
| 韓国語に切り替え | `Right Shift + 1` |
| 日本語に切り替え | `Right Shift + 2` |

**トグル方式** — 英語 ↔ 非英語間の切り替え
| 機能 | デフォルトショートカット |
|------|------------------------|
| 英語 ↔ 前の言語トグル | `Right Shift` タップ |
| 非英語モードトグル | （未設定 — 設定で指定） |

すべてのショートカットは設定で変更・**無効化**可能。選択方式のみ、トグル方式のみ、または両方使用できます。

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
| F6 | ひらがな |
| F7 | 全角カタカナ |
| F8 | 半角カタカナ |
| F9 | 全角ローマ字 |
| F10 | 半角ローマ字 |

</details>

## 設定

メニューバーのNRIMEアイコンをクリックして設定アプリを開きます。

| タブ | 内容 |
|------|------|
| General | ショートカット変更/無効化、インラインインジケーター、変換トリガー選択 |
| Japanese | Caps Lock/Shift動作、句読点スタイル、ライブ変換、全角スペース |
| Per-App | アプリごとに最後に使った言語を記憶 |
| Developer | 診断ログ（ローカル専用、アップロードなし） |

## 互換性

| 環境 | 状態 |
|------|------|
| ネイティブmacOSアプリ | 正常動作 |
| Electronアプリ（VS Code、Slack、Discordなど） | 正常動作 |
| キーリマッピング（Karabiner、BetterTouchTool） | 競合なし |
| パスワードフィールド | 自動検出、システムに委任 |
| バックグラウンドプロセス | なし（LaunchAgent未使用） |

## アンインストール

```bash
bash Tools/uninstall.sh
```

ログアウト/ログインで完全に削除されます。

<details>
<summary>手動アンインストール</summary>

```bash
killall NRIME NRIMESettings NRIMERestoreHelper mozc_server 2>/dev/null

# 旧バージョンのLaunchAgent削除
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist 2>/dev/null
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist 2>/dev/null

# アプリ削除
rm -rf ~/Library/Input\ Methods/NRIME.app ~/Library/Input\ Methods/NRIMESettings.app ~/Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -rf /Library/Input\ Methods/NRIME.app /Library/Input\ Methods/NRIMESettings.app /Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist

# 設定/データ削除
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null
rm -rf ~/Library/Application\ Support/Mozc ~/Library/Caches/com.nrime.inputmethod.app ~/Library/Caches/com.nrime.settings ~/Library/Group\ Containers/group.com.nrime
```

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

## ライセンス

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
