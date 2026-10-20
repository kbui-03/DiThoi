import Foundation
import CloudKit

// MARK: - Loopback

/// A second phone that lives in a file.
///
/// It exists so the half of sync that can actually be wrong — merging, the
/// settlement handshake, two people editing the same trip offline — can be
/// exercised without an Apple Developer account, an iCloud container, or a
/// second device. `Tools/VerifyTrip.swift` drives two stores through this and
/// checks they converge.
final class LoopbackSyncTransport: SyncTransport, @unchecked Sendable {
    let name = "This device only"
    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }

    /// Milliseconds of pretend network, so the UI's syncing state is real
    /// enough to see.
    var latency: Duration = .milliseconds(120)

    private let url: URL
    private let queue = DispatchQueue(label: "dithoi.loopback")

    init(named box: String = "shared") {
        url = Storage.loopbackDirectory.appendingPathComponent("loopback-\(box).json")
    }

    func push(_ payload: SyncPayload) async throws {
        try? await Task.sleep(for: latency)
        let data = try JSONEncoder().encode(payload)
        try queue.sync { try Storage.writeLoopback(data, to: url) }
    }

    func pull(tripID: UUID) async throws -> SyncPayload? {
        try? await Task.sleep(for: latency)
        guard let data = queue.sync(execute: { try? Data(contentsOf: url) }),
              let payload = try? JSONDecoder().decode(SyncPayload.self, from: data)
        else { return nil }
        // Somebody else's trip is not this trip's problem. `SyncMerge` refuses
        // a mismatch too, but refusing it here means the round is quiet rather
        // than raising a notice about a trip nobody asked about.
        return payload.tripID == tripID ? payload : nil
    }

    /// There is no second phone, so there is nobody to invite.
    ///
    /// Refused rather than faked. A URL from here would be a link that opens
    /// nothing, handed to somebody as if a trip were waiting behind it — the
    /// "Send to Emmie" button, one subsystem over.
    func invitation(to tripID: UUID, named title: String,
                    inviting slot: Traveller) async throws -> URL {
        throw SyncError.unavailable(
            "This build keeps the trip on this phone, so there is nobody to invite to it.")
    }

    func erase() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - CloudKit

/// Where a trip lives in iCloud, and whether iCloud is usable at all.
///
/// This was `CloudKitSyncTransport`'s private business until the letters needed
/// the same answer. `CloudKitLetterDropTransport` used to work it out by
/// enumerating every zone looking for one named `DiThoi` — which meant a letter
/// could only be posted if the *sync* transport had already run and made it, and
/// otherwise `post` threw with nothing to say. Two transports asking the same
/// question two different ways is how they come to disagree about the answer.
///
/// The anchor is the trip record, not the zone name: the zone tells you where to
/// look, the record tells you the trip is actually there. Letters ride in the
/// same zone, so they resolve it the same way.
final class CloudKitZone: @unchecked Sendable {

    static let containerID = "iCloud.com.lovedones.dithoi"
    static let zoneName = "DiThoi"

