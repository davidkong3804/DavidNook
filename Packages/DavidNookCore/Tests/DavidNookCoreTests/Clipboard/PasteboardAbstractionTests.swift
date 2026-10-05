import AppKit
import XCTest
@testable import DavidNookCore

/// 元件 2（純邏輯部分）：PasteboardSnapshot 與寫回時的表示法編碼。
final class PasteboardSnapshotTests: XCTestCase {
    func testEagerSnapshotExposesChangeCountTypesAndData() {
        let snapshot = PasteboardSnapshot(
            changeCount: 7,
            types: ["public.utf8-plain-text", "public.rtf"],
            data: ["public.utf8-plain-text": [utf8("hi")]],
            sourceAppBundleID: "com.example.app"
        )
        XCTAssertEqual(snapshot.changeCount, 7)
        XCTAssertEqual(snapshot.types, ["public.utf8-plain-text", "public.rtf"])
        XCTAssertEqual(snapshot.sourceAppBundleID, "com.example.app")
        XCTAssertEqual(snapshot.data(forType: "public.utf8-plain-text"), utf8("hi"))
        XCTAssertNil(snapshot.data(forType: "public.rtf"), "宣告了型別但沒有資料")
        XCTAssertNil(snapshot.data(forType: "no.such.type"))
    }

    func testDataIsLoadedLazilyOnlyWhenRequested() {
        let counter = DataReadCounter()
        let snapshot = makeCountingSnapshot(["public.utf8-plain-text": utf8("secret")], counter: counter)
        _ = snapshot.types
        _ = snapshot.changeCount
        XCTAssertEqual(counter.count, 0, "只看 types/changeCount 不得讀取內容")
        _ = snapshot.data(forType: "public.utf8-plain-text")
        XCTAssertEqual(counter.readTypes, ["public.utf8-plain-text"])
    }

    func testFirstDataVersusAllDataAcrossItems() {
        let snapshot = PasteboardSnapshot(
            changeCount: 1,
            types: [PBType.fileURL],
            data: [PBType.fileURL: [utf8("file:///a"), utf8("file:///b")]]
        )
        XCTAssertEqual(snapshot.data(forType: PBType.fileURL), utf8("file:///a"))
        XCTAssertEqual(snapshot.allData(forType: PBType.fileURL), [utf8("file:///a"), utf8("file:///b")])
        XCTAssertEqual(snapshot.allData(forType: "missing"), [])
    }

    func testHasTypeIsCaseInsensitive() {
        let snapshot = makeSnapshot(["Org.NSPasteboard.ConcealedType": utf8("x")])
        XCTAssertTrue(snapshot.hasType("org.nspasteboard.concealedtype"))
        XCTAssertFalse(snapshot.hasType("org.nspasteboard.TransientType"))
    }
}

/// 寫回時的表示法編碼（純邏輯，不碰任何剪貼簿）。
final class PasteboardEncodingTests: XCTestCase {
    func testTextItemEncodesUTF8TextPlusSelfMarkerCarryingItemID() throws {
        let item = ClipboardItem(text: "你好")
        let items = try XCTUnwrap(item.pasteboardRepresentations())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].first { $0.type == PBType.utf8Text }?.data, utf8("你好"))
        XCTAssertEqual(items[0].first { $0.type == PBType.selfMarker }?.data, utf8(item.id.uuidString))
    }

    func testImageItemEncodesPNGOrTIFFByExtension() throws {
        let png = ClipboardItem(imageData: tinyPNG, fileExtension: "png")
        let pngItems = try XCTUnwrap(png.pasteboardRepresentations(imageData: tinyPNG))
        XCTAssertEqual(pngItems[0].first { $0.type == PBType.png }?.data, tinyPNG)
        XCTAssertNil(pngItems[0].first { $0.type == PBType.tiff })

        let tiff = ClipboardItem(imageData: tinyPNG, fileExtension: "tiff")
        let tiffItems = try XCTUnwrap(tiff.pasteboardRepresentations(imageData: tinyPNG))
        XCTAssertNotNil(tiffItems[0].first { $0.type == PBType.tiff })
        XCTAssertNotNil(tiffItems[0].first { $0.type == PBType.selfMarker })
    }

    func testImageItemWithoutDataCannotBeEncoded() {
        XCTAssertNil(ClipboardItem(imageData: tinyPNG).pasteboardRepresentations(imageData: nil))
    }

    func testFilesItemEncodesOnePasteboardItemPerPathEachWithMarker() throws {
        let item = ClipboardItem(filePaths: ["/Users/a/My File.txt", "/tmp/b"])
        let items = try XCTUnwrap(item.pasteboardRepresentations())
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].first { $0.type == PBType.fileURL }?.data, fileURLData("/Users/a/My File.txt"))
        XCTAssertEqual(items[1].first { $0.type == PBType.fileURL }?.data, fileURLData("/tmp/b"))
        for entry in items {
            XCTAssertEqual(entry.first { $0.type == PBType.selfMarker }?.data, utf8(item.id.uuidString))
        }
    }
}

