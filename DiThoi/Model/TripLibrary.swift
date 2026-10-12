import Foundation
import Combine

// MARK: - A trip, from the outside

/// What the shelf knows about a trip without opening it.
///
/// Frozen at the moment of closing. An archived trip is read-only, so a summary
/// that could drift from its contents is a summary that can't drift from its
/// contents.
struct TripSummary: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var start: Date
    var dayCount: Int
    var countries: [String]
    var pageCount: Int
    var nightsAway: Int
    var stampsEarned: Int
    var stampsTotal: Int
    var spentHome: Double
    var homeCurrency: Currency
    var lettersDelivered: Int
    var lettersSealed: Int
    var status: TripStatus
    var closedOn: Date?
    var printedOn: Date?
    var lastSyncedAt: Date?
    /// How far the trip went, and how many moments it kept. Both are
    /// **optional on purpose**, and they are the first fields added since
    /// shelves started being written. This struct uses synthesised `Codable`,
    /// which throws on a missing non-optional key, and a shelf that fails to
    /// decode is every finished trip gone at once. A summary frozen before
    /// these existed has no figure, and `shelvedLine` leaves the clause out.
    var kilometres: Int? = nil
    var moments: Int? = nil

    var end: Date {
        Calendar.trip.date(byAdding: .day, value: dayCount - 1, to: start) ?? start
    }

    var year: String { start.text("yyyy") }

    /// The mirror of `TripStore.displayName`, for a trip nothing has open.
    ///
    /// A summary is frozen, so the fallback cannot live where the name is
    /// written — an archived row reads this struct and never reaches a store.
    /// Without it a trip that was never named draws a spine reading " · 2026"
    /// and an accessibility label reading ", 2026, live", which is the shape of
    /// the meeting point's ". Agreed at 00:53."
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this trip" : trimmed
    }

    var spine: String { "\(displayName) · \(year)" }

    /// What the shelf says under a trip that has just been put away.
    ///
    /// Built clause by clause, in the manner of `packedSummary`, and every
    /// clause but the length drops out when it has nothing in it. "0 km ·
    /// 0 moments" under a book that was just shelved would be counting nothing
    /// at the moment somebody is looking hardest.
    ///
    /// Countries are counted **distinct**. `countries` is one entry per leg, so
    /// Thailand → Laos → Thailand is three entries and two countries — the
    /// trap `perDayByCountry` fell into once, one screen over.
    var shelvedLine: String {
        var clauses = [Self.counted(dayCount, "day")]
        let distinct = Set(countries.map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty })
        if !distinct.isEmpty { clauses.append(Self.counted(distinct.count, "country", plural: "countries")) }
        if let km = kilometres, km > 0 {
            clauses.append("\(Formatting.decimal(Double(km), places: 0)) km")
        }
        if pageCount > 0 { clauses.append(Self.counted(pageCount, "page")) }
        if let moments, moments > 0 { clauses.append(Self.counted(moments, "moment")) }
        return clauses.joined(separator: " · ")
    }

    private static func counted(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        "\(Formatting.decimal(Double(value), places: 0)) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    var routeLine: String {
        let route = countries.map(Self.shortCountry).joined(separator: " · ")
        return route.isEmpty ? "\(dayCount) days" : "\(route) · \(dayCount) days"
    }

    var datesLine: String {
        "\(start.shortDayMonth) – \(end.shortDate) · \(dayCount) days"
    }

    static func shortCountry(_ name: String) -> String {
        switch name {
        case "Thailand": "TH"
        case "Vietnam": "VN"
        case "South Korea", "Korea": "KR"
        case "Portugal": "PT"
        default: String(name.prefix(2)).uppercased()
        }
    }

    /// K1 · a spine's thickness is its page count and its height is its length,
    /// because that is what a shelf of real books looks like. Both are clamped
    /// so a weekend is still a visible object and a year is still on the screen.
    var spineWidth: Double { min(max(26 + Double(pageCount) * 0.17, 26), 54) }
    var spineHeight: Double { min(max(96 + Double(dayCount) * 1.6, 96), 196) }
}

