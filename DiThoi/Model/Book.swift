import Foundation

// MARK: - The physical object

/// 8.5 × 8.5 inches, square. That is Lulu's square photo book, and the size
/// matters more than it looks: this used to be 8 × 8 under a comment saying
/// "Blurb and Lulu both stock it", and neither does — Blurb's squares are 7 and
/// 12 inches, Lulu's is 8.5. A file at a trim nobody prints is a file a print
/// service refuses, or worse, scales.
///
/// A square page is still the one shape a phone photo never crops badly into
/// whichever way it was held.
struct BookSpec: Equatable {
    var trimInches: Double = 8.5
    var bleedInches: Double = 0.125
    /// What a photograph is saved at, so it can print this sharp.
    var dpi: Int = 300
    /// What it has to fall below before the print screen says anything.
    ///
    /// Separate from `dpi` on purpose. 300 is what the app *aims* for; a
    /// photograph at 283 prints indistinguishably from one at 300, and a
    /// warning that fires on photographs nobody could tell apart is the "every
    /// page will print soft" warning this screen once gave about every page —
    /// always true, so it carried no information. Below 250 a print does
    /// soften, and that is worth a sentence.
    var softBelowDPI: Int = 250
    /// The fewest pages a print service binds. Lulu's square book starts at
    /// 20 and a casewrap at 24, so 24 satisfies both; the book pads up to it
    /// with notes pages rather than being refused.
    var minimumPages: Int = 24
    /// What the file actually is. This said "PDF/X-3 · CMYK" while the writer
    /// produced neither — an RGB file of flattened pictures.
    var format = "PDF · sRGB"

    /// Pixels a full-bleed photo needs to hit the stated dpi.
    var fullBleedPixels: Int { Int(((trimInches + bleedInches * 2) * Double(dpi)).rounded()) }

    /// What a square of this many pixels prints at, and whether that is under
    /// the spec.
    ///
    /// One arithmetic, three callers: the crop screen asks it about the square
    /// being chosen, `PhotoCrop` asks it on the way past, and
    /// `PhotoMeasurement` asks it about a photograph already on disk. Held here
    /// rather than copied into the crop screen so the warning on the way in and
    /// the warning on the print screen cannot disagree — the same reason
    /// `PhotoStore.printLongEdge` reads `fullBleedPixels` rather than 2048.
    ///
    /// Named apart from the `dpi` property on purpose: one shared label is what
    /// makes a call site ambiguous.
    func printedDPI(forSquare pixels: Int) -> Int {
        Int((Double(pixels) / (trimInches + bleedInches * 2)).rounded())
    }

    func isSoft(square pixels: Int) -> Bool { printedDPI(forSquare: pixels) < softBelowDPI }

    /// Points, at 72 per inch, which is what a PDF context works in.
    var trimPoints: Double { trimInches * 72 }
    var bleedPoints: Double { bleedInches * 72 }
    var mediaPoints: Double { (trimInches + bleedInches * 2) * 72 }

    var trimLabel: String {
        let side = Formatting.decimal(trimInches, places: trimInches.rounded() == trimInches ? 0 : 1)
        return "\(side) × \(side) in · square"
    }
    var bleedLabel: String { "\(Formatting.decimal(bleedInches, places: 3)) in all sides" }

    /// How much the trim artwork is enlarged so it runs off every cut edge.
    ///
    /// One number for both axes. Scaling them separately — 1.0156 against
    /// 1.0313 — makes every printed page 1.5% taller than wide, type included:
    /// invisible on a screen, permanent in a bound book. Kept here rather than
    /// in the renderer so it can be checked without a PDF context.
    var bleedScale: Double { mediaPoints / trimPoints }
}

// MARK: - What is on each spread

/// A spread is two facing pages, and it is the unit the book is actually
/// designed in — a photo on the left, the writing on the right.
///
/// **Facing pages are an even page and the odd one after it.** Page 1 of a
/// bound book is a right-hand page on its own, with the inside of the cover
/// opposite; the first true spread is pages 2 and 3. The book used to number
/// spreads (1, 2), (3, 4)… which is how a PDF viewer shows them and not how
/// paper folds: every day's photograph printed on a right-hand page and its
/// line on the *back of the same leaf*, so the two were never seen together.
/// `.opening` and `.closing` are the half-spreads that make the arithmetic
/// true: the left of the first and the right of the last are the insides of
/// the covers and never print.
///
/// Page numbers are derived from the order, never stored, so inserting a day
/// can't leave a stale number behind.
enum BookSpread: Identifiable, Hashable {
    /// Inside the front cover, unprinted · page 1, the half-title.
    case opening
    case title
    /// The contents, after the title spread and before anything else, and
    /// printed — the preview had always listed the sections while the bound
    /// book had no page saying where anything was. Paginated like the stamps:
    /// a page that has no rows left on it is ruled for notes. Each volume
    /// carries its own, numbered to its own pages.
    case contents(page: Int)
    /// `ordinal` counts distinct countries in the order they were first
    /// entered, and `visit` counts the times this one has been entered so far
    /// — Thailand → Laos → Thailand is ordinal 1, visit 2 on the way back.
    ///
    /// `moments` is a short group the opener carries itself — see
    /// `openerCarries` — rather than a spread of its own. Empty almost always.
    case countryOpener(legID: UUID, country: String, nights: Int, stampCount: Int,
                       fromDay: Int, toDay: Int, ordinal: Int, visit: Int, moments: [UUID])
    case day(entryID: UUID)
    /// The earned stamps, paginated: there is no number of them a trip is
    /// allowed to have, and one fixed grid silently clipped everything past
    /// the twentieth — the moments bug, one section over.
    case stamps(page: Int)
    /// Every place they agreed to meet, in the order they last agreed it —
    /// the list the meeting-point picker keeps and nothing printed. The first
    /// spread spends its left page on the heading, like the stamps.
    case meetingPlaces(page: Int)
    /// What happened along the way, printed at the end of the country it
    /// happened in — after that country's last night, inside its section.
    ///
    /// They used to be one section at the back of the book, so "the dog that
    /// followed us the whole way up" printed a hundred pages after the day it
    /// was about. `group` is the leg's id (or `before` / `elsewhere`), and the
    /// spread carries exactly which moments each page draws, cut by
    /// `momentPages` — so what the plan counted and what the page prints
    /// cannot disagree. An empty `right` is the ruled notes page.
    case moments(group: String, heading: String, page: Int, left: [UUID], right: [UUID])
    /// The whole trip, at the very end: what it added up to, and the trail.
    case wholeTrip
    /// Notes pages, so a short book reaches the fewest pages a printer binds.
    case notes(index: Int)
    /// The colophon · inside the back cover, unprinted.
    case closing

