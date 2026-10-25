import Foundation

// MARK: - People

/// The two slots the ledger, the journal and the book are keyed on.
///
/// The raw values are persisted in several records, so the cases are permanent.
/// A slot carries no name of its own: what it is called is trip data, lives in
/// `TripNames`, and is read through the store.
enum Traveller: String, Codable, CaseIterable, Identifiable {
    case one, two
    var id: String { rawValue }
    var other: Traveller { self == .one ? .two : .one }
}

/// A name and when it was chosen.
///
/// The stamp is per slot rather than per trip, so two phones renaming
/// themselves in the same round both survive the merge. A slot nobody has
/// touched carries `.distantPast` and loses to one somebody has set.
struct StampedName: Codable, Equatable {
    var value: String
    var updatedAt: Date

    static let unset = StampedName(value: "", updatedAt: .distantPast)

    static func newer(_ mine: StampedName, _ theirs: StampedName) -> StampedName {
        theirs.updatedAt > mine.updatedAt ? theirs : mine
    }
}

/// What the people on a trip are called.
///
/// Kept out of `TripSettings`, which merges as one blob on a single timestamp:
/// a rename riding in it would win the dates, the budget and the currency too.
struct TripNames: Codable, Equatable {
    var one: StampedName
    var two: StampedName
    /// Stays on this phone. The observer doesn't join the symmetric channel, so
    /// there is nowhere for this to travel to.
    var observer: String

    /// Nothing named until somebody says so; the fallbacks below stand in.
    static let blank = TripNames(one: .unset, two: .unset, observer: "")

    /// Never empty — copy is assembled from these, and a blank name
    /// mid-sentence reads as a bug.
    subscript(who: Traveller) -> String {
        let stamped = who == .one ? one : two
        return stamped.value.isEmpty ? Self.fallback(who) : stamped.value
    }

    static func fallback(_ who: Traveller) -> String {
        who == .one ? "Traveller one" : "Traveller two"
    }

    var observerName: String { observer.isEmpty ? "Home" : observer }

    mutating func set(_ name: String, for who: Traveller, at when: Date) {
        let stamped = StampedName(value: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  updatedAt: when)
        if who == .one { one = stamped } else { two = stamped }
    }

    /// Slot by slot, each on its own stamp, so the merge doesn't need to know
    /// which phone sent the payload.
    func merged(with remote: TripNames) -> TripNames {
        TripNames(one: .newer(one, remote.one),
                  two: .newer(two, remote.two),
                  observer: observer)
    }
}

// MARK: - Money

enum Currency: String, Codable, CaseIterable, Identifiable {
    // Raw values are lowercase ISO 4217 codes and are persisted: on expenses,
    // legs, settings, settlements and the shelf. Add a case; never rename one.
    // An unknown raw value throws and wipes the trip (§5.3).
    //
    // Six of these were the whole list, so Japan, Laos, Cambodia and most of
    // Europe outside the euro could not record what they spent. The set is
    // curated rather than every code the rate feed has: each case needs a
    // built-in rate to be judged against (`RateSnapshot.builtIn`), and none of
    // them has three decimals, because the keypad and `Expense.isEditable`
    // deal in whole units. Bulgaria joined the euro in 2026.
    case eur, usd, gbp, thb, vnd, krw, jpy, cny, hkd, twd, lak, khr, mmk, myr, sgd,
         idr, php, inr, npr, lkr, aed, chf, czk, pln, huf, ron, dkk, sek, nok, isk,
         `try`, cad, mxn, pen, clp, cop, brl, ars, aud, nzd, zar, mad, egp
    var id: String { rawValue }

    var code: String { rawValue.uppercased() }

    /// How a currency is written. One table rather than three switches, so a
    /// new case is one line and a check can ask that every case has one.
    struct Face {
        let symbol: String
        let name: String
        /// What a traveller actually writes down. Nobody records satang.
        let decimals: Int
    }

    static let faces: [Currency: Face] = [
        .eur: Face(symbol: "€", name: "Euro", decimals: 2),
        .usd: Face(symbol: "$", name: "US dollar", decimals: 2),
        .gbp: Face(symbol: "£", name: "Pound sterling", decimals: 2),
        .thb: Face(symbol: "฿", name: "Thai baht", decimals: 0),
        .vnd: Face(symbol: "₫", name: "Vietnamese đồng", decimals: 0),
        .krw: Face(symbol: "₩", name: "Korean won", decimals: 0),
        .jpy: Face(symbol: "¥", name: "Japanese yen", decimals: 0),
        .cny: Face(symbol: "CN¥", name: "Chinese yuan", decimals: 2),
        .hkd: Face(symbol: "HK$", name: "Hong Kong dollar", decimals: 2),
        .twd: Face(symbol: "NT$", name: "New Taiwan dollar", decimals: 0),
        .lak: Face(symbol: "₭", name: "Lao kip", decimals: 0),
        .khr: Face(symbol: "៛", name: "Cambodian riel", decimals: 0),
        .mmk: Face(symbol: "K", name: "Myanmar kyat", decimals: 0),
        .myr: Face(symbol: "RM", name: "Malaysian ringgit", decimals: 2),
        .sgd: Face(symbol: "S$", name: "Singapore dollar", decimals: 2),
        .idr: Face(symbol: "Rp", name: "Indonesian rupiah", decimals: 0),
        .php: Face(symbol: "₱", name: "Philippine peso", decimals: 0),
        .inr: Face(symbol: "₹", name: "Indian rupee", decimals: 0),
        .npr: Face(symbol: "रू", name: "Nepalese rupee", decimals: 0),
        .lkr: Face(symbol: "Rs", name: "Sri Lankan rupee", decimals: 0),
        .aed: Face(symbol: "AED", name: "UAE dirham", decimals: 2),
        .chf: Face(symbol: "CHF", name: "Swiss franc", decimals: 2),
        .czk: Face(symbol: "Kč", name: "Czech koruna", decimals: 0),
        .pln: Face(symbol: "zł", name: "Polish złoty", decimals: 2),
        .huf: Face(symbol: "Ft", name: "Hungarian forint", decimals: 0),
        .ron: Face(symbol: "lei", name: "Romanian leu", decimals: 2),
        .dkk: Face(symbol: "kr", name: "Danish krone", decimals: 2),
        .sek: Face(symbol: "kr", name: "Swedish krona", decimals: 0),
        .nok: Face(symbol: "kr", name: "Norwegian krone", decimals: 0),
        .isk: Face(symbol: "kr", name: "Icelandic króna", decimals: 0),
        .`try`: Face(symbol: "₺", name: "Turkish lira", decimals: 0),
        .cad: Face(symbol: "C$", name: "Canadian dollar", decimals: 2),
        .mxn: Face(symbol: "MX$", name: "Mexican peso", decimals: 0),
        .pen: Face(symbol: "S/", name: "Peruvian sol", decimals: 2),
        .clp: Face(symbol: "CLP$", name: "Chilean peso", decimals: 0),
        .cop: Face(symbol: "COL$", name: "Colombian peso", decimals: 0),
        .brl: Face(symbol: "R$", name: "Brazilian real", decimals: 2),
        .ars: Face(symbol: "AR$", name: "Argentine peso", decimals: 0),
        .aud: Face(symbol: "A$", name: "Australian dollar", decimals: 2),
        .nzd: Face(symbol: "NZ$", name: "New Zealand dollar", decimals: 2),
        .zar: Face(symbol: "R", name: "South African rand", decimals: 0),
        .mad: Face(symbol: "DH", name: "Moroccan dirham", decimals: 0),
        .egp: Face(symbol: "E£", name: "Egyptian pound", decimals: 0),
    ]

    private var face: Face {
        Self.faces[self] ?? Face(symbol: code, name: code, decimals: 0)
    }