/// A closed trip and everything in it, kept whole.
///
/// The snapshot is the same blob the live store persists, so opening an
/// archived trip is the app it was, not a report about it.
struct ShelvedTrip: Codable, Identifiable {
    var summary: TripSummary
    var snapshot: Data
    var id: UUID { summary.id }
}

// MARK: - A year ago today

/// A moment or a page from this date in an earlier year, on a shelved trip.
///
/// Its `id` is the source record's, never minted: memories are derived, and a
/// derived value with minted ids has new identity on every pass.
struct Memory: Identifiable, Equatable {
    enum Kind: Equatable { case moment, page }

    let id: UUID
    let tripID: UUID
    let tripName: String
    let kind: Kind
    let yearsAgo: Int
    let words: String
    let photoID: String?
    let place: String?
    let when: Date

    /// "A year ago today", "Two years ago today".
    var heading: String {
        yearsAgo == 1 ? "A year ago today"
            : "\(Formatting.spelledCount(yearsAgo, "year")) ago today"
    }
}

// MARK: - The shelf

/// Every trip this phone has ever held, minus the live one.
///
/// Only one trip is live at a time, which is the whole reason multi-trip
/// doesn't turn sync into a per-trip fan-out: the live trip syncs and the shelf
/// is cold storage. Archived trips don't sync, don't notify and don't drop
/// pins.
@MainActor
final class TripLibrary: ObservableObject {
    @Published private(set) var shelf: [ShelvedTrip] = []
    /// The next trip, sketched ahead. At most one, in the shelf's own shape —
    /// a summary and a snapshot — but in a file of its own, so the shelf's
    /// format and everything that decodes it are untouched.
    @Published private(set) var plan: ShelvedTrip?

    private let key: String

    /// Named once, here, and read by `DebugScreen.reset()` — the shelf has to
    /// go on a reset or a "first launch" opens with the last run's trips on it.
    nonisolated static let defaultKey = "dithoi.library.v1"
    /// The plan's file. Named in `Storage.appKeys`, so a reset takes it too.
    nonisolated static let planKey = "dithoi.plan.v1"

    init(key: String = TripLibrary.defaultKey) {
        self.key = key
        load()
    }

    /// The plan's file sits beside the shelf's. A scratch library in the
    /// checks has its own key, and gets its own plan with it.
    private var planKey: String {
        key == Self.defaultKey ? Self.planKey : key + ".plan"
    }

