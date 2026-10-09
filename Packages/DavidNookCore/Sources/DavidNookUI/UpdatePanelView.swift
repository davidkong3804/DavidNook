import SwiftUI

/// 設定頁「更新」區塊的狀態（純資料；App 端的 UpdateController 決定目前是哪一個）。
public enum UpdatePanelState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String, notes: String, isPrerelease: Bool)
    /// 還沒有 DavidNook 所在資料夾的寫入授權；`folder` 是要請使用者選的資料夾名稱。
    case needsFolderAccess(folder: String)
    case downloading(version: String, progress: Double)
    case verifying(version: String)
    case installing(version: String)
    /// 新版已就位；等使用者按下重新啟動。
    case finished(version: String)
    /// 新版已安裝，但 macOS（Gatekeeper）擋下第一次開啟；舊版繼續執行。
    case relaunchBlocked
    /// `canOpenReleasePage`：已知道目標版本時才提供「在瀏覽器查看」。
    case failed(message: String, detail: String?, canOpenReleasePage: Bool)
}

/// 更新區塊的文案（App 傳入在地化後的字串；預設為繁體中文，供預覽與測試使用）。
public struct UpdatePanelStrings {
    public var check = "檢查更新"
    public var checkAgain = "再檢查一次"
    public var checking = "正在檢查…"
    public var upToDate = "已是最新版本"
    public var available: (String) -> String = { "有新版本：\($0)" }
    public var prereleaseBadge = "預覽版"
    public var updateAndRestart = "更新並重新啟動"
    public var viewInBrowser = "在瀏覽器查看這個版本"
    public var releaseNotes = "發行說明（摘要）"
    public var needsFolderTitle = "需要你的授權才能更新"
    public var needsFolderBody: (String) -> String = {
        "DavidNook 在沙盒中執行，沒有你的允許就不能改動自己所在的資料夾。請選擇「\($0)」資料夾來授權這次更新；只有更新時會請你選一次，DavidNook 不會記住或重複使用這個授權。"
    }
    public var chooseFolder = "選擇資料夾…"
    public var cancel = "取消"
    public var downloading: (String) -> String = { "正在下載 \($0)…" }
    public var verifying: (String) -> String = { "正在驗證 \($0)（雜湊、簽章、權限）…" }
    public var installing: (String) -> String = { "正在安裝 \($0)…" }
    public var finishedTitle: (String) -> String = { "已安裝 \($0)" }
    public var finishedBody = "舊版已備份為 DavidNook.app.previous。因為 DavidNook 是自行簽署、未經 Apple 公證的 App，macOS 會把新版當成剛下載的 App：第一次開啟可能會被擋下一次，請到「系統設定 → 隱私權與安全性」按「仍要打開」。另外更新後簽章指紋會改變，螢幕錄製與自動化的授權可能需要重新允許。"
    public var relaunch = "重新啟動並打開新版"
    public var relaunchBlocked = "macOS 還沒有打開新版。更新後這是正常的：請到「系統設定 → 隱私權與安全性」按「仍要打開」，再打開一次 DavidNook。在那之前，目前這個版本會繼續執行。"
    public var relaunchBlockedTitle = "新版已安裝，但還沒打開"
    public var failedTitle = "更新失敗"
    public var retry = "再試一次"

    public init() {}
}

public struct UpdatePanelCallbacks {
    public var onCheck: () -> Void
    public var onUpdate: () -> Void
    public var onChooseFolder: () -> Void
    public var onCancel: () -> Void
    public var onOpenReleasePage: () -> Void
    public var onRelaunch: () -> Void

    public init(onCheck: @escaping () -> Void = {}, onUpdate: @escaping () -> Void = {}, onChooseFolder: @escaping () -> Void = {},
                onCancel: @escaping () -> Void = {}, onOpenReleasePage: @escaping () -> Void = {}, onRelaunch: @escaping () -> Void = {}) {
        self.onCheck = onCheck
        self.onUpdate = onUpdate
        self.onChooseFolder = onChooseFolder
        self.onCancel = onCancel
        self.onOpenReleasePage = onOpenReleasePage
        self.onRelaunch = onRelaunch
    }
}

/// 狀態 → 要顯示哪些按鈕（獨立成純函式，方便單元測試；視圖只照著畫）。
public enum UpdatePanelButton: Equatable, Sendable {
    case check, checkAgain, update, chooseFolder, cancel, viewInBrowser, relaunch, retry
}

public extension UpdatePanelState {
    var buttons: [UpdatePanelButton] {
        switch self {
        case .idle: [.check]
        case .checking: []
        case .upToDate: [.checkAgain]
        case .available: [.update, .viewInBrowser]
        case .needsFolderAccess: [.chooseFolder, .cancel]
        case .downloading: [.cancel]
        case .verifying, .installing: []
        case .finished, .relaunchBlocked: [.relaunch]
        case .failed(_, _, let canOpen): canOpen ? [.retry, .viewInBrowser] : [.retry]
        }
    }

