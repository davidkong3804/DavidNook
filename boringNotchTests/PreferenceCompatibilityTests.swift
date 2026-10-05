//
//  PreferenceCompatibilityTests.swift
//  boringNotchTests
//

import Foundation
import XCTest
@testable import boringNotch

final class PreferenceCompatibilityTests: XCTestCase {
    private func checkEncodings<T: RawRepresentable & Equatable>(
        _ encodings: [(String, String, T)]
    ) throws where T.RawValue == String {
        let name = "PreferenceCompatibilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        for (legacy, current, expected) in encodings {
            for encoded in [legacy, current] {
                defaults.set(encoded, forKey: "enum")
                let stored = try XCTUnwrap(defaults.string(forKey: "enum"))
                let decoded = try XCTUnwrap(T(rawValue: stored))
                XCTAssertEqual(decoded, expected)
                XCTAssertEqual(decoded.rawValue, current)
            }
        }
        for invalid in ["", "unknown", "NOW PLAYING"] {
            XCTAssertNil(T(rawValue: invalid))
        }
    }

    func testMediaControllerEncodings() throws {
        try checkEncodings([
            ("Now Playing", "nowPlaying", MediaControllerType.nowPlaying),
            ("Apple Music", "appleMusic", .appleMusic)
        ])
    }

    func testSneakPeekEncodings() throws {
        try checkEncodings([
            ("Default", "standard", SneakPeekStyle.standard),
            ("Inline", "inline", .inline)
        ])
    }

    func testSliderColorEncodings() throws {
        try checkEncodings([
            ("White", "white", SliderColorEnum.white),
            ("Match album art", "albumArt", .albumArt),
            ("Accent color", "accent", .accent)
        ])
    }
}
