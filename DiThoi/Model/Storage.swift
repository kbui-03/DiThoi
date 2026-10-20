import Foundation

/// Where this process keeps things.
///
/// One seam, for one reason: the model checks used to write to
/// `UserDefaults.standard` and to the developer's real
/// `~/Library/Application Support/DiThoi`, and they didn't clean all of it up.
/// A test suite that mutates the machine it runs on is a test suite you
/// eventually stop trusting — and worse, one whose results depend on what the
/// last run left behind.
///
/// In the app both values are the real ones and nothing reads this file twice.
/// `Tools/VerifyTrip.swift` points them at a scratch suite and a temporary
/// directory before it builds anything.
enum Storage {

    /// Redirected once, before anything else runs. Not thread-safe and doesn't
    /// need to be: it is set at the top of `main` or never.
    nonisolated(unsafe) private static var overrideDefaults: UserDefaults?
    nonisolated(unsafe) private static var overrideContainer: URL?
    nonisolated(unsafe) private static var overrideShared: UserDefaults?

    static var defaults: UserDefaults { overrideDefaults ?? .standard }

    /// Everything the app keeps in `defaults`, named by the types that own the
    /// keys.
    ///
    /// It lives here rather than in `DebugScreen.reset()`, which is where the
    /// list used to be — as four fresh string literals, while every one of them
    /// already had a constant. Bump `TripStore.storeKey` to v4 and that reset
    /// would go on faithfully clearing v3, and every screenshot taken after it
    /// would carry the previous run's trip. This project has had that failure
    /// once already.
    ///
    /// Here it is also somewhere `run-checks.sh` can see: `DiThoi/Root/` isn't
    /// compiled by the checks, so a list kept over there could only ever be
    /// checked against a copy of itself.
    static var appKeys: [String] {
        [TripStore.storeKey, RatesService.storeKey,
         SyncCoordinator.stampKey, TripLibrary.defaultKey, TripLibrary.planKey]
    }

    /// Forgets one key, wherever it happens to live.
    ///
    /// Both places, unconditionally. Three of these five are protected files now
    /// and two are still preferences, and a reset that had to know which is a
    /// reset that goes stale the next time one moves — the same failure the
    /// `appKeys` list itself exists to prevent, one level down. Clearing an
    /// address nothing is at costs nothing.
    static func forget(_ key: String) {
        defaults.removeObject(forKey: key)
        removeProtected(named: key)
    }

    /// The one suite the widget extension can see. Exactly one key lives in it
    /// — see the note at the top of `Shared/WidgetSnapshot.swift` for why the
    /// trip itself deliberately stays out.
    ///
    /// Deliberately *not* falling back to `defaults` when the group is
    /// unreachable: `UserDefaults(suiteName:)` hands back a working object
    /// whether or not the entitlement is there, so a fallback would write the
    /// widget's data into the app's own plist, where nothing reads it and
    /// nothing complains. `nil` is the honest answer, and the widget draws its
    /// placeholder rather than somebody else's trip.
    static var shared: UserDefaults? {
        overrideShared ?? UserDefaults(suiteName: AppGroup.id)
    }

    /// The app's own folder. Everything file-backed hangs off this.
    static var container: URL {
        if let overrideContainer { return overrideContainer }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiThoi", isDirectory: true)
    }

