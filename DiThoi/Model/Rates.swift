import Foundation

/// A set of exchange rates and — just as important — when they were last true.
/// Every conversion in the app carries its date so nobody has to guess how
/// stale a number is.
struct RateSnapshot: Codable, Equatable {
    enum Source: String, Codable {
        /// Shipped with the app.
        case builtIn
        /// Fetched from the network.
        case live
    }

    /// Units of each currency per 1 EUR.
    var perEuro: [String: Double]
    var updatedAt: Date?
    var source: Source

    /// Correct on the day this was built and drifting ever since. Only ever
    /// used until the first successful fetch reaches the phone.
    static let builtIn = RateSnapshot(
        perEuro: [
            "EUR": 1,
            "USD": 1.138,
            "GBP": 0.854,
            "THB": 38.35,
            "VND": 29_900,
            "KRW": 1_666
        ],
        updatedAt: nil,
        source: .builtIn
    )

    /// Units of `currency` per 1 EUR. Falls back to the built-in figure rather
    /// than returning something that would silently zero out a conversion.
    func perEuro(_ currency: Currency) -> Double {
        if let rate = perEuro[currency.code], rate > 0 { return rate }
        return RateSnapshot.builtIn.perEuro[currency.code] ?? 1
    }

    func convert(_ amount: Double, from: Currency, to: Currency) -> Double {
        guard from != to else { return amount }
        let euros = amount / perEuro(from)
        return euros * perEuro(to)
    }

    /// "1 EUR = 38.348 THB"
    func line(for currency: Currency) -> String {
        let rate = perEuro(currency)
        return "1 EUR = \(Formatting.decimal(rate, places: rate >= 100 ? 0 : 3)) \(currency.code)"
    }
}

/// Keeps `snapshot` as fresh as the network allows, and never blocks anything
/// while it tries. The app is built to work with no signal at all; live rates
/// are an improvement on the numbers, not a requirement for them.
@MainActor
final class RatesService: ObservableObject {

    @Published private(set) var snapshot: RateSnapshot
    @Published private(set) var isRefreshing = false
    /// True when the last attempt couldn't reach the network. Not an error the
    /// user has to dismiss — it just explains why the date hasn't moved.
    @Published private(set) var lastAttemptFailed = false

