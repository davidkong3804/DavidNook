import XCTest
@testable import DavidNookCore

final class UpdateHostPolicyTests: XCTestCase {
    private func allowed(_ s: String) -> Bool { UpdateHostPolicy.isAllowed(URL(string: s)!) }

    func testAllowsExactHosts() {
        XCTAssertTrue(allowed("https://api.github.com/repos/davidkong3804/DavidNook/releases?per_page=10"))
        XCTAssertTrue(allowed("https://github.com/davidkong3804/DavidNook/releases/download/v1/x.zip"))
        XCTAssertTrue(allowed("https://objects.githubusercontent.com/github-production-release-asset/x"))
        XCTAssertTrue(allowed("https://release-assets.githubusercontent.com/github-production-release-asset/x"))
    }

    func testAllowsGithubusercontentSubdomains() {
        XCTAssertTrue(allowed("https://something.githubusercontent.com/a"))
        XCTAssertTrue(allowed("https://a.b.githubusercontent.com/a"))
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertTrue(allowed("https://API.GitHub.com/x"))
    }

    func testRejectsHttp() {
        XCTAssertFalse(allowed("http://api.github.com/x"))
        XCTAssertFalse(allowed("http://github.com/x"))
    }

    func testRejectsOtherSchemes() {
        XCTAssertFalse(allowed("ftp://github.com/x"))
        XCTAssertFalse(allowed("file:///etc/passwd"))
        XCTAssertFalse(allowed("data:text/plain,hi"))
    }

    func testRejectsLookalikeHosts() {
        XCTAssertFalse(allowed("https://evilgithubusercontent.com/x"))
        XCTAssertFalse(allowed("https://githubusercontent.com/x"), "裸網域不在白名單（只有 *.githubusercontent.com）")
        XCTAssertFalse(allowed("https://github.com.evil.example/x"))
        XCTAssertFalse(allowed("https://api.github.com.evil.example/x"))
        XCTAssertFalse(allowed("https://evil.example/github.com"))
        XCTAssertFalse(allowed("https://raw.githubusercontent.com.evil.example/x"))
        XCTAssertFalse(allowed("https://gist.github.com/x"), "github.com 的子網域不在白名單")
        XCTAssertFalse(allowed("https://example.com/x"))
    }

    func testRejectsUserInfoAndCustomPorts() {
        XCTAssertFalse(allowed("https://github.com@evil.example/x"))
        XCTAssertFalse(allowed("https://user:pw@github.com/x"))
        XCTAssertFalse(allowed("https://github.com:8443/x"))
        XCTAssertTrue(allowed("https://github.com:443/x"))
    }

    func testRedirectDecisionUsesSamePolicy() {
        XCTAssertTrue(UpdateHostPolicy.allowsRedirect(to: URL(string: "https://release-assets.githubusercontent.com/a")!))
        XCTAssertFalse(UpdateHostPolicy.allowsRedirect(to: URL(string: "https://evil.example/a")!))
        XCTAssertFalse(UpdateHostPolicy.allowsRedirect(to: URL(string: "http://objects.githubusercontent.com/a")!))
    }
}