    /// A subfolder of the container, created if it isn't there.
    static func directory(_ name: String) -> URL {
        let url = container.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Files the phone should not read while it is locked

    /// Where the trip and the exports live.
    ///
    /// `UserDefaults` used to hold the whole trip — the journal, every letter's
    /// full text, the moments, the ledger, and via the shelf every archived trip
    /// as well. A preferences plist is in every iCloud and Finder backup, is
    /// plaintext, and carries only the default protection class, which means it
    /// is readable whenever the phone has been unlocked once since boot. The
    /// passport scans got AES-GCM and a backup exclusion; the half of the app
    /// that its own screens call private got neither. `PhotoStore.init`'s
    /// comment names this exact asymmetry and only fixed the photographs.
    ///
    /// A file can carry a protection class. That is the whole reason for this.
    private static var storeDirectory: URL { directory("Store") }

    /// Writes with complete protection: unreadable, by anything, while the
    /// device is locked.
    ///
    /// Throws rather than returning a `Bool`. A silent failure here is somebody
    /// losing an evening's writing, and the caller has to be able to try again —
    /// see `TripStore.flush()`, which now retries on the next foreground.
    static func writeProtected(_ data: Data, named name: String) throws {
        // The protection class is an iOS notion; on macOS, which is where
        // `run-checks.sh` runs, the option does not exist. Everything else about
        // the write — the path, the atomicity, the three-state read that comes
        // back — is identical, which is what keeps the checks meaningful.
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try data.write(to: storeDirectory.appendingPathComponent(name), options: options)
    }

    /// What is stored under that name, or nil if nothing is.
    ///
    /// - Throws: when the file is *there* and could not be read — which on a
    ///   protected file most often means the device is locked. That has to be
    ///   distinguishable from "nothing saved", because the caller's answer to
    ///   the second one is to start a fresh trip.
    static func readProtected(named name: String) throws -> Data? {
        let url = storeDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    static func removeProtected(named name: String) {
        try? FileManager.default.removeItem(
            at: storeDirectory.appendingPathComponent(name))
    }

    // MARK: - The loopback boxes

    /// Where the stand-in transports keep their boxes.
    ///
    /// They used to write to the container root at the default protection
    /// class: `loopback-shared.json` (the ledger, the itinerary, the meeting
    /// point) and `letters-*.json` (every sealed letter in full, unsealed),
    /// both in every backup. That is the gap `writeProtected` was built to
    /// close, left open one folder up. The app no longer falls back to either
    /// box; they are reached by injection, from the checks and debug screens.
    /// Protected and out of backups all the same, because "only the checks
    /// write here" is a promise the next fallback can break.
    static var loopbackDirectory: URL {
        let url = directory("Loopback")
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = url
        try? excluded.setResourceValues(values)
        return url
    }

    /// The same write `writeProtected` makes, into the loopback folder.
    static func writeLoopback(_ data: Data, to url: URL) throws {
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try data.write(to: url, options: options)
    }

    /// Deletes the boxes earlier builds left in the container root.
    ///
    /// Removed without a read-back, which "never remove on faith" would
    /// otherwise forbid: neither file was ever the only copy of anything.
    /// `loopback-*.json` is this phone's own payload, pushed from the trip in
    /// `Store/`; `letters-*.json` is the sealed set, whose originals are
    /// `TripStore.letters` in the same protected snapshot. Run on every launch,
    /// because an earlier build can be restored from a backup at any time.
    ///
    /// - Returns: the names it removed, so a check can see it did something.
    @discardableResult
    static func sweepStrayLoopbackFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: container.path)) ?? []
        let strays = names.filter {
            $0.hasSuffix(".json") && ($0.hasPrefix("loopback-") || $0.hasPrefix("letters-"))
        }
        for name in strays {
            try? FileManager.default.removeItem(at: container.appendingPathComponent(name))
        }
        return strays
    }

    /// Where a built book waits for the share sheet.
    ///
    /// Not `temporaryDirectory`, which is where it used to go: the PDF is the
    /// entire journal — every page, every photograph, every opened letter — and
    /// it sat there at the ordinary protection class, under a name built from
    /// the trip's own title, with nothing on any path deleting it. iOS empties
    /// `tmp/` under storage pressure and on no schedule an app may rely on.
    ///
    /// `.completeUnlessOpen` rather than `.complete`, and the difference
    /// matters: the point of this file is to be handed to another process
    /// through the share sheet — Files, Mail, a print service — and a fully
    /// protected file becomes unreadable the moment the phone locks, mid-send.
    /// `UnlessOpen` keeps it readable to whoever already has it open and sealed
    /// to everybody else. The class goes on the directory so anything written
    /// into it inherits it, including the PDF `UIGraphicsPDFRenderer` creates
    /// on its own.
    static var exportDirectory: URL {
        let url = directory("Export")
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path)
        #endif
        return url
    }

    /// Empties the export folder. Called before each build and once the share
    /// sheet has finished with the file.
    static func clearExports() {
        let names = (try? FileManager.default
            .contentsOfDirectory(atPath: exportDirectory.path)) ?? []
        for name in names {
            try? FileManager.default.removeItem(
                at: exportDirectory.appendingPathComponent(name))
        }
    }

    /// Sends everything this process stores somewhere disposable.
    ///
    /// - Returns: the scratch container, so the caller can delete it afterwards.
    @discardableResult
    static func useScratch(named name: String) -> URL {
        scratchName = name
        let suite = UserDefaults(suiteName: name) ?? .standard
        suite.removePersistentDomain(forName: name)
        overrideDefaults = suite

        // The group suite has to be redirected too. On macOS
        // `UserDefaults(suiteName: "group.com.lovedones.dithoi")` succeeds and
        // writes a real plist — which is exactly the "file named after the test
        // suite living on the developer's Mac" that `discardScratch` exists to
        // prevent, just under a different name.
        let sharedName = name + ".shared"
        let sharedSuite = UserDefaults(suiteName: sharedName) ?? .standard
        sharedSuite.removePersistentDomain(forName: sharedName)
        overrideShared = sharedSuite

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        overrideContainer = url
        return url
    }

    nonisolated(unsafe) private static var scratchName: String?

    /// Puts the scratch back. Both halves of it — the directory *and* the
    /// preferences suite, which is easy to forget because it isn't a file you
    /// can see, and which is how a plist named after the test suite ends up
    /// living on the developer's machine.
    ///
    /// Call this explicitly rather than from a `defer`: `exit()` does not
    /// unwind, so a `defer` at the top of `main` never runs.
    static func discardScratch() {
        guard let scratchName else { return }
        if let url = overrideContainer { try? FileManager.default.removeItem(at: url) }
        overrideDefaults?.removePersistentDomain(forName: scratchName)
        overrideShared?.removePersistentDomain(forName: scratchName + ".shared")
        overrideDefaults = nil
        overrideShared = nil
        overrideContainer = nil
        self.scratchName = nil
    }
}
