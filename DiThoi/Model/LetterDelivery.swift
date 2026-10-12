import Foundation
import CloudKit
import CryptoKit

// MARK: - Who a drop can be opened by

/// The travellers' public keys, one per slot.
///
/// Stamped and merged per slot for the reason `TripNames` is: two phones
/// publishing in the same round both have to survive, and a slot nobody has
/// answered for carries `.distantPast` and loses to one that has.
///
/// Only the *public* half is ever here. The private key lives in the Keychain —
/// see `LetterKeyStore` — so it is in no snapshot, no backup and no payload.
/// Putting a public key on the sync payload is not a leak; it is the one thing
/// it exists to be.
struct LetterKeyring: Codable, Equatable {
    var one: StampedKey
    var two: StampedKey

    static let blank = LetterKeyring(one: .unset, two: .unset)

    subscript(who: Traveller) -> Data? {
        get { (who == .one ? one : two).value }
        set {
            let stamped = StampedKey(value: newValue, updatedAt: Date())
            if who == .one { one = stamped } else { two = stamped }
        }
    }

    mutating func set(_ key: Data, for who: Traveller, at when: Date) {
        let stamped = StampedKey(value: key, updatedAt: when)
        if who == .one { one = stamped } else { two = stamped }
    }

    func merged(with other: LetterKeyring) -> LetterKeyring {
        LetterKeyring(one: StampedKey.newer(one, other.one),
                      two: StampedKey.newer(two, other.two))
    }
}

struct StampedKey: Codable, Equatable {
    var value: Data?
    var updatedAt: Date

    static let unset = StampedKey(value: nil, updatedAt: .distantPast)

    static func newer(_ mine: StampedKey, _ theirs: StampedKey) -> StampedKey {
        theirs.updatedAt > mine.updatedAt ? theirs : mine
    }
}

// MARK: - Sealing a drop to one traveller

/// Closes the hole CloudKit cannot.
///
/// The record name carries the recipient, and the old comment on
/// `CloudKitLetterDropTransport` claimed that meant "the wrong phone constructs
/// a name nothing answers to". It doesn't. Both travellers are participants in
/// the same shared zone and both know `tripID` — it is a field on the payload —
/// so the name is fully derivable. Worse, the zone's *owner* can read every
/// record in their own zone unconditionally, and the owner is whichever
/// traveller pushed the trip first. The addressing constrains this app's code
/// and nothing else.
///
/// So the drop is sealed before it leaves the writing phone, to a key only the
/// addressed traveller holds. The other traveller and the zone owner get
/// ciphertext, which is a promise that does not depend on who is running which
/// build.
enum LetterSeal {

    /// Bound into the key derivation, so a drop sealed for one trip and one slot
    /// cannot be opened as another even by somebody holding both keys.
    private static func info(tripID: UUID, recipient: Traveller) -> Data {
        Data("dithoi.letters.v1.\(tripID.uuidString).\(recipient.rawValue)".utf8)
    }

    enum Failure: Error, Equatable {
        /// The recipient hasn't published a key yet — usually because the trip
        /// has not synced to their phone since this build landed.
        case noRecipientKey
        case unusableKey
        case cannotOpen
    }

    /// Sealed with an ephemeral key pair, so the sender needs no key of their
    /// own and two drops to the same person share no key material. The public
    /// half rides in front of the ciphertext.
    static func seal(_ drop: LetterDrop, to recipient: Traveller,
                     using recipientPublicKey: Data?) throws -> Data {
        guard let recipientPublicKey else { throw Failure.noRecipientKey }
        guard let theirs = try? Curve25519.KeyAgreement
            .PublicKey(rawRepresentation: recipientPublicKey) else {
            throw Failure.unusableKey
        }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: theirs)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: info(tripID: drop.tripID, recipient: recipient),
            outputByteCount: 32)

        let plain = try JSONEncoder().encode(drop)
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw Failure.cannotOpen }
        return ephemeral.publicKey.rawRepresentation + combined
    }

    static func open(_ sealed: Data, as recipient: Traveller, tripID: UUID,
                     with privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> LetterDrop {
        let keyLength = 32
        guard sealed.count > keyLength else { throw Failure.cannotOpen }
        let ephemeralKey = sealed.prefix(keyLength)
        let body = sealed.dropFirst(keyLength)

        guard let theirs = try? Curve25519.KeyAgreement
            .PublicKey(rawRepresentation: ephemeralKey) else {
            throw Failure.cannotOpen
        }
        guard let shared = try? privateKey.sharedSecretFromKeyAgreement(with: theirs) else {
            throw Failure.cannotOpen
        }
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: info(tripID: tripID, recipient: recipient),
            outputByteCount: 32)

        guard let box = try? AES.GCM.SealedBox(combined: Data(body)),
              let plain = try? AES.GCM.open(box, using: key),
              let drop = try? JSONDecoder().decode(LetterDrop.self, from: plain) else {
            throw Failure.cannotOpen
        }
        return drop
    }
}

