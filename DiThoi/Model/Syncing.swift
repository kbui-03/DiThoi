import Foundation

// MARK: - What crosses between the phones

/// The shared half of a trip.
///
/// Deliberately *not* in here: journals and letters. The design promises the
/// journals stay private until the books print, and that the letters exist on
/// one phone only. Sync is exactly where promises like that get broken by
/// accident, so those collections never enter the payload at all.
struct SyncPayload: Codable, Equatable {
    /// Which trip this is. Only the live trip ever syncs — archived ones are
    /// cold storage — so a round still ships one payload however many trips are
    /// on the shelf. The id is what lets the transport key its record off the
    /// trip, and what lets the merge refuse a payload from a different one.
    var tripID: UUID
    var settings: TripSettings
    /// Names ride here rather than in `settings` because settings merge as one
    /// blob on one timestamp: a rename tucked inside them would win the dates,
    /// the budget and the currency along with it.
    var names: TripNames
    var itinerary: ItineraryDocument
    var expenses: [Expense]
    var stamps: [Stamp]
    var meetingPoint: StampedMeetingPoint
    /// Everywhere this trip has met, so tonight's point replacing last night's
    /// doesn't take last night's off both phones. Shared for the same reason
    /// the point itself is: either of them can be the one who typed it, and
    /// either of them can be the one picking it again a week later.
    var meetingPlaces: [MeetingPoint]
    var settlements: [SettlementProposal]
    /// What they wrote about each day, and the cards they hand to strangers.
    ///
    /// These are here because they became editable, and the sharing screen has
    /// always said "money, plans, the trail and the meeting point are shared
    /// both ways" — two people editing the same day on two phones with no merge
    /// is that sentence turned into a lie. They union by id like the expenses.
    ///
    /// Note what still isn't here: the journal and the letters. Those are absent
    /// by *not being fields*, and adding neighbours to the payload doesn't
    /// change that. Don't tidy them in.
    var dayPlans: [DayPlan]
    var showCards: [ShowCard]
    /// The travellers' **public** keys, so the observer can seal a letter drop
    /// to the phone it is addressed to.
    ///
    /// Adding a field here is a deliberate edit in the open — the reflection
    /// check in `Tools/VerifyTrip.swift` pins this list precisely so that it
    /// cannot happen by tidying. The argument for this one:
    ///
    /// A public key is public by construction. It is the only part of the
    /// letter channel that *should* travel, and it is what lets the sealing
    /// close a hole CloudKit cannot — a shared zone is readable by every
    /// participant and unconditionally by its owner, so the record name being
    /// "the address" was never a lock. The private half is in the Keychain and
    /// enters neither this nor `TripSnapshot`.
    ///
    /// What is still not here: the journal, the letters and the moments. This
    /// carries the means to seal a letter, and nothing about any letter.
    var letterKeys: LetterKeyring

    static func empty(tripID: UUID = UUID(), now: Date = Date()) -> SyncPayload {
        SyncPayload(
            tripID: tripID,
            settings: TripSettings(start: Date(), dayCount: 1, budget: 0,
                                   homeCurrency: .eur, updatedAt: .distantPast),
            names: .blank,
            itinerary: ItineraryDocument(legs: []),
            expenses: [], stamps: [],
            meetingPoint: StampedMeetingPoint(
                value: MeetingPoint(place: "", detail: "", localScript: "", setAt: .distantPast),
                updatedAt: .distantPast, setBy: .one),
            meetingPlaces: [],
            settlements: [],
            dayPlans: [], showCards: [],
            letterKeys: .blank
        )
    }

    init(tripID: UUID, settings: TripSettings, names: TripNames,
         itinerary: ItineraryDocument,
         expenses: [Expense], stamps: [Stamp], meetingPoint: StampedMeetingPoint,
         meetingPlaces: [MeetingPoint] = [],
         settlements: [SettlementProposal],
         dayPlans: [DayPlan] = [], showCards: [ShowCard] = [],
         letterKeys: LetterKeyring = .blank) {
        self.tripID = tripID
        self.settings = settings
        self.names = names
        self.itinerary = itinerary
        self.expenses = expenses
        self.stamps = stamps
        self.meetingPoint = meetingPoint
        self.meetingPlaces = meetingPlaces
        self.settlements = settlements
        self.dayPlans = dayPlans
        self.showCards = showCards
        self.letterKeys = letterKeys
    }

