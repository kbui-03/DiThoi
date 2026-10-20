import Foundation

/// The only thing the widget can see.
///
/// Moving `dithoi.trip.v3` into the shared container would be the cheap way to
/// feed a widget, and it would put the journal and the sealed letters inside a
/// container the extension is entitled to read. So nothing moves.
///
/// The trip, the shelf, the rates, the photos, the passport scans and the
/// letter drop all stay in the app's own container, and the group holds exactly
/// one key whose value is this: a day, a place, and a distance. Two checks hold
/// it — the group's key set is exactly `[snapshotKey]`, and every field here is
/// a scalar, so nothing that could hold a journal can be added later.
///
/// It also means no migration: nothing has to be found in a new place, so
/// `TripStore.init` can never take its seeding branch because of this.
enum AppGroup {
    static let id = "group.com.lovedones.dithoi"

    /// One constant for the kind, so the app's reload call and the extension's
    /// `Widget` cannot drift apart into a widget that never refreshes.
    static let widgetKind = "DiThoiDay"

    static let snapshotKey = "dithoi.widget.v1"

    /// How far ahead the app publishes. Every entry is one day, and the widget
    /// asks for more when it runs out.
    static let horizon = 24
}

struct WidgetSnapshot: Codable, Equatable {
    enum Phase: String, Codable { case before, during, after }

    /// The day this describes, at local midnight. The widget's timeline entry
    /// dates are these.
    var date: Date
    var phase: Phase
    var daysUntilDeparture: Int
    var dayNumber: Int
    var dayCount: Int
    var city: String
    var nextCity: String?
    var daysUntilNextCity: Int?
    var tripName: String
    var isClosed: Bool

    var progress: Double { TripMarkGeometry.progress(day: dayNumber, of: dayCount) }

    /// The dot is a claim that something has been walked, so before departure
    /// there isn't one.
    var showsDot: Bool { phase != .before }

    /// The label the app already uses, computed in one place because it has a
    /// number in it. `TodayView` and `HomeView` say these exact sentences.
    var kicker: String {
        switch phase {
        case .before:
            daysUntilDeparture == 1 ? "Tomorrow" : "\(daysUntilDeparture) days to go"
        case .during:
            "Day \(dayNumber) of \(dayCount)"
        case .after:
            "Home · \(dayCount) day\(dayCount == 1 ? "" : "s") done"
        }
    }

    /// Where they are. The small tile has room for this and nothing else.
    var place: String {
        phase == .after ? "The trip is over" : city
    }

    /// Where they're going, if anywhere. Kept apart from `place` so the small
    /// tile can drop it rather than wrap a whole sentence over three lines.
    var nextLine: String? {
        guard phase == .during, let nextCity,
              let days = daysUntilNextCity, days > 0 else { return nil }
        return "\(days) day\(days == 1 ? "" : "s") until \(nextCity)"
    }

    /// Both halves, for the tiles wide enough to hold them.
    var headline: String {
        guard let nextLine else { return place }
        return "\(place) · \(nextLine)"
    }

    // MARK: - The wire

    /// What the widget draws before anything has been published — a fresh
    /// install, or an extension that couldn't reach the group. Blank: no city
    /// and no counts anybody could mistake for their own.
    static let placeholder = WidgetSnapshot(
        date: Date(timeIntervalSinceReferenceDate: 0),
        phase: .before, daysUntilDeparture: 0,
        dayNumber: 1, dayCount: 1, city: "—",
        nextCity: nil, daysUntilNextCity: nil,
        tripName: "Đi Thôi", isClosed: false)

    static func read(from suite: UserDefaults?) -> [WidgetSnapshot] {
        guard let data = suite?.data(forKey: AppGroup.snapshotKey),
              let days = try? JSONDecoder().decode([WidgetSnapshot].self, from: data)
        else { return [] }
        return days
    }

    static func write(_ days: [WidgetSnapshot], to suite: UserDefaults?) {
        guard let suite, let data = try? JSONEncoder().encode(days) else { return }
        suite.set(data, forKey: AppGroup.snapshotKey)
    }

    static func clear(from suite: UserDefaults?) {
        suite?.removeObject(forKey: AppGroup.snapshotKey)
    }
}
