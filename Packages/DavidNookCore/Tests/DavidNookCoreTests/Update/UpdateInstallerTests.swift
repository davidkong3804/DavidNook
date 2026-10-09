import XCTest
@testable import DavidNookCore

// 檔案操作全在 temp 目錄；下載／解壓／簽章檢查都以假物件取代。「App」只是帶標記檔的普通資料夾。

private final class FakeDownloader: UpdateDownloading, @unchecked Sendable {
    var payload = Data("zip-bytes".utf8)
    var failure: Error?
    private(set) var requestedURLs: [URL] = []
    func download(from url: URL, to destination: URL, progress: @Sendable (Double) -> Void) async throws {
        requestedURLs.append(url)
        if let failure { throw failure }
        progress(0.5)
        try payload.write(to: destination)
        progress(1.0)
    }
}

private final class FakeExtractor: ArchiveExtracting, @unchecked Sendable {
    var marker = "NEW"
    var extraItems: [String] = []
    var skipApp = false
    var failure: Error?
    func extract(archive: URL, to directory: URL) throws {
        if let failure { throw failure }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !skipApp {
            let app = directory.appendingPathComponent("DavidNook.app")
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: app.appendingPathComponent("Contents/marker.txt"))
        }
        for item in extraItems { try Data("x".utf8).write(to: directory.appendingPathComponent(item)) }
    }
}

final class UpdateInstallerTests: XCTestCase {
    private var root: URL!
    private var installDir: URL!
    private var work: URL!
    private var target: URL!
    private let current = SemanticVersion("0.1.0-beta.1")!