    /// Payloads written before trips had ids belong to whichever trip reads
    /// them — there was only one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tripID = try c.decodeIfPresent(UUID.self, forKey: .tripID) ?? UUID()
        settings = try c.decode(TripSettings.self, forKey: .settings)
        // Unnamed rather than guessed. Both slots carry `.distantPast`, so the
        // merge loses to any name the other phone has actually set.
        names = try c.decodeIfPresent(TripNames.self, forKey: .names) ?? .blank
        itinerary = try c.decode(ItineraryDocument.self, forKey: .itinerary)
        expenses = try c.decode([Expense].self, forKey: .expenses)
        stamps = try c.decode([Stamp].self, forKey: .stamps)
        meetingPoint = try c.decode(StampedMeetingPoint.self, forKey: .meetingPoint)
        // Same rule as the two below: a phone on the older build says nothing
        // about the history, and nothing said must not read as "we have met
        // nowhere" — the merge unions, so an erasure here would be one phone
        // forgetting on the other's behalf.
        meetingPlaces = try c.decodeIfPresent([MeetingPoint].self, forKey: .meetingPlaces) ?? []
        settlements = try c.decode([SettlementProposal].self, forKey: .settlements)
        // A payload pushed by a phone running the older build carries neither
        // of these. Absent has to mean "nothing to say about them", not
        // "empty" — the latter would let one un-updated phone clear both
        // collections off the other on the next round.
        dayPlans = try c.decodeIfPresent([DayPlan].self, forKey: .dayPlans) ?? []
        showCards = try c.decodeIfPresent([ShowCard].self, forKey: .showCards) ?? []
        // A phone on the older build publishes no key, and that has to read as
        // "hasn't said" rather than "has none" — `.blank` carries `.distantPast`
        // on both slots, so it loses the merge to any key actually set and never
        // clears one off the other phone.
        letterKeys = try c.decodeIfPresent(LetterKeyring.self, forKey: .letterKeys) ?? .blank
    }
}

/// The three answers the whole app is computed from. Merged whole rather than
/// per-field: they are set together on one screen, and a half-and-half result
/// (one phone's dates, the other's budget) is a trip neither of them chose.
struct TripSettings: Codable, Equatable {
    var start: Date
    var dayCount: Int
    var budget: Double
    var homeCurrency: Currency
    var updatedAt: Date
}

struct StampedMeetingPoint: Codable, Equatable {
    var value: MeetingPoint
    var updatedAt: Date
    var setBy: Traveller
}

// MARK: - Settling, which needs both of them

/// Settling is the one thing neither traveller can do alone, so it is a real
/// two-phase commit rather than a button that looks like one.
///
/// One proposes, the other confirms, and only then does each phone write the
/// `.transfer` — using `id` as the expense id, so applying it twice is
/// impossible even if both sides apply it at once.
struct SettlementProposal: Identifiable, Codable, Hashable {
    var id = UUID()
    var proposedBy: Traveller
    /// Who owes. Not inferable from `proposedBy` — either of them can raise a
    /// settlement regardless of which way the balance runs.
    var debtor: Traveller
    var amountHome: Double
    var paidIn: Currency
    var amountPaid: Double
    var note: String
    /// Where they were when it was raised.
    ///
    /// Carried rather than worked out when the transfer is written, because
    /// `applyConfirmedSettlements` runs on both phones and each used to stamp
    /// the line with its *own* `currentCountry`. Same expense id, two different
    /// countries, resolved by whichever `updatedAt` happened to be later.
    var country: String = ""
    var proposedAt: Date
    var confirmedBy: Traveller?
    var confirmedAt: Date?
    /// Agreed with both of them at one phone, which is the only way a build
    /// with no sync can clear a tab. Optional so that a proposal written
    /// before it existed still decodes — the synthesised decoder throws on a
    /// missing non-optional key — and so the history can say which it was.
    var confirmedInPerson: Bool?
    var cancelledAt: Date?
    var updatedAt: Date = .distantPast
    var deletedAt: Date?

    var isConfirmed: Bool { confirmedAt != nil }
    var isCancelled: Bool { cancelledAt != nil }
    var isPending: Bool { !isConfirmed && !isCancelled }

    /// Whoever didn't propose it is the one who has to agree.
    var awaiting: Traveller { proposedBy.other }
}

extension SettlementProposal: SyncableRecord {}

// MARK: - Merging

/// What the merge had to decide, so the app can tell them rather than silently
/// picking a winner.
struct SyncNotice: Identifiable, Equatable {
    var id = UUID()
    var text: String
}