    /// Never a bare "$" for anything but the US dollar: a trip through two
    /// dollar countries would otherwise print both ledgers in one sign.
    var symbol: String { face.symbol }
    var name: String { face.name }
    var decimals: Int { face.decimals }

    /// "฿ THB", or just "CHF" where the symbol is the code.
    var chipLabel: String { symbol == code ? code : "\(symbol) \(code)" }

    /// Every case, alphabetical by name, for the "another…" menus.
    static var byName: [Currency] { allCases.sorted { $0.name < $1.name } }

    /// The currency a country most likely spends, among the ones the app can
    /// get a rate for — or nil.
    ///
    /// A suggestion drawn on a chip, never a choice made silently: a leg's
    /// currency drives every conversion on it, and a wrong guess applied
    /// without asking is money filed in the wrong unit. Nil is the ordinary
    /// answer for a country the table doesn't know, and means no chip is
    /// preselected, not that the country is unknown. Keyed through
    /// `CountryFacts.normalise`, so "south korea" and "Việt Nam" find their
    /// row the way the card does.
    static func likely(forCountry country: String) -> Currency? {
        likelyByCountry[CountryFacts.normalise(country)]
    }

    private static let likelyByCountry: [String: Currency] = {
        let rows: [(Currency, [String])] = [
            (.thb, ["Thailand"]),
            (.vnd, ["Vietnam", "Viet Nam"]),
            (.krw, ["South Korea", "Korea", "Republic of Korea"]),
            (.gbp, ["United Kingdom", "UK", "England", "Scotland", "Wales",
                    "Northern Ireland", "Great Britain"]),
            (.usd, ["United States", "USA", "US", "America", "United States of America"]),
            (.eur, ["Austria", "Belgium", "Bulgaria", "Croatia", "Cyprus", "Estonia",
                    "Finland", "France", "Germany", "Greece", "Ireland", "Italy",
                    "Latvia", "Lithuania", "Luxembourg", "Malta", "Netherlands",
                    "Portugal", "Slovakia", "Slovenia", "Spain"]),
            (.jpy, ["Japan"]),
            (.cny, ["China", "People's Republic of China", "PRC"]),
            (.hkd, ["Hong Kong"]),
            (.twd, ["Taiwan"]),
            (.lak, ["Laos", "Lao PDR"]),
            (.khr, ["Cambodia"]),
            (.mmk, ["Myanmar", "Burma"]),
            (.myr, ["Malaysia"]),
            (.sgd, ["Singapore"]),
            (.idr, ["Indonesia", "Bali"]),
            (.php, ["Philippines"]),
            (.inr, ["India"]),
            (.npr, ["Nepal"]),
            (.lkr, ["Sri Lanka"]),
            (.aed, ["United Arab Emirates", "UAE", "Dubai"]),
            (.chf, ["Switzerland", "Liechtenstein"]),
            (.czk, ["Czechia", "Czech Republic"]),
            (.pln, ["Poland"]),
            (.huf, ["Hungary"]),
            (.ron, ["Romania"]),
            (.dkk, ["Denmark"]),
            (.sek, ["Sweden"]),
            (.nok, ["Norway"]),
            (.isk, ["Iceland"]),
            (.`try`, ["Turkey", "Türkiye"]),
            (.cad, ["Canada"]),
            (.mxn, ["Mexico"]),
            (.pen, ["Peru"]),
            (.clp, ["Chile"]),
            (.cop, ["Colombia"]),
            (.brl, ["Brazil"]),
            (.ars, ["Argentina"]),
            (.aud, ["Australia"]),
            (.nzd, ["New Zealand"]),
            (.zar, ["South Africa"]),
            (.mad, ["Morocco"]),
            (.egp, ["Egypt"])
        ]
        var table: [String: Currency] = [:]
        for (currency, names) in rows {
            for name in names { table[CountryFacts.normalise(name)] = currency }
        }
        return table
    }()

    /// Currencies you can hold a trip budget in: any of them, the common
    /// three first.
    static let homeOptions: [Currency] = [.eur, .gbp, .usd]
        + byName.filter { ![.eur, .gbp, .usd].contains($0) }

    func format(_ amount: Double) -> String {
        prefix + Formatting.decimal(amount, places: decimals)
    }

    /// Whole units only — for headlines where the cents are noise.
    func formatRounded(_ amount: Double) -> String {
        prefix + Formatting.decimal(amount.rounded(), places: 0)
    }

    /// A symbol that ends in a letter ("Rp", "CHF", "kr") gets a space before
    /// the number, or "Rp15000" reads as one word.
    private var prefix: String {
        symbol.last?.isLetter == true ? symbol + " " : symbol
    }
}

enum Formatting {
    /// One formatter per shape, not one per call.
    ///
    /// `NumberFormatter` is expensive to build and these are read inside
    /// scrolling lists, so a ledger row cost an allocation and a locale lookup
    /// every time it was drawn. There are two shapes in the whole app.
    ///
    /// The forced `en_GB` locale and the explicit separators stay: taking the
    /// device region renders `38.348 THB` as `"38,348"` on a Dutch phone.
    private static let formatters = FormatterBox<Key, NumberFormatter> { key in
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_GB")
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = key.grouping
        formatter.minimumFractionDigits = key.places
        formatter.maximumFractionDigits = key.places
        return formatter
    }

    private struct Key: Hashable {
        var places: Int
        var grouping: Bool
    }

    static func decimal(_ value: Double, places: Int, grouping: Bool = true) -> String {
        let formatter = formatters.formatter(for: Key(places: places, grouping: grouping))
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// The spelled-out shape, which is a third one and had no home.
    ///
    /// Both callers built their own on every read, from `body`, on screens
    /// `TripStore` invalidates on every mutation — exactly the cost `formatters`
    /// above exists to avoid, in the one shape that never got consolidated. A
    /// `let` rather than a `FormatterBox` entry because there is nothing to key
    /// on; the box's rule still holds, which is that it is configured once and
    /// mutated never.
    private static let speller: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_GB")
        return formatter
    }()

    /// A count and the noun it governs, spelled out while that still reads as
    /// English.
    ///
    /// "One days in" is what this exists to make unrepresentable. The number is
    /// a *word*, so nothing in the sentence forces the noun to agree with it,
    /// and both callers had simply written the plural into the string —
    /// `BookView` on the first day of every trip, `ItineraryView` on any
    /// one-day one, which `dayCount`'s `min(max(days, 1), 3650)` allows.
    ///
    /// Past `spellingUpTo` a numeral is kinder: "Three thousand six hundred and
    /// fifty days in" is a 38pt headline. `ItineraryView` guarded that and
    /// `BookView` did not — one sentence written twice, disagreeing in two
    /// different places, which is the shape of the seven copies of the waypoint
    /// join that `segment(for:)` exists to end.
    ///
    /// Capitalised, because both callers are headlines.
    static func spelledCount(_ value: Int, _ singular: String,
                             plural: String? = nil,
                             spellingUpTo limit: Int = 100) -> String {
        let noun = value == 1 ? singular : (plural ?? singular + "s")
        guard value >= 0, value <= limit,
              let words = speller.string(from: NSNumber(value: value)),
              !words.isEmpty
        else { return "\(value) \(noun)" }
        return words.prefix(1).uppercased() + words.dropFirst() + " " + noun
    }
}

/// A tiny memo for the two formatter types, which are expensive to build and
/// safe to reuse once configured.
///
/// Locked rather than actor-isolated: `Date.text(_:)` and `Formatting.decimal`
/// are called from `body` on the main actor and from the checks off it, and
/// neither can afford to become `async`. `Foundation`'s formatters are not
/// documented as thread-safe for *configuration*, which is why the box hands
/// back an already-configured one and nothing mutates it afterwards.
final class FormatterBox<Key: Hashable, Value: AnyObject>: @unchecked Sendable {
    private let make: (Key) -> Value
    private var cache: [Key: Value] = [:]
    private let lock = NSLock()

    init(_ make: @escaping (Key) -> Value) { self.make = make }

