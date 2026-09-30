# NRIME

[한국어](README.md) | [English](README.en.md) | 日本語

macOS用オールインワン入力メソッド。韓国語・英語・日本語を**1つの入力ソース**で処理します。

- ショートカットで即座に言語変更（入力ソースの切り替え不要）
- 入力と変換はすべてこのMac内で処理（入力した内容は外部に送信されず、ネットワークはGitHubでのアップデート確認にのみ使用）
- Electronアプリ完全対応（VS Code、Slack、Discordなど）
- 日本語変換は [Google Mozc](https://github.com/google/mozc) エンジンを使用（BSDライセンス）
- バックグラウンドプロセスなし（LaunchAgent未使用）

## インストール

[Releases](https://github.com/NR2BJ/NRIME/releases) ページから最新の `.pkg` をダウンロードしてインストールします。

インストール後、メニューバーにNRIMEアイコンが表示されます。
表示されない場合は、ログアウト/ログイン後 **システム設定 → キーボード → 入力ソース → 編集 → +** からNRIMEを追加してください。

## 機能

### 言語切り替え

2つのショートカットで言語を切り替えます。どちらも設定で変更・**無効化**可能です。

| 機能 | デフォルトショートカット |
|------|------------------------|
| 英語に切替（英語 ↔ 前の言語） | `Right Shift` タップ |
| 非英語モード切替（韓国語 ↔ 日本語） | `Shift + Space` |

### 韓国語

ドゥボルシク配列。漢字変換：入力中に `Option + Enter`（またはテキスト選択後に `Option + Enter`）

### 日本語

ローマ字入力 → ひらがなで表示 → `Space` で漢字変換

```
nihongo → にほんご → Space → 日本語
```

変換中：`↑↓` で移動、`1-9` で直接選択、`Enter` で確定、`Escape` でキャンセル

<details>
<summary>変換キー詳細</summary>

| キー | 機能 |
|------|------|
| Space / Tab | 変換開始（入力中 — 各キーON/OFF設定可能） |
| ↑ / ↓ | 候補を選択 |
| ← / → | 文節間を移動（文節が1つなら候補のページ送り） |
| Shift + ← / → | 文節の長さを変更 |
| 1 – 9 | 番号で候補を確定 |
| Tab | 候補の展開 / 折りたたみ（候補ウィンドウ表示中） |
| Enter | 変換を確定 |
| Escape | 変換をキャンセル |

</details>

### その他の機能

- **インラインモード表示**：モード切替時に入力カーソル（またはマウスカーソル）付近に現在の入力モードを表示
- **日本語ユーザー辞書**：読み・単語・品詞を登録して変換候補に追加（日本語タブ → ユーザー辞書）
- **自動アップデート**：情報タブからGitHub Releasesベースのアップデート確認・インストール（正式版/ベータのチャンネル選択）
- **設定UI多言語対応**：韓国語/英語/日本語（情報タブで変更、すぐに反映）
- **設定エクスポート/インポート**：JSONバックアップで設定を移行
- **開発者モード**：診断ログ出力（ローカル専用、アップロードなし）
- **ABC入力ソース切り替え防止**：システムがABCに切り替えるのを防止
- **パスワード入力時に英字キーボードへ切替**：パスワード欄などmacOSのセキュア入力が有効な間はABCキーボードに切り替え、終了後に元へ戻す（デフォルトON）
- **高速タップ切替補正（実験的）**：Shiftタップ直後の高速入力で大文字などが混入する問題を補正（デフォルトOFF）
- **Caps Lockで言語切り替え**：Karabiner-ElementsでCaps Lock → F18マッピング時に言語切り替えキーとして活用可能

## 設定

メニューバーのNRIMEアイコンをクリックして設定アプリを開きます。

### 一般タブ

| セクション | 内容 |
|------------|------|
| ショートカット | 英語に切替、非英語モード切替、漢字変換 — それぞれ記録（キーを指定）/クリア（無効化）可能 |
| タップ認識時間 | 修飾キー単独タップと認識する最大時間のスライダー（0.1～0.5秒） |
| 高速タップ切替補正（実験的） | Shiftタップ直後の高速入力で大文字などが混入する問題を補正（デフォルトOFF）。Shiftに意味のないキーはそのまま切替、濃音・大文字はShiftを30ms以内に離したときだけ、単語途中の濃音は切り替えない |
| 表示 | モード切替時にインライン表示（インジケーター位置：入力カーソル位置/マウスカーソル位置）、ABCへの切替を防止、パスワード入力時に英字キーボードへ切替、候補フォントサイズ（12～24pt） |
| Shift+Enter 改行の待ち時間 | 入力中のShift+Enterで確定してから改行までの待ち時間 — Electron・Chromiumアプリ（0～100ms、デフォルト20ms、⌘ショートカットの送り直しにも適用）、Shift+Enterを送り直すアプリ（改行文字で送信してしまうアプリ、現在はCodex：0～200ms、デフォルト50ms）。Macごとに保存 |
| 入力メソッドの権限 | デバイスの制御とデータへのアクセス（macOS 26以前：アクセシビリティ）の許可状態、再確認 / 権限を要求、システム設定を開く — 確定後に⌘+キーやCodexのShift+Enterをアプリへ送り直すために必要 |
| 開発者 | 開発者モードを有効化（診断ログ）、ログを開く/Finderで表示/ログをクリア |
| バックアップと復元 | 設定をエクスポート（JSON）/ インポート |

### 日本語タブ

上部で **設定** と **ユーザー辞書** のページを切り替えます。

**設定**

| セクション | 内容 |
|------------|------|
| 変換トリガーキー | スペース、Tab — 入力中に変換を開始するキー（各キーON/OFF） |
| キー動作 | Caps Lock 動作 — Caps Lock（デフォルト）/カタカナに変換/ローマ字に変換 |
| スペース | スペース幅 — 半角 (U+0020)/全角 (U+3000)、未入力時に適用 |
| 句読点と記号 | 句読点スタイル — 日本語（。、）/全角西洋式（．，）/半角西洋式（.,）、入力例のプレビュー、`/` キー → `・`（中黒）、`\` キー → `¥`（円記号） |
| 変換エンジン（Mozc） | 使用中のMozcバージョン、新しいMozcの確認・今すぐ適用 |
| 変換履歴 | Mozc変換履歴のクリア |
| 変換ショートカット | 変換中キー操作ガイド表示 |

**ユーザー辞書**

| 項目 | 内容 |
|------|------|
| 単語一覧 | 読み（ひらがな）・単語・品詞・コメント、検索 |
| 編集 | `+` で追加、ダブルクリックで編集、`−` で削除 |
| 自動学習 | 自動学習された変換は一覧に表示されない — 設定ページの「変換履歴をクリア」でリセット |

### 情報タブ

| セクション | 内容 |
|------------|------|
| バージョン | 現在のバージョン、GitHubリンク |
| 自動アップデート | GitHub Releasesから最新バージョン確認、ダウンロード、インストール |
| アップデートチャンネル | 正式版/ベータ（ベータはテストビルドを先に受け取る） |
| 言語 | 設定アプリUI言語の変更（韓国語/English/日本語） |

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

**必要環境:** macOS 13.0+、Xcode 15+、[xcodegen](https://github.com/yonaskolb/XcodeGen)、[bazelisk](https://github.com/bazelbuild/bazelisk)（`brew install bazelisk` — 変換エンジンMozcをソースからビルドします。初回は数分かかります）

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
| **Shift+Enter** | テキスト確定 → 20ms後に `client.insertText("\n")` + `return true`（Codexのように `\n` が入るとメッセージを送信するアプリには、50ms後に Shift+Enter キーを送り直す。待たないと遅いMacで入力中の文字が消える） |
| **Cmd+A/C/V/X/Z** | テキスト確定 → CGEvent repost via `.cghidEventTap` + `return true` |

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
<summary>技術ノート：Mozcの組み込み</summary>

日本語変換エンジンMozcは入力メソッドのプロセス内で動作します。Mozcをライブラリ（`libnrime_mozc.dylib`、`Tools/mozc`）としてビルドして入力メソッドが実行時に読み込み、変換コマンドはMozcのプロトコル（protobuf）を関数呼び出しでやり取りします。変換1回はおよそ1ミリ秒です。
以前は `mozc_server` を別プロセスとして起動しMach IPCで通信していましたが、サーバーが固まったり再起動したりする間に入力が待たされる問題があり、2026年9月に組み込みへ変更しました。
Mozcのバージョンは `Tools/mozc/MOZC_COMMIT` で固定し、ベータリリースごとに最新のupstreamコミットへ更新します（`Tools/mozc/update.sh` — ビルドとテストに通った場合のみ反映）。
NRIMEの新バージョンがなくてもMozcは単独で更新されます。GitHub Actions（`.github/workflows/mozc-component.yml`）が毎週upstreamのバージョン・データの変更を確認してビルド・テストし、`mozc-<abi>-<日付>-<コミット>` のプレリリースとして公開します。入力メソッドが1日1回確認してダウンロードし（SHA-256で検証）、次回の起動時から使います（設定 → 日本語 からすぐに適用することもできます）。新しいエンジンが失敗した場合はアプリ内のエンジンに戻ります。

</details>

## ライセンス

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
