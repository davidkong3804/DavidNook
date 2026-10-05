import XCTest
@testable import DavidNookUI

/// F6：縮圖快取持有由剪貼簿圖片產生的縮圖與檔案路徑；字串化時不得露出（description／dump 一律 `<redacted>`）。
final class ClipboardThumbnailRedactionTests: XCTestCase {
    func testThumbnailCacheDescriptionsAreRedacted() async {
        let cache = ClipboardThumbnailCache()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("secret-dir-F6/secret-image.png")
        // 以不存在的檔案觸發一次查詢（會把路徑當 key 放進 in-flight 表一瞬間）。
        _ = await cache.thumbnail(for: missing)

        var dumped = ""
        dump(cache, to: &dumped)
        for rendering in [String(describing: cache), "\(cache)", String(reflecting: cache), dumped] {
            XCTAssertTrue(rendering.contains("redacted"), rendering)
            XCTAssertFalse(rendering.contains("secret-dir-F6"), rendering)
            XCTAssertFalse(rendering.contains("secret-image"), rendering)
        }
    }
}
