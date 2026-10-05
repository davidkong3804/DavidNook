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