    /// CloudKit is only usable if the app was actually signed with the
    /// entitlement. Checking the bundle rather than calling CloudKit keeps this
    /// safe to construct in any build — touching `CKContainer` without the
    /// entitlement traps.
    ///
    /// One place, because it was two copies of the same string literal and a
    /// build where the two disagreed would have had the trip in iCloud and the
    /// letters on a file, which is very nearly what shipped.
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "DiThoiCloudKitEnabled") as? Bool ?? false
    }

    var container: CKContainer { CKContainer(identifier: Self.containerID) }

    /// Which side of the share this phone is on, once we've found out. Owner
    /// and participant read the same trip through different databases, and
    /// there is no flag anywhere that says which you are — you find out by
    /// looking.
    private var resolved: [UUID: CKRecordZone.ID] = [:]
    private let lock = NSLock()

    private func cachedZone(_ tripID: UUID) -> CKRecordZone.ID? {
        lock.lock(); defer { lock.unlock() }
        return resolved[tripID]
    }

    private func remember(_ zone: CKRecordZone.ID, for tripID: UUID) {
        lock.lock(); defer { lock.unlock() }
        resolved[tripID] = zone
    }

    /// The trip's own record — the thing whose presence proves the zone is the
    /// right one.
    static func tripRecordID(_ tripID: UUID, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "Trip-\(tripID.uuidString)", zoneID: zone)
    }

    /// The trip a record name is for, and the reason `tripRecordID` had to stay
    /// reversible.
    ///
    /// A phone accepting an invitation is handed share metadata and nothing
    /// else. The one thing that identifies the trip is the root record's name,
    /// so this is how the joining phone learns which trip it just joined — and
    /// adopting the *wrong* id is not a visible failure, it is two phones
    /// syncing quietly past each other, which is the state this whole feature
    /// exists to end. Hence a parser with a check on it rather than a
    /// `dropFirst(5)` at the call site.
    ///
    /// The prefix is checked rather than trimmed: `LetterDrop` records live in
    /// the same zone, and a name that isn't a trip's must answer nil rather
    /// than a UUID that happens to parse.
    static func tripID(fromRecordName name: String) -> UUID? {
        let prefix = "Trip-"
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }

    /// Which traveller the person following an invitation becomes.
    ///
    /// A field on the trip *record*, not on `SyncPayload`. The payload's field
    /// list is pinned by a reflection check for a reason, and this is routing
    /// for one handshake rather than part of the trip: it is read once, on the
    /// way in, and never merged.
    static let invitedSlotKey = "invitedSlot"

    /// The database and zone this trip actually lives in.
    ///
    /// Owner first, because that is the common case and it needs no fetch of
    /// anything else. Then the shared database, whose zones each belong to
    /// whoever shared them — there is no way to guess the owner's name, so they
    /// have to be enumerated.
    ///
    /// - Parameter creatingIfNeeded: makes this phone the owner when nobody has
    ///   pushed the trip anywhere. **Only the trip may pass `true`.** A letter
    ///   posted into a freshly created private zone would be a write that
    ///   succeeds into a box on the writer's own account that no traveller can
    ///   ever read — worse than the throw, because it looks like it worked.
    func locate(_ tripID: UUID, creatingIfNeeded: Bool) async throws -> (CKDatabase, CKRecordZone.ID) {
        if let zone = cachedZone(tripID) {
            let database = zone.ownerName == CKCurrentUserDefaultName
                ? container.privateCloudDatabase
                : container.sharedCloudDatabase
            return (database, zone)
        }

        let ownZone = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        if await exists(Self.tripRecordID(tripID, in: ownZone), in: container.privateCloudDatabase) {
            remember(ownZone, for: tripID)
            return (container.privateCloudDatabase, ownZone)
        }

        let shared = container.sharedCloudDatabase
        if let zones = try? await shared.allRecordZones() {
            for zone in zones where zone.zoneID.zoneName == Self.zoneName {
                if await exists(Self.tripRecordID(tripID, in: zone.zoneID), in: shared) {
                    remember(zone.zoneID, for: tripID)
                    return (shared, zone.zoneID)
                }
            }
        }

        guard creatingIfNeeded else { throw SyncError.transport("nothing shared yet") }

        // Nobody has pushed this trip anywhere, so this phone is the owner.
        _ = try? await container.privateCloudDatabase.save(CKRecordZone(zoneID: ownZone))
        remember(ownZone, for: tripID)
        return (container.privateCloudDatabase, ownZone)
    }

    private func exists(_ id: CKRecord.ID, in database: CKDatabase) async -> Bool {
        (try? await database.record(for: id)) != nil
    }

    // MARK: What went wrong, in words

    /// Everything CloudKit does when it goes wrong, said the way the rest of
    /// the app talks. The distinction that matters is between "try again in a
    /// moment" and "this needs a person", because the first should never reach
    /// a screen.
    static func translate(_ error: Error) -> SyncError {
        guard let ck = error as? CKError else {
            return .transport(error.localizedDescription)
        }
        switch ck.code {
        case .serverRecordChanged:
            return .conflict
        case .networkUnavailable, .networkFailure:
            return .retryable("no signal", after: ck.retryAfterSeconds ?? 5)
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .retryable("iCloud is busy", after: ck.retryAfterSeconds ?? 10)
        case .notAuthenticated:
            return .unavailable("Sign in to iCloud on this phone and the trip will start syncing again.")
        case .quotaExceeded:
            return .unavailable("This iCloud account is full, so the trip can't sync until something is cleared.")
        case .managedAccountRestricted, .permissionFailure:
            return .unavailable("This iCloud account isn't allowed to share, so the trip stays on this phone.")
        case .zoneNotFound, .userDeletedZone:
            return .unavailable("The shared trip isn't in iCloud any more. Everything is still on this phone.")
        case .changeTokenExpired:
            return .retryable("catching up from scratch", after: 0)
        case .incompatibleVersion:
            return .unavailable("This phone is running an older version of the app than the trip was written with.")
        case .partialFailure:
            // One record, so a partial failure is a whole failure — but the
            // useful error is the one inside it.
            if let inner = (ck.partialErrorsByItemID?.values.first) {
                return translate(inner)
            }
            return .transport(ck.localizedDescription)
        default:
            return .transport(ck.localizedDescription)
        }
    }
}

