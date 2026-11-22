# QuickTranslate

## 概要

QuickTranslate は、macOS 向け翻訳アプリ [Easydict](https://github.com/tisfeng/Easydict)（2.26.0 / GPL-3.0）を元にした非公式派生版です。Easydict 公式とは無関係です。

- リポジトリ: https://github.com/sojiro-o/chatgpt-translator
- 対応環境: macOS 13 以降（macOS 15 以降を推奨）、Intel / Apple Silicon 両対応
- UI・翻訳方向: 日本語 UI、英語 → 日本語翻訳（英日混在に対応）
- 翻訳エンジン: ChatGPT（Codex 経由、ChatGPT Plus の利用枠を使用。API キー不要）
- 常駐形式: メニューバー常駐（Dock には表示されません）

## 使い方

### 基本の操作

1. 翻訳したい英文を選択します。
2. `⌘C` を素早く 2 回押します（初期設定は 600ms 以内。設定で 200〜1500ms の範囲で変更可能）。
3. マウス付近に小さなポップアップが開き、ChatGPT（Codex 経由、ChatGPT Plus の枠）による日本語訳がストリーミング表示されます。
4. コピーボタンで訳文をコピーできます。閉じるには `ESC` キーまたは閉じるボタンを押します。エラー時は再試行ボタンからやり直せます。

### 翻訳の仕様

- 英語 → 日本語に翻訳します（英日混在の文章にも対応）。
- Markdown・箇条書き・コードを保持し、訳文だけを出力します。
- 原文中に指示が含まれていても、その指示には従いません。

### メニューバー

メニューバーのアイコンから次の項目を利用できます。

- `設定…`
- `ChatGPT にログイン…`
- `クリップボードを翻訳`
- `QuickTranslate を終了`

### ポップアップを出さない／送信しない条件

- 1 回の `⌘C`、キー長押し、2 回の `⌘C` の間に他のキーを押した場合、アプリを切り替えた場合はポップアップを出しません。
- QuickTranslate 自身のウィンドウ内でのコピーは無視します。
- テキスト以外（画像・ファイル）、パスワード管理アプリが「機密」と印を付けたクリップボード内容、10,000 文字を超えるテキストは送信しません。

## インストール（Actions の成果物から）

動作環境は macOS 13 以降（macOS 15 以降を推奨）で、Intel / Apple Silicon 両対応のビルドです。

1. GitHub にログインします（Artifacts のダウンロードに必要です）。
2. リポジトリの [Actions](https://github.com/sojiro-o/chatgpt-translator/actions) を開き、「Build QuickTranslate」の最新の成功した実行を選択します。
3. Artifacts から `QuickTranslate-<コミット>` をダウンロードします。
4. ダウンロードした zip ファイルを展開し、`QuickTranslate.app` を「アプリケーション」フォルダへ移動します。
5. 署名・公証していないため、初回は Finder で `QuickTranslate.app` を右クリックして「開く」を選ぶか、ターミナルで次を実行してから起動します。

```bash
xattr -dr com.apple.quarantine /Applications/QuickTranslate.app
```

Easydict 本体と同時にインストール可能です（Bundle ID は `io.github.sojiro-o.QuickTranslate`、URL スキームは `quicktranslate` で、設定・保存先も別です）。

## 自分でビルドする

ビルドには **Xcode 27** が必要です（macOS 26 SDK 以降の API を含みます）。CocoaPods の依存（Pods）はリポジトリに同梱されているため `pod install` は不要です。

1. リポジトリを取得し、`quicktranslate` ブランチに切り替えます。

```bash
git clone https://github.com/sojiro-o/chatgpt-translator.git
cd chatgpt-translator
git checkout quicktranslate
```

2. 次のコマンドでビルドします（ターゲット名・スキーム名は元の `Easydict` のままです）。

```bash
xcodebuild build -workspace Easydict.xcworkspace -scheme Easydict -configuration Release -derivedDataPath build/DerivedData -skipPackagePluginValidation -skipMacroValidation EASYDICT_RELEASE_PACKAGING=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

3. ビルドが完了すると、`build/DerivedData/Build/Products/Release/QuickTranslate.app` にアプリが生成されます。

自分の Apple ID の開発チームで署名したい場合は、`Easydict.local.xcconfig`（git 管理外）に `DEVELOPMENT_TEAM = <Team ID>` 等を記述してください。

## ChatGPT ログインの設定

API キーは不要で、入力欄もありません。API 従量課金に切り替わる経路はありません。

1. メニューバーの「ChatGPT にログイン…」（または「設定 > サービス > ChatGPT」）を開きます。
2. **Codex コンポーネントをダウンロード**します（初回のみ）。OpenAI 公式 Codex のリリースを GitHub から取得し、SHA-256 と OpenAI のコード署名を検証します。
3. **ChatGPT でサインイン**します。ブラウザで `auth.openai.com` が開くのでログインを完了します。
4. **接続確認**を行います（短い英文を 1 回翻訳して動作を確認します）。

### 認証情報とモデル設定

- ログイン情報は Codex が macOS のキーチェーンに保存します（平文ファイルには保存しません。キーチェーンが使えない環境ではエラーで停止します）。
- ログアウトも同じ画面から行えます。ログアウト後は翻訳できません。
- モデルは同梱カタログの既定（macOS 15 以降は `gpt-5.6-luna`、macOS 13/14 は `gpt-5.5`）、思考量の既定は「低」です（いずれも設定で変更できます）。

## macOS の権限

必要な権限は **「入力監視」だけ** です（`⌘C` を 2 回押したことを検出するため）。読み取り専用のキーイベント監視であり、キー入力を記録・送信しません。

1. 初回起動時にアプリが日本語で案内を表示します。
2. 「システム設定 > プライバシーとセキュリティ > 入力監視」を開き、`QuickTranslate` をオンにします。

- アクセシビリティや画面収録は既定では要求しません（Easydict の選択テキスト自動取得・OCR は無効化しています）。
- 署名なしビルドはアプリを更新するたびに権限の許可をやり直す必要がある場合があります（[Issue #8](https://github.com/sojiro-o/chatgpt-translator/issues/8)）。

## 設定

設定ウィンドウのタブは **一般 / サービス / ショートカット / 情報** のみです。

- **ショートカット**: 「⌘C を2回押して翻訳」のオン/オフ、2 回押しの判定時間（初期 600ms、200〜1500ms）
- **サービス**: ChatGPT のみ表示（ログイン／ログアウト、モデル、思考量など）

## プライバシーと保存しないもの

### ローカルに保存しないもの・隔離設定

- 翻訳履歴、お気に入り、クエリ統計、単語帳、Anki 連携、訳文の自動コピー、音声の自動再生は無効です。
- アプリのログファイルは作成しません（ログに原文・訳文は出さず、文字数のみ出力します）。
- ポップアップを閉じると原文・訳文への参照を手放します。
- Codex 側も一時スレッド（ephemeral）で実行し、履歴保存（`history.persistence`）と Codex のログ出力をオフにしています。作業用の一時ディレクトリ（`$TMPDIR/quicktranslate-codex-<pid>`）はセッション終了・アプリ終了時に削除します。
- Codex の MCP・ツール・Web 検索・ファイル書き込み・ネットワーク権限は無効で、送信前に隔離設定を毎回確認します。

### 無効化した機能・外部サービス

- Firebase Analytics / Sentry（初期化しません。SDK 自体はバイナリに残っています → [Issue #3](https://github.com/sojiro-o/chatgpt-translator/issues/3)）
- クラッシュログの送信と保存
- Sparkle の自動更新（本家 Easydict の更新で上書きされません）
- GitHub の最新版確認、GitHub Copilot のモデル取得
- 言語検出の Baidu / Google 問い合わせ
- Youdao・DeepL・Built-in AI など他の翻訳サービス（既定で有効なのは ChatGPT のみで、設定のサービス一覧にも ChatGPT のみ表示されます）

### OpenAI サーバー側での取り扱い

- ChatGPT（OpenAI）のサーバー側でのデータ処理・保持はアプリでは制御できず、削除も保証できません。
- モデルの学習に使われたくない場合は、ChatGPT の「設定 > データコントロール」で「すべての人のためにモデルを改善する」をオフにしてください。

## 外部通信先と目的

| 通信先 | 目的 | 備考 |
| --- | --- | --- |
| `github.com/openai/codex/releases`（および GitHub のダウンロード用 CDN） | Codex コンポーネントの初回ダウンロード | ユーザー操作時のみ |
| `auth.openai.com` | ChatGPT サインイン | ブラウザで認証 |
| `chatgpt.com/backend-api/` | 翻訳 | ChatGPT（Codex 経由） |

これ以外の通信は既定では行いません（他サービスのコードは残っていますが、無効化しています）。

## セキュリティ上の注意

1. **ChatGPT Plus の利用枠**: 翻訳は ChatGPT Plus の「Work と Codex」の利用枠（5 時間枠と週枠）を使います。コーディングで使う Codex と同じ枠のため、使い切ると翻訳もできなくなります。OpenAI は 2026 年 12 月から ChatGPT と Codex の枠を共有すると告知しています（詳細は未確定）。
2. **クレジットの自動消費**: ChatGPT のクレジットを購入済みの場合、利用枠を超えた後にクレジットが自動で消費されることがあります。避けるにはクレジットを持たないか、ChatGPT の「設定 > 使用量」で `Automatic reload` をオフにしてください（[Issue #2](https://github.com/sojiro-o/chatgpt-translator/issues/2)）。
3. **利用方式と仕様変更のリスク**: 公式 Codex 本体を起動して `codex login` でサインインする方式を第三者アプリから使うことについて、OpenAI の公式文書は許可も禁止も明記していません。公式には別の「Sign in with ChatGPT」方式がオープンソース向けに案内されています（[Issue #1](https://github.com/sojiro-o/chatgpt-translator/issues/1)）。仕様変更で使えなくなる可能性があります。個人のローカル利用を想定しており、商用・ホスティング用途には使わないでください。
4. **機密情報の取り扱い**: 機密文書を翻訳する場合は、所属組織の規程と OpenAI のデータ取り扱いを確認してください。
5. **署名・公証なしビルド**: 署名・公証していないビルドのため、入手元（このリポジトリの Actions）を確認して利用してください。

## テスト結果

### 検証済み

- CI の結果: 2026-11-22 の [GitHub Actions の実行](https://github.com/sojiro-o/chatgpt-translator/actions/runs/45039388856)で、すべて成功（Release ビルドは x86_64 + arm64 のユニバーサル、識別子と更新フィード未設定の確認、⌘C 2回判定の単体テスト 9 件）
- 対象:
  - GitHub Actions（Xcode 27, macOS）での Release ビルド
  - Bundle ID・アプリ名・URL スキーム・更新フィード未設定の自動確認
  - `⌘C` 2 回判定ロジックの単体テスト

### 未検証（Mac 実機が必要）

※ ChatGPT を使う確認は、Codex の枠が戻る 2026-11-26 以降に実施予定です。

- Chrome / Safari / プレビュー（PDF）/ Word / VS Code での `⌘C` 2 回翻訳
- 1 回の `⌘C` ではポップアップが出ないこと
- 通常のコピーが壊れないこと
- 他のキーで誤検出しないこと
- クリップボードの取得タイミング
- 同じ文の繰り返し翻訳
- 利用上限・通信エラー時に落ちないこと
- ログアウト後に翻訳できないこと
- 履歴ファイル・ログが残らないこと
- 他サービスへの通信が無いこと
- ダークモード表示
- Easydict との同時インストール

## 既知の問題

未解決の課題は [Issues](https://github.com/sojiro-o/chatgpt-translator/issues)（Issue #1〜#8）で管理しています。

- [#1](https://github.com/sojiro-o/chatgpt-translator/issues/1): 「Sign in with ChatGPT」方式への移行
- [#2](https://github.com/sojiro-o/chatgpt-translator/issues/2): 上限到達前に止める
- [#3](https://github.com/sojiro-o/chatgpt-translator/issues/3): Firebase / Sentry SDK の除去
- [#4](https://github.com/sojiro-o/chatgpt-translator/issues/4): QWERTY 以外の配列への対応
- [#5](https://github.com/sojiro-o/chatgpt-translator/issues/5): 原文の展開表示
- [#6](https://github.com/sojiro-o/chatgpt-translator/issues/6): Apple 端末内翻訳を予備に
- [#7](https://github.com/sojiro-o/chatgpt-translator/issues/7): 既存ユニットテストの整理
- [#8](https://github.com/sojiro-o/chatgpt-translator/issues/8): 署名なしビルドでの権限の再許可

また、Easydict 由来のコード（辞書・OCR・TTS・他サービス等）は削除せず、無効化・非表示にしているだけです。

## ライセンスと著作権

- ライセンス: [GPL-3.0](./LICENSE)（`LICENSE` を維持）
- 著作権表示: [Easydict](https://github.com/tisfeng/Easydict) の著作権表示（Copyright tisfeng および Easydict のコントリビューター）を維持しています。
- 改変版を配布する場合は、GPL-3.0 に従い対応するソースコードを提供してください。
- Easydict 公式アプリと誤認されないよう名称・説明を分けています。
- 元の Easydict の英語 README は [README_Easydict.md](./README_Easydict.md) に残しています。
