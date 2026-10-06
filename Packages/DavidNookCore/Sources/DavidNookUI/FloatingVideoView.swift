import AppKit
import DavidNookCore

/// 浮動視窗上所有文案；App 傳入在地化後的字串。
public struct FloatingVideoStrings {
    public var unpin: String
    public var opacity: String
    public var protectedTitle: String
    public var protectedHint: String
    public var reconnecting: String
    public var stalledTitle: String
    public var stalledHint: String

    public init(
        unpin: String = "Unpin", opacity: String = "Opacity", protectedTitle: String = "This source is content-protected",
        protectedHint: String = "The system does not allow capturing it. Try the source's own picture-in-picture.",
        reconnecting: String = "Reconnecting…", stalledTitle: String = "No picture is coming in",
        stalledHint: String = "Unpin and pin the video again, or choose the window again."
    ) {
        self.unpin = unpin; self.opacity = opacity
        self.protectedTitle = protectedTitle; self.protectedHint = protectedHint
        self.reconnecting = reconnecting; self.stalledTitle = stalledTitle; self.stalledHint = stalledHint
    }
}

/// 浮動視窗用的 NSPanel：無邊框、不搶焦點、浮在一般視窗上方，可出現在所有桌面空間與全螢幕 App 之上。
/// 大小與位置完全由內容視圖（`FloatingVideoView`）與控制器決定；**這是一般的桌面視窗，不是瀏海視窗**。
public final class FloatingVideoPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovable = false            // 移動由內容視圖自己處理（避免與縮放手勢互搶）
        animationBehavior = .none
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// 小圖示按鈕：不需要先啟用視窗就吃第一下點擊（浮動視窗不搶焦點）。
final class FloatingIconButton: NSButton {
    init(symbol: String, help: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?.withSymbolConfiguration(config)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = .white
        toolTip = help
        setAccessibilityLabel(help)
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 浮動視窗的內容：**純 AppKit（layer-backed NSView）**，不使用 SwiftUI／NSHostingView——
/// 視窗會被持續拖曳與縮放，NSHostingView 在視窗改大小時曾造成版面更新迴圈而閃退（見 git c30828f）。
///
/// - 畫面：一個 CALayer，`contents` 由 `VideoFrameDisplay` 直接放 IOSurface（與封面槽、膠囊同一份、同一條串流）。
/// - 移動：在視窗任一處按住拖曳；縮放：拖四角（約 18 pt 感應區），鎖定長寬比（`FloatingVideoGeometry.resize`）。
///   選擇自訂四角拖曳而非 NSWindow.resizeIncrements／aspectRatio：無邊框視窗沒有系統縮放邊，自訂版行為可由純函式測試。
/// - hover 才出現控制列（✕＝取消釘選、透明度）；雙擊＝取消釘選；右鍵選單有取消釘選與透明度。
/// - 黑畫面（疑似受保護）：蓋上簡短說明，控制列一直顯示（可關閉）。
@MainActor
public final class FloatingVideoView: NSView {
    public enum Content: Equatable { case live, protectedNotice, reconnecting, stalledNotice }

    public var strings: FloatingVideoStrings { didSet { refreshStrings() } }
    /// 取消釘選（✕、雙擊、右鍵選單）。
    public var onUnpin: () -> Void = {}
    public var onOpacityChange: (Double) -> Void = { _ in }
    /// 移動或縮放結束（滑鼠放開）時回報最終 frame，給控制器記住位置。
    public var onInteractionEnd: (CGRect) -> Void = { _ in }
    /// 目前畫面的長寬比（縮放鎖定用）。
    public var aspectRatio: Double = 16.0 / 9.0
    /// 視窗所在螢幕的可視範圍（縮放上限）。App 端預設取視窗所在螢幕。
    public var visibleFrameProvider: () -> CGRect = {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    public var content: Content = .live { didSet { applyContent() } }
    public private(set) var opacity: Double = FloatingVideoOpacity.defaultValue
    public static let cornerRadius: CGFloat = 10
    static let cornerZone: CGFloat = 18

    private let videoLayer = CALayer()
    private let gripLayer = CAShapeLayer()
    private let noticeView = NSView()
    private let noticeTitle = NSTextField(wrappingLabelWithString: "")
    private let noticeHint = NSTextField(wrappingLabelWithString: "")
    private let controlBar = NSView()
    private var buttons: [NSButton] = []
    private var trackingArea: NSTrackingArea?
    private var hovering = false
    private var drag: Drag?

    private enum Drag {
        case move(startMouse: CGPoint, startFrame: CGRect)
        case resize(corner: FloatingVideoCorner, grabOffset: CGSize, startFrame: CGRect)
    }

    public init(display: VideoFrameDisplay, strings: FloatingVideoStrings = FloatingVideoStrings()) {
        self.strings = strings
        super.init(frame: NSRect(x: 0, y: 0, width: FloatingVideoGeometry.defaultWidth, height: FloatingVideoGeometry.defaultWidth * 9 / 16))
        wantsLayer = true
        guard let root = layer else { return }
        root.backgroundColor = NSColor.black.cgColor
        root.cornerRadius = Self.cornerRadius
        root.cornerCurve = .continuous
        root.masksToBounds = true
        root.borderWidth = 0.5
        root.borderColor = NSColor(white: 1, alpha: 0.18).cgColor

        videoLayer.contentsGravity = .resizeAspect
        videoLayer.backgroundColor = NSColor.black.cgColor
        root.addSublayer(videoLayer)
        display.attach(videoLayer)

        gripLayer.fillColor = nil
        gripLayer.strokeColor = NSColor(white: 1, alpha: 0.85).cgColor
        gripLayer.lineWidth = 2
        gripLayer.lineCap = .round
        gripLayer.opacity = 0
        root.addSublayer(gripLayer)

        setUpNotice()
        setUpControls()
        applyContent()
        refreshStrings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: 子視圖

    private func setUpNotice() {
        noticeView.wantsLayer = true
        noticeView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        noticeTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        noticeHint.font = .systemFont(ofSize: 10.5)
        for field in [noticeTitle, noticeHint] {
            field.textColor = NSColor(white: 1, alpha: field === noticeTitle ? 0.95 : 0.7)
            field.alignment = .center
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            noticeView.addSubview(field)
        }
        addSubview(noticeView)
    }

    private func setUpControls() {
        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = NSColor(white: 0, alpha: 0.62).cgColor
        controlBar.layer?.cornerRadius = 12
        controlBar.layer?.cornerCurve = .continuous
        buttons = [
            FloatingIconButton(symbol: "xmark", help: strings.unpin, target: self, action: #selector(unpinTapped)),
            FloatingIconButton(symbol: "circle.lefthalf.filled", help: strings.opacity, target: self, action: #selector(opacityTapped)),
        ]
        buttons.forEach(controlBar.addSubview)
        controlBar.alphaValue = 0
        addSubview(controlBar)
    }

    private func refreshStrings() {
        guard buttons.count == 2 else { return }
        let helps = [strings.unpin, strings.opacity]
        for (button, help) in zip(buttons, helps) { button.toolTip = help; button.setAccessibilityLabel(help) }
        applyNoticeText()
        needsLayout = true
    }

    private func applyNoticeText() {
        switch content {
        case .live: break
        case .protectedNotice: noticeTitle.stringValue = strings.protectedTitle; noticeHint.stringValue = strings.protectedHint
        case .reconnecting: noticeTitle.stringValue = strings.reconnecting; noticeHint.stringValue = String()
        case .stalledNotice: noticeTitle.stringValue = strings.stalledTitle; noticeHint.stringValue = strings.stalledHint
        }
    }

    private func applyContent() {
        applyNoticeText()
        noticeView.isHidden = content == .live
        // 重新連線中：半透明蓋在最後一幀上；其他說明不透明。
        noticeView.layer?.backgroundColor = NSColor(white: 0.12, alpha: content == .reconnecting ? 0.78 : 1).cgColor
        videoLayer.isHidden = content == .protectedNotice || content == .stalledNotice
        updateControlsVisibility(animated: false)
        needsLayout = true
    }

    // MARK: 版面（手動；視窗大小由外部決定，這裡只排內容）

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        gripLayer.frame = bounds
        gripLayer.path = Self.gripPath(in: bounds)
        CATransaction.commit()
        noticeView.frame = bounds
        let inset: CGFloat = 12
        let barBottom: CGFloat = 38  // 控制列佔掉的上方高度
        let width = max(bounds.width - inset * 2, 0)
        let titleSize = noticeTitle.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
        let hintSize = noticeHint.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
        // 太小放不下時只留標題，完整說明改放 tooltip。
        let available = bounds.height - barBottom - 6
        let showsHint = titleSize.height + 4 + hintSize.height <= available
        noticeHint.isHidden = !showsHint
        noticeView.toolTip = content == .protectedNotice ? strings.protectedHint : (content == .stalledNotice ? strings.stalledHint : nil)
        let total = showsHint ? titleSize.height + 4 + hintSize.height : titleSize.height
        let region = bounds.height - barBottom   // 控制列在上方，說明置中於它下方的區域
        let top = min(region / 2 + total / 2, region)
        noticeTitle.frame = CGRect(x: inset, y: top - titleSize.height, width: width, height: titleSize.height)
        noticeHint.frame = CGRect(x: inset, y: top - titleSize.height - 4 - hintSize.height, width: width, height: hintSize.height)

        let buttonWidth: CGFloat = 28, barHeight: CGFloat = 24
        let barWidth = buttonWidth * CGFloat(buttons.count) + 6
        controlBar.frame = CGRect(x: (bounds.width - barWidth) / 2, y: bounds.height - barHeight - 8, width: barWidth, height: barHeight)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: 3 + buttonWidth * CGFloat(index), y: 0, width: buttonWidth, height: barHeight)
        }
        window?.invalidateShadow()
    }

    /// 四角的小直角標記（hover 時顯示，提示可以拖角縮放）。
    static func gripPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let inset: CGFloat = 5, len: CGFloat = 9
        let (l, r, b, t) = (rect.minX + inset, rect.maxX - inset, rect.minY + inset, rect.maxY - inset)
        path.move(to: CGPoint(x: l, y: b + len)); path.addLine(to: CGPoint(x: l, y: b)); path.addLine(to: CGPoint(x: l + len, y: b))
        path.move(to: CGPoint(x: r - len, y: b)); path.addLine(to: CGPoint(x: r, y: b)); path.addLine(to: CGPoint(x: r, y: b + len))
        path.move(to: CGPoint(x: l, y: t - len)); path.addLine(to: CGPoint(x: l, y: t)); path.addLine(to: CGPoint(x: l + len, y: t))
        path.move(to: CGPoint(x: r - len, y: t)); path.addLine(to: CGPoint(x: r, y: t)); path.addLine(to: CGPoint(x: r, y: t - len))
        return path
    }

    // MARK: 透明度、畫面、hover

    /// 設定目前透明度（視窗的 alphaValue 由控制器設；這裡只記住並用於選單打勾）。
    public func setOpacity(_ value: Double) { opacity = FloatingVideoOpacity.clamped(value) }

    /// 測試／離屏渲染用的假畫面（正式 App 一律走 `VideoFrameDisplay`）。
    public func setStaticFrame(_ image: CGImage?) { videoLayer.contents = image }

    /// 測試／離屏渲染用：強制顯示（或隱藏）hover 才出現的控制列與四角標記。
    public func setHoverForTesting(_ value: Bool) { hovering = value; updateControlsVisibility(animated: false) }

    /// 控制列目前是否可見（hover 中，或黑畫面說明時一直顯示）。
    public var controlsAreVisible: Bool { hovering || content != .live }
    var controlBarForTesting: NSView { controlBar }
    var buttonsForTesting: [NSButton] { buttons }

    private func updateControlsVisibility(animated: Bool) {
        let target: CGFloat = controlsAreVisible ? 1 : 0
        let grip: Float = hovering && content == .live ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                controlBar.animator().alphaValue = target
            }
        } else {
            controlBar.alphaValue = target
        }
        gripLayer.opacity = grip
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) { hovering = true; updateControlsVisibility(animated: true) }
    public override func mouseExited(with event: NSEvent) { hovering = false; updateControlsVisibility(animated: true) }

