# QuickTranslate

## 概要

QuickTranslate は、macOS 向け翻訳アプリ [Easydict](https://github.com/tisfeng/Easydict)（2.26.0 / GPL-3.0）を元にした非公式派生版です。Easydict 公式とは無関係です。

- リポジトリ: https://github.com/sojiro-o/chatgpt-translator
- 対応環境: macOS 13 以降（macOS 15 以降を推奨）、Intel / Apple Silicon 両対応
- UI・翻訳方向: 日本語 UI、英語 → 日本語翻訳（英日混在に対応）
- 翻訳エンジン: ChatGPT（既定。Codex 経由、ChatGPT Plus の利用枠を使用。API キー不要）、Apple 翻訳（Mac 内）、Apple Intelligence（Mac 内）
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
- `アップデートを確認…`
- `QuickTranslate をアンインストール…`
- `QuickTranslate を終了`

### ポップアップを出さない／送信しない条件

- 1 回の `⌘C`、キー長押し、2 回の `⌘C` の間に他のキーを押した場合、アプリを切り替えた場合はポップアップを出しません。
- QuickTranslate 自身のウィンドウ内でのコピーは無視します。
- テキスト以外（画像・ファイル）、パスワード管理アプリが「機密」と印を付けたクリップボード内容、10,000 文字を超えるテキストは送信しません。

## 翻訳エンジン

設定の **「サービス」** タブで、次の 3 つの翻訳エンジンをそれぞれオン／オフできます。複数オンにすると、ポップアップに各エンジンの訳が縦に並ぶため、その場で訳を比べられます。

- **ChatGPT**（既定でオン）: 公式 Codex（app-server）経由で翻訳します。ChatGPT Plus 等の利用枠を使用し、API キーは不要です。「原文との対応」表示に対応しています。
- **Apple 翻訳（Mac 内）**（既定でオフ）: macOS 15 以降の `Translation` フレームワークを使って Mac 内で翻訳します。無料・外部通信なしで、ChatGPT の利用枠を消費しません。初回のみ、macOS が英語・日本語の言語データのダウンロードを求めることがあります。「原文との対応」は表示されません。
- **Apple Intelligence（Mac 内）**（既定でオフ）: macOS 26 以降の Apple Silicon Mac（システム設定で Apple Intelligence がオン）で、`FoundationModels`（端末内の言語モデル）を使って Mac 内で翻訳します。無料・外部通信なしで、ChatGPT の利用枠を消費しません。端末内モデルの文脈長の都合により、原文は約 1,500 文字までです。「原文との対応」表示を試みます（小さいモデルのため、番号付けに失敗した場合は対応ボタンが表示されません）。

※ 訳の質は一般に **ChatGPT ＞ Apple 翻訳／Apple Intelligence** です。ChatGPT の利用枠を節約したい場合や、外部へ送信せずに Mac 内だけで訳したい場合、訳を並べて比較したい場合に Apple 翻訳・Apple Intelligence を併用できます。

## インストール

動作環境は macOS 13 以降（macOS 15 以降を推奨）で、Intel / Apple Silicon 両対応のビルドです。

### 1. ターミナルでインストール（おすすめ）

次の 1 行をターミナルで実行します。`curl` でダウンロードするため macOS の隔離属性（`com.apple.quarantine`）が付かず、`xattr` での解除は不要です。

```bash
curl -fsSL https://raw.githubusercontent.com/sojiro-o/chatgpt-translator/quicktranslate/scripts/install.sh | bash
```

スクリプトは GitHub Releases から最新版を取得し、SHA-256 とコード署名（改ざんの有無）を検証したうえで `/Applications/QuickTranslate.app`（書き込み不可の場合は `~/Applications/QuickTranslate.app`）へ配置して起動します。

### 2. 手動でインストール

1. [Releases](https://github.com/sojiro-o/chatgpt-translator/releases/latest) から `QuickTranslate.zip` をダウンロードして展開します。
2. `QuickTranslate.app` を「アプリケーション」フォルダへ移動します。
3. ブラウザでダウンロードした場合は Apple の公証がないため、初回だけ一度開こうとして警告が出たあとに「システム設定 › プライバシーとセキュリティ」の「このまま開く」を押します（またはターミナルで次を実行してから起動します）。

```bash
xattr -dr com.apple.quarantine /Applications/QuickTranslate.app
```

> 開発者向け: 未リリースのビルドや PR 検証用の成果物は [Actions](https://github.com/sojiro-o/chatgpt-translator/actions) の「Build QuickTranslate」からも取得できます（Artifacts の zip の中に `QuickTranslate.zip` が入っています）。

### 署名と Easydict 共存について

- Releases のビルドは ad-hoc 署名のみで、Apple の公証は受けていません。ad-hoc 署名はビルドごとに変わるため、macOS は更新後のアプリを別物とみなし、「入力監視」の許可が外れます。インストール用スクリプトは古い許可を自動でリセットするので、更新のたびに「システム設定 › プライバシーとセキュリティ › 入力監視」で QuickTranslate をもう一度オンにしてください（[Issue #8](https://github.com/sojiro-o/chatgpt-translator/issues/8)）。
- Easydict 本体と同時にインストール可能です（Bundle ID は `io.github.sojiro-o.QuickTranslate`、URL スキームは `quicktranslate` で、設定・保存先も別です）。

## アップデート

- 上のインストール用コマンドをもう一度実行します（起動中のアプリは自動で終了し、置き換えて起動し直します）。
- 更新後は「入力監視」をもう一度オンにしてください。
- メニューバーの **「アップデートを確認…」** を押すと、新しい版があるかを確認し、更新用のコマンドをコピーできます。自動の更新確認は行いません（押したときだけ GitHub に接続します）。

## アンインストール

Bundle ID が本家と別なので、Easydict 本体には影響しません。いずれの方法でも、OpenAI 側に保存されたデータは削除されません。

### 1. アプリのメニューから（おすすめ）

メニューバーの **「QuickTranslate をアンインストール…」** を選びます。ChatGPT からのログアウト、設定と Codex コンポーネントの削除、macOS の権限リセットを行い、アプリ本体をゴミ箱へ移動します。

### 2. ターミナルでアンインストール

アプリを起動できない場合などは、次の 1 行で同様に削除できます（確認プロンプトなしで削除対象を表示して実行します）。

```bash
curl -fsSL https://raw.githubusercontent.com/sojiro-o/chatgpt-translator/quicktranslate/scripts/uninstall.sh | bash
```

### 3. 手動で行う場合

1. 設定 › サービス › ChatGPT で「ログアウト」を押します（キーチェーンに保存された ChatGPT のログイン情報を Codex が削除します）。「ログイン時に起動」をオンにしていた場合はオフにします。
2. メニューバーのアイコンから「QuickTranslate を終了」を選びます。
3. ターミナルでアプリと保存データを削除します（Codex コンポーネントと Codex の状態は Application Support 内にあります）。

```bash
rm -rf /Applications/QuickTranslate.app
rm -rf ~/Library/Application\ Support/io.github.sojiro-o.QuickTranslate
rm -rf ~/Library/Caches/io.github.sojiro-o.QuickTranslate
rm -rf ~/Library/HTTPStorages/io.github.sojiro-o.QuickTranslate
rm -rf ~/Library/HTTPStorages/io.github.sojiro-o.QuickTranslate.binarycookies
rm -rf ~/Library/Saved\ Application\ State/io.github.sojiro-o.QuickTranslate.savedState
rm -rf ~/Library/WebKit/io.github.sojiro-o.QuickTranslate
defaults delete io.github.sojiro-o.QuickTranslate
rm -f ~/Library/Preferences/io.github.sojiro-o.QuickTranslate.plist
rm -rf "${TMPDIR:-/tmp}"/quicktranslate-codex-*
```

4. プライバシー権限を取り消します（「システム設定 › プライバシーとセキュリティ › 入力監視」で QuickTranslate を「−」で削除しても同じです）。

```bash
tccutil reset All io.github.sojiro-o.QuickTranslate
```

ログアウトせずに削除した場合は、「キーチェーンアクセス」で `"Codex Auth"` を検索し、QuickTranslate が作成した項目を削除してください。ご自身の Codex CLI の項目と取り違えないよう注意してください。迷う場合は、アプリを入れ直してログアウトしてから削除するのが確実です。

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
- ビルドは ad-hoc 署名のため、更新のたびに入力監視の許可をやり直す必要があります。インストール用スクリプトを使うと古い許可は自動でリセットされます（[Issue #8](https://github.com/sojiro-o/chatgpt-translator/issues/8)）。

## 設定

設定ウィンドウのタブは **一般 / サービス / ショートカット / 情報** のみです。

- **ショートカット**: 「⌘C を2回押して翻訳」のオン/オフ、2 回押しの判定時間（初期 600ms、200〜1500ms）
- **サービス**: ChatGPT、Apple 翻訳（Mac 内）、Apple Intelligence（Mac 内）の 3 つのみ表示（それぞれのオン/オフ、ChatGPT のログイン／ログアウト・モデル・思考量など）

## プライバシーと保存しないもの

### ローカルに保存しないもの・隔離設定

- 翻訳履歴、お気に入り、クエリ統計、単語帳、Anki 連携、訳文の自動コピー、音声の自動再生は無効です。
- アプリのログファイルは作成しません（ログに原文・訳文は出さず、文字数のみ出力します）。
- ポップアップを閉じると原文・訳文への参照を手放します。
- Codex 側も一時スレッド（ephemeral）で実行し、履歴保存（`history.persistence`）と Codex のログ出力をオフにしています。作業用の一時ディレクトリ（`$TMPDIR/quicktranslate-codex-<pid>`）はセッション終了・アプリ終了時に削除します。
- Codex の MCP・ツール・Web 検索・ファイル書き込み・ネットワーク権限は無効で、送信前に隔離設定を毎回確認します。
- **Apple 翻訳（Mac 内）** と **Apple Intelligence（Mac 内）** はどちらも Mac 内のモデルで処理し、原文・訳文を外部へ送信しません（Apple 翻訳で初回に必要な英語・日本語の言語データのダウンロードは macOS が行います）。

### 無効化した機能・外部サービス

- Firebase Analytics / Sentry（初期化しません。SDK 自体はバイナリに残っています → [Issue #3](https://github.com/sojiro-o/chatgpt-translator/issues/3)）
- クラッシュログの送信と保存
- Sparkle の自動更新（本家 Easydict の更新で上書きされません）
- 自動の更新確認（メニューの「アップデートを確認…」から手動で確認したときだけ通信します）
- GitHub Copilot のモデル取得
- 言語検出の Baidu / Google 問い合わせ
- Youdao・DeepL・Built-in AI など他の翻訳サービス（設定のサービス一覧に表示されるのは ChatGPT・Apple 翻訳（Mac 内）・Apple Intelligence（Mac 内）の 3 つのみで、既定で有効なのは ChatGPT のみです）

### OpenAI サーバー側での取り扱い

- ChatGPT（OpenAI）のサーバー側でのデータ処理・保持はアプリでは制御できず、削除も保証できません。
- モデルの学習に使われたくない場合は、ChatGPT の「設定 > データコントロール」で「すべての人のためにモデルを改善する」をオフにしてください。

## 外部通信先と目的

| 通信先 | 目的 | 備考 |
| --- | --- | --- |
| `github.com/openai/codex/releases`（および GitHub のダウンロード用 CDN） | Codex コンポーネントの初回ダウンロード | ユーザー操作時のみ |
| `auth.openai.com` | ChatGPT サインイン | ブラウザで認証 |
| `chatgpt.com/backend-api/` | 翻訳 | ChatGPT（Codex 経由） |
| `api.github.com` | 最新版の確認 | 「アップデートを確認…」を押したときだけ |

- **Apple 翻訳（Mac 内）** と **Apple Intelligence（Mac 内）** による翻訳はすべて Mac 内で処理され、アプリから外部への通信は行いません（Apple 翻訳の言語データのダウンロードは macOS が行います）。
- これ以外の通信は既定では行いません（他サービスのコードは残っていますが、無効化しています）。

## セキュリティ上の注意

1. **ChatGPT Plus の利用枠**: 翻訳は ChatGPT Plus の「Work と Codex」の利用枠（5 時間枠と週枠）を使います。コーディングで使う Codex と同じ枠のため、使い切ると翻訳もできなくなります。OpenAI は 2026 年 12 月から ChatGPT と Codex の枠を共有すると告知しています（詳細は未確定）。
2. **クレジットの自動消費**: ChatGPT のクレジットを購入済みの場合、利用枠を超えた後にクレジットが自動で消費されることがあります。避けるにはクレジットを持たないか、ChatGPT の「設定 > 使用量」で `Automatic reload` をオフにしてください（[Issue #2](https://github.com/sojiro-o/chatgpt-translator/issues/2)）。
3. **利用方式と仕様変更のリスク**: 公式 Codex 本体を起動して `codex login` でサインインする方式を第三者アプリから使うことについて、OpenAI の公式文書は許可も禁止も明記していません。公式には別の「Sign in with ChatGPT」方式がオープンソース向けに案内されています（[Issue #1](https://github.com/sojiro-o/chatgpt-translator/issues/1)）。仕様変更で使えなくなる可能性があります。個人のローカル利用を想定しており、商用・ホスティング用途には使わないでください。
4. **機密情報の取り扱い**: 機密文書を翻訳する場合は、所属組織の規程と OpenAI のデータ取り扱いを確認してください。
5. **ad-hoc 署名・Apple 公証なし**: 配布元の身元を証明する署名はありません。入手元（このリポジトリの Releases）を確認して利用してください。インストール用スクリプトは SHA-256 とコード署名の整合性（改ざんの有無）を確認します。

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
