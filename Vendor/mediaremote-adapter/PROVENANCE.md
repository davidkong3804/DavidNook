# mediaremote-adapter 來源與建置紀錄（PROVENANCE）

DavidNook 以 `/usr/bin/perl` 載入 mediaremote-adapter 的 framework 來取得 Now Playing 資訊（Apple 私有行為，
見設計文件〈已知風險〉）。`mediaremote-adapter/` 目錄內的三個檔案**全部由上游原始碼自行建置**，不再沿用上游
boring.notch 內的預編譯品。

## 版本

| 項目 | 值 |
| --- | --- |
| 上游 | https://github.com/ungive/mediaremote-adapter （Jonas van den Berg 與貢獻者） |
| tag | `v0.7.7` |
| commit SHA（完整） | `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6` |
| 授權 | BSD-3-Clause（全文見本檔最下方） |
| 建置日期 | 2026-10-05 |
| 建置環境 | macOS 27.0.1、Xcode 27.0（Apple clang 21.0.0）、cmake 3.27.7；產物為 x86_64 + arm64 universal |

> 備註：先前研究記錄的上游 HEAD `2971825` 是 `v0.7.7` 之後的提交；本專案刻意釘在 tag `v0.7.7`。

## 如何重現

```sh
Tools/build_adapter.sh            # clone → 檢出並驗證釘選 SHA → cmake → ad-hoc 簽章 → 複製到 mediaremote-adapter/
Tools/build_adapter.sh <工作目錄>  # 指定暫存目錄；SKIP_INSTALL=1 時只建置、不覆蓋 repo
```

腳本等同下列步驟（細節與錯誤檢查見腳本本身）：

```sh
git clone https://github.com/ungive/mediaremote-adapter
cd mediaremote-adapter && git checkout --detach e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build                         # CMakeLists 的 POST_BUILD 會 ad-hoc 簽章 framework
codesign --force --deep --sign - build/MediaRemoteAdapter.framework
codesign --force --sign - build/MediaRemoteAdapterTestClient
# 然後把 build/MediaRemoteAdapter.framework、build/MediaRemoteAdapterTestClient、bin/mediaremote-adapter.pl
# 複製到 mediaremote-adapter/
```

建置**不保證逐位元可重現**（簽章與連結器中繼資料可能不同），但來源由 SHA 釘死、腳本會驗證 SHA 與 tag 一致且工作樹乾淨。

## 產物（2026-10-05 建置）

| 檔案 | SHA-256 |
| --- | --- |
| `mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter` | `a7e7ba036d6d2bf1f8387ae136586da006d1322d1ee8360921c5bf0fb152f5c2` |
| `mediaremote-adapter/MediaRemoteAdapterTestClient` | `a97ab582421ef195f506b4f0400e1c9a93edd1b1a798c8c47a5723d284c9bc79`（與先前 repo 內預編譯品位元相同） |
| `mediaremote-adapter/mediaremote-adapter.pl` | `d97802e46db9535e2549e178c105ebf417a0254b3929fc32f08ecfd14d49a85f`（與上游 `bin/mediaremote-adapter.pl` 位元相同） |

## 安全約束（不可違反）

- **只「嵌入」，不「連結」**：`MediaRemoteAdapter.framework` 只放進 app 的 `Contents/Frameworks/`（Xcode 的 Embed Frameworks，
  CodeSignOnCopy），**不得**加入 target 的 Link Binary With Libraries；app 原始碼不得 `import MediaRemoteAdapter`。
  理由：ad-hoc 簽章沒有 Team ID，Hardened Runtime 的 library validation 會在啟動時拒絕載入「連結」的 framework
  （M1 實測：dyld 報 `mapping process and mapped file (non-platform) have different Team IDs`，app 啟動即崩潰）。
  由 `/usr/bin/perl`（Apple 平台程式）以 dlopen 載入則是上游的原始設計。
- **不得**關閉 Hardened Runtime、不得加 `com.apple.security.cs.disable-library-validation` 或任何放寬的 entitlement。
- 建置腳本不加 entitlement、不改簽章旗標。

## 更新到新版本

1. 在上游 releases 選定 tag，取得其完整 commit SHA。
2. 修改 `Tools/build_adapter.sh` 的 `TAG` 與 `PINNED_SHA`，執行腳本。
3. 更新本檔的版本、SHA、日期與雜湊；更新 `THIRD_PARTY_NOTICES.md`。
4. 重新建置 app，確認 `otool -L` 無 MediaRemote 連結、`codesign -dvv` 的 flags 含 `runtime`、
   `perl mediaremote-adapter.pl <framework> <testclient> test` 結束碼為 0，且 app 啟動後存活。

## 授權全文（BSD-3-Clause；複製自上游 `LICENSE`，tag `v0.7.7`）

```text
BSD 3-Clause License

Copyright (c) 2025, Jonas van den Berg and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
