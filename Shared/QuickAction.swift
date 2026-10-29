import Foundation
import Combine

/// Something asked for from outside the app — Siri, Spotlight, a control on
/// the Lock Screen — that the app should do the moment a screen can.
///
/// No case carries anything. The intent that posts one runs in the widget
/// extension's reach as well as the app's, and the extension is entitled to
/// exactly one key of trip data (see WidgetSnapshot.swift). An action that
/// named a moment's words or a city would be a second.
enum QuickAction: String, Equatable, Identifiable {
    case markMoment
    /// Tonight's page, from a tap on the day widget. Which night is the app's
    /// to work out when it opens — the link names none, so a widget entry
    /// drawn for Thursday and tapped on Friday still opens Friday.
    case writeTonight

    var id: String { rawValue }

    static let scheme = "dithoi"

    /// The day widget's link. Any app or web page can open a URL scheme, which
    /// is a second reason it carries nothing: all it can do is open a
    /// composer that saves nothing until somebody writes.
    static let tonightURL = URL(string: "\(scheme)://tonight")!

    /// The action a link asks for, or nil for anything this app didn't make.
    init?(url: URL) {
        guard url.scheme?.lowercased() == QuickAction.scheme else { return nil }
        switch url.host?.lowercased() {
        case "tonight": self = .writeTonight
        default: return nil
        }
    }
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
