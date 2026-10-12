import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UserNotifications
#endif

// MARK: - The hour it learns

/// When to ask for tonight's page.
///
/// Not a setting. The design's whole position on this is that the app notices
/// when the walking stops and never says so — there is no screen anywhere that
/// explains the time it picked, and no way to type one in.
///
/// Pure arithmetic over past behaviour, so the interesting half is checkable
/// without a notification centre or a device.
struct RitualClock: Codable, Equatable {
    /// Minutes past midnight, one per night a page was written, newest last.
    private(set) var observations: [Int]

    /// The zone those minutes are counted in.
    ///
    /// Without this the habit follows the phone across a border: observations
    /// are wall-clock minutes, so flying Amsterdam → Bangkok drags a learned
    /// 22:40 to 04:40 and the median walks with it, night after night, until the
    /// prompt has quietly relocated to breakfast. Storing the zone means the
    /// habit is "half ten at night, wherever that is" rather than a number that
    /// only meant something in the country it was learned in.
    ///
    /// Nil on a clock saved before this existed — which is right, because those
    /// observations were recorded in whatever zone the phone was in and there is
    /// no way to know which.
    private(set) var zoneID: String?

    var zone: TimeZone { zoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
    /// Nothing learned yet: late enough that they're indoors, early enough that
    /// it isn't a 1am guilt trip.
    static let fallbackMinute = 21 * 60 + 30
    /// A fortnight is enough to have a habit and short enough to follow one
    /// that changes when the trip does.
    static let window = 14

    init(observations: [Int] = [], zoneID: String? = nil) {
        self.observations = observations
        self.zoneID = zoneID
    }

    /// Records when a page was written, in the zone the habit is kept in.
    ///
    /// The first page fixes the zone. Every one after it is converted into that
    /// zone before it joins the median, so crossing a border doesn't move the
    /// habit — it just means tonight's page was written at a different local
    /// hour, which is the truth.
    mutating func observe(_ date: Date, calendar: Calendar = .trip, in current: TimeZone = .current) {
        if zoneID == nil { zoneID = current.identifier }
        var counting = calendar
        counting.timeZone = zone
        let parts = counting.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return }
        // A page written at 00:20 is last night's, not this morning's, so the
        // small hours count as a late evening rather than dragging the median
        // back to breakfast.
        let raw = hour * 60 + minute
        observations.append(raw < 5 * 60 ? raw + 24 * 60 : raw)
        if observations.count > Self.window { observations.removeFirst(observations.count - Self.window) }
    }

    /// The median rather than the mean, so one 3am airport entry doesn't move
    /// the whole habit.
    var learnedMinute: Int {
        guard !observations.isEmpty else { return Self.fallbackMinute }
        let sorted = observations.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
        return median % (24 * 60)
    }

    var hasLearned: Bool { observations.count >= 3 }

    /// "Never at the same hour twice" — a few minutes either side, derived from
    /// the day so the same day always produces the same answer. Deterministic
    /// on purpose: a notification that moves when the phone is woken twice is a
    /// notification that fires twice.
    func minute(forDay day: Int) -> Int {
        let jitter = [-11, -6, -2, 3, 7, 12, 17][abs(day) % 7]
        let value = learnedMinute + (hasLearned ? jitter : 0)
        return min(max(value, 17 * 60), 23 * 60 + 45)
    }

    /// When to ask, as an absolute moment.
    ///
    /// Resolved in the zone the habit was learned in, so "half ten at night"
    /// stays half ten at night for the person who set it. The notification is
    /// scheduled from the resulting instant rather than from wall-clock
    /// components, which is what stops a flight taken after scheduling firing it
    /// at the wrong local hour.
    func fireDate(forDay day: Int, on date: Date, calendar: Calendar = .trip) -> Date? {
        let total = minute(forDay: day)
        var counting = calendar
        counting.timeZone = zone
        return counting.date(bySettingHour: total / 60, minute: total % 60, second: 0, of: date)
    }
}

// MARK: - What the notification says

/// H1 · plain text, no photo, no badge, no count.
///
/// Three lines, assembled from where they are. Nothing in it is a score, and
/// nothing in it is a streak — a broken streak on a hard day is a punishment,
/// and the design takes the opposite line everywhere else.
struct RitualPrompt: Equatable {
    var dayNumber: Int
    var city: String
    var subject: String

    var title: String { "Day \(dayNumber). \(city)." }
    var body: String { subject }