    func formatter(for key: Key) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let held = cache[key] { return held }
        let made = make(key)
        cache[key] = made
        return made
    }
}

enum Split: String, Codable, CaseIterable, Identifiable {
    case evenly, mineOnly, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .evenly: "Evenly"
        case .mineOnly: "Mine only"
        case .custom: "Custom"
        }
    }
}

enum Payer: String, Codable, CaseIterable, Identifiable {
    case one, two, both
    var id: String { rawValue }

    /// Which slot paid, when one of them did. `label(for:)` on the store turns
    /// this into something with a name on it.
    var traveller: Traveller? {
        switch self {
        case .one: .one
        case .two: .two
        case .both: nil
        }
    }
}

// MARK: - Syncing

/// A record that can be merged with the same record from the other phone.
///
/// Merging is last-writer-wins per record, which for the append-only
/// collections (expenses, stamps) is just a union, and which handles edits and
/// deletions correctly when they do happen. `deletedAt` is a tombstone rather
/// than a removal so a delete can win over a concurrent edit.
protocol SyncableRecord: Identifiable, Codable, Hashable {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension SyncableRecord {
    var isDeleted: Bool { deletedAt != nil }
}

extension Array where Element: SyncableRecord {
    /// Union by id, keeping whichever side was written last.
    func merged(with other: [Element]) -> [Element] {
        var byID: [Element.ID: Element] = [:]
        for record in self { byID[record.id] = record }
        for record in other {
            if let existing = byID[record.id], existing.updatedAt >= record.updatedAt { continue }
            byID[record.id] = record
        }
        return Array(byID.values)
    }

    /// What a screen should draw: everything that hasn't been tombstoned.
    var live: [Element] { filter { !$0.isDeleted } }
}

enum ExpenseKind: String, Codable {
    /// Money left the trip. Counts against the budget.
    case spend
    /// Money moved between the two of them. Moves the balance, and the budget
    /// never notices.
    case transfer
}

/// What a line of the ledger was for.
///
/// Inferred from the note rather than asked for, because a category picker on
/// the add-expense screen is one more tap at the exact moment somebody is
/// standing at a counter. `Expense.category` stays nil until a traveller
/// disagrees with the guess, so a correction is distinguishable from a guess
/// that happened to be right — and re-inference never overwrites a correction.
enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case stay, food, transport, tickets, stuff, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .stay: "Stay"
        case .food: "Food"
        case .transport: "Getting about"
        case .tickets: "Tickets"
        case .stuff: "Stuff"
        case .other: "Everything else"
        }
    }

    /// Lowercase words that decide it. First category with a hit wins, in the
    /// order of `CaseIterable`, so "guesthouse dinner" is a stay.
    var keywords: [String] {
        switch self {
        case .stay:
            ["guesthouse", "hostel", "hotel", "room", "night", "nights", "airbnb",
             "homestay", "deposit", "orapin", "check-in", "dorm"]
        case .food:
            ["dinner", "lunch", "breakfast", "food", "eat", "coffee", "beer",
             "market", "street", "noodles", "khao", "soi", "cao", "lầu", "banh",
             "bánh", "phở", "pho", "snack", "water", "drinks", "bar", "restaurant"]
        case .transport:
            ["bus", "train", "taxi", "grab", "tuk", "flight", "ferry", "boat",
             "scooter", "bike", "bicycle", "bicycles", "transfer", "transfers",
             "minibus", "sleeper", "metro", "fuel", "petrol"]
        case .tickets:
            ["temple", "temples", "ticket", "tickets", "entry", "museum", "park",
             "tour", "springs", "show", "class", "cooking", "dive", "trek"]
        case .stuff:
            ["laundry", "sim", "clothes", "poncho", "bag", "bags", "gun", "guns",
             "supplies", "shop", "pharmacy", "sunscreen", "gift", "gifts", "souvenir"]
        case .other:
            []
        }
    }

    /// Best guess for a note, before anybody corrects it.
    static func inferred(from note: String) -> SpendCategory {
        let words = Set(
            note.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.union(
                    CharacterSet(charactersIn: "ầớếồ")).inverted)
                .filter { !$0.isEmpty }
        )
        for category in SpendCategory.allCases where !category.keywords.isEmpty {
            if words.contains(where: { word in category.keywords.contains(word) }) {
                return category
            }
        }
        return .other
    }
}

struct Expense: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double
    var currency: Currency
    var payer: Payer
    var split: Split
    var note: String
    var country: String
    var kind: ExpenseKind = .spend
    /// For `.custom` splits: the fraction of the bill borne by whoever didn't
    /// pay. `.evenly` is 0.5 and `.mineOnly` is 0.
    var customShare: Double = 0.5
    /// Nil means "nobody has disagreed with the guess". Set means a traveller
    /// corrected it, and inference must leave it alone from then on.
    var correctedCategory: SpendCategory?
    var updatedAt: Date = .distantPast
    var deletedAt: Date?

    /// What this line counts as. A correction if there is one, the guess if not.
    var category: SpendCategory {
        correctedCategory ?? SpendCategory.inferred(from: note)
    }

    var categoryWasCorrected: Bool { correctedCategory != nil }

    /// Whether the add-expense sheet can put this line back on screen without
    /// changing it.
    ///
    /// Two exclusions, both about not quietly rewriting something:
    ///
    /// - A `.transfer` is a settlement artefact. Its id is the proposal's id —
    ///   that is what makes both phones converge on one ledger line — and its
    ///   amount is what the two of them agreed. Neither is this screen's to
    ///   alter; the way to undo a settlement is to raise another one.
    /// - The keypad is whole units only, so a fractional amount cannot be typed
    ///   back in. Opening one would silently round it, and a ledger that rounds
    ///   a number because you looked at it is worse than one you can't edit.
    var isEditable: Bool {
        kind == .spend && amount == amount.rounded()
    }

    /// The part of this line the non-payer owes back.
    var shareOwedByOther: Double {
        switch split {
        case .evenly: 0.5
        case .mineOnly: 0
        case .custom: min(max(customShare, 0), 1)
        }
    }

    /// Multiply by this line's value in the home currency to get how much it
    /// moves the balance. Positive means slot two ends up owing slot one.
    ///
    /// Rate-free: conversion needs today's rates, which live in `RatesService`,
    /// so the store does that half.
    var balanceFactor: Double {
        let direction: Double
        switch payer {
        case .one: direction = 1
        case .two: direction = -1
        case .both: direction = 0
        }
        // A payment between them settles debt one-for-one; a shared bill only
        // moves the non-payer's share of it.
        return kind == .transfer ? direction : direction * shareOwedByOther
    }

    // Written by hand so that ledgers saved before `kind` and `customShare`
    // existed still decode.
    init(id: UUID = UUID(), date: Date, amount: Double, currency: Currency,
         payer: Payer, split: Split, note: String, country: String,
         kind: ExpenseKind = .spend, customShare: Double = 0.5,
         correctedCategory: SpendCategory? = nil,
         updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.currency = currency
        self.payer = payer
        self.split = split
        self.note = note
        self.country = country
        self.kind = kind
        self.customShare = customShare
        self.correctedCategory = correctedCategory
        // A line written now beats one written before it, and seeded lines
        // default to when they were spent.
        self.updatedAt = updatedAt ?? date
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        amount = try container.decode(Double.self, forKey: .amount)
        currency = try container.decode(Currency.self, forKey: .currency)
        payer = try container.decode(Payer.self, forKey: .payer)
        split = try container.decode(Split.self, forKey: .split)
        note = try container.decode(String.self, forKey: .note)
        country = try container.decode(String.self, forKey: .country)
        kind = try container.decodeIfPresent(ExpenseKind.self, forKey: .kind) ?? .spend
        customShare = try container.decodeIfPresent(Double.self, forKey: .customShare) ?? 0.5
        correctedCategory = try container.decodeIfPresent(SpendCategory.self, forKey: .correctedCategory)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

extension Expense: SyncableRecord {}

// MARK: - Itinerary

/// Segments are held as trip-day offsets, not calendar dates, so that moving
/// the departure date moves the whole itinerary with it.
struct Segment: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// 1-based day the leg starts on.
    var startDay: Int
    /// 1-based day they leave — exclusive, so it's also the next leg's start.
    var endDay: Int

    var nights: Int { max(endDay - startDay, 0) }
    func contains(day: Int) -> Bool { day >= startDay && day < endDay }

    /// The places this stop names.
    ///
    /// A title is one stop and may name two places — "Ayutthaya · Pai" is one
    /// leg of the plan holding two waypoints — so the split is part of what a
    /// segment *is*, not something each caller works out.
    ///
    /// It was written out in nine places and only one of them trimmed, which
    /// meant a title typed with irregular spacing around the separator resolved
    /// in the app and not in the book: the same shape as the seven copies of
    /// the waypoint join that `segment(for:)` exists to end. The join was
    /// consolidated; the split wasn't. Blanks are dropped, so a stop nobody
    /// named answers `[]` rather than `[""]` — which is what lets the callers
    /// below have a real fallback instead of a dead one.
    var places: [String] { Segment.places(in: title) }

    /// The same split, for a title that has no segment yet.
    ///
    /// The stamp fields are offered while a new stop is still being typed, so
    /// the places have to be readable off a bare string — and there is exactly
    /// one splitter, which is the whole point of the property above.
    static func places(in title: String) -> [String] {
        title.components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The one the headlines use. A stop naming two places is titled with the
    /// one they arrive in first.
    var primaryPlace: String { places.first ?? title }

    /// Whether this stop names a city. Whole names only — a substring match
    /// would let "Ha Long" claim "Ha Long Bay".
    func names(city: String) -> Bool { places.contains(city) }
}

struct Leg: Identifiable, Codable, Hashable {
    var id = UUID()
    var country: String
    var currency: Currency
    var segments: [Segment]

    var nights: Int { segments.reduce(0) { $0 + $1.nights } }
    var startDay: Int { segments.map(\.startDay).min() ?? 1 }
    var endDay: Int { segments.map(\.endDay).max() ?? 1 }
    func contains(day: Int) -> Bool { day >= startDay && day < endDay }
}

extension Array {
    /// `move(fromOffsets:toOffset:)` without SwiftUI. The model layer stays
    /// Foundation-only so it can be built and checked for macOS.
    mutating func moveElements(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.sorted().compactMap { $0 < count ? self[$0] : nil }
        guard !moving.isEmpty else { return }
        let insertAt = destination - offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) where index < count { remove(at: index) }
        insert(contentsOf: moving, at: Swift.max(0, Swift.min(insertAt, count)))
    }
}

