import Foundation
import Combine

/// The whole trip, on the phone. The travellers set the dates, the budget and
/// the currency they think in; everything else is worked out from those three
/// answers, persisted locally, and — for the half they share — merged with the
/// other phone.
@MainActor
final class TripStore: ObservableObject {

    // Which trip, and whose phone
    @Published private(set) var tripID: UUID { didSet { save() } }
    @Published var tripName: String { didSet { save() } }
    /// Either traveller, or the observer who stays home and writes. `role`
    /// below is the traveller identity the ledger and the journal use; in home
    /// mode it is the traveller being written *to*.
    @Published var participant: Participant { didSet { save() } }
    /// What the two slots are called, and what the observer calls themselves.
    /// Not routed through `touchSettings()`: a rename isn't an answer about the
    /// trip, and settings merge as one blob, so it would win the dates and the
    /// budget as well.
    @Published var names: TripNames { didSet { save() } }
    /// Whether this trip arrived filled in. Fixed at creation.
    @Published private(set) var origin: TripOrigin { didSet { save() } }
    /// Not routed through `touchSettings()` either: the switches never leave
    /// this phone, so a stamp would only let a local toggle win the other
    /// phone's real budget change.
    @Published var features: TripFeatures { didSet { save(); bookInputsChanged() } }
    @Published private(set) var template: TripTemplate { didSet { save() } }
    @Published private(set) var closedOn: Date? { didSet { save() } }

    // Set by the travellers
    /// Two senses in one flag: onboarding is finished, and a trip is running.
    /// They only stay in step because every path that creates a trip collects
    /// everything onboarding would have asked for, and that path is always
    /// `ArrivalFlow`: `beginNextTrip` sets this false.
    @Published var hasOpened: Bool { didSet { save() } }
    @Published var role: Traveller { didSet { save(); bookInputsChanged() } }
    @Published private(set) var start: Date { didSet { save() } }
    @Published private(set) var dayCount: Int { didSet { save() } }
    @Published var budget: Double { didSet { touchSettings(); save() } }
    @Published var homeCurrency: Currency { didSet { touchSettings(); save() } }
    /// When the three answers above last changed, for merging.
    @Published private(set) var settingsUpdatedAt: Date { didSet { save() } }

    // Shared with the other phone
    /// A day nobody's stop covered was filed by its number; once a stop covers
    /// it, that is where it is filed — `backfillPlanKeys()` after every edit.
    @Published var itinerary: ItineraryDocument {
        didSet { backfillPlanKeys(); backfillWaypointPositions(); save(); bookInputsChanged() }
    }
    @Published var expenses: [Expense] { didSet { save() } }
    @Published var stamps: [Stamp] { didSet { save(); bookInputsChanged() } }
    @Published private(set) var meetingPoint: StampedMeetingPoint { didSet { save() } }
    /// Everywhere this trip has agreed to meet, most recent first.
    ///
    /// `meetingPoint` above is one value — there is one place they are standing
    /// tonight — so the history is kept separately, and setting tomorrow's
    /// doesn't lose yesterday's. Shared for the same reason the point is:
    /// either of them may have been the one who typed it.
    @Published private(set) var meetingPlaces: [MeetingPoint] { didSet { save(); bookInputsChanged() } }
    @Published private(set) var settlements: [SettlementProposal] { didSet { save() } }

    // This phone only — never enters a sync payload
    @Published var journal: [JournalEntry] { didSet { save(); bookInputsChanged() } }
    @Published var letters: [Letter] { didSet { save() } }
    /// Who the letters on this phone belong to — the slot they were addressed
    /// to, or the observer who wrote them.
    ///
    /// Its own field because nothing else answers the question. `role` is the
    /// addressee on a traveller's phone and the *recipient* on the observer's,
    /// so `adopt` asking `traveller != role` let an observer writing to slot two
    /// become traveller two and keep every letter they had written. And
    /// `participant` can't stand in either: `ArrivalFlow.commitNames()` writes
    /// it on every continue, reversibly, precisely so the flow can draw home
    /// mode before anything has been committed — so by the time the
    /// irreversible half runs it already reads as the new person.
    ///
    /// This moves only when the letterbox is actually re-established, which is
    /// what makes it safe to compare against.
    @Published private(set) var lettersBelongTo: Participant { didSet { save() } }
    /// The travellers' public keys as last merged. Persisted so the observer
    /// doesn't have to wait for a sync round before sealing what they wrote
    /// tonight.
    ///
    /// Trailing underscore because `letterKeys` is the Keychain store above and
    /// this is the synced ring — two different halves of the same channel, and
    /// naming them the same thing is how somebody seals to their own key.
    @Published private(set) var letterKeys_: LetterKeyring { didSet { save() } }
    /// What they stopped for that nobody planned. Local, like the journal: it
    /// is written to be read later, in a book, not sent anywhere tonight.
    @Published private(set) var moments: [Moment] { didSet { save(); bookInputsChanged() } }
    @Published var separatedSince: Date? { didSet { save() } }
    /// The hour the evening prompt has learned, and the nights it has already
    /// asked about. Never synced: it's a habit, not a fact about the trip.
    @Published private(set) var ritualClock: RitualClock { didSet { save() } }
    @Published private(set) var backfill: BackfillOffers { didSet { save() } }
    /// Tags somebody added to the chip row themselves. The composer offered
    /// eight fixed words and whatever had been tagged before — which could
    /// only ever be those eight — so a trip's vocabulary was set for good.
    /// Kept across trips: they are this person's words, not this trip's.
    @Published private(set) var customTags: [String] { didSet { save() } }
    /// Countries whose "that's done" moment Today has already shown. Asked
    /// once, like the backfill: a moment that repeats is a reminder.
    @Published private(set) var countriesMarkedDone: Set<UUID> { didSet { save() } }
    /// How many times Money has offered to set a budget on a trip without one.
    /// Three and it stops: a line that asks on every visit is a line people
    /// learn not to read, and the budget is still in Papers → Trip → Setup. This
    /// phone's habit, not a fact about the trip, so it never syncs.
    @Published private(set) var budgetNudgeShows: Int { didSet { save() } }

    /// What happened the last time this phone tried to post its sealed letters,
    /// and when it last succeeded.
    ///
    /// Neither persisted nor synced: it is this phone's account of its own
    /// outgoing post. Every foreground re-posts, so a failure is something to
    /// say once rather than something to store.
    ///
    /// There is no reading equivalent. Reporting a failed *fetch* to a
    /// traveller would tell them a letter box exists, which is what the
    /// addressing withholds.
    @Published private(set) var lastPostFailure: String?
    @Published private(set) var lastPostedAt: Date?

    /// Live where there's signal, cached where there isn't.
    let rates: RatesService
    /// Merges the shared half of the trip with the other phone.
    let sync: SyncCoordinator
    /// Only asked for while Separated is on.
    let location: LocationService
    /// One-way, home → here. Separate from `sync`, which is symmetric.
    let letterPost: LetterDropTransport
    /// This phone's half of the letter channel. The private key lives in the
    /// Keychain and is never persisted with the trip, so it is in no snapshot,
    /// no backup and no payload.
    let letterKeys: LetterKeyStore
    /// Posts the one evening prompt, when there is a device to post it to.
    let ritual: RitualScheduler
    /// Every trip that isn't this one.
    let library: TripLibrary
    /// Where a typed city is. A closure so the 2.8 MB list is read the first
    /// time a position is wanted, not every time a store opens a trip; the
    /// checks hand in a fixture.
    var cityList: () -> CityPositions? = { CityPositions.bundled }

    // What this trip came with. Stored per trip rather than read from a shared
    // constant, so a trip created from scratch opens with its own papers and
    // day plans rather than somebody else's.
    @Published private(set) var dayPlans: [DayPlan] { didSet { save() } }
    @Published private(set) var documents: [TravelDocument] { didSet { save() } }
    @Published private(set) var showCards: [ShowCard] { didSet { save() } }
    @Published private(set) var sharingRules: [SharingRule] { didSet { save() } }

    private var subscriptions: [AnyCancellable] = []
    /// The one write waiting to happen. See `save()`.
    private var pendingSave: Task<Void, Never>?
    nonisolated static let storeKey = "dithoi.trip.v3"

    /// Where this store reads and writes itself, or `nil` for a store that does
    /// neither.
    ///
    /// A `nil` key is what makes an archived trip openable. Every `@Published`
    /// here carries `didSet { save() }`, so a second store built from a frozen
    /// snapshot would otherwise write that snapshot over the live trip on its
    /// first mutation. Loading is gated on the same value, so a non-persisting
    /// store can't pick the live trip up either.
    private let storeKey: String?

    /// Where "now" comes from. Everything time-dependent in this class reads
    /// `now`, never `Date()`, so a check can put the trip on its last day or on
    /// the other side of a flight.
    private let clock: () -> Date

    /// There is a saved trip on this phone that this build could not read.
    ///
    /// When it is set the store refuses to write, so whatever is down there
    /// survives to be recovered by a later build. Published so the app can say
    /// so on screen rather than running on an empty trip in silence.
    @Published private(set) var storageFault = false

    // MARK: - Init

    /// - Parameters:
    ///   - storeKey: where to persist. `nil` means this store never touches
    ///     disk, in either direction.
    ///   - snapshot: open this exact trip rather than whatever is saved. Used
    ///     by the shelf to open a closed trip without disturbing the live one,
    ///     and by the checks to start from a fixture.
    ///   - clock: what "now" means. Injectable so that midnight, the end of the
    ///     trip, a daylight-saving boundary and a flight into another timezone
    ///     are all reachable from a check — otherwise they are only reachable
    ///     by waiting.
    init(storeKey: String? = TripStore.storeKey,
         snapshot: TripSnapshot? = nil,
         clock: @escaping () -> Date = { Date() },
         rates: RatesService? = nil,
         sync: SyncCoordinator? = nil,
         location: LocationService? = nil,
         letterPost: LetterDropTransport? = nil,
         ritual: RitualScheduler? = nil,
         library: TripLibrary? = nil) {
        self.storeKey = storeKey
        self.clock = clock
        let rates = rates ?? RatesService()
        let sync = sync ?? SyncCoordinator()
        let location = location ?? LocationService()
        self.rates = rates
        self.sync = sync
        self.location = location
        // Letters pick their transport the way sync does, so switching iCloud
        // on moves the letters along with the trip rather than leaving them
        // writing to a file on this phone.
        self.letterPost = letterPost
            ?? chooseLetterTransport(cloudAvailable: CloudKitLetterDropTransport().isAvailable)
        self.letterKeys = LetterKeyStore()
        #if canImport(UserNotifications) && canImport(UIKit)
        self.ritual = ritual ?? LocalRitualScheduler()
        #else
        self.ritual = ritual ?? SilentRitualScheduler()
        #endif
        self.library = library ?? TripLibrary()

        // Three states, not two. Something saved that won't decode must never
        // be treated as nothing saved, or launch quietly starts a fresh trip
        // over the top of somebody's two months.
        let onDisk: TripSnapshot.Stored = snapshot.map { .trip($0) }
            ?? storeKey.map { TripSnapshot.stored(key: $0) }
            ?? .none
        if case .unreadable = onDisk { storageFault = true } else { storageFault = false }

        if case .trip(let snapshot) = onDisk {
            tripID = snapshot.tripID
            tripName = snapshot.tripName
            participant = snapshot.participant
            names = snapshot.names
            origin = snapshot.origin
            features = snapshot.features
            template = snapshot.template
            closedOn = snapshot.closedOn
            hasOpened = snapshot.hasOpened
            role = snapshot.role
            start = snapshot.start
            dayCount = snapshot.dayCount
            budget = snapshot.budget
            homeCurrency = snapshot.homeCurrency
            settingsUpdatedAt = snapshot.settingsUpdatedAt
            itinerary = snapshot.itinerary
            expenses = snapshot.expenses
            stamps = snapshot.stamps
            meetingPoint = snapshot.meetingPoint
            meetingPlaces = snapshot.meetingPlaces
            settlements = snapshot.settlements
            journal = snapshot.journal
            letters = snapshot.letters
            lettersBelongTo = snapshot.lettersBelongTo
            letterKeys_ = snapshot.letterKeys
            moments = snapshot.moments
            separatedSince = snapshot.separatedSince
            ritualClock = snapshot.ritualClock
            backfill = snapshot.backfill
            customTags = snapshot.customTags
            countriesMarkedDone = snapshot.countriesMarkedDone
            budgetNudgeShows = snapshot.budgetNudgeShows
            dayPlans = snapshot.dayPlans
            documents = snapshot.documents
            showCards = snapshot.showCards
            sharingRules = snapshot.sharingRules
        } else {
            // A first launch with nothing saved. The trip is empty: dates,
            // budget, countries and names are all genuinely unanswered, and
            // onboarding is what asks for them.
            //
            // `clock` the parameter, not `now` — no member of self is reachable
            // until every stored property is initialised.
            let defaultStart = Calendar.trip.startOfDay(for: clock())
            tripID = UUID()
            tripName = ""
            participant = .one
            names = .blank
            origin = .blank
            features = TripTemplate.someonesLeaving.features
            template = .someonesLeaving
            closedOn = nil
            hasOpened = false
            role = .one
            start = defaultStart
            dayCount = TripTemplate.someonesLeaving.suggestedDays
            budget = 0
            homeCurrency = .eur
            settingsUpdatedAt = .distantPast
            itinerary = ItineraryDocument(legs: [])
            expenses = []
            stamps = []
            meetingPoint = StampedMeetingPoint(
                value: MeetingPoint(place: "", detail: "", localScript: "", setAt: .distantPast),
                updatedAt: .distantPast, setBy: .one)
            meetingPlaces = []
            settlements = []
            journal = []
            letters = []
            lettersBelongTo = .one
            letterKeys_ = .blank
            moments = []
            separatedSince = nil
            ritualClock = RitualClock()
            backfill = BackfillOffers()
            customTags = []
            countriesMarkedDone = []
            budgetNudgeShows = 0
            dayPlans = []
            documents = []
            showCards = []
            sharingRules = []
        }

        // Views watch the store, so anything the store owns has to reach them.
        for child in [rates.objectWillChange.eraseToAnyPublisher(),
                      sync.objectWillChange.eraseToAnyPublisher(),
                      location.objectWillChange.eraseToAnyPublisher(),
                      self.library.objectWillChange.eraseToAnyPublisher()] {
            subscriptions.append(child.sink { [weak self] _ in self?.objectWillChange.send() })
        }

        // A trip saved before waypoints named their stops still has to join up.
        // Non-destructive, so it costs nothing to run on every launch, and it
        // has to run somewhere both branches above reach.
        backfillWaypointJoins()
        backfillPlanKeys()
        backfillWaypointPositions()
    }

    // MARK: - Who everybody is

    /// Every name in the app comes through here. `Traveller` carries no `name`
    /// of its own, so there is no second route that could disagree.
    func name(for who: Traveller) -> String { names[who] }

    var myName: String { name(for: role) }

    var otherName: String { name(for: role.other) }

    var observerName: String { names.observerName }

    /// A different label to the `Traveller` overload: both enums share their
    /// case names, so one label would make every leading-dot call site
    /// ambiguous.
    func name(of who: Participant) -> String {
        guard let traveller = who.traveller else { return observerName }
        return name(for: traveller)
    }

    /// The name as somebody typed it, empty when nobody has. What the editors
    /// bind to: `name(of:)` substitutes "Traveller one" for an unset slot,
    /// which as a field value gets typed *into* rather than replaced.
    func typedName(of who: Participant) -> String {
        guard let traveller = who.traveller else { return names.observer }
        return typedName(for: traveller)
    }

    func typedName(for who: Traveller) -> String {
        (who == .one ? names.one : names.two).value
    }

    /// A payer, with a name on it. `.both` isn't a person.
    func label(for payer: Payer) -> String {
        guard let traveller = payer.traveller else { return "Both" }
        return name(for: traveller)
    }

    /// Renames one slot and stamps only that slot, so two phones renaming
    /// themselves in the same round both survive the merge.
    func rename(_ who: Traveller, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != names[who] else { return }
        names.set(trimmed, for: who, at: now)
    }

