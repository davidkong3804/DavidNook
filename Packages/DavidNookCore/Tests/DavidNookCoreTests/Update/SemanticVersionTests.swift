import XCTest
@testable import DavidNookCore

// SemVer 2.0.0 規範：https://semver.org/spec/v2.0.0.html（第 2、9、10、11 條）。
final class SemanticVersionTests: XCTestCase {
    private func v(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> SemanticVersion {
        guard let version = SemanticVersion(s) else {
            XCTFail("應能解析 \(s)", file: file, line: line)
            return SemanticVersion(major: 0, minor: 0, patch: 0)
        }
        return version
    }

    func testParsesPlainVersion() {
        let version = v("1.2.3")
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 3)
        XCTAssertTrue(version.prerelease.isEmpty)
        XCTAssertFalse(version.isPrerelease)
    }

    func testAcceptsLeadingVPrefix() {
        XCTAssertEqual(v("v0.1.0-beta.1"), v("0.1.0-beta.1"))
        XCTAssertEqual(v("V1.0.0"), v("1.0.0"))
    }

    func testParsesPrereleaseIdentifiers() {
        let version = v("0.1.0-beta.1")
        XCTAssertEqual(version.prerelease, ["beta", "1"])
        XCTAssertTrue(version.isPrerelease)
    }

    func testDescriptionIsCanonicalWithoutPrefix() {
        XCTAssertEqual(v("v0.1.0-beta.2").description, "0.1.0-beta.2")
        XCTAssertEqual(v("1.0.0").description, "1.0.0")
    }

    func testBuildMetadataIsIgnoredForPrecedenceAndEquality() {
        XCTAssertEqual(v("1.0.0+5"), v("1.0.0+9"))
        XCTAssertEqual(v("1.0.0+5").description, "1.0.0")
        XCTAssertFalse(v("1.0.0+9").isStrictlyNewer(than: v("1.0.0+5")))
    }

    func testRejectsMalformedStrings() {
        for bad in ["", "v", "1", "1.2", "1.2.3.4", "a.b.c", "1.2.x", "01.2.3", "1.02.3", "1.2.03",
                    "1.2.3-", "1.2.3-01", "1.2.3-beta..1", "1.2.3-be ta", "1.2.3-é", "-1.2.3", "1.2.3+",
                    " 1.2.3", "1.2.3 ", "1.2.3-beta+", "v v1.2.3", "99999999999999999999.0.0"] {
            XCTAssertNil(SemanticVersion(bad), "不該解析成功：\(bad.debugDescription)")
        }
    }

    func testNumericPrereleaseIdentifierZeroIsAllowedButNotLeadingZeros() {
        XCTAssertNotNil(SemanticVersion("1.0.0-0"))
        XCTAssertNotNil(SemanticVersion("1.0.0-alpha.0"))
        XCTAssertNil(SemanticVersion("1.0.0-alpha.00"))
        XCTAssertNotNil(SemanticVersion("1.0.0-0abc")) // 含字母的識別字可以以 0 開頭
    }

    func testCoreNumbersCompareNumericallyNotLexically() {
        XCTAssertLessThan(v("1.9.0"), v("1.10.0"))
        XCTAssertLessThan(v("0.9.9"), v("0.10.0"))
        XCTAssertLessThan(v("1.2.3"), v("1.2.4"))
        XCTAssertLessThan(v("1.2.3"), v("2.0.0"))
    }

    // 規範第 11 條的範例排序：
    // 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
    func testSpecPrecedenceChain() {
        let chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                     "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"].map { v($0) }
        for i in 0..<chain.count - 1 {
            XCTAssertLessThan(chain[i], chain[i + 1], "\(chain[i]) 應小於 \(chain[i + 1])")
            XCTAssertGreaterThan(chain[i + 1], chain[i])
        }
        XCTAssertEqual(chain.shuffled().sorted(), chain)
    }

    func testProjectReleaseOrdering() {
        XCTAssertLessThan(v("0.1.0-beta.1"), v("0.1.0-beta.2"))
        XCTAssertLessThan(v("0.1.0-beta.2"), v("0.1.0"))
        XCTAssertLessThan(v("0.1.0-beta.9"), v("0.1.0-beta.10")) // 數字識別字依數值比
        XCTAssertLessThan(v("0.1.0"), v("0.1.1-beta.1"))
    }

    func testNumericIdentifiersRankBelowAlphanumeric() {
        XCTAssertLessThan(v("1.0.0-1"), v("1.0.0-alpha"))
        XCTAssertLessThan(v("1.0.0-alpha.1"), v("1.0.0-alpha.beta"))
    }

    func testAlphanumericIdentifiersCompareByAsciiOrder() {
        XCTAssertLessThan(v("1.0.0-Beta"), v("1.0.0-alpha")) // 大寫 ASCII 小於小寫
        XCTAssertLessThan(v("1.0.0-alpha-1"), v("1.0.0-alpha-2"))
    }

    func testStrictlyNewerRejectsEqualAndOlder() {
        XCTAssertTrue(v("0.1.0-beta.2").isStrictlyNewer(than: v("0.1.0-beta.1")))
        XCTAssertTrue(v("0.1.0").isStrictlyNewer(than: v("0.1.0-beta.9")))
        XCTAssertFalse(v("0.1.0-beta.1").isStrictlyNewer(than: v("0.1.0-beta.1")))
        XCTAssertFalse(v("0.1.0-beta.1").isStrictlyNewer(than: v("0.1.0")), "防降版：預覽版不能取代同號正式版")
        XCTAssertFalse(v("0.0.9").isStrictlyNewer(than: v("0.1.0")))
    }

    func testMatchesBundleShortVersionString() {
        // CFBundleShortVersionString 以完整 SemVer（含預覽後綴）寫入，與 tag 去掉 v 後逐字相同。
        let tag = v("v0.2.0-beta.3")
        let bundle = v("0.2.0-beta.3")
        XCTAssertEqual(tag, bundle)
        XCTAssertNotEqual(v("0.2.0"), tag, "只有 0.2.0 的 bundle 不等於 tag 0.2.0-beta.3")
    }

    func testHashableConsistentWithEquality() {
        XCTAssertEqual(Set([v("1.0.0+a"), v("1.0.0+b"), v("v1.0.0")]).count, 1)
    }
}
