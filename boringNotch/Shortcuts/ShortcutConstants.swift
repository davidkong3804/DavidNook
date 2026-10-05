//
//  ShortcutConstants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleSneakPeek = Self("toggleSneakPeek", initial: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", initial: .init(.i, modifiers: [.command, .shift]))
    /// 展開瀏海並切到剪貼簿分頁。預設不設定（避免與其他 App 的快捷鍵衝突），由使用者在設定 → Shortcuts 指定。
    static let openClipboard = Self("openClipboard")
}