    private var sha: String { SHA256HexForTests.of(Data("zip-bytes".utf8)) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("installer-\(UUID().uuidString)")
        installDir = root.appendingPathComponent("Apps")
        work = root.appendingPathComponent("work")
        target = installDir.appendingPathComponent("DavidNook.app")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: target.appendingPathComponent("Contents/marker.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: installDir.path)
        try? FileManager.default.removeItem(at: root)
    }

    private func marker(_ app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    private func candidate(sha: String? = nil) -> UpdateCandidate {
        UpdateCandidate(
            version: SemanticVersion("0.2.0-beta.1")!, tag: "v0.2.0-beta.1", title: "v0.2.0-beta.1", isPrerelease: true,
            releasePageURL: URL(string: "https://github.com/davidkong3804/DavidNook/releases/tag/v0.2.0-beta.1")!,
            archiveURL: URL(string: "https://github.com/davidkong3804/DavidNook/releases/download/v0.2.0-beta.1/DavidNook-0.2.0-beta.1-arm64.zip")!,
            archiveName: "DavidNook-0.2.0-beta.1-arm64.zip", archiveSize: 9, sha256: sha ?? self.sha, notes: "n"
        )
    }

    private struct Rig {
        var installer: UpdateInstaller
        var downloader: FakeDownloader
        var extractor: FakeExtractor
        var inspector: FakeInspector
    }

    private func rig(replace: (@Sendable (URL, URL, String) throws -> Void)? = nil) -> Rig {
        let downloader = FakeDownloader()
        let extractor = FakeExtractor()
        let inspector = FakeInspector(.goodNext)
        let installer = UpdateInstaller(
            downloader: downloader, extractor: extractor, verifier: UpdateVerifier(inspector: inspector),
            volumeIsReadOnly: { _ in false }, replaceItem: replace
        )
        return Rig(installer: installer, downloader: downloader, extractor: extractor, inspector: inspector)
    }

    private func request(_ candidate: UpdateCandidate? = nil, target: URL? = nil) -> UpdateInstallRequest {
        UpdateInstallRequest(candidate: candidate ?? self.candidate(), currentVersion: current,
                             currentEntitlements: AppBundleFacts.currentEntitlements,
                             targetAppURL: target ?? self.target, workDirectory: work)
    }

    private func run(_ rig: Rig, _ req: UpdateInstallRequest, phases: Locked<[UpdatePhase]> = Locked([])) async throws -> URL {
        try await rig.installer.run(req) { phase in phases.withLock { $0.append(phase) } }
    }

    // MARK: 成功路徑

    func testHappyPathReplacesAppKeepsBackupAndReportsPhasesInOrder() async throws {
        let rig = rig()
        let phases = Locked<[UpdatePhase]>([])
        let result = try await run(rig, request(), phases: phases)

        XCTAssertEqual(result.standardizedFileURL.path, target.standardizedFileURL.path)
        XCTAssertEqual(marker(target), "NEW")
        let backup = installDir.appendingPathComponent("DavidNook.app.previous")
        XCTAssertEqual(marker(backup), "OLD", "舊版備份在 DavidNook.app.previous")
        XCTAssertEqual(rig.downloader.requestedURLs, [candidate().archiveURL])

        let kinds = phases.snapshot.map { $0.kind }
        XCTAssertEqual(kinds.first, .downloading)
        XCTAssertEqual(Array(kinds.drop(while: { $0 == .downloading })), [.verifying, .installing, .finished])
        XCTAssertTrue(phases.snapshot.contains(.downloading(progress: 1.0)))
        // 暫存的解壓與下載已清掉
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("extracted").path))
        // 安裝目錄裡沒有留下暫存殘骸
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installDir.path).sorted()
        XCTAssertEqual(leftovers, ["DavidNook.app", "DavidNook.app.previous"])
    }

    func testOldBackupIsReplacedByNewBackup() async throws {
        let rig = rig()
        let old = installDir.appendingPathComponent("DavidNook.app.previous")
        try FileManager.default.createDirectory(at: old.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("ANCIENT".utf8).write(to: old.appendingPathComponent("Contents/marker.txt"))
        _ = try await run(rig, request())
        XCTAssertEqual(marker(old), "OLD")
        XCTAssertEqual(marker(target), "NEW")
    }

    // MARK: 驗證失敗＝不覆蓋

    func testChecksumMismatchNeverTouchesInstalledApp() async throws {
        let rig = rig()
        do {
            _ = try await run(rig, request(candidate(sha: String(repeating: "0", count: 64))))
            XCTFail("應拋錯")
        } catch let error as UpdateInstallError {
            guard case .verification(.checksumMismatch) = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(marker(target), "OLD")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.appendingPathComponent("DavidNook.app.previous").path))
        XCTAssertTrue(rig.inspector.inspectedPaths.isEmpty, "雜湊不符時連解壓都不該發生")
    }

    func testAppVerificationFailureNeverTouchesInstalledApp() async throws {
        let rig = rig()
        var bad = AppBundleFacts.goodNext
        bad.entitlements["com.apple.security.cs.disable-library-validation"] = .bool(true)
        rig.inspector.set(bad, forPathSuffix: "extracted/DavidNook.app")
        do {
            _ = try await run(rig, request())
            XCTFail("應拋錯")
        } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .verification(.entitlementsExpanded(["com.apple.security.cs.disable-library-validation"])))
        }
        XCTAssertEqual(marker(target), "OLD")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installDir.path), ["DavidNook.app"])
    }

    func testDowngradeCandidateIsRejected() async throws {
        let rig = rig()
        var req = request()
        req.currentVersion = SemanticVersion("0.2.0-beta.1")!
        do { _ = try await run(rig, req); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            guard case .verification(.notNewer) = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(marker(target), "OLD")
    }

    func testArchiveWithoutAppIsRejected() async throws {
        let rig = rig()
        rig.extractor.skipApp = true
        do { _ = try await run(rig, request()); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .unexpectedArchiveContents)
        }
        XCTAssertEqual(marker(target), "OLD")
    }

    func testArchiveWithExtraTopLevelItemsIsRejected() async throws {
        let rig = rig()
        rig.extractor.extraItems = ["evil.sh"]
        do { _ = try await run(rig, request()); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .unexpectedArchiveContents)
        }
        XCTAssertEqual(marker(target), "OLD")
    }

    func testDownloadFailureIsReportedAndNothingChanges() async throws {
        let rig = rig()
        rig.downloader.failure = URLError(.notConnectedToInternet)
        do { _ = try await run(rig, request()); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            guard case .download = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(marker(target), "OLD")
    }

    func testExtractionFailureIsReported() async throws {
        let rig = rig()
        rig.extractor.failure = NSError(domain: "x", code: 1)
        do { _ = try await run(rig, request()); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            guard case .extraction = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(marker(target), "OLD")
    }

    // MARK: 失敗還原

    func testReplaceFailureLeavesOldAppInPlace() async throws {
        struct Boom: Error {}
        let rig = rig(replace: { _, _, _ in throw Boom() })
        do { _ = try await run(rig, request()); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            guard case .replaceFailed(_, let restored) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(restored)
        }
        XCTAssertEqual(marker(target), "OLD")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installDir.path).sorted(), ["DavidNook.app"], "暫存的新版也要清掉")
    }

    func testPostInstallVerificationFailureRestoresPreviousVersion() async throws {
        let rig = rig()
        var bad = AppBundleFacts.goodNext
        bad.signatureError = "broken after copy"
        rig.inspector.set(bad, forPathSuffix: "Apps/DavidNook.app") // 只有安裝後的位置不通過
        do { _ = try await run(rig, request()); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .postInstallVerificationFailed(.invalidSignature("broken after copy"), restored: true))
        }
        XCTAssertEqual(marker(target), "OLD", "自動還原舊版")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installDir.path).sorted(), ["DavidNook.app"])
    }

    func testCancellationBeforeInstallLeavesAppUntouched() async throws {
        let rig = rig()
        let task = Task { try await self.run(rig, self.request()) }
        task.cancel()
        _ = await task.result
        XCTAssertEqual(marker(target), "OLD")
    }

    // MARK: 位置檢查

    func testPreflightOkForWritableFolder() {
        XCTAssertEqual(UpdateInstaller.preflight(targetAppURL: target, volumeIsReadOnly: { _ in false }), .ok)
    }

    func testPreflightRejectsAppTranslocation() {
        let url = URL(fileURLWithPath: "/private/var/folders/xx/T/AppTranslocation/ABCD-1234/d/DavidNook.app")
        XCTAssertEqual(UpdateInstaller.preflight(targetAppURL: url, volumeIsReadOnly: { _ in false }), .translocated)
    }

    func testPreflightRejectsReadOnlyVolume() {
        XCTAssertEqual(UpdateInstaller.preflight(targetAppURL: target, volumeIsReadOnly: { _ in true }), .readOnlyVolume)
    }

    func testPreflightReportsNeedsFolderAccessWhenParentNotWritable() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: installDir.path)
        XCTAssertEqual(UpdateInstaller.preflight(targetAppURL: target, volumeIsReadOnly: { _ in false }), .needsFolderAccess)
    }

    func testRunRefusesTranslocatedPath() async throws {
        let rig = rig()
        let url = URL(fileURLWithPath: "/private/var/folders/xx/T/AppTranslocation/ABCD/d/DavidNook.app")
        do { _ = try await run(rig, request(target: url)); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .translocated)
        }
        XCTAssertTrue(rig.downloader.requestedURLs.isEmpty, "位置不合格時連下載都不該開始")
    }

    func testRunRefusesWhenParentNotWritable() async throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: installDir.path)
        let rig = rig()
        do { _ = try await run(rig, request()); XCTFail("應拋錯") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .targetNotWritable)
        }
        XCTAssertTrue(rig.downloader.requestedURLs.isEmpty)
    }

    func testUserFacingMessagesForLocationProblemsAreHelpful() {
        XCTAssertTrue(UpdateInstallError.translocated.reason.contains("應用程式"))
        XCTAssertFalse(UpdateInstallError.readOnlyVolume.reason.isEmpty)
    }

    // MARK: 授權資料夾

    func testGrantedFolderCoversParentOrAncestorOnly() {
        let app = URL(fileURLWithPath: "/Users/x/Applications/DavidNook.app")
        XCTAssertTrue(GrantedFolder.covers(URL(fileURLWithPath: "/Users/x/Applications"), appURL: app))
        XCTAssertTrue(GrantedFolder.covers(URL(fileURLWithPath: "/Users/x"), appURL: app))
        XCTAssertTrue(GrantedFolder.covers(URL(fileURLWithPath: "/Users/x/Applications/"), appURL: app))
        XCTAssertFalse(GrantedFolder.covers(URL(fileURLWithPath: "/Users/x/Applications/Sub"), appURL: app))
        XCTAssertFalse(GrantedFolder.covers(URL(fileURLWithPath: "/Users/x/Applications2"), appURL: app))
        XCTAssertFalse(GrantedFolder.covers(URL(fileURLWithPath: "/Users/y"), appURL: app))
        XCTAssertFalse(GrantedFolder.covers(URL(fileURLWithPath: "/Users/x/Applications/DavidNook.app"), appURL: app))
    }

    func testGrantedFolderResolvesSymlinks() throws {
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: installDir)
        XCTAssertTrue(GrantedFolder.covers(link, appURL: target))
    }
}

/// 測試用的 SHA-256（獨立實作路徑：用 shasum，不用被測的 SHA256Hasher）。
enum SHA256HexForTests {
    static func of(_ data: Data) -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString)")
        try? data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "256", file.path]
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return String(out.prefix(64))
    }
}