    var id: String {
        switch self {
        case .opening: "opening"
        case .title: "title"
        case .contents(let page): "contents-\(page)"
        case .countryOpener(let legID, _, _, _, _, _, _, _, _): "leg-\(legID)"
        case .day(let entryID): "day-\(entryID)"
        case .stamps(let page): "stamps-\(page)"
        case .meetingPlaces(let page): "meeting-\(page)"
        case .moments(let group, _, let page, _, _): "moments-\(group)-\(page)"
        case .wholeTrip: "whole-trip"
        case .notes(let index): "notes-\(index)"
        case .closing: "closing"
        }
    }

    /// Whether each half is a real page. The two that aren't are the insides
    /// of the covers.
    var printsLeft: Bool { self != .opening }
    var printsRight: Bool { self != .closing }
}

/// One country's worth of the contents list.
struct BookSection: Identifiable, Hashable {
    var title: String
    var firstPage: Int
    var lastPage: Int
    /// The title spread and the contents themselves: listed in the app's
    /// contents, left off the printed one, which is on those pages.
    var isFrontMatter = false
    var pageRange: String { firstPage == lastPage ? "\(firstPage)" : "\(firstPage)–\(lastPage)" }

    /// A section *is* where it starts and what it is called.
    ///
    /// This was a stored `UUID`, minted fresh inside `BookPlan.build` — and the
    /// plan is derived, rebuilt on every read. So the contents list had brand-new
    /// identity on every pass: nothing diffed, nothing animated, and comparing a
    /// section against one from a moment ago was always false. Exactly the reason
    /// `LetterSchedule.Silence.id` is its span rather than a UUID.
    var id: String { "\(firstPage)-\(title)" }
}

/// The whole book, laid out.
///
/// Everything here is derived from the journal, the itinerary and the stamps.
/// Nothing is stored, so the book cannot disagree with the app it was made
/// from.
struct BookPlan: Equatable {
    var spec: BookSpec
    var spreads: [BookSpread]
    /// The whole book's sections, front matter included — what the app's
    /// contents list jumps between.
    var sections: [BookSection]
    var volumes: Int
    /// The same book cut into `volumes` printable files. Each one opens and
    /// closes like a book of its own — half-title, title, contents, colophon —
    /// and is padded to the printer's minimum on its own account. With one
    /// volume it is `[spreads]`.
    ///
    /// Real spreads, not arithmetic. `pagesPerVolume` used to be computed from
    /// counters while the export wrote one file whatever the count, so the
    /// preview promised two books and the printer got one.
    var volumeSpreads: [[BookSpread]]
    /// Each volume's sections, numbered to its own pages — what its printed
    /// contents says. The writer numbers each file from page 1, so the whole
    /// book's numbers would be wrong in every volume after the first.
    var volumeSections: [[BookSection]]
    /// The nights with no page before each written one, by entry id: the gap
    /// between the previous page (or day 1) and this one. Days after the last
    /// page are not here — on a live trip those are the future, not a gap.
    var missedBefore: [UUID: ClosedRange<Int>]

    /// Days between day 1 and the last page that have no page at all.
    /// Derived from `missedBefore`, so the line on the page and the count on
    /// the preview are one number.
    var skippedDays: Int { missedBefore.values.reduce(0) { $0 + $1.count } }

    /// Printed pages. Every spread is two pages except the insides of the
    /// covers, which are half of the first and half of the last.
    var pageCount: Int { Self.pageCount(spreads) }

    static func pageCount(_ spreads: [BookSpread]) -> Int { max(spreads.count * 2 - 2, 0) }

    /// The page number of the left-hand page of the spread at this position.
    /// The opening's left is the inside of the cover, which is page 0 — never
    /// drawn, never numbered.
    static func leftPage(ofSpreadAt index: Int) -> Int { index * 2 }

    var pagesPerVolume: [Int] { volumeSpreads.map(Self.pageCount) }

    /// The first printed page of a spread, by id.
    func firstPage(ofSpread id: String) -> Int? {
        guard let index = spreads.firstIndex(where: { $0.id == id }) else { return nil }
        return index == 0 ? 1 : Self.leftPage(ofSpreadAt: index)
    }

    var hasStampsSpread: Bool { stampSpreadCount > 0 }

    /// Counted, not inferred.
    ///
    /// Subtracting the other kinds from the total — "anything that isn't a day,
    /// the title or the stamps is an opener" — is true until a fifth kind of
    /// spread exists, and then it fails silently: the new kind counts as an
    /// opener, lands in volume one, and every total still adds up.
    var countryOpenerCount: Int {
        spreads.reduce(0) { count, spread in
            if case .countryOpener = spread { return count + 1 }
            return count
        }
    }

    var contentsSpreadCount: Int {
        spreads.reduce(0) { count, spread in
            if case .contents = spread { return count + 1 }
            return count
        }
    }

    var stampSpreadCount: Int {
        spreads.reduce(0) { count, spread in
            if case .stamps = spread { return count + 1 }
            return count
        }
    }

    var meetingSpreadCount: Int {
        spreads.reduce(0) { count, spread in
            if case .meetingPlaces = spread { return count + 1 }
            return count
        }
    }

    /// Every moments spread, wherever its country put it.
    var momentSpreadCount: Int {
        spreads.reduce(0) { count, spread in
            if case .moments = spread { return count + 1 }
            return count
        }
    }

    var wholeTripSpreadCount: Int { spreads.contains(.wholeTrip) ? 1 : 0 }

    var notesSpreadCount: Int {
        spreads.reduce(0) { count, spread in
            if case .notes = spread { return count + 1 }
            return count
        }
    }

    /// Six to a spread, three to a page — when none of them has a
    /// photograph. A page holds `momentPageCapacity`; a moment in words costs
    /// two of it and a moment with a photograph three, so a page is three in
    /// words, or two photographs large enough to look at, or one of each.
    /// They used to be three to a page whatever they held, which made every
    /// photograph a 74-point thumbnail.
    static let momentsPerSpread = 6
    static let momentPageCapacity = 6

    static func momentWeight(hasPhoto: Bool) -> Int { hasPhoto ? 3 : 2 }

