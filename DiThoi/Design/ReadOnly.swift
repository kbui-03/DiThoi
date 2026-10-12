import SwiftUI

/// Whether the trip on screen can be written to.
///
/// Set in two places, for two different reasons, and the same screens honour
/// both:
///
/// - **the shelf**, when it opens a closed trip. The screens underneath are the
///   same ones the live trip uses — the ledger, the letters, the book — so
///   rather than building read-only copies of each, the handful of controls
///   that write check this and don't draw.
/// - **home mode's trail tab.** The observer is shown where they are; a pin is
///   a claim about somebody else's position and is not theirs to drop. Note it
///   is set on that tab alone and not on `HomeTabs` as a whole — the other two
///   destinations are the letters, which are the one thing that phone is for.
///
/// It is a courtesy, not the guarantee. For the shelf the guarantee is that an
/// archived trip is opened in a store built with no persistence key at all, so
/// nothing it does can reach disk even if a control slipped through; for the
/// observer it is `TripStore.arrive` and `setMeetingPoint` refusing outright.
/// This flag is what stops the app *offering* an edit it would then drop.
private struct ReadOnlyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isReadOnly: Bool {
        get { self[ReadOnlyKey.self] }
        set { self[ReadOnlyKey.self] = newValue }
    }
}

// MARK: - Motion

extension View {
    /// `withAnimation`, unless the reader has asked for less of it.
    ///
    /// The app cross-fades between whole screens and slides banners in from the
    /// edge. For somebody with vestibular sensitivity that is not decoration,
    /// and Reduce Motion is how they say so — it was being ignored everywhere.
    func gentleAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(GentleAnimation(animation: animation, value: value))
    }
}

private struct GentleAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// The same thing for imperative calls.
@MainActor
func withGentleAnimation(_ animation: Animation, _ body: () -> Void) {
    if UIAccessibility.isReduceMotionEnabled {
        body()
    } else {
        withAnimation(animation, body)
    }
}
