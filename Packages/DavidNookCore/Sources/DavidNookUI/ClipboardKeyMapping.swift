import AppKit
import DavidNookCore

/// 把鍵盤事件（keyCode／字元／修飾鍵）翻成面板的鍵盤語意。純函式，方便測試；實際攔截事件的是 App 端。
///
/// 規則：
/// - ↑ ↓ Home End Enter（含數字鍵盤 Enter）Esc：**不可帶任何修飾鍵**（⇧↑ 之類留給文字欄位選取文字）。
/// - ⌘⌫：恰好只有 ⌘（⌫ 為退格鍵 keyCode 51；Forward Delete 117 也算）。
/// - ⌘P：恰好只有 ⌘。若目前輸入來源的字元是 ASCII 就比字元（Dvorak 等配置才不會誤判）；
///   不是 ASCII（例如注音輸入法下 `charactersIgnoringModifiers` 會是注音符號）就退回實體按鍵 keyCode 35。
public enum ClipboardKeyMapping {
    // 虛擬鍵碼（Carbon HIToolbox `kVK_*`；這裡寫死數字以免 UI 套件依賴 Carbon）。
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    static let home: UInt16 = 115
    static let end: UInt16 = 119
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let backspace: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let escape: UInt16 = 53
    static let ansiP: UInt16 = 35

    public static func key(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> ClipboardPanelKey? {
        let relevant = modifiers.intersection([.command, .shift, .option, .control])

        if relevant.isEmpty {
            switch keyCode {
            case upArrow: return .up
            case downArrow: return .down
            case home: return .home
            case end: return .end
            case returnKey, keypadEnter: return .enter
            case escape: return .escape
            default: return nil
            }
        }

        guard relevant == .command else { return nil }
        switch keyCode {
        case backspace, forwardDelete:
            return .commandDelete
        default:
            return isPKey(keyCode: keyCode, characters: charactersIgnoringModifiers) ? .commandP : nil
        }
    }

    /// NSEvent 的便利版本（只讀 keyCode、字元與修飾鍵，不碰事件內容的其他部分）。
    public static func key(for event: NSEvent) -> ClipboardPanelKey? {
        guard event.type == .keyDown else { return nil }
        return key(keyCode: event.keyCode, charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
    }

    private static func isPKey(keyCode: UInt16, characters: String?) -> Bool {
        if let characters, !characters.isEmpty, characters.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return characters.lowercased() == "p"
        }
        return keyCode == ansiP
    }
}