    /// The moments, in order, cut into pages. Every moment is on exactly one
    /// page and the order is never changed: this is the one function every
    /// moments spread is cut by.
    static func momentPages(photoFlags: [Bool]) -> [Range<Int>] {
        var pages: [Range<Int>] = []
        var start = 0
        var used = 0
        for (index, hasPhoto) in photoFlags.enumerated() {
            let weight = momentWeight(hasPhoto: hasPhoto)
            if used + weight > momentPageCapacity, index > start {
                pages.append(start..<index)
                start = index
                used = 0
            }
            used += weight
        }
        if start < photoFlags.count { pages.append(start..<photoFlags.count) }
        return pages
    }

    /// Whether a country's moments are few and short enough to print on its
    /// opener rather than on a spread of their own: up to two in words, or one
    /// with a photograph, each within `OpenerMoments.noteLimit`.
    ///
    /// A country with one moment used to get a whole spread — one tile facing
    /// a ruled page — and across a trip that is paper somebody pays for. The
    /// opener's left page has a band free between the dates and the figures,
    /// and `OpenerMoments` holds its size; a check proves the largest group
    /// this allows fits it. They print a few pages before their days rather
    /// than after, which is the price.
    static func openerCarries(_ moments: [Moment]) -> Bool {
        guard !moments.isEmpty,
              moments.allSatisfy({ $0.note.trimmingCharacters(in: .whitespacesAndNewlines).count <= OpenerMoments.noteLimit })
        else { return false }
        let photographed = moments.filter { $0.photoID != nil }.count
        return (photographed == 0 && moments.count <= OpenerMoments.mostInWords)
            || (photographed == 1 && moments.count == 1)
    }

    /// Below this many of its own located places, an opener's map is a dot or
    /// two and a line — so the page sets the stops under a smaller map rather
    /// than leaving a lone dot to be the whole page.
    static let mapAloneFrom = 3

    static func openerListsStops(locatedPlaces: Int) -> Bool { locatedPlaces < mapAloneFrom }

    /// One group of moments — a country's, or those from before they left —
    /// as spreads, two pages to each. An odd last page leaves the right-hand
    /// one empty, and the view rules it for notes.
    static func momentSpreads(_ moments: [Moment], group: String, heading: String) -> [BookSpread] {
        let pages = momentPages(photoFlags: moments.map { $0.photoID != nil })
            .map { moments[$0].map(\.id) }
        return stride(from: 0, to: pages.count, by: 2).map { index in
            .moments(group: group, heading: heading, page: index / 2,
                     left: pages[index], right: index + 1 < pages.count ? pages[index + 1] : [])
        }
    }

    /// The earned stamps that belong to a leg.
    ///
    /// A waypoint belongs to the country holding its stop. Where it doesn't
    /// name one — an older trip, or a stop that was merged away — the country
    /// whose stops name its city, which is what the link was before the id
    /// existed. One rule for the opener's count and the opener's map.
    static func earnedStamps(_ stamps: [Stamp], inLeg leg: Leg, allSegmentIDs: Set<UUID>) -> [Stamp] {
        let cities = Set(leg.segments.flatMap(\.places))
        let here = Set(leg.segments.map(\.id))
        return stamps.filter { stamp in
            guard stamp.earned else { return false }
            if let id = stamp.segmentID, allSegmentIDs.contains(id) { return here.contains(id) }
            return cities.contains(stamp.city)
        }
    }

    /// Twelve to a page: a four-by-three grid of seals, each with the city
    /// under it. The first spread spends its left page on the heading, so it
    /// holds one page's worth; every spread after it holds two.
    ///
    /// Sixteen while they were bare circles; the city printed under each one
    /// takes the fourth row.
    static let stampsPerPage = 12

    static func stampSpreadCount(earned: Int) -> Int {
        pagedSpreadCount(count: earned, perPage: stampsPerPage)
    }

    /// Which earned stamps (by position, in order) one page draws. Nil for the
    /// heading page, which draws none.
    static func stampRange(spread page: Int, half: Int, earned: Int) -> Range<Int>? {
        pagedRange(spread: page, half: half, count: earned, perPage: stampsPerPage)
    }

    /// Spreads for a list whose first spread spends its left page on a
    /// heading: the stamps and the meeting places. One arithmetic, so the two
    /// can't drift into dropping a different record each.
    static func pagedSpreadCount(count: Int, perPage: Int) -> Int {
        guard count > 0 else { return 0 }
        let rest = max(count - perPage, 0)
        return 1 + (rest + perPage * 2 - 1) / (perPage * 2)
    }

    /// Which records (by position) one page of such a list draws. Nil for the
    /// heading page.
    static func pagedRange(spread page: Int, half: Int, count: Int, perPage: Int) -> Range<Int>? {
        let start: Int
        if page == 0 {
            guard half == 1 else { return nil }
            start = 0
        } else {
            start = perPage + (page - 1) * perPage * 2 + half * perPage
        }
        let end = min(start + perPage, count)
        return start < end ? start..<end : start..<start
    }

    /// Three to a page: a place's name in up to two lines at one size,
    /// directions in up to two, its script, and when it was agreed. Four fit
    /// only by shrinking long names, which set the rows at visibly different
    /// sizes on one page.
    static let meetingPlacesPerPage = 3

    /// The meeting places as the book prints them: only ones somebody set,
    /// oldest first, so the list reads in the order the trip went. The
    /// picker keeps them newest first, because there the question is "where
    /// did we meet last". Both the plan and the page read this.
    static func meetingPlacesInOrder(_ places: [MeetingPoint]) -> [MeetingPoint] {
        places.filter(\.isSet).sorted {
            $0.setAt == $1.setAt ? $0.place < $1.place : $0.setAt < $1.setAt
        }
    }

    /// Spreads that belong at the back of the last volume rather than with the
    /// days they follow. The moments are not among them any more: they print
    /// with their country.
    var endmatterCount: Int { stampSpreadCount + meetingSpreadCount + wholeTripSpreadCount }

    var dayCountInBook: Int {
        spreads.reduce(0) { count, spread in
            if case .day = spread { return count + 1 }
            return count
        }
    }

    /// Where a record prints: the spread holding a night's page, or the
    /// moments spread holding a moment. What "a year ago today" opens the
    /// book at. Nil for anything the book doesn't print.
    func spreadIndex(containing id: UUID) -> Int? {
        spreads.firstIndex { spread in
            switch spread {
            case .day(let entryID): return entryID == id
            case .moments(_, _, _, let left, let right): return left.contains(id) || right.contains(id)
            case .countryOpener(_, _, _, _, _, _, _, _, let carried): return carried.contains(id)
            default: return false
            }
        }
    }