    /// 進行中（不該再接受新的「檢查」或「更新」點擊）。
    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing: true
        default: false
        }
    }

    /// 進度條：nil 表示不顯示；不確定進度用 -1。
    var progress: Double? {
        switch self {
        case .checking, .verifying, .installing: -1
        case .downloading(_, let p): min(max(p, 0), 1)
        default: nil
        }
    }
}

public struct UpdatePanelView: View {
    public var state: UpdatePanelState
    public var strings: UpdatePanelStrings
    public var callbacks: UpdatePanelCallbacks

    public init(state: UpdatePanelState, strings: UpdatePanelStrings = UpdatePanelStrings(), callbacks: UpdatePanelCallbacks = UpdatePanelCallbacks()) {
        self.state = state
        self.strings = strings
        self.callbacks = callbacks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            if case .available(_, let notes, _) = state, !notes.isEmpty { notesBlock(notes) }
            if case .needsFolderAccess(let folder) = state { detail(strings.needsFolderBody(folder)) }
            if case .finished = state { detail(strings.finishedBody) }
            if case .relaunchBlocked = state { detail(strings.relaunchBlocked) }
            if case .failed(_, let detailText, _) = state {
                if let detailText, !detailText.isEmpty { detail(detailText) }
            }
            if let progress = state.progress { ProgressBar(value: progress) }
            if !state.buttons.isEmpty {
                HStack(spacing: 8) {
                    ForEach(state.buttons, id: \.self) { button in
                        UpdateButton(title: title(for: button), isPrimary: button == primaryButton) { action(for: button)() }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: 部件

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon.name).foregroundStyle(icon.color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.body.weight(.medium))
                if case .available(_, _, true) = state {
                    Text(strings.prereleaseBadge).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strings.releaseNotes).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: notes) // 純文字：不解析 Markdown、不開連結
                .font(.callout)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private func detail(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headline: String {
        switch state {
        case .idle: ""
        case .checking: strings.checking
        case .upToDate: strings.upToDate
        case .available(let v, _, _): strings.available(v)
        case .needsFolderAccess: strings.needsFolderTitle
        case .downloading(let v, let p): strings.downloading(v) + " " + "\(Int((min(max(p, 0), 1)) * 100))%"
        case .verifying(let v): strings.verifying(v)
        case .installing(let v): strings.installing(v)
        case .finished(let v): strings.finishedTitle(v)
        case .relaunchBlocked: strings.relaunchBlockedTitle
        case .failed(let message, _, _): message
        }
    }

    private var icon: (name: String, color: Color) {
        switch state {
        case .idle: ("arrow.triangle.2.circlepath", .secondary)
        case .checking, .downloading, .verifying, .installing: ("arrow.triangle.2.circlepath", .accentColor)
        case .upToDate: ("checkmark.circle.fill", .green)
        case .available: ("arrow.down.circle.fill", .accentColor)
        case .needsFolderAccess: ("folder.badge.questionmark", .orange)
        case .finished: ("checkmark.seal.fill", .green)
        case .relaunchBlocked: ("lock.shield.fill", .orange)
        case .failed: ("exclamationmark.triangle.fill", .orange)
        }
    }

    private var primaryButton: UpdatePanelButton? {
        switch state {
        case .idle: .check
        case .available: .update
        case .needsFolderAccess: .chooseFolder
        case .finished, .relaunchBlocked: .relaunch
        case .failed: .retry
        default: nil
        }
    }

    private func title(for button: UpdatePanelButton) -> String {
        switch button {
        case .check: strings.check
        case .checkAgain: strings.checkAgain
        case .update: strings.updateAndRestart
        case .chooseFolder: strings.chooseFolder
        case .cancel: strings.cancel
        case .viewInBrowser: strings.viewInBrowser
        case .relaunch: strings.relaunch
        case .retry: strings.retry
        }
    }

    private func action(for button: UpdatePanelButton) -> () -> Void {
        switch button {
        case .check, .checkAgain, .retry: callbacks.onCheck
        case .update: callbacks.onUpdate
        case .chooseFolder: callbacks.onChooseFolder
        case .cancel: callbacks.onCancel
        case .viewInBrowser: callbacks.onOpenReleasePage
        case .relaunch: callbacks.onRelaunch
        }
    }
}

// MARK: - 自繪元件（不依賴 AppKit 控制項，離屏渲染才畫得出來）

private struct ProgressBar: View {
    var value: Double // -1＝不確定

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.accentColor)
                    .frame(width: value < 0 ? proxy.size.width * 0.3 : proxy.size.width * value)
                    .offset(x: value < 0 ? proxy.size.width * 0.35 : 0)
            }
        }
        .frame(height: 6)
        .accessibilityValue(value < 0 ? Text(verbatim: "") : Text(verbatim: "\(Int(value * 100))%"))
    }
}

private struct UpdateButton: View {
    var title: String
    var isPrimary: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.callout.weight(isPrimary ? .semibold : .regular))
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(isPrimary ? Color.accentColor : Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
