//
//  NotchUIEvent.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Created as part of the architecture remediation.
//

import SwiftUI
import Combine

/// UI-presentation events emitted by managers.
///
/// Managers publish; `BoringViewCoordinator` is the single subscriber and
/// decides what to present, so managers stay testable without the UI stack.
enum NotchUIEvent {
    case sneakPeek(
        type: SneakContentType,
        targetScreenUUID: String? = nil,
        duration: TimeInterval = 1.5
    )
    case expandingView(type: SneakContentType)
}

/// The event pipe. `BoringViewCoordinator` is the intended subscriber.
enum NotchUIEventBus {
    static let events = PassthroughSubject<NotchUIEvent, Never>()
}
