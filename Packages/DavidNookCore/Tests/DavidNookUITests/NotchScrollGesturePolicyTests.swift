import XCTest
@testable import DavidNookUI

/// 瀏海外層的滾動手勢（上滑關閉、下滑展開）何時該略過：
/// 剪貼簿分頁、滑鼠在可捲動清單上時，垂直滾動只用來捲清單；其他位置維持原本手勢。
final class NotchScrollGesturePolicyTests: XCTestCase {
    private typealias P = NotchScrollGesturePolicy

    func testClipboardOverListBlocksVerticalGestures() {
        XCTAssertFalse(P.shouldHandle(tab: .clipboard, pointerOverScrollable: true, direction: .up))
        XCTAssertFalse(P.shouldHandle(tab: .clipboard, pointerOverScrollable: true, direction: .down))
    }

    func testClipboardOverListKeepsHorizontalGestures() {
        // 清單沒有橫向捲動，左右滑（上一首／下一首）維持原樣。
        XCTAssertTrue(P.shouldHandle(tab: .clipboard, pointerOverScrollable: true, direction: .left))
        XCTAssertTrue(P.shouldHandle(tab: .clipboard, pointerOverScrollable: true, direction: .right))
    }

    func testClipboardOffListKeepsAllGestures() {
        for d in NotchScrollGestureDirection.allCases {
            XCTAssertTrue(P.shouldHandle(tab: .clipboard, pointerOverScrollable: false, direction: d), "\(d)")
        }
    }

    func testHomeTabNeverBlocked() {
        // 首頁沒有可捲動清單；即使旗標殘留為 true 也不能擋住手勢。
        for d in NotchScrollGestureDirection.allCases {
            XCTAssertTrue(P.shouldHandle(tab: .home, pointerOverScrollable: true, direction: d), "\(d)")
            XCTAssertTrue(P.shouldHandle(tab: .home, pointerOverScrollable: false, direction: d), "\(d)")
        }
    }

    func testEndPhaseIsAlwaysHandled() {
        // 結束事件一律處理，避免手勢進度卡住。
        for d in NotchScrollGestureDirection.allCases {
            XCTAssertTrue(P.shouldHandle(tab: .clipboard, pointerOverScrollable: true, direction: d, isEnd: true), "\(d)")
        }
    }
}
