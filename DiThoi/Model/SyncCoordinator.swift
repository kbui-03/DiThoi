import Foundation
import CloudKit

/// Runs a sync round and reports what it had to decide.
///
/// Pull, merge, push the merged result. The merge is pure and lives in
/// `SyncMerge`; this only sequences it and owns the state a screen can show.
@MainActor
final class SyncCoordinator: ObservableObject {

    @Published private(set) var state: SyncState
    @Published private(set) var lastSyncedAt: Date?
    /// What the last merge overwrote. Shown once, then dismissed — a silently
    /// replaced meeting point is how two people end up in different parts of a
    /// city.
    @Published var notices: [SyncNotice] = []

    private(set) var transport: SyncTransport

    /// Not private, for the reason `RatesService.storeKey` isn't: the reset
    /// path has to name it, and naming it twice is how they drift.
    nonisolated static let stampKey = "dithoi.sync.lastSyncedAt"

    init(transport: SyncTransport? = nil) {
        let chosen: SyncTransport
        if let transport {
            chosen = transport
        } else {
            let cloud = CloudKitSyncTransport()
            chosen = cloud.isAvailable ? cloud : LoopbackSyncTransport()
        }
        self.transport = chosen
        state = chosen.isAvailable ? .idle : .unavailable(reason: chosen.unavailableReason ?? "")
        lastSyncedAt = Storage.defaults.object(forKey: Self.stampKey) as? Date
    }

    var isSyncing: Bool { state == .syncing }

    /// Whether the other phone can see any of this yet.
    var isShared: Bool { transport is CloudKitSyncTransport && transport.isAvailable }

    // MARK: - Pairing

    /// A link that puts this trip on the other person's phone.
    ///
    /// Straight through to the transport. It is here rather than reached by
    /// downcasting `transport` at the call site because a screen that has to
    /// know which transport it has is a screen that will get it wrong on the
    /// build where the answer changes.
    func invitation(to tripID: UUID, named title: String,
                    inviting slot: Traveller) async throws -> URL {
        try await transport.invitation(to: tripID, named: title, inviting: slot)
    }

    /// Whether an invitation can be made at all, so the row can be absent
    /// rather than present and failing. A dead control is worse than a missing
    /// one — the whole reason "Send to Emmie" is remembered.
    var canInvite: Bool { transport is CloudKitSyncTransport && transport.isAvailable }

    /// The invitation this phone has been handed and not yet answered.
    ///
    /// It lives here rather than on `TripStore` for one reason: it is a
    /// `CKShare.Metadata`, and keeping it here is what lets `TripStore` stay
    /// free of `import CloudKit`. The store holds the *question* — a plain
    /// value — and this holds the thing needed to answer it.
    private var heldInvitation: CKShare.Metadata?

    /// Read an invitation and keep it, without joining anything.
    ///
    /// Returns what it says so the caller can put it on screen. Nil when the
    /// link isn't one of ours, or when this build has no CloudKit to accept it
    /// with — either way the answer is a sentence to somebody, not a silent
    /// no-op.
    func hold(_ metadata: CKShare.Metadata) -> CloudKitSyncTransport.Invitation? {
        guard transport is CloudKitSyncTransport, transport.isAvailable else { return nil }
        guard let details = CloudKitSyncTransport.details(of: metadata) else { return nil }
        heldInvitation = metadata
        return details
    }

    func forgetHeldInvitation() { heldInvitation = nil }

    /// Join the share that was held. Throws rather than reporting, because the
    /// caller has a trip to decide about on the strength of the answer — and
    /// deciding it on a failure is how somebody's trip gets shelved for
    /// nothing.
    func acceptHeldInvitation() async throws {
        guard let metadata = heldInvitation else {
            throw SyncError.transport("that invitation has already been dealt with")
        }
        guard let cloud = transport as? CloudKitSyncTransport else {
            throw SyncError.unavailable(transport.unavailableReason
                ?? "This build can't join a shared trip.")
        }
        try await cloud.accept(metadata)
        heldInvitation = nil
        // Nothing to invalidate: `locate` only remembers a zone it found, so a
        // trip this phone has never resolved has no entry to go stale. The next
        // round looks the zone up for the first time and finds it in the shared
        // database, which is where accepting has just put it.
    }

    /// How many times a round will start over before giving up.
    ///
    /// A conflict means the other phone wrote between this round's pull and its
    /// push, so the answer is to merge again against what is now there rather
    /// than to report a failure at somebody. Two goes is plenty for two people;
    /// a third means something other than a race.
    private static let attempts = 3

    /// How many the screen will stack before the oldest starts dropping off.
    private static let maximumNotices = 4

    /// One round. Returns the merged payload for the store to apply, or nil if
    /// nothing changed hands.
    func sync(local: SyncPayload, as role: Traveller) async -> SyncPayload? {
        guard transport.isAvailable else {
            state = .unavailable(reason: transport.unavailableReason ?? "")
            return nil
        }
        guard state != .syncing else { return nil }
        state = .syncing
        defer { if state == .syncing { state = .idle } }

        for attempt in 1...Self.attempts {
            do {
                return try await round(local: local, as: role)
            } catch SyncError.conflict where attempt < Self.attempts {
                // Straight back round: pull again, merge against what the other
                // phone just wrote, push that. Nothing is lost, because the
                // merge is the same pure function either way.
                continue
            } catch SyncError.retryable(let why, let after) where attempt < Self.attempts {
                state = .syncing
                try? await Task.sleep(for: .seconds(min(after, 30)))
                if attempt == Self.attempts - 1 { state = .failed(why) }
            } catch let error as SyncError {
                state = error.isFatal
                    ? .unavailable(reason: error.errorDescription ?? "")
                    : .failed(error.errorDescription ?? "")
                return nil
            } catch {
                state = .failed(error.localizedDescription)
                return nil
            }
        }
        return nil
    }

    /// Pull, merge, push. The merge is pure and lives in `SyncMerge`; this only
    /// sequences it.
    private func round(local: SyncPayload, as role: Traveller) async throws -> SyncPayload {
        let remote = try await transport.pull(tripID: local.tripID)
        let result = remote.map { SyncMerge.merge(local: local, remote: $0, as: role) }
        let merged = result?.payload ?? local

        try await transport.push(merged)

        notices.append(contentsOf: result?.notices ?? [])
        // Capped, newest kept. Nothing dismisses these but a tap, and a stack
        // of them down the screen is a stack nobody reads — which is the
        // opposite of why the meeting point raises one at all.
        if notices.count > Self.maximumNotices {
            notices.removeFirst(notices.count - Self.maximumNotices)
        }
        lastSyncedAt = Date()
        Storage.defaults.set(lastSyncedAt, forKey: Self.stampKey)
        state = .idle
        return merged
    }

    func dismiss(_ notice: SyncNotice) {
        notices.removeAll { $0.id == notice.id }
    }

    func dismissAllNotices() { notices.removeAll() }

    // MARK: - How it reads on screen

    var summary: String {
        switch state {
        case .unavailable(let reason): reason
        case .syncing: "syncing…"
        case .failed(let why): "couldn't sync · \(why.lowercased())"
        case .idle:
            if let lastSyncedAt {
                "synced \(Self.age(of: lastSyncedAt))"
            } else {
                "not synced yet"
            }
        }
    }

    private static func age(of date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 90 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours)h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    /// Used by the model checks to point two coordinators at one box.
    func useForTesting(_ replacement: SyncTransport) {
        transport = replacement
        state = replacement.isAvailable ? .idle : .unavailable(reason: replacement.unavailableReason ?? "")
    }
}
