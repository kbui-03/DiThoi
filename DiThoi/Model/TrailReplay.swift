import Foundation

/// The trail, day by day — what the last-day screen and a shelved trip play.
///
/// Derived entirely from what the live screens already read: a stamp appears
/// on the day its `earnedOn` falls, a moment on the day it was kept, and the
/// kilometres are measured the way `kilometresTravelled` measures them — along
/// earned stamps that have a position, in the order they were earned. So the
/// last frame *is* the trail's own headline, and a check holds the two
/// together; a replay that ended on a different number would be a second
/// answer to the one question the trail screen exists to answer.
struct TrailReplay {
    struct Frame: Equatable {
        let day: Int
        /// Earned by the end of `day`, located or not — the map only draws the
        /// located ones, and the count is still a count of places stood in.
        let stamps: [Stamp]
        let moments: [Moment]
        let kilometres: Int
    }

    let stamps: [Stamp]
    let moments: [Moment]
    let start: Date
    let dayCount: Int

    /// - Parameters:
    ///   - stamps: live ones only; tombstones are not part of the trail.
    ///   - moments: finished or not — a spot with nothing written was still
    ///     somewhere they stood, and on a map it says so honestly.
    init(stamps: [Stamp], moments: [Moment], start: Date, dayCount: Int) {
        self.stamps = stamps.filter(\.earned).sorted { ($0.earnedOn ?? .distantPast) < ($1.earnedOn ?? .distantPast) }
        self.moments = moments.sorted { $0.capturedAt < $1.capturedAt }
        self.start = start
        self.dayCount = max(dayCount, 1)
    }

    /// Nothing that could be drawn. The screens say so rather than animating
    /// an empty map for twelve seconds.
    var isEmpty: Bool {
        !stamps.contains(where: \.hasLocation) && !moments.contains(where: \.hasLocation)
    }

    /// Day 0 exists only when something happened before departure, so a trip
    /// that began at the gate starts there and one that didn't starts on day 1.
    var days: ClosedRange<Int> {
        (moments.contains(where: \.isBeforeDeparture) ? 0 : 1)...dayCount
    }

    func frame(atDay day: Int) -> Frame {
        let clamped = min(max(day, days.lowerBound), days.upperBound)
        let earned = stamps.filter { stamp in
            guard let earnedOn = stamp.earnedOn else { return false }
            return dayNumber(of: earnedOn) <= clamped
        }
        let kept = moments.filter { moment in
            moment.isBeforeDeparture || dayNumber(of: moment.capturedAt) <= clamped
        }.filter { clamped >= 1 || $0.isBeforeDeparture }
        return Frame(day: clamped, stamps: earned, moments: kept,
                     kilometres: Self.kilometres(along: earned))
    }

    var last: Frame { frame(atDay: days.upperBound) }

    /// `kilometresTravelled`'s rule, shared: skip what has no position rather
    /// than zero the legs either side of it.
    static func kilometres(along earned: [Stamp]) -> Int {
        let route = earned.filter(\.hasLocation)
        guard route.count > 1 else { return 0 }
        let total = zip(route, route.dropFirst()).reduce(0.0) { $0 + $1.0.kilometres(to: $1.1) }
        return Int(total.rounded())
    }

    private func dayNumber(of date: Date) -> Int {
        Calendar.trip.days(from: start, to: date) + 1
    }
}