    // MARK: 滑鼠：移動、四角縮放、雙擊

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    /// 控制列透明（沒 hover）時不可攔截點擊：否則從那裡開始拖曳會變成按到看不見的按鈕。
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if !controlsAreVisible, let hit, hit !== self, hit.isDescendant(of: controlBar) { return self }
        return hit
    }

    /// 滑鼠位置（視圖座標）落在哪個角的感應區；不在角落＝nil。
    func corner(at point: CGPoint) -> FloatingVideoCorner? {
        let z = Self.cornerZone
        let left = point.x <= z, right = point.x >= bounds.width - z
        let bottom = point.y <= z, top = point.y >= bounds.height - z
        switch (left, right, bottom, top) {
        case (true, _, true, _): return .bottomLeft
        case (_, true, true, _): return .bottomRight
        case (true, _, _, true): return .topLeft
        case (_, true, _, true): return .topRight
        default: return nil
        }
    }

    public override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount >= 2 {
            drag = nil
            onUnpin()
            return
        }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        let frame = window.frame
        if let corner = corner(at: convert(event.locationInWindow, from: nil)) {
            let cornerPoint: CGPoint
            switch corner {
            case .bottomLeft: cornerPoint = CGPoint(x: frame.minX, y: frame.minY)
            case .bottomRight: cornerPoint = CGPoint(x: frame.maxX, y: frame.minY)
            case .topLeft: cornerPoint = CGPoint(x: frame.minX, y: frame.maxY)
            case .topRight: cornerPoint = CGPoint(x: frame.maxX, y: frame.maxY)
            }
            drag = .resize(corner: corner, grabOffset: CGSize(width: mouse.x - cornerPoint.x, height: mouse.y - cornerPoint.y), startFrame: frame)
        } else {
            drag = .move(startMouse: mouse, startFrame: frame)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let window, let drag else { return }
        // 用事件自己的視窗座標換算成螢幕座標（視窗一邊移動時仍然正確，也能在測試中合成事件）。
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        switch drag {
        case .move(let start, let startFrame):
            window.setFrameOrigin(CGPoint(x: startFrame.minX + mouse.x - start.x, y: startFrame.minY + mouse.y - start.y))
        case .resize(let corner, let grab, let startFrame):
            let pointer = CGPoint(x: mouse.x - grab.width, y: mouse.y - grab.height)
            let next = FloatingVideoGeometry.resize(frame: startFrame, corner: corner, pointer: pointer, aspectRatio: aspectRatio, in: visibleFrameProvider())
            if next != window.frame { window.setFrame(next, display: true) }
        }
    }

    public override func mouseUp(with event: NSEvent) {
        guard drag != nil, let window else { drag = nil; return }
        drag = nil
        onInteractionEnd(window.frame)
    }

    // MARK: 按鈕與右鍵選單

    @objc private func unpinTapped() { onUnpin() }
    @objc private func opacityTapped() { onOpacityChange(FloatingVideoOpacity.next(after: opacity)) }
    @objc private func opacityMenuItemChosen(_ item: NSMenuItem) { onOpacityChange(FloatingVideoOpacity.clamped(Double(item.tag) / 100)) }

    public override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }

    /// 右鍵選單：與控制列相同的動作。
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add(strings.unpin, #selector(unpinTapped))
        let opacityItem = NSMenuItem(title: strings.opacity, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for step in FloatingVideoOpacity.steps {
            let percent = Int((step * 100).rounded())
            let label = String(format: "%d%%", percent)   // 純數字，不需在地化
            let item = NSMenuItem(title: label, action: #selector(opacityMenuItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.state = abs(step - opacity) < 0.05 ? .on : .off
            sub.addItem(item)
        }
        opacityItem.submenu = sub
        menu.addItem(opacityItem)
        return menu
    }
}