// MARK: - What crosses from home

/// A letter as it travels: writer → traveller, one direction, once.
///
/// The writing side never learns whether a letter was read. `SyncPayload`
/// holds that by not carrying letters at all; this type holds the other half by
/// carrying no field that could bring the answer back. There is no `openedOn`,
/// no `receivedAt`, no read flag — absent from the type rather than filtered at
/// the boundary, so a later field can't leak one.
///
/// It is also why delivery is a separate channel rather than another field on
/// the sync payload: sync is symmetric, and this must not be.
struct SealedLetter: Identifiable, Codable, Hashable {
    var id: UUID
    var number: Int
    var title: String
    var writtenOn: Date
    var sealedAt: Date
    var condition: LetterCondition
    var hint: String
    var paragraphs: [String]
    var signature: String
    var secretCondition: Bool

    init(_ letter: Letter, sealedAt: Date) {
        id = letter.id
        number = letter.number
        title = letter.title
        writtenOn = letter.writtenOn
        self.sealedAt = sealedAt
        condition = letter.condition
        hint = letter.hint
        paragraphs = letter.paragraphs
        signature = letter.signature
        secretCondition = letter.secretCondition
    }
}

extension Letter {
    /// The traveller's copy of a letter that just arrived. Always unopened:
    /// arriving and being read are different events, and only the phone that
    /// holds it records the second.
    init(received: SealedLetter, at now: Date) {
        self.init(id: received.id,
                  number: received.number,
                  title: received.title,
                  writtenOn: received.writtenOn,
                  condition: received.condition,
                  hint: received.hint,
                  openedPlace: nil,
                  openedOn: nil,
                  paragraphs: received.paragraphs,
                  signature: received.signature,
                  sealedAt: received.sealedAt,
                  receivedAt: now,
                  secretCondition: received.secretCondition)
    }
}

/// Everything the observer has sealed for one traveller on one trip. Whole-set
/// rather than incremental: twelve letters is a few kilobytes, and a set that
/// can only be replaced wholesale cannot half-arrive.
struct LetterDrop: Codable, Equatable {
    var tripID: UUID
    /// Which traveller this post is for.
    ///
    /// The box is keyed on this as well as the trip, so the other traveller
    /// doesn't fetch a drop and decline to draw it — they fetch nothing, from
    /// an address that says nothing about whether any other address exists.
    /// Routing rather than rendering.
    var recipient: Traveller
    var letters: [SealedLetter]
    var updatedAt: Date

    static func empty(tripID: UUID, recipient: Traveller) -> LetterDrop {
        LetterDrop(tripID: tripID, recipient: recipient, letters: [], updatedAt: .distantPast)
    }

    init(tripID: UUID, recipient: Traveller, letters: [SealedLetter], updatedAt: Date) {
        self.tripID = tripID
        self.recipient = recipient
        self.letters = letters
        self.updatedAt = updatedAt
    }

    /// Hand-written so a drop posted before the box had addresses still decodes.
    /// There was only one recipient then, and it was this one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        recipient = try c.decodeIfPresent(Traveller.self, forKey: .recipient) ?? .one
        letters = try c.decode([SealedLetter].self, forKey: .letters)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// A pipe that only goes one way, to one person. The traveller it is addressed
/// to can `collect`; only the observer's phone can `post`.
protocol LetterDropTransport: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    /// Why not, in words somebody at home can act on. `nil` when it is
    /// available.
    ///
    /// The writing side is the half of the app with nobody else to notice a
    /// failure, so it is the half that needs a sentence it can print.
    var unavailableReason: String? { get }
    /// - Parameter sealingTo: the recipient's public key, from the synced
    ///   keyring. The drop is sealed to it before it leaves this phone, so a
    ///   transport that puts letters somewhere the other traveller can reach —
    ///   which the CloudKit one does, since a shared zone is shared — still
    ///   hands them nothing they can read. A transport that cannot seal must
    ///   refuse rather than post in clear.
    func post(_ drop: LetterDrop, to recipient: Traveller, sealingTo key: Data?) async throws
    /// - Parameter opening: this phone's private key. Nil where sealing never
    ///   applied.
    func collect(tripID: UUID, for recipient: Traveller,
                 opening key: Curve25519.KeyAgreement.PrivateKey?) async throws -> LetterDrop?
}

