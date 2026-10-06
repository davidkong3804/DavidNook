# 影片膠囊：可行性研究與設計（2026-10-06）

狀態：**僅研究與設計，尚無任何程式碼**。所有 API 名稱皆出自下列來源；查不到者標「未查證」。
來源縮寫：[A1] https://developer.apple.com/documentation/screencapturekit.md ／ [A2] https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker.md ／ [A3] https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos.md ／ [A4] https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration.md ／ [A5] https://developer.apple.com/documentation/screencapturekit/sccontentsharingpickerobserver.md ／ [W22] https://developer.apple.com/videos/play/wwdc2022/10155/ ／ [W23] https://developer.apple.com/videos/play/wwdc2023/10136/ ／ [N] https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/ ／ [R] https://docs.rs/screencapturekit ／ [C] https://github.com/CapSoftware/Cap/issues/1722 ／ [T] https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly ／ [F] https://developer.apple.com/forums/thread/760483

## 1. 目標與非目標
**目標**
- 看影片／球賽時，在**展開的瀏海**裡顯示使用者挑選的那個視窗的即時縮小畫面。
- 「釘選」：收合時在瀏海下方保留一顆影片膠囊（像子母畫面），與既有歌詞膠囊並存。
- 最小權限：只看使用者挑的**單一視窗**；不擷取音訊（聲音照常由原 App 播）。

**非目標**：錄影／截圖存檔、上傳、擷取整個螢幕、擷取音訊、互動控制來源視窗（不轉送點擊）、DRM 內容保證可顯示、多視窗同時顯示（第一版只一路）。

## 2. 可行性結論（逐條附來源）
**a. 沙盒／簽章／entitlement／Info.plist**
- ScreenCaptureKit 的授權由 TCC（螢幕錄製）控管，**沒有對應的 `com.apple.security.*` 螢幕擷取 entitlement**；只需 `app-sandbox`。[R]（第三方文件，但與 Apple 論壇「`com.apple.private.*` 不開放第三方」一致 [F]）→ **現有 entitlements 不需放寬、不需 disable-library-validation、不動 Hardened Runtime**。
- Info.plist 需 `NSScreenCaptureUsageDescription`（Apple 要求在擷取前請求螢幕錄製權限並提供用途字串）。[A1]；缺少時 App 會被終止（第三方說法）[R]。走系統挑選器路徑時是否仍需此字串：**未查證**，保守起見仍加。
- **風險**：有 Rust 專案回報 macOS Sequoia 對「ad-hoc 簽章（無 Team ID）」的 App，`CGPreflightScreenCaptureAccess()` 恆為 false、ScreenCaptureKit 被默默拒絕。[C]（單一來源、非 Apple 文件，**未驗證是否適用本專案**）。DavidNook 為 ad-hoc 簽章，故 M-A／M-B 之前必須先做「實機 spike」。

**b. 螢幕錄製權限（TCC）與系統挑選器**
- 程式化列舉（`SCShareableContent`）**需要**螢幕錄製授權；Apple 範例：首次執行會彈授權，授權後**需重啟 App** 才能擷取。[A3][N]
- `SCContentSharingPicker`（`SCContentSharingPicker.shared`）：macOS 14.0+，由系統呈現挑選 UI；Apple 建議用它取代自製選擇 UI。[A1][A2]。第三方（Nonstrict）明言挑選器「不需要螢幕錄製授權，使用者選了視窗就能用」，但程式化 API 需要。[N]；WWDC23 說明動機為避免「授予整個螢幕錄製權限造成過度分享」。[W23]（逐字轉錄未明講免授權 → **「免 TCC」只有第三方來源，需實測**）。
- 單一視窗：`present(using:)` 搭配 `SCShareableContentStyle`，內容樣式可選 window。[A2][W23] 設定物件 `SCContentSharingPickerConfiguration`（可排除 bundle ID／視窗、`allowsRepicking`；允許的選取模式見 `SCContentSharingPickerMode`，確切屬性名稱未查證）。[A1][W23]。可設 `maximumStreamCount` 限制串流數。[A2]
- 挑選結果由 `SCContentSharingPickerObserver` 回呼：`contentSharingPicker(_:didUpdateWith:for:)`（取得 `SCContentFilter`）、`didCancelFor`、`contentSharingPickerStartDidFailWithError`。使用前 `isActive` 需為 true。[A2][A5][W23]
- 沙盒相容：挑選器為系統服務，文件未見沙盒限制，**未查證／需實測**。
- 再確認提示：macOS 15 beta 6 起由每週改為**每月**「允許一個月／開啟系統設定」。[T] macOS 26／27 的行為：**未查證**。挑選器可能免除此提醒：僅見搜尋摘要稱「使用挑選器可能消除 Sequoia 的提醒」（https://mjtsai.com/blog/?p=44412 ，未逐字驗證），**未查證**。重新建置（ad-hoc cdhash 改變）後授權是否失效：**未查證，需實測**；程式化授權狀態預檢 `CGPreflightScreenCaptureAccess()` 在 ad-hoc 下可能不可靠。[C]