/// The whole itinerary, as one editable document.
///
/// Segments hold day offsets, but the *authority* is their order and their
/// length in nights. `reflow()` re-derives every `startDay`/`endDay` from that
/// order, so any edit — add, remove, reorder, resize — is one mutation plus a
/// reflow, and the days can never end up with a gap or an overlap.
struct ItineraryDocument: Codable, Hashable {
    var legs: [Leg]
    var updatedAt: Date = .distantPast

    init(legs: [Leg], updatedAt: Date = .distantPast) {
        self.legs = legs
        self.updatedAt = updatedAt
        reflow()
    }

    /// Last day the itinerary reaches. Day 1 with nothing planned is day 1.
    var lastDay: Int { legs.last?.endDay ?? 1 }
    var totalNights: Int { legs.reduce(0) { $0 + $1.nights } }
    var allSegments: [Segment] { legs.flatMap(\.segments) }

    mutating func reflow() {
        var cursor = 1
        for legIndex in legs.indices {
            for segmentIndex in legs[legIndex].segments.indices {
                let nights = max(legs[legIndex].segments[segmentIndex].nights, 1)
                legs[legIndex].segments[segmentIndex].startDay = cursor
                legs[legIndex].segments[segmentIndex].endDay = cursor + nights
                cursor += nights
            }
        }
    }

    private mutating func touched(_ now: Date) {
        reflow()
        updatedAt = now
    }

    // MARK: Editing

    mutating func setNights(_ nights: Int, forSegment id: UUID, now: Date = Date()) {
        guard let position = position(of: id) else { return }
        let clamped = max(1, min(nights, 365))
        legs[position.leg].segments[position.segment].endDay =
            legs[position.leg].segments[position.segment].startDay + clamped
        touched(now)
    }

    mutating func moveSegments(inLeg legID: UUID, from offsets: IndexSet, to destination: Int, now: Date = Date()) {
        guard let legIndex = legs.firstIndex(where: { $0.id == legID }) else { return }
        legs[legIndex].segments.moveElements(fromOffsets: offsets, toOffset: destination)
        touched(now)
    }

    mutating func removeSegment(_ id: UUID, now: Date = Date()) {
        guard let position = position(of: id) else { return }
        legs[position.leg].segments.remove(at: position.segment)
        // A country with nowhere left in it isn't a country you're visiting.
        if legs[position.leg].segments.isEmpty { legs.remove(at: position.leg) }
        touched(now)
    }

    /// Returns the stop it made, so a caller giving a new stop its stamp in the
    /// same breath has something to hang it off. Nil when the leg is gone.
    @discardableResult
    mutating func addSegment(title: String, nights: Int, toLeg legID: UUID, now: Date = Date()) -> Segment? {
        guard let legIndex = legs.firstIndex(where: { $0.id == legID }) else { return nil }
        let start = legs[legIndex].segments.last?.endDay ?? 1
        let segment = Segment(title: title, startDay: start, endDay: start + max(nights, 1))
        legs[legIndex].segments.append(segment)
        touched(now)
        // Read back rather than handing out the local copy: `touched` reflows,
        // so the days on that copy are the ones it had before the renumber.
        return allSegments.first { $0.id == segment.id }
    }

    /// Returns the first stop it made, for the same reason `addSegment` does.
    /// A country's first stop is a stop like any other and takes a stamp in the
    /// same breath — while this returned nothing, the sheet that makes it had no
    /// handle to hang one off, which is why the first stop of every leg was the
    /// one that couldn't be stamped where it was typed.
    @discardableResult
    mutating func addLeg(country: String, currency: Currency, firstStop: String, nights: Int, now: Date = Date()) -> Segment? {
        let start = lastDay
        let segment = Segment(title: firstStop, startDay: start, endDay: start + max(nights, 1))
        legs.append(Leg(country: country, currency: currency, segments: [segment]))
        touched(now)
        // Read back rather than handing out the local copy: `touched` reflows,
        // so the days on that copy are the ones it had before the renumber.
        return allSegments.first { $0.id == segment.id }
    }

    mutating func removeLeg(_ id: UUID, now: Date = Date()) {
        legs.removeAll { $0.id == id }
        touched(now)
    }

    /// A stop's title. Blank is refused: `Segment.places` would answer `[]`.
    mutating func renameSegment(_ id: UUID, title: String, now: Date = Date()) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let position = position(of: id) else { return }
        legs[position.leg].segments[position.segment].title = trimmed
        touched(now)
    }

    mutating func renameLeg(_ id: UUID, country: String, now: Date = Date()) {
        let trimmed = country.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = legs.firstIndex(where: { $0.id == id }) else { return }
        legs[index].country = trimmed
        touched(now)
    }

    mutating func setCurrency(_ currency: Currency, forLeg id: UUID, now: Date = Date()) {
        guard let index = legs.firstIndex(where: { $0.id == id }) else { return }
        legs[index].currency = currency
        touched(now)
    }

    mutating func moveLegs(from offsets: IndexSet, to destination: Int, now: Date = Date()) {
        legs.moveElements(fromOffsets: offsets, toOffset: destination)
        touched(now)
    }

    private func position(of segmentID: UUID) -> (leg: Int, segment: Int)? {
        for (legIndex, leg) in legs.enumerated() {
            if let segmentIndex = leg.segments.firstIndex(where: { $0.id == segmentID }) {
                return (legIndex, segmentIndex)
            }
        }
        return nil
    }
}

