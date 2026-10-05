#!/bin/bash
# 由原始碼重建 mediaremote-adapter 並放進 repo（取代預編譯品）。
#
# 做法：clone 上游 → 檢出釘選的 commit（並驗證 SHA）→ cmake 建置 → ad-hoc 簽章 →
#       複製 framework、perl 腳本、test client 到 repo 的 mediaremote-adapter/。
#
# 用法：Tools/build_adapter.sh [工作目錄]
#   工作目錄預設為 mktemp 建立的暫存目錄（結束時保留，路徑會印出來）。
#   環境變數 SKIP_INSTALL=1 時只建置、不覆蓋 repo 內的檔案。
#
# 安全注意：framework 只能「嵌入」app，不可「連結」（見 Vendor/mediaremote-adapter/PROVENANCE.md）。
# 本腳本不改任何簽章／entitlement 設定；framework 與 test client 皆為 ad-hoc 簽章，
# app 建置時由 Xcode 以 CodeSignOnCopy 重新簽章。

set -euo pipefail

REPO_URL="https://github.com/ungive/mediaremote-adapter"
TAG="v0.7.7"
PINNED_SHA="e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/mediaremote-adapter"
WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/davidnook-adapter.XXXXXX")}"
SRC="$WORK/mediaremote-adapter"
BUILD="$SRC/build"

echo "==> 工作目錄：$WORK"
mkdir -p "$WORK"

if [ ! -d "$SRC/.git" ]; then
    echo "==> clone $REPO_URL"
    git clone --quiet "$REPO_URL" "$SRC"
fi

echo "==> 檢出 $TAG（預期 $PINNED_SHA）"
git -C "$SRC" fetch --quiet --tags origin
git -C "$SRC" checkout --quiet --detach "$PINNED_SHA"
ACTUAL_SHA="$(git -C "$SRC" rev-parse HEAD)"
if [ "$ACTUAL_SHA" != "$PINNED_SHA" ]; then
    echo "錯誤：HEAD 為 $ACTUAL_SHA，與釘選的 $PINNED_SHA 不符" >&2
    exit 1
fi
TAG_SHA="$(git -C "$SRC" rev-parse "$TAG^{commit}" 2>/dev/null || true)"
if [ "$TAG_SHA" != "$PINNED_SHA" ]; then
    echo "錯誤：tag $TAG 指向 ${TAG_SHA:-（不存在）}，與釘選的 $PINNED_SHA 不符" >&2
    exit 1
fi
# 工作樹必須乾淨（排除 build 目錄），避免建出與 SHA 不符的內容。
if [ -n "$(git -C "$SRC" status --porcelain --untracked-files=no)" ]; then
    echo "錯誤：上游工作樹有未提交的修改" >&2
    exit 1
fi

echo "==> cmake 建置（Release，x86_64+arm64；CMakeLists 的 POST_BUILD 會 ad-hoc 簽章 framework）"
rm -rf "$BUILD"
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release > "$WORK/cmake-configure.log"
cmake --build "$BUILD" > "$WORK/cmake-build.log"

FRAMEWORK="$BUILD/MediaRemoteAdapter.framework"
TESTCLIENT="$BUILD/MediaRemoteAdapterTestClient"
SCRIPT="$SRC/bin/mediaremote-adapter.pl"
for f in "$FRAMEWORK" "$TESTCLIENT" "$SCRIPT"; do
    [ -e "$f" ] || { echo "錯誤：建置產物缺少 $f" >&2; exit 1; }
done

echo "==> ad-hoc 簽章（不加任何 entitlement、不改任何簽章旗標）"
codesign --force --deep --sign - "$FRAMEWORK"
codesign --force --sign - "$TESTCLIENT"
codesign --verify --deep --strict "$FRAMEWORK"
codesign --verify --strict "$TESTCLIENT"

echo "==> 檢查架構"
lipo -archs "$FRAMEWORK/Versions/A/MediaRemoteAdapter"
lipo -archs "$TESTCLIENT"

if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo "==> SKIP_INSTALL=1：不覆蓋 repo。產物在 $BUILD"
    exit 0
fi

echo "==> 複製到 $DEST"
mkdir -p "$DEST"
rm -rf "$DEST/MediaRemoteAdapter.framework"
# -R 保留 framework 內的符號連結（Versions/Current 等）。
cp -R "$FRAMEWORK" "$DEST/MediaRemoteAdapter.framework"
cp "$TESTCLIENT" "$DEST/MediaRemoteAdapterTestClient"
cp "$SCRIPT" "$DEST/mediaremote-adapter.pl"
chmod 755 "$DEST/MediaRemoteAdapterTestClient"

echo "==> 完成。來源：$REPO_URL @ $PINNED_SHA（$TAG）"
echo "    驗證：/usr/bin/perl $DEST/mediaremote-adapter.pl $DEST/MediaRemoteAdapter.framework $DEST/MediaRemoteAdapterTestClient test"
