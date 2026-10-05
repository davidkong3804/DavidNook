import CryptoKit
import XCTest
@testable import DavidNookCore

/// 元件 1：ClipboardItem（資料模型、contentHash、Codable）。
final class ClipboardItemTests: XCTestCase {
    // SHA-256("abc") 的公開標準測試向量
    private let sha256ABC = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    // SHA-256("") 的公開標準測試向量
    private let sha256Empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    func testTextItemHashIsSHA256OfUTF8() {
        let item = ClipboardItem(text: "abc", now: t(0))
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "abc")
        XCTAssertNil(item.imageFileName)
        XCTAssertNil(item.filePaths)
        XCTAssertEqual(item.contentHash, sha256ABC)
    }

    func testEmptyAndUnicodeTextHashes() {
        XCTAssertEqual(ClipboardItem(text: "").contentHash, sha256Empty)
        let unicode = "繁體中文 🎵"
        let expected = SHA256.hash(data: Data(unicode.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(ClipboardItem(text: unicode).contentHash, expected)
    }

    func testImageItemHashIsSHA256OfRawDataAndFileNameDerivesFromHash() {
        let png = ClipboardItem(imageData: utf8("abc"), fileExtension: "png", now: t(0))
        XCTAssertEqual(png.kind, .image)
        XCTAssertEqual(png.contentHash, sha256ABC)
        XCTAssertEqual(png.imageFileName, "\(sha256ABC).png")
        XCTAssertNil(png.text)
        XCTAssertNil(png.filePaths)

        let tiff = ClipboardItem(imageData: utf8("abc"), fileExtension: "tiff")
        XCTAssertEqual(tiff.imageFileName, "\(sha256ABC).tiff")
        XCTAssertEqual(tiff.contentHash, png.contentHash, "同樣的原始資料 hash 相同，與副檔名無關")
    }

    func testImageFileExtensionIsSanitizedAgainstPathTricks() {
        let item = ClipboardItem(imageData: utf8("abc"), fileExtension: "../../evil")
        let name = item.imageFileName ?? ""
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(".."))
        XCTAssertNotNil(name.range(of: "^[0-9a-f]{64}\\.[a-z0-9]{1,8}$", options: .regularExpression), "檔名 = \(name)")
    }

    func testFilesHashUsesSortedPathsSoOrderDoesNotMatter() {
        let ab = ClipboardItem(filePaths: ["/b", "/a"])
        let ba = ClipboardItem(filePaths: ["/a", "/b"])
        XCTAssertEqual(ab.contentHash, ba.contentHash)
        XCTAssertEqual(ab.kind, .files)
        XCTAssertEqual(ab.filePaths, ["/b", "/a"], "保留複製時的原始順序")
        XCTAssertNil(ab.text)
        XCTAssertNil(ab.imageFileName)
        // 單一路徑時，排序串接就是路徑本身
        XCTAssertEqual(ClipboardItem(filePaths: ["abc"]).contentHash, sha256ABC)
        // 路徑集合不同 → hash 不同；且以分隔符避免 ["ab","c"] 與 ["a","bc"] 撞 hash
        XCTAssertNotEqual(ClipboardItem(filePaths: ["ab", "c"]).contentHash, ClipboardItem(filePaths: ["a", "bc"]).contentHash)
    }

    func testSameContentDifferentKindsShareHashButNotDedupKey() {
        let text = ClipboardItem(text: "abc")
        let image = ClipboardItem(imageData: utf8("abc"))
        let files = ClipboardItem(filePaths: ["abc"])
        XCTAssertEqual(text.contentHash, image.contentHash)
        XCTAssertEqual(text.contentHash, files.contentHash)
        XCTAssertEqual(Set([text.dedupKey, image.dedupKey, files.dedupKey]).count, 3)
    }

    func testInitializerDefaults() {
        let a = ClipboardItem(text: "x", now: t(5))
        let b = ClipboardItem(text: "x", now: t(5))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.createdAt, t(5))
        XCTAssertEqual(a.lastUsedAt, t(5))
        XCTAssertFalse(a.isPinned)
        XCTAssertNil(a.sourceAppBundleID)
    }

    func testCodableRoundTripPreservesAllFieldsForEveryKind() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000.123456)
        var items = [
            ClipboardItem(text: "你好", now: created, isPinned: true, sourceAppBundleID: "com.apple.Notes"),
            ClipboardItem(imageData: tinyPNG, fileExtension: "png", now: created),
            ClipboardItem(filePaths: ["/Users/a/b c.txt", "/tmp/x"], now: created, sourceAppBundleID: "com.apple.finder"),
        ]
        items[1].lastUsedAt = created.addingTimeInterval(99.5)
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)
        XCTAssertEqual(decoded, items)
    }

    func testDecodingRejectsKindPayloadMismatch() throws {
        let item = ClipboardItem(text: "hello")
        let data = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "text")
        let broken = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(ClipboardItem.self, from: broken))

        var wrongKind = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        wrongKind["kind"] = "image"   // 有 text 卻沒有 imageFileName
        let broken2 = try JSONSerialization.data(withJSONObject: wrongKind)
        XCTAssertThrowsError(try JSONDecoder().decode(ClipboardItem.self, from: broken2))
    }

    func testClipboardKindRawValuesAreStable() {
        XCTAssertEqual(ClipboardKind.text.rawValue, "text")
        XCTAssertEqual(ClipboardKind.image.rawValue, "image")
        XCTAssertEqual(ClipboardKind.files.rawValue, "files")
    }
}
