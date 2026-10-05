#!/bin/bash
# 建置 Release、ad-hoc 簽章的 DavidNook.app，輸出到 ./build/DavidNook.app。
#
# 用法：Tools/build_release.sh [選項]
#   --out <目錄>        輸出目錄（預設：<專案>/build；DavidNook.app 與 build.log 會放在這裡）
#   --derived <目錄>    DerivedData 目錄（預設：<輸出目錄>/DerivedData）
#   --clean             建置前先清掉 DerivedData（乾淨建置）
#   --rebuild-adapter   先用 Tools/build_adapter.sh 由上游原始碼重建 mediaremote-adapter（需要 cmake）
#   -h, --help          顯示這段說明
#
# 需求：macOS 14 以上、完整的 Xcode（不是只有 Command Line Tools）。不需要開發者帳號：
# 使用 ad-hoc 簽章（codesign --sign -），不會、也不能公證。cmake 只有在 --rebuild-adapter 時才需要。
#
# 安全：本腳本不會關閉 Hardened Runtime、不會放寬 entitlements，也不會停用 library validation；
# 建置完成後會檢查「Hardened Runtime 仍開啟」與「主程式沒有連結 MediaRemoteAdapter.framework」
# （framework 只能嵌入；連結會讓 ad-hoc＋Hardened Runtime 的 app 在啟動時被 dyld 擋下）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/build"
DERIVED=""
CLEAN=0
REBUILD_ADAPTER=0

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    echo "錯誤：$*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --out) [ $# -ge 2 ] || die "--out 需要一個目錄"; OUT_DIR="$2"; shift 2 ;;
        --derived) [ $# -ge 2 ] || die "--derived 需要一個目錄"; DERIVED="$2"; shift 2 ;;
        --clean) CLEAN=1; shift ;;
        --rebuild-adapter) REBUILD_ADAPTER=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) die "不認得的參數：$1（用 --help 看說明）" ;;
    esac
done

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
[ -n "$DERIVED" ] || DERIVED="$OUT_DIR/DerivedData"
LOG="$OUT_DIR/build.log"
APP="$OUT_DIR/DavidNook.app"

# --- 1. 檢查工具 -------------------------------------------------------------
if ! command -v xcodebuild > /dev/null 2>&1; then
    die "找不到 xcodebuild。請先從 App Store 安裝 Xcode，開啟一次完成初始設定，
      再執行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
      （這個指令要你自己執行；本腳本不使用 sudo）"
fi
# 注意：不要把 xcodebuild 的輸出直接接給 head（pipefail 下 head 提早結束會讓 xcodebuild 收到 SIGPIPE 而誤判失敗）。
XCODE_OUTPUT=""
for _attempt in 1 2 3; do # xcodebuild 偶爾會在載入外掛時失敗一次，重試幾次再判定
    if XCODE_OUTPUT="$(xcodebuild -version 2> /dev/null)" && [ -n "$XCODE_OUTPUT" ]; then break; fi
    XCODE_OUTPUT=""
done
if [ -z "$XCODE_OUTPUT" ]; then
    die "xcodebuild 無法使用，通常是只裝了 Command Line Tools、沒有完整的 Xcode，或尚未同意授權。
      請安裝 Xcode 後執行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
      並開啟 Xcode 一次（或執行 sudo xcodebuild -license accept）。本腳本不使用 sudo。"
fi
for tool in codesign lipo ditto otool plutil; do
    command -v "$tool" > /dev/null 2>&1 || die "找不到 $tool（應該隨 macOS／Xcode 提供）"
done
XCODE_VERSION="$(printf '%s\n' "$XCODE_OUTPUT" | head -n 1)"
echo "==> 工具：$XCODE_VERSION"

# --- 2. （可選）重建 mediaremote-adapter ---------------------------------------
if [ "$REBUILD_ADAPTER" = "1" ]; then
    command -v cmake > /dev/null 2>&1 || die "--rebuild-adapter 需要 cmake，但找不到。
      請安裝 cmake（例如 brew install cmake，或從 https://cmake.org/download/ 下載）後再試。
      不重建 adapter 時不需要 cmake：repo 內已有由上游 v0.7.7 原始碼建好的產物。"
    command -v git > /dev/null 2>&1 || die "重建 adapter 需要 git"
    echo "==> 重建 mediaremote-adapter（Tools/build_adapter.sh）"
    "$ROOT/Tools/build_adapter.sh"
fi

ADAPTER="$ROOT/mediaremote-adapter"
for f in "$ADAPTER/MediaRemoteAdapter.framework" "$ADAPTER/MediaRemoteAdapterTestClient" "$ADAPTER/mediaremote-adapter.pl"; do
    [ -e "$f" ] || die "缺少 $f。請先執行 Tools/build_adapter.sh（需要 cmake）或重新取得完整的原始碼。"
done

# --- 3. 建置 -----------------------------------------------------------------
if [ "$CLEAN" = "1" ] && [ -d "$DERIVED" ]; then
    echo "==> 清除 $DERIVED"
    rm -rf "$DERIVED"
fi
echo "==> xcodebuild Release（ad-hoc 簽章；完整輸出：$LOG）"
set +e
xcodebuild \
    -project "$ROOT/boringNotch.xcodeproj" \
    -scheme boringNotch \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    build > "$LOG" 2>&1
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ]; then
    echo "--- build.log 最後 40 行 ---" >&2
    tail -n 40 "$LOG" >&2
    die "xcodebuild 失敗（結束碼 $STATUS）。完整記錄：$LOG"
fi

PRODUCT="$DERIVED/Build/Products/Release/DavidNook.app"
[ -d "$PRODUCT" ] || die "建置成功但找不到 $PRODUCT（見 $LOG）"

rm -rf "$APP"
ditto "$PRODUCT" "$APP"

# --- 4. 驗證與摘要 -------------------------------------------------------------
echo "==> 驗證簽章"
codesign --verify --deep --strict "$APP" || die "codesign 驗證失敗"
SIGN_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
printf '%s\n' "$SIGN_INFO" | grep -E '^(Identifier|Format|CodeDirectory|Signature|CDHash|TeamIdentifier)' | sed 's/^/    /' || true
if [[ "$SIGN_INFO" != *flags=*runtime* ]]; then
    die "Hardened Runtime 未啟用（codesign flags 沒有 runtime）。這會削弱安全設定，請檢查專案設定。"
fi
echo "    Hardened Runtime：開啟"

EXECUTABLE="$APP/Contents/MacOS/DavidNook"
LINKED_LIBS="$(otool -L "$EXECUTABLE")"
if [[ "$LINKED_LIBS" == *MediaRemoteAdapter* ]]; then
    die "主程式連結了 MediaRemoteAdapter.framework。framework 只能嵌入、不可連結（會被 dyld library validation 擋下）。"
fi
echo "    MediaRemoteAdapter.framework：僅嵌入（未連結）"

echo "==> Entitlements"
codesign -d --entitlements - --xml "$APP" 2> /dev/null | plutil -p - | sed 's/^/    /'

echo "==> 架構：$(lipo -archs "$EXECUTABLE")（預設只建置這台 Mac 的架構；不是 Universal）"
echo "==> 完成：$APP"
echo "    下一步：Tools/install.sh（預設複製到 ~/Applications），或直接開啟 $APP"
