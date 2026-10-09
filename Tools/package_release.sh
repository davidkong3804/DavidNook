#!/bin/bash
# 把 build/DavidNook.app 打包成可上傳到 GitHub Release 的檔案（只在本機產生檔案，不上傳、不發布）。
#
# 用法：Tools/package_release.sh <版本號> [選項]
#   <版本號>            完整語意化版本，不含 v，例如 0.2.0-beta.1 或 0.2.0
#                       必須與 App 的 CFBundleShortVersionString 逐字相同（App 內的自動更新靠它判斷新舊與防降版）
#   --app <路徑>        要打包的 .app（預設：<專案>/build/DavidNook.app，由 Tools/build_release.sh 產生）
#   --out <目錄>        輸出目錄（預設：<專案>/dist；已在 .gitignore）
#   -h, --help          顯示這段說明
#
# 產生：
#   dist/DavidNook-<版本>-arm64.zip           ditto -c -k --keepParent（App 內的自動更新只認這個檔名格式）
#   dist/DavidNook-<版本>-arm64.zip.sha256    格式「<64 位十六進位>  <檔名>」
#
# 打包前會檢查：簽章（codesign --verify --deep --strict）、Hardened Runtime、含 arm64、
# bundle id、CFBundleShortVersionString 與版本相符、沒有多餘的 entitlement（只允許目前專案用到的那幾個）。
# 最後只「印出」建立 GitHub Release 的範例指令，不會執行它；發布由你自己決定。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DavidNook.app"
OUT_DIR="$ROOT/dist"
VERSION=""
BUNDLE_ID="io.github.davidkong3804.DavidNook"
# 允許出現在 App 上的 entitlement（與 boringNotch/boringNotch.entitlements 一致）；多出任何一個就拒絕打包。
ALLOWED_ENTITLEMENTS=(
    "com.apple.security.app-sandbox"
    "com.apple.security.automation.apple-events"
    "com.apple.security.files.user-selected.read-write"
    "com.apple.security.network.client"
    "com.apple.security.temporary-exception.apple-events"
)

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    echo "錯誤：$*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app) [ $# -ge 2 ] || die "--app 需要一個路徑"; APP="$2"; shift 2 ;;
        --out) [ $# -ge 2 ] || die "--out 需要一個目錄"; OUT_DIR="$2"; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        -*) die "不認得的參數：$1（用 --help 看說明）" ;;
        *) [ -z "$VERSION" ] || die "只能給一個版本號"; VERSION="$1"; shift ;;
    esac
done

[ -n "$VERSION" ] || { usage >&2; die "缺少版本號"; }
# SemVer 2.0.0 規範的官方正規表示式（不含 v 前綴、不含建置後綴）。
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?$'
[[ "$VERSION" =~ $SEMVER_RE ]] || die "版本號格式不對：$VERSION（要像 0.2.0 或 0.2.0-beta.1，不含 v 前綴）"

for tool in codesign lipo ditto plutil shasum unzip; do
    command -v "$tool" > /dev/null 2>&1 || die "找不到 $tool（應該隨 macOS 提供）"
done
[ -d "$APP" ] || die "找不到 $APP。請先執行 Tools/build_release.sh。"

# --- 檢查 -----------------------------------------------------------------
echo "==> 檢查 $APP"
codesign --verify --deep --strict "$APP" 2> /dev/null || die "codesign 驗證失敗（簽章無效或內容被改過）"
SIGN_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
[[ "$SIGN_INFO" == *flags=*runtime* ]] || die "Hardened Runtime 未啟用，拒絕打包"
echo "    簽章：通過；Hardened Runtime：開啟"

EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE_NAME")"
[[ " $ARCHS " == *" arm64 "* ]] || die "主程式沒有 arm64（目前：$ARCHS），拒絕打包"
echo "    架構：$ARCHS"

ACTUAL_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")"
[ "$ACTUAL_ID" = "$BUNDLE_ID" ] || die "bundle id 是 $ACTUAL_ID，應為 $BUNDLE_ID"
ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
[ "$ACTUAL_VERSION" = "$VERSION" ] || die "App 的 CFBundleShortVersionString 是 $ACTUAL_VERSION，與要打包的版本 $VERSION 不同。
      請把 Xcode 專案的 MARKETING_VERSION 改成 $VERSION 後重新建置（自動更新靠這個字串判斷新舊）。"
echo "    版本：$ACTUAL_VERSION（與參數相符）"

ENT_KEYS="$(codesign -d --entitlements - --xml "$APP" 2> /dev/null | plutil -convert json -o - - | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin).keys())))')"
while IFS= read -r key; do
    [ -n "$key" ] || continue
    allowed=0
    for ok in "${ALLOWED_ENTITLEMENTS[@]}"; do [ "$key" = "$ok" ] && allowed=1; done
    [ "$allowed" = "1" ] || die "App 帶有不在允許清單的 entitlement：$key（自動更新會拒絕擴權的新版）"
done <<< "$ENT_KEYS"
echo "    Entitlements：皆在允許清單內"

# --- 打包 -----------------------------------------------------------------
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
ZIP_NAME="DavidNook-$VERSION-arm64.zip"
ZIP="$OUT_DIR/$ZIP_NAME"
rm -f "$ZIP" "$ZIP.sha256"
echo "==> 打包 $ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ZIP"

# 內容檢查：每個項目都在 DavidNook.app/ 底下（App 內的自動更新也會做同樣的檢查）。
BAD="$(unzip -Z1 "$ZIP" | grep -v '^DavidNook\.app/' || true)"
[ -z "$BAD" ] || die "zip 內有不在 DavidNook.app/ 底下的項目：$BAD"
[ "$(basename "$APP")" = "DavidNook.app" ] || die "App 資料夾名稱必須是 DavidNook.app（目前：$(basename "$APP")）"

HASH="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$HASH" "$ZIP_NAME" > "$ZIP.sha256"
SIZE="$(stat -f %z "$ZIP")"
echo "    $ZIP（$SIZE 位元組）"
echo "    $ZIP.sha256"
echo "    SHA-256：$HASH"

# --- 範例指令（只印出，不執行） ------------------------------------------------
TAG="v$VERSION"
PRE_FLAG=""
[[ "$VERSION" == *-* ]] && PRE_FLAG=" --prerelease"
cat << EOF

==> 要發布時，由你自己執行（本腳本不會執行它；內文請自行補上說明）：

    gh release create $TAG \\
        "$ZIP" \\
        "$ZIP.sha256" \\
        --repo davidkong3804/DavidNook --title "DavidNook $VERSION"$PRE_FLAG \\
        --notes 'SHA-256：\`$HASH\`'

    內文那一行「SHA-256：\`<雜湊>\`」是 App 的備援校驗來源；同 release 的 .sha256 檔案優先。
    兩者不一致時，App 內的更新會拒絕。
EOF
