import Foundation

// MARK: - Who is holding the phone

/// Three ways to be on a trip: either of the two travellers, or the observer —
/// whoever stays home, watches the trail and writes the letters.
///
/// Separate from `Traveller`. A `Traveller` is somebody the ledger can owe
/// money to and the book can be written by; the observer is neither, and the
/// type saying so is what keeps home mode from growing a journal or a share of
/// the bill.
///
/// The raw values are persisted. `decodeIfPresent` throws on a present but
/// unknown raw value and `TripSnapshot` swallows that with `try?`, so renaming
/// a case loses the saved trip rather than one field.
enum Participant: String, Codable, CaseIterable, Identifiable {
    case one, two, writer
    var id: String { rawValue }

    var traveller: Traveller? {
        switch self {
        case .one: .one
        case .two: .two
        case .writer: nil
        }
    }

    var isObserver: Bool { self == .writer }

    /// What this slot is called before anybody has named it. The travellers get
    /// their real names from `TripNames`; the observer's is local.
    var genericName: String {
        switch self {
        case .one: TripNames.fallback(.one)
        case .two: TripNames.fallback(.two)
        case .writer: "Observer"
        }
    }

    var subtitle: String {
        switch self {
        case .one, .two: "goes, and writes a book"
        case .writer: "stays home · letters only"
        }
    }

    var tag: String { isObserver ? "observer" : "traveller" }

    init(_ traveller: Traveller) {
        self = traveller == .one ? .one : .two
    }
}

// MARK: - Where a trip came from

/// Whether somebody filled this trip in before handing the phone over, or
/// whether it started empty.
///
/// Stored rather than inferred. The obvious test — "does it have an itinerary
/// yet" — changes its answer *during* the flow it gates: the blank branch hands
/// off to the itinerary editor, and one added country would make a re-entered
/// onboarding show a manifest of what nobody filled in.
enum TripOrigin: String, Codable {
    /// Arrived with an itinerary and letters already inside, so onboarding
    /// confirms the dates rather than asking for them.
    case packed
    /// Nothing inside. Dates, budget and countries are genuinely unanswered.
    case blank
}

// MARK: - What a trip bothers with

/// K6 · the switches a trip is created with. Everything here is a thing the app
/// can be asked to stop doing entirely, rather than a preference that only
/// changes wording.
struct TripFeatures: Codable, Hashable {
    var letters: Bool
    var nightlyPage: Bool
    var stamps: Bool
    var printedBooks: Bool
    var sharedLedger: Bool
    /// How many physical volumes the book prints as. Three months of pages in
    /// one binding won't lie flat.
    var volumes: Int

    static let everything = TripFeatures(letters: true, nightlyPage: true, stamps: true,
                                         printedBooks: true, sharedLedger: true, volumes: 1)

    /// Rows for K6, in the order the design lists them.
    var rows: [(title: String, on: Bool)] {
        [("Letters", letters), ("Nightly page", nightlyPage), ("Stamps", stamps),
         ("Printed books", printedBooks), ("Shared ledger", sharedLedger)]
    }
}

/// K2 · five templates. Each one only presets the prompt rhythm, the book shape
/// and whether letters exist — nothing it sets is unchangeable afterwards.
enum TripTemplate: String, Codable, CaseIterable, Identifiable {
    case someonesLeaving, twoWeeksWarm, oneCitySlowly, longHaul, justTheMoney
    var id: String { rawValue }

    var title: String {
        switch self {
        case .someonesLeaving: "Someone's leaving"
        case .twoWeeksWarm: "Two weeks somewhere warm"
        case .oneCitySlowly: "One city, slowly"
        case .longHaul: "Long haul"
        case .justTheMoney: "Just the money"
        }
    }

    var badge: String {
        switch self {
        case .someonesLeaving: "letters on"
        case .twoWeeksWarm: "no letters"
        case .oneCitySlowly: "no stamps"
        case .longHaul: "volumes"
        case .justTheMoney: "no book"
        }
    }

    var blurb: String {
        switch self {
        case .someonesLeaving:
            "One month or longer, two people, letters from home, printed books at the end."
        case .twoWeeksWarm:
            "Money split matters, journal is optional, one thin book at the end."
        case .oneCitySlowly:
            "A month in one place. Stamps make no sense; the prompt asks about people instead."
        case .longHaul:
            "Three months or more. Prints as two volumes so one book isn't 400 pages."
        case .justTheMoney:
            "A work trip or a weekend. Split, papers, done. Nothing prints."
        }
    }

    var features: TripFeatures {
        switch self {
        case .someonesLeaving:
            TripFeatures(letters: true, nightlyPage: true, stamps: true,
                         printedBooks: true, sharedLedger: true, volumes: 1)
        case .twoWeeksWarm:
            TripFeatures(letters: false, nightlyPage: true, stamps: true,
                         printedBooks: true, sharedLedger: true, volumes: 1)
        case .oneCitySlowly:
            TripFeatures(letters: false, nightlyPage: true, stamps: false,
                         printedBooks: true, sharedLedger: true, volumes: 1)
        case .longHaul:
            TripFeatures(letters: true, nightlyPage: true, stamps: true,
                         printedBooks: true, sharedLedger: true, volumes: 2)
        case .justTheMoney:
            TripFeatures(letters: false, nightlyPage: false, stamps: false,
                         printedBooks: false, sharedLedger: true, volumes: 0)
        }
    }

    /// A starting length, in days, so the date step opens on something sensible.
    var suggestedDays: Int {
        switch self {
        case .someonesLeaving: 61
        case .twoWeeksWarm: 14
        case .oneCitySlowly: 30
        case .longHaul: 120
        case .justTheMoney: 4
        }
    }

    /// The nightly prompt is the same three taps everywhere; only what it asks
    /// about changes, and only because the trip shape changed.
    var promptSubject: String {
        switch self {
        case .oneCitySlowly: "Who did you talk to?"
        default: "One photo, one line."
        }
    }

    /// K1's rule, applied at creation: a trip long enough to be lonely gets
    /// letters offered; a weekend doesn't.
    static func suggested(forDays days: Int) -> TripTemplate {
        switch days {
        case ..<7: .justTheMoney
        case ..<21: .twoWeeksWarm
        case ..<90: .someonesLeaving
        default: .longHaul
        }
    }
}

// MARK: - Where a trip is in its life

enum TripStatus: String, Codable {
    /// The one trip that syncs, notifies and drops pins. There is never a
    /// second one.
    case live
    /// On the shelf and read-only. Its trail, its book, its letters and its
    /// ledger reopen from the frozen snapshot; the screens that were about
    /// *running* a trip — today, the papers — do not, because they were about a
    /// day that has already happened.
    ///
    /// The trail used to be on the other side of that line, which was the wrong
    /// side: a finished trail is not a control for running a trip, it is the
    /// record of where they went, and it is the first thing anybody reopens a
    /// closed trip to look at. The one thing on it that *was* about running —
    /// handing out a stamp — is already behind `\.isReadOnly`, which is why
    /// moving it cost a row rather than a screen.
    case archived
    /// Sketched ahead on this phone, not started: a name, dates, the money
    /// and an itinerary. Kept in its own file (`TripLibrary.planKey`), so no
    /// shelf ever holds one, and it never syncs — the other phone meets it
    /// when it goes live and the invite step pairs them.
    case planned
}