enum SyncMerge {

    /// Merge two copies of the shared trip.
    ///
    /// - append-only collections (expenses, stamps, settlements, day plans,
    ///   show-this cards) union by id, last writer winning on a genuine clash;
    /// - the settings and the itinerary are single documents, last-writer-wins,
    ///   with the loser surfaced as a notice;
    /// - the meeting point is last-writer-wins and always surfaced, because a
    ///   silently-replaced meeting point is how two people end up in different
    ///   parts of a city.
    static func merge(local: SyncPayload, remote: SyncPayload, as role: Traveller)
        -> (payload: SyncPayload, notices: [SyncNotice]) {

        // Two trips are two trips. Merging a payload from a different one would
        // pour somebody else's ledger into this book, so the round is a no-op
        // and says so.
        guard remote.tripID == local.tripID else {
            return (local, [SyncNotice(text: "That's a different trip — nothing was merged.")])
        }

        // One calendar before anything is compared.
        //
        // Every dated record in a payload is measured from that payload's own
        // `settings.start`: `setStart` moves them together. When the two
        // phones disagree about the start, the side whose settings lose has
        // its dates moved into the winner's frame here, before the union.
        // `updatedAt` is left alone, so an edit or a delete on either phone
        // still wins or loses on its own merits. The obvious fix, re-stamping
        // every shifted record in `setStart`, would let one date move override
        // the other phone's unsynced edits and bring its deleted lines back.
        //
        // Without this the other phone took the new start and kept its own
        // unshifted copies (a tie keeps the local one), so every expense sat
        // N days off on one phone for good.
        var local = local
        var remote = remote
        let remoteWinsSettings = remote.settings.updatedAt > local.settings.updatedAt
        if remoteWinsSettings {
            local.shiftDates(by: TripShift.days(from: local.settings.start, to: remote.settings.start))
        } else {
            remote.shiftDates(by: TripShift.days(from: remote.settings.start, to: local.settings.start))
        }

        var notices: [SyncNotice] = []
        var merged = local

        merged.expenses = local.expenses.merged(with: remote.expenses)
        merged.stamps = local.stamps.merged(with: remote.stamps)
        merged.settlements = local.settlements.merged(with: remote.settlements)
        // No notice for either. A meeting point is surfaced because a silently
        // replaced one is how two people end up in different parts of a city;
        // a day's blurb or a phrase card is not that, and a banner every time
        // the other phone typed a line is a banner people stop reading.
        merged.dayPlans = local.dayPlans.merged(with: remote.dayPlans)
        merged.showCards = local.showCards.merged(with: remote.showCards)

        // Names first, so every notice below is written with the freshest one
        // rather than whatever this phone happened to be holding.
        merged.names = local.names.merged(with: remote.names)
        // Per slot, like the names, and for the same reason: two phones
        // publishing their own key in one round must both survive. No notice —
        // a key is plumbing, not something either of them chose.
        merged.letterKeys = local.letterKeys.merged(with: remote.letterKeys)
        let theirName = merged.names[role.other]

        if remoteWinsSettings {
            merged.settings = remote.settings
            if local.settings.updatedAt > .distantPast, remote.settings != local.settings {
                notices.append(SyncNotice(text: "\(theirName) changed the dates or the budget."))
            }
        }

        if remote.itinerary.updatedAt > local.itinerary.updatedAt {
            merged.itinerary = remote.itinerary
            if local.itinerary.updatedAt > .distantPast {
                notices.append(SyncNotice(text: "\(theirName) changed the itinerary."))
            }
        }

        // Where they have met unions; where they are meeting *tonight* is one
        // value and last writer wins. Both, because the losing point is still
        // a place either of them can walk to — losing the round is not the same
        // as never having been there.
        merged.meetingPlaces = local.meetingPlaces
            .remembering(remote.meetingPlaces)
            .remembering([local.meetingPoint.value, remote.meetingPoint.value])

        if remote.meetingPoint.updatedAt > local.meetingPoint.updatedAt {
            merged.meetingPoint = remote.meetingPoint
            if local.meetingPoint.updatedAt > .distantPast,
               remote.meetingPoint.value.place != local.meetingPoint.value.place {
                let time = remote.meetingPoint.updatedAt.text("HH:mm")
                notices.append(SyncNotice(
                    text: "\(merged.names[remote.meetingPoint.setBy]) set the meeting point to \(remote.meetingPoint.value.place) at \(time)."))
            }
        }

        return (merged, notices)
    }
}

