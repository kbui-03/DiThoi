import SwiftUI
import CloudKit

/// Where a tapped invitation link arrives.
///
/// The trip is shared as a `CKShare`, and iOS delivers an accepted share to a
/// *scene* delegate — `application(_:userDidAcceptCloudKitShareWith:)` is not
/// called for an app with scenes, which every SwiftUI app has. So the app needs
/// a `UIApplicationDelegate` whose only job is to name a `UISceneDelegate`, and
/// a scene delegate whose only job is to hand the metadata on. Neither of them
/// decides anything.
///
/// This lives in `Root/`, which `run-checks.sh` does not compile, and that is
/// the reason the parsing is not here: what an invitation *says* —
/// `CloudKitZone.tripID(fromRecordName:)` and `CloudKitSyncTransport.details` —
/// is in `Model/`, where it is checked. Everything in this file is delivery.

/// The one thing the delegate and the app both hold.
///
/// A published value rather than a call into the store, because the delegate is
/// built by UIKit and the store is a `@StateObject` belonging to the scene —
/// there is no moment where one can reach for the other and be sure it exists.
/// The metadata waits here until a view is alive to answer it.
@MainActor
final class InvitationInbox: ObservableObject {
    static let shared = InvitationInbox()

    /// Cleared by whoever takes it. It is `@Published` so a link followed while
    /// the app is already open lands on screen without a relaunch, which is the
    /// ordinary case: the invitation arrives in a chat app on the same phone.
    @Published var arrived: CKShare.Metadata?

    private init() {}

    /// Hand over what arrived, if anything, and clear it.
    ///
    /// The guard is load-bearing and the `defer` spelling of this was a bug
    /// that blanked the entire app. `@Published` fires on every set, not on
    /// every *change*, so clearing unconditionally published nil-over-nil —
    /// which re-fired the `onReceive` that had just called this, which called
    /// it again. The loop ran inside SwiftUI's layout pass, so the first render
    /// never finished: no window contents, every screen white, nothing logged
    /// and no crash to find. Only a stack sample showed it.
    ///
    /// Nothing is published when there is nothing to take.
    func take() -> CKShare.Metadata? {
        guard let metadata = arrived else { return nil }
        arrived = nil
        return metadata
    }
}

/// The app delegate, and **no scene delegate**.
///
/// The obvious shape for a scene-based app is a `UISceneDelegate` implementing
/// `windowScene(_:userDidAcceptCloudKitShareWith:)`, since that is the callback
/// UIKit documents for apps with scenes. It cannot be used here: naming a
/// `delegateClass` in `application(_:configurationForConnecting:options:)`
/// *replaces* the scene delegate SwiftUI installs, and that delegate is what
/// creates the window and hosts the view hierarchy. The app then launches to a
/// blank white screen — every screen, not only the ones this file is about —
/// with nothing logged and nothing crashed. Both spellings were tried: building
/// a fresh `UISceneConfiguration`, and setting `delegateClass` on the session's
/// own. Both blank.
///
/// So the acceptance lands on the app delegate instead, which SwiftUI leaves
/// alone. `@UIApplicationDelegateAdaptor` is supported precisely for callbacks
/// with no SwiftUI equivalent, and this is one.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Somebody followed the invitation link.
    ///
    /// Reached whether the app was running or launched by the tap, so there is
    /// no second path to keep in step — which is the other thing the scene
    /// delegate would have cost: a cold-launch branch reading
    /// `connectionOptions.cloudKitShareMetadata` that only ever runs on one of
    /// the two ways in, and is therefore the one that rots.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in InvitationInbox.shared.arrived = metadata }
    }

    /// Portrait, except while the book reader is open — see `OrientationLock`.
    /// Overrides the Info.plist list, which stays portrait.
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
