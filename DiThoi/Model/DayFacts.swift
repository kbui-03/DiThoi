import Foundation

/// What the app already knows about a day, set as one quiet line in the day
/// page's footer: "฿1,240 · 14 km · 3 moments".
///
/// Every figure is computed from the trip, and nothing is fetched. A
/// temperature was asked for and refused: the app holds no weather, and a
/// number nothing on the phone can derive is the "38 pins dropped" bug.
struct DayFacts: Equatable {
    /// The footer's mono tracking for the facts; the tags beside them use 0.14.
    static let tracking = 0.1

    /// The day's spending, in the money of the leg that day was in.
    var spent: Double = 0
    var currency: Currency?
    /// Whether saying it meant converting anything. `spentTodayText`'s rule:
    /// a "≈" on a day that needed a rate, and never on one that didn't.
    var converted = false
    /// The trail walked that day, in whole kilometres.
    var kilometres = 0
    var moments = 0

    /// The line, clause by clause, each dropping when it has nothing to say
    /// — the way `TripStore.packedSummary` is built. Nil when every clause
    /// drops, so the footer never prints a separator standing alone.
    var line: String? { lines.first }

    /// The line and its shorter selves, longest first: each drops the last
    /// clause. The footer shares its line with the tags, and the tags are
    /// what somebody chose, so it is the facts that give way — the page sets
    /// the longest that fits beside them and drops the rest a clause at a
    /// time, never mid-figure. Money is last to go.
    var lines: [String] {
        let all = clauses
        return all.indices.reversed().map { all[...$0].joined(separator: " · ") }
    }

    private var clauses: [String] {
        var clauses: [String] = []
        if spent > 0, let currency {
            clauses.append(converted ? "≈\(currency.formatRounded(spent))" : currency.format(spent))
        }
        if kilometres > 0 {
            clauses.append("\(Formatting.decimal(Double(kilometres), places: 0)) km")
        }
        if moments > 0 {
            clauses.append(Formatting.spelledCount(moments, "moment", spellingUpTo: 0))
        }
        return clauses
    }
}

extension TripStore {
    /// The facts for one night of the book.
    ///
    /// Not memoised, and that is deliberate. The book's cache is kept honest by
    /// the `didSet`s that call `bookInputsChanged()`, and expenses are not
    /// among them — so caching this would freeze the money on a page the
    /// first time it was drawn. If it is ever cached, `expenses` joins that
    /// list first.
    func dayFacts(forDay day: Int) -> DayFacts {
        var facts = DayFacts()

        // The currency of *that* day's leg, not `localCurrency`, which is
        // today's: a night in Hội An reads in dong after they have flown on to
        // Seoul. A day no leg covers reads in the home currency.
        let currency = leg(forDay: day)?.currency ?? homeCurrency
        let spent = expenses(onDay: day)
        if !spent.isEmpty {
            facts.currency = currency
            facts.spent = spent.reduce(0) {
                $0 + rates.snapshot.convert($1.amount, from: $1.currency, to: currency)
            }
            facts.converted = spent.contains { $0.currency != currency }
        }

        facts.kilometres = kilometresWalked[day] ?? 0
        facts.moments = moments(onDay: day).count
        return facts
    }

    /// The trail's kilometres, credited to the day each leg *arrived*.
    ///
    /// The walk is `TrailReplay.kilometres(along:)`'s exactly — located earned
    /// stamps in order, unlocated ones skipped — so the days add up to the
    /// trail's headline by construction rather than by agreement. A check
    /// holds them equal: a page's "14 km" must never be a second answer to
    /// the trail's one question.
    ///
    /// Rounding each day on its own would not do it: three days of 0.5 km
    /// round to 3 while the trail says 2. So the whole kilometres are handed
    /// out by largest remainder, which makes the days sum to the rounded total
    /// exactly.
    var kilometresWalked: [Int: Int] {
        let route = earnedStamps.filter(\.hasLocation)
        var byDay: [Int: Double] = [:]
        for (from, to) in zip(route, route.dropFirst()) {
            guard let earnedOn = to.earnedOn else { continue }
            byDay[dayNumber(for: earnedOn), default: 0] += from.kilometres(to: to)
        }
        let total = TrailReplay.kilometres(along: earnedStamps)
        var whole = byDay.mapValues { Int($0.rounded(.down)) }
        let short = total - whole.values.reduce(0, +)
        let byRemainder = byDay.sorted {
            let a = $0.value - $0.value.rounded(.down), b = $1.value - $1.value.rounded(.down)
            return a != b ? a > b : $0.key < $1.key
        }
        for (day, _) in byRemainder.prefix(max(short, 0)) { whole[day, default: 0] += 1 }
        return whole
    }
}
