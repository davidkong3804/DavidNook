import XCTest
@testable import DavidNookCore

// 所有 HTTP 一律走 StubTransport，測試不會連外網。

private let hashA = String(repeating: "a", count: 64)
private let hashB = String(repeating: "b", count: 64)

private func asset(_ name: String, tag: String, digest: String? = nil, state: String = "uploaded", size: Int = 4_000_000,
                   url: String? = nil) -> [String: Any] {
    var a: [String: Any] = [
        "name": name, "state": state, "size": size, "content_type": "application/zip",
        "browser_download_url": url ?? "https://github.com/davidkong3804/DavidNook/releases/download/\(tag)/\(name)",
    ]
    if let digest { a["digest"] = digest }
    return a
}

private func fakeRelease(
    tag: String, prerelease: Bool = true, draft: Bool = false, body: String? = nil,
    assets: [[String: Any]]? = nil, hashInBody: String? = nil, name: String? = nil
) -> [String: Any] {
    let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    var text = body ?? "說明文字"
    if let hashInBody { text += "\n- SHA-256：`\(hashInBody)`" }
    return [
        "tag_name": tag, "name": name ?? tag, "draft": draft, "prerelease": prerelease, "body": text,
        "html_url": "https://github.com/davidkong3804/DavidNook/releases/tag/\(tag)",
        "assets": assets ?? [asset("DavidNook-\(ver)-arm64.zip", tag: tag)],
    ]
}

private func listing(_ releases: [[String: Any]]) -> String { jsonString(releases) }

