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

RESOLVED_HOME="$(cd "$HOME" && pwd -P)"
if [ -z "$RESOLVED_HOME" ] || [ "$RESOLVED_HOME" = "/" ]; then
  echo "エラー: ホームディレクトリの解決に失敗しました。" >&2
  exit 1
fi

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"

readonly APP_SUPPORT_DIR="$RESOLVED_HOME/Library/Application Support/$BUNDLE_ID"
readonly CACHES_DIR="$RESOLVED_HOME/Library/Caches/$BUNDLE_ID"
readonly HTTP_STORAGES_DIR="$RESOLVED_HOME/Library/HTTPStorages/$BUNDLE_ID"
readonly HTTP_COOKIES_FILE="$RESOLVED_HOME/Library/HTTPStorages/$BUNDLE_ID.binarycookies"
readonly SAVED_STATE_DIR="$RESOLVED_HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
readonly WEBKIT_DIR="$RESOLVED_HOME/Library/WebKit/$BUNDLE_ID"
readonly PREFS_PLIST="$RESOLVED_HOME/Library/Preferences/$BUNDLE_ID.plist"
readonly CODEX_COMPONENTS_DIR="$APP_SUPPORT_DIR/codex/components"
readonly CODEX_HOME_DIR="$APP_SUPPORT_DIR/codex/state"

LOGOUT_WORK_DIR=""
cleanup() {
  if [ -n "${LOGOUT_WORK_DIR:-}" ] && [ -d "$LOGOUT_WORK_DIR" ]; then
    rm -rf "$LOGOUT_WORK_DIR"
  fi
}
trap cleanup EXIT

echo "QuickTranslate をアンインストールします。"
echo "以下のアプリ本体・設定・データ・権限を削除します（Easydict 本体には影響しません）:"
echo "  - /Applications/$APP_NAME および ~/Applications/$APP_NAME（Bundle ID が一致するもの）"
echo "  - ChatGPT のログイン情報（Codex 経由でログアウト）"
echo "  - ~/Library/Application Support/$BUNDLE_ID"
echo "  - ~/Library/Caches/$BUNDLE_ID"
echo "  - ~/Library/HTTPStorages/$BUNDLE_ID および .binarycookies"
echo "  - ~/Library/Saved Application State/$BUNDLE_ID.savedState"
echo "  - ~/Library/WebKit/$BUNDLE_ID"
echo "  - ~/Library/Preferences/$BUNDLE_ID.plist および UserDefaults 設定"
echo "  - $TMP_BASE/quicktranslate-codex-*"
echo "  - macOS のプライバシー権限（tccutil reset All $BUNDLE_ID）"
echo ""

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  echo "実行中の $PROCESS_NAME を終了しています..."
  pkill -x "$PROCESS_NAME" || true
  waited=0
  while pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; do
    if [ "$waited" -ge 10 ]; then
      echo "警告: $PROCESS_NAME が通常終了しないため強制終了します。" >&2
      pkill -9 -x "$PROCESS_NAME" || true
      sleep 1
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
fi

