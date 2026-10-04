import XCTest
@testable import DavidNookCore

/// 效能基準：只記錄、不設硬性門檻（輸出以 `BENCH` 開頭，方便 grep）。
final class LyricsChineseBenchmarkTests: XCTestCase {
    private static let sampleLines = [
        "我愿意为你被放逐天际",
        "后来我们没有回头",
        "头发散落在肩上",
        "发如雪",
        "里面有软件和网络",
        "干杯，朋友们",
        "邻里之间的夜晚",
        "The night is quiet and I wait for you",
        "",
        "这个世界还有很多爱",
        "不断发展的城市",
        "海里有鱼，在海里游",
    ]

    private func makeLines(_ count: Int) -> [String] {
        (0..<count).map { Self.sampleLines[$0 % Self.sampleLines.count] }
    }

    private func elapsed(_ body: () throws -> Void) rethrows -> Duration {
        try ContinuousClock().measure(body)
    }

    func testBenchmark5000LinesSimplifiedDocument() throws {
        let lines = makeLines(5_000)
        let localizer = LyricsLocalizer()

        // 第一次含轉換器初始化（字典載入）；之後是穩態。
        var firstResult: LocalizedLyrics?
        let cold = try elapsed { firstResult = try localizer.localize(lines: lines) }
        var warm: [Duration] = []
        for _ in 0..<3 {
            warm.append(try elapsed { _ = try localizer.localize(lines: lines) })
        }
        XCTAssertEqual(firstResult?.lines.count, 5_000)
        XCTAssertEqual(firstResult?.script, .simplified)
        print("BENCH localize 5,000 lines (simplified, conservative): first call \(cold), warm runs \(warm)")
    }

    func testBenchmark5000LinesTaiwanIdioms() throws {
        let lines = makeLines(5_000)
        let localizer = LyricsLocalizer()
        _ = try localizer.localize(lines: ["我们"], options: LyricsLocalizationOptions(useTaiwanIdioms: true))
        let duration = try elapsed {
            _ = try localizer.localize(lines: lines, options: LyricsLocalizationOptions(useTaiwanIdioms: true))
        }
        print("BENCH localize 5,000 lines (simplified, taiwanIdioms): \(duration)")
    }

    func testBenchmark5000LinesNativeTraditional() throws {
        let traditional = try LyricsLocalizer().localize(lines: makeLines(5_000)).lines
        let localizer = LyricsLocalizer()
        _ = try localizer.localize(lines: ["我們"])
        let duration = try elapsed { _ = try localizer.localize(lines: traditional) }
        print("BENCH localize 5,000 lines (native traditional, variantsOnly): \(duration)")
    }

    func testBenchmarkConverterInitialization() throws {
        var durations: [String] = []
        for mode in LyricsConversionMode.allCases {
            let duration = try elapsed { _ = try LyricsChineseConverter(mode: mode) }
            durations.append("\(mode)=\(duration)")
        }
        print("BENCH converter init (not cached): \(durations.joined(separator: ", "))")
    }

    func testBenchmarkDetectorOnly() {
        let detector = ChineseScriptDetector()
        let lines = makeLines(5_000)
        let duration = elapsed { _ = detector.detect(lines: lines) }
        print("BENCH detector over 5,000 lines: \(duration)")
    }
}