/// Which postal service this build actually has.
///
/// A function rather than a line inside `TripStore.init`, so the letters pick
/// their transport the way sync does: turning CloudKit on has to move both, not
/// move the trip and leave the letters writing to a file on this phone.
///
/// `cloudAvailable` is passed in rather than read here so both branches can be
/// checked — `isAvailable` reads the bundle, and the checks can't forge one.
func chooseLetterTransport(cloudAvailable: Bool) -> LetterDropTransport {
    cloudAvailable ? CloudKitLetterDropTransport() : LoopbackLetterDropTransport()
}

/// File-backed stand-in for the real thing, exactly as `LoopbackSyncTransport`
/// stands in for CloudKit — and for the same reason: it lets the interesting
/// half be verified without an account or a second device.
///
/// One file per address. When this grows a CloudKit sibling the address belongs
/// in the record name for the same reason it is in the filename here: a phone
/// must not be able to read a box it isn't on.
final class LoopbackLetterDropTransport: LetterDropTransport, @unchecked Sendable {
    let name = "This phone (loopback)"

    /// True: the box works and really holds post. What it isn't is a box on
    /// another phone, which is `unavailableReason`'s job — a channel reporting
    /// itself unavailable would leave `chooseLetterTransport` nothing to fall
    /// back to.
    var isAvailable: Bool { true }

    /// Said plainly: home mode rests on sealing a letter sending it somewhere,
    /// and on this build it doesn't leave the phone.
    var unavailableReason: String? {
        "Letters aren't switched on for this build, so sealed ones wait on this phone."
    }

    private let directory: URL
    private let box: String
    /// The same serialisation `LoopbackSyncTransport` has. This is captured
    /// across an `await` from `@MainActor`, which under Swift 6 is a diagnostic
    /// and under 5.0 is silent.
    private let queue = DispatchQueue(label: "dithoi.loopback.letters")

    init(named box: String = "letters") {
        directory = Storage.directory(".")
        self.box = box
    }

    private func url(for recipient: Traveller) -> URL {
        directory.appendingPathComponent("\(box)-\(recipient.rawValue).json")
    }

    /// Unsealed, and that is correct here rather than an oversight.
    ///
    /// The file is in this app's own container on this one phone. Sealing it
    /// would encrypt a drop against a key held by the same process that wrote
    /// it, which protects nobody and would make the loopback stop being a
    /// faithful stand-in — the interesting half is the addressing and the merge,
    /// and both have to stay exercisable on a machine with no Developer account.
    /// The seal exists because a *shared CloudKit zone* is readable by people
    /// who are not the recipient. A file here is not.
    func post(_ drop: LetterDrop, to recipient: Traveller, sealingTo key: Data?) async throws {
        let data = try JSONEncoder().encode(drop)
        let target = url(for: recipient)
        try queue.sync { try data.write(to: target, options: .atomic) }
    }

    func collect(tripID: UUID, for recipient: Traveller,
                 opening key: Curve25519.KeyAgreement.PrivateKey?) async throws -> LetterDrop? {
        let source = url(for: recipient)
        guard let data = queue.sync(execute: { try? Data(contentsOf: source) }),
              let drop = try? JSONDecoder().decode(LetterDrop.self, from: data)
        else { return nil }
        // A drop for a different trip, or addressed to somebody else, is
        // somebody else's post. The address is already in the path; this is the
        // same guard the trip id gets, and it is what the CloudKit sibling will
        // lean on when the record name is the only thing carrying the address.
        guard drop.tripID == tripID, drop.recipient == recipient else { return nil }
        return drop
    }

    /// Every address, not one file — a reset that leaves a box behind is not a
    /// reset, and `DebugScreen.reset()` is what first launch is tested through.
    func erase() {
        for who in Traveller.allCases {
            try? FileManager.default.removeItem(at: url(for: who))
        }
    }
}

// MARK: - The real one