/// The real transport, for when the app has a team and a container.
///
/// **Inert as it stands.** `isAvailable` is `CloudKitZone.isEnabled`, and every
/// call checks it, so nothing here runs. To switch it on:
///
/// 1. Set `DEVELOPMENT_TEAM` in the project — and it must be a **paid**
///    membership. A free personal team cannot hold the iCloud capability at
///    all: the portal refuses the profile with "Personal development teams…
///    do not support the iCloud capability", so steps 2 and 3 have nothing to
///    stand on.
/// 2. Add the iCloud capability with CloudKit, and a container named
///    `iCloud.com.lovedones.dithoi`, to `DiThoi.entitlements`.
/// 3. Set `DiThoiCloudKitEnabled` to `<true/>` in `DiThoi-Info.plist`.
///
/// Step 3 is a physical plist and not `INFOPLIST_KEY_DiThoiCloudKitEnabled`,
/// which is what it used to say. That mechanism only injects keys Xcode already
/// knows about, so the custom one was dropped and the built app had no such key
/// — `isEnabled` read `nil` and answered `false` no matter what the project
/// said. The switch documented here was a switch that did nothing.
///
/// The order matters: `isEnabled` reads the flag and cannot see the
/// entitlement, so a build with step 3 done and step 2 missing asks
/// `CKContainer` for a container it was not signed for. On a device the build
/// fails before that can ship; on the simulator it builds, and the entitlement
/// is simulated, so it resolves the container and fails at the account instead.
///
/// Those three now switch the **letters** on as well as the trip — see
/// `chooseLetterTransport`. They used to switch on only the trip, because
/// `TripStore` built a `LoopbackLetterDropTransport` unconditionally.
///
/// **None of this has ever executed.** It is written to the shape the rest of
/// the app already assumes, and its semantics are pinned by the same
/// conformance suite the loopback passes (`TransportConformance`), but the
/// first real run will find things a file-backed stand-in cannot simulate.
///
/// ## Why a custom zone and a share
///
/// This used to write one fixed record, named `trip`, to
/// `privateCloudDatabase`. The private database is scoped to a single iCloud
/// account, so that gave one person sync across their own devices and nothing
/// at all between two people — while every screen in the app said the trip was
/// shared. Sharing needs three things the old shape couldn't provide:
///
/// - a **custom zone**, because records in the default zone can't be shared;
/// - a **`CKShare` on a root record**, which is what produces an invitation;
/// - reading through **`sharedCloudDatabase`** when this phone is the
///   participant rather than the owner.
///
/// The record is keyed off the trip, which is what `SyncPayload.tripID` was
/// always for. One record per trip, holding the whole payload as JSON: the
/// merge is ours, not CloudKit's, and one record means one atomic write and no
/// partially-applied trip.
final class CloudKitSyncTransport: SyncTransport, @unchecked Sendable {