struct PlanItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var time: String
    var title: String
    var note: String

    /// Minutes past midnight, for the times people actually type: "07:30",
    /// "7:30", "19.00", "7am", "7:30 pm". Nil for "after dark", which is a
    /// time too, just not one that sorts.
    var minutes: Int? {
        var text = time.trimmingCharacters(in: .whitespaces).lowercased()
        var meridiem: String?
        for suffix in ["am", "pm", "a.m.", "p.m."] where text.hasSuffix(suffix) {
            meridiem = String(suffix.prefix(1))
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let parts = text.split(omittingEmptySubsequences: false,
                               whereSeparator: { $0 == ":" || $0 == "." || $0 == "h" })
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy { $0.isNumber } }),
              var hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) ?? -1 : 0
        guard (0...59).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "p" ? 12 : 0)
        }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }
}

/// One day of the trip, as the two of them wrote it.
///
/// The merge unit is the day rather than the hour: `PlanItem` stays a plain
/// value and travels inside its day, so reordering breakfast and the temple is
/// one edit with one timestamp instead of a race between two.
///
/// It joins on the stop it was written in and how many days into that stop,
/// not on `dayNumber`. `ItineraryDocument.reflow()` renumbers every day on any
/// itinerary edit, so a plan keyed by day number stayed on day 20 while Chiang
/// Mai was dragged away from under it, and read as Chiang Rai's. Keyed by stop,
/// it goes where the stop goes. Read through `TripStore.planKey(forDay:)`.
///
/// `segmentID == nil` means keyed by `dayNumber` after all: a day no stop
/// covers, and a plan saved before the stop keys existed until
/// `backfillPlanKeys()` attaches it. `dayNumber` is still written, for a
/// payload from the older build.
///
/// `city` is what the day was written *about*; the screens prefer the segment.
struct DayPlan: Identifiable, Codable, Hashable {
    var id = UUID()
    var dayNumber: Int
    /// The stop the day belongs to.
    var segmentID: UUID?
    /// How far into that stop, from 0. A stop shortened past it sets the plan
    /// aside rather than deleting it, and lengthening it brings the plan back.
    var dayOfStop: Int?
    var city: String
    var occasion: String?
    var blurb: String
    var items: [PlanItem]
    var lodgingTitle: String?
    var lodgingNote: String?
    var updatedAt: Date = .distantPast
    /// Clearing a day tombstones it rather than removing it, so the clear can
    /// beat a concurrent edit on the other phone. Same mechanism as `Expense`.
    var deletedAt: Date?

