import Foundation
import Combine

/// Something asked for from outside the app — Siri, Spotlight, a control on
/// the Lock Screen — that the app should do the moment a screen can.
///
/// One case, and it carries nothing. The intent that posts it runs in the
/// widget extension's reach as well as the app's, and the extension is
/// entitled to exactly one key of trip data (see WidgetSnapshot.swift). An
/// action that named a moment's words or a city would be a second.
enum QuickAction: String, Equatable {
    case markMoment
}

/// Where a quick action waits for a screen that can take it.
///
/// `InvitationInbox`'s shape, for the same reason: on a cold launch the intent
/// runs before any view exists, so the value is collected on arrival *and* on
/// appearance.
@MainActor
final class QuickActionInbox: ObservableObject {
    static let shared = QuickActionInbox()

    @Published var pending: QuickAction?

    /// Empties the inbox, and **guards before it clears**. `@Published` fires
    /// on every set, not on every change, and `take()` is called from an
    /// `onReceive` on this very publisher — so clearing an empty inbox
    /// publishes nil over nil, re-fires the receiver, and loops inside
    /// SwiftUI's layout pass. That is how `InvitationInbox` once drew a blank
    /// white screen on every launch.
    func take() -> QuickAction? {
        guard let action = pending else { return nil }
        pending = nil
        return action
    }
}
