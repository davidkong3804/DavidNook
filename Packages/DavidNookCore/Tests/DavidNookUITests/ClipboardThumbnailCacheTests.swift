import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DavidNookUI

/// 縮圖快取：證明大圖由 ImageIO 在背景縮成小圖、原圖不會被整張保存。圖片全部由 CoreGraphics 現場生成（漸層），沒有任何真實內容。
final class ClipboardThumbnailCacheTests: XCTestCase {
    /// 用 CoreGraphics 畫一張 width×height 的漸層並存成 PNG；回傳檔案 URL。
    private func writeGradientPNG(width: Int, height: Int) throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let gradient = try XCTUnwrap(CGGradient(
            colorsSpace: space,
            colors: [CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1), CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)] as CFArray,
            locations: [0, 1]
        ))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        let image = try XCTUnwrap(context.makeImage())

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DavidNookThumb-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        // 縮圖以 2x 為準：點數 × 2 ＝ 像素。
        (Int((image.size.width * 2).rounded()), Int((image.size.height * 2).rounded()))
    }

    func testDefaultLimitsAreTheDocumentedOnes() {
        let cache = ClipboardThumbnailCache()
        XCTAssertEqual(cache.maxPixelSize, 96)
        XCTAssertEqual(cache.countLimit, 120)
        XCTAssertEqual(cache.totalCostLimit, 8 * 1024 * 1024)
        XCTAssertEqual(cache.maxSourcePixels, 100_000_000)
    }

    func testLargeImageIsDownscaledToMaxPixelSizeKeepingAspect() async throws {
        let url = try writeGradientPNG(width: 4000, height: 3000)
        let cache = ClipboardThumbnailCache()
        let thumbOpt = await cache.thumbnail(for: url)
        let thumb = try XCTUnwrap(thumbOpt)
        let size = pixelSize(of: thumb)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 96, "最長邊不得超過 96 像素")
        XCTAssertEqual(max(size.width, size.height), 96, "有縮到上限而不是更小")
        XCTAssertEqual(Double(size.width) / Double(size.height), 4.0 / 3.0, accuracy: 0.05, "保留比例")
    }

    func testThumbnailIsServedFromMemoryCacheAfterFirstGeneration() async throws {
        let url = try writeGradientPNG(width: 800, height: 600)
        let cache = ClipboardThumbnailCache()
        XCTAssertNil(cache.cachedThumbnail(for: url))
        let firstOpt = await cache.thumbnail(for: url)
        let first = try XCTUnwrap(firstOpt)
        XCTAssertTrue(cache.cachedThumbnail(for: url) === first)

        // 檔案刪掉以後，快取仍能回傳（證明第二次沒有再碰磁碟）。
        try FileManager.default.removeItem(at: url)
        let second = await cache.thumbnail(for: url)
        XCTAssertTrue(second === first)

        cache.removeAll()
        XCTAssertNil(cache.cachedThumbnail(for: url))
    }

    func testConcurrentRequestsForSameFileShareOneGeneration() async throws {
        let url = try writeGradientPNG(width: 1600, height: 1200)
        let cache = ClipboardThumbnailCache()
        let images = await withTaskGroup(of: NSImage?.self) { group in
            for _ in 0..<8 { group.addTask { await cache.thumbnail(for: url) } }
            var result: [NSImage?] = []
            for await image in group { result.append(image) }
            return result
        }
        let first = try XCTUnwrap(images.first ?? nil)
        for image in images {
            XCTAssertTrue(try XCTUnwrap(image) === first, "同一檔案同時被多處要求時只產生一次")
        }
    }

    func testMissingFileReturnsNil() async {
        let cache = ClipboardThumbnailCache()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).png")
        let thumb = await cache.thumbnail(for: url)
        XCTAssertNil(thumb)
    }

    func testNonImageFileReturnsNil() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-image-\(UUID().uuidString).png")
        try Data("this is not a png".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let cache = ClipboardThumbnailCache()
        let thumb = await cache.thumbnail(for: url)
        XCTAssertNil(thumb)
    }

    func testSourceLargerThanPixelBudgetIsNotDecoded() async throws {
        let url = try writeGradientPNG(width: 2000, height: 1500)  // 3,000,000 px
        let strict = ClipboardThumbnailCache(maxSourcePixels: 1_000_000)
        let rejected = await strict.thumbnail(for: url)
        XCTAssertNil(rejected, "超過像素上限的來源不解碼（避免壓縮炸彈）")
        let relaxed = ClipboardThumbnailCache(maxSourcePixels: 4_000_000)
        let accepted = await relaxed.thumbnail(for: url)
        XCTAssertNotNil(accepted)
    }

    func testCostIsProportionalToThumbnailPixelsNotSourcePixels() async throws {
        let url = try writeGradientPNG(width: 3000, height: 3000)
        let cache = ClipboardThumbnailCache()
        let thumbOpt = await cache.thumbnail(for: url)
        let thumb = try XCTUnwrap(thumbOpt)
        let size = pixelSize(of: thumb)
        // 一張縮圖最多 96×96×4 ≈ 36KB；8MB 上限可容納 200 多張。
        XCTAssertLessThanOrEqual(size.width * size.height * 4, 96 * 96 * 4)
        XCTAssertGreaterThan(cache.totalCostLimit / (96 * 96 * 4), 200)
    }
}