    init(id: UUID = UUID(), dayNumber: Int, segmentID: UUID? = nil, dayOfStop: Int? = nil,
         city: String, occasion: String? = nil,
         blurb: String, items: [PlanItem], lodgingTitle: String? = nil,
         lodgingNote: String? = nil,
         updatedAt: Date = .distantPast, deletedAt: Date? = nil) {
        self.id = id
        self.dayNumber = dayNumber
        self.segmentID = segmentID
        self.dayOfStop = dayOfStop
        self.city = city
        self.occasion = occasion
        self.blurb = blurb
        self.items = items
        self.lodgingTitle = lodgingTitle
        self.lodgingNote = lodgingNote
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// The hours in the order the day happens: by time, with the ones that
    /// have no clock time after them in the order they were written. Derived,
    /// so the stored order — and with it the merge — is never touched.
    var orderedItems: [PlanItem] {
        items.enumerated()
            .sorted { ($0.element.minutes ?? Int.max, $0.offset) < ($1.element.minutes ?? Int.max, $1.offset) }
            .map(\.element)
    }

    /// Plans written before day plans could be edited carry no timestamp, so
    /// they lose to anything typed since — which is the right way round.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        dayNumber = try c.decodeIfPresent(Int.self, forKey: .dayNumber) ?? 1
        segmentID = try c.decodeIfPresent(UUID.self, forKey: .segmentID)
        dayOfStop = try c.decodeIfPresent(Int.self, forKey: .dayOfStop)
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        occasion = try c.decodeIfPresent(String.self, forKey: .occasion)
        blurb = try c.decodeIfPresent(String.self, forKey: .blurb) ?? ""
        items = try c.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
        lodgingTitle = try c.decodeIfPresent(String.self, forKey: .lodgingTitle)
        lodgingNote = try c.decodeIfPresent(String.self, forKey: .lodgingNote)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

extension DayPlan: SyncableRecord {}

// MARK: - Letters

enum LetterCondition: Codable, Hashable {
    case place(String)          // opens on arriving somewhere
    case day(Int)               // opens on a given trip day
    case stamp(String)          // opens with one named stamp, by code
    case finalStamp             // opens with the last stamp
    /// The only condition guaranteed to fire for a letter written after they
    /// have left: it opens the next time the letter reaches the phone.
    case nextOnline
    case hidden                 // the condition itself is withheld

    var summary: String {
        switch self {
        case .place(let name): "Opens in \(name)"
        case .day(let day): "Opens on day \(day)"
        case .stamp(let code): "Opens with the \(code) stamp"
        case .finalStamp: "Opens with the last stamp"
        case .nextOnline: "Opens the next time you're online"
        case .hidden: "Sealed"
        }
    }

    /// What the writing side calls it while the condition is being chosen.
    var kindLabel: String {
        switch self {
        case .place: "A place"
        case .day: "A day"
        case .stamp, .finalStamp: "A stamp"
        case .nextOnline: "Next time they're online"
        case .hidden: "Sealed"
        }
    }
}

struct Letter: Identifiable, Codable, Hashable {
    var id = UUID()
    var number: Int
    var title: String
    var writtenOn: Date
    var condition: LetterCondition
    /// Shown under the title in the sealed list — a hint, never the content.
    var hint: String
    var openedPlace: String?
    var openedOn: Date?
    var paragraphs: [String]
    var signature: String
    /// Set when the writer seals it. Nil means it is still a draft on the
    /// writing phone — a state the reading phone never observes, because
    /// drafts don't travel.
    var sealedAt: Date?
    /// When this phone first held the sealed letter. Distinct from `openedOn`,
    /// which belongs to the reader and never leaves the phone.
    var receivedAt: Date?
    /// The writer can withhold the condition as well as the contents. The
    /// reading side then shows "sealed" and a count, and nothing else.
    ///
    /// Separate from the condition rather than a case of it, because the letter
    /// still has to know when to open itself while the reader can't see when
    /// that is.
    var secretCondition: Bool = false

    /// Sealing is one-way: it is what makes the condition binding.
    var isSealed: Bool { sealedAt != nil }
    var isDraft: Bool { sealedAt == nil }
    var isOpen: Bool { openedOn != nil }
    var numberLabel: String { String(format: "%02d", number) }

    init(id: UUID = UUID(), number: Int, title: String, writtenOn: Date,
         condition: LetterCondition, hint: String, openedPlace: String? = nil,
         openedOn: Date? = nil, paragraphs: [String], signature: String,
         sealedAt: Date? = nil, receivedAt: Date? = nil, secretCondition: Bool = false) {
        self.id = id
        self.number = number
        self.title = title
        self.writtenOn = writtenOn
        self.condition = condition
        self.hint = hint
        self.openedPlace = openedPlace
        self.openedOn = openedOn
        self.paragraphs = paragraphs
        self.signature = signature
        // Passed through exactly. Nil means draft, which the writing side
        // depends on — defaulting it to `writtenOn` would seal every letter the
        // moment it was started.
        self.sealedAt = sealedAt
        self.receivedAt = receivedAt
        // "Hidden" and "the condition was withheld" are the same statement,
        // said once.
        self.secretCondition = secretCondition || condition == .hidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        writtenOn = try c.decode(Date.self, forKey: .writtenOn)
        condition = try c.decode(LetterCondition.self, forKey: .condition)
        hint = try c.decode(String.self, forKey: .hint)
        openedPlace = try c.decodeIfPresent(String.self, forKey: .openedPlace)
        openedOn = try c.decodeIfPresent(Date.self, forKey: .openedOn)
        paragraphs = try c.decode([String].self, forKey: .paragraphs)
        signature = try c.decode(String.self, forKey: .signature)
        sealedAt = try c.decodeIfPresent(Date.self, forKey: .sealedAt) ?? writtenOn
        receivedAt = try c.decodeIfPresent(Date.self, forKey: .receivedAt)
        secretCondition = try c.decodeIfPresent(Bool.self, forKey: .secretCondition)
            ?? (condition == .hidden)
    }
}

// MARK: - Trail

struct Stamp: Identifiable, Codable, Hashable {
    var id = UUID()
    var code: String            // BKK
    var city: String            // Bangkok
    var index: Int              // 1…11
    var earnedOn: Date?
    /// Copy shown on the full-screen moment when it is earned.
    var arrivalNote: String
    /// Letter number this stamp releases, if any.
    var unlocksLetter: Int?
    var latitude: Double = 0
    var longitude: Double = 0
    /// Which stop on the itinerary this waypoint belongs to.
    ///
    /// `nil` is legal and permanent: a trip saved before this field existed
    /// falls back to matching on the stop's name, and so does a waypoint whose
    /// stop was merged away. Everything reads it through
    /// `TripStore.segment(for:)`.
    var segmentID: UUID?
    var updatedAt: Date = .distantPast
    var deletedAt: Date?

    var earned: Bool { earnedOn != nil }
    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    /// Great-circle distance to another stamp, in kilometres.
    ///
    /// Plain arithmetic rather than CoreLocation, so the trail's headline figure
    /// can be checked on a machine with no location services — and so the model
    /// layer stays Foundation-only.
    func kilometres(to other: Stamp) -> Double {
        guard hasLocation, other.hasLocation else { return 0 }
        return Geo.kilometres(latitude, longitude, other.latitude, other.longitude)
    }

    init(id: UUID = UUID(), code: String, city: String, index: Int, earnedOn: Date? = nil,
         arrivalNote: String, unlocksLetter: Int? = nil,
         latitude: Double = 0, longitude: Double = 0, segmentID: UUID? = nil,
         updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.segmentID = segmentID
        self.id = id
        self.code = code
        self.city = city
        self.index = index
        self.earnedOn = earnedOn
        self.arrivalNote = arrivalNote
        self.unlocksLetter = unlocksLetter
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt ?? earnedOn ?? .distantPast
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        city = try c.decode(String.self, forKey: .city)
        index = try c.decode(Int.self, forKey: .index)
        earnedOn = try c.decodeIfPresent(Date.self, forKey: .earnedOn)
        arrivalNote = try c.decode(String.self, forKey: .arrivalNote)
        unlocksLetter = try c.decodeIfPresent(Int.self, forKey: .unlocksLetter)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        segmentID = try c.decodeIfPresent(UUID.self, forKey: .segmentID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? earnedOn ?? .distantPast
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

extension Stamp: SyncableRecord {}

// MARK: - Journal

struct JournalEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var dayNumber: Int
    var date: Date
    var city: String
    var line: String
    var tags: [String]
    /// True when a page has an image, whether or not it has loaded yet.
    var hasPhoto: Bool
    /// Filename of the copy kept in the app's own container. A reference to
    /// the photo library would break the moment they tidy their camera roll,
    /// and the book has to survive that.
    var photoID: String?
    var author: Traveller
    /// Up to two more photographs, optional. The page is still one photo and
    /// one line unless somebody asks for more; when they do, the book prints
    /// the three as a contact sheet on the left page.
    var extraPhotoIDs: [String] = []
    /// A few more lines, optional, printed under the line in body type.
    var note: String = ""

    /// The line's length, and the note's. The note's is the room the text page
    /// has under a full line, so a note at the limit fits and nothing past it
    /// can be typed — a page that clipped a sentence would be bound that way.
    static let lineLimit = 120
    static let noteLimit = 240
    static let extraPhotoLimit = 2

    /// Every photograph the page holds, the main one first.
    var allPhotoIDs: [String] { [photoID].compactMap { $0 } + extraPhotoIDs }

    init(id: UUID = UUID(), dayNumber: Int, date: Date, city: String, line: String,
         tags: [String], hasPhoto: Bool, photoID: String? = nil, author: Traveller,
         extraPhotoIDs: [String] = [], note: String = "") {
        self.id = id
        self.dayNumber = dayNumber
        self.date = date
        self.city = city
        self.line = line
        self.tags = tags
        self.hasPhoto = hasPhoto
        self.photoID = photoID
        self.author = author
        self.extraPhotoIDs = extraPhotoIDs
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        dayNumber = try c.decode(Int.self, forKey: .dayNumber)
        date = try c.decode(Date.self, forKey: .date)
        city = try c.decode(String.self, forKey: .city)
        line = try c.decode(String.self, forKey: .line)
        tags = try c.decode([String].self, forKey: .tags)
        hasPhoto = try c.decode(Bool.self, forKey: .hasPhoto)
        photoID = try c.decodeIfPresent(String.self, forKey: .photoID)
        author = try c.decode(Traveller.self, forKey: .author)
        // Both new, so both optional on the way in. Everything above is
        // `decode`, and a missing key there throws — which `TripSnapshot`
        // swallows and re-seeds over: every page of every trip saved before
        // these existed would be gone.
        extraPhotoIDs = try c.decodeIfPresent([String].self, forKey: .extraPhotoIDs) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

// MARK: - Moments

/// Something worth keeping that the itinerary never planned for.
///
/// Deliberately not a `Stamp`. A stamp is three things at once — a planned
/// waypoint with a position in the order, the key a letter is sealed to, and a
/// record that somebody stood somewhere. A moment is only the third, so it
/// earns nothing, opens nothing, moves no distance and never appears in the
/// `04 / 11` the trail counts. It is also the opposite of a stamp in the one
/// way that matters: a stamp cannot be undone, and a moment can be deleted,
/// which is what makes it safe to record on impulse.
///
/// **Never synced, and absent from `SyncPayload` by not being a field** — the
/// same promise the journal and the letters keep. Note what this type does not
/// have: `updatedAt` and `deletedAt`. Without them it cannot conform to
/// `SyncableRecord`, so it cannot be `merged(with:)`, so it cannot be unioned
/// into a payload by somebody tidying. The absence is the guarantee.
/// Great-circle distance, once. The trail's headline and the "180 km from
/// here" on Next stop are the same question, and two copies of a formula are
/// two answers waiting to disagree.
enum Geo {
    static func kilometres(_ fromLatitude: Double, _ fromLongitude: Double,
                           _ toLatitude: Double, _ toLongitude: Double) -> Double {
        let earthRadius = 6_371.0
        let φ1 = fromLatitude * .pi / 180, φ2 = toLatitude * .pi / 180
        let Δφ = (toLatitude - fromLatitude) * .pi / 180
        let Δλ = (toLongitude - fromLongitude) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2)
            + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// A run of moments kept in one place, for the full list.
///
/// Derived, so its `id` is borrowed from its first moment rather than minted:
/// anything minted inside a derived value has new identity on every pass,
/// which is the `BookSection.id` bug.
struct MomentGroup: Identifiable, Equatable {
    let id: UUID
    let place: String?
    let isBeforeDeparture: Bool
    /// Newest first.
    let moments: [Moment]

    /// "Chiang Mai · days 9–14", "Chiang Mai · day 9", "Before we left", or
    /// "Days 3–5" with nowhere to name. The separator belongs to the place.
    var heading: String {
        if isBeforeDeparture { return place.map { "Before we left · \($0)" } ?? "Before we left" }
        let days = moments.map(\.dayNumber)
        let first = days.min() ?? 0, last = days.max() ?? 0
        let span = first == last ? "day \(first)" : "days \(first)–\(last)"
        guard let place else { return span.prefix(1).uppercased() + span.dropFirst() }
        return "\(place) · \(span)"
    }
}

struct Moment: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Wall-clock time it was captured. Moved by `setStart`, like every other
    /// dated record.
    var capturedAt: Date
    /// The trip-relative fact, which `setStart` leaves alone — exactly the
    /// split `JournalEntry` makes between `date` and `dayNumber`.
    var dayNumber: Int
    /// Where the trip thought they were, for the book's caption. Not a claim
    /// about the coordinate, which may be missing.
    var city: String
    var note: String
    /// True when there is an image, whether or not it has loaded yet.
    var hasPhoto: Bool
    /// Filename in the app's own container, like a journal page's.
    var photoID: String?
    /// The phone's own fix at the time, when it had one. Zero means it didn't:
    /// a moment recorded with no position is still a moment, it just doesn't
    /// draw on the map.
    var latitude: Double = 0
    var longitude: Double = 0

    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    /// Kept in one tap — "just keep the spot" — and not written up yet.
    /// Derived, not stored: a stored flag is a field on `TripSnapshot` and a
    /// migration, and this is only ever a question about what is there.
    var isUnfinished: Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photoID == nil
    }

    /// Made before day 1 — at the airport, on the way there. `dayNumber` is
    /// the true offset for these, zero or below, rather than `TripStore`'s
    /// clamped one: clamped, a moment at Schiphol was "day 1 · Bangkok", a
    /// place they had not reached, printed in the book as if they had.
    /// Invariant under `setStart`, which moves `capturedAt` and leaves the
    /// day alone.
    var isBeforeDeparture: Bool { dayNumber < 1 }

    /// The city, when there is one worth printing. Empty means nobody could
    /// say — before departure, or on a trip with nowhere in it — and the
    /// em-dash is what a build that let the label leak into data wrote.
    var place: String? {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "—" ? nil : trimmed
    }

    /// Runs of consecutive moments in one place, newest run first and newest
    /// moment first inside it.
    ///
    /// Consecutive rather than by city: Bangkok on the way out and Bangkok on
    /// the way home are two stays, and one heading spanning days 1–58 would
    /// say they never left. Keyed on what the moment recorded, not on the
    /// itinerary as it stands — a moment is a record of where they were, like
    /// an expense, and dragging a stop doesn't change that.
    static func groupedByStop(_ moments: [Moment]) -> [MomentGroup] {
        var runs: [[Moment]] = []
        for moment in moments.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            if let last = runs.last?.last,
               last.isBeforeDeparture == moment.isBeforeDeparture,
               last.place?.lowercased() == moment.place?.lowercased() {
                runs[runs.count - 1].append(moment)
            } else {
                runs.append([moment])
            }
        }
        return runs.reversed().map { run in
            MomentGroup(id: run[0].id, place: run[0].place,
                        isBeforeDeparture: run[0].isBeforeDeparture,
                        moments: run.reversed())
        }
    }

    /// "day 12 · Chiang Mai", "day 3", or "before we left". The separator
    /// belongs to the place, so a moment with none draws no dangling " · ".
    var caption: String {
        let when = isBeforeDeparture ? "before we left" : "day \(dayNumber)"
        guard let place else { return when }
        return "\(when) · \(place)"
    }

    init(id: UUID = UUID(), capturedAt: Date, dayNumber: Int, city: String, note: String,
         hasPhoto: Bool = false, photoID: String? = nil,
         latitude: Double = 0, longitude: Double = 0) {
        self.id = id
        self.capturedAt = capturedAt
        self.dayNumber = dayNumber
        self.city = city
        self.note = note
        self.hasPhoto = hasPhoto
        self.photoID = photoID
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        dayNumber = try c.decodeIfPresent(Int.self, forKey: .dayNumber) ?? 1
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        hasPhoto = try c.decodeIfPresent(Bool.self, forKey: .hasPhoto) ?? false
        photoID = try c.decodeIfPresent(String.self, forKey: .photoID)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
    }
}

// MARK: - Papers

/// A passport, a visa, an insurance policy — the row on Papers, its typed
/// fields, and the id its encrypted scans are filed under in `ScanVault`.
///
/// **No `updatedAt`, and no `deletedAt`.** Not an oversight and not a thing to
/// tidy up for symmetry with `Expense` or `ShowCard`: `fields` holds passport
/// numbers, and without `updatedAt` this type cannot conform to
/// `SyncableRecord`, so it cannot be `merged(with:)`, so nobody can union it
/// into a `SyncPayload` without first writing the field themselves in the open.
/// The same trick as `Moment`, one collection over, and a check reflects over
/// this type to hold it.
///
/// The missing `deletedAt` is the second half of that. A tombstone exists so a
/// delete can beat a concurrent edit on another phone; there is no other phone
/// here, and a tombstoned row is a passport number still on disk under the word
/// "deleted". Deleting one is a real removal plus `ScanVault.deleteAll(for:)`.
struct TravelDocument: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var subtitle: String
    /// The short word on the row — "PASSPORT", "VISA". Typed, and a `String`
    /// rather than an enum on purpose: `decodeIfPresent` *throws* on an unknown
    /// raw value, `TripSnapshot` swallows that with `try?`, and the store
    /// re-seeds over somebody's trip. The same trap `Participant.writer`'s raw
    /// value is kept for.
    var badge: String
    var owner: Traveller?
    var fields: [DocumentField]
    var footnoteTitle: String?
    var footnoteBody: String?

    init(id: UUID = UUID(), title: String, subtitle: String = "", badge: String = "",
         owner: Traveller? = nil, fields: [DocumentField] = [],
         footnoteTitle: String? = nil, footnoteBody: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.owner = owner
        self.fields = fields
        self.footnoteTitle = footnoteTitle
        self.footnoteBody = footnoteBody
    }

    /// Field by field with defaults, like `Moment` and like `TripSnapshot`
    /// itself. The synthesized decode requires every key, and one missing key
    /// here throws out of `TripSnapshot`'s `decodeIfPresent([TravelDocument])`,
    /// which `TripSnapshot.decode` catches with `try?` — so the trip reads as
    /// unreadable and the store starts a fresh one over the top of it. A
    /// dropped field must cost a field, never the trip.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        badge = try c.decodeIfPresent(String.self, forKey: .badge) ?? ""
        owner = try c.decodeIfPresent(Traveller.self, forKey: .owner)
        fields = try c.decodeIfPresent([DocumentField].self, forKey: .fields) ?? []
        footnoteTitle = try c.decodeIfPresent(String.self, forKey: .footnoteTitle)
        footnoteBody = try c.decodeIfPresent(String.self, forKey: .footnoteBody)
    }

    /// The same row with everything private taken out of it.
    ///
    /// What `closeTrip()` writes into the snapshot it shelves. The labels stay
    /// and the values go, so a reopened trip still draws "Passport · Number ·
    /// Expires" and reads as emptied rather than as broken — the shelf's promise
    /// is that every screen reopens, and a row that vanished would break it
    /// quietly instead of saying what happened.
    func emptied() -> TravelDocument {
        var copy = self
        copy.fields = fields.map { DocumentField(id: $0.id, label: $0.label, value: "") }
        copy.footnoteBody = footnoteBody == nil ? nil : ""
        return copy
    }

    /// Whether anything on this row is still worth protecting.
    var holdsAnything: Bool {
        fields.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !(footnoteBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DocumentField: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var value: String

    init(id: UUID = UUID(), label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
}

/// A sentence to hand a stranger, in their language and in the holder's.
///
/// Both halves are typed by the people carrying the phone. The app holds no
/// translation service: it labels the field with the language of wherever they
/// are — see `CountryFacts.language` — and takes whatever they write. The
/// editor says as much, so a card is only ever as good as the person who
/// checked it.
struct ShowCard: Identifiable, Codable, Hashable {
    var id = UUID()
    var native: String
    var english: String
    var footerTitle: String?
    var footerBody: String?
    var footerNote: String?
    var shortName: String
    /// What order they are swiped through in.
    ///
    /// It has to be a stored field rather than the array's order, for the same
    /// reason `Stamp` carries one: the merge unions by id into a dictionary and
    /// hands back its values, so the order a card was appended in does not
    /// survive a sync. The cards are read by a stranger under pressure and the
    /// address is always first — that is not a thing to leave to a hash.
    var index: Int = 0
    var updatedAt: Date = .distantPast
    var deletedAt: Date?

    init(id: UUID = UUID(), native: String, english: String,
         footerTitle: String? = nil, footerBody: String? = nil, footerNote: String? = nil,
         shortName: String, index: Int = 0,
         updatedAt: Date = .distantPast, deletedAt: Date? = nil) {
        self.id = id
        self.native = native
        self.english = english
        self.footerTitle = footerTitle
        self.footerBody = footerBody
        self.footerNote = footerNote
        self.shortName = shortName
        self.index = index
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        native = try c.decodeIfPresent(String.self, forKey: .native) ?? ""
        english = try c.decodeIfPresent(String.self, forKey: .english) ?? ""
        footerTitle = try c.decodeIfPresent(String.self, forKey: .footerTitle)
        footerBody = try c.decodeIfPresent(String.self, forKey: .footerBody)
        footerNote = try c.decodeIfPresent(String.self, forKey: .footerNote)
        shortName = try c.decodeIfPresent(String.self, forKey: .shortName) ?? ""
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

extension ShowCard: SyncableRecord {}

// MARK: - Sharing

struct SharingRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var state: String
    var isShared: Bool
}

/// One line of "what actually travels", worked out rather than written down.
///
/// `SharingRule` is the stored version and it is sample data: `SampleTrip` fills
/// it in, `SampleTrip` is commented out, and every trip made through onboarding
/// therefore carries an empty array — so the screen that exists to say what the
/// other phone can see listed nothing at all on every real trip. Nobody noticed
/// because the one trip anybody looked at came packed.
///
/// So this is derived, which is the rule the rest of the app already follows:
/// everything on screen is computed or deleted. The stored property stays where
/// it is for decoding's sake and nothing reads it.
///
/// `fields` is what makes the claim checkable. Each line names the `SyncPayload`
/// properties it is talking about, and a check asserts that a line saying
/// "shared" names only fields the payload actually has, and a line saying
/// otherwise names none of them. The alternative is a screen that promises the
/// journal stays private because somebody typed that it does.
struct SharingLine: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var detail: String
    var state: String
    var isShared: Bool
    /// The `SyncPayload` fields this line describes. Empty for a line about
    /// something the payload has no field for at all — which is itself the
    /// point being made.
    var fields: [String]
}

// MARK: - Meeting point

struct MeetingPoint: Codable, Hashable {
    var place: String
    var detail: String
    var localScript: String
    var setAt: Date
    var latitude: Double = 0
    var longitude: Double = 0

    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    init(place: String, detail: String, localScript: String, setAt: Date,
         latitude: Double = 0, longitude: Double = 0) {
        self.place = place
        self.detail = detail
        self.localScript = localScript
        self.setAt = setAt
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        place = try c.decode(String.self, forKey: .place)
        detail = try c.decode(String.self, forKey: .detail)
        localScript = try c.decode(String.self, forKey: .localScript)
        setAt = try c.decode(Date.self, forKey: .setAt)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
    }

    /// What makes two entries the same place.
    ///
    /// A meeting point has no id and must not grow one: the thing being
    /// identified is a gate somebody can walk to, and two phones that both
    /// typed "the bridge" mean the same bridge. Ids minted per phone would put
    /// it in the list twice; a fresh id per decode would put it there again
    /// every launch. `place` is the identity the picker has always drawn and
    /// deduped with — folded for case and spacing so re-typing "The Bridge"
    /// updates the entry rather than adding a second one.
    var placeKey: String {
        place.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether anybody has actually agreed one.
    ///
    /// A blank trip carries `MeetingPoint(place: "", detail: "", localScript: "",
    /// setAt: .distantPast)` — a real value that is not a real answer. Three
    /// screens drew it as though it were: Papers rendered ". Agreed at 00:53."
    /// (a bare full stop where the place should be, and `.distantPast` formatted
    /// as a time somebody chose), and Separated — the 2am screen — said "Go to
    /// the" over an empty card captioned "show this to a driver".
    ///
    /// `TodayView` was asking this correctly the whole time and keeping the
    /// answer to itself as `hasMeetingPoint`. It lives here now, so there is one
    /// question and not three views' worth of guesses about it.
    ///
    /// Keyed on `placeKey`, not on `setAt`: the place is what a person walks to,
    /// and it is already the identity this type is deduped and merged by.
    var isSet: Bool { !placeKey.isEmpty }
}

extension Array where Element == MeetingPoint {

    /// Union by place, latest `setAt` winning, most recent first.
    ///
    /// This is what a *history* is, so it is the merge on both seams: one
    /// phone remembering what it just typed, and two phones remembering each
    /// other's. Blank places are dropped rather than stored — a trip that has
    /// never met anywhere carries an empty meeting point, and an entry with no
    /// name is a row nobody can read.
    ///
    /// Ties go to the receiver, which only decides between two writes of the
    /// same place at the same instant, and decides it the same way on both
    /// phones however the rounds interleave.
    func remembering(_ others: [MeetingPoint]) -> [MeetingPoint] {
        var byPlace: [String: MeetingPoint] = [:]
        for point in self + others where !point.placeKey.isEmpty {
            if let held = byPlace[point.placeKey], held.setAt >= point.setAt { continue }
            byPlace[point.placeKey] = point
        }
        // Sorted rather than appended, because the order is the answer to
        // "where did we meet last" and a merge arrives out of order.
        return byPlace.values.sorted {
            $0.setAt == $1.setAt ? $0.place < $1.place : $0.setAt > $1.setAt
        }
    }

    func remembering(_ point: MeetingPoint) -> [MeetingPoint] { remembering([point]) }
}

// MARK: - Where the trip is up to

enum TripPhase: Equatable {
    case before(daysUntil: Int)
    case during
    case after(daysSince: Int)

    var isBefore: Bool { if case .before = self { true } else { false } }
    var isAfter: Bool { if case .after = self { true } else { false } }
}

// MARK: - Calendar

extension Calendar {
    /// One calendar for the whole app, so a day number never depends on which
    /// screen asked. Uses the device's own zone — the dates are the user's.
    static let trip: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    func days(from: Date, to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to)).day ?? 0
    }
}

extension Date {
    /// One formatter per format string. There are nine of them in the app and
    /// they are read once per row of every dated list, so building one per call
    /// put a `DateFormatter` allocation inside the scroll.
    private static let formatters = FormatterBox<String, DateFormatter> { format in
        let formatter = DateFormatter()
        formatter.calendar = Calendar.trip
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = format
        return formatter
    }

    func text(_ format: String) -> String {
        Date.formatters.formatter(for: format).string(from: self)
    }

    /// "13 April"
    var dayMonth: String { text("d MMMM") }
    /// "13 Apr"
    var shortDayMonth: String { text("d MMM") }
    /// "13 Apr 2027"
    var shortDate: String { text("d MMM yyyy") }
    /// "Tuesday,\n13 April"
    var weekdayAndDate: String { text("EEEE,'\n'd MMMM") }
    /// "04 APR"
    var stampDate: String { text("dd MMM").uppercased() }
}