    /// Not private: `DebugScreen.reset()` has to clear it, and a second copy of
    /// the literal over there is how a `-resetTrip` quietly stops resetting
    /// something.
    nonisolated static let storeKey = "dithoi.rates.v1"
    /// Rates move slowly enough that once an hour is plenty.
    private let minimumInterval: TimeInterval = 60 * 60

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        if let data = Storage.defaults.data(forKey: Self.storeKey),
           let cached = try? JSONDecoder().decode(RateSnapshot.self, from: data) {
            snapshot = cached
        } else {
            snapshot = .builtIn
        }
    }

    var isStale: Bool {
        guard let updatedAt = snapshot.updatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > minimumInterval
    }

    /// Called when the app comes to the foreground. Cheap and silent when the
    /// rates are already current.
    func refreshIfNeeded() async {
        guard isStale else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for endpoint in Endpoint.allCases {
            if let fetched = await fetch(endpoint) {
                snapshot = fetched
                lastAttemptFailed = false
                persist()
                return
            }
        }
        lastAttemptFailed = true
    }

    // MARK: - Fetching

    private enum Endpoint: CaseIterable {
        case erAPI
        case currencyAPI

        var url: URL? {
            switch self {
            case .erAPI:
                URL(string: "https://open.er-api.com/v6/latest/EUR")
            case .currencyAPI:
                // A public npm package on a CDN, so whoever publishes it
                // decides what the app converts with, and `@latest` accepts
                // every future version unreviewed.
                //
                // Pinning is the obvious answer and it does not work here. The
                // package is CalVer, republished *daily* — `2026.8.8` — so
                // there is no major to pin (`@1` is a 404, which would silently
                // drop this endpoint), and pinning a dated version freezes the
                // rates at that date, which is the one thing this endpoint
                // exists to avoid. It is a data feed wearing a package's
                // clothes.
                //
                // So the integrity control is not provenance, it is the numbers
                // themselves: `make(from:)` refuses a payload whose rates are
                // implausible against the figures the app shipped with. That
                // holds whoever published them, which is more than a pin would
                // have given. Don't "fix" this back to a version — check that
                // the URL still returns before changing it.
                URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/eur.json")
            }
        }
    }

    private func fetch(_ endpoint: Endpoint) async -> RateSnapshot? {
        guard let url = endpoint.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Nothing about the trip is sent — this is an unauthenticated request
        // for a public list of numbers.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return switch endpoint {
            case .erAPI: Self.decodeERAPI(data)
            case .currencyAPI: Self.decodeCurrencyAPI(data)
            }
        } catch {
            return nil
        }
    }

    /// `{"result":"success","time_last_update_unix":…,"rates":{"USD":1.08,…}}`
    private static func decodeERAPI(_ data: Data) -> RateSnapshot? {
        struct Payload: Decodable {
            let result: String
            let time_last_update_unix: Double?
            let rates: [String: Double]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.result == "success" else { return nil }
        return make(from: payload.rates,
                    updatedAt: payload.time_last_update_unix.map { Date(timeIntervalSince1970: $0) })
    }

    /// `{"date":"2027-04-15","eur":{"usd":1.08,…}}` — lowercase codes.
    private static func decodeCurrencyAPI(_ data: Data) -> RateSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let table = object["eur"] as? [String: Any] else { return nil }

        var rates: [String: Double] = [:]
        for currency in Currency.allCases {
            if let value = table[currency.rawValue] as? Double { rates[currency.code] = value }
        }

        var updatedAt: Date?
        if let day = object["date"] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            updatedAt = formatter.date(from: day)
        }
        return make(from: rates, updatedAt: updatedAt)
    }

    /// How far a fetched rate may sit from the figure the app shipped with
    /// before it is refused outright.
    ///
    /// Currencies drift; they do not move by an order of magnitude between
    /// builds. A factor of four either way is generous enough to cover several
    /// years of ordinary movement — including a currency having a genuinely bad
    /// decade — and tight enough to catch the failures that matter: a decimal
    /// in the wrong place, a table that lost its thousands, a units-per-euro
    /// figure that arrived inverted.
    static let plausibleFactor = 4.0

    /// Whether a rate is close enough to the built-in figure to be believed.
    ///
    /// Not private, and its own function, because it is the thing worth
    /// checking: `make` is otherwise unreachable from a test without a network.
    static func isPlausible(_ rate: Double, for currency: Currency) -> Bool {
        guard rate > 0, rate.isFinite else { return false }
        let anchor = RateSnapshot.builtIn.perEuro(currency)
        guard anchor > 0 else { return true }     // nothing to compare against
        return rate >= anchor / plausibleFactor && rate <= anchor * plausibleFactor
    }

    /// Keeps only the currencies the app knows about, and refuses a payload
    /// that is missing *or implausible* in any of them rather than
    /// half-updating the table.
    ///
    /// `rate > 0` was the whole of the validation, which is not validation: a
    /// rate wrong by a factor of a thousand passed, and every number downstream
    /// is load-bearing. The budget forecast, the per-day-by-country figures and
    /// the `amountHome` written into a `SettlementProposal` — a real transfer
    /// between two people — are all computed from this table. Refusing the
    /// payload falls through to the next endpoint, and failing that to the
    /// cached or built-in rates, which the disclaimer already dates honestly.
    private static func make(from rates: [String: Double], updatedAt: Date?) -> RateSnapshot? {
        var table: [String: Double] = ["EUR": 1]
        for currency in Currency.allCases where currency != .eur {
            guard let rate = rates[currency.code], isPlausible(rate, for: currency) else {
                return nil
            }
            table[currency.code] = rate
        }
        return RateSnapshot(perEuro: table, updatedAt: updatedAt ?? Date(), source: .live)
    }

    /// Swaps in a known set of rates. Used by the model checks so the maths can
    /// be exercised without reaching the network.
    func applyForTesting(_ replacement: RateSnapshot) {
        snapshot = replacement
        lastAttemptFailed = false
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        Storage.defaults.set(data, forKey: Self.storeKey)
    }

    // MARK: - How it reads on screen

    /// The disclaimer that sits under every converted figure.
    var disclaimer: String {
        if isRefreshing && snapshot.source == .builtIn { return "checking today's rates" }
        guard let updatedAt = snapshot.updatedAt, snapshot.source == .live else {
            return "built-in rates · never updated"
        }
        return "rates \(age(of: updatedAt))"
    }

    /// Longer form for the settings screen.
    var detail: String {
        guard let updatedAt = snapshot.updatedAt, snapshot.source == .live else {
            return "No rate update has reached this phone yet, so conversions use the figures the app shipped with."
        }
        let when = "\(updatedAt.shortDate) at \(updatedAt.text("HH:mm"))"
        if lastAttemptFailed {
            return "Last updated \(when). The most recent check couldn't reach the network, so these are still in use."
        }
        return "Last updated \(when)."
    }

    private func age(of date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 90 * 60 { return "updated just now" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "cached \(hours) hours ago" }
        let days = Int(seconds / 86_400)
        if days == 1 { return "cached yesterday" }
        return "cached \(days) days ago"
    }
}
