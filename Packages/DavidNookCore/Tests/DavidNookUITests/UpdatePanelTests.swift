import AppKit
import SwiftUI
import XCTest
@testable import DavidNookUI

/// 更新區塊：狀態 → 按鈕的規則，以及各狀態的離屏渲染（PNG 輸出到 DAVIDNOOK_SNAPSHOT_DIR；ImageRenderer 不開視窗）。
@MainActor
final class UpdatePanelTests: XCTestCase {
    private func available(prerelease: Bool = true) -> UpdatePanelState {
        .available(version: "0.2.0-beta.1", notes: "新增：按一下就從 GitHub 更新。\n修正：歌詞偏移在切歌後沒有歸零。", isPrerelease: prerelease)
    }

    // MARK: 規則

    func testButtonsPerState() {
        XCTAssertEqual(UpdatePanelState.idle.buttons, [.check])
        XCTAssertEqual(UpdatePanelState.checking.buttons, [])
        XCTAssertEqual(UpdatePanelState.upToDate.buttons, [.checkAgain])
        XCTAssertEqual(available().buttons, [.update, .viewInBrowser])
        XCTAssertEqual(UpdatePanelState.needsFolderAccess(folder: "Applications").buttons, [.chooseFolder, .cancel])
        XCTAssertEqual(UpdatePanelState.downloading(version: "1", progress: 0.4).buttons, [.cancel])
        XCTAssertEqual(UpdatePanelState.verifying(version: "1").buttons, [])
        XCTAssertEqual(UpdatePanelState.installing(version: "1").buttons, [], "安裝中不可取消（替換已開始）")
        XCTAssertEqual(UpdatePanelState.finished(version: "1").buttons, [.relaunch])
        XCTAssertEqual(UpdatePanelState.relaunchBlocked.buttons, [.relaunch])
        XCTAssertEqual(UpdatePanelState.failed(message: "x", detail: nil, canOpenReleasePage: false).buttons, [.retry])
        XCTAssertEqual(UpdatePanelState.failed(message: "x", detail: nil, canOpenReleasePage: true).buttons, [.retry, .viewInBrowser])
    }

    func testBusyAndProgress() {
        XCTAssertTrue(UpdatePanelState.checking.isBusy)
        XCTAssertTrue(UpdatePanelState.downloading(version: "1", progress: 0.1).isBusy)
        XCTAssertTrue(UpdatePanelState.installing(version: "1").isBusy)
        XCTAssertFalse(UpdatePanelState.upToDate.isBusy)
        XCTAssertFalse(available().isBusy)
        XCTAssertEqual(UpdatePanelState.downloading(version: "1", progress: 1.7).progress, 1)
        XCTAssertEqual(UpdatePanelState.downloading(version: "1", progress: -2).progress, 0)
        XCTAssertEqual(UpdatePanelState.verifying(version: "1").progress, -1)
        XCTAssertNil(UpdatePanelState.upToDate.progress)
    }

    func testFinishedTextExplainsGatekeeperAndReauthorization() {
        let s = UpdatePanelStrings().finishedBody
        XCTAssertTrue(s.contains("仍要打開"))
        XCTAssertTrue(s.contains("重新允許"))
        XCTAssertTrue(s.contains("DavidNook.app.previous"))
    }

    // MARK: 離屏渲染

    private func render(_ state: UpdatePanelState, name: String, height: CGFloat = 260) throws {
        let view = UpdatePanelView(state: state)
            .padding(16)
            .frame(width: 500, alignment: .topLeading)
            .frame(minHeight: height, alignment: .topLeading)
            .background(Color(white: 0.96))
            .environment(\.colorScheme, .light)
        let image = try renderImage(view)
        let url = try writeSnapshot(image, named: "updater-" + name)
        let pixels = Pixels(image)
        XCTAssertGreaterThan(pixels.width, 800)
        // 面板不是空白：存在深色文字像素。
        XCTAssertGreaterThan(pixels.count(rows: 0...(pixels.height - 1), above: -1) - pixels.count(rows: 0...(pixels.height - 1), above: 0.85), 200, url.lastPathComponent)
    }

    func testRenderUpToDate() throws { try render(.upToDate, name: "1-up-to-date", height: 110) }
    func testRenderAvailable() throws { try render(available(), name: "2-available", height: 270) }
    func testRenderDownloading() throws { try render(.downloading(version: "0.2.0-beta.1", progress: 0.42), name: "3-downloading", height: 120) }
    func testRenderVerifying() throws { try render(.verifying(version: "0.2.0-beta.1"), name: "3b-verifying", height: 110) }
    func testRenderError() throws {
        try render(.failed(message: "下載的檔案和發布者公佈的 SHA-256 不相符，已停止更新。", detail: "SHA-256 mismatch (expected 4f5f…, got 9a1c…)", canOpenReleasePage: true), name: "4-error", height: 200)
    }
    func testRenderNeedsFolder() throws { try render(.needsFolderAccess(folder: "Applications"), name: "5-needs-folder", height: 220) }
    func testRenderRelaunchBlocked() throws { try render(.relaunchBlocked, name: "7-relaunch-blocked", height: 220) }
    func testRenderFinished() throws { try render(.finished(version: "0.2.0-beta.1"), name: "6-finished", height: 260) }
}
