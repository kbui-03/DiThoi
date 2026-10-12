import Foundation
#if os(iOS)
import WidgetKit
#endif

/// What the app tells the widget, and nothing else.
///
/// The derivation lives on the app side on purpose: `Shared/WidgetSnapshot.swift`
/// travels into the extension and this file does not, so the extension has no
/// way to reach a `Leg`, a `Letter` or a `JournalEntry` even by accident. See
/// the note at the top of that file.
extension TripStore {

    // MARK: - Where they'll be next

    /// The next place, and how far off it is.
    ///
    /// The next *leg* first, because "9 days until Seoul" is about crossing a
    /// border and that is the thing worth counting down. Failing that — they're
    /// already in the last country — the next segment, so the line still says
    /// something on the last leg. Failing that, nothing: on the final stop there
    /// is no next place, and the headline drops the clause rather than inventing
    /// one.
    ///
    /// (The design's own widget reads "Hội An · 11 days until Seoul" on day 38.
    /// The seeded itinerary puts Hội An at days 32–41 and South Korea at day 47,
    /// so the answer is 9. Same as the "61 days" the prototype printed on six
    /// screens over a 72-day range: when a design's numbers disagree, compute.)
    func nextStop(after day: Int) -> (city: String, days: Int)? {
        if let leg = legs.first(where: { $0.startDay > day }),
           let opening = leg.segments.min(by: { $0.startDay < $1.startDay }) {
            return (opening.primaryPlace, leg.startDay - day)
        }
        if let segment = itinerary.allSegments
            .filter({ $0.startDay > day })
            .min(by: { $0.startDay < $1.startDay }) {
            return (segment.primaryPlace, segment.startDay - day)
        }
        return nil
    }

    // MARK: - The snapshot

    /// One day, as the widget will draw it.
    func widgetSnapshot(on date: Date) -> WidgetSnapshot {
        let day = min(max(dayNumber(for: date), 1), dayCount)
        var kind = WidgetSnapshot.Phase.during
        var untilDeparture = 0
        switch phase(on: date) {
        case .before(let daysUntil):
            kind = .before
            untilDeparture = daysUntil
        case .during:
            kind = .during
        case .after:
            kind = .after
        }
        // Before departure the next stop is the *first* stop, which `city`
        // already is — counting down to it twice would read as two journeys.
        let next = kind == .during ? nextStop(after: day) : nil
        return WidgetSnapshot(
            date: Calendar.trip.startOfDay(for: date),
            phase: kind,
            daysUntilDeparture: untilDeparture,
            dayNumber: day,
            dayCount: dayCount,
            city: city(forDay: day),
            nextCity: next?.city,
            daysUntilNextCity: next?.days,
            // The fallback, substituted on the way out: `WidgetSnapshot` holds
            // only scalars by design, so it has no room for a computed one, and
            // the widget's corner would otherwise be blank on an unnamed trip.
            tripName: displayName,
            isClosed: closedOn != nil)
    }

    /// Today and the days after it, so the widget can cross midnight without
    /// the app having been opened — and so a future entry can advance the
    /// *city*, not just the day number.
    var widgetSnapshots: [WidgetSnapshot] {
        let today = Calendar.trip.startOfDay(for: now)
        var days: [WidgetSnapshot] = []
        for offset in 0 ..< AppGroup.horizon {
            // Calendar arithmetic, never `+ 86_400`: a DST boundary would
            // otherwise shift every later entry by an hour and the day would
            // tick over at 23:00 for the rest of the trip.
            guard let date = Calendar.trip.date(byAdding: .day, value: offset, to: today)
            else { break }
            let day = widgetSnapshot(on: date)
            days.append(day)
            // One "the trip is over" entry is enough — nothing after it moves.
            if day.phase == .after || day.isClosed { break }
        }
        return days
    }

    /// Publishes, if there is anything new to say.
    ///
    /// Two guards, both load-bearing:
    ///
    /// `persists` — the shelf opens an archived trip as a second store with no
    /// key. Without this, reading a finished trip would repaint the Home Screen
    /// with it and leave it there.
    ///
    /// The equality check — `WidgetCenter` reloads are budgeted at a few dozen
    /// a day, and `save()` fires per burst of typing. An evening of journalling
    /// would spend the whole budget, after which the widget stops updating at
    /// midnight and nothing anywhere says so. `WidgetSnapshot` is coarse enough
    /// that typing a page doesn't change it, so almost all of those are skipped.
    func publishWidgetSnapshot() {
        guard persists else { return }
        TripStore.publishWidget(widgetSnapshots)
    }

    nonisolated static func publishWidget(_ days: [WidgetSnapshot]) {
        guard days != WidgetSnapshot.read(from: Storage.shared) else { return }
        WidgetSnapshot.write(days, to: Storage.shared)
        reloadWidgetTimelines()
    }
}

/// Reloading is iOS-only; the model layer still builds for macOS, which is what
/// `Tools/run-checks.sh` depends on.
func reloadWidgetTimelines() {
    #if os(iOS)
    WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
    #endif
}
