# 瀏海動畫與尺寸筆記

## 一、現況（改動前，基準 69341a6；行號指當時的檔案）

### 尺寸
- 展開尺寸寫死：`openNotchSize = 640×190`（`boringNotch/sizing/matters.swift:13`），視窗 `windowSize = 640×(190+20)`（同檔 :14，`shadowPadding = 20`）。
- 視窗只在建立時以 `windowSize` 開一次（`NotchWindowManager.swift:122`），之後大小不變，開／關都是同一個 640×210 的透明視窗。
- 展開後的實際寬度不是明確指定的：`NotchLayout` 裡有 `maxWidth: .infinity` 的子視圖，會吃滿 `ContentView` 最外層 `.frame(maxWidth: windowSize.width)`（`ContentView.swift:328`）給的寬度（640）；高度則是內容自然高度（約 186），`openNotchHeight`（190）只是外層 frame，不是黑色形體的高度（`ContentView.swift:115`、:255）。
- Home 內容區：專輯圖 120 寬＋歌詞面板 215×124；剪貼簿分頁內容固定高 128（`ClipboardTabView.swift:133`）。

### 動畫曲線（用 `Spring.value` 實測，目標 1.0）
| 項目 | 定義 | 過衝 | 進入 ±1% 帶 |
| --- | --- | --- | --- |
| 展開 `StandardAnimations.open` | `spring(response: 0.42/速度倍率, dampingFraction: 0.8)`（`animations/drop.swift:19-24`） | 1.52% | 0.424 s |
| 收合 `StandardAnimations.close` | `spring(response: 0.45/速度倍率, dampingFraction: 1.0)`（同檔 :27-32） | 0% | 0.475 s |
| 互動 `StandardAnimations.interactive` | `interactiveSpring(response: 0.38, dampingFraction: 0.8)`（同檔 :16） | 1.52% | 0.384 s |
| 分頁切換 | `withAnimation(.smooth)`（`TabSelectionView.swift:35`） | 約 0 | 約 0.5 s |
| 展開內容轉場 | `.scale(0.8, anchor: .top) + .opacity`，`.smooth(duration: 0.35)`（`ContentView.swift:437-441`） | — | 0.35 s |

- 形體尺寸由 `.animation(open/close, value: vm.notchState)`（`ContentView.swift:258`）驅動：框架的版面大小被彈簧內插；上下圓角由 `NotchShape.animatableData` 同一個動畫內插。
- 不尊重「減少動態」；有尊重 `enableOpeningAnimation`（關掉就是 `linear(duration: 0)`）與 `animationSpeedMultiplier`（response 除以倍率）。
- Hover：`handleHover` 在進入時 `withAnimation(interactive) { isHovering = true }`，目前只影響陰影；沒有任何「鼓起」預期動作。`minimumHoverDuration`（預設 0.3 s）之後才 `doOpen()`。
- 手勢：`gestureProgress` 以 `.smooth`／`interactive` 驅動整體 `scaleEffect`（`ContentView.swift:216-220`、:331-336）。

### Hit-testing（讀碼結論）
- 全專案沒有 `ignoresMouseEvents`、沒有覆寫 `hitTest`；視窗是 `NSPanel`（`.borderless/.nonactivatingPanel`），`isOpaque = false`、`backgroundColor = .clear`（`BoringNotchSkyLightWindow.swift:54-63`）。
- 點擊／hover 全靠 SwiftUI：`.contentShape(Rectangle())` + `.onHover` + `.onTapGesture` 都掛在「閉合形體」那個 frame 上（`ContentView.swift:267-275`）。
- 視窗透明區域是否讓點擊穿透，完全仰賴 WindowServer 對 alpha = 0 像素的處理；上游特別把 chin 區域畫成 `black.opacity(0.01)`（`ContentView.swift:322`），也就是上游自己也假設「alpha 為 0 的地方收不到滑鼠事件」。
- 結論：舊版的 640×210 透明視窗在閉合時就已經涵蓋瀏海兩側各約 225 pt、下方約 180 pt 的區域；是否擋點擊從未被明確處理。

## 二、改版後的設計（本次）

### 尺寸（`NotchSizing`，DavidNookUI，有測試）
- 形體外框（含上緣兩側各 19 pt 的圓角耳朵與上方瀏海高度區，與舊 `openNotchSize` 同義）：
  Home **720×176**、剪貼簿 **720×232**；設定頁「展開寬度」560–900（步進 10，預設 720）、「展開高度」85%–130%（預設 100%），
  即時生效、以 Defaults（`openNotchWidth`／`openNotchHeightScale`）持久化，「還原預設尺寸」鈕。