run_with_timeout() {
  local max_seconds="$1"
  shift
  "$@" &
  local pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$max_seconds" ]; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

find_codex_binary() {
  local host_arch preferred_arch fallback_arch arm64_cap candidate
  host_arch="$(uname -m)"
  if [ "$host_arch" = "arm64" ]; then
    preferred_arch="aarch64"
    fallback_arch="x86_64"
  else
    arm64_cap="$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)"
    if [ "$arm64_cap" = "1" ]; then
      preferred_arch="aarch64"
      fallback_arch="x86_64"
    else
      preferred_arch="x86_64"
      fallback_arch="aarch64"
    fi
  fi

  for candidate in \
    "$CODEX_COMPONENTS_DIR/0.153.4/$preferred_arch/bin/codex" \
    "$CODEX_COMPONENTS_DIR/0.153.4/$fallback_arch/bin/codex" \
    "$CODEX_COMPONENTS_DIR/0.134.0/$preferred_arch/bin/codex" \
    "$CODEX_COMPONENTS_DIR/0.134.0/$fallback_arch/bin/codex"; do
    if [ -x "$candidate" ] && [ ! -L "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for candidate in "$CODEX_COMPONENTS_DIR"/*/*/bin/codex; do
    if [ -x "$candidate" ] && [ ! -L "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

LOGOUT_STATUS="skipped"
CODEX_BIN=""
if [ -d "$CODEX_COMPONENTS_DIR" ]; then
  CODEX_BIN="$(find_codex_binary || true)"
fi

if [ -n "$CODEX_BIN" ]; then
  echo "ChatGPT からログアウトしています..."
  LOGOUT_WORK_DIR="$(mktemp -d "$TMP_BASE/quicktranslate-uninstall.XXXXXX")"
  chmod 700 "$LOGOUT_WORK_DIR"
  LOGOUT_CWD="$LOGOUT_WORK_DIR/work"
  LOGOUT_SQLITE="$LOGOUT_WORK_DIR/sqlite"
  LOGOUT_LOGS="$LOGOUT_WORK_DIR/logs"
  mkdir -p -m 700 "$LOGOUT_CWD" "$LOGOUT_SQLITE" "$LOGOUT_LOGS" "$CODEX_HOME_DIR"

  BIN_DIR="$(dirname "$CODEX_BIN")"
  PACKAGE_DIR="$(dirname "$BIN_DIR")"
  RELEASE_DIR="$(dirname "$PACKAGE_DIR")"
  RELEASE_VER="$(basename "$RELEASE_DIR")"

  env_args=(
    "HOME=$RESOLVED_HOME"
    "CODEX_HOME=$CODEX_HOME_DIR"
    "PATH=$PACKAGE_DIR/codex-path:/usr/bin:/bin:/usr/sbin:/sbin"
    "TMPDIR=${TMPDIR:-/tmp}"
    "LANG=en_US.UTF-8"
    "RUST_LOG=off"
  )
  for var_name in \
    HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY \
    http_proxy https_proxy all_proxy no_proxy \
    CODEX_CA_CERTIFICATE SSL_CERT_FILE; do
    var_val="$(printenv "$var_name" 2>/dev/null || true)"
    if [ -n "$var_val" ]; then
      env_args=("${env_args[@]}" "${var_name}=${var_val}")
    fi
  done

  codex_args=(
    "logout"
    "-c" 'cli_auth_credentials_store="keyring"'
    "-c" "skills.bundled.enabled=false"
    "-c" "skills.include_instructions=false"
    "-c" 'forced_login_method="chatgpt"'
    "-c" 'model_providers.quicktranslate.name="OpenAI"'
    "-c" 'model_providers.quicktranslate.wire_api="responses"'
    "-c" "model_providers.quicktranslate.requires_openai_auth=true"
    "-c" "model_providers.quicktranslate.supports_websockets=false"
    "-c" 'model_provider="quicktranslate"'
    "-c" 'chatgpt_base_url="https://chatgpt.com/backend-api/"'
    "-c" "sqlite_home=\"$LOGOUT_SQLITE\""
    "-c" "log_dir=\"$LOGOUT_LOGS\""
  )
  if [ "$RELEASE_VER" != "0.134.0" ]; then
    codex_args=("${codex_args[@]}" "--disable" "secret_auth_storage")
  fi

  if (
    cd "$LOGOUT_CWD"
    run_with_timeout 20 env -i "${env_args[@]}" "$CODEX_BIN" "${codex_args[@]}"
  ) >/dev/null 2>&1; then
    LOGOUT_STATUS="succeeded"
    echo "ChatGPT からログアウトしました。"
  else
    LOGOUT_STATUS="failed"
    echo "警告: ChatGPT からの自動ログアウトに失敗しました。削除を続行します。" >&2
  fi
fi

echo "設定・データ・一時ファイルを削除しています..."
rm -rf \
  "$APP_SUPPORT_DIR" \
  "$CACHES_DIR" \
  "$HTTP_STORAGES_DIR" \
  "$HTTP_COOKIES_FILE" \
  "$SAVED_STATE_DIR" \
  "$WEBKIT_DIR"

if [ -n "$TMP_BASE" ] && [ "$TMP_BASE" != "/" ] && [ -d "$TMP_BASE" ]; then
  for tmp_item in "$TMP_BASE"/quicktranslate-codex-*; do
    if [ -e "$tmp_item" ] || [ -L "$tmp_item" ]; then
      rm -rf "$tmp_item"
    fi
  done
fi

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$PREFS_PLIST"

echo "macOS のプライバシー権限をリセットしています..."
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true

remove_app_if_matching() {
  local app_path="$1"
  if [ ! -d "$app_path" ] || [ -L "$app_path" ]; then
    return 0
  fi
  case "$app_path" in
    */"$APP_NAME")
      ;;
    *)
      echo "スキップ: 想定外のパスです ($app_path)" >&2
      return 0
      ;;
  esac
  local plist="$app_path/Contents/Info.plist"
  if [ ! -f "$plist" ]; then
    echo "スキップ: Info.plist が見つかりません ($app_path)" >&2
    return 0
  fi
  local found_id=""
  found_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  if [ "$found_id" != "$BUNDLE_ID" ]; then
    echo "スキップ: CFBundleIdentifier が一致しないため削除しません ($app_path: ${found_id:-不明})" >&2
    return 0
  fi
  echo "アプリを削除しています: $app_path"
  rm -rf "$app_path"
}

remove_app_if_matching "/Applications/$APP_NAME"
remove_app_if_matching "$RESOLVED_HOME/Applications/$APP_NAME"

echo ""
echo "QuickTranslate のアンインストールが完了しました。"
if [ "$LOGOUT_STATUS" = "succeeded" ]; then
  echo "  キーチェーン: Codex 経由でログアウトしました。念のため確認する場合は、「キーチェーンアクセス」で \"Codex Auth\" を検索してください（ご自身の Codex CLI の項目を誤って削除しないよう注意してください）。"
else
  echo "  キーチェーン: 自動ログアウトを実行または完了できませんでした。ログイン情報が残っている場合は、「キーチェーンアクセス」で \"Codex Auth\" を検索し、QuickTranslate 用の項目を削除してください（ご自身の Codex CLI の項目を誤って削除しないよう注意してください）。"
fi
echo "  注意: OpenAI 側に保存されたデータは削除されません。"
