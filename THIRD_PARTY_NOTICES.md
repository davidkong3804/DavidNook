# THIRD_PARTY_NOTICES

DavidNook 整體以 **GPL-3.0** 發佈，不附帶任何擔保（見 [`LICENSE`](LICENSE)，為上游 boring.notch 的原文，未更動）。
本檔列出 DavidNook **實際內含、連入或衍生自**的第三方成果。各授權全文放在 [`LICENSES/`](LICENSES/)，
並隨 App 內附：App 內「設定 → 關於 → 第三方授權」顯示本檔與 `LICENSES/*.txt`。

核對日期：2026-10-05。核對依據：

- 版本與 SHA：`boringNotch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 與
  `Packages/DavidNookCore/Package.resolved`（兩份都釘到同一個 SwiftyOpenCC revision）。
- 授權類型：直接讀各依賴在 SwiftPM checkout（`SourcePackages/checkouts/<套件>/`，`git rev-parse HEAD` 與 Package.resolved 一致）
  內的 LICENSE 檔；不在 checkout 內的專案（DynamicNotchKit、NotchDrop、Parrot、darts-clone、adapter 的現行版本）以
  `gh api repos/<owner>/<repo>/license` 取得上游 LICENSE。讀不到的標「未查證」。
- 實際連入：Release 產物 `Build/Products/Release/` 內的靜態連結物件（`Defaults.o`、`KeyboardShortcuts.o`、`LaunchAtLogin.o`、
  `MacroVisionKit.o`、`SkyLightWindow.o`、`OpenCC.o`、`copencc.o`、`DavidNookCore.o`、`DavidNookUI.o`）與
  `Contents/Frameworks/`（只有 `MediaRemoteAdapter.framework`）；原始碼中的 `import` 與之相符。

## 基礎專案（GPL-3.0）

| 名稱 | 版本／SHA | 授權 | 來源 | 說明 |
| --- | --- | --- | --- | --- |
| boring.notch（The Bored Team 與貢獻者） | tag `v2.8-rc.1`，`fb2643121741c6ba6102d5ef2b2c7a787f26fad1` | GPL-3.0 | <https://github.com/TheBoredTeam/boring.notch> | DavidNook 的基礎；上游 git 歷史完整保留（merge commit `31b6a32`），檔頭署名與 `Original source:` 註解皆未移除。 |
| Atoll（Ebullioscopic） | 未釘版本 | GPL-3.0 | <https://github.com/Ebullioscopic/Atoll> | Compact 播放器的版面比例與 `MusicSliderView` 的剩餘時間顯示，見 `CompactHomeView.swift`、`NotchHomeView.swift`、`ContentView.swift`、`sizing/matters.swift` 的檔頭／註解；Atoll 本身也是 boring.notch 的 fork。 |

## 連入或內嵌於 App 的第三方元件

| 名稱 | 版本／SHA | 授權 | 來源 | 用途 | 方式 | 授權全文 |
| --- | --- | --- | --- | --- | --- | --- |
| mediaremote-adapter（Jonas van den Berg 與貢獻者） | `v0.7.7`，`e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6` | BSD-3-Clause | <https://github.com/ungive/mediaremote-adapter> | Now Playing（讀取目前曲目與播放狀態、控制播放） | **由原始碼自行建置**並**僅內嵌**（`Contents/Frameworks/MediaRemoteAdapter.framework`，由 `/usr/bin/perl` 載入，**不連結**）；`mediaremote-adapter.pl`、`MediaRemoteAdapterTestClient` 在 `Contents/Resources/`。來源、建置與雜湊見 `Vendor/mediaremote-adapter/PROVENANCE.md` | `LICENSES/BSD-3-Clause.txt` |
| Defaults（Sindre Sorhus） | 9.0.9，`00a7465a0668a87fa159e779b9d80f1f9652357e` | MIT | <https://github.com/sindresorhus/Defaults> | 設定儲存 | 靜態連結 | `LICENSES/MIT.txt` |
| KeyboardShortcuts（Sindre Sorhus） | 3.1.0，`772133d9dbe800fdac0473226822994c5c162c58` | MIT | <https://github.com/sindresorhus/KeyboardShortcuts> | 全域快速鍵與設定頁的快速鍵錄製元件 | 靜態連結（資源 bundle：含自身的多語系字串） | `LICENSES/MIT.txt` |
| LaunchAtLogin-Modern（Sindre Sorhus） | 1.1.0，`a04ec1c363be3627734f6dad757d82f5d4fa8fcc` | MIT | <https://github.com/sindresorhus/LaunchAtLogin-Modern> | 「登入時啟動」開關 | 靜態連結 | `LICENSES/MIT.txt` |
| MacroVisionKit（版權行：github.com/theboringhumane） | 0.2.0，`da481a6be8d8b1bf7fcb218507a72428bbcae7b0` | MIT | <https://github.com/TheBoredTeam/MacroVisionKit> | 偵測其他 App 是否全螢幕（`FullscreenMediaDetection.swift`） | 靜態連結 | `LICENSES/MIT.txt` |
| SkyLightWindow（Lakr Aream） | 1.0.0，`b7bd99f62a0673a99bed4bfd31098ca1dcdd10eb` | MIT | <https://github.com/Lakr233/SkyLightWindow> | 讓瀏海視窗可顯示在鎖定畫面（`BoringNotchSkyLightWindow.swift`） | 靜態連結 | `LICENSES/MIT.txt` |
| SwiftyOpenCC（DengXiang） | revision `1d8105a0f7199c90af722bff62728050c858e777`（上游沒有發行 tag，最後更新 2021，故以 revision 釘選） | MIT | <https://github.com/ddddxxx/SwiftyOpenCC> | OpenCC 的 Swift 封裝（`Packages/DavidNookCore` 的簡繁轉換） | 靜態連結（`OpenCC.o`、`copencc.o`；資源 bundle `SwiftyOpenCC_OpenCC.bundle` 含字典） | `LICENSES/MIT.txt` |
| OpenCC（Carbo Kuo 與貢獻者） | 1.1.2（SwiftyOpenCC 內 `OpenCC/CMakeLists.txt`） | Apache-2.0；該目錄**沒有 NOTICE 檔**，字典資料沒有另外的授權檔（是否有逐檔例外：未查證） | <https://github.com/BYVoid/OpenCC> | 簡繁轉換演算法與字典 | 隨 SwiftyOpenCC 內含並靜態連結 | `LICENSES/Apache-2.0.txt` |
| marisa-trie（Susumu Yata） | 0.2.6（`OpenCC/deps/marisa-0.2.6`） | BSD-2-Clause **或** LGPL-2.1 以後（雙授權；DavidNook 選擇 BSD-2-Clause） | <https://github.com/s-yata/marisa-trie> | OpenCC 的字典資料結構 | 隨 OpenCC 靜態連結 | `LICENSES/BSD-2-Clause.txt` |
| darts-clone（Susumu Yata） | 0.32（`OpenCC/deps/darts-clone/darts.h`） | BSD-2-Clause（依其上游儲存庫的 COPYING.md；**隨附的 `darts.h` 本身沒有授權標頭**） | <https://github.com/s-yata/darts-clone> | OpenCC 的字典資料結構 | 隨 OpenCC 靜態連結 | `LICENSES/BSD-2-Clause.txt` |

## 建置期相依（不隨 App 散布）

| 名稱 | 版本／SHA | 授權 | 來源 | 用途 |
| --- | --- | --- | --- | --- |
| swift-syntax（Apple Inc. 與 Swift 專案作者） | 603.0.2，`79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1` | Apache-2.0 with Runtime Library Exception | <https://github.com/swiftlang/swift-syntax> | Defaults 的 Swift 巨集在建置時需要；Release 產物沒有連入（沒有對應的連結物件）。全文與 `LICENSES/Apache-2.0.txt` 相同，另有 Runtime Library Exception 段落（其 `LICENSE.txt`）。 |

## 程式碼層級的衍生（單一檔案）

| 來源 | 授權 | DavidNook 內的檔案 | 說明 |
| --- | --- | --- | --- |
| DynamicNotchKit（Kai Azim） <https://github.com/MrKai77/DynamicNotchKit> | MIT（Copyright (c) 2025 Kai Azim） | `boringNotch/components/Notch/NotchShape.swift`（檔頭 `Original source:`） | 瀏海形狀。授權全文見 `LICENSES/MIT.txt`。 |
| Parrot（Aditya Vaidyam 與貢獻者） <https://github.com/avaidyam/Parrot/> | **MPL-2.0** | `boringNotch/private/CGSSpace.swift`（檔頭保留 MPL-2.0 聲明與 `Original source:`） | 檔案層級 copyleft：該檔維持 MPL-2.0，其完整原始碼就在本專案的原始碼樹，Parrot 原版可由上面連結取得；其餘檔案不受影響，仍為 GPL-3.0（MPL-2.0 §3.3）。全文見 `LICENSES/MPL-2.0.txt`。 |

## 僅致謝（不在使用中）

- [NotchDrop](https://github.com/Lakr233/NotchDrop)（Lakr Aream，MIT，Copyright (c) 2024 Lakr Aream）：上游 boring.notch 曾列為來源之一（Shelf／AirDrop 相關功能）。
  DavidNook 已移除這些功能；原始碼中已搜尋不到其署名或引用（`git grep -i notchdrop` 只剩本檔與 `LICENSES/MIT.txt`）。
  是否仍有殘存程式碼源自 NotchDrop：**未逐檔比對上游，未查證**；因此保守地保留其版權聲明於 `LICENSES/MIT.txt`。

## 已移除（不在 App 內，也不再列為使用中）

上游 boring.notch 在 `fb26431…` 的 Package.resolved 內，而目前的 Package.resolved 已不存在、也沒有連入的套件：
Sparkle、lottie-spm（Lottie）、Pow、swift-collections、SwiftUI-Introspect、AsyncXPCConnection。
這些套件的授權沒有逐一核對（它們不屬於 DavidNook 的發佈內容）。

## 授權相容性

- DavidNook 整體為 GPL-3.0。MIT、BSD-2-Clause、BSD-3-Clause 與 GPL-3.0 相容；Apache-2.0 與 GPL-3.0（不是 GPL-2.0）相容；
  marisa-trie 以其 BSD-2-Clause 選項使用，不涉及 LGPL。
- MPL-2.0（Parrot 衍生檔）的檔案層級 copyleft 與整體 GPL-3.0 相容（MPL-2.0 §3.3，Secondary License）。
- 其餘上游 boring.notch 原始檔的檔頭署名（`Created by …`、`Modified by …`、`Original source: …`）皆保留。