    /// What the phone shows on the lock screen, as one string, for the places
    /// that render it inline rather than posting it.
    var oneLine: String { "\(title) \(body)" }
}

// MARK: - Missed nights, asked about once

/// H4 · the backfill offer.
///
/// The design forgives missed nights everywhere ("the book skips them"), so the
/// one place it mentions them is a single offer, once, for the night just gone.
/// `offered` is what stops it becoming nagging: a day that has been asked about
/// can never be asked about again, whatever happens to the page afterwards.
struct BackfillOffers: Codable, Equatable {
    private(set) var offered: Set<Int> = []

    /// The most recent unwritten day worth offering, or nil.
    ///
    /// - Only yesterday. Offering day 12 on day 36 is archaeology.
    /// - Only once ever.
    func candidate(today: Int, writtenDays: Set<Int>) -> Int? {
        let yesterday = today - 1
        guard yesterday >= 1, !writtenDays.contains(yesterday), !offered.contains(yesterday) else { return nil }
        return yesterday
    }

    mutating func markOffered(_ day: Int) { offered.insert(day) }
}

// MARK: - Posting it

/// Everything the ritual needs that only the device can do. Kept behind a
/// protocol so the store can be built, and checked, on a machine with no
/// notification centre.
///
/// `@MainActor`, which is where it was always used from: `TripStore` is
/// main-actor-isolated and is the only caller. Saying so is what lets the real
/// implementation hold mutable state — the authorisation flag and the
/// generation counter — without a lock.
@MainActor
protocol RitualScheduler: AnyObject {
    var isAuthorised: Bool { get }
    func requestPermission() async
    /// Replaces whatever was pending. One prompt exists at a time; a queue of
    /// them is how an app ends up shouting.
    func schedule(_ prompt: RitualPrompt, at date: Date)
    func cancelAll()
}

/// Used by the checks and by home mode, where there is nothing to prompt about.
@MainActor
final class SilentRitualScheduler: RitualScheduler {
    private(set) var scheduled: [(RitualPrompt, Date)] = []
    var isAuthorised: Bool { false }
    func requestPermission() async {}
    func schedule(_ prompt: RitualPrompt, at date: Date) { scheduled = [(prompt, date)] }
    func cancelAll() { scheduled = [] }
}

#if canImport(UserNotifications) && canImport(UIKit)

/// The real one. A single non-repeating request, replaced each evening, so the
/// app can never accumulate a backlog of guilt on a phone that was off for a
/// week.
///
/// `@MainActor`, because `schedule` has to finish asynchronously — the
/// authorisation has to be re-read before the centre is touched at all — and
/// `isAuthorised` was being written from that task on a plain class while the
/// store read it from the main actor.
@MainActor
final class LocalRitualScheduler: RitualScheduler {
    private let identifier = "dithoi.ritual.tonight"
    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorised = false
    /// Bumped by every `schedule` and every `cancelAll`.
    ///
    /// `schedule` yields before it adds anything, so a `cancelAll()` arriving in
    /// that window used to remove a request that had not been made yet and then
    /// watch the task add it — a prompt for a trip that had just been closed.
    private var generation = 0

    init() {
        Task { await refreshAuthorisation() }
    }

    func requestPermission() async {
        // Sound only, no badge: a number on the icon would be a count of
        // something, and nothing here counts anybody's nights.
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        isAuthorised = granted
    }

    private func refreshAuthorisation() async {
        let settings = await center.notificationSettings()
        isAuthorised = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    func schedule(_ prompt: RitualPrompt, at date: Date) {
        generation += 1
        let mine = generation
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard date > Date() else { return }

        // Never touch the centre until permission is actually held. Handing it
        // a request while the decision is still "not determined" is what puts a
        // system alert in front of somebody who has only opened the book tab.
        Task { [identifier] in
            await refreshAuthorisation()
            guard isAuthorised else { return }
            // Anything that happened while we were away wins: a later
            // `schedule`, or a `cancelAll` from the trip being closed.
            guard mine == generation else { return }

            let content = UNMutableNotificationContent()
            content.title = prompt.title
            content.body = prompt.body
            content.sound = .default
            // No badge. Deliberate — see above.

            // From an interval, not from wall-clock components. Calendar
            // components are resolved against the device's zone *when the
            // notification fires*, so a flight taken after scheduling would move
            // it — 21:30 components set in Amsterdam fire at 21:30 Bangkok,
            // which is five hours off the habit that produced them.
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier,
                                                        content: content, trigger: trigger))
        }
    }

    func cancelAll() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

#endif
