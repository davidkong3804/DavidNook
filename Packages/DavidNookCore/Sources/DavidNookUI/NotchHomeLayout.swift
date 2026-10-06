import SwiftUI

/// Home 分頁的三欄版面：封面｜控制區｜歌詞。尺寸全部來自 `NotchHomeMetrics`。
///
/// 版面容器放在 DavidNookUI，是為了讓 App 與離屏渲染測試用同一份幾何：App 把真正的封面、播放控制與歌詞面板放進三個欄位，
/// 測試則放尺寸相同的替身，因此「不截斷、不重疊」的結論套用在真正的版面規則上。
public struct NotchHomeLayout<Art: View, Controls: View, Lyrics: View>: View {
    public let metrics: NotchHomeMetrics
    private let art: Art
    private let controls: Controls
    private let lyrics: Lyrics

    public init(
        metrics: NotchHomeMetrics,
        @ViewBuilder art: () -> Art,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder lyrics: () -> Lyrics
    ) {
        self.metrics = metrics
        self.art = art()
        self.controls = controls()
        self.lyrics = lyrics()
    }

    public var body: some View {
        HStack(spacing: metrics.spacing) {
            art
                .frame(width: metrics.artWidth, height: metrics.artSize)
                .padding(metrics.artPadding)
            controls
            if metrics.showsLyrics {
                lyrics
                    .frame(width: metrics.lyricsWidth, height: metrics.lyricsHeight)
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.contentWidth, height: metrics.bodyHeight, alignment: .leading)
    }
}

/// 控制區的直式版面：歌名／歌手｜進度條與時間｜播放工具列，三塊之間的空白平均分配（至少 `minimumGap`）。
public struct NotchControlsLayout<Info: View, Slider: View, Toolbar: View>: View {
    public let metrics: NotchHomeMetrics
    private let info: Info
    private let slider: Slider
    private let toolbar: Toolbar

    public init(
        metrics: NotchHomeMetrics,
        @ViewBuilder info: () -> Info,
        @ViewBuilder slider: () -> Slider,
        @ViewBuilder toolbar: () -> Toolbar
    ) {
        self.metrics = metrics
        self.info = info()
        self.slider = slider()
        self.toolbar = toolbar()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            info
                .padding(.leading, NotchHomeMetrics.controlsLeadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: NotchHomeMetrics.infoHeight, alignment: .topLeading)
            Spacer(minLength: metrics.minimumGap)
            slider
                .padding(.leading, NotchHomeMetrics.controlsLeadingInset)
                .frame(height: metrics.sliderHeight)
            Spacer(minLength: metrics.minimumGap)
            toolbar
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: metrics.primaryButtonSize)
        }
        .frame(width: metrics.controlsWidth, height: metrics.bodyHeight, alignment: .top)
    }
}
