import SwiftUI
import WidgetKit

struct DayEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

/// Reads the published days and hands one to the view per calendar day.
///
/// The only input that moves on its own is what day it is, so the timeline is
/// simply the days themselves. WidgetKit draws the last entry whose date has
/// passed, which means a phone that hasn't opened the app since Tuesday still
/// shows the right day on Thursday.
struct DayProvider: TimelineProvider {
    private var suite: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }

    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, snapshot: published.first ?? .gallery)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        // The gallery has to draw *something* before anyone has a trip, and a
        // blank rule with no city in it reads as a broken widget rather than an
        // empty one. `.gallery` is the only invented data in the extension and
        // it never survives contact with a real trip.
        let snapshot = current ?? (context.isPreview ? .gallery : .placeholder)
        completion(DayEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let days = published
        guard !days.isEmpty else {
            // Nothing published yet. Ask again shortly rather than never —
            // this is a fresh install between the widget being added and the
            // app being opened.
            let retry = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
            completion(Timeline(entries: [DayEntry(date: .now, snapshot: .placeholder)],
                                policy: .after(retry)))
            return
        }

        let entries = days.map { DayEntry(date: $0.date, snapshot: $0) }
        let last = days[days.count - 1]
        // A closed trip and a finished one have nothing left to say, so they
        // don't spend a refresh saying it. Starting a new trip republishes and
        // reloads, which overrides `.never`.
        let policy: TimelineReloadPolicy =
            (last.isClosed || last.phase == .after) ? .never : .after(last.date)
        completion(Timeline(entries: entries, policy: policy))
    }

    private var published: [WidgetSnapshot] { WidgetSnapshot.read(from: suite) }

    private var current: WidgetSnapshot? {
        let days = published
        let now = Date.now
        return days.last { $0.date <= now } ?? days.first
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.widgetKind, provider: DayProvider()) { entry in
            DayWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Đi Thôi")
        .description("How far along the trip is, and where you're going next.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryCircular])
    }
}

extension WidgetSnapshot {
    /// For the widget gallery only, before a trip exists. The design's own
    /// example, with its arithmetic corrected — it prints "11 days until Seoul"
    /// on day 38, and the itinerary it ships puts Seoul on day 47.
    static let gallery = WidgetSnapshot(
        date: Date(timeIntervalSinceReferenceDate: 0),
        phase: .during, daysUntilDeparture: 0,
        dayNumber: 38, dayCount: 61, city: "Hội An",
        nextCity: "Seoul", daysUntilNextCity: 9,
        tripName: "Đi Thôi", isClosed: false)
}