/// 元件 2（真實 NSPasteboard 部分）：NSPasteboardReader / NSPasteboardWriter，只用具名剪貼簿。
final class NSPasteboardAdapterTests: NamedPasteboardTestCase {
    func testReaderChangeCountTracksPasteboardAndAdvancesOnChange() {
        let reader = NSPasteboardReader(pasteboard: pasteboard, sourceAppProvider: { nil })
        XCTAssertEqual(reader.changeCount, pasteboard.changeCount)
        let before = reader.changeCount
        externalCopy([(PBType.utf8Text, utf8("a"))])
        XCTAssertGreaterThan(reader.changeCount, before)
        XCTAssertEqual(reader.changeCount, pasteboard.changeCount)
    }

    func testReaderSnapshotListsTypesAndReadsData() {
        externalCopy([(PBType.utf8Text, utf8("hello")), (PBType.png, tinyPNG)])
        let reader = NSPasteboardReader(pasteboard: pasteboard, sourceAppProvider: { nil })
        let snapshot = reader.snapshot()
        XCTAssertEqual(snapshot.changeCount, pasteboard.changeCount)
        XCTAssertTrue(snapshot.hasType(PBType.utf8Text))
        XCTAssertTrue(snapshot.hasType(PBType.png))
        XCTAssertEqual(snapshot.data(forType: PBType.utf8Text), utf8("hello"))
        XCTAssertEqual(snapshot.data(forType: PBType.png), tinyPNG)
    }

    func testReaderOnEmptyPasteboardHasNoTypes() {
        let reader = NSPasteboardReader(pasteboard: pasteboard, sourceAppProvider: { nil })
        let snapshot = reader.snapshot()
        XCTAssertTrue(snapshot.types.isEmpty)
        XCTAssertNil(snapshot.data(forType: PBType.utf8Text))
    }

    func testReaderCollectsFileURLsAcrossMultiplePasteboardItems() {
        let a = NSURL(fileURLWithPath: "/Users/example/Documents/a.txt")
        let b = NSURL(fileURLWithPath: "/Users/example/Documents/b.txt")
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([a, b]))
        let reader = NSPasteboardReader(pasteboard: pasteboard, sourceAppProvider: { nil })
        let snapshot = reader.snapshot()
        XCTAssertTrue(snapshot.hasType(PBType.fileURL))
        XCTAssertEqual(snapshot.allData(forType: PBType.fileURL).count, 2)
    }

    func testReaderUnionsTypesOfAllItemsSoAConcealedMarkerOnLaterItemIsStillSeen() {
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("visible", forType: .string)
        let second = NSPasteboardItem()
        second.setString("x", forType: .string)
        second.setData(Data(), forType: NSPasteboard.PasteboardType(PBType.concealed))
        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        let snapshot = NSPasteboardReader(pasteboard: pasteboard, sourceAppProvider: { nil }).snapshot()
        XCTAssertTrue(snapshot.hasType(PBType.concealed))
    }

    func testReaderUsesNSPasteboardSourceTypeBeforeFallbackProvider() {
        externalCopy([(PBType.utf8Text, utf8("x")), (PBType.source, utf8("com.example.source"))])
        let reader = NSPasteboardReader(pasteboard: pasteboard, sourceAppProvider: { "com.example.frontmost" })
        XCTAssertEqual(reader.snapshot().sourceAppBundleID, "com.example.source")

        externalCopy([(PBType.utf8Text, utf8("y"))])
        XCTAssertEqual(reader.snapshot().sourceAppBundleID, "com.example.frontmost")
    }

    func testWriterWritesTextAndSelfMarkerAndReturnsNewChangeCount() {
        let writer = NSPasteboardWriter(pasteboard: pasteboard)
        let before = pasteboard.changeCount
        let item = ClipboardItem(text: "寫回")
        let new = writer.write(item.pasteboardRepresentations()!)
        XCTAssertEqual(new, pasteboard.changeCount, "回傳值必須等於寫入完成後的 changeCount")
        XCTAssertGreaterThan(new, before)
        XCTAssertEqual(pasteboard.string(forType: .string), "寫回")
        XCTAssertEqual(pasteboard.data(forType: NSPasteboard.PasteboardType(PBType.selfMarker)), utf8(item.id.uuidString))
    }

    func testWriterReplacesPreviousContentsAndWritesMultipleFileItems() {
        externalCopy([(PBType.utf8Text, utf8("old"))])
        let writer = NSPasteboardWriter(pasteboard: pasteboard)
        let item = ClipboardItem(filePaths: ["/Users/example/a.txt", "/Users/example/b.txt"])
        _ = writer.write(item.pasteboardRepresentations()!)
        XCTAssertNil(pasteboard.string(forType: .string), "舊內容必須被清掉")
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.map(\.path), ["/Users/example/a.txt", "/Users/example/b.txt"])
    }
}
