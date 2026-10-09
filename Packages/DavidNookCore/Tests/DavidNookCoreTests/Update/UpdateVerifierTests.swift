import XCTest
@testable import DavidNookCore

/// 以腳本回答檢查結果的假檢查器；不碰真實簽章。
final class FakeInspector: AppBundleInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var _facts: [String: AppBundleFacts] = [:]
    var defaultFacts: AppBundleFacts
    var inspectedPaths: [String] { lock.withLock { _inspected } }
    private var _inspected: [String] = []

    init(_ facts: AppBundleFacts = .goodNext) { defaultFacts = facts }

    func set(_ facts: AppBundleFacts, forPathSuffix suffix: String) { lock.withLock { _facts[suffix] = facts } }

    func inspect(appAt url: URL) throws -> AppBundleFacts {
        lock.withLock {
            _inspected.append(url.path)
            for (suffix, facts) in _facts where url.path.hasSuffix(suffix) { return facts }
            return defaultFacts
        }
    }
}

extension AppBundleFacts {
    static let currentEntitlements: [String: EntitlementValue] = [
        "com.apple.security.app-sandbox": .bool(true),
        "com.apple.security.automation.apple-events": .bool(true),
        "com.apple.security.network.client": .bool(true),
        "com.apple.security.temporary-exception.apple-events": .array([.string("com.apple.Music")]),
    ]

    static var goodNext: AppBundleFacts {
        AppBundleFacts(
            bundleIdentifier: "io.github.davidkong3804.DavidNook",
            shortVersion: "0.2.0-beta.1",
            architectures: ["arm64"],
            signatureError: nil,
            hardenedRuntime: true,
            entitlements: currentEntitlements
        )
    }
}

final class UpdateVerifierTests: XCTestCase {
    private var tmp: URL!
    private let current = SemanticVersion("0.1.0-beta.1")!
    private let target = SemanticVersion("0.2.0-beta.1")!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("verifier-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func verifier(_ facts: AppBundleFacts = .goodNext) -> (UpdateVerifier, FakeInspector) {
        let inspector = FakeInspector(facts)
        return (UpdateVerifier(inspector: inspector), inspector)
    }

    private func verifyApp(_ facts: AppBundleFacts) throws {
        let (v, _) = verifier(facts)
        try v.verifyApp(at: tmp.appendingPathComponent("DavidNook.app"), expectedVersion: target,
                        currentVersion: current, currentEntitlements: AppBundleFacts.currentEntitlements)
    }