private func shaFileStep(_ content: String) -> StubTransport.Step {
    .response(HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/plain"], body: Data(content.utf8)))
}

final class GitHubReleaseClientTests: XCTestCase {
    private let current = SemanticVersion("0.1.0-beta.1")!

    private func client(_ transport: StubTransport, version: String = "0.1.0-beta.1", prereleases: Bool = true) -> GitHubReleaseClient {
        GitHubReleaseClient(transport: transport, appVersion: version, includePrereleases: prereleases)
    }

    // MARK: 請求本身

    func testRequestIsPlainGetToReleasesListWithUserAgentOnly() async throws {
        let transport = StubTransport(steps: [.ok(listing([]))])
        _ = try await client(transport, version: "0.1.0-beta.1").check(current: current)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/davidkong3804/DavidNook/releases?per_page=10")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "DavidNook/0.1.0-beta.1")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "不帶 token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.httpBody)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }), ["user-agent", "accept"],
                       "除 User-Agent 與 Accept 外不送任何標頭")
    }

    // MARK: 版本挑選

    func testPicksHighestVersionIncludingPrereleaseNotListOrder() async throws {
        let body = listing([
            fakeRelease(tag: "v0.1.0-beta.1", hashInBody: hashA),
            fakeRelease(tag: "v0.1.0-beta.2", hashInBody: hashB),
            fakeRelease(tag: "v0.1.0-beta.10", hashInBody: hashB),
            fakeRelease(tag: "v0.1.0-alpha.9", hashInBody: hashA),
        ])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        guard case .available(let c) = result else { return XCTFail("應有新版：\(result)") }
        XCTAssertEqual(c.version, SemanticVersion("0.1.0-beta.10"))
        XCTAssertEqual(c.tag, "v0.1.0-beta.10")
    }

    func testStableReleaseBeatsItsBetas() async throws {
        let body = listing([
            fakeRelease(tag: "v0.1.0-beta.2", hashInBody: hashA),
            fakeRelease(tag: "v0.1.0", prerelease: false, hashInBody: hashB),
        ])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.version, SemanticVersion("0.1.0"))
        XCTAssertEqual(c.sha256, hashB)
        XCTAssertFalse(c.isPrerelease)
    }

    func testUpToDateWhenLatestEqualsCurrent() async throws {
        let body = listing([fakeRelease(tag: "v0.1.0-beta.1", hashInBody: hashA)])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        XCTAssertEqual(result, .upToDate(latest: SemanticVersion("0.1.0-beta.1")))
    }

    func testNeverOffersDowngrade() async throws {
        let body = listing([fakeRelease(tag: "v0.0.9", hashInBody: hashA), fakeRelease(tag: "v0.1.0-alpha.1", hashInBody: hashA)])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        XCTAssertEqual(result, .upToDate(latest: SemanticVersion("0.1.0-alpha.1")))
    }

    func testEmptyListIsUpToDate() async throws {
        let result = try await client(StubTransport(steps: [.ok("[]")])).check(current: current)
        XCTAssertEqual(result, .upToDate(latest: nil))
    }

    func testDraftsAndUnparseableTagsAreIgnored() async throws {
        let body = listing([
            fakeRelease(tag: "v9.9.9", draft: true, hashInBody: hashA),
            fakeRelease(tag: "nightly", hashInBody: hashA),
            fakeRelease(tag: "v0.1.0-beta.2", hashInBody: hashB),
        ])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.tag, "v0.1.0-beta.2")
    }

    func testExcludingPrereleasesSkipsThem() async throws {
        let body = listing([fakeRelease(tag: "v0.2.0-beta.1", hashInBody: hashA)])
        let result = try await client(StubTransport(steps: [.ok(body)]), version: "0.1.0", prereleases: false)
            .check(current: SemanticVersion("0.1.0")!)
        XCTAssertEqual(result, .upToDate(latest: nil))
    }

    // MARK: Asset 與 SHA-256

    func testSelectsArm64ZipByExactName() async throws {
        let assets = [
            asset("DavidNook-0.1.0-beta.2-x86_64.zip", tag: "v0.1.0-beta.2"),
            asset("DavidNook-0.1.0-beta.2-arm64.zip.sig", tag: "v0.1.0-beta.2"),
            asset("Source.zip", tag: "v0.1.0-beta.2"),
            asset("DavidNook-0.1.0-beta.2-arm64.zip", tag: "v0.1.0-beta.2"),
        ]
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", assets: assets, hashInBody: hashA)])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.archiveName, "DavidNook-0.1.0-beta.2-arm64.zip")
        XCTAssertEqual(c.archiveURL.absoluteString,
                       "https://github.com/davidkong3804/DavidNook/releases/download/v0.1.0-beta.2/DavidNook-0.1.0-beta.2-arm64.zip")
        XCTAssertEqual(c.archiveSize, 4_000_000)
    }

    func testZipForOtherVersionIsNotAccepted() async throws {
        let assets = [asset("DavidNook-0.1.0-beta.1-arm64.zip", tag: "v0.1.0-beta.2")]
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", assets: assets, hashInBody: hashA)])
        await assertThrows(UpdateCheckError.missingArchive(tag: "v0.1.0-beta.2"), StubTransport(steps: [.ok(body)]))
    }

    func testMissingArm64ZipIsRejected() async throws {
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", assets: [], hashInBody: hashA)])
        await assertThrows(UpdateCheckError.missingArchive(tag: "v0.1.0-beta.2"), StubTransport(steps: [.ok(body)]))
    }

    func testAssetNotFullyUploadedIsRejected() async throws {
        let assets = [asset("DavidNook-0.1.0-beta.2-arm64.zip", tag: "v0.1.0-beta.2", state: "starter")]
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", assets: assets, hashInBody: hashA)])
        await assertThrows(UpdateCheckError.missingArchive(tag: "v0.1.0-beta.2"), StubTransport(steps: [.ok(body)]))
    }

    func testAssetWithDisallowedHostIsRejected() async throws {
        let assets = [asset("DavidNook-0.1.0-beta.2-arm64.zip", tag: "v0.1.0-beta.2", url: "https://evil.example/DavidNook-0.1.0-beta.2-arm64.zip")]
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", assets: assets, hashInBody: hashA)])
        await assertThrows(UpdateCheckError.disallowedURL("https://evil.example/DavidNook-0.1.0-beta.2-arm64.zip"),
                           StubTransport(steps: [.ok(body)]))
    }

    func testPrefersSha256AssetOverBody() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag), asset(name + ".sha256", tag: tag, size: 100)]
        let body = listing([fakeRelease(tag: tag, assets: assets, hashInBody: hashA)])
        let transport = StubTransport(steps: [.ok(body), shaFileStep("\(hashA.uppercased())  \(name)\n")])
        let result = try await client(transport).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.sha256, hashA, "雜湊一律轉小寫")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[1].url?.lastPathComponent, name + ".sha256")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "User-Agent"), "DavidNook/0.1.0-beta.1")
        XCTAssertNil(transport.requests[1].value(forHTTPHeaderField: "Authorization"))
    }

    func testSha256AssetAloneIsEnough() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag), asset(name + ".sha256", tag: tag)]
        let body = listing([fakeRelease(tag: tag, assets: assets)])
        let transport = StubTransport(steps: [.ok(body), shaFileStep("\(hashB)  \(name)")])
        let result = try await client(transport).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.sha256, hashB)
    }

    func testSha256AssetBinaryModeMarkerIsAccepted() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag), asset(name + ".sha256", tag: tag)]
        let transport = StubTransport(steps: [.ok(listing([fakeRelease(tag: tag, assets: assets)])), shaFileStep("\(hashB) *\(name)")])
        let result = try await client(transport).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.sha256, hashB)
    }

    func testSha256AssetNamingAnotherFileIsRejected() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag), asset(name + ".sha256", tag: tag)]
        let transport = StubTransport(steps: [.ok(listing([fakeRelease(tag: tag, assets: assets, hashInBody: hashB)])),
                                              shaFileStep("\(hashB)  other.zip")])
        await assertThrows(UpdateCheckError.invalidChecksumFile(tag: tag), transport)
    }

    func testMalformedSha256AssetIsRejectedNotSilentlyFallingBack() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag), asset(name + ".sha256", tag: tag)]
        let transport = StubTransport(steps: [.ok(listing([fakeRelease(tag: tag, assets: assets, hashInBody: hashB)])),
                                              shaFileStep("not a hash")])
        await assertThrows(UpdateCheckError.invalidChecksumFile(tag: tag), transport)
    }

    func testFallsBackToBodyWhenNoSha256Asset() async throws {
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", hashInBody: hashA.uppercased())])
        let transport = StubTransport(steps: [.ok(body)])
        let result = try await client(transport).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.sha256, hashA)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testBodyHashAcceptsAsciiColonToo() async throws {
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", body: "SHA-256: `\(hashA)`")])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.sha256, hashA)
    }

    func testNoChecksumAnywhereRefusesUpdate() async throws {
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2")])
        await assertThrows(UpdateCheckError.missingChecksum(tag: "v0.1.0-beta.2"), StubTransport(steps: [.ok(body)]))
    }

    func testBodyWithWrongLengthHashRefusesUpdate() async throws {
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", body: "SHA-256：`abc123`")])
        await assertThrows(UpdateCheckError.missingChecksum(tag: "v0.1.0-beta.2"), StubTransport(steps: [.ok(body)]))
    }

    func testConflictingHashesInBodyAreRejected() async throws {
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", body: "SHA-256：`\(hashA)`\nSHA-256：`\(hashB)`")])
        await assertThrows(UpdateCheckError.checksumConflict(tag: "v0.1.0-beta.2"), StubTransport(steps: [.ok(body)]))
    }

    func testSha256AssetDisagreeingWithBodyIsRejected() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag), asset(name + ".sha256", tag: tag)]
        let transport = StubTransport(steps: [.ok(listing([fakeRelease(tag: tag, assets: assets, hashInBody: hashA)])),
                                              shaFileStep("\(hashB)  \(name)")])
        await assertThrows(UpdateCheckError.checksumConflict(tag: tag), transport)
    }

    func testGithubDigestDisagreeingWithPublishedHashIsRejected() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag, digest: "sha256:\(hashB)")]
        let body = listing([fakeRelease(tag: tag, assets: assets, hashInBody: hashA)])
        await assertThrows(UpdateCheckError.checksumConflict(tag: tag), StubTransport(steps: [.ok(body)]))
    }

    func testGithubDigestAgreeingIsFine() async throws {
        let tag = "v0.1.0-beta.2"
        let name = "DavidNook-0.1.0-beta.2-arm64.zip"
        let assets = [asset(name, tag: tag, digest: "sha256:\(hashA)")]
        let result = try await client(StubTransport(steps: [.ok(listing([fakeRelease(tag: tag, assets: assets, hashInBody: hashA)]))])).check(current: current)
        guard case .available = result else { return XCTFail("\(result)") }
    }

    // MARK: 說明文字

    func testNotesAreSanitizedAndTruncated() async throws {
        let long = "<script>x</script>[連結](https://evil.example) " + String(repeating: "很長", count: 2000)
        let body = listing([fakeRelease(tag: "v0.1.0-beta.2", body: long, hashInBody: hashA)])
        let result = try await client(StubTransport(steps: [.ok(body)])).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(c.notes.contains("<script"))
        XCTAssertFalse(c.notes.contains("evil.example"))
        XCTAssertLessThanOrEqual(c.notes.count, GitHubReleaseClient.maxNotesLength)
        XCTAssertEqual(c.releasePageURL.absoluteString, "https://github.com/davidkong3804/DavidNook/releases/tag/v0.1.0-beta.2")
    }

    func testReleasePageURLOutsideAllowlistFallsBackToCanonicalTagPage() async throws {
        var r = fakeRelease(tag: "v0.1.0-beta.2", hashInBody: hashA)
        r["html_url"] = "https://evil.example/phish"
        let result = try await client(StubTransport(steps: [.ok(listing([r]))])).check(current: current)
        guard case .available(let c) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(c.releasePageURL.absoluteString, "https://github.com/davidkong3804/DavidNook/releases/tag/v0.1.0-beta.2")
    }

    // MARK: 錯誤

    func testHttp403RateLimitIsReported() async throws {
        let step = StubTransport.Step.response(HTTPResponse(statusCode: 403, headers: ["X-RateLimit-Remaining": "0"], body: Data()))
        await assertThrows(UpdateCheckError.rateLimited, StubTransport(steps: [step]))
    }

    func testHttpErrorStatusIsReported() async throws {
        await assertThrows(UpdateCheckError.httpStatus(500), StubTransport(steps: [.status(500)]))
    }

    func testTransportFailureIsReported() async throws {
        let transport = StubTransport(steps: [.failure(URLError(.notConnectedToInternet))])
        do {
            _ = try await client(transport).check(current: current)
            XCTFail("應拋錯")
        } catch let error as UpdateCheckError {
            guard case .network = error else { return XCTFail("\(error)") }
        }
    }

    func testMalformedJsonIsReported() async throws {
        await assertThrows(UpdateCheckError.malformedResponse, StubTransport(steps: [.ok("{not json")]))
        await assertThrows(UpdateCheckError.malformedResponse, StubTransport(steps: [.ok(#"{"message":"x"}"#)]))
    }

    func testOversizedResponseIsRejected() async throws {
        let huge = String(repeating: " ", count: GitHubReleaseClient.maxResponseBytes + 1)
        await assertThrows(UpdateCheckError.malformedResponse, StubTransport(steps: [.ok("[]" + huge)]))
    }

    private func assertThrows(_ expected: UpdateCheckError, _ transport: StubTransport,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let r = try await client(transport).check(current: current)
            XCTFail("應拋 \(expected)，卻得到 \(r)", file: file, line: line)
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("非預期錯誤 \(error)", file: file, line: line)
        }
    }
}
