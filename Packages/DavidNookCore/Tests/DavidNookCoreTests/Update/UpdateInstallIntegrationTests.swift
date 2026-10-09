import XCTest
@testable import DavidNookCore

/// 整條流程用「真的」簽章檢查、ditto 解壓與 replaceItemAt，對象是暫時用 ad-hoc 簽出來的小 App（temp 目錄內，
/// 不碰任何已安裝的 App）。無法簽章的環境會略過。只有下載是假的（把本機 zip 複製過去）。
private final class CopyDownloader: UpdateDownloading, @unchecked Sendable {
    let source: URL
    init(source: URL) { self.source = source }
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.copyItem(at: source, to: destination)
        progress(1)
    }
}

final class UpdateInstallIntegrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("install-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func run(_ path: String, _ args: [String]) throws -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardError = Pipe(); p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// 在 `dir` 建一個 DavidNook.app（ad-hoc＋Hardened Runtime＋給定 entitlements）。
    private func makeApp(in dir: URL, version: String, entitlements: [String: Any], bundleID: String = UpdateVerifier.expectedBundleIdentifier) throws -> URL {
        let app = dir.appendingPathComponent("DavidNook.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleExecutable": "DavidNook", "CFBundleShortVersionString": version,
            "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
        ]
        try (info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macos.appendingPathComponent("DavidNook"))
        let ents = root.appendingPathComponent("ents-\(UUID().uuidString.prefix(4)).plist")
        try (entitlements as NSDictionary).write(to: ents)
        guard try run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", "--entitlements", ents.path, app.path]) else {
            throw XCTSkip("此環境無法 ad-hoc 簽章")
        }
        return app
    }

    private func zip(_ app: URL, to zip: URL) throws {
        XCTAssertTrue(try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]))
    }

    private let baseEntitlements: [String: Any] = [
        "com.apple.security.app-sandbox": true, "com.apple.security.network.client": true,
    ]

    private struct Fixture {
        var target: URL
        var installDir: URL
        var zipURL: URL
        var candidate: UpdateCandidate
        var work: URL
    }

    private func fixture(newVersion: String = "0.2.0-beta.1", newEntitlements: [String: Any]? = nil, newBundleID: String = UpdateVerifier.expectedBundleIdentifier,
                         tamperAfterZip: Bool = false) throws -> Fixture {
        let installDir = root.appendingPathComponent("Apps")
        let oldDir = installDir
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        let target = try makeApp(in: oldDir, version: "0.1.0-beta.1", entitlements: baseEntitlements)

        let newDir = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        let newApp = try makeApp(in: newDir, version: newVersion, entitlements: newEntitlements ?? baseEntitlements, bundleID: newBundleID)
        let zipURL = root.appendingPathComponent("DavidNook-\(newVersion)-arm64.zip")
        try zip(newApp, to: zipURL)
        let hash = try SHA256Hasher.hexDigest(of: zipURL)
        if tamperAfterZip { // 下載途中被改：雜湊就是舊的
            let handle = try FileHandle(forWritingTo: zipURL)
            try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        }
        let work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let version = SemanticVersion(newVersion)!
        let candidate = UpdateCandidate(
            version: version, tag: "v\(newVersion)", title: "t", isPrerelease: true,
            releasePageURL: URL(string: "https://github.com/davidkong3804/DavidNook/releases/tag/v\(newVersion)")!,
            archiveURL: URL(string: "https://github.com/davidkong3804/DavidNook/releases/download/v\(newVersion)/DavidNook-\(newVersion)-arm64.zip")!,
            archiveName: "DavidNook-\(newVersion)-arm64.zip", archiveSize: nil, sha256: hash, notes: ""
        )
        return Fixture(target: target, installDir: installDir, zipURL: zipURL, candidate: candidate, work: work)
    }

    private func install(_ f: Fixture) async throws -> URL {
        let inspector = SecurityAppBundleInspector()
        let current = try inspector.inspect(appAt: f.target)
        let installer = UpdateInstaller(downloader: CopyDownloader(source: f.zipURL), extractor: DittoArchiveExtractor(),
                                        verifier: UpdateVerifier(inspector: inspector))
        let request = UpdateInstallRequest(candidate: f.candidate, currentVersion: SemanticVersion(current.shortVersion!)!,
                                           currentEntitlements: current.entitlements, targetAppURL: f.target, workDirectory: f.work)
        return try await installer.run(request) { _ in }
    }

    private func version(of app: URL) throws -> String? {
        try SecurityAppBundleInspector().inspect(appAt: app).shortVersion
    }

    func testRealInstallReplacesAndKeepsSignedBackup() async throws {
        let f = try fixture()
        _ = try await install(f)
        XCTAssertEqual(try version(of: f.target), "0.2.0-beta.1")
        let backup = f.installDir.appendingPathComponent("DavidNook.app.previous")
        XCTAssertEqual(try version(of: backup), "0.1.0-beta.1")
        XCTAssertNil(try SecurityAppBundleInspector().inspect(appAt: f.target).signatureError, "安裝後的新版簽章仍然有效")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.installDir.path).sorted(), ["DavidNook.app", "DavidNook.app.previous"])
    }

    func testRealInstallAcceptsOnlyTheUserSelectedAddition() async throws {
        var ents = baseEntitlements
        ents["com.apple.security.files.user-selected.read-write"] = true
        let f = try fixture(newEntitlements: ents)
        _ = try await install(f)
        XCTAssertEqual(try version(of: f.target), "0.2.0-beta.1")
    }

    func testRealInstallRefusesExpandedEntitlementsAndKeepsOldApp() async throws {
        var ents = baseEntitlements
        ents["com.apple.security.cs.disable-library-validation"] = true
        let f = try fixture(newEntitlements: ents)
        do { _ = try await install(f); XCTFail("應拒絕") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .verification(.entitlementsExpanded(["com.apple.security.cs.disable-library-validation"])))
        }
        XCTAssertEqual(try version(of: f.target), "0.1.0-beta.1")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.installDir.path), ["DavidNook.app"])
    }

    func testRealInstallRefusesWrongBundleIdentifier() async throws {
        let f = try fixture(newBundleID: "com.evil.DavidNook")
        do { _ = try await install(f); XCTFail("應拒絕") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .verification(.unexpectedBundleIdentifier("com.evil.DavidNook")))
        }
        XCTAssertEqual(try version(of: f.target), "0.1.0-beta.1")
    }

    func testRealInstallRefusesTamperedDownload() async throws {
        let f = try fixture(tamperAfterZip: true)
        do { _ = try await install(f); XCTFail("應拒絕") } catch let error as UpdateInstallError {
            guard case .verification(.checksumMismatch) = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try version(of: f.target), "0.1.0-beta.1")
    }

    func testRealInstallRefusesVersionNotMatchingTag() async throws {
        // bundle 寫 0.2.0，但 release 標的是 0.2.0-beta.1（例如忘了改 MARKETING_VERSION）。
        let f = try fixture(newVersion: "0.2.0")
        var mismatched = f
        mismatched.candidate = UpdateCandidate(
            version: SemanticVersion("0.2.0-beta.1")!, tag: "v0.2.0-beta.1", title: "t", isPrerelease: true,
            releasePageURL: f.candidate.releasePageURL, archiveURL: f.candidate.archiveURL, archiveName: f.candidate.archiveName,
            archiveSize: nil, sha256: f.candidate.sha256, notes: "")
        do { _ = try await install(mismatched); XCTFail("應拒絕") } catch let error as UpdateInstallError {
            XCTAssertEqual(error, .verification(.versionMismatch(expected: "0.2.0-beta.1", actual: "0.2.0")))
        }
        XCTAssertEqual(try version(of: f.target), "0.1.0-beta.1")
    }
}
