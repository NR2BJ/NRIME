# NRIME

[한국어](README.md) | [English](README.en.md) | 日本語

macOS用オールインワン入力メソッド。韓国語・英語・日本語を**1つの入力ソース**で処理します。

- 入力ソースの切り替え不要 — ショートカットで即座に言語変更
- 完全オフライン動作
- 日本語変換は [Google Mozc](https://github.com/google/mozc) エンジンを使用（BSDライセンス）

## インストール

### PKGインストール（推奨）

[Releases](https://github.com/NR2BJ/NRIME/releases) ページから最新の `.pkg` ファイルをダウンロードし、ダブルクリックでインストールします。

インストール後、メニューバーにNRIMEが表示されます。
表示されない場合は、ログアウト/ログイン後 **システム設定 → キーボード → 入力ソース → 編集 → +** からNRIMEを追加してください。

### ソースからビルド

<details>
<summary>開発者向け</summary>

**必要環境:**
- macOS 13.0 (Ventura) 以上
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
git clone https://github.com/NR2BJ/NRIME.git
cd NRIME
bash Tools/install.sh
```

PKGビルド:
```bash
bash Tools/build_pkg.sh
# 出力: build/NRIME-<version>.pkg
```

</details>

### アンインストール

アンインストールスクリプトですべての痕跡を完全に削除します:

```bash
bash Tools/uninstall.sh
```

ログアウト/ログインで完全に削除されます。

<details>
<summary>手動アンインストール</summary>

```bash
# プロセス終了
killall NRIME NRIMESettings mozc_server 2>/dev/null

# アプリ削除
rm -rf ~/Library/Input\ Methods/NRIME.app
rm -rf ~/Library/Input\ Methods/NRIMESettings.app
sudo rm -rf /Library/Input\ Methods/NRIME.app       # PKGでインストールした場合
sudo rm -rf /Library/Input\ Methods/NRIMESettings.app

# 設定削除
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null

# Mozcデータ削除（ユーザー辞書を含む）
rm -rf ~/Library/Application\ Support/Mozc

# キャッシュ削除
rm -rf ~/Library/Caches/com.nrime.inputmethod.app
rm -rf ~/Library/Caches/com.nrime.settings
```

</details>

## デフォルトショートカット

| 機能 | デフォルトショートカット |
|------|------------------------|
| 英語 ↔ 前の言語トグル | `Right Shift` タップ |
| 韓国語に切り替え | `Right Shift + 1` |
| 日本語に切り替え | `Right Shift + 2` |
| 漢字変換 | `Option + Enter` |

すべてのショートカットは設定アプリで変更できます。左右のShift、Ctrl、Option、Cmdを個別に区別します。

## 使い方

### 英語

システムキーボードと同じ動作です（パススルー）。

### 韓国語

ドゥボルシク配列。入力中の文字は下線で表示され、次の文字入力時に自動確定されます。

**漢字変換:**
- 入力中に `Option + Enter` → 候補ウィンドウ表示
- またはテキストをドラッグで選択してから `Option + Enter`
- `↑↓` で移動、`1-9` で番号選択、`Enter` で確定

### 日本語

ローマ字入力 → ひらがなリアルタイム変換 → Spaceで漢字変換。

```
入力: nihongo → にほんご → Space → 日本語
```

**変換の流れ:**
1. ローマ字入力 → ひらがなでリアルタイム表示
2. `Space` または `↓` → 変換候補を表示
3. `↑↓` で候補移動、`1-9` で直接選択
4. `Enter` で確定、`Escape` でキャンセル

**Shift / Caps Lock の動作（設定で変更可能）:**

| 設定 | 動作 |
|------|------|
| Katakana | キーを押しながらタイプするとカタカナで入力 |
| Romaji | キーを押しながらタイプするとローマ字で直接入力 |

**変換キー（入力中に使用）:**

| キー | 機能 |
|------|------|
| F6 | ひらがな |
| F7 | 全角カタカナ |
| F8 | 半角カタカナ |
| F9 | 全角ローマ字 |
| F10 | 半角ローマ字 |

## 設定

メニューバーのNRIMEアイコンをクリックすると設定アプリが開きます。

| タブ | 内容 |
|------|------|
| General | ショートカット変更、インラインモード表示 ON/OFF |
| Japanese | F6-F10キー設定、Caps Lock/Shift動作、句読点スタイル |
| Per-App | アプリごとに最後に使った言語を記憶（ホワイトリスト/ブラックリスト） |
| About | バージョン情報 |

## 互換性

- **キーリマッピングアプリ**: Karabiner-Elements、BetterTouchTool等と競合なし（キー入力監視用CGEventTap未使用）
- **リモートデスクトップ**: 正常動作
- **パスワードフィールド**: 自動検出してシステムに委任

## ライセンス

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
