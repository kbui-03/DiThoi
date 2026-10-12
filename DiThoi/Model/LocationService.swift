import Foundation
import CoreLocation

/// Where they are — asked for by the act that needs it, never at launch.
///
/// Position is shared only while Separated is on, and only as a city. So this
/// asks for when-in-use authorisation at the moment Separated starts, never at
/// launch, and stops the moment they find each other. There is no background
/// mode and no always-on authorisation.
@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published private(set) var current: CLLocation?
    @Published private(set) var authorisation: CLAuthorizationStatus
    @Published private(set) var isTracking = false

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

    // MARK: - Distances

    func distance(toLatitude latitude: Double, longitude: Double) -> Measurement<UnitLength>? {
        guard let current else { return nil }
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return Measurement(value: current.distance(from: target), unit: .meters)
    }

    /// "north-east" — the way you'd say it to someone, not a bearing in degrees.
    func compassDirection(toLatitude latitude: Double, longitude: Double) -> String? {
        guard let current else { return nil }
        let from = current.coordinate
        let to = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        let fromLat = from.latitude * .pi / 180
        let toLat = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(toLat)
        let x = cos(fromLat) * sin(toLat) - sin(fromLat) * cos(toLat) * cos(deltaLon)
        var degrees = atan2(y, x) * 180 / .pi
        if degrees < 0 { degrees += 360 }

        let points = ["north", "north-east", "east", "south-east",
                      "south", "south-west", "west", "north-west"]
        return points[Int((degrees + 22.5) / 45) % 8]
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let newest = locations.last else { return }
            current = newest
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
        // Nothing to say. The screen falls back to the written directions,
        // which is what it had before location existed.
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
