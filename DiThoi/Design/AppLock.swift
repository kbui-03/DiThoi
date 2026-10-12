import SwiftUI
import LocalAuthentication

/// A gate in front of the passport scans.
///
/// `DocumentStore` encrypts them properly — AES-GCM, key in the Keychain — and
/// that defends against somebody pulling the files off the device. It does
/// nothing about the threat this tab creates for itself: the Show-this cards
/// exist to be *handed over*, to a driver, a hotel desk, a border official. An
/// unlocked phone passed across a counter was two taps from a decrypted
/// passport.
///
/// Not an app-wide lock. Authenticating to check what lunch cost is the kind of
/// security that gets switched off; the vault is the one place worth the
/// friction.
@MainActor
final class AppLock: ObservableObject {

    /// Locked until proven otherwise, and locked again as soon as the app goes
    /// away: backgrounding is the moment the phone is most likely to be in
    /// somebody else's hands.
    @Published private(set) var isOpen = false
    @Published private(set) var lastFailure: String?

    /// Whether a prompt is already on screen.
    ///
    /// `isOpen` alone was enough while exactly one screen was gated. It stopped
    /// being enough when the document *editor* went behind the same gate: a
    /// `Locked` sheet over `Locked` content means two `.task` blocks, both
    /// starting while the lock is still shut, and `LAContext` will happily put
    /// up two Face ID prompts one behind the other. Not a data problem — just a
    /// second dialog nobody asked for, over the screen that already looks like
    /// something went wrong.
    private var isAsking = false

    /// Whether this device can ask at all. A phone with no passcode set has no
    /// way to answer, and refusing to show somebody their own passport because
    /// of that would be protecting the wrong person.
    var canAsk: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func lock() {
        isOpen = false
        lastFailure = nil
    }

    func unlock() async {
        guard !isOpen, !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        // `.deviceOwnerAuthentication`, not `...WithBiometrics`: it falls back
        // to the passcode by itself, so a wet thumb in a Songkran water fight
        // doesn't lock somebody out of their own passport.
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        guard canAsk else {
            // Nothing to ask with. Open it rather than sealing the vault shut:
            // the scans are still encrypted at rest, and a lock nobody can
            // satisfy is just a way of losing your documents at a border.
            isOpen = true
            return
        }
        do {
            isOpen = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Your passport and visa scans are behind this.")
            lastFailure = isOpen ? nil : "Not unlocked."
        } catch {
            isOpen = false
            lastFailure = (error as? LAError)?.friendlyReason
        }
    }
}

private extension LAError {
    /// Only the ones worth saying out loud. "Cancelled" is not news.
    var friendlyReason: String? {
        switch code {
        case .userCancel, .appCancel, .systemCancel: nil
        case .userFallback: nil
        case .biometryLockout: "Too many attempts. Unlock the phone with its passcode first."
        case .passcodeNotSet: "This phone has no passcode, so there's nothing to check against."
        default: "Couldn't check it was you."
        }
    }
}

/// Covers what is on screen before iOS photographs it for the app switcher.
///
/// The lock already re-locks on `scenePhase`, and that is the *state* change.
/// This is the paint, and it needs a different signal: SwiftUI gives no
/// guarantee that a `scenePhase` re-render lands before the system takes its
/// snapshot, and that snapshot is written to disk at the ordinary protection
/// class. So a decrypted passport at full brightness could end up in
/// `Library/SplashBoard/Snapshots/` — the exact thing the lock exists to
/// prevent, one layer underneath it.
///
/// `willResignActive` is posted synchronously before the snapshot is taken,
/// which is the whole reason to use it rather than `scenePhase`.
private struct PrivacyCover: ViewModifier {
    @State private var covered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if covered {
                    ZStack {
                        Palette.bg
                        Mono("Locked", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                    }
                    .ignoresSafeArea()
                    .transition(.identity)      // no fade: the snapshot is now
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification)) { _ in
                covered = true
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification)) { _ in
                covered = false
            }
    }
}

extension View {
    /// Hides this view from the app-switcher snapshot. For the screens that put
    /// a document on the glass.
    func privacyCovered() -> some View { modifier(PrivacyCover()) }
}

/// Draws `content` only once the lock is open.
struct Locked<Content: View>: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    var reason: String
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if lock.isOpen {
                content
            } else {
                closed
            }
        }
        .privacyCovered()
        .task { await lock.unlock() }
        .onChange(of: scenePhase) { _, phase in
            // Re-locks the moment the app leaves the foreground, because that
            // is the moment the phone changes hands. The cover above is the
            // other half of the same worry — this decides what is on screen
            // when the app comes *back*, that decides what is in the picture
            // taken on the way out.
            if phase != .active { lock.lock() }
        }
    }

    private var closed: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Mono("Locked", size: 10.5, color: Palette.a700)
            Display(text: "Only you", size: 38)
                .padding(.top, 8)
                .padding(.bottom, 4)
            Aside(text: reason, size: 13)
                .padding(.bottom, Space.s4)

            if let failure = lock.lastFailure {
                Aside(text: failure, size: 12.5, color: Palette.a800)
                    .padding(.bottom, Space.s3)
            }

            OutlineButton(title: "Unlock", minHeight: 50, size: 16) {
                Task { await lock.unlock() }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.gutter)
        .background(Palette.bg)
    }
}
