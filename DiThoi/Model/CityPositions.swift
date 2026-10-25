import Foundation

/// Where a typed city is, from a list that ships inside the app.
///
/// A waypoint somebody typed had no position until somebody stood in it, so
/// the three things that need one never happened on a trip nobody packed: the
/// "You look close" nudge, the distance to the next stop, and anything ahead
/// on the map. Asking the network would break the app's first promise, that it
/// works with no signal — so the answer is GeoNames' cities of 15,000 people or
/// more, bundled as `Resources/cities.tsv` by `Tools/build-cities.sh`. CC BY
/// 4.0, which is why the settings screen credits it.
///
/// **Only ever inside the country the stop is in.** There are a dozen
/// Springfields and two Hyderabads; a city looked up anywhere would put a stop
/// on the wrong continent and fire the nudge there. An unknown country answers
/// nil, the country card's rule (§8.5): never one country's answer under
/// another's name.
struct CityPositions {
    struct Position: Equatable {
        var latitude: Double
        var longitude: Double
    }

    /// ISO code → that country's lines, unparsed. A lookup scans one country,
    /// a few hundred lines at most, so nothing is built for the other 250 —
    /// the list is read at launch whenever a waypoint is missing a position.
    private var lines: [String: [Substring]] = [:]
    /// Every way of writing a country, normalised → its ISO code.
    private var countries: [String: String] = [:]

    init(tsv: String) {
        for line in tsv.split(separator: "\n") {
            if line.hasPrefix("#") {
                let columns = line.split(separator: "\t")
                guard columns.count >= 3 else { continue }
                countries[CountryFacts.normalise(String(columns[2]))] = String(columns[1])
            } else if let tab = line.firstIndex(of: "\t") {
                lines[String(line[..<tab]), default: []].append(line)
            }
        }
        // The spellings the country list doesn't carry, and that people type.
        for (alias, code) in CityPositions.aliases where countries[CountryFacts.normalise(alias)] == nil {
            countries[CountryFacts.normalise(alias)] = code
        }
    }

    /// The bundled list, read the first time a position is asked for. Nil in
    /// the checks, which build their own from a fixture.
    static let bundled: CityPositions? = Bundle.main
        .url(forResource: "cities", withExtension: "tsv")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        .map(CityPositions.init(tsv:))

    func code(forCountry country: String) -> String? {
        countries[CountryFacts.normalise(country)]
    }

    /// The most populous city in that country going by that name, under any
    /// of its Latin-script spellings — "Saigon", "Sài Gòn" and "Ho Chi Minh
    /// City" are one place.
    func position(of city: String, inCountry country: String) -> Position? {
        let wanted = CountryFacts.normalise(city)
        guard !wanted.isEmpty, let code = code(forCountry: country), let rows = lines[code] else { return nil }
        // Sorted by population, largest first, by the script — so the first
        // match is the one meant: Bangkok, not Bangkok Noi.
        for row in rows {
            let columns = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 5,
                  columns[4...].contains(where: { CountryFacts.normalise(String($0)) == wanted }),
                  let latitude = Double(columns[1]), let longitude = Double(columns[2])
            else { continue }
            return Position(latitude: latitude, longitude: longitude)
        }
        return nil
    }

    private static let aliases: [(String, String)] = [
        ("Viet Nam", "VN"), ("Korea", "KR"), ("Republic of Korea", "KR"),
        ("UK", "GB"), ("Great Britain", "GB"), ("Britain", "GB"), ("England", "GB"),
        ("Scotland", "GB"), ("Wales", "GB"), ("Northern Ireland", "GB"),
        ("USA", "US"), ("US", "US"), ("America", "US"), ("United States of America", "US"),
        ("Czech Republic", "CZ"), ("Holland", "NL"), ("Burma", "MM"), ("Lao PDR", "LA"),
        ("Türkiye", "TR"), ("Turkey", "TR"), ("UAE", "AE"), ("Ivory Coast", "CI"),
    ]
}
