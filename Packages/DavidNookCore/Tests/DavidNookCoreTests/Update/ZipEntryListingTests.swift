import XCTest
@testable import DavidNookCore

final class ZipEntryListingTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeZip(files: [String: String]) throws -> URL {
        let src = tmp.appendingPathComponent("src")
        for (path, content) in files {
            let url = src.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        let zip = tmp.appendingPathComponent("a.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", src.appendingPathComponent("DavidNook.app").path, zip.path]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return zip
    }

    func testListsEntriesOfRealDittoZip() throws {
        let zip = try makeZip(files: ["DavidNook.app/Contents/Info.plist": "x", "DavidNook.app/Contents/MacOS/DavidNook": "y"])
        let names = try ZipEntryListing.entryNames(of: zip)
        XCTAssertTrue(names.contains("DavidNook.app/Contents/Info.plist"))
        XCTAssertTrue(names.contains("DavidNook.app/Contents/MacOS/DavidNook"))
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("DavidNook.app/") })
    }

    func testSafeLayoutAcceptsOnlyAppPrefixedRelativeEntries() throws {
        XCTAssertNoThrow(try ZipEntryListing.validateLayout(["DavidNook.app/", "DavidNook.app/Contents/Info.plist"], appName: "DavidNook.app"))
    }

    func testRejectsPathTraversalAbsoluteAndForeignEntries() {
        let bad: [[String]] = [
            ["DavidNook.app/../../evil"], ["../evil"], ["/etc/passwd"], ["DavidNook.app/a/../../b"],
            ["DavidNook.app/ok", "Other.app/x"], ["evil.sh"], ["DavidNook.app/\u{0}x"], ["DavidNook.app\\..\\x"],
        ]
        for names in bad {
            XCTAssertThrowsError(try ZipEntryListing.validateLayout(names, appName: "DavidNook.app"), "\(names)")
        }
    }

    func testEmptyArchiveIsRejected() {
        XCTAssertThrowsError(try ZipEntryListing.validateLayout([], appName: "DavidNook.app"))
    }

    func testGarbageFileIsRejected() throws {
        let f = tmp.appendingPathComponent("junk.zip")
        try Data("this is not a zip".utf8).write(to: f)
        XCTAssertThrowsError(try ZipEntryListing.entryNames(of: f))
    }

    func testTruncatedZipIsRejected() throws {
        let zip = try makeZip(files: ["DavidNook.app/Contents/Info.plist": String(repeating: "z", count: 5000)])
        let data = try Data(contentsOf: zip)
        let cut = tmp.appendingPathComponent("cut.zip")
        try data.prefix(data.count / 2).write(to: cut)
        XCTAssertThrowsError(try ZipEntryListing.entryNames(of: cut))
    }

    func testDittoExtractorRoundTripsRealZip() throws {
        let zip = try makeZip(files: ["DavidNook.app/Contents/Info.plist": "plist", "DavidNook.app/Contents/MacOS/DavidNook": "bin"])
        let out = tmp.appendingPathComponent("out")
        try DittoArchiveExtractor().extract(archive: zip, to: out)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("DavidNook.app/Contents/Info.plist")), "plist")
    }

    func testDittoExtractorRefusesZipWithForeignTopLevelItem() throws {
        let zip = try makeZip(files: ["DavidNook.app/Contents/Info.plist": "x"])
        // 另做一個頂層不是 DavidNook.app 的 zip。
        let other = tmp.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: other.appendingPathComponent("f"))
        let bad = tmp.appendingPathComponent("bad.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", other.path, bad.path]
        try p.run(); p.waitUntilExit()
        XCTAssertNoThrow(try DittoArchiveExtractor().extract(archive: zip, to: tmp.appendingPathComponent("ok")))
        let out = tmp.appendingPathComponent("never")
        XCTAssertThrowsError(try DittoArchiveExtractor().extract(archive: bad, to: out))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "不合格的 zip 不得開始解壓")
    }
}
