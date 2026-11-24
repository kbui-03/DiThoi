import Foundation
import CoreLocation

/// Where they are — asked for by the act that needs it, never at launch.
///
/// Separated tracks (`start()`, stopped when they find each other); keeping a
/// moment and dropping a pin take one fix (`requestOnce()`); the trail and
/// Today take one only if somebody already said yes (`requestOnceIfAllowed()`).
/// A moment's position stays on the phone. A pin's is the one that travels: an
/// arrival fills a blank waypoint, and waypoints sync. There is no background
/// mode and no always-on authorisation.
@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published private(set) var current: CLLocation?
    @Published private(set) var authorisation: CLAuthorizationStatus
    @Published private(set) var isTracking = false
    /// How many times Core Location has said it couldn't find the phone.
    /// A count rather than a flag so a screen can ask "since I asked?": the
    /// pin row notes it when it asks and compares when it draws.
    @Published private(set) var failures = 0
    /// Whether the last word from Core Location was a failure rather than a
    /// fix. Separated reads it so "Finding you…" can stop.
    @Published private(set) var hasFailedSinceFix = false

    private let manager: CLLocationManager
    /// A one-shot fix asked for before the permission answer came back.
    private var wantsOneFix = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        authorisation = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Street-level is plenty to say "700 m away, north-east", and asking
        // for less precision costs less battery on a phone that's already dying.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    var isDenied: Bool {
        authorisation == .denied || authorisation == .restricted
    }

    private var isAuthorised: Bool {
        #if os(iOS)
        authorisation == .authorizedWhenInUse || authorisation == .authorizedAlways
        #else
        authorisation == .authorizedAlways
        #endif
    }

    func start() {
        isTracking = true
        if authorisation == .notDetermined {
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #endif
        } else if isAuthorised {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        isTracking = false
        manager.stopUpdatingLocation()
        current = nil
    }

    /// One fix, for a moment being recorded now.
    ///
    /// `start()` is Separated's, and it is the only thing that ever asked — so
    /// outside Separated `current` is nil and a moment recorded on a walk would
    /// silently get no position, then silently not draw on the map. This asks
    /// for the same when-in-use authorisation at the same kind of moment: when
    /// the person taps the thing that needs it, never at launch.
    ///
    /// It leaves `isTracking` alone. Separated owns that flag, and `stop()`
    /// clears `current` — so a moment recorded mid-Separated must not tidy up
    /// after itself and blank the 2am screen's distance readout on the way out.
    func requestOnce() {
        guard !isTracking else { return }
        if authorisation == .notDetermined {
            // The answer arrives asynchronously, so the ask has to be
            // remembered — otherwise granting permission produces nothing and
            // the composer says "no position" over a phone that now has one.
            wantsOneFix = true
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #endif
            return
        }
        if isAuthorised { manager.requestLocation() }
    }

    /// A fix, if one can be had without asking.
    ///
    /// For screens that would *like* a position but are never the moment to
    /// ask for one — the trail, opened on any afternoon. The prompt belongs to
    /// the act that needs it: keeping a moment, dropping a pin, Separated.
    func requestOnceIfAllowed() {
        guard !isTracking, isAuthorised else { return }
        manager.requestLocation()
    }

    // MARK: - How old a fix is

    /// Fifteen minutes. A position is a claim about now, and one without its
    /// age pretends to be current. Every reader goes through this — the trail,
    /// the map, the arrival nudge, the moment composer and `arrive(at:)` — so
    /// nothing written down for good is pinned to wherever the phone last was.
    ///
    /// The composer and the stamp used to read `current` raw, so a moment kept
    /// with no new fix landed hours back down the road, and a stamp's position
    /// — which syncs, and never changes again — could be another town's.
    static let freshness: TimeInterval = 15 * 60

    /// Measured against the caller's clock, not `Date()`: the store's `now`
    /// is the clock, and the checks move it.
    static func isFresh(_ fix: CLLocation, at now: Date) -> Bool {
        now.timeIntervalSince(fix.timestamp) < freshness
    }

    /// The last fix, if it is recent enough to stand for where they are now.
    func freshFix(at now: Date) -> CLLocation? {
        current.flatMap { Self.isFresh($0, at: now) ? $0 : nil }
    }

    /// Takes a fix as though Core Location had just delivered it. The
    /// delegate's path, and the checks' way in.
    func record(_ fix: CLLocation) {
        current = fix
        if hasFailedSinceFix { hasFailedSinceFix = false }
    }

    /// Core Location's failure, as an answer. The delegate's path, and the
    /// checks' way in.
    ///
    /// It used to be swallowed, so "Finding where you are…" on the meeting
    /// point picker waited for ever: a one-shot `requestLocation()` that
    /// can't get a fix says so here and nowhere else. While tracking,
    /// `locationUnknown` is the system saying "still trying" and is not a
    /// failure; for a one-shot it is the whole answer.
    func fail(_ error: Error) {
        if isTracking, (error as? CLError)?.code == .locationUnknown { return }
        wantsOneFix = false
        failures += 1
        hasFailedSinceFix = true
    }

    // MARK: - Distances

    func distance(toLatitude latitude: Double, longitude: Double) -> Measurement<UnitLength>? {
        guard let current else { return nil }
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return Measurement(value: current.distance(from: target), unit: .meters)
    }

    /// "north-east": the way to walk from here to there. `Geo.compassPoint`
    /// is the formula.
    func compassDirection(toLatitude latitude: Double, longitude: Double) -> String? {
        guard let current else { return nil }
        return Geo.compassPoint(current.coordinate.latitude, current.coordinate.longitude,
                                latitude, longitude)
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let newest = locations.last else { return }
            record(newest)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorisation = manager.authorizationStatus
            if isTracking, isAuthorised {
                manager.startUpdatingLocation()
            } else if wantsOneFix, isAuthorised {
                wantsOneFix = false
                manager.requestLocation()
            } else if isDenied {
                wantsOneFix = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in fail(error) }
    }
}

extension Measurement where UnitType == UnitLength {
    /// "700 m" / "1.4 km" — the way it reads on the screen.
    var walkingText: String {
        let metres = converted(to: .meters).value
        if metres < 1000 {
            return "\(Int((metres / 10).rounded()) * 10) m"
        }
        return "\(Formatting.decimal(metres / 1000, places: 1)) km"
    }
}

extension MeetingPoint {
    /// "700 m north-east of you": where the meeting point is, from here.
    ///
    /// The compass point is the way *to* the meeting point, so the sentence
    /// has to be about the meeting point. It used to read "700 m north-east of
    /// the meeting point", which sends somebody the opposite way at 2am.
    static func fromHere(_ distance: Measurement<UnitLength>, compass: String?) -> String {
        guard let compass else { return "\(distance.walkingText) away" }
        return "\(distance.walkingText) \(compass) of you"
    }
}
