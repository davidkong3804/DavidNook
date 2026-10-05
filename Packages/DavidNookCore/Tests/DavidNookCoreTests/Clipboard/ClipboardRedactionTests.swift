import XCTest
@testable import DavidNookCore

/// F6：任何持有剪貼簿內容的型別，被 `print`／字串內插／`String(describing:)`／`String(reflecting:)`／`dump`
/// 都不得露出內容。description 只含種類與位元組數（或筆數），固定帶 `<redacted>`。
/// 測試資料全部自編。
final class ClipboardRedactionTests: XCTestCase {
    private let secretText = "TOPSECRET-F6-TEXT"
    private let secretPath = "/Users/secret-user/F6-private-plans.txt"
    private let secretImage = "IMAGE-F6-SECRET-BYTES"
    private let secretApp = "com.secret.f6app"
    private let secretQuery = "TOPSECRET-F6-QUERY"

    private var allSecrets: [String] {
        [secretText, secretPath, secretImage, secretApp, secretQuery, "secret-user", "private-plans", "F6-private"]
    }

    /// 所有把一個值轉成字串的方式。
    private func renderings(of value: Any) -> [String] {
        var dumped = ""
        dump(value, to: &dumped)
        var debugPrinted = ""
        debugPrint(value, to: &debugPrinted)
        var printed = ""
        print(value, to: &printed)
        return [
            String(describing: value),
            "\(value)",
            String(reflecting: value),
            dumped,
            debugPrinted,
            printed,
        ]
    }

    private func assertRedacted(_ value: Any, secrets: [String]? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let hidden = secrets ?? allSecrets
        for rendering in renderings(of: value) {
            XCTAssertTrue(rendering.contains("redacted"), "缺少 redacted 標記：\(rendering)", file: file, line: line)
            for secret in hidden {
                XCTAssertFalse(rendering.contains(secret), "洩漏內容「\(secret)」：\(rendering)", file: file, line: line)
            }
        }
    }

    // MARK: ClipboardItem

    func testTextItemDescriptionsHideTheTextAndSourceApp() {
        let item = ClipboardItem(text: secretText, sourceAppBundleID: secretApp)
        assertRedacted(item)
        XCTAssertTrue(String(describing: item).contains("kind=text"))
        XCTAssertTrue(String(describing: item).contains("bytes=\(secretText.utf8.count)"), String(describing: item))
        XCTAssertEqual(String(describing: item), String(reflecting: item))
    }

    func testFilesItemDescriptionsHideEveryPath() {
        let item = ClipboardItem(filePaths: [secretPath, "/Users/secret-user/second.txt"], sourceAppBundleID: secretApp)
        assertRedacted(item)
        XCTAssertTrue(String(describing: item).contains("kind=files"))
        XCTAssertTrue(String(describing: item).contains("count=2"), String(describing: item))
    }

    func testImageItemDescriptionsHideFileNameAndHash() {
        let item = ClipboardItem(imageData: Data(secretImage.utf8), sourceAppBundleID: secretApp)
        let hash = item.contentHash
        assertRedacted(item, secrets: allSecrets + [hash])
        XCTAssertTrue(String(describing: item).contains("kind=image"))
    }

    func testArraysAndOptionalsOfItemsAreRedactedToo() {
        let items = [ClipboardItem(text: secretText), ClipboardItem(filePaths: [secretPath])]
        assertRedacted(items)
        assertRedacted(Optional(items[0]) as Any)
        assertRedacted(["k": items[1]])
    }

    // MARK: ClipboardCapture

    func testCaptureDescriptionsHideEveryPayload() {
        let text = ClipboardCapture(text: secretText, sourceAppBundleID: secretApp)
        let files = ClipboardCapture(filePaths: [secretPath], sourceAppBundleID: secretApp)
        let image = ClipboardCapture(imageData: Data(secretImage.utf8), sourceAppBundleID: secretApp)
        assertRedacted(text)
        assertRedacted(files)
        assertRedacted(image, secrets: allSecrets + [image.contentHash])
        XCTAssertTrue(String(describing: text).contains("bytes=\(secretText.utf8.count)"), String(describing: text))
        XCTAssertTrue(String(describing: image).contains("bytes=\(secretImage.utf8.count)"), String(describing: image))
        XCTAssertTrue(String(describing: files).contains("count=1"), String(describing: files))
    }

    func testPayloadEnumAloneIsRedacted() {
        assertRedacted(ClipboardCapture.Payload.text(secretText))
        assertRedacted(ClipboardCapture.Payload.files([secretPath]))
        assertRedacted(ClipboardCapture.Payload.image(Data(secretImage.utf8), fileExtension: "png"))
    }

    func testDecisionAndAddResultWrappingContentAreRedacted() {
        let capture = ClipboardCapture(text: secretText, sourceAppBundleID: secretApp)
        assertRedacted(ClipboardDecision.record(capture), secrets: allSecrets, line: #line)
        let item = ClipboardItem(text: secretText)
        assertRedacted(ClipboardAddResult.inserted(item))
        assertRedacted(ClipboardAddResult.bumped(item))
    }

    // MARK: PasteboardSnapshot / PasteboardRepresentation

    func testSnapshotDescriptionsHideContentAndNeverInvokeTheProviders() {
        let counter = DataReadCounter()
        let snapshot = PasteboardSnapshot(
            changeCount: 7,
            types: [PBType.utf8Text, PBType.png],
            sourceAppBundleIDProvider: { self.secretApp },
            dataProvider: { type in
                counter.record(type)
                return [Data(self.secretText.utf8)]
            }
        )
        assertRedacted(snapshot)
        XCTAssertTrue(String(describing: snapshot).contains("changeCount=7"), String(describing: snapshot))
        XCTAssertEqual(counter.count, 0, "字串化 snapshot 不得觸發任何資料讀取")
    }

    func testPasteboardRepresentationHidesItsData() {
        let representation = PasteboardRepresentation(type: PBType.utf8Text, data: Data(secretText.utf8))
        assertRedacted(representation)
        XCTAssertTrue(String(describing: representation).contains("bytes=\(secretText.utf8.count)"), String(describing: representation))
        assertRedacted([[representation]])
    }

    // MARK: ClipboardPanelModel

    func testPanelModelHidesItemsAndTheSearchQuery() {
        let model = ClipboardPanelModel(
            items: [ClipboardItem(text: secretText), ClipboardItem(filePaths: [secretPath])],
            query: secretQuery
        )
        assertRedacted(model)
    }
}
