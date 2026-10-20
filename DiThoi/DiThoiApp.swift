import SwiftUI

@main
struct DiThoiApp: App {
    /// Only here so a `UISceneDelegate` can be named. iOS delivers an accepted
    /// `CKShare` to the scene, not to the app, and a SwiftUI app has scenes —
    /// so without this the invitation link opens the app and nothing happens.
    /// See `ShareAcceptance.swift`.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: TripStore
    /// One lock for the whole app, so the vault re-locks the moment it goes to
    /// the background rather than per-screen.
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // A stored property's default value is evaluated before `init()` runs,
        // so the store has to be built here — otherwise -resetTrip wipes the
        // defaults *after* it has already read them.
        #if DEBUG
        if DebugScreen.wantsReset { DebugScreen.reset() }
        #endif
        Storage.sweepStrayLoopbackFiles()
        _store = StateObject(wrappedValue: TripStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(lock)
                .tint(Palette.accent)
                // The Classical design is a single warm-paper palette; the dark
                // screens in it (stamp, separated, lock) are deliberate moments
                // rather than a dark mode, so the app doesn't follow the system
                // appearance.
                .preferredColorScheme(.light)
                .task {
                    // Opportunistic: if there's signal, the rates are current by
                    // the time a number is on screen. If there isn't, nothing
                    // happens and the cached ones keep working. Same for the
                    // other phone's half of the trip.
                    await store.rates.refreshIfNeeded()
                    await catchUp()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task {
                            // Before anything else. The trip is a protected file
                            // now, so a write that was in flight when the phone
                            // locked will have been refused — and this is the
                            // first moment it can succeed.
                            store.retryFailedWrite()
                            await store.rates.refreshIfNeeded()
                            await catchUp()
                        }
                    case .background:
                        // A built book is the whole journal in one file. The
                        // share sheet clears it when it finishes, but a sheet
                        // that was never finished with — the app swiped away
                        // mid-share — would leave it on disk indefinitely, which
                        // is the state it used to be left in every time.
                        Storage.clearExports()
                        fallthrough
                    case .inactive:
                        // Re-arm on the way out, so the hour it uses is the
                        // freshest habit rather than the one it had at launch —
                        // and write out anything a coalesced save is still
                        // holding, because the app can be gone a moment later.
                        //
                        // Under a background task assertion, which the write did
                        // not need while it was a `UserDefaults` key. It is a
                        // protected file now: it is refused once the phone
                        // locks, and the encode happens off the main actor, so
                        // without the assertion the gap between "app suspended"
                        // and "write lands" is exactly where an evening's page
                        // goes missing. The retry on the way back in is the
                        // second line, not the first.
                        Task { @MainActor in
                            let task = UIApplication.shared
                                .beginBackgroundTask(withName: "dithoi.flush")
                            // Awaited, not dispatched. The assertion is only
                            // worth holding if we know when to let it go, and
                            // sleeping a fixed two seconds would be guessing at
                            // both ends — too long to hold, too short to be sure.
                            await store.flushAndWait()
                            store.rescheduleRitual()
                            if task != .invalid {
                                UIApplication.shared.endBackgroundTask(task)
                            }
                        }
                    default:
                        break
                    }
                }
        }
    }

    /// One pass over everything that can only happen when the app is awake:
    /// merge the shared trip, collect anything posted from home, open whatever is
    /// now due, and re-arm tonight's prompt.
    ///
    /// Order matters. Letters arrive before conditions are evaluated, so a
    /// letter that lands and is already due opens in the same pass rather than
    /// on the next launch.
    @MainActor
    private func catchUp() async {
        await store.syncNow()
        if store.isObserver {
            await store.postLetters()
        } else {
            await store.collectLetters()
            store.openDueLetters()
            // Permission is asked the first time a page is saved, not
            // here. An app that opens with a system alert has spent something
            // it hasn't earned yet.
            store.rescheduleRitual()
        }
        // Photos nothing points at any more, including anything the shelf's
        // books still reference. Once per wake-up: a directory listing and a set
        // difference, against a folder that otherwise only ever grew.
        store.pruneOrphanedPhotos()
        // The same sweep for the scans, whose set is the live trip alone — see
        // `referencedDocumentIDs`. Anything that clears `documents` without
        // going through `closeTrip` leaves scans behind, and this catches
        // them.
        store.pruneOrphanedScans()
        // The widget otherwise waits for the first edit — so a fresh install, or
        // a phone that has only been read from, would sit on its placeholder.
        // A no-op when nothing has changed since the last publish.
        store.publishWidgetSnapshot()
    }
}