    static let empty = BookPlan(spec: BookSpec(), spreads: [], sections: [],
                                volumes: 1, volumeSpreads: [], volumeSections: [], missedBefore: [:])

    /// "First country", "Back again". The country's name is set large right
    /// under it, so a second visit doesn't repeat it.
    ///
    /// The ordinal used to be the *leg's* position, looked up by the country's
    /// name with `firstIndex` — so Thailand on the way back was "First
    /// country" again, and anything past the fourth leg was "Fourth country".
    static func openerLabel(ordinal: Int, visit: Int) -> String {
        if visit > 1 { return "Back again" }
        let words = ["First", "Second", "Third", "Fourth", "Fifth",
                     "Sixth", "Seventh", "Eighth", "Ninth", "Tenth"]
        guard ordinal >= 1, ordinal <= words.count else { return "Country \(ordinal)" }
        return "\(words[ordinal - 1]) country"
    }

    /// The title page's italic line: "Sixty-one days, three countries".
    ///
    /// It was `legs.count` with a hand-written plural, so Thailand → Laos →
    /// Thailand printed "3 countries", and a trip with nowhere in it printed
    /// "0 countries" in a bound book. A clause with nothing in it drops.
    static func subtitle(days: Int, countries: Int) -> String {
        let length = Formatting.spelledCount(days, "day")
        guard countries > 0 else { return length }
        let places = Formatting.spelledCount(countries, "country", plural: "countries")
        return "\(length), \(places.prefix(1).lowercased() + places.dropFirst())"
    }

    /// The quiet line on the page after a gap: "Day 13 · no page", "Days
    /// 13–14 · no page". It keeps the calendar honest without asking anyone
    /// to go back and fill it in.
    static func missedLine(_ days: ClosedRange<Int>) -> String {
        days.count == 1 ? "Day \(days.lowerBound) · no page"
                        : "Days \(days.lowerBound)–\(days.upperBound) · no page"
    }

    /// Rows on one printed contents page. A two-week trip is half a dozen
    /// rows; a page holds ten at the size the contents are set in, and a trip
    /// with more turns onto the facing page.
    static let contentsRowsPerPage = 10

    static func contentsSpreadCount(rows: Int) -> Int {
        max(1, (rows + contentsRowsPerPage * 2 - 1) / (contentsRowsPerPage * 2))
    }

    /// What a printed contents page lists: everything but the pages it is on.
    static func contentsRows(_ sections: [BookSection]) -> [BookSection] {
        sections.filter { !$0.isFrontMatter }
    }

    /// The rows one contents page draws, in order.
    static func contentsRows(_ sections: [BookSection], page: Int, half: Int) -> ArraySlice<BookSection> {
        let rows = contentsRows(sections)
        let start = min((page * 2 + half) * contentsRowsPerPage, rows.count)
        return rows[start..<min(start + contentsRowsPerPage, rows.count)]
    }

    /// A body or back-matter spread and the section it is listed under.
    /// `key` tells two sections with the same title apart — two Thai legs of
    /// the same length — and consecutive spreads sharing one are one section.
    struct Placed: Equatable {
        var spread: BookSpread
        var key: String
        var title: String
        /// The country, for a leg's spreads: a volume that opens partway
        /// through one lists it as "Thailand, continued".
        var country: String? = nil
    }