    /// Writes the plan. Status is set here, so no caller can file a plan as
    /// live or archived by passing its store's summary straight through.
    func savePlan(summary: TripSummary, snapshot: Data) {
        var sketched = summary
        sketched.status = .planned
        sketched.closedOn = nil
        plan = ShelvedTrip(summary: sketched, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(plan) else { return }
        try? Storage.writeProtected(data, named: planKey)
    }

    func clearPlan() {
        plan = nil
        Storage.removeProtected(named: planKey)
    }

    /// Newest first, which is also tallest-at-the-left on the shelf.
    var byRecency: [ShelvedTrip] {
        shelf.sorted { $0.summary.start > $1.summary.start }
    }

    var isEmpty: Bool { shelf.isEmpty }

    func trip(_ id: UUID) -> ShelvedTrip? { shelf.first { $0.id == id } }

    /// Memoised per calendar day: decoding every snapshot on the shelf is not
    /// something to do on every pass of `TodayView.body`. Cleared whenever the
    /// shelf changes, because a trip closed this morning is one more place a
    /// memory could come from.
    private var memoryCache: (day: String, memories: [Memory])?

    /// What this phone kept on this date in an earlier year.
    ///
    /// Moments, and pages written by the slot this phone held on that trip —
    /// the book already filters to your own pages, and somebody else's page
    /// is not your memory. Unfinished moments are skipped: a date and nothing
    /// else is not worth a panel. 29 February matches only 29 February, quiet
    /// three years in four rather than misdated.
    func memories(on date: Date) -> [Memory] {
        let key = date.text("yyyy-MM-dd")
        if let memoryCache, memoryCache.day == key { return memoryCache.memories }
        let found = Self.memories(in: shelf, on: date)
        memoryCache = (key, found)
        return found
    }

    nonisolated static func memories(in shelf: [ShelvedTrip], on date: Date) -> [Memory] {
        let calendar = Calendar.trip
        let today = calendar.dateComponents([.year, .month, .day], from: date)
        func yearsBack(_ other: Date) -> Int? {
            let then = calendar.dateComponents([.year, .month, .day], from: other)
            guard then.month == today.month, then.day == today.day,
                  let thenYear = then.year, let nowYear = today.year, thenYear < nowYear
            else { return nil }
            return nowYear - thenYear
        }

        var found: [Memory] = []
        for trip in shelf {
            guard let snapshot = TripSnapshot.decode(trip.snapshot),
                  !snapshot.participant.isObserver else { continue }
            let name = trip.summary.displayName
            for moment in snapshot.moments where !moment.isUnfinished {
                guard let years = yearsBack(moment.capturedAt) else { continue }
                found.append(Memory(id: moment.id, tripID: trip.id, tripName: name, kind: .moment,
                                    yearsAgo: years, words: moment.note, photoID: moment.photoID,
                                    place: moment.place, when: moment.capturedAt))
            }
            for page in snapshot.journal where page.author == snapshot.role {
                guard let years = yearsBack(page.date),
                      !page.line.trimmingCharacters(in: .whitespaces).isEmpty || page.photoID != nil
                else { continue }
                let city = page.city.trimmingCharacters(in: .whitespaces)
                found.append(Memory(id: page.id, tripID: trip.id, tripName: name, kind: .page,
                                    yearsAgo: years, words: page.line, photoID: page.photoID,
                                    place: city.isEmpty || city == "—" ? nil : city, when: page.date))
            }
        }
        return found.sorted { ($0.yearsAgo, $0.when) < ($1.yearsAgo, $1.when) }
    }

    func archive(_ summary: TripSummary, snapshot: Data) {
        var frozen = summary
        frozen.status = .archived
        if frozen.closedOn == nil { frozen.closedOn = Date() }
        shelf.removeAll { $0.id == frozen.id }
        shelf.append(ShelvedTrip(summary: frozen, snapshot: snapshot))
        memoryCache = nil
        save()
    }

    /// Closing frees the offline maps but never a page, a photo or a letter —
    /// see K7. Removing a trip from the shelf entirely is a different act and
    /// the app does not offer it.
    func forget(_ id: UUID) {
        shelf.removeAll { $0.id == id }
        memoryCache = nil
        save()
    }

    func erase() {
        shelf = []
        memoryCache = nil
        Storage.removeProtected(named: key)
        Storage.defaults.removeObject(forKey: key)
        clearPlan()
    }

    // MARK: Persistence

    /// A protected file, for the reason the live trip is one: every row here
    /// carries a whole `TripSnapshot`, which means a finished trip's journal,
    /// its letters and its moments. The shelf is the *larger* half of the
    /// problem, not the smaller — a phone two trips in holds more private text
    /// here than in the live trip. It sat in the preferences plist alongside it.
    private func load() {
        TripSnapshot.migrateFromDefaultsIfNeeded(key: key)
        guard let data = (try? Storage.readProtected(named: key)) ?? nil,
              let decoded = try? JSONDecoder().decode([ShelvedTrip].self, from: data)
        else { loadPlan(); return }
        shelf = decoded
        loadPlan()
    }

    private func loadPlan() {
        guard let data = (try? Storage.readProtected(named: planKey)) ?? nil else { return }
        plan = try? JSONDecoder().decode(ShelvedTrip.self, from: data)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shelf) else { return }
        // Unlike the live trip there is no retry here, and there doesn't need to
        // be: the shelf only changes when a trip is closed or forgotten, which
        // are deliberate acts on an unlocked phone rather than a coalesced
        // background write.
        try? Storage.writeProtected(data, named: key)
    }
}