// MARK: - Moving the calendar

/// A start-date move, as arithmetic.
///
/// One place for both callers: `TripStore.setStart`, which moves this phone's
/// records, and `SyncMerge`, which moves the losing payload's records into the
/// winning start's frame. A new dated collection joins here (§3.2).
enum TripShift {
    /// Whole trip days between two starts.
    static func days(from old: Date, to new: Date) -> Int {
        Calendar.trip.days(from: Calendar.trip.startOfDay(for: old),
                           to: Calendar.trip.startOfDay(for: new))
    }

    static func move(_ date: Date, by days: Int) -> Date {
        guard days != 0 else { return date }
        return Calendar.trip.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func expenses(_ list: [Expense], by days: Int) -> [Expense] {
        guard days != 0 else { return list }
        return list.map { var c = $0; c.date = move($0.date, by: days); return c }
    }

    static func stamps(_ list: [Stamp], by days: Int) -> [Stamp] {
        guard days != 0 else { return list }
        return list.map { var c = $0; c.earnedOn = $0.earnedOn.map { move($0, by: days) }; return c }
    }

    static func meetingPlaces(_ list: [MeetingPoint], by days: Int) -> [MeetingPoint] {
        guard days != 0 else { return list }
        return list.map { var c = $0; c.setAt = move($0.setAt, by: days); return c }
    }
}

extension SyncPayload {
    /// The shared half of `TripStore.setStart`: every dated record this payload
    /// carries, moved by whole days. Settings are not touched; the caller
    /// decides which start the dates now belong to.
    mutating func shiftDates(by days: Int) {
        guard days != 0 else { return }
        expenses = TripShift.expenses(expenses, by: days)
        stamps = TripShift.stamps(stamps, by: days)
        meetingPoint.value.setAt = TripShift.move(meetingPoint.value.setAt, by: days)
        meetingPlaces = TripShift.meetingPlaces(meetingPlaces, by: days)
    }
}

// MARK: - Transport

enum SyncState: Equatable {
    case unavailable(reason: String)
    case idle
    case syncing
    case failed(String)
}

/// A dumb pipe. It moves a payload; it does not decide anything.
///
/// Keeping merge out of the transport is what makes the interesting half
/// testable without a network, an account or a second phone.
protocol SyncTransport: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func push(_ payload: SyncPayload) async throws
    /// The shared copy of one trip, or nil if nobody has pushed it yet.
    ///
    /// Takes the trip rather than assuming there is only one. `SyncPayload`
    /// has carried a `tripID` since multi-trip landed, and its own comment said
    /// the id "lets the transport key its record off the trip" — which the
    /// transport then didn't do, keying everything off one fixed record name.
    func pull(tripID: UUID) async throws -> SyncPayload?

    /// A link that puts this trip on somebody else's phone.
    ///
    /// On the protocol rather than only on the CloudKit class because a caller
    /// that has to downcast to find out whether it can invite is a caller that
    /// will one day forget to. A transport with nobody to invite throws
    /// `.unavailable`, which is the same shape `TransportConformance.inert`
    /// already pins for a write that cannot happen.
    ///
    /// - Parameter slot: which traveller the person following the link becomes.
    ///   The invitation carries it because the alternative is both phones
    ///   defaulting to `.one` and then merging against the same slot — the
    ///   trip's names would be written by whichever synced last, and per-slot
    ///   stamping, which exists precisely so that cannot happen, would have
    ///   nothing to tell the two apart.
    func invitation(to tripID: UUID, named title: String,
                    inviting slot: Traveller) async throws -> URL
}

enum SyncError: LocalizedError {
    case unavailable(String)
    case transport(String)
    /// Somebody else wrote between this round's pull and its push.
    ///
    /// Its own case because it is the one failure that is not a failure: the
    /// answer is to merge again against what is now there, which is the
    /// coordinator's job. The transport only reports that the ground moved.
    case conflict
    /// Worth trying again, after this long.
    case retryable(String, after: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): why
        case .transport(let why): why
        case .conflict: "the other phone was writing at the same moment"
        case .retryable(let why, _): why
        }
    }

    /// Whether this is something waiting will fix. A signing-out or a full
    /// account needs a person; a busy service does not, and telling somebody
    /// about it would be telling them about weather.
    var isFatal: Bool {
        if case .unavailable = self { return true }
        return false
    }
}