    /// - Parameters:
    ///   - entries: this traveller's pages, any order.
    ///   - legs: the itinerary, which supplies the country openers.
    ///   - stamps: the live ones. Only earned stamps print — an unearned stamp
    ///     is not a place anybody stood.
    ///   - moments: this phone's own, oldest first — they print in the order
    ///     they happened, which is the reverse of the order the trail lists.
    static func build(entries: [JournalEntry], legs: [Leg], stamps: [Stamp],
                      moments: [Moment] = [],
                      meetingPlaces: [MeetingPoint] = [],
                      spec: BookSpec = BookSpec(), volumes: Int = 1,
                      includeStamps: Bool = true,
                      includeMoments: Bool = true) -> BookPlan {
        let ordered = entries.sorted { $0.dayNumber < $1.dayNumber }
        let keptMoments = includeMoments ? moments : []
        // The body is the openers, the days and their moments, in reading
        // order; it is what volumes divide. Front and back matter go round
        // each volume.
        var body: [Placed] = []

        // Every stop there is, so a waypoint pointing at one that was removed
        // can be told apart from one that never named a stop at all.
        let allSegmentIDs = Set(legs.flatMap(\.segments).map(\.id))

        // Which leg a day belongs to. `endDay` is the day they leave, so the
        // last day of the trip is inside no leg — the trap
        // `lastKnownSegment(forDay:)` exists for. Here it sent the night
        // before the flight home to the back of the book, after every
        // country, under "Elsewhere". The last leg keeps every day from its
        // start on, which is what `city(forDay:)` says about those days too.
        func legIndex(forDay day: Int) -> Int? {
            legs.indices.first { index in
                day >= legs[index].startDay && (index == legs.count - 1 || day < legs[index].endDay)
            }
        }

        // Moments made before day 1 — at the airport, on the way there — open
        // the book, ahead of the first country.
        let before = keptMoments.filter(\.isBeforeDeparture)
        if !before.isEmpty {
            for spread in momentSpreads(before, group: "before", heading: "Before we left") {
                body.append(Placed(spread: spread, key: "before", title: "Before we left"))
            }
        }
        let during = keptMoments.filter { !$0.isBeforeDeparture }
        let momentLeg = Dictionary(grouping: during) { legIndex(forDay: $0.dayNumber) ?? -1 }

        var countryOrder: [String] = []
        var visits: [String: Int] = [:]
        for (index, leg) in legs.enumerated() {
            if !countryOrder.contains(leg.country) { countryOrder.append(leg.country) }
            visits[leg.country, default: 0] += 1
            let inLeg = ordered.filter { legIndex(forDay: $0.dayNumber) == index }
            let legMoments = momentLeg[index] ?? []
            // A country with moments and no written night still opens: the
            // moments happened there, and printing them under the country
            // before would put them somewhere they weren't.
            guard !inLeg.isEmpty || !legMoments.isEmpty else { continue }
            let key = "leg-\(leg.id)"
            let title = "\(leg.country) · \(Formatting.spelledCount(leg.nights, "night", spellingUpTo: 0))"
            let earned = earnedStamps(stamps, inLeg: leg, allSegmentIDs: allSegmentIDs)
            let carried = openerCarries(legMoments)
            body.append(Placed(spread: .countryOpener(legID: leg.id, country: leg.country,
                                                      nights: leg.nights,
                                                      stampCount: earned.count,
                                                      fromDay: leg.startDay, toDay: leg.endDay,
                                                      ordinal: (countryOrder.firstIndex(of: leg.country) ?? 0) + 1,
                                                      visit: visits[leg.country] ?? 1,
                                                      moments: carried ? legMoments.map(\.id) : []),
                               key: key, title: title, country: leg.country))
            for entry in inLeg {
                body.append(Placed(spread: .day(entryID: entry.id), key: key, title: title, country: leg.country))
            }
            if !carried {
                for spread in momentSpreads(legMoments, group: leg.id.uuidString,
                                            heading: "Along the way · \(leg.country)") {
                    body.append(Placed(spread: spread, key: key, title: title, country: leg.country))
                }
            }
        }

        // Pages written somewhere the itinerary no longer covers still belong
        // in the book: a page must never be lost because a city was dropped
        // from the plan. The same goes for a moment.
        let orphans = ordered.filter { legIndex(forDay: $0.dayNumber) == nil }
        let strayMoments = momentLeg[-1] ?? []
        if !orphans.isEmpty || !strayMoments.isEmpty {
            let title = orphans.isEmpty
                ? "Elsewhere"
                : "Elsewhere · \(Formatting.spelledCount(orphans.count, "night", spellingUpTo: 0))"
            for entry in orphans {
                body.append(Placed(spread: .day(entryID: entry.id), key: "elsewhere", title: title))
            }
            for spread in momentSpreads(strayMoments, group: "elsewhere", heading: "Along the way") {
                body.append(Placed(spread: spread, key: "elsewhere", title: title))
            }
        }

        var endmatter: [Placed] = []
        let earnedCount = stamps.filter(\.earned).count
        if includeStamps, earnedCount > 0 {
            for page in 0..<stampSpreadCount(earned: earnedCount) {
                endmatter.append(Placed(spread: .stamps(page: page), key: "stamps", title: "The stamps"))
            }
        }

        let places = meetingPlacesInOrder(meetingPlaces).count
        for page in 0..<pagedSpreadCount(count: places, perPage: meetingPlacesPerPage) {
            endmatter.append(Placed(spread: .meetingPlaces(page: page), key: "meeting",
                                    title: "Where we said we'd meet"))
        }

        // The end of the book: what it all added up to, and the trail whole.
        // Only once something is written — a book of nothing has no total.
        if !ordered.isEmpty {
            endmatter.append(Placed(spread: .wholeTrip, key: "whole-trip", title: "The whole trip"))
        }

        let whole = assemble(body: body, endmatter: endmatter, spec: spec)

        let count = max(volumes, 1)
        let volumeParts = count == 1
            ? [whole]
            : split(body: body, into: count).enumerated().map { index, chunk in
                assemble(body: chunk, endmatter: index == count - 1 ? endmatter : [], spec: spec)
            }

        // The gap before each page. Only gaps *between* pages: the days after
        // the last one are still to come on a live trip.
        var missed: [UUID: ClosedRange<Int>] = [:]
        var previous = 0
        for entry in ordered where entry.dayNumber >= 1 {
            if entry.dayNumber > previous + 1 { missed[entry.id] = (previous + 1)...(entry.dayNumber - 1) }
            previous = max(previous, entry.dayNumber)
        }

        return BookPlan(spec: spec, spreads: whole.spreads, sections: whole.sections,
                        volumes: count, volumeSpreads: volumeParts.map(\.spreads),
                        volumeSections: volumeParts.map(\.sections), missedBefore: missed)
    }

    /// Front matter, the body, the back, notes pages up to the printer's
    /// minimum, and the colophon — and the sections, paged from where each
    /// spread actually landed, so the contents can't disagree with the book.
    private static func assemble(body: [Placed], endmatter: [Placed],
                                 spec: BookSpec) -> (spreads: [BookSpread], sections: [BookSection]) {
        let placed = body + endmatter
        // Consecutive spreads under one key are one section. A country's run
        // that doesn't begin with its opener is the rest of a country the
        // previous volume began.
        var runs: [(key: String, title: String, count: Int)] = []
        for item in placed {
            if let last = runs.last, last.key == item.key {
                runs[runs.count - 1].count += 1
            } else {
                var title = item.title
                if let country = item.country {
                    if case .countryOpener = item.spread {} else { title = "\(country), continued" }
                }
                runs.append((item.key, title, 1))
            }
        }

        let contents = contentsSpreadCount(rows: runs.count)
        var spreads: [BookSpread] = [.opening, .title]
        for page in 0..<contents { spreads.append(.contents(page: page)) }
        var sections = [
            BookSection(title: "Title & route", firstPage: 2, lastPage: 3, isFrontMatter: true),
            BookSection(title: "Contents", firstPage: leftPage(ofSpreadAt: 2),
                        lastPage: leftPage(ofSpreadAt: 2 + contents) - 1, isFrontMatter: true)
        ]
        var cursor = spreads.count
        for run in runs {
            sections.append(BookSection(title: run.title, firstPage: leftPage(ofSpreadAt: cursor),
                                        lastPage: leftPage(ofSpreadAt: cursor + run.count) - 1))
            cursor += run.count
        }
        spreads += placed.map(\.spread)

        // Pages are `2 × spreads − 2` once the closing is on, so this is the
        // spread count that reaches the minimum.
        let needed = spec.minimumPages / 2 + 1
        var index = 0
        while spreads.count + 1 < needed {
            spreads.append(.notes(index: index))
            index += 1
        }
        spreads.append(.closing)
        return (spreads, sections)
    }

    /// The body cut into `count` runs of days, as even as the days allow.
    ///
    /// A country's opener always travels with the first of its days — an
    /// opener stranded at the end of one volume with its country in the next
    /// would be a title page for nothing. Everything else that isn't a day —
    /// a country's moments — stays in the volume of the day before it. It
    /// used to be sent by the count of days already *passed*, which after a
    /// country's last night is the next volume's share: the moments would have
    /// opened the next book, ahead of the country they belonged to.
    static func split(body: [Placed], into count: Int) -> [[Placed]] {
        let dayTotal = body.reduce(0) { total, item in
            if case .day = item.spread { return total + 1 }
            return total
        }
        guard count > 1, dayTotal > 0 else { return [body] + Array(repeating: [], count: max(count - 1, 0)) }
        var chunks = Array(repeating: [Placed](), count: count)
        // Openers waiting for their first day, and anything that came between
        // — a country with moments and no night written travels with the next
        // day there is.
        var pending: [Placed] = []
        var dayIndex = 0
        var lastVolume = 0
        for item in body {
            switch item.spread {
            case .countryOpener:
                pending.append(item)
            case .day:
                let volume = min(dayIndex * count / dayTotal, count - 1)
                chunks[volume] += pending
                pending = []
                chunks[volume].append(item)
                lastVolume = volume
                dayIndex += 1
            default:
                if pending.isEmpty { chunks[lastVolume].append(item) } else { pending.append(item) }
            }
        }
        chunks[lastVolume] += pending
        return chunks
    }
}

