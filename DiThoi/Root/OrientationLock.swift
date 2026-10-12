import UIKit

/// Which way the app may face, asked by the app delegate on every rotation.
///
/// The app is portrait, and the Info.plist still says so. One screen is the
/// exception: the book reader, because a spread is two square pages side by
/// side, and drawn across a portrait phone its type was six points. The
/// delegate's answer overrides the plist, so only what this says can turn.
///
/// Static and starting at `.portrait`, so nothing can leave the app rotatable
/// by accident: a reader that is killed while open never got to put it back,
/// and the next launch starts portrait anyway.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    /// The reader, open.
    @MainActor static func landscape() { apply(.landscape, turnTo: .landscapeRight) }

    /// Everything else — and the reader while a portrait sheet is over it.
    @MainActor static func portrait() { apply(.portrait, turnTo: .portrait) }

    @MainActor private static func apply(_ allowed: UIInterfaceOrientationMask,
                                         turnTo orientation: UIInterfaceOrientationMask) {
        mask = allowed
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            // Every window's root re-asks, so the presented cover's answer is
            // read against the new mask before the turn is requested.
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
    }
}
