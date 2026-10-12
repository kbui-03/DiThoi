import AppIntents

/// What Siri and Spotlight offer without anybody setting anything up — and
/// what the Action button runs, through the Shortcuts app.
///
/// The Home Screen icon's long-press menu is deliberately not the route. A
/// `UIApplicationShortcutItem` reaches a scene-based app only through a scene
/// delegate, and naming one replaces the delegate SwiftUI installs, which
/// launches every screen blank (see `ShareAcceptance.swift`). App Intents need
/// no delegate at all.
struct DiThoiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MarkMomentIntent(),
                    phrases: ["Mark a moment in \(.applicationName)",
                              "Keep this moment in \(.applicationName)"],
                    shortTitle: "Mark a moment",
                    systemImageName: "sparkle")
    }
}