// MARK: - Whether it will actually print

/// One photo, measured against the spec. Pixel dimensions come from whoever can
/// read the file; the arithmetic lives here so it can be checked on macOS.
struct PhotoMeasurement: Identifiable, Hashable {
    var id: UUID
    var dayNumber: Int
    var pixels: Int
    /// How wide it prints, as a fraction of a full-bleed page. A photograph
    /// on a contact sheet or among the moments is a fraction of the page and
    /// needs that fraction of the pixels — measuring every one as if it
    /// filled the page warns about pictures that will print perfectly.
    var printedFraction: Double = 1

    func dpi(on spec: BookSpec) -> Int {
        Int((Double(spec.printedDPI(forSquare: pixels)) / max(printedFraction, 0.01)).rounded())
    }

    func isSoft(on spec: BookSpec) -> Bool { dpi(on: spec) < spec.softBelowDPI }
}

/// How a day's spread is laid out, from what the page holds.
///
/// One photograph is the page, full bleed, as it always was. Two or three are
/// a contact sheet on the left page — the first large, the others beside it.
/// None is the day set in type. The right page is the line, with the note under
/// it in body type when there is one. Every combination is exactly one layout,
/// which a check holds.
struct DaySpreadLayout: Equatable {
    enum Photos: Equatable {
        case quiet
        case single
        case contact(count: Int)
    }
    var photos: Photos
    var hasNote: Bool

    init(photoCount: Int, hasNote: Bool) {
        switch photoCount {
        case ...0: photos = .quiet
        case 1: photos = .single
        default: photos = .contact(count: min(photoCount, 1 + JournalEntry.extraPhotoLimit))
        }
        self.hasNote = hasNote
    }