/// Letters, over iCloud.
///
/// **Inert as it stands**, for the same reason and behind the same flag as
/// `CloudKitSyncTransport`, and never executed.
///
/// It exists because the loopback above writes to a file on *this* device, so
/// until now the writing side could not deliver a letter to another phone at
/// all — home mode was a complete feature with no postal service, and turning
/// CloudKit on for the trip would not have changed that.
///
/// ## The address is the record name, and that is routing, not a lock
///
/// `Letters-<tripID>-<recipient>`, in the same shared zone the trip uses. This
/// used to claim that the wrong phone "constructs a name nothing answers to".
/// It doesn't, and the claim was the dangerous part:
///
/// - both travellers are participants in the same shared zone, and both know
///   `tripID` — it is a field on `SyncPayload` — so the name is fully derivable;
/// - the zone's **owner** can read every record in their own zone regardless of
///   any share, and the owner is whichever traveller pushed the trip first.
///
/// So the addressing is what keeps *this app's code* from fetching a box it
/// isn't on — which is worth having, because it is what stops the other
/// traveller's phone from learning a box exists. It is not what keeps the
/// letters unreadable. `LetterSeal` is: the drop is sealed to a key only the
/// addressed traveller holds before it leaves the writing phone, so what is in
/// the zone is ciphertext to everybody else including the owner.
///
/// The record body also rides in `encryptedValues`, which keeps it from
/// CloudKit's own servers. That had to be decided before the schema existed —
/// a field's encryption cannot be changed afterwards — and nothing here has ever
/// run, so this is the only moment it was free.
///
/// The `SealedLetter` this carries still has nowhere to put a read receipt, and
/// there is still no route back up the channel.
final class CloudKitLetterDropTransport: LetterDropTransport, @unchecked Sendable {

    let name = "iCloud, one way"

    private let recordType = "LetterDrop"
    private let zone = CloudKitZone()

    var isAvailable: Bool { CloudKitZone.isEnabled }

    var unavailableReason: String? {
        isAvailable ? nil : "This build has no iCloud container, so sealed letters wait on this phone."
    }