    private func assertFails(_ facts: AppBundleFacts, _ expected: UpdateVerificationFailure,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try verifyApp(facts), file: file, line: line) { error in
            XCTAssertEqual(error as? UpdateVerificationFailure, expected, file: file, line: line)
        }
    }

    // MARK: SHA-256

    func testSha256OfKnownContent() throws {
        let file = tmp.appendingPathComponent("a.bin")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try SHA256Hasher.hexDigest(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testSha256OfEmptyFile() throws {
        let file = tmp.appendingPathComponent("empty")
        try Data().write(to: file)
        XCTAssertEqual(try SHA256Hasher.hexDigest(of: file),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testArchiveWithMatchingHashPasses() throws {
        let file = tmp.appendingPathComponent("a.zip")
        try Data("abc".utf8).write(to: file)
        let (v, _) = verifier()
        XCTAssertNoThrow(try v.verifyArchive(at: file, expectedSHA256: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"))
    }

    func testArchiveWithDifferentHashIsRejected() throws {
        let file = tmp.appendingPathComponent("a.zip")
        try Data("abd".utf8).write(to: file)
        let (v, _) = verifier()
        XCTAssertThrowsError(try v.verifyArchive(at: file, expectedSHA256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")) {
            guard case UpdateVerificationFailure.checksumMismatch = $0 else { return XCTFail("\($0)") }
        }
    }

    func testMissingArchiveIsReportedAsUnreadable() {
        let (v, _) = verifier()
        XCTAssertThrowsError(try v.verifyArchive(at: tmp.appendingPathComponent("nope.zip"), expectedSHA256: String(repeating: "0", count: 64))) {
            guard case UpdateVerificationFailure.unreadable = $0 else { return XCTFail("\($0)") }
        }
    }

    // MARK: App 內容

    func testGoodAppPasses() {
        XCTAssertNoThrow(try verifyApp(.goodNext))
    }

    func testWrongBundleIdentifierIsRejected() {
        var f = AppBundleFacts.goodNext
        f.bundleIdentifier = "com.evil.DavidNook"
        assertFails(f, .unexpectedBundleIdentifier("com.evil.DavidNook"))
        f.bundleIdentifier = nil
        assertFails(f, .unexpectedBundleIdentifier(nil))
    }

    func testVersionMustEqualTagVersion() {
        var f = AppBundleFacts.goodNext
        f.shortVersion = "0.2.0"
        assertFails(f, .versionMismatch(expected: "0.2.0-beta.1", actual: "0.2.0"))
        f.shortVersion = nil
        assertFails(f, .versionMismatch(expected: "0.2.0-beta.1", actual: nil))
        f.shortVersion = "garbage"
        assertFails(f, .versionMismatch(expected: "0.2.0-beta.1", actual: "garbage"))
    }

    func testBuildMetadataDifferenceInVersionIsTolerated() {
        var f = AppBundleFacts.goodNext
        f.shortVersion = "0.2.0-beta.1+42"
        XCTAssertNoThrow(try verifyApp(f))
    }

    func testNotNewerThanCurrentIsRejected() {
        // 即使 tag 與 bundle 一致，也不接受相同或較舊版本（防降版）。
        let (v, _) = verifier()
        XCTAssertThrowsError(try v.verifyApp(at: tmp.appendingPathComponent("DavidNook.app"), expectedVersion: target,
                                            currentVersion: target, currentEntitlements: AppBundleFacts.currentEntitlements)) {
            XCTAssertEqual($0 as? UpdateVerificationFailure, .notNewer(candidate: "0.2.0-beta.1", current: "0.2.0-beta.1"))
        }
        XCTAssertThrowsError(try v.verifyApp(at: tmp.appendingPathComponent("DavidNook.app"), expectedVersion: target,
                                            currentVersion: SemanticVersion("0.2.0")!, currentEntitlements: AppBundleFacts.currentEntitlements)) {
            XCTAssertEqual($0 as? UpdateVerificationFailure, .notNewer(candidate: "0.2.0-beta.1", current: "0.2.0"))
        }
    }

    func testMissingArm64IsRejected() {
        var f = AppBundleFacts.goodNext
        f.architectures = ["x86_64"]
        assertFails(f, .missingArm64)
        f.architectures = []
        assertFails(f, .missingArm64)
    }

    func testFatBinaryWithArm64Passes() {
        var f = AppBundleFacts.goodNext
        f.architectures = ["x86_64", "arm64"]
        XCTAssertNoThrow(try verifyApp(f))
    }

    func testInvalidSignatureIsRejectedWithReason() {
        var f = AppBundleFacts.goodNext
        f.signatureError = "a sealed resource is missing or invalid"
        assertFails(f, .invalidSignature("a sealed resource is missing or invalid"))
    }

    func testMissingHardenedRuntimeIsRejected() {
        var f = AppBundleFacts.goodNext
        f.hardenedRuntime = false
        assertFails(f, .hardenedRuntimeMissing)
    }

    // MARK: Entitlements

    func testIdenticalEntitlementsPass() {
        XCTAssertNoThrow(try verifyApp(.goodNext))
    }

    func testFewerEntitlementsPass() {
        var f = AppBundleFacts.goodNext
        f.entitlements.removeValue(forKey: "com.apple.security.automation.apple-events")
        XCTAssertNoThrow(try verifyApp(f))
    }

    func testOnlyAllowedAdditionIsUserSelectedReadWrite() {
        var f = AppBundleFacts.goodNext
        f.entitlements["com.apple.security.files.user-selected.read-write"] = .bool(true)
        XCTAssertNoThrow(try verifyApp(f))
    }

    func testAddedDisableLibraryValidationIsRejected() {
        var f = AppBundleFacts.goodNext
        f.entitlements["com.apple.security.cs.disable-library-validation"] = .bool(true)
        assertFails(f, .entitlementsExpanded(["com.apple.security.cs.disable-library-validation"]))
    }

    func testOtherFileAccessEntitlementsAreRejected() {
        var f = AppBundleFacts.goodNext
        f.entitlements["com.apple.security.files.user-selected.read-write"] = .bool(true)
        f.entitlements["com.apple.security.files.downloads.read-write"] = .bool(true)
        f.entitlements["com.apple.security.files.bookmarks.app-scope"] = .bool(true)
        assertFails(f, .entitlementsExpanded(["com.apple.security.files.bookmarks.app-scope", "com.apple.security.files.downloads.read-write"]))
    }

    func testAllowedAdditionMustBeTrue() {
        var f = AppBundleFacts.goodNext
        f.entitlements["com.apple.security.files.user-selected.read-write"] = .string("yes")
        assertFails(f, .entitlementsExpanded(["com.apple.security.files.user-selected.read-write"]))
    }

    func testDisabledSandboxIsRejected() {
        var f = AppBundleFacts.goodNext
        f.entitlements["com.apple.security.app-sandbox"] = .bool(false)
        assertFails(f, .sandboxMissing)
        f.entitlements.removeValue(forKey: "com.apple.security.app-sandbox")
        assertFails(f, .sandboxMissing)
    }

    func testBoolValueFlippedToTrueIsExpansion() {
        let current: [String: EntitlementValue] = ["com.apple.security.app-sandbox": .bool(true), "x": .bool(false)]
        var next = AppBundleFacts.goodNext
        next.entitlements = ["com.apple.security.app-sandbox": .bool(true), "x": .bool(true)]
        let (v, _) = verifier(next)
        XCTAssertThrowsError(try v.verifyApp(at: tmp, expectedVersion: target, currentVersion: current0, currentEntitlements: current)) {
            XCTAssertEqual($0 as? UpdateVerificationFailure, .entitlementsExpanded(["x"]))
        }
    }

    private var current0: SemanticVersion { current }

    func testTemporaryExceptionArrayMayNotGainEntries() {
        var f = AppBundleFacts.goodNext
        f.entitlements["com.apple.security.temporary-exception.apple-events"] = .array([.string("com.apple.Music"), .string("com.apple.finder")])
        assertFails(f, .entitlementsExpanded(["com.apple.security.temporary-exception.apple-events"]))
    }

    func testTemporaryExceptionArrayMayShrink() {
        var f = AppBundleFacts.goodNext
        f.entitlements["com.apple.security.temporary-exception.apple-events"] = .array([])
        XCTAssertNoThrow(try verifyApp(f))
    }

    func testStringEntitlementMustMatchExactly() {
        let current: [String: EntitlementValue] = ["com.apple.security.app-sandbox": .bool(true), "k": .string("a")]
        var next = AppBundleFacts.goodNext
        next.entitlements = ["com.apple.security.app-sandbox": .bool(true), "k": .string("b")]
        let (v, _) = verifier(next)
        XCTAssertThrowsError(try v.verifyApp(at: tmp, expectedVersion: target, currentVersion: current0, currentEntitlements: current)) {
            XCTAssertEqual($0 as? UpdateVerificationFailure, .entitlementsExpanded(["k"]))
        }
    }

    // MARK: 失敗理由

    func testFailuresHaveHumanReadableReasons() {
        let all: [UpdateVerificationFailure] = [
            .checksumMismatch(expected: "a", actual: "b"), .unexpectedBundleIdentifier("x"), .versionMismatch(expected: "1", actual: nil),
            .notNewer(candidate: "1", current: "2"), .missingArm64, .invalidSignature("r"), .hardenedRuntimeMissing,
            .entitlementsExpanded(["k"]), .sandboxMissing, .unreadable("r"),
        ]
        for failure in all { XCTAssertFalse(failure.reason.isEmpty) }
        XCTAssertTrue(UpdateVerificationFailure.invalidSignature("seal broken").reason.contains("seal broken"))
    }

    // MARK: 真實檢查器（對暫時用 codesign 簽出的小 bundle；無法簽章的環境會略過）

    func testRealInspectorReadsAdHocSignedBundle() throws {
        let app = tmp.appendingPathComponent("Probe.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "io.github.davidkong3804.DavidNookProbeFixture", "CFBundleExecutable": "probe",
            "CFBundleShortVersionString": "9.9.9-test.1", "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
        ]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macos.appendingPathComponent("probe"))
        let ents = tmp.appendingPathComponent("e.plist")
        try (["com.apple.security.network.client": true] as NSDictionary).write(to: ents)

        func codesign(_ args: [String]) throws -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            p.arguments = args
            p.standardError = Pipe(); p.standardOutput = Pipe()
            try p.run(); p.waitUntilExit()
            return p.terminationStatus == 0
        }
        guard try codesign(["--force", "--sign", "-", "--options", "runtime", "--entitlements", ents.path, app.path]) else {
            throw XCTSkip("此環境無法 ad-hoc 簽章")
        }

        let facts = try SecurityAppBundleInspector().inspect(appAt: app)
        XCTAssertEqual(facts.bundleIdentifier, "io.github.davidkong3804.DavidNookProbeFixture")
        XCTAssertEqual(facts.shortVersion, "9.9.9-test.1")
        XCTAssertNil(facts.signatureError, "剛簽好的 bundle 應通過 strict 驗證：\(facts.signatureError ?? "")")
        XCTAssertTrue(facts.hardenedRuntime)
        XCTAssertEqual(facts.entitlements["com.apple.security.network.client"], .bool(true))
        XCTAssertFalse(facts.architectures.isEmpty)

        // 竄改簽章內容後必須驗證失敗。
        try Data("tampered".utf8).write(to: app.appendingPathComponent("Contents/Resources-extra.txt"))
        let after = try SecurityAppBundleInspector().inspect(appAt: app)
        XCTAssertNotNil(after.signatureError, "多出未簽章檔案後 strict 驗證應失敗")
    }
}