    init(_ entry: JournalEntry) {
        self.init(photoCount: entry.allPhotoIDs.count,
                  hasNote: !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// On a contact sheet the first photograph is two thirds of the page
    /// across and the others a third. What the print check measures them at.
    static let contactHeroFraction = 2.0 / 3
    static let contactSmallFraction = 1.0 / 3
    /// A moment's photograph prints at about this much of the page.
    static let momentFraction = 0.32

    func printedFraction(ofPhotoAt index: Int) -> Double {
        switch photos {
        case .quiet: return 0
        case .single: return 1
        case .contact: return index == 0 ? Self.contactHeroFraction : Self.contactSmallFraction
        }
    }
}

/// I3 · what the print screen says before anything is sent.
struct PrintReadiness: Equatable {
    var pageCount: Int
    var softPhotos: [Int]          // day numbers
    var missingPhotos: Int
    var estimatedMegabytes: Int
    /// Moments kept in one tap and never written up. Left out of the book, and
    /// named here, so leaving them out is never a surprise after printing.
    var unfinishedMoments: Int = 0
    /// The records whose photographs print soft — a night's page or a moment
    /// — in day order, so the Book tab can open the first one to fix.
    var softRecords: [UUID] = []

    var unfinishedLine: String? {
        guard unfinishedMoments > 0 else { return nil }
        return unfinishedMoments == 1
            ? "One moment with nothing in it yet won't print. Finish it on the trail."
            : "\(Formatting.spelledCount(unfinishedMoments, "moment")) with nothing in them yet won't print. Finish them on the trail."
    }

    var isClean: Bool { softPhotos.isEmpty }

    var softSummary: String? {
        guard !softPhotos.isEmpty else { return nil }
        // One entry per day, not per photograph. A page and a moment on the
        // same day are two soft photographs but one day to go and look at, so
        // the sentence dedupes and the count does not.
        // A moment kept before departure has a day of zero or below, and
        // "day -3" names nothing a reader could go and look for.
        var days: [String] = []
        for day in Set(softPhotos).sorted() {
            let label = day < 1 ? "one from before you left" : "day \(day)"
            if !days.contains(label) { days.append(label) }
        }
        let list: String
        switch days.count {
        case 1: list = days[0]
        case 2: list = "\(days[0]) and \(days[1])"
        default: list = days.dropLast().joined(separator: ", ") + " and " + days[days.count - 1]
        }
        return "\(list.prefix(1).uppercased() + list.dropFirst()) came off something smaller than the page needs and will print soft. Use them anyway, or pick different shots."
    }

    /// One quiet sentence for the Book tab, while there is still time to do
    /// something about it. The print screen used to be the first place either
    /// of these was said, which is after the trip — when the photograph can't
    /// be taken again. Nil when there is nothing to fix.
    var earlyLine: String? {
        var clauses: [String] = []
        var days: [String] = []
        for day in Set(softPhotos).sorted() {
            let label = day < 1 ? "the days before you left" : "day \(day)"
            if !days.contains(label) { days.append(label) }
        }
        switch days.count {
        case 0: break
        case 1: clauses.append("a photo on \(days[0]) is small for its page")
        default:
            let list = days.dropLast().joined(separator: ", ") + " and " + days[days.count - 1]
            clauses.append("photos on \(list) are small for their pages")
        }
        if unfinishedMoments == 1 {
            clauses.append("one moment has nothing in it yet")
        } else if unfinishedMoments > 1 {
            let count = Formatting.spelledCount(unfinishedMoments, "moment")
            clauses.append("\(count.prefix(1).lowercased() + count.dropFirst()) have nothing in them yet")
        }
        guard !clauses.isEmpty else { return nil }
        return "Before it prints: \(clauses.joined(separator: ", and "))."
    }

    static func measure(plan: BookPlan, photos: [PhotoMeasurement],
                        entriesWithoutPhoto: Int, unfinishedMoments: Int = 0) -> PrintReadiness {
        let softOnes = photos.filter { $0.isSoft(on: plan.spec) }
        let soft = softOnes.map(\.dayNumber)
        var records: [UUID] = []
        for photo in softOnes.sorted(by: { $0.dayNumber < $1.dayNumber }) where !records.contains(photo.id) {
            records.append(photo.id)
        }
        // The writer embeds each photograph once, as the JPEG `PhotoStore`
        // keeps — about 2.5 MB at full size — and draws the rest as type, which
        // costs next to nothing. This was 8 MB a photo plus 0.2 a page, the
        // arithmetic of a file made of flattened page pictures, which is what
        // the writer used to produce.
        let megabytes = Int((Double(photos.count) * 2.5 + Double(plan.pageCount) * 0.03).rounded())
        return PrintReadiness(pageCount: plan.pageCount,
                              softPhotos: soft,
                              missingPhotos: entriesWithoutPhoto,
                              estimatedMegabytes: max(megabytes, 1),
                              unfinishedMoments: unfinishedMoments,
                              softRecords: records)
    }

    /// How to talk about the size. A book with no photographs is a few
    /// megabytes, so the wording is chosen from the number rather than
    /// asserted alongside it.
    var sizeLine: String {
        let size = estimatedMegabytes >= 1_000
            ? "\(Formatting.decimal(Double(estimatedMegabytes) / 1_000, places: 1)) GB"
            : "\(estimatedMegabytes) MB"
        // No "it'll wait until it has some": the file goes to the share sheet,
        // and nothing here waits for anything.
        if estimatedMegabytes >= 200 {
            return "Built on the phone. About \(size) at 300 dpi, so send it on real wifi."
        }
        if estimatedMegabytes >= 20 {
            return "Built on the phone. About \(size) at 300 dpi — a café connection will manage it."
        }
        return "Built on the phone. About \(size), because the pages are mostly type."
    }
}


// MARK: - The cover

/// The case-wrap cover Lulu binds the 8.5 × 8.5 photo book in, as one flat
/// sheet: back board, spine, front board, and the cloth that wraps round them.
///
/// **Every number here came off Lulu's own templates**, downloaded for this
/// product (`product`) at 24, 84, 140, 300 and 500 pages — they are in
/// `Tools/LuluTemplates/`, and a check rebuilds each one's total size from
/// this struct. The spine table is Lulu's published one ("How is spine width
/// calculated?"), with its two overlapping rows settled by the templates: 84
/// pages is a quarter inch and 140 is a half.
///
/// The cover used to be missing for exactly this reason: the table found
/// first stopped at 360 pages and said nothing about the wrap, and a cover
/// sized by guesswork is a file the printer sends back.
struct CoverSpec: Equatable {
    /// Lulu's code for this book: 8.5 × 8.5, full colour, premium, case wrap,
    /// 80# coated, matte.
    static let product = "0850X0850.FC.PRE.CW.080CW444.MXX"

    /// A rectangle in inches, measured from the sheet's top-left corner.
    struct Box: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var maxX: Double { x + width }
        var maxY: Double { y + height }
        func inset(_ by: Double) -> Box {
            Box(x: x + by, y: y + by, width: width - by * 2, height: height - by * 2)
        }
    }

    /// The boards are larger than the pages they hold: 8.75 × 9 around an
    /// 8.5 × 8.5 interior.
    static let boardWidth = 8.75
    static let boardHeight = 9.0
    /// Cloth that folds round every edge of the boards. Artwork has to run
    /// into it; nothing that matters may sit in it.
    static let wrap = 0.625
    /// Lulu's safety margin, measured in from the wrap edge — the board's
    /// outer edges and the spine alike.
    static let safety = 0.625
    /// Lulu's optional barcode box on the back, next to the spine at the
    /// bottom. Nothing is printed there.
    static let barcodeWidth = 3.622
    static let barcodeHeight = 1.26
    /// Below this the spine carries no type. A quarter-inch case-wrap spine is
    /// a few points of cloth that shifts in binding; a name set on it lands on
    /// a board as often as not. This is the app's call, not Lulu's.
    static let spineTypeMinimum = 0.5
    /// The type's clearance either side of it on the spine. Also ours.
    static let spineTypeInset = 0.0625

    static let minimumPages = 24
    static let maximumPages = 800

    /// Lulu's case-wrap spine table: the last page count of each row and its
    /// width. Rows are 28 pages apart, give or take, and each is a sixteenth
    /// of an inch wider than the one before, except the first two.
    private static let spineRows: [(upTo: Int, inches: Double)] = [
        (84, 0.25), (140, 0.5), (168, 0.625), (194, 0.6875), (222, 0.75),
        (250, 0.8125), (278, 0.875), (306, 0.9375), (334, 1), (360, 1.0625),
        (388, 1.125), (416, 1.1875), (444, 1.25), (472, 1.3125), (500, 1.375),
        (528, 1.4375), (556, 1.5), (582, 1.5625), (610, 1.625), (638, 1.6875),
        (666, 1.75), (694, 1.8125), (722, 1.875), (750, 1.9375), (778, 2),
        (798, 2.0625)
    ]

    /// The spine for a page count, or nil when there is no answer to trust:
    /// outside 24…800, or at exactly 800, which the table lists twice with two
    /// different widths and no template has settled.
    static func spineWidth(pages: Int) -> Double? {
        guard pages >= minimumPages, pages < maximumPages else { return nil }
        return spineRows.first { pages <= $0.upTo }?.inches
    }

    let pages: Int
    let spine: Double

    init?(pages: Int) {
        guard let spine = Self.spineWidth(pages: pages) else { return nil }
        self.pages = pages
        self.spine = spine
    }

    var totalWidth: Double { Self.boardWidth * 2 + spine + Self.wrap * 2 }
    var totalHeight: Double { Self.boardHeight + Self.wrap * 2 }

    var back: Box { Box(x: Self.wrap, y: Self.wrap, width: Self.boardWidth, height: Self.boardHeight) }
    var spineBox: Box { Box(x: back.maxX, y: Self.wrap, width: spine, height: Self.boardHeight) }
    var front: Box { Box(x: spineBox.maxX, y: Self.wrap, width: Self.boardWidth, height: Self.boardHeight) }

    var backSafe: Box { back.inset(Self.safety) }
    var frontSafe: Box { front.inset(Self.safety) }

    /// Where the spine's type may go, or nil when the spine is too narrow to
    /// carry any.
    var spineTypeArea: Box? {
        guard spine >= Self.spineTypeMinimum else { return nil }
        return Box(x: spineBox.x + Self.spineTypeInset, y: spineBox.y + Self.safety,
                   width: spine - Self.spineTypeInset * 2, height: Self.boardHeight - Self.safety * 2)
    }

    /// The barcode box: bottom of the back board, against the safety line on
    /// the spine side, as Lulu's template draws it.
    var barcode: Box {
        Box(x: backSafe.maxX - Self.barcodeWidth, y: backSafe.maxY - Self.barcodeHeight,
            width: Self.barcodeWidth, height: Self.barcodeHeight)
    }

    /// Where the back's own artwork may go: the safe area, less a band at the
    /// bottom as deep as the barcode box, so nothing ever sits under one.
    var backArtwork: Box {
        Box(x: backSafe.x, y: backSafe.y, width: backSafe.width,
            height: backSafe.height - Self.barcodeHeight - 0.25)
    }

    var sizeLabel: String {
        func inches(_ value: Double) -> String {
            Formatting.decimal(value, places: value.rounded() == value ? 0 : 3)
                .replacingOccurrences(of: #"(\.\d*?)0+$"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
        return "\(inches(totalWidth)) × \(inches(totalHeight)) in · spine \(inches(spine)) in"
    }
}

// MARK: - The day's text page

/// The right-hand page of a day, in the spread's own units: a page is `side`
/// units square, whatever size it is drawn at.
///
/// Held here rather than written into the view so the checks can prove the
/// page holds what the store lets onto it. The text sits in a box of a fixed
/// height; the view tries `scales` largest first and takes the first that
/// fits. The proof is a check that sets the longest line and the longest note
/// the store accepts — in the widest characters, as one unbroken word, and as
/// emoji — in the book's own typeface at the smallest scale, and measures that
/// it fits the box. So the last-resort shrink the view keeps underneath is
/// never reached by anything the store will save.
///
/// It used to be guarded, not proven: three sizes and a hope, and nothing
/// stopping one long word from running off the page into a bound book.
enum DayTextPage {
    /// Units per page side.
    static let side = 381.0
    static let margin = 46.0
    static var width: Double { side - margin * 2 }

    // Everything above and below the text, in units. The heading and footer
    // are single lines of 10.5- and 9.5-unit mono type; each is given room
    // for a line height of 1.35 × its size, which no monospaced face exceeds.
    static let headingLine = 15.0
    static let ruleAbovePlain = 18.5, ruleBelowPlain = 22.5
    static let ruleAboveWithNote = 12.5, ruleBelowWithNote = 14.5
    /// The trip mark under the heading, showing how far through the trip the
    /// night was — flipping through, the dot walks across the book. It took
    /// the place of a 1-unit accent rule, and the 3 units it is taller came
    /// out of the gaps either side, so `textHeight` did not move and every
    /// fit proof stands as it was. A check holds the heights to their old
    /// values. At 4 units the lockup's stroke is about 1.4 and its dot about
    /// 3.8, which keeps the weight of the hairline it replaced.
    static let mark = 4.0
    /// Tags, the gap above the page number, and the page number.
    static let footer = 13.0 + 8.0 + 13.0
    /// Kept clear between the text and the tags.
    static let footerGap = 18.0

    /// The day's occasion — "Market day" — on its own line under the heading,
    /// the way the day screen shows it. A 9.5-unit mono line at 1.35 × its
    /// size, and the gap under it.
    static let occasionLine = 15.0

    /// The text box's height. An occasion takes its line out of the box, so
    /// the proof is run with and without one.
    static func textHeight(hasNote: Bool, hasOccasion: Bool = false) -> Double {
        let rules = hasNote ? ruleAboveWithNote + mark + ruleBelowWithNote
                            : ruleAbovePlain + mark + ruleBelowPlain
        return side - margin * 2 - headingLine - (hasOccasion ? occasionLine : 0)
            - rules - footer - footerGap
    }

    // Type, at scale 1.
    static let lineAlone = 31.0, lineAloneSpacing = 7.0
    static let lineWithNote = 21.0, lineWithNoteSpacing = 4.0
    static let note = 11.5, noteSpacing = 4.0
    static let lineToNote = 14.0

    /// The sizes tried, largest first. The last is the one the check proves.
    /// The steps above 1 are only ever reached by a short line — see
    /// `maxScale(forLine:hasNote:)`.
    static let scales: [Double] = [1.45, 1.25, 1.2, 1, 0.88, 0.76, 0.66, 0.58, 0.5, 0.43, 0.37]

    /// How large a line may be set, from how long it is.
    ///
    /// The page used to try the same largest size for every line and only
    /// ever shrink, so four words and a full paragraph that both fitted were
    /// set identically — the short line lost in the white of the page. A
    /// short line is the page's whole content and is set like a title; the
    /// sizes then fall back through `scales` as before for anything that
    /// doesn't fit. Counted in characters a reader sees, so an emoji is one.
    static func maxScale(forLine line: String, hasNote: Bool) -> Double {
        let length = line.trimmingCharacters(in: .whitespacesAndNewlines).count
        if hasNote { return length <= shortLineWithNote ? 1.25 : 1 }
        if length <= shortLine { return 1.45 }
        if length <= mediumLine { return 1.2 }
        return 1
    }

    static let shortLine = 20
    static let mediumLine = 36
    static let shortLineWithNote = 30

    /// The scales a line of this length is tried at, largest first.
    static func scales(forLine line: String, hasNote: Bool) -> [Double] {
        let cap = maxScale(forLine: line, hasNote: hasNote)
        return scales.filter { $0 <= cap }
    }
}

// MARK: - Moments on an opener

/// The band on a country opener's left page that carries a short group of
/// moments, in the page's own 381-unit scale, between the dates and the
/// figures. Held here so a check can prove the largest group `openerCarries`
/// allows fits it, the way `DayTextPage` is proven.
enum OpenerMoments {
    /// The longest note a carried moment may have.
    static let noteLimit = 70
    /// Moments in words alone, at most.
    static let mostInWords = 2

    /// The band's height, and the page's text width.
    static let band = 105.0
    static var width: Double { DayTextPage.width }

    // A tile: the note, its caption under it, and the gap to the next.
    static let note = 11.5, noteSpacing = 1.5
    /// A 7-unit mono caption at 1.35 × its size, and the gap above it.
    static let caption = 9.5 + 2.0
    static let tileGap = 8.0
    /// A photographed moment's thumbnail, and the gap beside it.
    static let thumb = 56.0, thumbGap = 10.0

    /// The country's name on an opener carrying moments, smaller to make the
    /// room; 58 otherwise.
    static let countrySize = 44.0
}
