#!/bin/bash
# 把本機建置好的 DavidNook.app 複製到指定資料夾（預設 ~/Applications）。
#
# 用法：Tools/install.sh [選項]
#   --dest <目錄>   安裝目的地（預設：$HOME/Applications；不存在會建立）
#   --app <路徑>    要安裝的 DavidNook.app（預設：<專案>/build/DavidNook.app）
#   -h, --help      顯示這段說明
#
# 做的事：複製 .app（ditto，保留簽章）→ 對「複製後的本機建置副本」移除 quarantine 屬性
# （xattr -dr com.apple.quarantine）→ 驗證簽章。
# 不做的事：不使用 sudo、不修改登入項目（要開機自動啟動請在 App 的「設定 → 一般」自行開啟）、
# 不改任何系統設定、不碰 /Applications 以外的東西。找不到建置產物時請先執行 Tools/build_release.sh。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/Applications"
SRC="$ROOT/build/DavidNook.app"

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    echo "錯誤：$*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dest) [ $# -ge 2 ] || die "--dest 需要一個目錄"; DEST="$2"; shift 2 ;;
        --app) [ $# -ge 2 ] || die "--app 需要一個路徑"; SRC="$2"; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        *) die "不認得的參數：$1（用 --help 看說明）" ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    die "請不要用 root／sudo 執行；本腳本只會寫入你指定的使用者資料夾。"
fi

if [ ! -d "$SRC" ] || [ ! -x "$SRC/Contents/MacOS/DavidNook" ]; then
    die "找不到建置產物：$SRC
      請先執行 Tools/build_release.sh 建置，或用 --app 指定 DavidNook.app 的位置。"
fi

mkdir -p "$DEST" || die "無法建立目的資料夾：$DEST"
DEST="$(cd "$DEST" && pwd)"
TARGET="$DEST/DavidNook.app"

# 目的地的 App 正在執行時不要覆蓋（避免把執行中的程式換掉）。
if pgrep -f "$TARGET/Contents/MacOS/DavidNook" > /dev/null 2>&1; then
    die "$TARGET 正在執行。請先結束 DavidNook（選單列圖示 → 結束）再安裝。"
fi

echo "==> 安裝到 $TARGET"
if [ -e "$TARGET" ]; then
    # 只刪我們要換掉的那個 .app（路徑一定以 /DavidNook.app 結尾）。
    case "$TARGET" in
        */DavidNook.app) rm -rf "$TARGET" ;;
        *) die "內部錯誤：目標路徑不是 DavidNook.app" ;;
    esac
fi
ditto "$SRC" "$TARGET"

# 本機建置的副本通常沒有 quarantine 屬性（沒有從網路下載）；若是從壓縮檔等管道取得，移除後才不會被擋。
# 這只對剛複製出來的副本動作，指令找不到該屬性時的警告可以忽略。
xattr -dr com.apple.quarantine "$TARGET" 2> /dev/null || true

codesign --verify --deep --strict "$TARGET" || die "安裝後簽章驗證失敗：$TARGET"
echo "    簽章驗證通過（ad-hoc；每次重新建置 cdhash 都會改變，系統授權可能需要重新給）"
echo "==> 完成。開啟方式：open \"$TARGET\""
echo "    第一次開啟若被 Gatekeeper 擋下，請依系統提示處理（見 README「Gatekeeper」一節）。"