- 取捨：Home 內容區 126 = 120 pt 封面 + 5 行歌詞（124）；比舊版（約 188）矮 12 pt、寬 80 pt。
  剪貼簿內容區 182 = 搜尋列 26 + 間距 6 + 整整 4 列（4 × 36 + 3 × 2 = 150）；224 只放得下 3.7 列，所以取 232。
- 內容區下限 100：最小尺寸（560 寬、85% 高）時 Home 改「精簡密度」（播放鈕 40→30、進度條 32→30）、歌詞降為 4 行
  （偶數行把目前行上移半個節距，避免最外側兩行被面板邊緣切半）；自訂瀏海高度較高時，面板高度會跟著加高而不是壓縮內容。
- 內容以「最終尺寸」固定排版（`NotchHomeMetrics`／`NotchHomeLayout`），外層形體的彈簧變形只負責揭露內容，展開途中不會重新折行。

### 動畫（`NotchMotion`，所有常數集中於此，有測試）
| 項目 | 參數 | 實測（Spring.value 逐毫秒） |
| --- | --- | --- |
| 展開（形體寬高＋上下圓角同一條） | `Spring(response 0.46, dampingRatio 0.72)` | 過衝 3.84%，0.483 s 進入 ±1% |
| 收合 | `Spring(0.34, 0.9)` | 過衝 0.15%，0.277 s |
| 分頁切換（兩個分頁尺寸間變形） | `Spring(0.38, 0.82)` | 1.11%，0.362 s |
| Hover 預期鼓起 | `interactiveSpring(0.2, 0.7)`，scale 1.04（錨點上緣中央） | 4.6% 作用於 0.04 的縮放量 |
| 內容層進場 | 延遲 0.09 s；臨界阻尼 response 0.30；blur 10→0、scale 0.97→1、下移 4→0 | 0.316 s |
| 內容層出場 | 無延遲 easeOut 0.12 s | 0.110 s |
- 速度倍率（`animationSpeedMultiplier`）把所有 response／duration／delay 除以倍率（純時間軸縮放，測試以 `progress(t) == progress(2t)` 驗證）；
  「減少動態」→ 一律 0.2 s easeInOut、無過衝、無 blur／位移／縮放／鼓起；「Notch animation」關閉 → 全部瞬間。
- 展開峰值（t≈0.331 s）Home 寬度 740（目標 720，多 20 pt）、高度 181.5（目標 176）。

### 視窗與 hit-testing
- 視窗不再固定：**關閉＝舊版 640×210（與改版前完全相同，不新增任何可能擋住點擊的區域）**，展開＝948×346（涵蓋所有分頁、所有可調上限、彈簧過衝與陰影）。
  展開時在 SwiftUI 開始動畫之前同步放大（頂端置中不動）；收合後等彈簧穩定（再多 0.25 s）才縮回。`NSHostingView.sizingOptions = []`，視窗大小只由 `NotchWindowManager` 決定。
- 為什麼這樣做：專案沒有 `ignoresMouseEvents`／`hitTest` 保證，透明區能否穿透點擊取決於 WindowServer 對 alpha 的處理（未驗證）；
  讓關閉狀態維持舊版大小，就不需要依賴這個假設。

### 效能（讀碼推論，未用 profiler）
- 歌詞 `TimelineView` 在瀏海變形期間（`notchIsMorphing`）由 10 Hz 降為 2 Hz；變形結束自動恢復。
- 內容固定最終尺寸，變形過程只做合成（裁切／blur／縮放），沒有每格重新排版；列表／縮圖視圖沒有 `.id(尺寸)`，不會因尺寸動畫重建。

### 待處理與未驗證
- **ClipboardTabView.swift:133 的 `.frame(height: 128)`** 會把剪貼簿內容釘在 128 pt（本次依規定未動該檔）：
  合併後請套用一行修改 `.frame(maxHeight: .infinity)`（已驗證可乾淨套用的 patch：docs/superpowers/clipboard-tab-fill-height.patch，`git apply` 即可），
  否則剪貼簿分頁在 232 pt 的面板裡下方會留空。
- 真機實際手感、與 NotchNook 的主觀相似度、`blur(radius: 0)` 常駐的 GPU 成本、透明區是否穿透點擊：均未驗證。
