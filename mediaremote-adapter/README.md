# MediaRemoteAdapter（由原始碼自行建置）

本目錄放 [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)（BSD-3-Clause）
`v0.7.7`（commit `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`）的**自行建置產物**。
來源、建置指令、雜湊與授權全文見 [`../Vendor/mediaremote-adapter/PROVENANCE.md`](../Vendor/mediaremote-adapter/PROVENANCE.md)；
重新建置請執行 [`../Tools/build_adapter.sh`](../Tools/build_adapter.sh)（請勿手動替換本目錄的檔案）。

## 檔案與用途

| 檔案 | 用途 |
|---|---|
| `mediaremote-adapter.pl` | 複製到 app 的 Resources；由 `NowPlayingController` 以 `/usr/bin/perl` 執行（`stream` 命令） |
| `MediaRemoteAdapter.framework` | 嵌入 `Contents/Frameworks`；由上述 perl 腳本於執行期載入。**只嵌入，不連結** |
| `MediaRemoteAdapterTestClient` | 隨附的診斷執行檔（`test` 命令），啟動時用來自檢 adapter 是否可用；失敗則退回 Music.app 備援 |

## 不可違反的約束

- framework **不得**加入 target 的 Link Binary With Libraries、app 不得 `import MediaRemoteAdapter`
  （ad-hoc 簽章＋Hardened Runtime 下連結內嵌 framework 會在啟動時被 library validation 擋下而崩潰）。
- 不得關閉 Hardened Runtime，也不得加入 `disable-library-validation` 等放寬的 entitlement。

## 簽章

產物為 ad-hoc 簽章（`codesign -dv` 顯示 `Signature=adhoc`）；app 建置時 Xcode 以 CodeSignOnCopy 重新簽章。