**c. 擷取限制**
- 視窗被遮住／部分遮住／完全在螢幕外或其他顯示器：串流**仍含完整視窗內容**；視窗**最小化時串流暫停**，還原後繼續。[W22] 其他 Space：文件未明講，**未查證**（「螢幕外」案例暗示可，需實測）。
- 自己的視窗：程式化路徑可用 `SCContentFilter(display:excludingApplications:exceptingWindows:)`；單視窗 `SCContentFilter(desktopIndependentWindow:)` 本就只含該視窗。[A3][W22] 挑選器路徑以設定中的排除 bundle ID／視窗 ID 擋掉自己。[W23]
- DRM（FairPlay／Widevine）是否黑畫面：**未查證**。Electron 有針對「內容保護視窗」在螢幕擷取時隱藏的修補（顯示器層級），暗示受保護視窗可能被隱藏或黑畫面。https://ayakael.net/mirrors/electron/commit/fd88908457a986f06e310e80499e4b2775d8ba70 → 文案要預期 Netflix／Apple TV 可能無畫面。
- 瀏覽器原生畫中畫（PiP）視窗能否被當成獨立視窗擷取／挑選：**未查證，需實測**（PiP 為置頂浮動視窗，僅有一般介紹）。

**d. 效能**
- 設定項（皆在 [A4]）：`width`／`height`（輸出尺寸，Apple 範例單視窗以 window.frame×2 做 Retina）、`scalesToFit`、`minimumFrameInterval`（Apple 範例為 60 fps；我們取 15–30 fps）、`queueDepth`（預設 3，不得超過 8；越大越吃記憶體）、`pixelFormat`（螢幕顯示用 BGRA，YUV420 供編碼）、`showsCursor`、`capturesAudio`（關）、`captureResolution`。[A3][A4][W22]
- 建議值（皆為**待實測的起點**）：輸出寬高＝目標膠囊尺寸×螢幕縮放（上限 ≤ 2× 的 288×162 ＝ 約 576×324）、`minimumFrameInterval`＝1/20 s（收合釘選）／1/30 s（展開）、`queueDepth`＝3、`pixelFormat`＝BGRA、`showsCursor`＝false、`capturesAudio`＝false。`SCFrameStatus.complete` 才處理，其餘丟棄。[A3]
- 顯示：Apple 範例把 `CVPixelBuffer` 背後的 `IOSurface`（`CVPixelBufferGetIOSurface`）直接設為 NSView layer 的內容。[A3] → **採此做法**：零拷貝、不經 CPU 轉圖、與 `NSViewRepresentable` 簡單相容；不使用逐幀轉 `NSImage`／`CGImage`。其他顯示方式（sample buffer 顯示圖層）未評估。
- 預期 CPU／GPU：**未量測**，列為 M-B 驗收項（見 §9）。