    let name = "iCloud, shared with the other phone"

    private let recordType = "SharedTrip"
    private let zone = CloudKitZone()

    var isAvailable: Bool { CloudKitZone.isEnabled }

    var unavailableReason: String? {
        isAvailable ? nil : "This build has no iCloud container, so the trip stays on this phone."
    }

    private var container: CKContainer { zone.container }

    private func locate(_ tripID: UUID, creatingIfNeeded: Bool) async throws -> (CKDatabase, CKRecordZone.ID) {
        try await zone.locate(tripID, creatingIfNeeded: creatingIfNeeded)
    }

    private func recordID(_ tripID: UUID, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CloudKitZone.tripRecordID(tripID, in: zone)
    }

    // MARK: Moving the payload

    func push(_ payload: SyncPayload) async throws {
        guard isAvailable else { throw SyncError.unavailable(unavailableReason ?? "") }
        let data = try JSONEncoder().encode(payload)
        let (database, zone) = try await locate(payload.tripID, creatingIfNeeded: true)
        let id = recordID(payload.tripID, in: zone)

        let record = (try? await database.record(for: id))
            ?? CKRecord(recordType: recordType, recordID: id)
        record["payload"] = data as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue

        do {
            // `.ifServerRecordUnchanged` is what closes the window between this
            // round's pull and this push. Without it the last writer wins the
            // whole record, so a phone pushing a payload built from a stale
            // pull silently drops whatever the other one added in between —
            // recoverable only because both phones keep their own copies and
            // re-push. With it, the write is refused and the round runs again.
            let (saves, _) = try await database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            for (_, result) in saves {
                if case .failure(let error) = result { throw CloudKitZone.translate(error) }
            }
        } catch let error as SyncError {
            throw error
        } catch {
            throw CloudKitZone.translate(error)
        }
    }

    func pull(tripID: UUID) async throws -> SyncPayload? {
        guard isAvailable else { throw SyncError.unavailable(unavailableReason ?? "") }
        do {
            let (database, zone) = try await locate(tripID, creatingIfNeeded: false)
            let record = try await database.record(for: recordID(tripID, in: zone))
            guard let data = record["payload"] as? Data else { return nil }
            let payload = try JSONDecoder().decode(SyncPayload.self, from: data)
            // The record name carries the trip, so this should never fire. It
            // is here because "should never" is how a ledger ends up merged into
            // somebody else's book.
            return payload.tripID == tripID ? payload : nil
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil          // nobody has pushed yet
        } catch let error as SyncError {
            if case .transport("nothing shared yet") = error { return nil }
            throw error
        } catch {
            throw CloudKitZone.translate(error)
        }
    }

    // MARK: Pairing

