import Foundation

/// A week of the book as one picture to keep: a spread the traveller chose,
/// with the week's stamp, its route and the trip mark under it.
///
/// What the app does with it is save it to their Photos, and nothing else.
/// It never says "sent", because it sends nothing — the postcard leaves the
/// phone only by the traveller's own hand, from Photos or a share sheet they
/// opened. And it never rides on `SyncPayload` or `LetterDrop`: the journal is
/// not a field on either, and a picture of the journal is the journal.
///
/// Everything here is derived. The offer is not a flag that remembers being
/// shown; it is a property of the page just saved.
extension TripStore {
    /// Weeks of the trip, in seven-day chunks from day 1.
    static let postcardWeekLength = 7

    func postcardWeek(forDay day: Int) -> Int {
        max((day - 1) / Self.postcardWeekLength, 0) + 1
    }

    func postcardDays(week: Int) -> ClosedRange<Int> {
        let first = (week - 1) * Self.postcardWeekLength + 1
        return first...max(first, min(first + Self.postcardWeekLength - 1, dayCount))
    }

    /// The spreads a week's postcard can be made from: this phone's written
    /// nights in it, in order. `bookPlan` is already this phone's book.
    func postcardSpreads(week: Int) -> [Int] {
        let days = postcardDays(week: week)
        return bookNights.filter { days.contains($0.day) }.map(\.index)
    }

    /// The weeks that have a page to send, earliest first.
    var postcardWeeks: [Int] {
        var weeks: [Int] = []
        for night in bookNights {
            let week = postcardWeek(forDay: night.day)
            if !weeks.contains(week) { weeks.append(week) }
        }
        return weeks
    }

    /// The week to offer a postcard of, right after a page is saved — or nil.
    ///
    /// Only tonight's page, on a live trip, on a traveller's phone, and only
    /// when the book has just reached another seven nights. Writing up a
    /// missed night is catching up, not an occasion. There is no "already
    /// offered" to store: the count moves on with the next page.
    func postcardOffer(after entry: JournalEntry) -> Int? {
        guard features.printedBooks, isLive, !isObserver,
              entry.dayNumber == dayNumber,
              nightsWritten > 0, nightsWritten % Self.postcardWeekLength == 0
        else { return nil }
        let week = postcardWeek(forDay: entry.dayNumber)
        return postcardSpreads(week: week).isEmpty ? nil : week
    }

    /// Where the week went, in order and each place once: "Chiang Mai → Pai".
    func postcardRoute(week: Int) -> [String] {
        var places: [String] = []
        for day in postcardDays(week: week) {
            guard let place = lastKnownSegment(forDay: day)?.primaryPlace,
                  !place.isEmpty, !places.contains(place) else { continue }
            places.append(place)
        }
        return places
    }

    /// The last stamp earned that week, for the seal in the postcard's corner.
    func postcardStamp(week: Int) -> Stamp? {
        let days = postcardDays(week: week)
        return earnedStamps.last { stamp in
            stamp.earnedOn.map { days.contains(dayNumber(for: $0)) } ?? false
        }
    }
}