## 3. 最小權限推薦
**推薦：系統挑選器（`SCContentSharingPicker`，macOS 14+）為主、`SCShareableContent`＋螢幕錄製授權為備案。**
理由：(1) 使用者每次只明確分享一個視窗，符合「只看我挑的那個」；(2) 第三方來源稱免螢幕錄製授權，若屬實則無 TCC 提示與每月再確認；(3) Apple 建議不要自製挑選 UI [A1]；(4) 不需要放寬任何 entitlement。
代價：每次（含重啟後）需重新挑選（挑選結果是否可跨重啟保存：**未查證**）；無法自行列出視窗清單，來源視窗關閉靠 `SCStreamDelegate` 的停止事件判斷；挑選器 UI 非我們掌控。
**決策閘（M-B 第一個 spike）**：以目前 ad-hoc 建置實測 (i) 不授權也能經挑選器串流？(ii) 沙盒下可用？(iii) 重建後不失效？任一為否 → 退回備案並在設定頁引導授權。

## 4. UX
- **展開瀏海**：新增「影片」區塊（分頁位置於實作時對照現有分頁結構決定；不在本文件預設）。未選擇時顯示「選擇視窗」按鈕 → 呼叫系統挑選器；已選擇顯示即時畫面（保持來源長寬比，夾在 1:2～2:1）＋按鈕：換視窗、釘選、停止。
- **尺寸**：S／M／L＝寬 128／176／224 pt（高依長寬比，16:9 時 72／99／126），設定頁可選；所有數值在使用處再夾限（見 §6）。
- **釘選**：收合時於瀏海下方顯示膠囊；與歌詞膠囊**垂直堆疊**——歌詞膠囊在上（緊貼瀏海，維持現有位置），影片膠囊在其下，間距 6 pt；歌詞膠囊不顯示時影片膠囊上移到歌詞膠囊的位置。hover／點擊沿用歌詞膠囊的「透明區域轉接 `handleHover`／`doOpen()`」做法。
- **狀態**：未選擇／等待挑選／串流中／來源最小化（暫停：顯示最後一幀＋「已最小化」）／來源關閉（顯示「視窗已關閉」2 s 後自動收起膠囊並解除釘選）／權限不足（備案路徑）／失敗（可重試）。
- **沒授權的說明文案**（備案路徑）：「要顯示影片，DavidNook 需要『螢幕錄製』權限。畫面只在你的 Mac 記憶體中縮小顯示，不會儲存或上傳；聲音仍由原本的 App 播放。」附「開啟系統設定」按鈕。授權後提示需重啟 App。
- 無障礙：「減少動態」時不做縮放動畫，只淡入淡出。

## 5. 技術架構
- **Core（純邏輯，可單元測試）**，放 `Packages/DavidNookCore`：
  - `VideoCaptureSource` protocol（開始／停止／狀態串流／畫面回呼）；`FakeVideoCaptureSource` 供測試。
  - `VideoCapsuleStateMachine`：§4 各狀態與轉移（含釘選、來源最小化／關閉、授權變化）。
  - `VideoCapsuleMetrics`：尺寸夾限、長寬比、與歌詞膠囊堆疊的版面計算（見 §6）。
  - `VideoCapsuleVisibility`：功能開啟＋收合＋已釘選＋串流中（或暫停有最後一幀）才顯示（仿 `LyricsPillVisibility`）。
- **UI（`DavidNookUI`）**：`VideoCapsuleView`（SwiftUI 殼）＋ `NSViewRepresentable` 畫面視圖（吃 IOSurface）。
- **App 端（只有這裡碰 ScreenCaptureKit）**：`SCKVideoCaptureSource`（實作 protocol）；`SCContentSharingPickerObserver` 轉接；`SCStreamOutput`／`SCStreamDelegate` 回呼只做「丟畫面／回報狀態」，不做業務判斷。
- 串流以 `updateContentFilter`／`updateConfiguration` 動態更新而不重啟（Apple 範例做法）。[A3]
- 資源策略：不可見（展開未顯示該區塊且未釘選）→ 立即停止串流；展開→收合若已釘選則降 fps 繼續。