    private func recordID(tripID: UUID, recipient: Traveller, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "Letters-\(tripID.uuidString)-\(recipient.rawValue)", zoneID: zone)
    }

    /// The zone the *trip* lives in, which is the zone the letters ride in.
    ///
    /// `creatingIfNeeded: false`, always. The observer is a participant rather
    /// than the owner, so there is nothing here for them to create: if `locate`
    /// can't find the trip, the trip hasn't been shared with this phone and a
    /// throw is the right answer. Passing `true` would mint a zone in the
    /// writer's own private database and post into it — a write that reports
    /// success into a box no traveller can read.
    private func locate(_ tripID: UUID) async throws -> (CKDatabase, CKRecordZone.ID) {
        do {
            return try await zone.locate(tripID, creatingIfNeeded: false)
        } catch {
            throw SyncError.transport("couldn't reach the letter box — is the trip shared yet?")
        }
    }

    func post(_ drop: LetterDrop, to recipient: Traveller, sealingTo key: Data?) async throws {
        guard isAvailable else { throw SyncError.unavailable(unavailableReason ?? "") }
        // Sealed before it goes anywhere, and refused rather than posted in
        // clear when it can't be. A drop this phone cannot seal is a drop the
        // other traveller and the zone owner could read, and "the letters went
        // out" would then be true and wrong at the same time.
        let data: Data
        do {
            data = try LetterSeal.seal(drop, to: recipient, using: key)
        } catch LetterSeal.Failure.noRecipientKey {
            throw SyncError.transport(
                "Their phone hasn't synced since the letters were switched on, so there's nowhere sealed to send these yet. They'll go the next time it does.")
        } catch {
            throw SyncError.transport("couldn't seal the letters for sending")
        }
        let (database, zoneID) = try await locate(drop.tripID)
        let id = recordID(tripID: drop.tripID, recipient: recipient, in: zoneID)

        // One retry, in here rather than above. `SyncCoordinator` answers a
        // `.conflict` by running the whole round again; the letters have no
        // coordinator and nothing to merge — the drop is the entire sealed set —
        // so the resolution is simply to re-read the server's record and write
        // over it.
        for attempt in 0..<2 {
            let record = (try? await database.record(for: id))
                ?? CKRecord(recordType: recordType, recordID: id)
            // `encryptedValues`, not a plain field. The body is already sealed
            // to the recipient, so this is belt over braces — but it costs
            // nothing and it cannot be added later: CloudKit will not let a
            // field change between encrypted and not once the schema exists.
            // Nothing here has ever run, so this is the only moment it is free.
            record.encryptedValues["drop"] = data
            record["updatedAt"] = drop.updatedAt as CKRecordValue
            // Part of the shared hierarchy, or a participant cannot write it.
            //
            // This was missing, and it is why `post` would have failed on the
            // very first real run: the observer is always a participant — only
            // the trip may pass `creatingIfNeeded: true` — and a participant may
            // only save records that hang off the shared root. A top-level
            // record in somebody else's zone is not theirs to create.
            //
            // The parent is the trip record, which is the same anchor
            // `CloudKitZone` uses to decide the zone is the right one.
            record.parent = CKRecord.Reference(
                recordID: CloudKitZone.tripRecordID(drop.tripID, in: zoneID),
                action: .none)

            do {
                // Whole-set replacement, so a drop cannot half-arrive — the
                // same reason `LetterDrop` carries every sealed letter rather
                // than a delta. `.ifServerRecordUnchanged` rather than
                // `.changedKeys` for the reason `push` uses it: a write built on
                // a stale read should be refused, not silently win.
                let (saves, _) = try await database.modifyRecords(
                    saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
                // The result has to be read. `modifyRecords` returns a
                // dictionary of per-record outcomes and does not throw when one
                // of them failed, so the old `(try? …) != nil` treated a refused
                // write as a delivered letter.
                for (_, result) in saves {
                    if case .failure(let error) = result { throw CloudKitZone.translate(error) }
                }
                return
            } catch let error as SyncError {
                guard case .conflict = error, attempt == 0 else { throw error }
            } catch {
                throw CloudKitZone.translate(error)
            }
        }
        // Both attempts conflicted. Falling out of the loop without this is a
        // post that reports success having written nothing — the same shape as
        // the bug above, one level up.
        throw SyncError.conflict
    }

    func collect(tripID: UUID, for recipient: Traveller,
                 opening key: Curve25519.KeyAgreement.PrivateKey?) async throws -> LetterDrop? {
        guard isAvailable, let key else { return nil }
        // A trip this phone can't find is not an error on the reading side — it
        // is a phone with no post, which is what most phones are. Only the
        // poster needs to be told the trip isn't shared yet.
        guard let (database, zoneID) = try? await locate(tripID) else { return nil }
        do {
            let record = try await database.record(
                for: recordID(tripID: tripID, recipient: recipient, in: zoneID))
            guard let data = record.encryptedValues["drop"] as? Data,
                  let drop = try? LetterSeal.open(data, as: recipient,
                                                  tripID: tripID, with: key)
            else { return nil }
            // The address is already in the name; this is the same belt-and-
            // braces the loopback keeps, and it is what the record name will
            // be leaning on if either ever changes.
            guard drop.tripID == tripID, drop.recipient == recipient else { return nil }
            return drop
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Nothing at this address. Which is also what the *wrong* phone
            // gets, and the two have to be indistinguishable — a phone that
            // could tell "empty" from "not yours" has learned the box exists.
            return nil
        } catch let error as SyncError {
            throw error
        } catch {
            throw CloudKitZone.translate(error)
        }
    }
}

// MARK: - When a sealed letter opens

/// Everything a condition needs to know, gathered once so the rule is a pure
/// function of the trip rather than of whichever screen asked.
struct LetterMoment {
    var dayNumber: Int
    var city: String
    var earnedStampCodes: Set<String>
    var earnedStampCities: Set<String>
    var allStampsEarned: Bool
    /// True on the round where the letter has only just reached the phone.
    var justArrived: Bool
    /// Every waypoint the trip still has, earned or not.
    ///
    /// Sealed conditions name a code or a place as a *string*, and sealing is
    /// final — so a waypoint that is removed leaves a letter pointing at
    /// something that no longer exists. `canStillFire` used to answer "yes" for
    /// exactly that case, because "not earned yet" and "will never exist" are
    /// the same sentence if all you have is the earned set. Now they aren't.
    var knownStampCodes: Set<String> = []
    /// Every place a condition could still name: the waypoints' cities and the
    /// stops on the itinerary.
    var knownPlaces: Set<String> = []
}

extension LetterCondition {
    /// Whether this condition is met right now.
    func isMet(_ moment: LetterMoment) -> Bool {
        switch self {
        case .place(let name):
            // Arriving is the stamp, not the itinerary — standing in Đà Nẵng
            // does not open the Hội An letter.
            return moment.earnedStampCities.contains(name) || moment.city == name
        case .day(let day):
            return moment.dayNumber >= day
        case .stamp(let code):
            return moment.earnedStampCodes.contains(code)
        case .finalStamp:
            return moment.allStampsEarned
        case .nextOnline:
            return moment.justArrived
        case .hidden:
            return false
        }
    }

