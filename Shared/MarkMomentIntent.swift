import AppIntents

/// "Mark a moment" — from Siri, Spotlight, the Shortcuts app, the Action
/// button, and on iOS 18 a control on the Lock Screen or in Control Centre.
///
/// It opens the app and leaves a note in `QuickActionInbox`; the tabs present
/// the composer. Nothing is written here, because nothing here can say whether
/// this phone belongs to a traveller, an observer, or somebody who hasn't
/// finished onboarding — those screens simply never read the inbox, and the
/// intent opens the app and stops.
///
/// In both targets: a control in the widget extension can only run an intent
/// that extension knows about, and `openAppWhenRun` hands `perform()` to the
/// app process, which has to know it too.
struct MarkMomentIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a moment"
    static let description = IntentDescription("Opens Đi Thôi on a new moment — a photo and a line, kept on this phone.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.shared.pending = .markMoment
        return .result()
    }
}