## 6. 硬限制（版面）
- 視窗**已固定為涵蓋尺寸 948×346**；收合視窗 640×210（扣底部內縮 8）。**絕不在 SwiftUI 動畫中對 NSWindow `setFrame`**（NSHostingView 版面更新迴圈會閃退，見 git log c30828f）。膠囊只在既有視窗範圍內畫。
- 版面函式（純邏輯、測試鎖定）：可用高度＝收合視窗高 −8 −瀏海底緣（最壞 60）−下拉距離（最大 40）−歌詞膠囊（22＋間距 6，若顯示）。要求尺寸超過可用範圍時**等比縮小**；縮到寬 < 96 pt 則**不顯示**，絕不溢出。寬度另夾在 96–288（< 640）。
- 測試：`testWorstCaseStaysInsideTheClosedAndCoveringWindows` 同型測試——窮舉（瀏海底緣 0–60、下拉 −8…40、歌詞膠囊有／無、S/M/L、長寬比 1:2…2:1），斷言矩形必在 640×210（扣 8）與 948×346 內。
- 展開狀態的影片區塊同樣受展開面板尺寸夾限，不改視窗。

## 7. 隱私
- 畫面只存在記憶體（IOSurface 緩衝，隨佇列循環釋放）；**不存檔、不上傳、不快取、不截圖、不寫入剪貼簿**；無新增網路請求。
- log **不含畫面內容、視窗標題、來源 App 名稱**（只記狀態轉移與錯誤碼）。
- 不擷取音訊（`capturesAudio` 關）。不新增第三方依賴；ScreenCaptureKit 為系統框架，但 `THIRD_PARTY_NOTICES.md` 與 README「隱私」段仍須在 M-B 同步更新（說明新增能力、權限、資料流向）。本里程碑前不改。
- 系統會顯示螢幕錄製中指示（具體樣式未查證），文案需告知。

## 8. 效能預算（目標值，待實測驗證）
- 串流中收合釘選：CPU 增量 ≤ 3%（單核）、記憶體增量 ≤ 30 MB；展開顯示：≤ 6%。不顯示：0（串流已停）。
- 不得影響既有「收合 0% CPU／約 50MB」的基準於未使用此功能時。

## 9. 風險與未驗證項（需實測）
1. ad-hoc 簽章下 ScreenCaptureKit／挑選器是否可用 [C]（決策閘）。
2. 挑選器是否真的免螢幕錄製授權、沙盒下可用、跨重啟保存挑選。
3. 授權在 ad-hoc 重建後是否失效；macOS 26／27 再確認提示行為。
4. DRM 內容、瀏覽器 PiP 視窗、其他 Space 的視窗能否擷取。
5. 實際 CPU／GPU／記憶體；筆電耗電。
6. 挑選器於 accessory／無 Dock 圖示 App 是否正常彈出（未查證）。
7. 來源視窗關閉的偵測可靠度（挑選器路徑無視窗清單）。

## 10. 里程碑與驗收
| 階段 | 內容 | 驗收 | 估計 |
| --- | --- | --- | --- |
| M-A | Core：protocol、`FakeVideoCaptureSource`、狀態機、`VideoCapsuleMetrics`／`Visibility`；零 ScreenCaptureKit | `swift test` 全綠；窮舉版面測試證明在 640×210／948×346 內；狀態機覆蓋 §4 所有轉移 | 0.5 天 |
| M-B | 先做 §3 決策閘 spike；App 端 `SCKVideoCaptureSource`＋挑選器；展開瀏海「影片」區塊；Info.plist 用途字串；README 隱私段與 THIRD_PARTY 更新 | 實機：選視窗→即時畫面；關／最小化來源行為正確；不放寬 entitlements（diff 為證）；實測 CPU／記憶體符合 §8；連續開關展開 10 次不閃退 | 1–1.5 天 |
| M-C | 釘選收合膠囊、與歌詞膠囊堆疊、hover／點擊轉接、設定頁（尺寸 S/M/L、下拉距離、fps）、「減少動態」 | 實機：歌詞＋影片同時顯示不重疊不溢出；釘選時 CPU 符合預算；取消釘選串流立即停止；文件補「已驗證／未驗證」 | 1 天 |

每階段完成前依守則：以全新 context 的審查者 read-back 對照驗收條件；未驗證項明寫。

## 使用者補充與決議（2026-10-06）

