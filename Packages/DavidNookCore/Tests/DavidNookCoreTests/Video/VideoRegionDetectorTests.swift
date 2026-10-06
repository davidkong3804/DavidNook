import XCTest
@testable import DavidNookCore

/// 自動偵測影片區域：多幀小圖（亮度）→ 變動最大的連通區域的外接矩形（正規化）或 nil。全部用合成資料。
final class VideoRegionDetectorTests: XCTestCase {
    private let w = 64, h = 36

    private struct RNG {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
        mutating func unit() -> Double { Double(next() % 10_000) / 10_000 }
    }

    /// 靜態背景（棋盤格紋理）＋ `box`（像素範圍）內每幀亮度隨機變動。
    private func frames(count: Int = 12, box: (x: Int, y: Int, w: Int, h: Int)?, background: UInt8 = 120, boxSwing: Int = 100,
                        noise: Int = 0, seed: UInt64 = 7) -> [LumaFrame] {
        var rng = RNG(s: seed)
        return (0..<count).map { _ in
            var px = [UInt8](repeating: background, count: w * h)
            for y in 0..<h { for x in 0..<w where (x / 4 + y / 4) % 2 == 0 { px[y * w + x] = background &- 20 } }
            if let b = box {
                for y in b.y..<(b.y + b.h) { for x in b.x..<(b.x + b.w) {
                    px[y * w + x] = UInt8(max(0, min(255, 128 + Int(rng.unit() * Double(boxSwing)) - boxSwing / 2)))
                } }
            }
            if noise > 0 {
                for i in 0..<px.count { px[i] = UInt8(max(0, min(255, Int(px[i]) + Int(rng.unit() * Double(2 * noise + 1)) - noise))) }
            }
            return LumaFrame(width: w, height: h, pixels: px)
        }
    }

    func testFindsTheMovingCenterBox() throws {
        // 中央 16:9 方塊：x 16…48、y 9…27（32×18）。
        let r = try XCTUnwrap(VideoRegionDetector.detect(frames: frames(box: (16, 9, 32, 18))))
        XCTAssertEqual(r.x, 16.0 / 64, accuracy: 0.03)
        XCTAssertEqual(r.y, 9.0 / 36, accuracy: 0.04)
        XCTAssertEqual(r.width, 32.0 / 64, accuracy: 0.05)
        XCTAssertEqual(r.height, 18.0 / 36, accuracy: 0.06)
    }

    func testFindsAnOffCenterBoxAndIgnoresASmallerFlicker() throws {
        var fs = frames(box: (30, 4, 30, 17))
        // 另一個小閃爍（廣告小圖示）：比主區域小很多。
        var rng = RNG(s: 99)
        fs = fs.map { f in
            var p = f.pixels
            for y in 28..<32 { for x in 4..<10 { p[y * w + x] = UInt8(rng.next() % 256) } }
            return LumaFrame(width: w, height: h, pixels: p)
        }
        let r = try XCTUnwrap(VideoRegionDetector.detect(frames: fs))
        XCTAssertEqual(r.x, 30.0 / 64, accuracy: 0.04)
        XCTAssertEqual(r.width, 30.0 / 64, accuracy: 0.06)
        XCTAssertLessThan(r.y + r.height, 0.7, "不含左下角的小閃爍")
    }

    func testWholePageMovingReturnsNil() {
        XCTAssertNil(VideoRegionDetector.detect(frames: frames(box: (0, 0, 64, 36))), "整頁都在動（例如捲動）不亂框")
        XCTAssertNil(VideoRegionDetector.detect(frames: frames(box: (1, 1, 62, 34))))
    }

    func testAllStaticReturnsNil() {
        XCTAssertNil(VideoRegionDetector.detect(frames: frames(box: nil)))
    }

    func testNoiseBelowTheThresholdIsIgnored() {
        XCTAssertNil(VideoRegionDetector.detect(frames: frames(box: nil, noise: VideoRegionDetector.noiseThreshold / 3)))
        // 有真正的方塊時，低於門檻的全畫面雜訊不影響框選。
        let r = VideoRegionDetector.detect(frames: frames(box: (16, 9, 32, 18), noise: VideoRegionDetector.noiseThreshold / 3))
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.width ?? 0, 0.5, accuracy: 0.08)
    }

    func testSparseRandomSpecklesAreNotARegion() {
        var rng = RNG(s: 5)
        let fs = (0..<12).map { _ -> LumaFrame in
            var p = [UInt8](repeating: 100, count: w * h)
            for _ in 0..<12 { p[Int(rng.next() % UInt64(w * h))] = UInt8(rng.next() % 256) }
            return LumaFrame(width: w, height: h, pixels: p)
        }
        XCTAssertNil(VideoRegionDetector.detect(frames: fs))
    }

    func testTinyMovingBlobIsRejected() {
        XCTAssertNil(VideoRegionDetector.detect(frames: frames(box: (30, 16, 3, 3))), "太小的區域（例如游標、轉圈圈）不當影片")
    }

    func testNeedsEnoughConsistentFrames() {
        XCTAssertNil(VideoRegionDetector.detect(frames: []))
        XCTAssertNil(VideoRegionDetector.detect(frames: Array(frames(box: (16, 9, 32, 18)).prefix(2))))
        var mixed = frames(box: (16, 9, 32, 18))
        mixed[3] = LumaFrame(width: 8, height: 8, pixels: [UInt8](repeating: 0, count: 64))
        XCTAssertNil(VideoRegionDetector.detect(frames: mixed), "尺寸不一致的輸入不處理")
        XCTAssertNil(VideoRegionDetector.detect(frames: [LumaFrame(width: 4, height: 4, pixels: [1, 2])] + frames(box: nil)))
    }

    func testResultIsAlwaysSanitized() throws {
        let r = try XCTUnwrap(VideoRegionDetector.detect(frames: frames(box: (0, 6, 40, 24))))
        XCTAssertEqual(r, r.sanitized)
        XCTAssertGreaterThanOrEqual(r.x, 0)
    }
}
