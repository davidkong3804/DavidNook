# DavidNook

macOS 瀏海工具：完全本機、無伺服器、無遙測、無自動更新、無 AI、無帳號。

DavidNook 是 [boring.notch](https://github.com/TheBoredTeam/boring.notch)（The Bored Team 與貢獻者，GPL-3.0）的 **GPL-3.0 fork**，
基於 tag `v2.8-rc.1`（完整 commit SHA：`fb2643121741c6ba6102d5ef2b2c7a787f26fad1`）。上游 git 歷史完整保留以保留署名；
原始檔頭署名與 `Original source:` 註解皆未移除。授權見 [`LICENSE`](LICENSE)（上游 GPL-3.0 原文）與
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 功能範圍（M1）

- 瀏海展開／收合與 hover、多螢幕、無瀏海螢幕
- Now Playing（播放／暫停／上一首／下一首）與逐行同步歌詞（LRCLIB；簡體來源自動轉繁體，可逐曲調整偏移）
- 剪貼簿歷史（文字／圖片／檔案路徑；搜尋、類型篩選、釘選、點選貼回、暫停記錄、筆數與保留時間可設；設定 → 剪貼簿）。略過密碼管理員標記的項目；資料只存在本機。「點選後自動貼上」為實驗性選項（預設關）
- 分頁結構可擴充（`NotchViews` 列舉 + `TabSelectionView` + `ContentView` 的 switch）；目前有 Home 與剪貼簿兩個分頁

已從上游移除：Shelf（含 QuickShare/AirDrop）、行事曆／提醒事項、Mirror 相機、電池 live activity、
HUD 取代與 XPC helper、音訊波形／輸出裝置切換、通知監看與 OTP 偵測、Sparkle 自動更新、
Spotify 與 YouTube Music 專用 controller。權限只剩：網路 client（歌詞）與 Apple 事件（僅限「音樂」app 備援）。

## 自行建置與 ad-hoc 簽章（暫定；M4 會完善）

需求：macOS 14+、Xcode。不需要開發者帳號，也不會公證；每次重新建置 cdhash 會變，系統授權（如自動化）可能需要重新授權。

```sh
xcodebuild -scheme boringNotch -configuration Release -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  -derivedDataPath build build
# 產出：build/Build/Products/Release/DavidNook.app
```

（內部 Xcode project／scheme／target 名稱仍沿用上游的 `boringNotch`，以便與上游合併；產品名稱與 bundle id 為
`DavidNook`／`io.github.davidkong3804.DavidNook`。）

`Packages/DavidNookCore` 為純邏輯 Swift package（LRC、簡繁轉換、剪貼簿規則），可獨立測試：

```sh
cd Packages/DavidNookCore && swift test
```

## 隱私

- 不含遙測、不含自動更新。唯一的對外連線是歌詞查詢（`lrclib.net`，只送曲名、歌手與長度；可在設定 → Media 關閉）。
- 不記錄歌名、歌手、歌詞、剪貼簿等內容到 log。歌詞快取存在 Application Support/DavidNook/Lyrics（檔案 0600，可在設定中清除；目錄已排除於備份）。
- 剪貼簿歷史只存在這台 Mac 的 Application Support/DavidNook/Clipboard（目錄 0700、檔案 0600；剪貼簿資料已排除於備份，Time Machine 不會備份明文歷史，所以「清除全部」不會漏掉備份裡的舊副本），標示為密碼或一次性內容（`org.nspasteboard.ConcealedType` 等）的項目不會被記錄；設定 → 剪貼簿可「清除未釘選」或二次確認後「清除全部」（連同暫存圖片）。macOS 15.4 起，背景讀取剪貼簿會觸發系統的「從其他 App 貼上」提示，DavidNook 在設定為「每次詢問」或「拒絕」時不會反覆讀取，而是在面板上提示你到系統設定改成「允許」。

## 授權

GPL-3.0。第三方元件與其授權請見 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) 與 [`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES)。