    func renameObserver(to newName: String) {
        names.observer = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// This phone is that traveller.
    ///
    /// Changing who is holding the phone deletes any letters it holds, because
    /// they belonged to whoever it was before. Declining to *draw* somebody
    /// else's letters would still leave them on this disk, which is what the
    /// addressed channel exists to prevent.
    ///
    /// The question is `lettersBelongTo`, not `role`. Those are the same thing on
    /// a traveller's phone and different things on the observer's, where `role`
    /// is the traveller written *to* and `writeTo(_:)` moves it freely. Asking
    /// `traveller != role` therefore answered "nothing changed" for an observer
    /// adopting the slot they happened to be writing to — so the phone became
    /// that traveller still holding every letter the observer had written,
    /// drafts included, and including letters written for the *other* traveller
    /// if `writeTo` had been flipped earlier in the trip.
    func adopt(_ traveller: Traveller) {
        let who = Participant(traveller)
        participant = who
        role = traveller
        guard lettersBelongTo != who else { return }
        letters = []
        lettersBelongTo = who
    }

    /// This phone belongs to whoever stayed home.
    ///
    /// The mirror of `adopt(_:)`, and it has to exist for the same reason: the
    /// picker used to set `participant` straight through its binding with
    /// nothing else happening, so a traveller's received letters became the
    /// observer's outgoing set and `postLetters()` re-posted them under the new
    /// address as if they had been written here.
    func becomeObserver() {
        participant = .writer
        guard lettersBelongTo != .writer else { return }
        letters = []
        lettersBelongTo = .writer
    }

    /// Whether changing who holds this phone would throw letters away. What the
    /// confirmation is asked about, so the dialog and the guard can't disagree —
    /// the call site used to ask its own version of this and got it wrong.
    func adoptionDiscardsLetters(becoming who: Participant) -> Bool {
        lettersBelongTo != who && !letters.isEmpty
    }

    // MARK: - Joining somebody else's trip

    /// Take on the trip behind an invitation, as the slot the invitation names.
    ///
    /// **The id is the whole point.** Every phone mints its own `tripID` on
    /// first launch, `pull(tripID:)` fetches the record named after it, and
    /// `SyncMerge` refuses a payload whose id doesn't match — so two phones that
    /// each walked onboarding are two trips that will never meet, however well
    /// the merge works. Nothing anywhere else moves an id between phones. This
    /// is the seam, and it is why `tripRecordID` had to stay reversible.
    ///
    /// The failure it replaces was silent, which is what made it worth a
    /// feature rather than a fix: the joining phone's pull found no record,
    /// which is indistinguishable from being first, so it pushed its own blank
    /// trip and reported success. Two phones, both saying synced, neither
    /// carrying a word the other wrote.
    ///
    /// A trip already open here goes to the shelf first, which is also what
    /// `beginNextTrip` requires. There is never a moment where two trips are
    /// live, and joining somebody must not be a way to lose your own two
    /// months. `resetTrip()` leaves the shelf alone, so the archived copy
    /// survives the reset that follows it.
    ///
    /// `adopt(_:)` last, because it is the one irreversible step: it clears
    /// letters addressed to whoever this phone used to be. On a phone that has
    /// just been reset there are none, which is the ordinary case; ask
    /// `joiningDiscards` before calling if it might not be.
    func joinTrip(_ id: UUID, as traveller: Traveller) {
        if hasOpened { closeTrip() }
        // The shelf is never shown on the way to a joined trip, so a landing
        // left pending would play the next time it was, over the wrong book.
        justShelved = nil
        resetTrip()
        tripID = id
        adopt(traveller)
        // Not `.blank`: nobody is going to be asked to fill this trip in, and
        // the itinerary editor is the wrong place to send them. It arrives
        // packed, from the other phone, on the next round.
        origin = .packed
        hasOpened = true
    }

    /// What joining would cost, counted once so the confirmation and the act
    /// cannot drift — `adoptionDiscardsLetters`' shape, one flow over, and
    /// `papersLostOnClose`'s before that.
    ///
    /// Two separate losses, and they are not the same kind. The trip is
    /// *shelved* and can be reopened; the letters are gone. Anything drawing
    /// this has to say which is which.
    func joiningDiscards(becoming traveller: Traveller) -> (shelvesTrip: Bool, letters: Int) {
        let who = Participant(traveller)
        return (hasOpened, lettersBelongTo != who ? letters.count : 0)
    }

    /// An invitation this phone has been handed and not yet answered.
    ///
    /// Not persisted, not on `SyncPayload`, not on `TripSnapshot`: it is a
    /// question in flight, and a question that survived a relaunch would be a
    /// phone asking to join a trip whose link the person has since thought
    /// better of. It carries no `CKShare.Metadata` either — that stays in the
    /// coordinator, which is what keeps CloudKit out of this file.
    @Published var pendingInvitation: CloudKitSyncTransport.Invitation?

    /// Why the last join didn't happen. Shown once and cleared, like a sync
    /// notice — silence here would be a tap that did nothing.
    @Published var joinFailure: String?

    /// Hand this phone an invitation to answer. Nothing is joined and nothing
    /// is accepted; it only puts the question on screen.
    func offerInvitation(_ invitation: CloudKitSyncTransport.Invitation?) {
        guard let invitation else {
            joinFailure = "That link isn't an invitation to a trip."
            return
        }
        // Already here. Following the same link twice is ordinary — it is a
        // message in somebody's chat app — and re-joining would shelve the trip
        // and take it from the top.
        guard invitation.tripID != tripID else { return }
        pendingInvitation = invitation
    }

    /// Take the invitation up, as this traveller.
    ///
    /// The order matters and is the reverse of the obvious one: accept the
    /// share *first*, and only touch the local trip once iCloud has agreed. The
    /// other way round shelves somebody's trip and empties the phone, and then
    /// finds out there is no network — leaving them joined to nothing, with
    /// everything they had one screen further away.
    func acceptInvitation(as traveller: Traveller) async {
        guard let invitation = pendingInvitation else { return }
        do {
            try await sync.acceptHeldInvitation()
        } catch {
            joinFailure = error.localizedDescription
            return
        }
        pendingInvitation = nil
        joinTrip(invitation.tripID, as: traveller)
        // Straight away rather than on the next wake: the trip is empty until
        // the first round lands, and an empty trip under somebody else's name
        // is indistinguishable from a join that failed.
        await syncNow()
    }

    func declineInvitation() {
        pendingInvitation = nil
        sync.forgetHeldInvitation()
    }

    /// The observer picks who they are writing to. `role` is the address in home
    /// mode, so this is the only thing that decides where a drop lands.
    ///
    /// No deletion here, deliberately: the observer's copy is the archive of
    /// what they wrote, and writing to the other traveller doesn't unwrite it.
    func writeTo(_ traveller: Traveller) {
        role = traveller
    }

    // MARK: - The dates

    var end: Date {
        Calendar.trip.date(byAdding: .day, value: dayCount - 1, to: start) ?? start
    }

    var now: Date { clock() }

    /// Moving the departure date moves everything already written down with it,
    /// so the trip keeps its shape instead of scattering across the calendar.
    func setStart(_ newStart: Date) {
        let normalised = Calendar.trip.startOfDay(for: newStart)
        let shift = Calendar.trip.days(from: start, to: normalised)
        guard shift != 0 else { return }
        shiftDates(by: shift)
        start = normalised
        touchSettings()
    }

    /// Every dated record on this phone, moved by whole days.
    ///
    /// Shared by `setStart` and `apply`. The other phone's start winning a
    /// round is the same move made somewhere else: the shared records arrive
    /// already in the new frame (`SyncMerge` converts them), but the journal,
    /// the moments and the letters never travel, so this phone has to move its
    /// own. `apply` used to assign `start` and nothing else.
    private func shiftDates(by shift: Int) {
        guard shift != 0 else { return }
        func moved(_ date: Date) -> Date { TripShift.move(date, by: shift) }

        expenses = TripShift.expenses(expenses, by: shift)
        journal = journal.map { var c = $0; c.date = moved($0.date); return c }
        // `capturedAt` moves and `dayNumber` doesn't, the same split the
        // journal makes: the day is trip-relative and already correct.
        moments = moments.map { var c = $0; c.capturedAt = moved($0.capturedAt); return c }
        letters = letters.map { letter in
            var c = letter
            c.writtenOn = moved(letter.writtenOn)
            c.openedOn = letter.openedOn.map(moved)
            return c
        }
        stamps = TripShift.stamps(stamps, by: shift)
        meetingPoint.value.setAt = moved(meetingPoint.value.setAt)
        meetingPlaces = TripShift.meetingPlaces(meetingPlaces, by: shift)
        separatedSince = separatedSince.map(moved)
    }

    /// The travellers pick a return date; the length follows from it.
    func setEnd(_ newEnd: Date) {
        setDayCount(Calendar.trip.days(from: start, to: newEnd) + 1)
    }

    func setDayCount(_ days: Int) {
        dayCount = min(max(days, 1), 3650)
        touchSettings()
    }

    private func touchSettings() { settingsUpdatedAt = now }

    /// How far past the last day of the trip the itinerary runs, if at all.
    var itineraryOverrun: Int { max(itinerary.lastDay - dayCount, 0) }

    var phase: TripPhase { phase(on: now) }

    /// Where a given day falls. Parameterised rather than duplicated because the
    /// widget publishes the next three weeks and has to ask the same question
    /// about each of them; a second copy of this arithmetic is a second thing
    /// that can be wrong about a DST boundary.
    func phase(on date: Date) -> TripPhase {
        let elapsed = Calendar.trip.days(from: start, to: date)
        if elapsed < 0 { return .before(daysUntil: -elapsed) }
        if elapsed > dayCount - 1 { return .after(daysSince: elapsed - dayCount + 1) }
        return .during
    }

    /// Always a day that exists, so every screen has something to draw.
    var dayNumber: Int {
        min(max(Calendar.trip.days(from: start, to: now) + 1, 1), dayCount)
    }

    func date(forDay day: Int) -> Date {
        Calendar.trip.date(byAdding: .day, value: day - 1, to: start) ?? start
    }

    func dayNumber(for date: Date) -> Int {
        Calendar.trip.days(from: start, to: date) + 1
    }

    // MARK: - Where they are

    var legs: [Leg] { itinerary.legs }

    var currentLeg: Leg? { legs.first { $0.contains(day: dayNumber) } ?? legs.last }
    var currentSegment: Segment? { segment(forDay: dayNumber) }

    /// The stop Today's panel opens, including on the morning they fly home.
    ///
    /// The lenient one. `currentSegment` is the strict `segment(forDay:)` and
    /// answers nil on the last day of the trip, because `contains(day:)` is
    /// half-open — `currentCity` already goes through `lastKnownSegment` for
    /// exactly that reason. The two deliberately disagree; don't tidy them
    /// together.
    ///
    /// Still nil for a trip with no legs, and for a day in a gap nobody
    /// planned. Both mean there is no stop to show, and the caller draws the
    /// itinerary instead.
    var todaySegment: Segment? { lastKnownSegment(forDay: dayNumber) }

    var currentCity: String { city(forDay: dayNumber) }

    /// What a *label* says when the trip has nowhere in it.
    ///
    /// Named once because it is now asked in two directions: the screens draw
    /// it, and `country(of:)` has to recognise it in stored data written by a
    /// build that let it leak there.
    static let unknownPlace = "—"

    var currentCountry: String { currentLeg?.country ?? TripStore.unknownPlace }

    /// What to *stamp* on a record made now — the empty string when the trip
    /// has nowhere in it, never the label.
    ///
    /// `currentCountry`'s em-dash is a thing a screen says. Written onto an
    /// expense it becomes a country that does not exist: every reader keys off
    /// `legs`, so the line fell out of "by country" and the per-day lines in
    /// silence, and stayed out after the traveller typed Thailand in. The app
    /// ships with no trip inside it, so this was the ordinary first-run path
    /// and not a corner.
    var countryNow: String { currentLeg?.country ?? "" }

    /// `countryNow`'s twin for a city: what to stamp on a moment, never the
    /// em-dash `currentCity` draws on a trip with nowhere in it.
    var cityNow: String { lastKnownSegment(forDay: dayNumber)?.primaryPlace ?? "" }

    /// The unclamped day. `dayNumber` pins everything before departure to 1,
    /// which is right for a screen and wrong for a record: a moment kept at
    /// the airport five days early is day -4, not the first day in Bangkok.
    var trueDayNumber: Int {
        let day = Calendar.trip.days(from: start, to: now) + 1
        return day < 1 ? day : dayNumber
    }

    /// Before day 1. Asked by the moment composer, which has to say where a
    /// moment will be filed before it is.
    var isBeforeDeparture: Bool { trueDayNumber < 1 }

    /// The leg covering a day, including the morning they fly home.
    ///
    /// `Leg.contains(day:)` is half-open for the reason `Segment`'s is, so the
    /// last day of the trip falls in no leg and has to fall through — the same
    /// shape as `lastKnownSegment(forDay:)`. Strict otherwise: `currentLeg`
    /// ends in `?? legs.last`, which is right for "where am I now" against a
    /// clamped `dayNumber` and wrong for attributing a dated record.
    func leg(forDay day: Int) -> Leg? {
        legs.first { $0.contains(day: day) }
            ?? (day >= itinerary.lastDay ? legs.last : nil)
    }

    /// Which country a ledger line belongs to, which is not always what it was
    /// stamped with.
    ///
    /// The stamp wins whenever there is one. An expense is a record of a dated
    /// event, and where they were when they spent it does not change because
    /// somebody later dragged a stop. That is deliberately the opposite of
    /// `DayDetailView.cityName`, which prefers the live segment — a day *plan*
    /// joins on `dayNumber` and `reflow()` renumbers days, so there it is the
    /// stored city that goes stale.
    ///
    /// Empty is what a trip with nowhere in it stamps now, and `unknownPlace`
    /// is what it stamped before. Both mean "nobody had said yet", so both are
    /// resolved against the itinerary as it stands: the money was spent in
    /// Thailand whether or not Thailand had been typed in at the time.
    ///
    /// `nil` is a real answer — no stamp, and no leg covering that day.
    func country(of expense: Expense) -> String? {
        let stamped = expense.country.trimmingCharacters(in: .whitespaces)
        if !stamped.isEmpty, stamped != TripStore.unknownPlace { return stamped }
        return leg(forDay: dayNumber(for: expense.date))?.country
    }

    /// What they'll be handing over at the counter today.
    var localCurrency: Currency { currentLeg?.currency ?? .eur }

    /// Every currency the itinerary will make them spend.
    var tripCurrencies: [Currency] {
        var seen: [Currency] = []
        for leg in legs where !seen.contains(leg.currency) { seen.append(leg.currency) }
        return seen
    }

    var todayPlan: DayPlan? { plan(forDay: dayNumber) }

    /// What was written about a day, if anything still is. Every reader goes
    /// through here, which makes it the one place tombstones have to be
    /// filtered — `dayPlans` itself keeps the cleared ones so a clear can win
    /// a merge against an edit made before it.
    ///
    /// The newest wins when two answer. Two phones writing the same day before
    /// a round each mint a record, the merge keeps both, and `.first` over a
    /// merge's dictionary order picked one of them at random.
    func plan(forDay day: Int) -> DayPlan? {
        let key = planKey(forDay: day)
        return dayPlans.live.filter { planKey(of: $0) == key }.max { $0.updatedAt < $1.updatedAt }
    }

    /// Where a day's plan is filed.
    ///
    /// By the stop and how far into it, so a plan goes where its stop goes when
    /// the stops are dragged. The morning they fly home is in no stop, because
    /// `contains(day:)` is half-open, so it is filed one past the last stop's
    /// nights — the shape `lastKnownSegment(forDay:)` has. A day no stop covers
    /// is filed by its number.
    enum PlanKey: Hashable {
        case stop(UUID, Int)
        case day(Int)
    }

    func planKey(forDay day: Int) -> PlanKey {
        if let segment = segment(forDay: day) { return .stop(segment.id, day - segment.startDay) }
        if day == itinerary.lastDay, let last = itinerary.allSegments.last {
            return .stop(last.id, last.nights)
        }
        return .day(day)
    }

    private func planKey(of plan: DayPlan) -> PlanKey {
        if let segmentID = plan.segmentID, let offset = plan.dayOfStop { return .stop(segmentID, offset) }
        return .day(plan.dayNumber)
    }

    /// The plans a stop has but no longer has days for.
    ///
    /// Taking a night off a stop doesn't delete what was written for it: the
    /// plan waits, and adding the night back brings it back. Nothing is written
    /// either way, which is what makes the stepper safe to tap.
    func setAsidePlans(forSegment id: UUID) -> [DayPlan] {
        guard let segment = itinerary.allSegments.first(where: { $0.id == id }) else { return [] }
        let isLast = itinerary.allSegments.last?.id == id
        let reach = isLast ? segment.nights : segment.nights - 1
        return dayPlans.live
            .filter { $0.segmentID == id && ($0.dayOfStop ?? 0) > reach }
            .sorted { ($0.dayOfStop ?? 0) < ($1.dayOfStop ?? 0) }
    }

    /// The live plans filed under these stops, set aside or not.
    func plans(inSegments ids: Set<UUID>) -> [DayPlan] {
        dayPlans.live.filter { $0.segmentID.map(ids.contains) ?? false }
    }

    /// Files plans saved before the stop keys existed under the stop covering
    /// their day.
    ///
    /// Runs where `backfillWaypointJoins()` does, and for its reason: both
    /// phones derive the same answer, so it is not an edit and `updatedAt`
    /// stays put — bumping it would let a backfill win against a real edit.
    func backfillPlanKeys() {
        for index in dayPlans.indices where dayPlans[index].segmentID == nil {
            guard case .stop(let segmentID, let offset) = planKey(forDay: dayPlans[index].dayNumber)
            else { continue }
            dayPlans[index].segmentID = segmentID
            dayPlans[index].dayOfStop = offset
        }
    }

    func segment(forDay day: Int) -> Segment? {
        itinerary.allSegments.first { $0.contains(day: day) }
    }

    /// Where they are, including on the morning they fly home.
    ///
    /// `contains(day:)` is half-open, because `endDay` is the day they *leave*.
    /// That makes gaps and overlaps unrepresentable, and it also leaves the
    /// last day of the trip inside no segment at all — so it falls through to
    /// the last one, which is still where they are.
    func lastKnownSegment(forDay day: Int) -> Segment? {
        segment(forDay: day) ?? (day >= itinerary.lastDay ? itinerary.allSegments.last : nil)
    }

    func city(forDay day: Int) -> String {
        lastKnownSegment(forDay: day)?.primaryPlace ?? TripStore.unknownPlace
    }

    // MARK: - Editing the itinerary

    func setNights(_ nights: Int, forSegment id: UUID) {
        itinerary.setNights(nights, forSegment: id, now: now)
        reflowWaypoints()
    }

    func moveSegments(inLeg legID: UUID, from offsets: IndexSet, to destination: Int) {
        itinerary.moveSegments(inLeg: legID, from: offsets, to: destination, now: now)
        reflowWaypoints()
    }

    /// What removing these stops would take with it, and whether it may.
    ///
    /// One answer for a stop and for a whole country, because removing a
    /// country is removing every stop in it. The stamps go with their stop:
    /// leaving them behind is the AYU bug again — still in `orderedStamps`,
    /// still "next", reachable from no editor, and holding every letter sealed
    /// to the last stamp shut for good. Earned ones stay; they are a record of
    /// somebody standing somewhere.
    struct StopRemoval {
        /// The unearned waypoints that go with the stops.
        var stamps: [Stamp]
        /// The sealed letters that will never open, in the editor's words.
        var letterCost: String?
        /// How many written days go with them.
        var planCount: Int
        /// Why it is refused outright, or nil if it is only a thing to confirm.
        var refusal: String?
    }

    func removalSummary(ofSegments ids: [UUID]) -> StopRemoval {
        let going = ids.flatMap { waypoints(forSegment: $0) }.filter { !$0.earned }
        let goingIDs = Set(going.map(\.id))

        let sealed = letters.filter { letter in
            !letter.isDraft && !letter.isOpen
                && going.contains { stamp in lettersDepending(on: stamp).contains { $0.id == letter.id } }
        }
        var cost: String?
        if sealed.contains(where: \.secretCondition) {
            cost = "Something sealed is waiting on \(going.count == 1 ? "its stamp" : "its stamps"). Removing it means that never opens."
        } else if !sealed.isEmpty {
            let numbers = sealed.map(\.numberLabel).joined(separator: ", ")
            cost = sealed.count == 1
                ? "Letter \(numbers) opens with \(going.count == 1 ? "its stamp" : "one of its stamps"). Removing it means it never opens."
                : "Letters \(numbers) open with its stamps. Removing it means they never open."
        }

        // The group half of `removalRefusal(ofWaypoint:)`: taking away the last
        // stamps nobody has stood in completes the trail, and every letter
        // sealed to the last stamp opens on the spot, for good.
        var refusal: String?
        let remaining = stamps.live.filter { !goingIDs.contains($0.id) }
        if !going.isEmpty, !remaining.isEmpty, remaining.allSatisfy(\.earned),
           letters.contains(where: { $0.condition == .finalStamp && !$0.isDraft && !$0.isOpen }) {
            refusal = "This holds the last stamps nobody has stood in. Removing it opens the letter sealed to the last stamp, right here, and that can't be taken back."
        }

        return StopRemoval(stamps: going, letterCost: cost,
                           planCount: plans(inSegments: Set(ids)).count, refusal: refusal)
    }

    /// Removes a stop, its unearned stamps and the days written in it.
    /// `false` when it is refused.
    @discardableResult
    func removeSegment(_ id: UUID) -> Bool {
        guard itinerary.allSegments.contains(where: { $0.id == id }) else { return false }
        return removeStops([id]) { $0.removeSegment(id, now: now) }
    }

    /// Validated whole, then applied whole (§3.1): nothing is tombstoned until
    /// every stop in it is known to be removable.
    private func removeStops(_ ids: [UUID], _ mutate: (inout ItineraryDocument) -> Void) -> Bool {
        guard !isObserver else { return false }
        let summary = removalSummary(ofSegments: ids)
        guard summary.refusal == nil else { return false }

        let stampIDs = Set(summary.stamps.map(\.id))
        for index in stamps.indices where stampIDs.contains(stamps[index].id) {
            stamps[index].deletedAt = now
            stamps[index].updatedAt = now
        }
        let segmentIDs = Set(ids)
        for index in dayPlans.indices
        where !dayPlans[index].isDeleted && dayPlans[index].segmentID.map(segmentIDs.contains) == true {
            dayPlans[index].deletedAt = now
            dayPlans[index].updatedAt = now
        }
        mutate(&itinerary)
        reflowWaypoints()
        return true
    }

    /// Returns the stop it made, so the sheet that asks for a stop and its
    /// stamp in one breath can hang the stamp off it. Nil when nothing was made.
    @discardableResult
    func addSegment(title: String, nights: Int, toLeg legID: UUID) -> Segment? {
        let made = itinerary.addSegment(title: title, nights: nights, toLeg: legID, now: now)
        backfillWaypointJoins()
        reflowWaypoints()
        return made
    }

    /// Returns the country's first stop, so the sheet that makes it can give it
    /// a stamp the way `addSegment`'s caller does.
    @discardableResult
    func addLeg(country: String, currency: Currency, firstStop: String, nights: Int) -> Segment? {
        let made = itinerary.addLeg(country: country, currency: currency,
                                    firstStop: firstStop, nights: nights, now: now)
        backfillWaypointJoins()
        reflowWaypoints()
        return made
    }

    /// Removes a country: every stop in it, on the stop's terms.
    @discardableResult
    func removeLeg(_ id: UUID) -> Bool {
        guard let leg = legs.first(where: { $0.id == id }) else { return false }
        return removeStops(leg.segments.map(\.id)) { $0.removeLeg(id, now: now) }
    }

    /// Renames a stop and keeps its stamps on it.
    ///
    /// A stamp that found this stop by name — one saved before the join, or a
    /// stop naming two places, which `backfillWaypointJoins()` won't guess at —
    /// would lose it with the old name, so it is given the id first, as an
    /// edit. `Stamp.city` is never rewritten: a `.place` letter is sealed to it,
    /// and the stamp editor already offers the drifted city as a choice.
    @discardableResult
    func renameSegment(_ id: UUID, title: String) -> Bool {
        guard !isObserver else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let segment = itinerary.allSegments.first(where: { $0.id == id }) else { return false }
        guard trimmed != segment.title else { return true }
        for index in stamps.indices
        where !stamps[index].isDeleted && stamps[index].segmentID != id && self.segment(for: stamps[index])?.id == id {
            stamps[index].segmentID = id
            stamps[index].updatedAt = now
        }
        itinerary.renameSegment(id, title: trimmed, now: now)
        return true
    }

    /// Renames a country, and the lines spent there with it.
    ///
    /// An expense is stamped with the country it was spent in and is never
    /// re-resolved (§3.4), so renaming "Viet Nam" to "Vietnam" would leave
    /// every line under the old name and out of "by country". The lines that
    /// carry the old name *and* fall in this visit are re-stamped, as edits so
    /// the other phone keeps them; a country entered twice keeps the other
    /// visit's lines.
    @discardableResult
    func renameLeg(_ id: UUID, country: String) -> Bool {
        guard !isObserver else { return false }
        let trimmed = country.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let leg = legs.first(where: { $0.id == id }) else { return false }
        guard trimmed != leg.country else { return true }
        for index in expenses.indices
        where expenses[index].country.trimmingCharacters(in: .whitespaces) == leg.country
            && self.leg(forDay: dayNumber(for: expenses[index].date))?.id == id {
            expenses[index].country = trimmed
            expenses[index].updatedAt = now
        }
        itinerary.renameLeg(id, country: trimmed, now: now)
        return true
    }

    /// What new lines in this country default to. Every line already spent
    /// keeps the currency it was spent in.
    @discardableResult
    func setCurrency(_ currency: Currency, forLeg id: UUID) -> Bool {
        guard !isObserver, let leg = legs.first(where: { $0.id == id }) else { return false }
        guard leg.currency != currency else { return true }
        itinerary.setCurrency(currency, forLeg: id, now: now)
        return true
    }

    func moveLegs(from offsets: IndexSet, to destination: Int) {
        itinerary.moveLegs(from: offsets, to: destination, now: now)
        reflowWaypoints()
    }

    /// Stretch or trim the trip so the return date matches the plan.
    func matchDatesToItinerary() {
        setDayCount(max(itinerary.lastDay, 1))
    }

    // MARK: - Editing a day

    /// Every write to a day goes through here, so the timestamp can't be
    /// forgotten — the merge is only as good as the `updatedAt` on it.
    ///
    /// A day nobody has written about yet has no record at all, so the first
    /// edit mints one. `city` is seeded from the segment covering the day at
    /// the moment of writing; it is what the note was *about*, and the screens
    /// prefer the live segment over it.
    private func editPlan(forDay day: Int, _ mutate: (inout DayPlan) -> Void) {
        if let index = planIndex(forDay: day) {
            mutate(&dayPlans[index])
            dayPlans[index].dayNumber = day
            dayPlans[index].updatedAt = now
            // Writing to a day that had been cleared brings it back, the way
            // `restore` does for an expense. Typing into it is the undo.
            dayPlans[index].deletedAt = nil
        } else {
            let key = planKey(forDay: day)
            var plan = DayPlan(dayNumber: day,
                               city: lastKnownSegment(forDay: day)?.primaryPlace ?? "",
                               blurb: "", items: [])
            if case .stop(let segmentID, let offset) = key {
                plan.segmentID = segmentID
                plan.dayOfStop = offset
            }
            mutate(&plan)
            plan.updatedAt = now
            dayPlans.append(plan)
        }
    }

    func setBlurb(_ text: String, forDay day: Int) {
        editPlan(forDay: day) { $0.blurb = text }
    }

    /// Empty means no occasion, not an occasion called "". The screens key the
    /// chip off `occasion != nil`, so a blank string would draw a blank chip.
    func setOccasion(_ text: String?, forDay day: Int) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        editPlan(forDay: day) { $0.occasion = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    func setLodging(title: String?, note: String?, forDay day: Int) {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        editPlan(forDay: day) {
            $0.lodgingTitle = (trimmedTitle?.isEmpty ?? true) ? nil : trimmedTitle
            $0.lodgingNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        }
    }

    @discardableResult
    func addItem(time: String, title: String, note: String, toDay day: Int) -> PlanItem {
        let item = PlanItem(time: time, title: title, note: note)
        editPlan(forDay: day) { $0.items.append(item) }
        return item
    }

    func updateItem(_ item: PlanItem, onDay day: Int) {
        editPlan(forDay: day) {
            guard let index = $0.items.firstIndex(where: { $0.id == item.id }) else { return }
            $0.items[index] = item
        }
    }

    /// No tombstone: an hour lives inside its day, and the day carries the
    /// timestamp that decides the merge. Removing one is an edit to the day.
    func removeItem(_ id: UUID, fromDay day: Int) {
        editPlan(forDay: day) { $0.items.removeAll { $0.id == id } }
    }

    /// Tombstoned rather than removed, so a clear here beats an edit made on
    /// the other phone before the round — same reasoning as `delete(_ expense:)`.
    func clearPlan(forDay day: Int) {
        guard let index = planIndex(forDay: day), !dayPlans[index].isDeleted else { return }
        dayPlans[index].deletedAt = now
        dayPlans[index].updatedAt = now
    }

    /// The record a day's edits land on: the one `plan(forDay:)` shows, or
    /// failing that the newest cleared one, so writing into a cleared day
    /// brings it back rather than minting a second record beside it.
    private func planIndex(forDay day: Int) -> Int? {
        let key = planKey(forDay: day)
        let matching = dayPlans.indices.filter { planKey(of: dayPlans[$0]) == key }
        let newest: (Int, Int) -> Bool = { self.dayPlans[$0].updatedAt < self.dayPlans[$1].updatedAt }
        return matching.filter { !dayPlans[$0].isDeleted }.max(by: newest) ?? matching.max(by: newest)
    }

    // MARK: - Editing the show-this cards

    /// What to call the language of wherever they are, or `nil` where the app
    /// has never heard of the country.
    ///
    /// A *label* for the card editor's first field, not a translation. It names
    /// the language; the travellers write the sentence.
    var currentLanguage: String? {
        CountryFacts.lookup(currentLeg?.country ?? "")?.language
    }

    /// The cards as they are swiped through. Every screen reads this rather
    /// than `showCards`: it drops the tombstones and it sorts, and after a
    /// merge the raw array is in whatever order a dictionary handed back.
    var orderedShowCards: [ShowCard] {
        showCards.live.sorted { $0.index < $1.index }
    }

    @discardableResult
    func addShowCard(native: String, english: String, shortName: String,
                     footerTitle: String? = nil, footerBody: String? = nil,
                     footerNote: String? = nil) -> ShowCard {
        let card = ShowCard(native: native, english: english,
                            footerTitle: footerTitle, footerBody: footerBody,
                            footerNote: footerNote, shortName: shortName,
                            // Onto the end, and past anything tombstoned, so a
                            // deleted card can't leave a new one sharing its slot.
                            index: (showCards.map(\.index).max() ?? -1) + 1,
                            updatedAt: now)
        showCards.append(card)
        return card
    }

    /// Takes the card whole, the way the ledger's edit sheet does — the editor
    /// hands back a copy of what it was given with the fields changed, so
    /// `index` and `id` come along untouched.
    func updateShowCard(_ card: ShowCard) {
        guard let at = showCards.firstIndex(where: { $0.id == card.id }) else { return }
        showCards[at] = card
        showCards[at].updatedAt = now
    }

    func deleteShowCard(_ id: UUID) {
        guard let at = showCards.firstIndex(where: { $0.id == id }),
              !showCards[at].isDeleted else { return }
        showCards[at].deletedAt = now
        showCards[at].updatedAt = now
    }

    /// The undo, which is the delete's own mechanism run backwards — the same
    /// shape `restore(_:)` has one collection over. The fresh `updatedAt` is
    /// load-bearing: without it the other phone's tombstone is the later write
    /// and merges the card straight back out.
    func restoreShowCard(_ id: UUID) {
        guard let at = showCards.firstIndex(where: { $0.id == id }) else { return }
        showCards[at].deletedAt = nil
        showCards[at].updatedAt = now
    }

    /// Reordering renumbers, and renumbering is an edit to every card that
    /// moved — otherwise the other phone merges the new order away.
    func moveShowCards(from offsets: IndexSet, to destination: Int) {
        var ordered = orderedShowCards
        ordered.moveElements(fromOffsets: offsets, toOffset: destination)
        for (position, card) in ordered.enumerated() {
            guard let at = showCards.firstIndex(where: { $0.id == card.id }),
                  showCards[at].index != position else { continue }
            showCards[at].index = position
            showCards[at].updatedAt = now
        }
    }

    // MARK: - Papers

    /// Adds a document and hands it back.
    ///
    /// Takes it whole, like `updateDocument` below — one shape for both, so the
    /// editor builds a `TravelDocument` once and either writes it or replaces
    /// one. Returned rather than void the way `addSegment` is: the caller needs
    /// the id to file scans under.
    @discardableResult
    func addDocument(_ document: TravelDocument) -> TravelDocument? {
        guard !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !documents.contains(where: { $0.id == document.id }) else { return nil }
        documents.append(document)
        return document
    }

    /// Takes the document whole, the way `updateShowCard` does.
    ///
    /// The editor hands back a copy of what it was given with the fields
    /// changed, so `id` rides along untouched and the scans stay attached to it.
    /// Validated whole and applied whole — `updateWaypoint` used to check and
    /// write a field at a time and could return having changed half of one.
    func updateDocument(_ document: TravelDocument) {
        guard !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let at = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[at] = document
    }

    /// Removes the row and the scans filed under it.
    ///
    /// A real removal, not a tombstone. `TravelDocument` has no `deletedAt` and
    /// must not grow one: a tombstone is how a delete beats a concurrent edit
    /// across two phones, there is no second phone for a document, and a
    /// tombstoned row is a passport number still on disk under the word
    /// "deleted".
    ///
    /// - Returns: how many scans went with it.
    @discardableResult
    func deleteDocument(_ id: UUID) -> Int {
        guard let at = documents.firstIndex(where: { $0.id == id }) else { return 0 }
        documents.remove(at: at)
        // Directly, rather than leaving it to the next prune: the reason
        // somebody deletes a passport row is that they want it gone now.
        return ScanVault.shared.deleteAll(for: id)
    }

    func document(_ id: UUID) -> TravelDocument? {
        documents.first { $0.id == id }
    }

    func scanCount(for id: UUID) -> Int { ScanVault.shared.pageCount(for: id) }

    // MARK: - Converting

    /// Today's rate, or the last one that reached the phone.
    func inHome(_ amount: Double, from currency: Currency) -> Double {
        rates.snapshot.convert(amount, from: currency, to: homeCurrency)
    }

    func inHome(_ expense: Expense) -> Double {
        inHome(expense.amount, from: expense.currency)
    }

    func fromHome(_ amount: Double, to currency: Currency) -> Double {
        rates.snapshot.convert(amount, from: homeCurrency, to: currency)
    }

    /// Into the money they are actually handling today.
    ///
    /// `convert` returns the amount untouched when the two currencies match,
    /// so a baht expense on a baht day stays exact and nothing rounds through
    /// a rate it didn't need.
    func inLocal(_ amount: Double, from currency: Currency) -> Double {
        rates.snapshot.convert(amount, from: currency, to: localCurrency)
    }

    func inLocal(_ expense: Expense) -> Double {
        inLocal(expense.amount, from: expense.currency)
    }

    func homeText(_ amount: Double) -> String { homeCurrency.format(amount) }
    func homeTextRounded(_ amount: Double) -> String { homeCurrency.formatRounded(amount) }

    /// What is already on the phone, said on the countdown screen.
    ///
    /// Every clause has to earn its place. Written as one interpolation it read
    /// "61 days, 0 countries, €0 between you. It's all already on the phone."
    /// on every trip typed from scratch — which is every trip, since `init`
    /// always seeds a blank one. Three faults in one sentence: two counts of
    /// nothing stated as though they were facts, a plural nothing forced to
    /// agree so a one-country trip read "1 countries", and a promise about a
    /// phone with nothing on it.
    ///
    /// Here rather than in the view because `Features/` isn't compiled by
    /// `run-checks.sh`, and derived copy failing its own degenerate case is the
    /// thing this project keeps being bitten by — the forecast advising cooking
    /// twice a week once the projection ran the budget dry, "One days in" on
    /// the first day of every trip. A sentence with a branch in it wants a
    /// check, the way `whatTravels` and `papersLostOnClose` do.
    ///
    /// The counts go through `Formatting.spelledCount` at `spellingUpTo: 0` —
    /// the numeral branch, which still pluralises. This is a 13pt aside under a
    /// numeral headline, not the 38pt one the spelling is for.
    var packedSummary: String {
        var clauses = [Formatting.spelledCount(dayCount, "day", spellingUpTo: 0)]
        if !legs.isEmpty {
            clauses.append(Formatting.spelledCount(legs.count, "country",
                                                   plural: "countries",
                                                   spellingUpTo: 0))
        }
        if budget > 0 {
            clauses.append("\(homeTextRounded(budget)) between you")
        }
        let counted = clauses.joined(separator: ", ")
        // "It's all already on the phone" is a claim about the things just
        // named, so it holds only while something has been named. A trip that
        // is still nothing but dates gets the argument `FirstStopView` and the
        // itinerary's empty state both make, in its own words rather than
        // theirs: nothing else is settled, and nothing has to be.
        guard clauses.count > 1 else {
            return "\(counted). Nothing else is settled yet, and nothing has to be."
        }
        return "\(counted). It's all already on the phone."
    }

    /// The sentence under "Today together": who can find whom, and where.
    ///
    /// Asked of the store, so its branches can be checked. Written as one
    /// interpolation it read "set at The bridge's  if you lose each other"
    /// whenever "Which bit of it" was left empty — the possessive belongs to
    /// the detail, not to the line.
    var meetingLine: String {
        guard meeting.isSet else {
            return "No meeting point yet. Pick somewhere you can both walk to if the phones die."
        }
        let place = meeting.place.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = meeting.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let spot = detail.isEmpty ? place : "\(place)'s \(detail)"
        return "Meeting point set at \(spot) if you lose each other."
    }

    // MARK: - Money

    /// Only real spending counts against the budget — settlements between the
    /// two of them move the balance, not the burn.
    var spending: [Expense] { expenses.live.filter { $0.kind == .spend } }

    var spentHome: Double { spending.reduce(0) { $0 + inHome($1) } }
    var remainingHome: Double { max(budget - spentHome, 0) }
    var budgetFraction: Double { budget > 0 ? min(spentHome / budget, 1) : 0 }
    var daysLeft: Int { max(dayCount - dayNumber + 1, 1) }
    var dailyAllowanceHome: Double { remainingHome / Double(daysLeft) }
    var budgetPerDay: Double { budget / Double(max(dayCount, 1)) }

    /// Where the burn should be if they were spending evenly.
    var paceHome: Double { budgetPerDay * Double(dayNumber) }

    var paceDaysAhead: Int {
        guard budgetPerDay > 0 else { return 0 }
        return Int(((paceHome - spentHome) / budgetPerDay).rounded())
    }

    func expenses(onDay day: Int) -> [Expense] {
        spending.filter { dayNumber(for: $0.date) == day }
    }

    /// What today cost, in the money they are handling.
    ///
    /// Every expense, not only the ones already in the local currency. It used
    /// to filter on `currency == localCurrency`, which was survivable while the
    /// figure was inert and stopped being so the moment it became the control
    /// that adds an expense: a euro card payment in Thailand left the 30pt
    /// number somebody had just tapped sitting exactly where it was. "No error
    /// is not it worked", on a button.
    ///
    /// Local rather than home because this is the figure read at a counter, and
    /// it only changes currency when they cross a border — which it already
    /// did. The budget question is the pace line's, and that stays in home.
    var spentTodayInLocal: Double {
        expenses(onDay: dayNumber).reduce(0) { $0 + inLocal($1) }
    }

    /// Whether saying that meant converting anything.
    var spentTodayIsConverted: Bool {
        expenses(onDay: dayNumber).contains { $0.currency != localCurrency }
    }

    /// The figure as it is read: "฿250" on a day spent entirely in baht,
    /// "≈฿985" on one with a card payment in it.
    ///
    /// The approximation mark is computed, not always drawn — a day that needed
    /// no rate is exact, and marking it approximate would be the same lie in
    /// the other direction. `RateStamp` sits under it either way, because a
    /// converted number without its age pretends to be current.
    ///
    /// Rounded when it is approximate, for the reason `formatRounded` exists:
    /// the cents of an estimate are noise, and "≈€26.43" argues with itself.
    /// The two agree on baht, dong and won, which carry no decimals anyway, so
    /// the branch only shows on a leg whose currency is the home one.
    var spentTodayText: String {
        guard spentTodayIsConverted else {
            return localCurrency.format(spentTodayInLocal)
        }
        return "≈\(localCurrency.formatRounded(spentTodayInLocal))"
    }

    var spentTodayHome: Double {
        expenses(onDay: dayNumber).reduce(0) { $0 + inHome($1) }
    }

    /// Whether today's home figure needed a rate.
    var spentTodayHomeIsConverted: Bool {
        expenses(onDay: dayNumber).contains { $0.currency != homeCurrency }
    }

    /// The line under "Spent today": today in home money, and whether that
    /// keeps them on the budget's pace. Nil when there is nothing to say.
    ///
    /// The verdict needs a budget. With none — nought is allowed — it read
    /// "≈ €0 · under pace", and anything spent was "over pace" against a
    /// day worth nothing. Without one the line is only the conversion, and
    /// only when there was one: a day spent in home money is already the
    /// figure above it.
    ///
    /// The "≈" follows the same rule as `spentTodayText`: drawn only when a
    /// rate was used. When nothing was converted and the money in hand is
    /// the home money, the figure would repeat the 30pt one, so only the
    /// verdict is left.
    var paceNote: String? {
        let home = spentTodayHome
        let converted = spentTodayHomeIsConverted
        let figure: String?
        if converted, home > 0 {
            figure = "≈ \(homeTextRounded(home))"
        } else if localCurrency != homeCurrency, home > 0 {
            figure = homeText(home)
        } else {
            figure = nil
        }
        guard budget > 0 else { return figure }
        let verdict = home <= budgetPerDay ? "under pace" : "over pace"
        return [figure, verdict].compactMap { $0 }.joined(separator: " · ")
    }

    /// Every country the itinerary visits, once each, in the order they are
    /// first reached — with every leg that goes there.
    ///
    /// A country can be entered twice: Thailand → Laos → Thailand is an
    /// ordinary route, not a corner case. Anything keyed off "*the* leg for
    /// this country" answers with the first of them, and anything that iterates
    /// `legs` to talk about countries says the same country twice. Both
    /// happened: the money screen drew two "Thailand" rows, each showing every
    /// baht spent in Thailand, under two different day counts — and the
    /// per-day comparison below then found Thailand cheapest *and* dearest and
    /// suppressed itself.
    var countries: [(name: String, legs: [Leg])] {
        var order: [String] = []
        var byName: [String: [Leg]] = [:]
        for leg in legs {
            if byName[leg.country] == nil { order.append(leg.country) }
            byName[leg.country, default: []].append(leg)
        }
        return order.map { ($0, byName[$0] ?? []) }
    }

    /// A name for the trip, offered once somewhere is in it: "Japan '27",
    /// "Japan & Korea '27", "Japan, Korea & more '27". Nil with nowhere in it.
    ///
    /// Offered on a chip beside the name field, never as its placeholder:
    /// grey text in a field reads as an answer somebody already gave, which
    /// is the placeholder that reproduced day 12's plan under day 20. Counts
    /// through `countries`, so Thailand → Laos → Thailand is two names.
    var suggestedTripName: String? {
        let names = countries.map(\.name)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = names.first else { return nil }
        let year = "'" + start.text("yy")
        switch names.count {
        case 1: return "\(first) \(year)"
        case 2: return "\(first) & \(names[1]) \(year)"
        default: return "\(first), \(names[1]) & more \(year)"
        }
    }

    func legs(inCountry country: String) -> [Leg] {
        legs.filter { $0.country == country }
    }

    /// What a country cost, in its own money.
    ///
    /// Every line spent there, not only the ones already in its currency. It
    /// used to filter on `currency == ` the country's, so a card payment made
    /// in euros in Thailand counted towards the trip and towards nowhere —
    /// "by country" didn't add up to the total above it, with nothing on
    /// screen to say why. The other currencies come in through today's rate,
    /// and `converted` says so, for the reason `spentTodayIsConverted` does.
    func spent(inCountry country: String) -> (local: Double, currency: Currency, converted: Bool)? {
        // The currency belongs to the country, not to one crossing of it. Two
        // legs in one country spend the same money.
        guard let currency = legs(inCountry: country).first?.currency else { return nil }
        // Through `country(of:)`, so a line stamped before the itinerary
        // existed joins the country it was actually spent in. The stamped
        // case short-circuits, so this costs nothing on an ordinary trip.
        let lines = spending.filter { self.country(of: $0) == country }
        guard !lines.isEmpty else { return nil }
        let total = lines.reduce(0) { $0 + rates.snapshot.convert($1.amount, from: $1.currency, to: currency) }
        return (total, currency, lines.contains { $0.currency != currency })
    }

    /// The figure on a "by country" row: "฿62,400", or "≈฿64,180" once a rate
    /// was needed — rounded then, because the cents of an estimate are noise.
    func spentText(inCountry country: String) -> String? {
        guard let spend = spent(inCountry: country) else { return nil }
        return spend.converted
            ? "≈\(spend.currency.formatRounded(spend.local))"
            : spend.currency.format(spend.local)
    }

    /// Why a row has a "≈" in front of it: "≈ because €52 of it was paid in
    /// another currency." Nil when nothing was converted. The amount names the
    /// money by its symbol; a currency's *name* is never pluralised, because
    /// "us dollars" and "thai bahts" are what that produces. More than one
    /// foreign currency is said as such, since a list of four amounts under
    /// one row is a second ledger.
    func conversionNote(inCountry country: String) -> String? {
        guard let spend = spent(inCountry: country), spend.converted else { return nil }
        let foreign = spending.filter { self.country(of: $0) == country && $0.currency != spend.currency }
        let currencies = Set(foreign.map(\.currency))
        guard currencies.count == 1, let other = currencies.first else {
            return "≈ because some of it was paid in other currencies."
        }
        let total = foreign.reduce(0) { $0 + $1.amount }
        return "≈ because \(other.format(total)) of it was paid in another currency."
    }

    func daysSpent(in leg: Leg) -> Int {
        min(max(dayNumber - leg.startDay + 1, 0), leg.nights + 1)
    }

    /// Days spent in a country, across every leg that goes there.
    func daysSpent(inCountry country: String) -> Int {
        legs(inCountry: country).reduce(0) { $0 + daysSpent(in: $1) }
    }

    func sharedItemCount(currency: Currency) -> Int {
        spending.filter { $0.currency == currency && $0.shareOwedByOther > 0 && $0.payer != .both }.count
    }

    /// The part of the balance that came from bills paid in one currency,
    /// expressed back in that currency.
    func balance(in currency: Currency) -> Double {
        let home = expenses.live
            .filter { $0.currency == currency }
            .reduce(0) { $0 + inHome($1) * $1.balanceFactor }
        return fromHome(home, to: currency)
    }

    /// Positive: slot two owes slot one. Negative: the other way.
    var netBalanceHome: Double {
        expenses.live.reduce(0) { $0 + inHome($1) * $1.balanceFactor }
    }

    var debtor: Traveller { netBalanceHome >= 0 ? .two : .one }
    var creditor: Traveller { debtor.other }
    var balanceAmountHome: Double { abs(netBalanceHome) }

    func add(_ expense: Expense) {
        var line = expense
        line.updatedAt = now
        expenses.append(line)
    }

    /// Replaces a line in place, keeping its id so the other phone reads this as
    /// an edit rather than as a second expense.
    func update(_ expense: Expense) {
        guard let index = expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        var line = expense
        line.updatedAt = now
        expenses[index] = line
    }

    /// Marks a line deleted. A tombstone, never a removal.
    ///
    /// `merged(with:)` keeps whichever side was written last, so a delete can
    /// only beat a concurrent edit while the record is still there to carry the
    /// later timestamp. Removing it outright would let the other phone's copy
    /// walk back in on the next round.
    func delete(_ id: UUID) {
        guard let index = expenses.firstIndex(where: { $0.id == id }),
              !expenses[index].isDeleted else { return }
        expenses[index].deletedAt = now
        expenses[index].updatedAt = now
    }

    /// The undo: the same mechanism, run backwards, on a fresh timestamp.
    func restore(_ id: UUID) {
        guard let index = expenses.firstIndex(where: { $0.id == id }) else { return }
        expenses[index].deletedAt = nil
        expenses[index].updatedAt = now
    }

    // MARK: - The ledger, all of it

    /// Every live line, newest first.
    ///
    /// Tie-broken on the id. `merged(with:)` hands back `Array(byID.values)` —
    /// a dictionary's order — and `sorted` isn't stable, so two lines spent at
    /// the same moment could swap places between one draw and the next. One
    /// order for Money's recent lines and the full ledger, so the same line
    /// is never above another on one screen and below it on the other.
    var ledger: [Expense] {
        expenses.live.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
    }

    /// The ledger by trip day, newest day first. A line from before day 1
    /// keeps its own (zero or negative) day, so a deposit paid in March
    /// doesn't pretend to be the first night.
    var ledgerDays: [(day: Int, lines: [Expense])] {
        var order: [Int] = []
        var byDay: [Int: [Expense]] = [:]
        for line in ledger {
            let day = dayNumber(for: line.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(line)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    /// The heading over a day's lines: "Day 12 · Thu 16 Oct", or "Before day 1
    /// · 2 Mar" for money spent before they left.
    func ledgerHeading(forDay day: Int) -> String {
        let date = date(forDay: day)
        return day < 1
            ? "Before day 1 · \(date.text("d MMM"))"
            : "Day \(day) · \(date.text("EEE d MMM"))"
    }

    /// What a day's lines came to, in the money of the country they were in —
    /// with "≈" when a rate was needed. Settlements aren't spending and don't
    /// count; a day with only a settlement on it has no total.
    func ledgerTotal(forDay day: Int) -> String? {
        let lines = ledger.filter { $0.kind == .spend && dayNumber(for: $0.date) == day }
        guard !lines.isEmpty else { return nil }
        let money = leg(forDay: day)?.currency ?? homeCurrency
        let total = lines.reduce(0) { $0 + rates.snapshot.convert($1.amount, from: $1.currency, to: money) }
        return lines.contains { $0.currency != money }
            ? "≈\(money.formatRounded(total))"
            : money.format(total)
    }

    // MARK: - When it was spent

    /// The days an expense can be filed under, newest first: today, every
    /// earlier day of the trip, and day 0 for "before we left" — the flights
    /// and the deposit paid weeks ahead. Before departure "today" already *is*
    /// before they left, so it is the only answer.
    var expenseDays: [Int] {
        let today = trueDayNumber
        guard today >= 1 else { return [today] }
        return Array((0...today).reversed())
    }

    /// The moment to file a line under a day: now, for today; otherwise that
    /// day at this time of day, so lines still sort the way they were added.
    ///
    /// The clock time is *set*, not added. Adding 20 hours to midnight is 19:00
    /// on the day the clocks go back, and the checks caught it on exactly that
    /// day.
    func expenseDate(forDay day: Int) -> Date {
        guard day != trueDayNumber else { return now }
        let clock = Calendar.trip.dateComponents([.hour, .minute, .second], from: now)
        return Calendar.trip.date(bySettingHour: clock.hour ?? 12, minute: clock.minute ?? 0,
                                  second: clock.second ?? 0, of: date(forDay: day))
            ?? date(forDay: day)
    }

    /// The country to stamp on a line filed under a day — where they were
    /// *that* day, not today. Empty before day 1, and wherever no leg covers
    /// it, which `country(of:)` reads as "nobody had said".
    ///
    /// Today goes through `countryNow`, exactly as a new line always has.
    func expenseCountry(forDay day: Int) -> String {
        if day == trueDayNumber { return countryNow }
        guard day >= 1 else { return "" }
        return leg(forDay: day)?.country ?? ""
    }

    /// The chip that says which day a line is filed under.
    func expenseDayLabel(_ day: Int) -> String {
        let today = trueDayNumber
        if day == today { return "Today" }
        if day == today - 1, day >= 1 { return "Yesterday" }
        if day < 1 { return "Before we left" }
        return "Day \(day) · \(date(forDay: day).text("d MMM"))"
    }

    // MARK: - With no budget

    /// Nought is allowed, and means "we didn't set one" — not "we may spend
    /// nothing". Every sentence that judges spending against the budget asks
    /// this first.
    var hasBudget: Bool { budget > 0 }

    /// Money's headline: "€1,627 of €8,000", or "€1,627 spent" with no budget.
    /// It read "€1,627 of €0".
    var moneyHeadline: String {
        hasBudget
            ? "\(homeTextRounded(spentHome)) of \(homeTextRounded(budget))"
            : "\(homeTextRounded(spentHome)) spent"
    }

    /// The line under it. Against a budget, how far ahead of the burn they
    /// are; with none, what a day has cost so far, since "exactly on the
    /// burn" against a budget of nothing was the one verdict it could reach.
    var burnLine: String {
        let day = "Day \(dayNumber) of \(dayCount)"
        guard hasBudget else {
            guard spentHome > 0 else { return "\(day) · nothing spent yet." }
            return "\(day) · \(homeTextRounded(spentHome / Double(max(dayNumber, 1)))) a day so far."
        }
        let ahead = paceDaysAhead
        if ahead > 0 { return "\(day) — \(Formatting.spelledCount(ahead, "day", spellingUpTo: 0)) ahead of the burn." }
        if ahead < 0 { return "\(day) — \(Formatting.spelledCount(-ahead, "day", spellingUpTo: 0)) behind the burn." }
        return "\(day) — exactly on the burn."
    }

    /// The add-expense sheet's "Is this cheap?" — this amount against what a
    /// day is worth. Nil with no budget, and the panel goes with it; it drew
    /// as an empty box.
    func budgetComparison(forHome home: Double) -> String? {
        guard home > 0, hasBudget else { return nil }
        // Everything is priced against the budget they set, so the verdict
        // means something different for a €2,000 trip than a €9,000 one.
        let share = home / budgetPerDay
        if share < 0.1 {
            return "Under a tenth of a day's budget."
        }
        if share < 1 {
            return "About \(Int((share * 100).rounded()))% of a day's budget — \(homeTextRounded(budgetPerDay)) is what a day is worth on this trip."
        }
        return "That's \(String(format: "%.1f", share)) days of budget, at \(homeTextRounded(budgetPerDay)) a day."
    }

    /// Whether Money should offer to set a budget: none set, a traveller's
    /// phone on a live trip — the observer sets no trip parameters — and
    /// offered fewer than three times.
    var offersBudgetNudge: Bool {
        !hasBudget && !isObserver && isLive && budgetNudgeShows < 3
    }

    /// Counts one showing. Called once per visit to Money, never per draw.
    func noteBudgetNudgeShown() {
        guard offersBudgetNudge else { return }
        budgetNudgeShows += 1
    }

    // MARK: - Settling, which takes both of them

    var pendingSettlement: SettlementProposal? {
        settlements.live.filter(\.isPending).max { $0.proposedAt < $1.proposedAt }
    }

    /// True when the pending proposal is waiting on *this* phone.
    var settlementNeedsMyConfirmation: Bool {
        pendingSettlement.map { $0.awaiting == role } ?? false
    }

    @discardableResult
    func proposeSettlement(note: String, in currency: Currency? = nil) -> SettlementProposal? {
        let balance = netBalanceHome
        guard abs(balance) > 0.005 else { return nil }
        let paidIn = currency ?? homeCurrency
        let proposal = SettlementProposal(
            proposedBy: role,
            debtor: debtor,
            amountHome: abs(balance),
            paidIn: paidIn,
            amountPaid: fromHome(abs(balance), to: paidIn),
            note: note,
            country: countryNow,
            proposedAt: now,
            updatedAt: now
        )
        settlements.append(proposal)
        return proposal
    }

    /// Agrees to a pending proposal.
    ///
    /// - Parameter inPerson: both of them at this phone. The one who agrees
    ///   is then whoever the proposal is waiting on, not whoever holds the
    ///   phone — the phone's holder is usually the one who proposed it.
    func confirmSettlement(_ id: UUID, inPerson: Bool = false) {
        guard let index = settlements.firstIndex(where: { $0.id == id }),
              settlements[index].isPending else { return }
        settlements[index].confirmedBy = inPerson ? settlements[index].awaiting : role
        settlements[index].confirmedAt = now
        if inPerson { settlements[index].confirmedInPerson = true }
        settlements[index].updatedAt = now
        applyConfirmedSettlements()
    }

    /// Whether a tab can be cleared at one phone, with both of them there.
    ///
    /// Only while this build can't reach the other phone. Two phones confirming
    /// is the design; without sync it is also a promise nothing can keep, and
    /// a tab that can never clear is a ledger that is wrong forever. Once
    /// there is somebody to invite, settling goes back to taking both phones.
    var settlesOnOnePhone: Bool { !sync.canInvite && !isObserver }

    /// Proposes and agrees in one step, both of them at this phone.
    @discardableResult
    func settleTogether(note: String, in currency: Currency? = nil) -> SettlementProposal? {
        guard settlesOnOnePhone, let proposal = proposeSettlement(note: note, in: currency) else { return nil }
        confirmSettlement(proposal.id, inPerson: true)
        return settlements.first { $0.id == proposal.id }
    }

    // MARK: - What settling nets

    /// The currencies Settle up lists: every one the itinerary spends, then any
    /// other a shared line was paid in — the euro card payment in Thailand.
    /// Listing only the itinerary's left those lines out of the rows while
    /// counting them in the net beneath, so the rows didn't add up.
    var settleCurrencies: [Currency] {
        var list = tripCurrencies
        for line in ledger.reversed() where !list.contains(line.currency) && balanceMoves(line) {
            list.append(line.currency)
        }
        return list
    }

    private func balanceMoves(_ line: Expense) -> Bool {
        line.kind == .transfer || (line.shareOwedByOther > 0 && line.payer != .both)
    }

    /// The line under the headline, counted rather than written. It said
    /// "Across three currencies" on every trip, including one-currency trips
    /// and trips with nothing shared at all.
    var settleCurrencyLine: String {
        let used = settleCurrencies.filter { sharedItemCount(currency: $0) > 0 }
        switch used.count {
        case 0: return "Nothing shared yet."
        case 1: return "All in one currency, so nothing to convert."
        default:
            let count = Formatting.spelledCount(used.count, "currency", plural: "currencies", spellingUpTo: 10)
            return "Across \(count.prefix(1).lowercased() + count.dropFirst()), netted down to one number."
        }
    }

    func cancelSettlement(_ id: UUID) {
        guard let index = settlements.firstIndex(where: { $0.id == id }),
              settlements[index].isPending else { return }
        settlements[index].cancelledAt = now
        settlements[index].updatedAt = now
    }

    /// Writes the `.transfer` for every confirmed proposal that hasn't produced
    /// one yet. The expense borrows the proposal's id, so both phones applying
    /// the same settlement converge on one line instead of two.
    func applyConfirmedSettlements() {
        for proposal in settlements.live where proposal.isConfirmed {
            guard !expenses.contains(where: { $0.id == proposal.id }) else { continue }
            let payer: Payer = proposal.debtor == .two ? .two : .one
            expenses.append(Expense(
                id: proposal.id,
                date: proposal.confirmedAt ?? proposal.proposedAt,
                amount: proposal.amountPaid,
                currency: proposal.paidIn,
                payer: payer,
                split: .evenly,
                note: proposal.note,
                // The proposal's country, not this phone's — see `country` on
                // `SettlementProposal`.
                country: proposal.country,
                kind: .transfer,
                updatedAt: proposal.updatedAt
            ))
        }
    }

    // MARK: - Letters

    /// Whether this phone draws a letterbox at all.
    ///
    /// Asks what is on the phone, not who is holding it. The box is addressed
    /// (`LetterDrop.recipient`), so a phone that isn't the recipient collects
    /// nothing — and an empty letterbox would still be a reference to a channel
    /// that may not exist, so an empty set draws nothing.
    var lettersVisible: Bool { features.letters && !letters.isEmpty }

    /// What the other phone can see, worked out from what this trip actually
    /// has and what `SyncPayload` actually carries.
    ///
    /// Derived, because the stored `sharingRules` is sample data and is empty on
    /// every trip made through onboarding — see `SharingLine`. Gated on
    /// `features` for the same reason a switched-off feature has no tab: a line
    /// about the ledger on a trip with no shared ledger is a promise about a
    /// screen that isn't there.
    ///
    /// The letters line is deliberately keyed on the *feature* and not on
    /// `lettersVisible`, which asks whether any have arrived. This is the one
    /// screen where saying "there are none on this phone" is the right thing to
    /// do rather than a reference to a channel that may not exist — everywhere
    /// else, silence.
    var whatTravels: [SharingLine] {
        var lines: [SharingLine] = []
        if features.sharedLedger {
            lines.append(SharingLine(
                title: "Money", detail: "Every expense and every settling-up, both ways.",
                state: "shared", isShared: true, fields: ["expenses", "settlements"]))
        }
        lines.append(SharingLine(
            title: "Plans and the itinerary", detail: "Either of you can change them.",
            state: "shared", isShared: true, fields: ["itinerary", "dayPlans"]))
        if features.stamps {
            lines.append(SharingLine(
                title: "The trail", detail: "One trail, both of you, wherever it goes.",
                state: "shared", isShared: true, fields: ["stamps"]))
        }
        lines.append(SharingLine(
            title: "Tonight's meeting point", detail: "And everywhere you have already agreed to meet.",
            state: "shared", isShared: true, fields: ["meetingPoint", "meetingPlaces"]))
        lines.append(SharingLine(
            title: "Cards to show people", detail: "Written once, on whichever phone is nearer.",
            state: "shared", isShared: true, fields: ["showCards"]))
        if features.nightlyPage || features.printedBooks {
            lines.append(SharingLine(
                title: "Your pages", detail: "Nobody reads them until the books are printed.",
                state: "private", isShared: false, fields: []))
        }
        lines.append(SharingLine(
            title: "Moments", detail: "Yours. They travel no further than this phone.",
            state: "private", isShared: false, fields: []))
        if features.letters {
            lines.append(SharingLine(
                title: "Letters", detail: "Sealed, and never says when one was read.",
                state: "private", isShared: false, fields: []))
        }
        lines.append(SharingLine(
            title: "Passports and scans", detail: "Encrypted here, and they do not leave.",
            state: "never", isShared: false, fields: []))
        lines.append(SharingLine(
            title: "Where you are", detail: "For moments, pins, the trail, the meeting point and Separated. Never in the background. Only a pin's spot and a pinned meeting point leave this phone.",
            state: "on demand", isShared: false, fields: []))
        return lines
    }

    var openLetters: [Letter] {
        letters.filter(\.isOpen).sorted { $0.number > $1.number }
    }

    /// Sealed, with a condition the reader is allowed to see.
    var sealedLetters: [Letter] {
        letters.filter { !$0.isOpen && $0.isSealed && !$0.secretCondition }
            .sorted { $0.number < $1.number }
    }

    /// Sealed with the condition withheld. These show as a count and nothing
    /// else.
    var hiddenLetterCount: Int {
        letters.filter { !$0.isOpen && $0.isSealed && $0.secretCondition }.count
    }

    /// "1 open · 2 sealed", with each clause dropped when it would be a nought.
    ///
    /// Hidden letters count as sealed: the count is all the reader is allowed
    /// of them. Nil with no letters, which is never drawn anyway.
    var letterTally: String? {
        let open = openLetters.count
        let sealed = sealedLetters.count + hiddenLetterCount
        var clauses: [String] = []
        if open > 0 { clauses.append("\(open) open") }
        if sealed > 0 { clauses.append("\(sealed) sealed") }
        return clauses.isEmpty ? nil : clauses.joined(separator: " · ")
    }

    /// "The next one opens in Hội An." The anticipation, said under the tally.
    ///
    /// The soonest by the schedule's own guess at a day, so Today and the
    /// writer's board agree on what "next" is. A withheld condition is never
    /// the next one: naming where it opens is the one thing it withholds. Nil
    /// when nothing sealed can be placed — a letter waiting to be online has
    /// already opened by the time anybody reads this.
    var nextLetterLine: String? {
        guard !isObserver, features.letters else { return nil }
        let waiting = Set(letters.filter {
            $0.isSealed && !$0.isOpen && !$0.secretCondition && $0.condition != .nextOnline
        }.map(\.id))
        guard !waiting.isEmpty,
              let next = letterSchedule.placements
                .filter({ waiting.contains($0.id) })
                .min(by: { ($0.day, $0.number) < ($1.day, $1.number) })
        else { return nil }
        switch next.condition {
        case .place(let name):
            return "The next one opens in \(name)."
        case .stamp(let code):
            if let city = orderedStamps.first(where: { $0.code == code })?.city {
                return "The next one opens in \(city)."
            }
            return "The next one opens with the \(code) stamp."
        case .day(let day):
            return day == dayNumber + 1 ? "The next one opens tomorrow." : "The next one opens on day \(day)."
        case .finalStamp:
            return "The next one opens with the last stamp."
        case .nextOnline, .hidden:
            return nil
        }
    }

    var newestOpenLetter: Letter? {
        letters.filter(\.isOpen).max { ($0.openedOn ?? .distantPast) < ($1.openedOn ?? .distantPast) }
    }

    /// Opens one letter, by number, at a place.
    ///
    /// The guards carry weight. A stamp whose `unlocksLetter` points at a draft
    /// must not open it, and the observer's phone draws the trail too — so
    /// without `!isObserver` a pin dropped at home would mark a letter still
    /// being written as read.
    func open(letterNumber: Int, place: String) {
        guard !isObserver, features.letters,
              let index = letters.firstIndex(where: { $0.number == letterNumber }),
              letters[index].isSealed, !letters[index].isOpen
        else { return }
        letters[index].openedOn = now
        letters[index].openedPlace = place
    }

    // MARK: - Letters, from the other side

    /// This phone belongs to whoever stayed home. The whole app changes, not a
    /// few rows of it.
    var isObserver: Bool { participant.isObserver }

    /// Everything the observer has sealed, in the order they wrote them.
    var sealedByWriter: [Letter] {
        letters.filter(\.isSealed).sorted { $0.number < $1.number }
    }

    var writerDrafts: [Letter] {
        letters.filter(\.isDraft).sorted { $0.number < $1.number }
    }

    /// J1 · what the home screen counts. "Delivered" means the condition has
    /// been met — never that the letter was read, which is not reported back.
    var deliveredCount: Int {
        sealedByWriter.filter { $0.condition.isMet(letterMoment) }.count
    }

    var stillSealedCount: Int { sealedByWriter.count - deliveredCount }

    var nextLetterNumber: Int { (letters.map(\.number).max() ?? 0) + 1 }

    /// Everything a condition needs to decide, gathered once.
    var letterMoment: LetterMoment {
        LetterMoment(
            dayNumber: dayNumber,
            city: currentCity,
            earnedStampCodes: Set(earnedStamps.map(\.code)),
            earnedStampCities: Set(earnedStamps.map(\.city)),
            allStampsEarned: !orderedStamps.isEmpty && earnedStamps.count == orderedStamps.count,
            justArrived: false,
            // What the trip still has, so a condition naming something that was
            // removed can be told from one that simply hasn't happened yet.
            knownStampCodes: Set(orderedStamps.map(\.code)),
            knownPlaces: Set(orderedStamps.map(\.city))
                .union(itinerary.allSegments.flatMap(\.places))
        )
    }

    // J3's option list is built by `ConditionPickerView`, which is the only
    // thing that ever needed it — and which dedupes its day candidates through
    // a `Set`. A second, unreachable copy lived here and did not: `.day(dayCount
    // / 2)` can equal `.day(dayNumber + 1)`, so it could hand the same
    // condition back twice.

    @discardableResult
    func startLetter(title: String, condition: LetterCondition) -> Letter {
        let letter = Letter(number: nextLetterNumber, title: title, writtenOn: now,
                            condition: condition, hint: condition.summary.lowercased(),
                            paragraphs: [], signature: "— me, obviously", sealedAt: nil)
        letters.append(letter)
        return letter
    }

    func updateDraft(_ id: UUID, title: String? = nil, paragraphs: [String]? = nil,
                     condition: LetterCondition? = nil, signature: String? = nil) {
        guard let index = letters.firstIndex(where: { $0.id == id }), letters[index].isDraft else { return }
        if let title { letters[index].title = title }
        if let paragraphs { letters[index].paragraphs = paragraphs }
        if let condition {
            letters[index].condition = condition
            letters[index].hint = condition.summary.lowercased()
        }
        if let signature { letters[index].signature = signature }
    }

    func discardDraft(_ id: UUID) {
        letters.removeAll { $0.id == id && $0.isDraft }
    }

    /// For the composer on its way out: a draft with no title and no words is
    /// not a draft anybody wrote. "Write a letter" makes one before the sheet
    /// opens, and every swipe away used to leave another numbered blank behind.
    ///
    /// - Returns: whether it went.
    @discardableResult
    func discardDraftIfEmpty(_ id: UUID) -> Bool {
        guard let letter = letters.first(where: { $0.id == id }), letter.isDraft,
              letter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              letter.paragraphs.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return false }
        discardDraft(id)
        return true
    }

    /// J2/J4 · sealing is one-way, and it is what makes the condition binding.
    /// After this the letter can't be edited, re-keyed or withdrawn.
    func seal(_ id: UUID) {
        guard let index = letters.firstIndex(where: { $0.id == id }), letters[index].isDraft else { return }
        letters[index].sealedAt = now
    }

    /// Posts the sealed set to whoever it is for. Drafts are excluded by
    /// construction rather than by a filter, and in home mode `role` *is* the
    /// recipient, so the address needs no field of its own.
    func postLetters() async {
        // A closed letterbox is not a failed post. Trying would record its
        // refusal as `lastPostFailure`, and the screen would print an error
        // where the plain reason belongs.
        guard isObserver, isLive, letterPost.isAvailable else { return }
        let drop = LetterDrop(tripID: tripID, recipient: role,
                              letters: sealedByWriter.map { SealedLetter($0, sealedAt: $0.sealedAt ?? $0.writtenOn) },
                              updatedAt: now)
        // Not `try?`: a post that never left the phone has to be
        // distinguishable from one that did, or the screen reports a delivery
        // that didn't happen.
        do {
            try await letterPost.post(drop, to: role, sealingTo: letterKeys_[role])
            lastPostFailure = nil
            lastPostedAt = now
        } catch {
            lastPostFailure = error.localizedDescription
        }
    }

    /// True when the sealed set is sitting on this phone rather than in a box
    /// the traveller can reach — either because this build has no postal
    /// service, or because the last post failed.
    var lettersAreStuck: Bool {
        guard isObserver else { return false }
        return letterPost.unavailableReason != nil || lastPostFailure != nil
    }

    /// Why, in one sentence, or `nil` when the post is getting out.
    var letterPostProblem: String? {
        guard isObserver else { return nil }
        return lastPostFailure ?? letterPost.unavailableReason
    }

    /// The traveller's side of the same channel. Anything new arrives sealed and
    /// unopened, and anything already here keeps its own read state — the drop
    /// has no field that could overwrite it.
    ///
    /// Collects at this phone's own address. There is no check for *being* the
    /// recipient, because there is nothing at anybody else's address to find.
    ///
    /// - Returns: the letters that opened as a result.
    @discardableResult
    func collectLetters() async -> [Letter] {
        guard !isObserver, features.letters, isLive,
              let drop = try? await letterPost.collect(tripID: tripID, for: role,
                                                       opening: try? letterKeys.privateKey())
        else { return [] }

        var arrivedIDs: Set<UUID> = []
        for sealed in drop.letters where !letters.contains(where: { $0.id == sealed.id }) {
            letters.append(Letter(received: sealed, at: now))
            arrivedIDs.insert(sealed.id)
        }
        return openDueLetters(justArrivedIDs: arrivedIDs)
    }

    /// Opens every sealed letter whose condition is now met.
    ///
    /// The opening is recorded on this phone only — the place and the time, for
    /// the book. Nothing sends it back.
    @discardableResult
    func openDueLetters(justArrivedIDs: Set<UUID> = []) -> [Letter] {
        guard !isObserver, features.letters else { return [] }
        var opened: [Letter] = []
        // Built once. It is a fact about the trip, not about the letter being
        // asked — and opening one changes nothing in it — so rebuilding it per
        // letter cost five `Set` allocations and a walk of every waypoint and
        // every stop, per letter, on every wake.
        let base = letterMoment
        for index in letters.indices where !letters[index].isOpen && letters[index].isSealed {
            var moment = base
            moment.justArrived = justArrivedIDs.contains(letters[index].id)
            guard letters[index].condition.isMet(moment) else { continue }
            letters[index].openedOn = now
            // Where the *condition* was met, not where the itinerary says they
            // are: a letter keyed to one city can fire on a day the plan puts
            // them in the next one, and this place goes in the book.
            letters[index].openedPlace = place(satisfying: letters[index].condition) ?? currentCity
            opened.append(letters[index])
        }
        return opened
    }

    /// The place that satisfied a condition, where the condition names one.
    /// Nil for conditions that aren't about a place — a day, or "next time
    /// you're online" — which fall back to where they are.
    private func place(satisfying condition: LetterCondition) -> String? {
        switch condition {
        case .place(let name): name
        case .stamp(let code): earnedStamps.first { $0.code == code }?.city
        case .finalStamp: earnedStamps.last?.city
        case .day, .nextOnline, .hidden: nil
        }
    }

    /// J10 · written, sealed, and never fired. There is no control that re-keys
    /// one to somewhere they did reach; sealing is one-way.
    var undeliveredLetters: [Letter] {
        guard phase.isAfter || !isLive else { return [] }
        let moment = letterMoment
        return sealedByWriter.filter { !$0.condition.isMet(moment) && !$0.isOpen }
    }

    /// J5 · the board.
    var letterSchedule: LetterSchedule {
        LetterSchedule.build(
            letters: letters.filter { $0.condition != .hidden },
            dayCount: dayCount,
            dayForPlace: { [weak self] name in
                guard let self else { return nil }
                if let stamp = self.orderedStamps.first(where: { $0.city == name }),
                   let segment = self.segment(for: stamp) {
                    return segment.startDay
                }
                return self.segment(namingCity: name)?.startDay
            },
            dayForStamp: { [weak self] code in
                guard let self, let stamp = self.orderedStamps.first(where: { $0.code == code }) else { return nil }
                return self.segment(for: stamp)?.startDay
            }
        )
    }

    // MARK: - Trail

    var earnedStamps: [Stamp] { stamps.live.filter(\.earned).sorted { $0.index < $1.index } }
    var orderedStamps: [Stamp] { stamps.live.sorted { $0.index < $1.index } }
    var nextStamp: Stamp? { orderedStamps.first { !$0.earned } }

    /// The stop a waypoint belongs to.
    ///
    /// One join, in one place. Prefers the id and falls back to matching on the
    /// name, which covers a waypoint saved before the field existed and one
    /// whose stop was merged away.
    func segment(for stamp: Stamp) -> Segment? {
        if let segmentID = stamp.segmentID,
           let segment = itinerary.allSegments.first(where: { $0.id == segmentID }) {
            return segment
        }
        return itinerary.allSegments.first { $0.names(city: stamp.city) }
    }

    /// The first stop whose title names a place, for a letter keyed to a city
    /// no waypoint carries.
    func segment(namingCity city: String) -> Segment? {
        itinerary.allSegments.first { $0.names(city: city) }
    }

    /// Attaches waypoints saved before the join existed to the stops they name.
    ///
    /// Non-destructive, idempotent, and cautious: it attaches only where the
    /// match is unique in *both* directions, so a stop naming two places claims
    /// neither and both keep the name match. Nothing is ever guessed.
    ///
    /// Runs after init and after a merge, because the itinerary arriving from
    /// the other phone carries its own segment ids.
    func backfillWaypointJoins() {
        let segments = itinerary.allSegments
        guard !segments.isEmpty else { return }
        for index in stamps.indices where stamps[index].segmentID == nil {
            let city = stamps[index].city
            let matching = segments.filter { $0.names(city: city) }
            guard matching.count == 1, let segment = matching.first else { continue }
            let claimants = stamps.live.filter { $0.segmentID == nil && segment.names(city: $0.city) }
            guard claimants.count == 1 else { continue }
            // Not an edit anybody made, so `updatedAt` stays put: both phones
            // derive the same answer, and bumping it would let a backfill win
            // against a real edit.
            stamps[index].segmentID = segment.id
        }
    }

    /// Where a waypoint sits, as a position in the plan rather than a number
    /// somebody typed.
    ///
    /// Goes through `segment(for:)`, so a waypoint that never named a stop
    /// still lands where its city does. One that resolves to nothing sorts
    /// last, on its stored number.
    ///
    /// - Parameter positions: stop id → its place in the plan, built once by
    ///   the caller. `allSegments` is a `flatMap` that allocates the whole
    ///   array every time it is read, and this used to read it up to three
    ///   times *inside a sort comparator* — so renumbering eleven waypoints
    ///   rebuilt the itinerary about a hundred times.
    private func planPosition(of stamp: Stamp, in positions: [UUID: Int]) -> (Int, Int) {
        guard let segment = segment(for: stamp), let position = positions[segment.id]
        else { return (Int.max, stamp.index) }
        return (position, stamp.index)
    }

    /// Renumbers the waypoints from the order of the stops they belong to.
    ///
    /// The same relationship `reflow()` has to `startDay`/`endDay`: order is
    /// the authority and the number is derived, which makes a gap or a
    /// duplicate unrepresentable.
    ///
    /// Renumbering is an *edit* to every waypoint that moved, so each one is
    /// re-stamped. Without that the other phone merges the new order back out.
    ///
    /// The earned ones come first, in the order they were earned: the trail is
    /// where they have been, then where they are going. Ordering them by plan
    /// too sent an earned stamp to the end of the trail the moment its stop was
    /// removed, behind places nobody has reached.
    func reflowWaypoints() {
        var positions: [UUID: Int] = [:]
        for (offset, segment) in itinerary.allSegments.enumerated() { positions[segment.id] = offset }
        let earned = stamps.live.filter(\.earned).sorted {
            ($0.earnedOn ?? .distantPast, $0.index) < ($1.earnedOn ?? .distantPast, $1.index)
        }
        let ahead = stamps.live.filter { !$0.earned }.sorted {
            planPosition(of: $0, in: positions) < planPosition(of: $1, in: positions)
        }
        let live = earned + ahead
        var wanted: [UUID: Int] = [:]
        for (offset, stamp) in live.enumerated() { wanted[stamp.id] = offset + 1 }
        for index in stamps.indices {
            guard let number = wanted[stamps[index].id], stamps[index].index != number else { continue }
            stamps[index].index = number
            stamps[index].updatedAt = now
        }
    }

    // MARK: - Editing the waypoints

    /// Stamps nobody has earned whose stop is gone.
    ///
    /// Removing a stop takes its stamps now, but a merge can still make one:
    /// the other phone removes a stop while this one gives it a stamp. Left
    /// alone it is "next" on the trail, reachable from no stop, and holds every
    /// letter sealed to the last stamp shut — so the editor lists them, and
    /// each one is put on a stop or let go.
    var orphanedWaypoints: [Stamp] {
        orderedStamps.filter { !$0.earned && segment(for: $0) == nil }
    }

    /// Puts a waypoint on a stop. Refuses an earned one, which is a record.
    @discardableResult
    func attachWaypoint(_ id: UUID, toSegment segmentID: UUID) -> Bool {
        guard !isObserver else { return false }
        guard let index = stamps.firstIndex(where: { $0.id == id }), !stamps[index].isDeleted,
              !stamps[index].earned,
              itinerary.allSegments.contains(where: { $0.id == segmentID }) else { return false }
        stamps[index].segmentID = segmentID
        stamps[index].updatedAt = now
        reflowWaypoints()
        return true
    }

    /// The waypoints on a stop, in plan order.
    ///
    /// Plural, and it has to be: one stop can name two places and hold two
    /// waypoints, and returning only the first would leave the second
    /// unreachable from every screen.
    func waypoints(forSegment id: UUID) -> [Stamp] {
        stamps.live.filter { segment(for: $0)?.id == id }.sorted { $0.index < $1.index }
    }

    /// Every letter that names this waypoint — by its code, by its city, or by
    /// being the one it was packed to open.
    ///
    /// The join is a string on both sides. The condition's `summary` is the
    /// sentence the traveller was told, so keying it to an id would let the
    /// binding and the sentence drift apart.
    func lettersDepending(on stamp: Stamp) -> [Letter] {
        letters.filter { letter in
            if let number = stamp.unlocksLetter, letter.number == number { return true }
            switch letter.condition {
            case .stamp(let code): return code == stamp.code
            case .place(let name): return name == stamp.city
            default: return false
            }
        }
    }

    /// Why this waypoint can't be changed, in the words the editor shows, or
    /// `nil` when it can.
    ///
    /// Earned is the one locked state. `earnedOn` records somebody standing
    /// somewhere, and it backs the trail, the distance, `openedPlace` on
    /// letters that already fired, and the book's grid.
    ///
    /// The date, and nothing else: the absence of any control is what says it
    /// is locked, and the rule itself belongs in the arrival dialog, which
    /// states it there. A rule repeated under every earned waypoint wraps to
    /// three lines at an accessibility size.
    func waypointIsLocked(_ stamp: Stamp) -> String? {
        guard stamp.earned else { return nil }
        return "earned \(stamp.earnedOn?.stampDate ?? "on the trip")"
    }

    /// What removing this waypoint would cost, or `nil` if it costs nothing.
    ///
    /// Sealed letters are named rather than refused. Sealing is one-way and the
    /// writer can't re-key it, so removing the waypoint strands the letter —
    /// which is the traveller's call to make, with the number in front of them.
    func removalCost(ofWaypoint stamp: Stamp) -> String? {
        let sealed = lettersDepending(on: stamp).filter { !$0.isDraft && !$0.isOpen }
        guard !sealed.isEmpty else { return nil }
        // A secret condition stays secret: naming the letter here would give
        // away what the writer withheld.
        if sealed.contains(where: \.secretCondition) {
            return "Something sealed is waiting on this stamp. Removing it means that never opens."
        }
        let numbers = sealed.map { String(format: "%02d", $0.number) }.joined(separator: ", ")
        return sealed.count == 1
            ? "Letter \(numbers) opens with this stamp. Removing it means it never opens."
            : "Letters \(numbers) open with this stamp. Removing it means they never open."
    }

    /// Why removing this waypoint is refused outright, or `nil` if it is only a
    /// thing to confirm.
    ///
    /// The mirror of `appendCost`'s refusal. `.finalStamp` means "every
    /// waypoint earned", so removing the last *unearned* one completes the
    /// trail, and every letter sealed to the last stamp opens on the spot with
    /// `openedOn` and `openedPlace` written for good.
    func removalRefusal(ofWaypoint stamp: Stamp) -> String? {
        guard !stamp.earned else { return nil }
        let live = stamps.live
        let unearned = live.filter { !$0.earned }
        guard unearned.count == 1, unearned.first?.id == stamp.id, live.count > 1 else { return nil }
        let waiting = letters.filter { $0.condition == .finalStamp && !$0.isDraft && !$0.isOpen }
        guard !waiting.isEmpty else { return nil }
        return "This is the last stop nobody has stood in. Removing it opens the letter sealed to the last stamp, right here, and that can't be taken back."
    }

    /// What appending a waypoint would cost a letter sealed to the last one.
    ///
    /// `.finalStamp` is "every waypoint earned", so a new one puts it back out
    /// of reach. Refused outright once the trail is already complete: there is
    /// no honest way to take back a letter somebody has read.
    func appendCost() -> (refused: Bool, message: String?) {
        let moment = letterMoment
        let finals = letters.filter { $0.condition == .finalStamp && !$0.isDraft }
        guard !finals.isEmpty else { return (false, nil) }
        if moment.allStampsEarned {
            return (true, "A letter opens with the last stamp, and the last stamp is already earned. Adding a stop now would take it back.")
        }
        let numbers = finals.map { String(format: "%02d", $0.number) }.joined(separator: ", ")
        return (false, "Letter \(numbers) opens with the last stamp. Adding a stop means it waits for this one too.")
    }

    /// Whether a code can be used: two to four characters, and nobody else's.
    ///
    /// The ceiling isn't cosmetic. `BookSpreadView` draws the code inside a
    /// circle with no `lineLimit` and no `minimumScaleFactor`, in a book that
    /// gets bound.
    func codeIsAvailable(_ code: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard (2...4).contains(trimmed.count) else { return false }
        guard !stamps.live.contains(where: { $0.id != id && $0.code == trimmed }) else { return false }

        // A code a sealed letter still names can't be handed to a different
        // stop. Removing the waypoint is allowed and leaves the letter dead,
        // but `stamps.live` can't see the tombstone — so without this the code
        // comes free and a new waypoint picks it up, opening the letter at a
        // stamp the writer never chose.
        //
        // Cities get no such rule: a place *is* the place, so a new waypoint
        // for a city firing the letter sealed to that city is right. A code is
        // an arbitrary label.
        let claimed = letters.contains { letter in
            guard !letter.isDraft, case .stamp(let sealed) = letter.condition else { return false }
            return sealed == trimmed
        }
        guard claimed else { return true }
        return stamps.first { $0.id == id }?.code == trimmed
    }

    /// The waypoint already standing for a city, if there is one.
    ///
    /// A country can be entered twice and so can a city — Bangkok on the way
    /// out and Bangkok on the way home is an ordinary route — so this answers
    /// "has this place been stamped already", which is the question behind the
    /// suggested code below. Folded and trimmed, because the two spellings come
    /// from two different typings of the same name.
    func waypoint(forCity city: String) -> Stamp? {
        let key = cityKey(city)
        guard !key.isEmpty else { return nil }
        return orderedStamps.first { cityKey($0.city) == key }
    }

    /// A code nobody is using, derived from a city name.
    ///
    /// The code is the letter's address — `.stamp("BKK")` is what somebody at
    /// home seals to — so two stops cannot share one, and a city visited twice
    /// therefore needs a second label. That rule is right and the friction was
    /// never the rule: it was being refused *after* typing the obvious answer.
    /// So the second Bangkok is offered `BKK2`, derived from the first one's own
    /// code rather than from the city, which is what makes it recognisable as
    /// Bangkok on the writing screen weeks later.
    ///
    /// Empty when nothing is free — an empty field somebody fills in beats a
    /// suggestion that will be refused.
    func suggestedCode(forCity city: String) -> String {
        let trimmed = city.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if let already = waypoint(forCity: trimmed) {
            return numberedCode(from: already.code) ?? ""
        }
        // Two letters at least, and not only because the field takes two: the
        // suggestion is recomputed on every keystroke of a new stop's title, so
        // a one-letter base numbering itself would flash `H2` on the way into
        // "Hue". A name that short is left to be typed.
        let letters = codeLetters(in: trimmed)
        guard letters.count >= 2 else { return "" }
        let base = String(letters.prefix(3))
        if codeIsAvailable(base) { return base }
        return numberedCode(from: base) ?? ""
    }

    private func cityKey(_ city: String) -> String {
        city.trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The letters a code can be built from. Folded, because "Hội An" has to
    /// answer HOI: the code prints inside a circle in a bound book and the
    /// field takes two to four of them.
    private func codeLetters(in city: String) -> String {
        city.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
            .filter { $0.isLetter && $0.isASCII }
    }

    /// `BKK` → `BKK2`, and on past anything taken. The stem is cut to three so
    /// the digit still fits inside the four-character ceiling.
    private func numberedCode(from base: String) -> String? {
        let stem = String(codeLetters(in: base).prefix(3))
        guard !stem.isEmpty else { return nil }
        return (2...9).lazy.map { stem + String($0) }.first { codeIsAvailable($0) }
    }

    // MARK: - Where a typed waypoint is

    /// Where a city is, looked up in the bundled list inside one country.
    /// The stop sheets ask before the stop exists, so this takes the country.
    func position(ofCity city: String, inCountry country: String) -> CityPositions.Position? {
        cityList()?.position(of: city, inCountry: country)
    }

    private func position(ofCity city: String, onSegment id: UUID?) -> CityPositions.Position? {
        guard let id, let leg = legs.first(where: { $0.segments.contains { $0.id == id } }) else { return nil }
        return position(ofCity: city, inCountry: leg.country)
    }

    /// Where the plan goes, as far as the city list knows: every stop's places,
    /// in plan order, looked up inside the stop's own country.
    ///
    /// For the map to frame before any waypoint has a position. It used to
    /// fall back to a fixed point over Bangkok, which was the sample trip's
    /// first city and every other trip's wrong one. Empty when nothing can be
    /// placed, and then the map draws nothing rather than somewhere.
    var itineraryPositions: [CityPositions.Position] {
        legs.flatMap { leg in
            leg.segments.flatMap { segment in
                segment.places.compactMap { position(ofCity: $0, inCountry: leg.country) }
            }
        }
    }

    /// Gives every waypoint nobody has stood in, and that has no position, the
    /// one the city list has for it.
    ///
    /// Without one, the nudge, the distance to the next stop and the map ahead
    /// never happen on a trip that was typed. Both phones read the same list,
    /// so it is not an edit and `updatedAt` stays put, the way
    /// `backfillWaypointJoins()` leaves it. Only a blank is filled: an earned
    /// waypoint keeps the fix it was earned with, and a packed one its own.
    func backfillWaypointPositions() {
        let missing = stamps.indices.filter {
            !stamps[$0].isDeleted && !stamps[$0].earned && !stamps[$0].hasLocation
        }
        guard !missing.isEmpty else { return }
        for index in missing {
            guard let found = position(ofCity: stamps[index].city,
                                       onSegment: segment(for: stamps[index])?.id) else { continue }
            stamps[index].latitude = found.latitude
            stamps[index].longitude = found.longitude
        }
    }

    /// Gives a stop a waypoint. `nil` when it is refused.
    @discardableResult
    func addWaypoint(code: String, city: String, arrivalNote: String,
                     toSegment segmentID: UUID) -> Stamp? {
        guard !isObserver else { return nil }
        guard appendCost().refused == false else { return nil }
        let trimmedCode = code.trimmingCharacters(in: .whitespaces).uppercased()
        let trimmedCity = city.trimmingCharacters(in: .whitespaces)
        guard codeIsAvailable(trimmedCode), !trimmedCity.isEmpty else { return nil }
        guard itinerary.allSegments.contains(where: { $0.id == segmentID }) else { return nil }
        // No cap on how many a stop may hold: one that names two places has
        // two, and refusing the second leaves the first standing for both.

        var stamp = Stamp(code: trimmedCode, city: trimmedCity,
                          // Reflowed immediately, so this is only a starting
                          // position — past any tombstone, so a removed
                          // waypoint can't leave a new one in its slot.
                          index: (stamps.map(\.index).max() ?? 0) + 1,
                          arrivalNote: arrivalNote.trimmingCharacters(in: .whitespacesAndNewlines),
                          segmentID: segmentID, updatedAt: now)
        if let found = position(ofCity: trimmedCity, onSegment: segmentID) {
            stamp.latitude = found.latitude
            stamp.longitude = found.longitude
        }
        stamps.append(stamp)
        reflowWaypoints()
        return stamp
    }

    /// Changes a waypoint's code, city or arrival note. Refuses an earned one
    /// outright; everything else is the caller's to confirm first.
    ///
    /// Every field is validated before any of them is written. It used to
    /// validate and mutate a field at a time, so a call with a good code and an
    /// empty city changed the code, re-keyed the drafts that named it, returned
    /// `false` — and never reached the `updatedAt` at the bottom, which is what
    /// makes an edit visible to the merge. The other phone would have handed
    /// the old code straight back on the next round, over a letter now pointing
    /// somewhere else. The editor's `canSave` happens to prevent it; a guarantee
    /// that lives in a view isn't one.
    @discardableResult
    func updateWaypoint(_ id: UUID, code: String? = nil, city: String? = nil,
                        arrivalNote: String? = nil) -> Bool {
        guard !isObserver else { return false }
        guard let index = stamps.firstIndex(where: { $0.id == id }), !stamps[index].isDeleted else { return false }
        guard waypointIsLocked(stamps[index]) == nil else { return false }

        var newCode: String?
        if let code {
            let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
            guard codeIsAvailable(trimmed, excluding: id) else { return false }
            newCode = trimmed
        }
        var newCity: String?
        if let city {
            let trimmed = city.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            newCity = trimmed
        }

        // Past every guard: from here it either all lands or nothing did.
        if let newCode {
            rekeyDrafts(from: stamps[index].code, to: newCode, city: nil)
            stamps[index].code = newCode
        }
        if let newCity, newCity != stamps[index].city {
            rekeyDrafts(from: nil, to: nil, city: (stamps[index].city, newCity))
            stamps[index].city = newCity
            // Never earned (that is refused above), so whatever position it
            // had was the old city's, not a fix of somebody standing in it.
            let found = position(ofCity: newCity, onSegment: segment(for: stamps[index])?.id)
            stamps[index].latitude = found?.latitude ?? 0
            stamps[index].longitude = found?.longitude ?? 0
        }
        if let arrivalNote {
            stamps[index].arrivalNote = arrivalNote.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        stamps[index].updatedAt = now
        return true
    }

    /// Tombstones a waypoint, so the removal beats an edit made on the other
    /// phone in the same round.
    @discardableResult
    func removeWaypoint(_ id: UUID) -> Bool {
        guard !isObserver else { return false }
        guard let index = stamps.firstIndex(where: { $0.id == id }), !stamps[index].isDeleted else { return false }
        guard waypointIsLocked(stamps[index]) == nil else { return false }
        guard removalRefusal(ofWaypoint: stamps[index]) == nil else { return false }
        stamps[index].deletedAt = now
        stamps[index].updatedAt = now
        reflowWaypoints()
        return true
    }

    /// A draft is not binding, so re-keying a waypoint takes its drafts with it.
    /// A *sealed* letter is never touched: it says what it says.
    private func rekeyDrafts(from oldCode: String?, to newCode: String?,
                             city: (old: String, new: String)?) {
        for index in letters.indices where letters[index].isDraft {
            switch letters[index].condition {
            case .stamp(let code) where code == oldCode:
                if let newCode { letters[index].condition = .stamp(newCode) }
            case .place(let name) where name == city?.old:
                if let city { letters[index].condition = .place(city.new) }
            default: continue
            }
            letters[index].hint = letters[index].condition.summary.lowercased()
        }
    }

    /// Arriving somewhere is the only thing that earns a stamp, and a stamp is
    /// the only thing that can release the letters tied to it.
    ///
    /// Guarded against the observer, whose phone draws the trail but is not
    /// standing on it. A pin from home would earn the stamp, open the letter
    /// tied to that city, add its leg to the distance and change the headline
    /// on all three phones, none of which can be undone.
    ///
    /// - Returns: every letter that opened, in number order. Not just the
    ///   packed `unlocksLetter`, which only the sample trip ever set: the
    ///   letters written from home are keyed `.stamp`, `.place` and
    ///   `.finalStamp`, and asking only that field opened them on the next
    ///   wake, off screen, so the stamp screen's "something came with it"
    ///   never happened on a real trip.
    @discardableResult
    func arrive(at stamp: Stamp) -> [Letter] {
        guard !isObserver else { return [] }
        guard let index = stamps.firstIndex(where: { $0.id == stamp.id }), !stamps[index].earned else { return [] }
        stamps[index].earnedOn = now
        // A waypoint somebody typed has no coordinate, so it draws nowhere on
        // the map and adds nothing to the distance. Standing in it is the one
        // moment the phone can answer that, and it only ever fills a blank: a
        // waypoint that arrived with a coordinate keeps the one it came with.
        if !stamps[index].hasLocation, let fix = location.current?.coordinate {
            stamps[index].latitude = fix.latitude
            stamps[index].longitude = fix.longitude
        }
        stamps[index].updatedAt = now
        var opened: [Letter] = []
        if let number = stamps[index].unlocksLetter,
           letters.contains(where: { $0.number == number && !$0.isOpen }) {
            open(letterNumber: number, place: stamps[index].city)
            if let letter = letters.first(where: { $0.number == number && $0.isOpen }) { opened.append(letter) }
        }
        // The stamp is earned by now, so `letterMoment` already counts it.
        // Anything else that came due in the same instant opens with it too:
        // it would otherwise open on the next wake with nobody looking.
        opened += openDueLetters()
        return opened.sorted { $0.number < $1.number }
    }

    /// The letters arriving at this waypoint would open, for the trail to say
    /// so before the pin is dropped.
    ///
    /// Asks the same `isMet` the opening does, with the stamp counted as
    /// earned — so the promise and the opening can't disagree. A letter whose
    /// condition was withheld is never counted: "arriving here opens a letter"
    /// would tell them where the secret one is.
    func lettersOpening(onArrivalAt stamp: Stamp) -> [Letter] {
        guard !isObserver, features.letters, !stamp.earned else { return [] }
        let before = letterMoment
        var after = before
        after.earnedStampCodes.insert(stamp.code)
        after.earnedStampCities.insert(stamp.city)
        after.allStampsEarned = !orderedStamps.isEmpty
            && orderedStamps.allSatisfy { $0.earned || $0.id == stamp.id }
        return letters.filter { letter in
            guard letter.isSealed, !letter.isOpen, !letter.secretCondition else { return false }
            if let number = stamp.unlocksLetter, letter.number == number { return true }
            return letter.condition.isMet(after) && !letter.condition.isMet(before)
        }
        .sorted { $0.number < $1.number }
    }

    // MARK: - Meeting point

    var meeting: MeetingPoint { meetingPoint.value }

    /// Where to meet tonight, set by one of the two people who will be standing
    /// there.
    ///
    /// Home mode doesn't route to this screen, and the stamping is why it must
    /// not: `setBy` is `role`, and in home mode `role` is the traveller being
    /// *written to* — so an observer's write would land on both phones under
    /// one of their names.
    func setMeetingPoint(_ point: MeetingPoint) {
        guard !isObserver else { return }
        var chosen = point
        chosen.setAt = now
        // Trimmed here rather than only at the field, because the place is an
        // identity: "The bridge " and "The bridge" are one gate, and a list
        // offering both is a list nobody can pick from.
        chosen.place = chosen.place.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingPoint = StampedMeetingPoint(value: chosen, updatedAt: now, setBy: role)
        meetingPlaces = meetingPlaces.remembering(chosen)
    }

    /// How far they are from tonight's meeting point, if the phone knows both.
    var distanceToMeetingPoint: Measurement<UnitLength>? {
        guard meeting.hasLocation else { return nil }
        return location.distance(toLatitude: meeting.latitude, longitude: meeting.longitude)
    }

    var bearingToMeetingPoint: String? {
        guard meeting.hasLocation else { return nil }
        return location.compassDirection(toLatitude: meeting.latitude, longitude: meeting.longitude)
    }

    // MARK: - Journal

    func entries(for traveller: Traveller) -> [JournalEntry] {
        journal.filter { $0.author == traveller }.sorted { $0.dayNumber > $1.dayNumber }
    }

    var myEntries: [JournalEntry] { entries(for: role) }

    /// Nights with a page. Not a page count: a night is a spread, and the
    /// book's pages also hold the title, the openers and the back — so this
    /// was "12 pages" in the Book tab's corner over a row saying "34 pages".
    var nightsWritten: Int { myEntries.count }

    var todaysEntry: JournalEntry? {
        myEntries.first { $0.dayNumber == dayNumber }
    }

    var missedNights: Int {
        let written = Set(myEntries.map(\.dayNumber))
        return (1..<dayNumber).filter { !written.contains($0) }.count
    }

    /// Takes a page out of the book. The photograph is left to
    /// `pruneOrphanedPhotos()`, the one thing that knows whether anything
    /// else — a shelved trip — still names it.
    ///
    /// There was no way to do this at all: clearing the line read "Skip
    /// tonight" and closed the sheet with the page still in the book.
    func deleteEntry(day: Int) {
        guard isLive, participant.traveller != nil else { return }
        journal.removeAll { $0.dayNumber == day && $0.author == role }
        rescheduleRitual()
    }

    func save(entry incoming: JournalEntry) {
        // The page's limits are held here, not in the composer: a guarantee
        // that lives in a view isn't one, and the book lays a page out on the
        // assumption that its note fits and it has at most three photographs.
        var entry = incoming
        entry.line = String(entry.line.prefix(JournalEntry.lineLimit))
        entry.note = String(entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(JournalEntry.noteLimit))
        if entry.photoID == nil, !entry.extraPhotoIDs.isEmpty {
            entry.photoID = entry.extraPhotoIDs.removeFirst()
        }
        entry.extraPhotoIDs = Array(entry.extraPhotoIDs.filter { $0 != entry.photoID }
            .prefix(JournalEntry.extraPhotoLimit))
        entry.hasPhoto = entry.photoID != nil

        // Only tonight's page teaches the clock. Backfilling day 35 at
        // lunchtime says nothing about when this person writes.
        if entry.dayNumber == dayNumber, entry.author == role {
            ritualClock.observe(now)
        }
        if let index = journal.firstIndex(where: { $0.dayNumber == entry.dayNumber && $0.author == entry.author }) {
            // Replacing a page means the photographs it used to hold and no
            // longer does are now litter.
            let old = journal[index]
            for id in Set(old.allPhotoIDs).subtracting(entry.allPhotoIDs) {
                PhotoStore.shared.delete(id)
            }
            journal[index] = entry
        } else {
            journal.append(entry)
        }
    }

    // MARK: - Moments

    /// Most recent first, which is the order the trail lists them in and the
    /// reverse of the order the book prints them.
    var orderedMoments: [Moment] { moments.sorted { $0.capturedAt > $1.capturedAt } }

    /// Keeps a moment, at the phone's own position if it has one.
    ///
    /// Guarded against the observer, the same way `arrive(at:)` is: a moment
    /// carries a coordinate and a day, and one recorded at home would print in
    /// a book about somewhere else. Home mode never draws the control either,
    /// but the guard is what makes it certain.
    @discardableResult
    ///
    /// - Parameter city: where it was kept, when something knows better than
    ///   the itinerary — a stamp just earned. They can reach Huế a day before
    ///   the plan says, and the stamp is the truer answer. Before departure
    ///   it is still `""`: there is no stamp to earn before day 1.
    func addMoment(note: String, photoID: String? = nil,
                   latitude: Double = 0, longitude: Double = 0,
                   city: String? = nil) -> Moment? {
        guard !isObserver else { return nil }
        // A closed trip is frozen into its snapshot; a moment added after that
        // lands in a live journal nothing will ever shelve.
        guard isLive else { return nil }
        let day = trueDayNumber
        let place = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? cityNow
        let moment = Moment(capturedAt: now, dayNumber: day,
                            city: day < 1 ? "" : place,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            hasPhoto: photoID != nil, photoID: photoID,
                            latitude: latitude, longitude: longitude)
        moments.append(moment)
        return moment
    }

    /// Replaces a moment wholesale, the way `updateShowCard` does.
    ///
    /// A swapped photo leaves the old file behind, so it goes the same way it
    /// does in `save(entry:)`.
    func updateMoment(_ moment: Moment) {
        guard !isObserver else { return }
        // The shelved snapshot names this moment's photograph; changing it
        // here would delete the file the closed trip's book prints from.
        guard isLive else { return }
        guard let index = moments.firstIndex(where: { $0.id == moment.id }) else { return }
        if let oldPhoto = moments[index].photoID, oldPhoto != moment.photoID {
            PhotoStore.shared.delete(oldPhoto)
        }
        var updated = moment
        updated.hasPhoto = moment.photoID != nil
        moments[index] = updated
    }

    /// Removes the record outright, and leaves the photograph to the prune.
    ///
    /// No tombstone: a tombstone exists so a delete can win a merge, and a
    /// moment never syncs, so there is no merge to win. Unlike a stamp, a
    /// moment can be taken back.
    ///
    /// The file is not deleted here, because the screen offers ten seconds to
    /// change your mind and a restored moment pointing at a deleted photograph
    /// is a hatched box where the noodle stall was. `pruneOrphanedPhotos()`
    /// runs on every wake and is the one thing that knows every reference,
    /// live and shelved — so the file goes the next time the app comes back,
    /// by which point the undo offer has been withdrawn.
    func deleteMoment(_ id: UUID) {
        guard !isObserver else { return }
        // The shelved snapshot names this moment's photograph; changing it
        // here would delete the file the closed trip's book prints from.
        guard isLive else { return }
        guard let index = moments.firstIndex(where: { $0.id == id }) else { return }
        moments.remove(at: index)
    }

    /// Undo, for a delete a moment ago. The same value back, same id — a
    /// moment has no `updatedAt` to re-stamp, so it is simply the record again.
    @discardableResult
    func restoreMoment(_ moment: Moment) -> Bool {
        guard !isObserver, isLive else { return false }
        guard !moments.contains(where: { $0.id == moment.id }) else { return false }
        moments.append(moment)
        return true
    }

    /// Close enough to the next stop to say so. A city is not a point, and a
    /// fix in a guesthouse on the edge of Chiang Mai is still arriving.
    static let arrivalRadiusKm = 10.0

    /// The next waypoint, if this position is inside `arrivalRadiusKm` of it.
    ///
    /// Only ever a suggestion: the screens that ask this offer the
    /// confirmation `arrive(at:)` already has, and nothing here earns
    /// anything — a stamp cannot be undone and it opens letters. So it
    /// refuses everything `arrive` would, and before departure too, when the
    /// first stop is somewhere they are about to fly to rather than in.
    func nearNextStop(latitude: Double, longitude: Double) -> Stamp? {
        guard !isObserver, isLive, !isBeforeDeparture else { return nil }
        guard let next = nextStamp, !next.earned, next.hasLocation else { return nil }
        let km = Geo.kilometres(latitude, longitude, next.latitude, next.longitude)
        return km <= TripStore.arrivalRadiusKm ? next : nil
    }

    /// How far the next waypoint is from a position, in whole kilometres.
    ///
    /// Nil when the next waypoint has no position — every typed one — so the
    /// line is not drawn rather than drawn as "— km".
    func kilometresToNextStop(fromLatitude latitude: Double, longitude: Double) -> Int? {
        guard let next = nextStamp, next.hasLocation else { return nil }
        return Int(Geo.kilometres(latitude, longitude, next.latitude, next.longitude).rounded())
    }

    // MARK: - The evening ritual

    /// H1 · what tonight's prompt says. Day, place, and the one ask.
    var tonightsPrompt: RitualPrompt {
        RitualPrompt(dayNumber: dayNumber, city: currentCity, subject: template.promptSubject)
    }

    /// When it will arrive. Learned from when pages get written, never set.
    var tonightsPromptTime: Date? {
        guard features.nightlyPage, isLive, phase == .during else { return nil }
        return ritualClock.fireDate(forDay: dayNumber, on: now)
    }

    /// Re-arms the one pending prompt. Called when the app goes quiet, so the
    /// hour it uses is always the freshest habit rather than the one it had at
    /// launch.
    func rescheduleRitual() {
        guard participant.traveller != nil, features.nightlyPage, isLive else {
            ritual.cancelAll()
            return
        }
        guard todaysEntry == nil, let fire = tonightsPromptTime else {
            // Written already, or the trip is over. Tomorrow, then.
            guard let tomorrow = Calendar.trip.date(byAdding: .day, value: 1, to: now),
                  dayNumber < dayCount,
                  let fire = ritualClock.fireDate(forDay: dayNumber + 1, on: tomorrow)
            else { ritual.cancelAll(); return }
            let prompt = RitualPrompt(dayNumber: dayNumber + 1,
                                      city: city(forDay: dayNumber + 1),
                                      subject: template.promptSubject)
            ritual.schedule(prompt, at: fire)
            return
        }
        ritual.schedule(tonightsPrompt, at: fire)
    }

    /// H4 · the night just gone, if it has no page and has never been asked
    /// about. Nil almost always.
    var backfillCandidate: Int? {
        guard features.nightlyPage, isLive else { return nil }
        return backfill.candidate(today: dayNumber, writtenDays: Set(myEntries.map(\.dayNumber)))
    }

    /// Asked once. Either answer retires the day for good.
    func markBackfillOffered(_ day: Int) {
        backfill.markOffered(day)
    }

    /// H2 · tags already lit when the composer opens.
    ///
    /// Taken from what has actually been tagged in this city before, so the
    /// suggestion is evidence rather than a guess. With no history the composer
    /// opens with nothing lit.
    func suggestedTags(forDay day: Int, limit: Int = 3) -> [String] {
        let place = city(forDay: day)
        let history = journal
            .filter { $0.author == role && $0.city == place && $0.dayNumber != day }
            .sorted { $0.dayNumber > $1.dayNumber }
        var counts: [String: Int] = [:]
        for entry in history { for tag in entry.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit).map(\.key)
    }

    /// A word of their own for the chip row. Trimmed, lower-cased like the
    /// built-in ones, at most twenty characters, and never twice.
    @discardableResult
    func addTag(_ raw: String) -> String? {
        let tag = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(20))
        guard !tag.isEmpty else { return nil }
        if !customTags.contains(tag) { customTags.append(tag) }
        return tag
    }

    /// A country just finished, and in the book: the leg, the nights with a
    /// page in it, and the spread its opener is on. Nil almost always.
    ///
    /// Only on the two days after it ends, only once, and never for the last
    /// country — the end of the trip has a screen of its own. Derived from the
    /// itinerary and the journal; only the "already shown" is stored.
    var countryJustFinished: (leg: Leg, nights: Int, spread: Int)? {
        guard features.printedBooks, isLive, participant.traveller != nil else { return nil }
        let plan = bookPlan
        for leg in legs.dropLast() where (leg.endDay...leg.endDay + 1).contains(dayNumber) {
            guard !countriesMarkedDone.contains(leg.id) else { continue }
            let nights = myEntries.filter { $0.dayNumber >= leg.startDay && $0.dayNumber < leg.endDay }.count
            guard nights > 0,
                  let spread = plan.spreads.firstIndex(where: { $0.id == "leg-\(leg.id)" })
            else { continue }
            return (leg, nights, spread)
        }
        return nil
    }

    func markCountryDone(_ legID: UUID) {
        countriesMarkedDone.insert(legID)
    }

    // MARK: - Separated

    var isSeparated: Bool { separatedSince != nil }

    /// Whether Separated has anything to show: somewhere to go, or the
    /// numbers to call where they are.
    ///
    /// It used to need a meeting point, which hid the emergency numbers and
    /// the two phrases from the night nobody had agreed one. With neither, the
    /// screen would be a headline over nothing, so it isn't offered.
    var canStartSeparated: Bool {
        meeting.isSet || CountryFacts.lookup(currentCountry) != nil
    }

    func startSeparated() {
        separatedSince = now
        followMeetingPointIfPinned()
    }

    /// Tracks only while there is a pinned point to measure to.
    ///
    /// Without a position on the meeting point the distance can't be worked
    /// out however well the phone knows where it is, so tracking just asked
    /// for location and said "Finding you…" for ever. Called again when the
    /// point changes, because the other phone can pin it mid-separation, and
    /// on the way back into the screen after a relaunch.
    func followMeetingPointIfPinned() {
        guard isSeparated, meeting.hasLocation else {
            if location.isTracking { location.stop() }
            return
        }
        if !location.isTracking { location.start() }
    }

    func endSeparated() {
        separatedSince = nil
        location.stop()
    }

    // MARK: - The book

    // MARK: The book's caches
    //
    // The book is derived — nothing about it is stored — and it was derived on
    // every read: Today rebuilt the whole plan on each pass of its body to ask
    // whether a country had just finished, the composer rebuilt it on every
    // keystroke to print a page number, and each spread of the preview rebuilt
    // it two or three times more. Cheap on day 3 and not on day 300.
    //
    // So it is cached, and the cache is dropped by the `didSet` of every
    // property the book is made of: `journal`, `itinerary`, `stamps`,
    // `moments`, `meetingPlaces`, `features` and `role`. That list is the whole of what
    // `BookPlan.build` reads; a new input to the book has to join it, and a
    // check builds the plan fresh after each kind of edit and compares.

    private var bookPlanCache: BookPlan?
    private var printedMomentsCache: [Moment]?
    private var bookMapCache: [UUID?: BookMap?] = [:]
    private var bookPageCache: [Int: Int?] = [:]
    /// How many times the plan has actually been built. For the checks, which
    /// have no other way to tell a cache from a recomputation.
    private(set) var bookPlanBuilds = 0

    private func bookInputsChanged() {
        bookPlanCache = nil
        printedMomentsCache = nil
        bookMapCache = [:]
        bookPageCache = [:]
    }

    /// I1 · the book as it stands tonight, derived rather than stored.
    var bookPlan: BookPlan {
        if let cached = bookPlanCache { return cached }
        let plan = freshBookPlan()
        bookPlanCache = plan
        return plan
    }

    /// The plan built from scratch, bypassing the cache. The cache's own
    /// source, and what the checks compare it against.
    func freshBookPlan() -> BookPlan {
        bookPlanBuilds += 1
        guard features.printedBooks else { return .empty }
        return BookPlan.build(entries: myEntries, legs: legs, stamps: stamps.live,
                              moments: printedMoments,
                              meetingPlaces: meetingPlaces,
                              volumes: max(features.volumes, 1),
                              includeStamps: features.stamps)
    }

    /// The first page a day's spread starts on, as the book stands — or would
    /// stand, if that night had a page. Nil when the trip prints no book.
    ///
    /// The composer and the saved page used to say "page 12" meaning the
    /// twelfth *entry*, while the book put that night on pages 27 and 28.
    func bookPage(forDay day: Int) -> Int? {
        if let cached = bookPageCache[day] { return cached }
        let page = freshBookPage(forDay: day)
        bookPageCache[day] = page
        return page
    }

    private func freshBookPage(forDay day: Int) -> Int? {
        guard features.printedBooks else { return nil }
        // A night with a page is in the plan already, and the plan is cached.
        if let existing = myEntries.first(where: { $0.dayNumber == day }) {
            return bookPlan.firstPage(ofSpread: BookSpread.day(entryID: existing.id).id)
        }
        // A night without one yet: where it *would* land, so the composer can
        // say "page 27" before anything is saved. Built once per day and kept.
        let entry = JournalEntry(dayNumber: day, date: date(forDay: day), city: city(forDay: day),
                                 line: "", tags: [], hasPhoto: false, author: role)
        let plan = BookPlan.build(entries: myEntries + [entry], legs: legs, stamps: stamps.live,
                                  moments: printedMoments,
                                  meetingPlaces: meetingPlaces,
                                  volumes: 1, includeStamps: features.stamps)
        return plan.firstPage(ofSpread: BookSpread.day(entryID: entry.id).id)
    }

    /// The trail for the book's maps: every earned stamp with a position, and
    /// this leg's in the accent. Nil when there are fewer than two places to
    /// join, and the page sets the stops as type instead.
    ///
    /// An opener's map is framed on its own country's stamps, the rest of the
    /// route running off the edge. A country with no located stamp of its own
    /// has nothing to frame, and gets its stops as type — it used to get the
    /// whole trip with nothing on it highlighted.
    func bookMap(highlightingLeg legID: UUID? = nil) -> BookMap? {
        if let cached = bookMapCache[legID] { return cached }
        let map = freshBookMap(highlightingLeg: legID)
        bookMapCache[legID] = map
        return map
    }

    private func freshBookMap(highlightingLeg legID: UUID?) -> BookMap? {
        let live = stamps.live
        // The moments the book prints, as diamonds: the same mark the trail
        // draws, so the trip has one picture of itself.
        guard let legID else { return BookMap.fit(live, moments: printedMoments) }
        guard let leg = legs.first(where: { $0.id == legID }) else { return nil }
        let all = Set(legs.flatMap(\.segments).map(\.id))
        let own = Set(BookPlan.earnedStamps(live, inLeg: leg, allSegmentIDs: all)
            .filter(\.hasLocation).map(\.id))
        guard !own.isEmpty else { return nil }
        return BookMap.fit(live, highlighting: own, framing: own, moments: printedMoments)
    }

    /// Oldest first: the book runs forwards, and the trail's list runs back.
    ///
    /// Unfinished ones are left out — a spot kept in one tap with nothing
    /// written and no photograph would print as an empty frame and a date.
    /// Everything that paginates reads this, so leaving them out here is the
    /// whole of it: the book's moments spreads are cut from it and carry
    /// their own ids. The print screen says how many are waiting.
    var printedMoments: [Moment] {
        if let cached = printedMomentsCache { return cached }
        let printed = moments.filter { !$0.isUnfinished }.sorted { $0.capturedAt < $1.capturedAt }
        printedMomentsCache = printed
        return printed
    }

    /// Kept in one tap and not yet written up.
    var unfinishedMoments: [Moment] { orderedMoments.filter(\.isUnfinished) }

    /// Today's written-up moments, oldest first, for tonight's page to borrow
    /// from. Unfinished ones have their own row; offering an empty one here
    /// would copy nothing onto the page.
    var momentsToday: [Moment] {
        moments.filter { !$0.isUnfinished && Calendar.trip.isDate($0.capturedAt, inSameDayAs: now) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    /// A night's written-up moments, oldest first, for the composer to borrow
    /// from when it is writing a night that was missed. By the day the moment
    /// recorded, which is the night's own number.
    func moments(onDay day: Int) -> [Moment] {
        moments.filter { !$0.isUnfinished && $0.dayNumber == day }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    /// The meeting places as the book prints them.
    var bookMeetingPlaces: [MeetingPoint] { BookPlan.meetingPlacesInOrder(meetingPlaces) }

    /// Today's, for tonight's page — only today's, so the evening prompt never
    /// becomes a list of chores from last week.
    var unfinishedToday: [Moment] {
        unfinishedMoments.filter { Calendar.trip.isDate($0.capturedAt, inSameDayAs: now) }
    }

    func entry(_ id: UUID) -> JournalEntry? { journal.first { $0.id == id } }

    func moment(_ id: UUID) -> Moment? { moments.first { $0.id == id } }

    /// I3 · what the print screen has to say before anything is sent.
    ///
    /// - Parameter photoPixels: the **short** edge of each page photo, which
    ///   only something that can read image files knows. Passing it in keeps
    ///   the arithmetic checkable on a machine with no photo library. Short,
    ///   not long: the page is square and fills, so the shorter edge is the one
    ///   stretched to 8.25 inches — see `PhotoStore.pixelShortEdge`.
    func printReadiness(photoPixels: (String) -> Int?) -> PrintReadiness {
        let plan = bookPlan
        var measurements: [PhotoMeasurement] = []
        var missing = 0
        for entry in myEntries {
            guard entry.photoID != nil else {
                missing += 1
                continue
            }
            // Each photograph at the size it prints: the whole page alone, or
            // its share of a contact sheet.
            let layout = DaySpreadLayout(entry)
            for (index, id) in entry.allPhotoIDs.enumerated() {
                guard let pixels = photoPixels(id) else { continue }
                measurements.append(PhotoMeasurement(id: entry.id, dayNumber: entry.dayNumber, pixels: pixels,
                                                     printedFraction: layout.printedFraction(ofPhotoAt: index)))
            }
        }
        // A moment's photograph prints at the same size as a page's, so it is
        // measured the same way. It doesn't count toward `missing`: a page
        // without a photograph prints a hatched panel where one should be, and
        // a moment without one is a line of writing.
        for moment in printedMoments {
            guard let id = moment.photoID, let pixels = photoPixels(id) else { continue }
            measurements.append(PhotoMeasurement(id: moment.id, dayNumber: moment.dayNumber, pixels: pixels,
                                                 printedFraction: DaySpreadLayout.momentFraction))
        }
        return PrintReadiness.measure(plan: plan, photos: measurements, entriesWithoutPhoto: missing,
                                      unfinishedMoments: features.printedBooks ? unfinishedMoments.count : 0)
    }


    /// I7 · the last screen. Only ever true on the last day, and only once the
    /// trip has actually reached it.
    var isFinalDay: Bool { isLive && dayNumber >= dayCount }

    /// Home, and the trip is still open. The nudge on Today reads this, and so
    /// does anything else that offers to finish the trip, so they agree on
    /// when that starts. It starts the day *after* the last one: on the last
    /// day they are still travelling, and the ending screen makes that offer.
    /// `isFinalDay` stays true from then on too, because `dayNumber` clamps.
    var isOverButOpen: Bool { isLive && phase.isAfter }

    /// How far they have come, along the waypoints they have earned.
    ///
    /// Zero until the second one: a single place you have stood is not yet a
    /// distance travelled.
    var kilometresTravelled: Int {
        // Only the ones that know where they are. `kilometres(to:)` answers 0
        // when *either* end is unlocated, so a single positionless waypoint in
        // the middle would zero the legs on both sides of it. Skipping them
        // measures the trail along the places it does know.
        TrailReplay.kilometres(along: earnedStamps)
    }

    /// The trail, day by day, for the last-day screen and the shelf's replay.
    var trailReplay: TrailReplay {
        TrailReplay(stamps: stamps.live, moments: moments, start: start, dayCount: dayCount)
    }

    // MARK: - Smarter money

    /// 2.5 · what the trip went on, biggest first. Transfers between them are
    /// not spending and never appear.
    var spendByCategory: [(category: SpendCategory, home: Double, count: Int)] {
        var totals: [SpendCategory: (Double, Int)] = [:]
        for expense in spending {
            let existing = totals[expense.category] ?? (0, 0)
            totals[expense.category] = (existing.0 + inHome(expense), existing.1 + 1)
        }
        return totals
            .map { (category: $0.key, home: $0.value.0, count: $0.value.1) }
            .sorted { $0.home > $1.home }
    }

    /// The daily rate per country, worked out rather than written down.
    /// Countries they haven't reached yet are absent rather than zero, since
    /// zero would read as free.
    ///
    /// One row per country, not per leg — see `countries`. A trip that goes
    /// back to Thailand has one Thailand rate, over all the days it spent
    /// there.
    var perDayByCountry: [(country: String, perDay: Double, days: Int)] {
        countries.compactMap { country, here in
            let lines = spending.filter { self.country(of: $0) == country }
            guard !lines.isEmpty else { return nil }
            let days = max(here.reduce(0) { $0 + daysSpent(in: $1) }, 1)
            let total = lines.reduce(0) { $0 + inHome($1) }
            return (country, total / Double(days), days)
        }
    }

    func correctCategory(_ category: SpendCategory, for id: UUID) {
        guard let index = expenses.firstIndex(where: { $0.id == id }) else { return }
        expenses[index].correctedCategory = category
        expenses[index].updatedAt = now
    }

    /// 2.5 · a stay of several nights. One line becomes one entry per night,
    /// dated a day apart, so any of them can be edited or deleted on its own.
    @discardableResult
    func addRepeating(_ expense: Expense, nights: Int) -> [Expense] {
        let count = max(nights, 1)
        var written: [Expense] = []
        for night in 0..<count {
            guard let date = Calendar.trip.date(byAdding: .day, value: night, to: expense.date) else { continue }
            var line = expense
            line.id = UUID()
            line.date = date
            line.updatedAt = now
            line.note = count > 1 ? "\(expense.note) · night \(night + 1) of \(count)" : expense.note
            expenses.append(line)
            written.append(line)
        }
        return written
    }

    // MARK: - The shelf

    /// What the shelf will show for this trip.
    var summary: TripSummary {
        TripSummary(
            id: tripID, name: tripName, start: start, dayCount: dayCount,
            countries: legs.map(\.country), pageCount: bookPlan.pageCount,
            nightsAway: itinerary.totalNights,
            stampsEarned: earnedStamps.count, stampsTotal: orderedStamps.count,
            spentHome: spentHome, homeCurrency: homeCurrency,
            lettersDelivered: letters.filter(\.isOpen).count,
            lettersSealed: letters.filter { $0.isSealed && !$0.isOpen }.count,
            status: isLive ? .live : .archived,
            closedOn: closedOn,
            printedOn: nil,
            lastSyncedAt: sync.lastSyncedAt,
            kilometres: kilometresTravelled,
            moments: moments.count
        )
    }

    /// The trip's name, or words for not having one.
    ///
    /// `tripName` is `""` on a blank trip and on every reset one, so a sentence
    /// built around it reads "Close ?" — a bare question mark where the name
    /// goes, which is the shape of the `". Agreed at 00:53."` the meeting point
    /// used to print. Asked on the model rather than guessed at by each screen
    /// that puts the name inside a sentence.
    var displayName: String {
        let trimmed = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this trip" : trimmed
    }

    /// What closing this trip destroys, or nil if there is nothing to destroy.
    ///
    /// Asked of the store so the confirmation and the deletion cannot disagree.
    /// `adopt(_:)` is the precedent: its dialog asked its own version of the
    /// question, got it wrong in the same direction as the guard, and the two
    /// failed together — hence `adoptionDiscardsLetters(becoming:)`, and hence
    /// this.
    struct PapersLoss: Equatable {
        var documents: Int
        var scans: Int
    }

    var papersLostOnClose: PapersLoss? {
        let carrying = documents.filter(\.holdsAnything).count
        let scans = documents.reduce(0) { $0 + ScanVault.shared.pageCount(for: $1.id) }
        guard carrying > 0 || scans > 0 else { return nil }
        return PapersLoss(documents: carrying, scans: scans)
    }

    /// K7 · puts the trip on the shelf.
    ///
    /// Everything reopens and can be read — with one exception, which is the
    /// papers. The scans are deleted and the typed values are cleared *before*
    /// the snapshot is frozen, so a shelved trip carries no passport number and
    /// no encrypted page. A finished trip is a book worth keeping; the passport
    /// that got you through it is not, and a shelf that quietly held every
    /// number you had ever typed would be the opposite of what the vault is for.
    ///
    /// The labels survive the strip, so the row still reads "Passport · Number ·
    /// Expires" and says it was emptied rather than disappearing.
    func closeTrip() {
        guard isLive else { return }
        closedOn = now
        ritual.cancelAll()
        if isSeparated { endSeparated() }
        // Before the encode below, and on the live array too, so what is on
        // screen a second later matches what went to the shelf.
        for document in documents { ScanVault.shared.deleteAll(for: document.id) }
        documents = documents.map { $0.emptied() }
        library.archive(summary, snapshot: (try? JSONEncoder().encode(snapshot)) ?? Data())
        // Last, once the trip is really on the shelf, so whoever reads it
        // finds the spine it names.
        justShelved = tripID
    }

    /// The trip `closeTrip()` just put away, for the shelf to land it.
    ///
    /// An event, not state: not persisted, not on `TripSnapshot`, the way
    /// `pendingInvitation` isn't. A landing that survived a relaunch would
    /// replay a moment that already happened. Nothing but `closeTrip()` sets
    /// it — `beginNextTrip` shows no shelf, and `joinTrip`'s close goes
    /// straight to the joined trip, so a signal from either would be stale by
    /// the next time the shelf appeared.
    @Published private(set) var justShelved: UUID?

    /// Reads the landing once. Guarded before it clears, because `@Published`
    /// fires on every set: clearing nil to nil publishes, and a publish inside
    /// the render that asked is the `InvitationInbox` loop.
    func takeJustShelved() -> UUID? {
        guard let id = justShelved else { return nil }
        justShelved = nil
        return id
    }

    /// The one way from a finished trip to the next one.
    ///
    /// It used to be three: `startNewTrip` (closed the trip, then asked for a
    /// template, features and dates in a flow of its own), "Empty this trip"
    /// (`resetTrip()`, which shelved nothing and sent the phone back through
    /// onboarding), and joining. The first two now go through here, and what
    /// follows is always `ArrivalFlow`, because `hasOpened` goes false. The
    /// questions for a new trip are the questions for a first trip. Asking
    /// them twice in two flows is how the second copy ended up with no
    /// itinerary step and a role that always reset to `.one`.
    ///
    /// **Shelving:** called once the trip is closed (`!isLive`). Closing is
    /// its own act, on its own confirmation, and the phone waits between
    /// trips for as long as somebody wants to leave it there. Called on a live
    /// trip without `discarding`, it does nothing. The close has to be asked
    /// for, not implied.
    ///
    /// **Discarding** throws the live trip away without shelving it: the scans
    /// are deleted and orphaned photographs pruned once every collection is
    /// empty, as `resetTrip()` does. The shelf is untouched either way.
    ///
    /// **What carries:** who is holding the phone and what everyone is called,
    /// the money (currency, budget), the length, the switches, and the
    /// show-this cards. Everything else is for somewhere they no longer are.
    /// The cards come across as *new* records under fresh ids, because the new
    /// trip has a new `tripID` and a card is a `SyncableRecord`. Reusing an
    /// id is how a card resurrects against a tombstone on the other phone.
    ///
    /// The name is blanked so onboarding asks for it — "Thailand '26" carried
    /// into Japan would be printed on a book spine.
    func beginNextTrip(discarding: Bool = false, usingPlan: Bool = true) {
        guard discarding || !isLive else { return }
        // Read before anything is cleared, and decoded here rather than
        // trusted as a summary: the snapshot is what was actually planned.
        let planned = usingPlan ? library.plan.flatMap { TripSnapshot.decode($0.snapshot) } : nil
        let cards = orderedShowCards.enumerated().map { position, card in
            ShowCard(native: card.native, english: card.english,
                     footerTitle: card.footerTitle, footerBody: card.footerBody,
                     footerNote: card.footerNote, shortName: card.shortName,
                     index: position, updatedAt: now)
        }
        if discarding {
            for document in documents { ScanVault.shared.deleteAll(for: document.id) }
        }

        tripID = UUID()
        tripName = ""
        // Nobody filled this one in, and nothing that happens later changes it.
        origin = .blank
        closedOn = nil
        hasOpened = false
        // Whoever held the phone last trip is the likeliest to hold it this
        // one; the `who` step shows it rather than assuming it. The letterbox
        // is empty, so it belongs to them without an `adopt`.
        lettersBelongTo = participant

        start = Calendar.trip.startOfDay(for: now)
        settingsUpdatedAt = now

        itinerary = ItineraryDocument(legs: [])
        expenses = []
        stamps = []
        settlements = []
        journal = []
        letters = []
        // No photo deletion when shelving. `closeTrip()` has already archived
        // this trip's snapshot, so the shelf still points at those files and
        // `referencedPhotoIDs` keeps them alive. Deleting them would gut the
        // book that was just put away.
        moments = []
        separatedSince = nil
        ritualClock = RitualClock()
        backfill = BackfillOffers()
        budgetNudgeShows = 0
        meetingPoint = StampedMeetingPoint(
            value: MeetingPoint(place: "", detail: "", localScript: "", setAt: .distantPast),
            updatedAt: .distantPast, setBy: role)
        // Last trip's gates are in last trip's city.
        meetingPlaces = []
        // Day plans and papers are for another country. The cards are for
        // whoever is reading them: an allergy is an allergy in Japan too.
        dayPlans = []
        documents = []
        showCards = cards
        sharingRules = []

        if let planned { adopt(plan: planned) }

        if discarding {
            // Last, once every collection above is empty, so the set each
            // keeps is the shelf's (photographs) and nothing (scans).
            pruneOrphanedPhotos()
            pruneOrphanedScans()
        }
    }

    /// Takes on what was sketched ahead: the name, the dates, the money, the
    /// itinerary and its stamps. Everything else stays as `beginNextTrip`
    /// carried it, and the new `tripID` stands — a plan's own id only ever
    /// named a file on this phone.
    ///
    /// Stamps are the unearned live ones. A plan can't earn one, since `arrive`
    /// needs a live trip, but "can't" in a view isn't a guarantee.
    private func adopt(plan: TripSnapshot) {
        tripName = plan.tripName
        start = Calendar.trip.startOfDay(for: plan.start)
        dayCount = min(max(plan.dayCount, 1), 3650)
        budget = plan.budget
        homeCurrency = plan.homeCurrency
        settingsUpdatedAt = now
        itinerary = plan.itinerary
        stamps = plan.stamps.filter { !$0.isDeleted && $0.earnedOn == nil }
        backfillWaypointJoins()
        reflowWaypoints()
        library.clearPlan()
    }

    // MARK: - Sketching the next one

    /// A new plan, as a store that cannot write.
    ///
    /// Keyless, the arrangement the shelf's reader has: `persists` is false,
    /// so the photo and scan prunes, the widget and every save are no-ops. A
    /// second store *with* a key would prune the scans against its own
    /// document ids — none — and take the live trip's passport with it. It
    /// shares this store's `library`, so what it saves lands in the object
    /// the shelf is watching.
    ///
    /// Built from `init`'s blank branch rather than a copy of this trip, so no
    /// journal, letter, moment or document can ride into it by being
    /// forgotten in a list of things to clear. What is copied is named here:
    /// who everybody is, the money, the switches, the length. It starts the
    /// day after this trip ends — or today, between trips.
    ///
    /// Nil for the observer, who sets no trip parameters, and when a plan
    /// already exists: there is one at a time.
    func makePlan() -> TripStore? {
        guard !isObserver, library.plan == nil else { return nil }
        let plan = TripStore(storeKey: nil, snapshot: nil, clock: clock, rates: rates,
                             ritual: SilentRitualScheduler(), library: library)
        plan.names = names
        plan.participant = participant
        plan.role = role
        plan.budget = budget
        plan.homeCurrency = homeCurrency
        plan.features = features
        plan.dayCount = dayCount
        let begins = isLive
            ? Calendar.trip.date(byAdding: .day, value: 1, to: end) ?? now
            : now
        plan.start = Calendar.trip.startOfDay(for: begins)
        plan.savePlan()
        return plan
    }

    /// The plan that exists, opened for editing. Keyless for the same reason.
    func openPlan() -> TripStore? {
        guard let planned = library.plan, let snapshot = TripSnapshot.decode(planned.snapshot)
        else { return nil }
        return TripStore(storeKey: nil, snapshot: snapshot, clock: clock, rates: rates,
                         ritual: SilentRitualScheduler(), library: library)
    }

    /// Writes this store to the library as the plan. Only a keyless store
    /// may: a persisting one is the live trip, and the live trip filed as a
    /// plan would be the trip in two places.
    ///
    /// Skips a write that would change nothing, and that is load-bearing, not
    /// thrift. This store forwards its library's changes as its own, and the
    /// sheet saves on every change it sees, so an unconditional write here
    /// announces a change that asks for another write, every turn of the run
    /// loop. Sorted keys, so the same trip encodes to the same bytes and the
    /// comparison means something.
    func savePlan() {
        guard !persists else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(snapshot),
              data != library.plan?.snapshot else { return }
        library.savePlan(summary: summary, snapshot: data)
    }

    /// When the plan starts, from today: "today", "tomorrow", "in 43 days",
    /// "was due 3 days ago". Nil with no plan. Past dates are said plainly
    /// rather than clamped — a plan whose start has gone by is still a plan,
    /// and the dates step is where it gets moved.
    var planCountdown: String? {
        guard let plan = library.plan else { return nil }
        return Self.countdown(days: Calendar.trip.days(from: now, to: plan.summary.start))
    }

    nonisolated static func countdown(days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "tomorrow"
        case -1: "was due yesterday"
        case ..<0: "was due \(-days) days ago"
        default: "in \(days) days"
        }
    }

    /// What `beginNextTrip` brought over, as it was when the next trip
    /// opened. The first screen of that flow reads it and offers each part
    /// back as a row that can be declined.
    ///
    /// A snapshot, held by the flow, because declining is applied *from* it:
    /// the budget set to nought can only be given back if something
    /// remembers what it was.
    struct CarriedOver: Equatable {
        var budget: Double
        var homeCurrency: Currency
        var features: TripFeatures
        var cards: [ShowCard]
    }

    /// Which parts of `CarriedOver` are kept.
    struct CarryChoice: Equatable {
        var budget = true
        var currency = true
        var features = true
        var droppedCards: Set<UUID> = []
    }

    var carriedOver: CarriedOver {
        CarriedOver(budget: budget, homeCurrency: homeCurrency,
                    features: features, cards: orderedShowCards)
    }

    /// Makes the trip match a choice about what came along.
    ///
    /// Always from the snapshot, never from the trip as it now is, so it can
    /// run on every continue and be walked back: going back and ticking a row
    /// again restores what it held. Each write is skipped when it would
    /// change nothing, because `budget` and `homeCurrency` stamp the settings
    /// blob on every set, and a stamp that changed nothing still wins the
    /// merge against the other phone.
    ///
    /// A declined part goes back to what a blank trip has — no budget, euros,
    /// `init`'s switches — rather than to something new. A card is tombstoned
    /// rather than removed: young as this trip is, a sync round may already
    /// have carried it to the other phone.
    func applyCarry(_ choice: CarryChoice, from carried: CarriedOver) {
        let budgetWanted = choice.budget ? carried.budget : 0
        if budget != budgetWanted { budget = budgetWanted }
        let currencyWanted = choice.currency ? carried.homeCurrency : .eur
        if homeCurrency != currencyWanted { homeCurrency = currencyWanted }
        let featuresWanted = choice.features ? carried.features : TripTemplate.someonesLeaving.features
        if features != featuresWanted { features = featuresWanted }
        for card in carried.cards {
            guard let current = showCards.first(where: { $0.id == card.id }) else { continue }
            let dropped = choice.droppedCards.contains(card.id)
            if dropped, !current.isDeleted { deleteShowCard(card.id) }
            if !dropped, current.isDeleted { restoreShowCard(card.id) }
        }
    }

    // MARK: - Syncing

    /// The shared half of the trip. Journals, letters and moments are absent —
    /// they are not fields on `SyncPayload` at all.
    var payload: SyncPayload {
        SyncPayload(
            tripID: tripID,
            settings: TripSettings(start: start, dayCount: dayCount, budget: budget,
                                   homeCurrency: homeCurrency, updatedAt: settingsUpdatedAt),
            names: names,
            itinerary: itinerary,
            expenses: expenses,
            stamps: stamps,
            meetingPoint: meetingPoint,
            meetingPlaces: meetingPlaces,
            settlements: settlements,
            dayPlans: dayPlans,
            showCards: showCards,
            // Published on every round, so the observer can seal to this phone.
            // Only the public half — the private key never leaves the Keychain,
            // which is why it is in neither this nor `TripSnapshot`.
            letterKeys: publishedLetterKeys
        )
    }

    /// This phone's public key, folded into whatever the keyring already holds.
    ///
    /// Stamped per slot and merged per slot, like the names, so two phones
    /// publishing in one round both survive. A traveller's key is filed under
    /// the slot they are; the observer publishes nothing — there is no drop
    /// addressed to them, and a key on the writing side would be a key nobody
    /// seals to.
    private var publishedLetterKeys: LetterKeyring {
        guard !isObserver, let mine = letterKeys.publicKey else { return letterKeys_ }
        var ring = letterKeys_
        if ring[role] != mine { ring.set(mine, for: role, at: now) }
        return ring
    }

    func apply(_ payload: SyncPayload) {
        // Merged slot by slot upstream, so this only has to keep the observer's
        // own name — which never travelled in the first place.
        names = TripNames(one: payload.names.one, two: payload.names.two,
                          observer: names.observer)
        if payload.settings.updatedAt > settingsUpdatedAt {
            // Before anything below compares against this phone's copies: the
            // meeting point that loses on `updatedAt` stays, and has to stay
            // in the new frame.
            shiftDates(by: TripShift.days(from: start, to: payload.settings.start))
            start = payload.settings.start
            dayCount = payload.settings.dayCount
            budget = payload.settings.budget
            homeCurrency = payload.settings.homeCurrency
            settingsUpdatedAt = payload.settings.updatedAt
        }
        if payload.itinerary.updatedAt > itinerary.updatedAt { itinerary = payload.itinerary }
        if payload.meetingPoint.updatedAt > meetingPoint.updatedAt { meetingPoint = payload.meetingPoint }
        // Merged upstream, and then the winning point folded in on top: a phone
        // running the older build pushes a meeting point with no history behind
        // it, and the place it just set still has to be one this phone can
        // offer back.
        meetingPlaces = payload.meetingPlaces.remembering(meetingPoint.value)
        expenses = payload.expenses
        stamps = payload.stamps
        settlements = payload.settlements
        dayPlans = payload.dayPlans
        showCards = payload.showCards
        letterKeys_ = payload.letterKeys
        // A settlement the other phone confirmed becomes a transfer here too.
        applyConfirmedSettlements()
        // The itinerary that just arrived carries its own stop ids, so a
        // waypoint that had no join — or one whose stop went with the merge —
        // gets another go at finding it. So does a plan from the older build.
        backfillWaypointJoins()
        backfillPlanKeys()
        backfillWaypointPositions()
    }

    func syncNow() async {
        // An archived trip is cold storage. Skipping it keeps a sync round to
        // one trip rather than a fan-out over the whole shelf.
        guard isLive else { return }
        guard let merged = await sync.sync(local: payload, as: role) else { return }
        apply(merged)
    }

    var isLive: Bool { closedOn == nil }

    // MARK: - Tidying up

    /// Every photo any trip on this phone still points at — this one and every
    /// book on the shelf.
    ///
    /// The shelf half carries the weight. Archived trips reopen and their
    /// spreads draw real photographs, so a prune that read only the live
    /// journal would take the pictures out of every finished book. The set is
    /// assembled here rather than at the call site so there is one answer.
    var referencedPhotoIDs: Set<String> {
        // Every photograph on a page, not just the first — a page's extra
        // photographs are as much the book as its main one, and a prune that
        // read only `photoID` would take them on the next wake.
        var ids = Set(journal.flatMap(\.allPhotoIDs))
        ids.formUnion(moments.compactMap(\.photoID))
        for shelved in library.shelf {
            guard let snapshot = TripSnapshot.decode(shelved.snapshot) else { continue }
            ids.formUnion(snapshot.journal.flatMap(\.allPhotoIDs))
            ids.formUnion(snapshot.moments.compactMap(\.photoID))
        }
        return ids
    }

    /// Called once on launch. Cheap — a directory listing and a set difference.
    @discardableResult
    func pruneOrphanedPhotos() -> Int {
        // A store that can't write is a reader looking at an archive, so it
        // deletes nothing on the way past.
        guard persists else { return 0 }
        return PhotoStore.shared.prune(keeping: referencedPhotoIDs)
    }

    /// The documents whose scans are still wanted — the live trip's, and only
    /// those.
    ///
    /// Read `referencedPhotoIDs` above and then read this, because they answer
    /// the same question in opposite directions and the difference is
    /// deliberate. A closed trip's photographs are what its book is printed
    /// from, so that set walks the shelf. A closed trip's scans were deleted by
    /// `closeTrip()` before its snapshot was ever frozen, so no shelved trip can
    /// name one. Adding the shelf here would preserve exactly the files the
    /// close exists to destroy.
    var referencedDocumentIDs: Set<UUID> { Set(documents.map(\.id)) }

    /// Scans nothing points at any more.
    ///
    /// Nothing did this. `resetTrip()` set `documents` to `[]` and pruned the
    /// *photographs*, starting a new trip cleared them too, and
    /// `ScanVault.deleteAll(for:)` had no callers at all — so every encrypted
    /// passport page ever written stayed on the phone, referenced by nothing,
    /// for good. Invisible until documents could be made by hand, which is now.
    @discardableResult
    func pruneOrphanedScans() -> Int {
        // Same guard, and it matters more here: the shelf's reader store holds
        // a *different* trip's document ids, so a prune from one would take the
        // live trip's scans with it.
        guard persists else { return 0 }
        return ScanVault.shared.prune(keeping: referencedDocumentIDs)
    }

    // MARK: - Persistence

    /// Marks the trip dirty and schedules one write.
    ///
    /// Every `@Published` here calls this, and `save` encodes the *whole* trip.
    /// `setStart` alone touches seven of them, and a bound `TextField` touches
    /// one per keystroke, so a burst is coalesced into a single encode — off
    /// the main actor, since `TripSnapshot` is all value types.
    ///
    /// A store with no key is a reader — an archived trip opened off the shelf
    /// — and `storageFault` means there is a trip on disk this build couldn't
    /// read, so writing would destroy the only copy. Both are checked here
    /// rather than in the write, so a blocked store never queues.
    private func save() {
        guard storeKey != nil, !storageFault else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes now, if anything is waiting.
    ///
    /// Called on the way to the background, so a coalesced write isn't lost to
    /// the app being swiped away half a second after typing.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let storeKey, !storageFault else { return }
        let value = snapshot
        // Read on the main actor, where the published properties live; written
        // off it, with the trip. `storeKey != nil` is also the `persists` guard
        // the widget needs — a store opened off the shelf never gets here, so
        // reading an archived trip can't repaint somebody's Home Screen with it.
        let days = widgetSnapshots
        // Through a serial writer, not a bare `Task.detached`.
        //
        // Two flushes can be in flight at once — a coalesced save landing at
        // the moment the app goes to the background is exactly that — and
        // detached tasks have no order between them. Each encodes independently
        // and then writes, so the *older* snapshot could land last and the trip
        // would go backwards by however much was typed in between. The encode is
        // the slow part, which is what makes the race reachable rather than
        // theoretical.
        Task.detached(priority: .utility) { [weak self] in
            let stored = await TripWriter.shared.write(value, days: days, forKey: storeKey)
            await MainActor.run { self?.writeFailed = !stored }
        }
    }

    /// The last write didn't land.
    ///
    /// New with the move off `UserDefaults`: `set(_:forKey:)` could not fail, a
    /// protected file can — it is unwritable while the phone is locked, which is
    /// reachable by backgrounding the app and locking the phone a moment later.
    /// The protection is worth that; losing an evening's writing to it silently
    /// is not, so the next foreground writes again.
    @Published private(set) var writeFailed = false

    /// Writes anything the last attempt couldn't. Called on the way back in.
    func retryFailedWrite() {
        guard writeFailed else { return }
        flush()
    }

    /// Flushes, and comes back when the bytes are actually down.
    ///
    /// `flush()` dispatches and returns, which is right for a coalesced save and
    /// wrong for the two callers that need to know: the app on its way to the
    /// background, which has a limited assertion to spend and was otherwise
    /// sleeping two seconds and hoping, and a check that wants to read the file
    /// it just wrote. Same serial writer, so it cannot race an in-flight flush.
    @discardableResult
    func flushAndWait() async -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard let storeKey, !storageFault else { return false }
        let stored = await TripWriter.shared.write(snapshot, days: widgetSnapshots,
                                                   forKey: storeKey)
        writeFailed = !stored
        return stored
    }

    /// True for the one store the app is actually running on.
    var persists: Bool { storeKey != nil }

    /// The whole trip as one value. Also what the shelf freezes when a trip is
    /// closed, so an archived trip is the app it was rather than a report of it.
    var snapshot: TripSnapshot {
        TripSnapshot(
            tripID: tripID, tripName: tripName, participant: participant,
            names: names, origin: origin,
            features: features, template: template, closedOn: closedOn,
            hasOpened: hasOpened, role: role, start: start, dayCount: dayCount,
            budget: budget, homeCurrency: homeCurrency, settingsUpdatedAt: settingsUpdatedAt,
            itinerary: itinerary, expenses: expenses, stamps: stamps,
            meetingPoint: meetingPoint, meetingPlaces: meetingPlaces, settlements: settlements,
            journal: journal, moments: moments, letters: letters,
            lettersBelongTo: lettersBelongTo, letterKeys: letterKeys_,
            separatedSince: separatedSince,
            ritualClock: ritualClock, backfill: backfill,
            customTags: customTags, countriesMarkedDone: countriesMarkedDone,
            budgetNudgeShows: budgetNudgeShows,
            dayPlans: dayPlans, documents: documents,
            showCards: showCards, sharingRules: sharingRules
        )
    }

    // There is deliberately no method that pours a frozen trip into a running
    // store: assigning those properties outside `init` fires every
    // `didSet { save() }` handler, which would write the archive over the live
    // trip. Opening a closed trip is `init(storeKey: nil, snapshot:)` — a
    // second store that cannot write — and that is what the shelf uses.

    /// Empties the trip and sends the phone back through onboarding, keeping
    /// the dates, budget and currency that were chosen.
    ///
    /// `names` survives. Who you are isn't part of the trip's state, and asking
    /// somebody to type their name again to start over would be a strange thing
    /// to charge them for.
    func resetTrip() {
        hasOpened = false
        role = .one
        participant = .one
        // Back to where `init`'s blank branch starts, so a reset really is a
        // first launch. Without it the emptied letterbox would still be recorded
        // as belonging to whoever the phone was before the reset.
        lettersBelongTo = .one
        origin = .blank
        // The id goes back too. Two phones both starting over have to agree on
        // which trip that is, or each keeps whatever id it had drifted to and
        // `SyncMerge` refuses both payloads as somebody else's book.
        tripID = UUID()
        tripName = ""
        dayPlans = []
        documents = []
        showCards = []
        sharingRules = []
        itinerary = ItineraryDocument(legs: [])
        expenses = []
        journal = []
        moments = []
        // No blind delete of the photographs these pointed at.
        //
        // "Reset overwrites rather than archives, so nothing is left pointing
        // at these" was true of a live trip and false of a closed one:
        // `closeTrip()` freezes a snapshot and leaves the journal where it is,
        // and does not send the app back through onboarding — so a trip that
        // was put on the shelf a minute ago is still on screen with "Empty this
        // trip" one tap away, naming exactly the files that book is made of.
        //
        // `pruneOrphanedPhotos()` is the only thing that knows the whole
        // answer, because `referencedPhotoIDs` walks the shelf as well as the
        // live trip. Run it here so the reclaim is immediate rather than
        // waiting for the next wake.
        letters = []
        stamps = []
        meetingPoint = StampedMeetingPoint(
            value: MeetingPoint(place: "", detail: "", localScript: "", setAt: .distantPast),
            updatedAt: .distantPast, setBy: .one)
        meetingPlaces = []
        settlements = []
        separatedSince = nil
        ritualClock = RitualClock()
        backfill = BackfillOffers()
        budgetNudgeShows = 0
        customTags = []
        countriesMarkedDone = []
        closedOn = nil
        // Last, once every collection above is empty, so the set it keeps is
        // the shelf's and nothing else.
        pruneOrphanedPhotos()
        // And the scans, whose set is now empty for the opposite reason — no
        // shelved trip can name one, because closing deletes them. Without this
        // a reset left every encrypted page on the phone with nothing pointing
        // at it, which is not a first launch.
        pruneOrphanedScans()
    }
}

// MARK: - Writing it down

/// The one thing that writes the trip to disk.
///
/// An actor rather than a queue because the work either side of the write is
/// already `async`, and because "one writer" is the whole requirement: the
/// encode is expensive enough that two overlapping flushes can finish out of
/// order, and the last `set` wins whatever it happens to be holding.
///
/// The widget goes out from here too, in the same serialised step, so the two
/// containers can never disagree about which day it is.
actor TripWriter {
    static let shared = TripWriter()

    /// Writes the trip, and says whether it landed.
    ///
    /// The answer used to be discarded — `try?` around the encode and a `set`
    /// that cannot fail. It can fail now, because the trip is a protected file
    /// rather than a preferences key, and a protected file cannot be written
    /// while the phone is locked. That is the price of the protection and it has
    /// to be paid honestly: the caller retries rather than losing the evening.
    ///
    /// The widget goes out either way. It carries no private field and its own
    /// container is unprotected on purpose, so there is no reason to hold the
    /// Home Screen back because the trip's own write has to wait.
    @discardableResult
    func write(_ snapshot: TripSnapshot, days: [WidgetSnapshot], forKey key: String) -> Bool {
        var stored = false
        if let data = try? JSONEncoder().encode(snapshot) {
            do {
                try Storage.writeProtected(data, named: key)
                stored = true
            } catch {
                stored = false
            }
        }
        TripStore.publishWidget(days)
        return stored
    }
}

// MARK: - The trip, as one value

/// Persisted shape of a whole trip.
///
/// Decoded field by field with defaults, so a trip written by an earlier
/// version still opens rather than losing every page to one added flag.
struct TripSnapshot: Codable {
    var tripID: UUID
    var tripName: String
    var participant: Participant
    var names: TripNames
    var origin: TripOrigin
    var features: TripFeatures
    var template: TripTemplate
    var closedOn: Date?
    var hasOpened: Bool
    var role: Traveller
    var start: Date
    var dayCount: Int
    var budget: Double
    var homeCurrency: Currency
    var settingsUpdatedAt: Date
    var itinerary: ItineraryDocument
    var expenses: [Expense]
    var stamps: [Stamp]
    var meetingPoint: StampedMeetingPoint
    /// Where this trip has met before now. Dated, so `setStart` moves it.
    var meetingPlaces: [MeetingPoint]
    var settlements: [SettlementProposal]
    var journal: [JournalEntry]
    /// Never on `SyncPayload`, and dated, so `setStart` moves it.
    var moments: [Moment]
    var letters: [Letter]
    /// Who the letters above belong to. See `TripStore.lettersBelongTo`.
    var lettersBelongTo: Participant
    /// The travellers' **public** keys, as last merged. The private half is in
    /// the Keychain and is deliberately not here — a snapshot is backed up.
    var letterKeys: LetterKeyring
    var separatedSince: Date?
    var ritualClock: RitualClock
    var backfill: BackfillOffers
    var customTags: [String] = []
    var countriesMarkedDone: Set<UUID> = []
    /// See `TripStore.budgetNudgeShows`. This phone's, never on the payload.
    var budgetNudgeShows: Int = 0

    // Content that belongs to *this* trip, and travels with it, so a trip made
    // from scratch opens with its own papers rather than another trip's.
    var dayPlans: [DayPlan]
    var documents: [TravelDocument]
    var showCards: [ShowCard]
    var sharingRules: [SharingRule]

    /// What was on disk, and whether it could be read.
    ///
    /// Three answers, not two: "nothing saved yet" and "something is saved and
    /// it didn't decode" have to be told apart, or one unreadable field turns
    /// two months of pages into a fresh trip on launch.
    enum Stored {
        case none
        case trip(TripSnapshot)
        /// Present and unreadable. The bytes are handed back rather than
        /// dropped, so nothing writes over them.
        case unreadable(Data)
    }

    static func stored(key: String = TripStore.storeKey) -> Stored {
        migrateFromDefaultsIfNeeded(key: key)

        let data: Data?
        do {
            data = try Storage.readProtected(named: key)
        } catch {
            // The file is there and would not open. On a protected file that
            // usually means the phone is locked. It is emphatically not
            // "nothing saved" — answering that would start a fresh trip over
            // somebody's two months, which is the exact failure the three-state
            // answer exists to prevent. There are no bytes to hand back, so an
            // empty `unreadable` carries the fact without pretending to more.
            return .unreadable(Data())
        }
        guard let data else { return .none }
        guard let snapshot = try? JSONDecoder().decode(TripSnapshot.self, from: data) else {
            return .unreadable(data)
        }
        return .trip(snapshot)
    }

    /// Moves a trip written by an earlier build out of `UserDefaults`.
    ///
    /// The trip used to live in the app's preferences plist — journal, every
    /// letter in full, the moments, the ledger — which is in every backup, is
    /// plaintext, and is readable whenever the phone has been unlocked once
    /// since boot. It lives in a protected file now. This is what carries an
    /// existing install across, once.
    ///
    /// Order is the whole of it: **write, read back, and only then remove**. A
    /// remove that runs on faith loses the trip if the write failed — and the
    /// write can now fail, because a protected file cannot be written while the
    /// phone is locked. Leaving the old copy behind for one more launch costs
    /// nothing; removing it early costs everything.
    static func migrateFromDefaultsIfNeeded(key: String) {
        guard let legacy = Storage.defaults.data(forKey: key) else { return }
        // Something is already at the new address. Whatever it is, it is newer
        // than a value the app stopped writing, so the old key is just litter.
        if (try? Storage.readProtected(named: key)) ?? nil != nil {
            Storage.defaults.removeObject(forKey: key)
            return
        }
        guard (try? Storage.writeProtected(legacy, named: key)) != nil,
              let readBack = try? Storage.readProtected(named: key),
              readBack == legacy
        else { return }                       // try again next launch
        Storage.defaults.removeObject(forKey: key)
    }

    static func load(key: String = TripStore.storeKey) -> TripSnapshot? {
        if case .trip(let snapshot) = stored(key: key) { return snapshot }
        return nil
    }

    static func decode(_ data: Data) -> TripSnapshot? {
        try? JSONDecoder().decode(TripSnapshot.self, from: data)
    }
}

// MARK: - Decoding

/// `init(from:)` lives in an extension so Swift keeps synthesising the
/// memberwise initialiser — otherwise the same thirty fields would have to be
/// written out in a fourth place and kept in step by hand.
extension TripSnapshot {

    /// Every field decoded with `decodeIfPresent` and a default.
    ///
    /// Plain `decode` *throws* on a missing key, and a throw here isn't a
    /// missing field — it is a lost trip. This way a snapshot missing anything
    /// at all still opens, minus the part that was missing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        role = try c.decodeIfPresent(Traveller.self, forKey: .role) ?? .one
        hasOpened = try c.decodeIfPresent(Bool.self, forKey: .hasOpened) ?? false
        start = try c.decodeIfPresent(Date.self, forKey: .start)
            ?? Calendar.trip.startOfDay(for: Date())
        dayCount = try c.decodeIfPresent(Int.self, forKey: .dayCount) ?? 1
        budget = try c.decodeIfPresent(Double.self, forKey: .budget) ?? 0
        homeCurrency = try c.decodeIfPresent(Currency.self, forKey: .homeCurrency) ?? .eur
        settingsUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .settingsUpdatedAt) ?? .distantPast
        itinerary = try c.decodeIfPresent(ItineraryDocument.self, forKey: .itinerary)
            ?? ItineraryDocument(legs: [])
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        stamps = try c.decodeIfPresent([Stamp].self, forKey: .stamps) ?? []
        meetingPoint = try c.decodeIfPresent(StampedMeetingPoint.self, forKey: .meetingPoint)
            ?? StampedMeetingPoint(
                value: MeetingPoint(place: "", detail: "", localScript: "", setAt: .distantPast),
                updatedAt: .distantPast, setBy: .one)
        // Absent on every trip saved before the history existed, and empty is
        // the honest answer: those trips kept no record of where they had met.
        meetingPlaces = try c.decodeIfPresent([MeetingPoint].self, forKey: .meetingPlaces) ?? []
        settlements = try c.decodeIfPresent([SettlementProposal].self, forKey: .settlements) ?? []
        journal = try c.decodeIfPresent([JournalEntry].self, forKey: .journal) ?? []
        moments = try c.decodeIfPresent([Moment].self, forKey: .moments) ?? []
        letters = try c.decodeIfPresent([Letter].self, forKey: .letters) ?? []
        separatedSince = try c.decodeIfPresent(Date.self, forKey: .separatedSince)

        tripID = try c.decodeIfPresent(UUID.self, forKey: .tripID) ?? UUID()
        tripName = try c.decodeIfPresent(String.self, forKey: .tripName) ?? ""
        participant = try c.decodeIfPresent(Participant.self, forKey: .participant) ?? Participant(role)
        // Decoded after `participant` because that is its fallback, and the
        // fallback is the whole point: on a trip saved before this field
        // existed, the letters on the phone belong to whoever the phone is —
        // there was no other way for them to have got there. Guessing anything
        // else would either delete somebody's post on first launch or leave the
        // hole this field was added to close.
        lettersBelongTo = try c.decodeIfPresent(Participant.self, forKey: .lettersBelongTo) ?? participant
        letterKeys = try c.decodeIfPresent(LetterKeyring.self, forKey: .letterKeys) ?? .blank
        names = try c.decodeIfPresent(TripNames.self, forKey: .names) ?? .blank
        origin = try c.decodeIfPresent(TripOrigin.self, forKey: .origin) ?? .blank
        template = try c.decodeIfPresent(TripTemplate.self, forKey: .template) ?? .someonesLeaving
        features = try c.decodeIfPresent(TripFeatures.self, forKey: .features) ?? template.features
        closedOn = try c.decodeIfPresent(Date.self, forKey: .closedOn)
        ritualClock = try c.decodeIfPresent(RitualClock.self, forKey: .ritualClock) ?? RitualClock()
        backfill = try c.decodeIfPresent(BackfillOffers.self, forKey: .backfill) ?? BackfillOffers()
        customTags = try c.decodeIfPresent([String].self, forKey: .customTags) ?? []
        countriesMarkedDone = try c.decodeIfPresent(Set<UUID>.self, forKey: .countriesMarkedDone) ?? []
        budgetNudgeShows = try c.decodeIfPresent(Int.self, forKey: .budgetNudgeShows) ?? 0
        // `bookOrder` was here: an order that set a flag on this phone and
        // reached no printer. A file saved with one still carries the key, and
        // the keyed decoder passes over it.

        // Per-trip content, so the fallback is empty rather than another trip's.
        dayPlans = try c.decodeIfPresent([DayPlan].self, forKey: .dayPlans) ?? []
        documents = try c.decodeIfPresent([TravelDocument].self, forKey: .documents) ?? []
        showCards = try c.decodeIfPresent([ShowCard].self, forKey: .showCards) ?? []
        sharingRules = try c.decodeIfPresent([SharingRule].self, forKey: .sharingRules) ?? []
    }
}

