import AppKit
import DavidNookCore
import XCTest
@testable import DavidNookUI

/// 鍵盤事件 → 面板鍵盤語意（純函式；不產生任何真實事件）。
final class ClipboardKeyMappingTests: XCTestCase {
    private func map(_ keyCode: UInt16, _ chars: String? = nil, _ modifiers: NSEvent.ModifierFlags = []) -> ClipboardPanelKey? {
        ClipboardKeyMapping.key(keyCode: keyCode, charactersIgnoringModifiers: chars, modifiers: modifiers)
    }

    func testPlainNavigationKeys() {
        XCTAssertEqual(map(126), .up)
        XCTAssertEqual(map(125), .down)
        XCTAssertEqual(map(115), .home)
        XCTAssertEqual(map(119), .end)
        XCTAssertEqual(map(36), .enter)
        XCTAssertEqual(map(76), .enter, "數字鍵盤 Enter")
        XCTAssertEqual(map(53), .escape)
    }

    func testNavigationKeysWithModifiersAreNotHandled() {
        XCTAssertNil(map(126, nil, .shift), "⇧↑ 留給文字欄位選取文字")
        XCTAssertNil(map(125, nil, .command))
        XCTAssertNil(map(36, nil, .option))
        XCTAssertNil(map(53, nil, .control))
        XCTAssertNil(map(115, nil, [.shift, .command]))
    }

    func testCapsLockAndFunctionFlagsDoNotCountAsModifiers() {
        XCTAssertEqual(map(126, nil, .capsLock), .up)
        XCTAssertEqual(map(125, nil, [.numericPad, .function]), .down, "方向鍵本身會帶 numericPad／function 旗標")
    }

    func testCommandDelete() {
        XCTAssertEqual(map(51, nil, .command), .commandDelete)
        XCTAssertEqual(map(117, nil, .command), .commandDelete, "Forward Delete")
        XCTAssertNil(map(51), "沒有 ⌘ 的退格鍵留給文字欄位")
        XCTAssertNil(map(51, nil, [.command, .shift]))
        XCTAssertNil(map(51, nil, .option))
    }

    func testCommandPByCharacter() {
        XCTAssertEqual(map(35, "p", .command), .commandP)
        XCTAssertEqual(map(35, "P", .command), .commandP)
        XCTAssertNil(map(35, "p"), "沒有 ⌘")
        XCTAssertNil(map(35, "p", [.command, .shift]))
        XCTAssertNil(map(35, "p", [.command, .option]))
    }

    func testCommandPOnNonLatinInputSourceFallsBackToPhysicalKey() {
        // 注音輸入法下 charactersIgnoringModifiers 會是注音符號：退回實體按鍵（keyCode 35）。
        XCTAssertEqual(map(35, "ㄣ", .command), .commandP)
        XCTAssertNil(map(40, "ㄣ", .command), "別的實體按鍵不算")
    }

    func testCommandPDoesNotFireOnOtherLatinLettersEvenIfPhysicalKeyMatches() {
        // Dvorak 之類：實體 P 鍵印出別的字母，不該被當成 ⌘P。
        XCTAssertNil(map(35, "l", .command))
    }

    func testUnrelatedKeysAreIgnored() {
        XCTAssertNil(map(0, "a"))
        XCTAssertNil(map(0, "a", .command))
        XCTAssertNil(map(49, " "))
    }
}