- **尺寸由使用者決定**：不只 S／M／L 三檔；提供連續的寬度滑桿（預設約 320 pt，16:9），並夾限在視窗涵蓋範圍內（948×346，見硬限制）。展開瀏海內與釘選後的收合膠囊可各自記住尺寸。
- **DRM（Netflix 等）明確列為非目標**：本功能**不會**也不應嘗試繞過或規避 DRM／內容保護。受保護內容被系統擷取成黑畫面是平台的保護機制，不是我們要「解掉」的 bug。處理方式：偵測到持續全黑畫面時顯示說明（「這個來源受內容保護，系統不允許擷取」），並建議改用來源本身提供的畫中畫或無 DRM 的來源（例如 YouTube、無保護的直播、本機影片）。
- 進度：目前只有本設計文件；下一步是在實機做「挑選器在沙盒＋ad-hoc 下能否運作」的小實測（需使用者在畫面上操作），通過才開發。使用者表示「晚點再來」。

## UX 變更與 M-A／M-B 實作紀錄（2026-10-06，優先於 §4 的 UX 描述）

**UX 變更（使用者決定）**：不新增「影片」分頁。改為：
1. **封面槽即影片槽**：展開瀏海 Home（正在播放）面板裡，原本顯示專輯封面的那塊，在有擷取來源串流時改顯示擷取畫面（aspect-fit）；沒在擷取就維持專輯封面。
   槽原本是方形；橫向影片時把槽加寬（`NotchHomeMetrics(artAspectRatio:videoMaximumWidth:)`：槽高不變，寬 = 高 × 長寬比，上限 = min(版面容許寬、設定頁影片寬度)；版面容許寬已為控制區（≥ 184）與歌詞（≥ 190）保留最小寬，所以不會擠壞歌名與控制列）。直向影片維持方形。窮舉測試鎖定：寬 560–900、高度係數 0.85–1.30、表頭 38／60、有無歌詞、各種長寬比與寬度上限下，整排不超過內容寬、控制區與歌詞不低於最小寬、槽不超出內容高。動畫沿用分頁切換的彈簧（response 0.38、dampingRatio 0.82），只改槽內版面，**不對 NSWindow setFrame**（涵蓋視窗仍為 948×346）。
2. **操作**：封面右上有低調的「擷取視窗」小按鈕（沒擷取時；hover 才完全不透明）；擷取中 hover 影片才出現「換視窗」「停止」。**點一下影片＝釘選／取消釘選**：釘選的概念是影片在瀏海**外面**（收合狀態、瀏海正下方）長成一顆影片膠囊（M-C）。hover 時影片右上顯示圖釘（已釘選時實心且一直顯示），tooltip「點一下，把影片釘到瀏海外面」／「點一下取消釘選」。釘選手勢只掛在最底層的透明層，「換視窗」「停止」「回到封面」是疊在上面的獨立 Button，按鈕自己吃掉點擊，不會同時觸發釘選。
3. **說明狀態都在槽內**：黑畫面（疑似受保護）顯示「這個來源受內容保護」＋簡短說明＋「回到封面」；來源視窗關閉、權限不足（含「開啟系統設定」）、挑選器失敗、串流中斷、未知錯誤各有簡短說明與「選擇視窗」／「回到封面」。這些說明也放進加寬（16:9）的槽；槽太窄（最小面板）時精簡成標題＋按鈕，完整說明放 tooltip。
4. **寬度滑桿只在設定頁**（設定 → 影片，160–480 pt、預設 320）：只決定槽可加寬的上限與（M-C）釘選膠囊的大小；槽的實際尺寸由版面決定。

**釘選狀態（M-B 完整，膠囊畫面屬 M-C）**：`VideoCapsuleStateMachine.isPinned`＋輸入 `togglePin`。規則（有測試）：只在串流中才能釘；黑畫面期間不能新釘、已釘則維持；挑選取消與換視窗維持；**串流結束（停止、來源視窗關閉、錯誤）一律自動取消釘選**（決議：沒有畫面的膠囊沒有意義，重新啟動 App 也不殘留）。`videoCapsulePinned`（Defaults）由控制器每次變化同步、App 啟動時重設為 false，M-C 的視圖直接讀它。M-B 下面板不在畫面上時一律暫停串流（M-C 的釘選膠囊需要時，在 `VideoCapsuleController.slotDidDisappear` 依 `isPinned` 保留串流）。

