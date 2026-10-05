# THIRD_PARTY_NOTICES

DavidNook 整體以 **GPL-3.0** 發佈（見 [`LICENSE`](LICENSE)，為上游 boring.notch 的原文，未更動）。
下列為 DavidNook 內含或連結的第三方成果與授權。完整授權全文見 [`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES)
（上游沿用檔，已移除本專案不再使用的相依套件）以及各套件原始碼內的 LICENSE。

標註「未查」者表示尚未在各自原始碼中確認，不得視為已驗證。

## 基礎專案

| 名稱 | 授權 | 說明 |
| --- | --- | --- |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch)（The Bored Team 與貢獻者） | GPL-3.0 | DavidNook 的基礎；fork 自 tag `v2.8-rc.1`，完整 SHA `fb2643121741c6ba6102d5ef2b2c7a787f26fad1`，上游歷史完整保留（merge commit `31b6a32`）。 |
| [Atoll](https://github.com/Ebullioscopic/Atoll)（Ebullioscopic） | GPL-3.0 | 上游 boring.notch 內已移植的 Compact 播放器版面比例與 `MusicSliderView` 的剩餘時間顯示（見 `CompactHomeView.swift`、`NotchHomeView.swift` 檔頭註解）；Atoll 本身亦為 boring.notch 的 fork。 |

## 隨原始碼附帶的第三方程式碼

| 名稱 | 授權 | 位置／說明 |
| --- | --- | --- |
| [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)（Jonas van den Berg 與貢獻者） | BSD-3-Clause | `mediaremote-adapter/`。**由上游原始碼自行建置**：tag `v0.7.7`，完整 SHA `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`（`MediaRemoteAdapter.framework`、`MediaRemoteAdapterTestClient`、`mediaremote-adapter.pl`），以 `Tools/build_adapter.sh` 重建；來源、建置指令、雜湊與授權全文見 `Vendor/mediaremote-adapter/PROVENANCE.md`。framework 只嵌入、不連結。 |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)（Kai Azim） | MIT | `boringNotch/components/Notch/NotchShape.swift` 檔頭「Original source」。 |
| [NotchDrop](https://github.com/Lakr233/NotchDrop)（Lakr Aream） | MIT | 上游 `THIRD_PARTY_LICENSES` 列為參考來源；程式碼層級的引用範圍未查（本 fork 已移除 Shelf）。 |
| [Parrot](https://github.com/avaidyam/Parrot)（Aditya Vaidyam 與貢獻者） | MPL-2.0 | `boringNotch/private/CGSSpace.swift`（檔頭為 MPL-2.0 聲明；該檔維持 MPL-2.0 條款）。 |

## SwiftPM 相依（Xcode project 直接引用）

| 套件 | 版本 | 授權 | 版權 |
| --- | --- | --- | --- |
| [Defaults](https://github.com/sindresorhus/Defaults) | 9.0.9 | MIT | Sindre Sorhus |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 3.1.0 | MIT | Sindre Sorhus |
| [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) | 1.1.0 | MIT | Sindre Sorhus |
| [MacroVisionKit](https://github.com/TheBoredTeam/MacroVisionKit) | 0.2.0 | MIT | github.com/theboringhumane（2024） |
| [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) | 1.0.0 | MIT | Lakr Aream（2025） |
| [swift-syntax](https://github.com/swiftlang/swift-syntax)（Defaults 的巨集所需，建置期相依） | 603.0.2 | Apache-2.0 | Apple Inc. and the Swift project authors |

## DavidNookCore 的相依（`Packages/DavidNookCore`，同時連結進 app）

| 套件 | 版本 | 授權 | 說明 |
| --- | --- | --- | --- |
| [SwiftyOpenCC](https://github.com/ddddxxx/SwiftyOpenCC) | revision `1d8105a0f7199c90af722bff62728050c858e777`（上游最後更新 2021，故以 revision 釘選） | MIT | Copyright (c) 2017 DengXiang |
| [OpenCC](https://github.com/BYVoid/OpenCC)（隨 SwiftyOpenCC 內含，附字典） | 1.1.2（見 SwiftyOpenCC 內 `OpenCC/CMakeLists.txt`） | Apache-2.0 | 簡繁轉換字典與演算法。 |

## 其他

- 其餘上游 boring.notch 原始檔的檔頭署名（`Created by …`、`Modified by …`、`Original source: …`）皆保留。
- 授權衝突檢查：MPL-2.0（Parrot）檔案層級的 copyleft 與整體 GPL-3.0 相容（MPL-2.0 §3.3）；MIT、BSD-3-Clause、Apache-2.0 皆與 GPL-3.0 相容。
- 各套件的 LICENSE 全文於建置時可在 SwiftPM checkout（`SourcePackages/checkouts/<package>/`）取得；
  `THIRD_PARTY_LICENSES` 內含 BSD-3-Clause、MIT、MPL-2.0、Apache-2.0 全文。
