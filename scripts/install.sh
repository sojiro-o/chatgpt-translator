#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "エラー: QuickTranslate は macOS 専用です。" >&2
  exit 1
fi

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "エラー: HOME 環境変数が正しく設定されていません。" >&2
  exit 1
fi

readonly BUNDLE_ID="io.github.sojiro-o.QuickTranslate"
readonly APP_NAME="QuickTranslate.app"
readonly PROCESS_NAME="QuickTranslate"
readonly ZIP_URL="https://github.com/sojiro-o/chatgpt-translator/releases/latest/download/QuickTranslate.zip"
readonly SHA256_URL="https://github.com/sojiro-o/chatgpt-translator/releases/latest/download/QuickTranslate.zip.sha256"
readonly SIGNING_REQ='identifier "io.github.sojiro-o.QuickTranslate" and certificate leaf = H"2697524092a9b371d9be557c80d82f6a20557eb1"'

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
WORK_DIR="$(mktemp -d "$TMP_BASE/quicktranslate-install.XXXXXX")"

cleanup() {
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

echo "QuickTranslate をダウンロードしています..."
curl -fL --proto '=https' --tlsv1.2 --retry 3 -o "$WORK_DIR/QuickTranslate.zip" "$ZIP_URL"
curl -fL --proto '=https' --tlsv1.2 --retry 3 -o "$WORK_DIR/QuickTranslate.zip.sha256" "$SHA256_URL"

echo "SHA-256 を検証しています..."
(cd "$WORK_DIR" && shasum -a 256 -c QuickTranslate.zip.sha256)

UNPACK_DIR="$WORK_DIR/unpacked"
mkdir -p "$UNPACK_DIR"
echo "アーカイブを展開しています..."
ditto -x -k "$WORK_DIR/QuickTranslate.zip" "$UNPACK_DIR"

NEW_APP="$UNPACK_DIR/$APP_NAME"
if [ ! -d "$NEW_APP" ]; then
  echo "エラー: 展開後の $APP_NAME が見つかりませんでした。" >&2
  exit 1
fi

echo "コード署名とバンドル ID を検証しています..."
if ! codesign --verify --strict -R "=$SIGNING_REQ" "$NEW_APP"; then
  echo "エラー: アプリの署名検証に失敗しました。インストールを中止します。" >&2
  exit 1
fi

NEW_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$NEW_APP/Contents/Info.plist")"
if [ "$NEW_BUNDLE_ID" != "$BUNDLE_ID" ]; then
  echo "エラー: CFBundleIdentifier が一致しません ($NEW_BUNDLE_ID)。インストールを中止します。" >&2
  exit 1
fi

BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$NEW_APP/Contents/Info.plist" 2>/dev/null || echo "不明")"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NEW_APP/Contents/Info.plist" 2>/dev/null || echo "")"

SYSTEM_APP="/Applications/$APP_NAME"
USER_APPS_DIR="$HOME/Applications"
USER_APP="$USER_APPS_DIR/$APP_NAME"

if [ -d "$SYSTEM_APP" ]; then
  if [ -w "/Applications" ] && [ -w "$SYSTEM_APP" ]; then
    DEST_DIR="/Applications"
  else
    echo "エラー: $SYSTEM_APP が存在しますが、書き込み権限がありません。" >&2
    exit 1
  fi
elif [ -d "$USER_APP" ]; then
  DEST_DIR="$USER_APPS_DIR"
elif [ -w "/Applications" ]; then
  DEST_DIR="/Applications"
else
  mkdir -p "$USER_APPS_DIR"
  DEST_DIR="$USER_APPS_DIR"
fi

DEST_APP="$DEST_DIR/$APP_NAME"

case "$DEST_APP" in
  */"$APP_NAME")
    ;;
  *)
    echo "エラー: インストール先パスが不正です ($DEST_APP)。" >&2
    exit 1
    ;;
esac

TCC_RESET_DONE=0
if [ -d "$DEST_APP" ]; then
  if ! codesign --verify --strict -R "=$SIGNING_REQ" "$DEST_APP" >/dev/null 2>&1; then
    echo "既存のアプリが異なる署名（ad-hoc 版など）のため、古い権限設定をリセットします..."
    tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
    TCC_RESET_DONE=1
    echo "入力監視の許可をもう一度求められます。"
  fi
fi

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  echo "実行中の $PROCESS_NAME を終了しています..."
  pkill -x "$PROCESS_NAME" || true
  waited=0
  while pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; do
    if [ "$waited" -ge 10 ]; then
      echo "エラー: $PROCESS_NAME が終了しませんでした。手動で終了してからもう一度実行してください。" >&2
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
fi

if [ -e "$DEST_APP" ] || [ -L "$DEST_APP" ]; then
  rm -rf "$DEST_APP"
fi

echo "$DEST_APP に配置しています..."
ditto "$NEW_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" >/dev/null 2>&1 || true

echo "QuickTranslate を起動しています..."
open "$DEST_APP"

echo ""
echo "QuickTranslate のインストールが完了しました。"
if [ -n "$SHORT_VERSION" ]; then
  echo "  バージョン: $SHORT_VERSION (build $BUILD_VERSION)"
else
  echo "  ビルド番号: $BUILD_VERSION"
fi
echo "  インストール先: $DEST_APP"
echo "  今後の更新: メニューバーの「アップデートを確認…」から更新できます。"
if [ "$TCC_RESET_DONE" -eq 1 ]; then
  echo "  権限について: 古い署名の権限をリセットしたため、入力監視の許可をもう一度求められます（「システム設定 > プライバシーとセキュリティ > 入力監視」）。"
else
  echo "  権限について: 初回は入力監視の許可が必要です（「システム設定 > プライバシーとセキュリティ > 入力監視」）。"
fi