    /// J9 · whether a letter sealed *today* could still fire.
    ///
    /// A letter only lands the next time the traveller's phone is online, so
    /// keying it to somewhere they have already been keys it to something that
    /// will not happen again. The picker greys those out rather than accepting
    /// a letter that would silently never open.
    func canStillFire(_ moment: LetterMoment) -> Bool {
        switch self {
        case .place(let name):
            // Gone from the trip is not the same as not reached yet, and until
            // waypoints could be removed there was no way to tell them apart.
            guard moment.knownPlaces.isEmpty || moment.knownPlaces.contains(name) else { return false }
            return !moment.earnedStampCities.contains(name)
        case .day(let day):
            return day > moment.dayNumber
        case .stamp(let code):
            guard moment.knownStampCodes.isEmpty || moment.knownStampCodes.contains(code) else { return false }
            return !moment.earnedStampCodes.contains(code)
        case .finalStamp:
            return !moment.allStampsEarned
        case .nextOnline:
            return true
        case .hidden:
            return false
        }
    }

    /// Why it can't, in the words J9 uses on the greyed-out chip.
    func deadReason(_ moment: LetterMoment) -> String? {
        guard !canStillFire(moment) else { return nil }
        switch self {
        case .place(let name):
            return moment.knownPlaces.isEmpty || moment.knownPlaces.contains(name)
                ? "already passed" : "no longer on the trip"
        case .stamp(let code):
            return moment.knownStampCodes.isEmpty || moment.knownStampCodes.contains(code)
                ? "already passed" : "that stamp is gone"
        case .day: return "already gone"
        case .finalStamp: return "already earned"
        case .nextOnline: return nil
        case .hidden: return "no condition yet"
        }
    }
}

// MARK: - The writing side's view of its own work

/// J5 · the board. Where twelve letters land across sixty-one days, and where
/// the silences are.
struct LetterSchedule {
    struct Placement: Identifiable {
        var id: UUID
        var number: Int
        var title: String
        /// Best guess at which trip day it lands on, for drawing the line.
        var day: Int
        var sealed: Bool
        var condition: LetterCondition
    }

    struct Silence: Identifiable, Hashable {
        var fromDay: Int
        var toDay: Int
        var days: Int { max(toDay - fromDay, 0) }
        /// A silence *is* its span. A fresh UUID each time the schedule is
        /// rebuilt would mean nothing could ever be compared against it — and
        /// the schedule is a computed property, so it is rebuilt constantly.
        var id: String { "\(fromDay)-\(toDay)" }
    }

    var placements: [Placement]
    var silences: [Silence]
    var sealedCount: Int
    var total: Int

    /// - Parameter dayForPlace: where a named place falls on the itinerary,
    ///   which only the store knows.
    static func build(letters: [Letter], dayCount: Int,
                      dayForPlace: (String) -> Int?,
                      dayForStamp: (String) -> Int?,
                      quietThreshold: Int = 7) -> LetterSchedule {
        let placements: [Placement] = letters
            .sorted { $0.number < $1.number }
            .map { letter in
                let day: Int
                switch letter.condition {
                case .day(let value): day = value
                case .place(let name): day = dayForPlace(name) ?? dayCount
                case .stamp(let code): day = dayForStamp(code) ?? dayCount
                case .finalStamp: day = dayCount
                case .nextOnline, .hidden: day = 1
                }
                return Placement(id: letter.id, number: letter.number, title: letter.title,
                                 day: min(max(day, 1), dayCount), sealed: letter.isSealed,
                                 condition: letter.condition)
            }

        // Gaps between consecutive landings, plus the two ends.
        var silences: [Silence] = []
        let days = placements.map(\.day).sorted()
        var cursor = 1
        for day in days {
            if day - cursor >= quietThreshold { silences.append(Silence(fromDay: cursor, toDay: day)) }
            cursor = max(cursor, day)
        }
        if dayCount - cursor >= quietThreshold {
            silences.append(Silence(fromDay: cursor, toDay: dayCount))
        }

        return LetterSchedule(placements: placements, silences: silences,
                              sealedCount: placements.filter(\.sealed).count,
                              total: placements.count)
    }
}