    /// The invitation. Hand the URL to the other person however you like — it
    /// is a link, and following it puts this trip in their shared database.
    ///
    /// The trip record is saved along with the share, and carries which slot the
    /// invitee becomes. It has to be written *here* rather than read off the
    /// payload later: the joining phone needs to know who it is before it merges
    /// anything, and the payload it would read that from is the very thing the
    /// merge is about to rewrite.
    ///
    /// `CKShare` is also what would make `role` stop being a switch two phones
    /// can both flip: a participant has an identity, so "who is holding this
    /// phone" could be answered by CloudKit rather than by asking. That is a
    /// separate change, and this is the half it needs.
    func invitation(to tripID: UUID, named title: String,
                    inviting slot: Traveller) async throws -> URL {
        guard isAvailable else { throw SyncError.unavailable(unavailableReason ?? "") }
        let (database, zone) = try await locate(tripID, creatingIfNeeded: true)
        guard database === container.privateCloudDatabase else {
            throw SyncError.transport("only the person who started the trip can invite somebody to it")
        }

        let id = recordID(tripID, in: zone)
        let root = (try? await database.record(for: id))
            ?? CKRecord(recordType: recordType, recordID: id)

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .none      // invited people only, by name
        // On the *share*, not the root record. `CKShare.Metadata` carries the
        // share itself, so the other phone can read this before accepting
        // anything — which is what lets it say who they would become in the
        // confirmation, rather than after the fact. A field on the root would
        // need the zone already in their shared database to be readable, and
        // getting it there is the very thing being confirmed.
        share[CloudKitZone.invitedSlotKey] = slot.rawValue as CKRecordValue

        do {
            // `.changedKeys` and not `.ifServerRecordUnchanged`: the root here
            // may be a record this phone has never fetched, and an invitation
            // refused because the other phone pushed a moment ago is an
            // invitation that reads as broken. The payload is untouched by this
            // write, so there is nothing of the trip's to lose the race with.
            let (saves, _) = try await database.modifyRecords(saving: [root, share], deleting: [],
                                                              savePolicy: .changedKeys)
            // `modifyRecords` does not throw when a record failed to save — the
            // same reason `push` inspects these and `post` had to learn to.
            for (_, result) in saves {
                if case .failure(let error) = result { throw CloudKitZone.translate(error) }
            }
        } catch let error as SyncError {
            throw error
        } catch {
            throw CloudKitZone.translate(error)
        }
        guard let url = share.url else {
            throw SyncError.transport("iCloud didn't hand back an invitation link")
        }
        return url
    }

    /// What an invitation says, without joining anything.
    ///
    /// Reads only what `CKShare.Metadata` already carries — no network, no
    /// membership, nothing changed. It is separate from `accept` because the
    /// screen has to be able to name the trip and the slot *in* the
    /// confirmation, and a confirmation that has to join in order to describe
    /// what it is asking about is not a confirmation.
    ///
    /// Static because it touches no container: a phone can read an invitation
    /// on a build where CloudKit is switched off, and be told so plainly rather
    /// than have the link fail as though it were malformed.
    static func details(of metadata: CKShare.Metadata) -> Invitation? {
        guard let rootID = metadata.hierarchicalRootRecordID,
              let tripID = CloudKitZone.tripID(fromRecordName: rootID.recordName)
        else { return nil }
        let raw = metadata.share[CloudKitZone.invitedSlotKey] as? String
        return Invitation(tripID: tripID,
                          slot: raw.flatMap(Traveller.init(rawValue:)),
                          title: metadata.share[CKShare.SystemFieldKey.title] as? String)
    }

    /// Join the share for real. The zone lands in this phone's shared database,
    /// which is where `locate` will find it from the next round on.
    ///
    /// Accepting is still not *adopting*: the trip on this phone is dealt with
    /// by `TripStore.joinTrip`, and the split is deliberate — it keeps the
    /// irreversible half in the store, behind a confirmation, instead of in a
    /// system callback that fires the moment somebody taps a link.
    func accept(_ metadata: CKShare.Metadata) async throws {
        guard isAvailable else { throw SyncError.unavailable(unavailableReason ?? "") }
        do {
            _ = try await container.accept(metadata)
        } catch {
            throw CloudKitZone.translate(error)
        }
    }

    /// What an invitation turned out to be about.
    ///
    /// `Identifiable` on the trip and not on a minted UUID: it is read fresh
    /// from the metadata every time a link is followed, so an id of its own
    /// would be a new identity for the same invitation on every pass — the
    /// `BookSection` bug, and the reason anything derived here has it by
    /// default.
    struct Invitation: Equatable, Identifiable {
        var id: UUID { tripID }
        var tripID: UUID
        /// Nil when the share doesn't say — an older invitation, or one made by
        /// a build before the field existed. The caller asks the person rather
        /// than guessing: a wrong guess is both phones on the same slot, which
        /// is the bug the field was added to prevent.
        var slot: Traveller?
        var title: String?
    }
}
