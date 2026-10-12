import Foundation

/// The preview's page bar, scrubbed by date.
///
/// The bar is a timeline of the trip, day 1 to the last, on the same axis as
/// the trip mark — so a finger at the middle of it is the middle of the trip,
/// not the middle of the page count, which bunches wherever the writing was
/// heaviest. A day maps to the spread of its night; a night with no page maps
/// to the next one that has one, and past the last written night to the last
/// written night. Never to a non-day spread: the bar is for finding a day.
extension TripStore {
    /// Every written night in the book, in day order, with the spread it is.
    var bookNights: [(day: Int, index: Int)] {
        let spreads = bookPlan.spreads
        var nights: [(day: Int, index: Int)] = []
        for (index, spread) in spreads.enumerated() {
            guard case .day(let id) = spread, let entry = entry(id) else { continue }
            nights.append((entry.dayNumber, index))
        }
        return nights.sorted { $0.day < $1.day }
    }

    /// The trip day a spread is a night of; nil for every other kind.
    func bookDay(ofSpreadAt index: Int) -> Int? {
        bookNights.first { $0.index == index }?.day
    }

    /// Where scrubbing to a day lands. Nil only when the book has no nights.
    func bookSpreadIndex(forDay day: Int) -> Int? {
        let nights = bookNights
        return (nights.first { $0.day >= day } ?? nights.last)?.index
    }

    /// What the bubble over the bar says: "Day 12 · 30 Jul · Chiang Mai ·
    /// p. 24", or "Day 13 · 31 Jul · no page" for a night that was missed —
    /// said as plainly as the book's own "Days 13–14 · no page" line.
    func scrubLabel(forDay day: Int) -> String {
        var parts = ["Day \(day)", date(forDay: day).shortDayMonth]
        let place = city(forDay: day)
        if place != TripStore.unknownPlace, !place.isEmpty { parts.append(place) }
        if bookNights.contains(where: { $0.day == day }), let page = bookPage(forDay: day) {
            parts.append("p. \(page)")
        } else {
            parts.append("no page")
        }
        return parts.joined(separator: " · ")
    }
}