**給 M-C 的純邏輯（已完成、有窮舉測試）**：`VideoCapsuleStack.layout`（`DavidNookUI/VideoCapsuleMetrics.swift`）——歌詞膠囊在上（可切 `videoAbove`）、影片在其下、間距 6 pt；歌詞不顯示時影片上移到歌詞位置；可用高度 = 收合視窗高 − 底部內縮 8 − 上緣（瀏海底緣＋下拉距離）−（歌詞 22＋間距）；超過就等比縮小，縮到寬 < 96 不顯示；窮舉（瀏海底緣 0–60、下拉 −8…40、有無歌詞、兩種順序、各種寬與長寬比）斷言矩形必在收合視窗 640×210（扣底部 8）與涵蓋視窗 948×346 內且互不重疊。M-C 只需接視圖、hover／點擊轉接與設定。

**已完成的其他部分**
- 實機 spike（上方「進度」所述的小實測）：沙盒＋ad-hoc＋Hardened Runtime 下，`SCContentSharingPicker`（singleWindow）能彈出、`SCStream` 20 fps／480 寬收到畫面且非黑。因此 §3 決策閘 (ii)（沙盒下可用）成立、(i)（至少在這次實測中）可串流；(iii) 重建後授權是否失效仍**未驗證**。
- Core（`DavidNookCore/Video/`）：`VideoFrameSource` protocol（`start`／`stop`／`pause`／`resume`＋事件串流）與 `FakeVideoFrameSource`；`VideoCapsuleStateMachine`（idle／choosing／streaming／sourceClosed／blackContent／error＋釘選）；`BlackFrameDetector`（連續 3 秒平均亮度 < 2/255 才判黑，樣本間隔 > 2 秒重新計時，轉場的短暫黑場不誤判）；`VideoCapsuleSettings`（鍵名與預設：功能開關預設開、寬度 160…480 預設 320、釘選預設關）。畫面像素不經過 Core。
- UI：`VideoArtSlotView`（槽內所有狀態）、`VideoFrameDisplay`（IOSurface 直接當 layer.contents，零拷貝）、`VideoCapsuleMetrics`／`VideoCapsuleStack`。
- App 端：`ScreenCaptureKitVideoSource`（只有它碰 ScreenCaptureKit；挑選器只允許單一視窗並排除自己的 bundle ID；寬依設定最多 480、20 fps、無音訊、無游標、BGRA、queueDepth 3；每秒一次 32×32 格點亮度；視窗被縮放時依 contentRect 更新長寬比）、`VideoCapsuleController`（事件灌進狀態機；面板離開畫面就 `pause()` 並保留所選視窗；系統挑選器開著時暫時讓瀏海不自動收合）、設定 → 影片、`NSScreenCaptureUsageDescription`（en＋zh-Hant）。**entitlements 未改**；不呼叫 `CGRequestScreenCaptureAccess`。

**隱私（實作層）**：畫面只在記憶體；不存檔、不上傳、不快取、不截圖、不寫剪貼簿；log 只記狀態與錯誤碼。

**DRM**：不嘗試繞過；持續全黑只顯示「這個來源受內容保護，系統不允許擷取」並可一鍵回到封面。偵測是啟發式，極暗畫面可能被暫時誤判。

**與前文設計的差異**：§4 的「影片區塊／分頁」改為封面槽；S／M／L 三檔改為設定頁連續滑桿；釘選膠囊（`VideoCapsuleVisibility`、視圖、hover／點擊轉接）留給 M-C。

**仍未驗證（需真機）**：實際操作手感（點影片釘選、hover 按鈕、槽加寬動畫）；各瀏覽器視窗、瀏覽器畫中畫視窗、其他 Space 的視窗；視窗最小化／關閉時各種錯誤碼的實際值（目前把 noCaptureSource／noWindowList／systemStoppedStream／removingStream／userStopped 都視為「來源已關閉」，屬推測）；DRM 內容的實際行為；挑選器開啟時瀏海是否真的維持展開；ad-hoc 重建後授權是否失效、macOS 再確認提示；CPU／GPU／記憶體是否符合 §8；展開／收合連續 10 次不閃退。
