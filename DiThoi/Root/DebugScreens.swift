#if DEBUG
import SwiftUI

/// Debug-only screen router, compiled out of Release builds.
///
/// The app is driven with `xcrun simctl launch … -screen <id>` so every screen
/// can be opened and photographed without synthetic taps. It exists for
/// verification, not for the app.
enum DebugScreen {
    static func value(for flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var requested: String? { value(for: "-screen") }

    static var wantsReset: Bool {
        ProcessInfo.processInfo.arguments.contains("-resetTrip")
    }

    /// `-seedItinerary` puts somewhere to be in the trip.
    ///
    /// Nothing else does. `TripStore.init` always seeds a *blank* trip, so
    /// every route that draws the plan — `today`, `itinerary`, `day`,
    /// `dayplan` — has only ever run against a trip with nowhere in it.
    /// `-screen day` carries a written-down fallback to the editor for exactly
    /// that reason. The populated half of all four was unreachable, which is a
    /// screen nothing can reach and therefore a screen nothing checks.
    ///
    /// A flag rather than seeding those routes automatically, for two reasons:
    /// the empty states are half of what there is to look at here and have to
    /// stay photographable, and a flag composes with `-day n`.
    static var wantsItinerary: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedItinerary")
    }

    /// `-seedJournal` writes pages up to the day the trip is on, with
    /// photographs, so the book has something in it.
    ///
    /// Nothing else does. Every book route — `book`, `bookpreview`,
    /// `printfile`, `saved` — had only ever drawn an empty journal, which is
    /// how a print file that put each photograph on the back of its own line
    /// went unseen: the one screen that could show it showed "Nothing in it
    /// yet". A flag for the same reason `-seedItinerary` is one: the empty
    /// book is half of what there is to look at.
    static var wantsJournal: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedJournal")
    }

    /// `-seedSpending` puts two lines of spending on every day so far, in
    /// that day's own currency, plus one card payment in the home currency
    /// on the second — so the day pages' facts line has money in it, and one
    /// day of it is approximate. Nothing else seeds an expense.
    static var wantsSpending: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedSpending")
    }

    /// `-seedLetters` puts three sealed letters on the phone, one with its
    /// condition withheld; `-openLetter` opens the first of them as well.
    /// Their conditions are day 10 and later, so on an early `-day n` none
    /// opens itself.
    ///
    /// Nothing else puts a letter on the phone, which is how Today on a phone
    /// with sealed letters and none opened went unseen: it drew no letter
    /// card, no way into the letters, and no "Today together" either.
    static var wantsLetters: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedLetters")
    }

    static var wantsOpenLetter: Bool {
        ProcessInfo.processInfo.arguments.contains("-openLetter")
    }

    /// `-noBudget` zeroes the budget after the other seeds, so the pace
    /// line's no-budget branch can be photographed with money in the day.
    static var wantsNoBudget: Bool {
        ProcessInfo.processInfo.arguments.contains("-noBudget")
    }

    @MainActor
    static func seedLetters(into store: TripStore) {
        guard store.letters.isEmpty else { return }
        let written = Calendar.trip.date(byAdding: .day, value: -10, to: store.start) ?? store.start
        store.letters = [
            Letter(number: 1, title: "For the first night", writtenOn: written,
                   condition: .day(10), hint: "when you've put the bags down",
                   paragraphs: ["You made it. Eat something before you sleep, even if it's only rice."],
                   signature: "— me", sealedAt: written),
            Letter(number: 2, title: "Opens in Hanoi", writtenOn: written,
                   condition: .place("Hanoi"), hint: "when you land, whenever that is",
                   paragraphs: ["Second country. Walk into the traffic slowly and it goes around you."],
                   signature: "— me", sealedAt: written),
            Letter(number: 3, title: "Not saying", writtenOn: written,
                   condition: .day(30), hint: "",
                   paragraphs: ["Thirty days. From here every one is a day closer."],
                   signature: "— me", sealedAt: written, secretCondition: true),
        ]
        if wantsOpenLetter {
            store.open(letterNumber: 1, place: store.currentCity)
        }
    }

    @MainActor
    static func seedSpending(into store: TripStore) {
        guard store.expenses.live.isEmpty, store.dayNumber >= 1 else { return }
        for day in 1...min(store.dayNumber, store.dayCount) {
            let currency = store.leg(forDay: day)?.currency ?? store.homeCurrency
            let country = store.leg(forDay: day)?.country ?? ""
            let base = currency.decimals == 0 ? 400.0 : 12.0
            for (hour, factor, note) in [(13, 1.0, "Lunch"), (20, 2.1, "Dinner")] {
                store.add(Expense(date: Calendar.trip.date(byAdding: .hour, value: hour,
                                                           to: store.date(forDay: day)) ?? store.date(forDay: day),
                                  amount: (base * factor * Double(1 + day % 3)).rounded(),
                                  currency: currency, payer: day % 2 == 0 ? .one : .two,
                                  split: .evenly, note: note, country: country))
            }
            if day == 2 {
                store.add(Expense(date: store.date(forDay: day), amount: 24, currency: store.homeCurrency,
                                  payer: .one, split: .evenly, note: "Card", country: country))
            }
        }
    }

    /// `-day 25` puts the trip on that day, by moving the departure date.
    ///
    /// Several screens are only wrong in one country — the emergency card most
    /// of all — and reaching those days otherwise takes two months.
    ///
    /// Zero and below are allowed, and put the trip in the future: `-day -5` is
    /// six days before departure. Today's before-and-after branches are two
    /// different screens, and both need to be reachable.
    static var requestedDay: Int? { value(for: "-day").flatMap(Int.init) }

    @MainActor
    static func applyDay(to store: TripStore) {
        guard let day = requestedDay else { return }
        let today = Calendar.trip.startOfDay(for: Date())
        guard let start = Calendar.trip.date(byAdding: .day, value: -(day - 1), to: today) else { return }
        store.setStart(start)
    }

    /// Moments to photograph the trail with.
    ///
    /// Nothing seeds these — a moment is somebody's own, so the store never
    /// makes one. Without them the list, the map marks and the book's last
    /// section are unreachable from a reset trip.
    ///
    /// Idempotent, so relaunching doesn't pile them up. Coordinates are real
    /// places near the waypoints they sit between, since what these are for is
    /// checking whether a moment reads as a stamp.
    ///
    /// Spread over days and places rather than all made "now": five moments
    /// kept on one day in one city are one group on the full list and one
    /// cluster on the map, which is the screen with nothing to look at. They
    /// go in through `restoreMoment`, the one mutation that takes a whole
    /// value — `addMoment` stamps the clock's day and city, which is right
    /// for a real moment and exactly what a spread needs to avoid.
    @MainActor
    static func seedMoments(into store: TripStore) {
        guard store.moments.isEmpty else { return }
        let seeds: [(Int, String, String, Double, Double)] = [
            (-1, "", "Gate D7, far too early, far too excited", 52.3105, 4.7683),
            (2, "Bangkok", "The noodle stall with no name, four doors down", 13.7460, 100.5340),
            (6, "Ayutthaya", "Missed the last boat and didn't mind", 14.3560, 100.5680),
            (11, "Chiang Mai", "Wrong bus. Better temple.", 18.7960, 98.9790),
            (12, "Chiang Mai", "Rain, and nowhere open but this one", 0, 0),
            (12, "Chiang Mai", "The dog that followed us the whole way up", 18.8050, 98.9210),
            // Kept in one tap and not written up — "1 to finish", the row's
            // unfinished face, and the print screen's line.
            (12, "Chiang Mai", "", 18.7900, 98.9870)
        ]
        for (index, seed) in seeds.enumerated() {
            let (day, city, note, latitude, longitude) = seed
            let when = Calendar.trip.date(byAdding: .hour, value: (day - 1) * 24 + 9 + index,
                                          to: store.start) ?? store.now
            store.restoreMoment(Moment(capturedAt: when, dayNumber: day, city: city, note: note,
                                       latitude: latitude, longitude: longitude))
        }
    }

    /// Waypoints with positions, two of them earned, so the map has a trail
    /// to draw and a stop ahead to measure to. `-seedItinerary` makes the
    /// stops; nothing makes stamps, so every map photographed so far showed
    /// moments over an empty trail.
    @MainActor
    static func seedWaypoints(into store: TripStore) {
        guard store.orderedStamps.isEmpty else { return }
        let seeds: [(String, String, String, Double, Double)] = [
            ("Bangkok", "BKK", "Bangkok", 13.7563, 100.5018),
            ("Ayutthaya · Pai", "AYU", "Ayutthaya", 14.3532, 100.5689),
            ("Chiang Mai", "CNX", "Chiang Mai", 18.7883, 98.9853),
            ("Huế", "HUE", "Huế", 16.4637, 107.5909),
            ("Seoul", "SEL", "Seoul", 37.5665, 126.9780)
        ]
        for (title, code, city, _, _) in seeds {
            guard let segment = store.itinerary.allSegments.first(where: { $0.title == title }) else { continue }
            _ = store.addWaypoint(code: code, city: city, arrivalNote: "", toSegment: segment.id)
        }
        let earnedDays = ["BKK": 1, "AYU": 5]
        store.stamps = store.stamps.map { stamp in
            guard let seed = seeds.first(where: { $0.1 == stamp.code }) else { return stamp }
            var placed = stamp
            placed.latitude = seed.3
            placed.longitude = seed.4
            if let day = earnedDays[stamp.code] { placed.earnedOn = store.date(forDay: day) }
            return placed
        }
    }

    /// Books for the shelf.
    ///
    /// Nothing seeds these either: the shelf only fills when a trip is closed,
    /// and `reset()` clears `TripLibrary.defaultKey` on purpose. So `-screen
    /// shelf` on a reset trip drew one live spine and the dashed placeholder —
    /// which is the shelf with nothing on it, on the screen whose whole subject
    /// is a row of books.
    ///
    /// The names and lengths are the failing case, not decoration. A spine's
    /// height is its trip's length, so the shortest trip has the least room for
    /// its name; a long name on a three-day trip is exactly where the label used
    /// to paint over its neighbours. The second is short-named and long, so the
    /// two ends of the clamp are on screen together.
    ///
    /// Idempotent, like `seedMoments` and `seedDocuments`.
    /// Two typed names, so a screen that says them says a name rather than
    /// "Traveller one". Only where nobody has typed one yet.
    @MainActor
    static func nameTheTravellers(in store: TripStore) {
        if store.typedName(for: .one).isEmpty { store.rename(.one, to: "Alex") }
        if store.typedName(for: .two).isEmpty { store.rename(.two, to: "Lynn") }
        if store.tripName.isEmpty { store.tripName = "Three countries, slowly" }
    }

    static var wantsPlan: Bool {
        ProcessInfo.processInfo.arguments.contains("-planned")
    }

    /// A plan on the shelf: Vietnam, a fortnight, one stop. Idempotent, and
    /// through `makePlan` rather than a hand-built snapshot, so the route
    /// photographs what the button would make.
    @MainActor
    static func seedPlan(into store: TripStore) {
        guard store.library.plan == nil, let plan = store.makePlan() else { return }
        plan.tripName = "Vietnam, slowly"
        plan.setDayCount(14)
        _ = plan.addLeg(country: "Vietnam", currency: .vnd, firstStop: "Hội An", nights: 5)
        _ = plan.addLeg(country: "Laos", currency: .thb, firstStop: "Luang Prabang", nights: 4)
        plan.savePlan()
    }

    @MainActor
    static func seedShelf(into store: TripStore) {
        guard store.library.isEmpty else { return }
        let seeds: [(String, Int, Int, [String])] = [
            ("A long weekend somewhere warm and far away", 3, 4, ["Portugal"]),
            ("Seoul", 44, 38, ["South Korea", "Japan"])
        ]
        for (offset, seed) in seeds.enumerated() {
            let (name, dayCount, pageCount, countries) = seed
            var summary = store.summary
            summary.id = UUID()
            summary.name = name
            summary.dayCount = dayCount
            summary.pageCount = pageCount
            summary.countries = countries
            summary.start = Calendar.trip.date(byAdding: .year, value: -(offset + 1),
                                               to: store.start) ?? store.start
            summary.status = .archived
            summary.closedOn = summary.start
            // A real encoded snapshot, so the row opens rather than
            // photographing the "couldn't be read" branch.
            var snapshot = store.snapshot
            if offset == 0 {
                // Something from exactly a year ago, or "A year ago today" is
                // a panel nothing could ever photograph: nothing else puts a
                // dated record on the shelf.
                let yearAgo = Calendar.trip.date(byAdding: .year, value: -1, to: store.now) ?? store.now
                snapshot.moments = [Moment(capturedAt: yearAgo, dayNumber: 2, city: "Lisbon",
                                           note: "Custard tarts on the tram steps, still warm",
                                           latitude: 38.7110, longitude: -9.1300)]
                snapshot.journal = [JournalEntry(dayNumber: 2, date: yearAgo, city: "Lisbon",
                                                 line: "Walked until the tiles ran out",
                                                 tags: [], hasPhoto: false, author: snapshot.role)]
            }
            store.library.archive(summary,
                                  snapshot: (try? JSONEncoder().encode(snapshot)) ?? Data())
        }
    }

    /// One moment in the second country, so its opener carries it — the only
    /// way a page with moments on an opener can be photographed. Idempotent.
    @MainActor
    static func seedOpenerMoment(into store: TripStore) {
        let note = "The first coffee with condensed milk"
        guard store.legs.count >= 2, !store.moments.contains(where: { $0.note == note }) else { return }
        let day = store.legs[1].startDay
        guard day <= store.dayNumber else { return }
        let when = Calendar.trip.date(byAdding: .hour, value: (day - 1) * 24 + 10, to: store.start) ?? store.now
        store.restoreMoment(Moment(capturedAt: when, dayNumber: day, city: store.city(forDay: day),
                                   note: note, latitude: 16.4637, longitude: 107.5909))
    }

    /// Two moments with photographs on one night. Idempotent.
    @MainActor
    static func seedPhotographedMoments(onDay day: Int, into store: TripStore) {
        guard !store.moments(onDay: day).contains(where: { $0.photoID != nil }) else { return }
        let notes = ["The view from the top step", "Lanterns, and nobody else"]
        for (index, note) in notes.enumerated() {
            let when = Calendar.trip.date(byAdding: .hour, value: (day - 1) * 24 + 15 + index,
                                          to: store.start) ?? store.now
            let photo = PhotoStore.shared.save(seedPhotograph(day: day + 7 * (index + 1), side: 1_200))
            store.restoreMoment(Moment(capturedAt: when, dayNumber: day, city: store.city(forDay: day),
                                       note: note, hasPhoto: photo != nil, photoID: photo))
        }
    }

    /// Places they agreed to meet, so the book's "Where we said we'd meet"
    /// spread has something on it. With the journal rather than the
    /// itinerary: Today's empty meeting point is a state worth photographing,
    /// and `-seedItinerary` routes draw it.
    ///
    /// Idempotent, like the others.
    @MainActor
    static func seedMeetingPlaces(into store: TripStore) {
        guard store.meetingPlaces.isEmpty else { return }
        let places = [
            MeetingPoint(place: "The bridge by the night market", detail: "East end, under the lamp",
                         localScript: "สะพานไนท์บาซาร์", setAt: store.now),
            MeetingPoint(place: "Gate 3, Huế station", detail: "By the ticket windows, not the platform",
                         localScript: "Ga Huế, cổng 3", setAt: store.now),
            MeetingPoint(place: "The guesthouse with the blue door", detail: "Second floor, ring twice",
                         localScript: "", setAt: store.now)
        ]
        for place in places { store.setMeetingPoint(place) }
    }

    /// Papers for the document routes.
    ///
    /// Fixed ids, so the scans added to one on this launch are still its scans
    /// on the next — `ScanVault` files them under the document's uuid, and a
    /// fresh one each time would orphan them on every relaunch.
    static let sampleDocuments = [
        TravelDocument(
            id: UUID(uuidString: "D0C0FFEE-0000-4000-8000-000000000001")!,
            title: "Passport",
            subtitle: "The photo page",
            badge: "PASSPORT",
            owner: .one,
            fields: [
                DocumentField(label: "Number", value: "NX4419 882"),
                DocumentField(label: "Expires", value: "14 Aug 2031"),
                DocumentField(label: "Blank pages", value: "9")
            ]),
        TravelDocument(
            id: UUID(uuidString: "D0C0FFEE-0000-4000-8000-000000000002")!,
            title: "Vietnam e-visa",
            subtitle: "90 days, single entry",
            badge: "VISA",
            fields: [
                DocumentField(label: "Reference", value: "E12-4471"),
                DocumentField(label: "Entry", value: "Nội Bài")
            ],
            footnoteTitle: "At the border",
            footnoteBody: "Paper copy is in the front pocket of the blue backpack."),
        TravelDocument(
            id: UUID(uuidString: "D0C0FFEE-0000-4000-8000-000000000003")!,
            title: "Insurance",
            subtitle: "claim line, 24h",
            badge: "INSURANCE",
            fields: [
                DocumentField(label: "Policy", value: "TW-4471-882"),
                DocumentField(label: "Claim line", value: "+31 20 592 9292"),
                DocumentField(label: "Nationality", value: "Dutch")
            ])
    ]

    static var sampleDocument: TravelDocument { sampleDocuments[0] }

    /// Puts them in the store rather than handing one to a view.
    ///
    /// `-screen document` used to construct `DocumentDetailView` around a
    /// detached fixture, because nothing could put a document in the store. That
    /// is what produced "DOCUMENT 1 OF 0" — the total came off `store.documents`
    /// while the document being drawn was not in it. There is a mutation now, so
    /// the route can use it.
    ///
    /// Idempotent, like `seedMoments`.
    @MainActor
    static func seedDocuments(into store: TripStore) {
        guard store.documents.isEmpty else { return }
        for document in sampleDocuments { store.addDocument(document) }
    }

    /// Pages for every day so far but a few, so the book has skipped nights,
    /// a night with no photograph (a page set in type), one photograph too
    /// small to print sharp, and everything else full size.
    ///
    /// The photographs are drawn rather than shipped: a horizon, a sun and a
    /// sky in each country's colours, square, at the size `PhotoStore` keeps.
    /// Idempotent, like the others.
    @MainActor
    /// `savedpostcard`: the seeded book, cut back from its oldest night until
    /// tonight's page is a multiple of seven — the night the saved page
    /// offers a postcard. Needs `-seedJournal`, which writes tonight.
    static func trimToAWeekOfPages(in store: TripStore) {
        guard store.myEntries.contains(where: { $0.dayNumber == store.dayNumber }) else { return }
        let mine = store.myEntries.sorted { $0.dayNumber < $1.dayNumber }
        let extra = mine.count % TripStore.postcardWeekLength
        guard extra > 0, mine.count > extra else { return }
        let dropping = Set(mine.prefix(extra).map(\.id))
        store.journal.removeAll { dropping.contains($0.id) }
    }

    @MainActor
    static func seedJournal(into store: TripStore) {
        guard store.myEntries.isEmpty, store.participant.traveller != nil else { return }
        let lines = [
            "Landed into a wall of warm air and didn't mind at all.",
            "Got lost twice, ate well three times.",
            "The river was louder than the traffic for once.",
            "A temple with nobody in it but a cat.",
            "Long bus, short tempers, good noodles at the end.",
            "Rain all afternoon. We read and said nothing. Perfect.",
            "Somebody's grandmother insisted on feeding us.",
            "Walked until the map stopped making sense.",
            "The night market, again, because why not.",
            "Tired in the good way."
        ]
        let skipped: Set<Int> = [5, 13, 21]
        let lastDay = min(store.dayNumber, store.dayCount)
        guard lastDay >= 1 else { return }
        for day in 1...lastDay where !skipped.contains(day) {
            var photoID: String?
            if day != 9 {
                // Day 17 comes off a small picture, so the print screen has a
                // soft photograph to name.
                let side: CGFloat = day == 17 ? 1_400 : CGFloat(PhotoStore.printLongEdge)
                photoID = PhotoStore.shared.save(seedPhotograph(day: day, side: side))
            }
            let tags = [["food"], ["tired", "proud"], [], ["quiet"], ["lost", "strangers"]][day % 5]
            // Day 4 is a contact sheet with a note, day 7 two photographs, and
            // day 10 the longest line under the longest note — the page the
            // note's limit is set for.
            var extras: [String] = []
            if day == 4 || day == 7 {
                for offset in 1...(day == 4 ? 2 : 1) {
                    if let id = PhotoStore.shared.save(seedPhotograph(day: day + offset * 3,
                                                                      side: CGFloat(PhotoStore.printLongEdge))) {
                        extras.append(id)
                    }
                }
            }
            var line = lines[day % lines.count]
            var note = ""
            if day == 4 {
                note = "We found the ferry by following a man with a bicycle and a crate of limes. He wasn't going to the ferry."
            }
            if day == 10 {
                line = String("The longest line anybody could write about a day that went on and on, and then on a bit more for good luck, ok".prefix(JournalEntry.lineLimit))
                note = String(repeating: "Somebody wrote a great deal more than one line tonight, which is allowed now. ", count: 4)
            }
            store.save(entry: JournalEntry(dayNumber: day, date: store.date(forDay: day),
                                           city: store.city(forDay: day),
                                           line: line, tags: tags,
                                           hasPhoto: photoID != nil, photoID: photoID,
                                           author: store.role, extraPhotoIDs: extras, note: note))
        }
    }

    /// Every seeded waypoint whose stop has begun, earned on its first day —
    /// so a book seeded on day 40 has a trail across two countries to draw,
    /// rather than the two stamps `seedWaypoints` earns for the trail's own
    /// screens.
    @MainActor
    static func earnWaypointsSoFar(in store: TripStore) {
        store.stamps = store.stamps.map { stamp in
            guard !stamp.earned, stamp.hasLocation,
                  let segment = store.segment(for: stamp), segment.startDay <= store.dayNumber
            else { return stamp }
            var earned = stamp
            earned.earnedOn = store.date(forDay: segment.startDay)
            return earned
        }
    }

    /// `-seedWorstPages` overwrites days 11 and 12 with the text the day
    /// page's proof covers: the longest line as one unbroken word under the
    /// longest note, and the longest line in emoji. Photographs what the
    /// checks only measure.
    @MainActor
    static func seedWorstPages(into store: TripStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedWorstPages") else { return }
        let pages: [(Int, String, String)] = [
            (11, String(repeating: "m", count: JournalEntry.lineLimit), String(repeating: "W", count: JournalEntry.noteLimit)),
            (12, String(repeating: "🏝", count: JournalEntry.lineLimit), "")
        ]
        for (day, line, note) in pages where day <= store.dayNumber {
            let existing = store.myEntries.first { $0.dayNumber == day }
            store.save(entry: JournalEntry(dayNumber: day, date: store.date(forDay: day),
                                           city: store.city(forDay: day), line: line, tags: ["food"],
                                           hasPhoto: existing?.photoID != nil, photoID: existing?.photoID,
                                           author: store.role, note: note))
        }
    }

    private static func seedPhotograph(day: Int, side: CGFloat) -> UIImage {
        let hue = CGFloat((day * 37) % 360) / 360
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            let sky = [UIColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1).cgColor,
                       UIColor(hue: hue, saturation: 0.55, brightness: 0.75, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side * 0.62), options: [])
            }
            UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 1, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: side * 0.58, y: side * 0.22, width: side * 0.18, height: side * 0.18))
            UIColor(hue: hue, saturation: 0.45, brightness: 0.35, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: side * 0.62, width: side, height: side * 0.38))
            UIColor(white: 1, alpha: 0.18).setFill()
            for band in 0..<6 {
                cg.fill(CGRect(x: 0, y: side * (0.66 + CGFloat(band) * 0.055), width: side, height: side * 0.008))
            }
        }
    }

    /// Both seeds, in the order that matters.
    ///
    /// After `applyDay`, so the day plan lands on the day `-day n` asked for
    /// rather than on the day the trip happened to open at.
    @MainActor
    static func seedTripIfAsked(into store: TripStore) {
        guard wantsItinerary else { return }
        seedItinerary(into: store)
        seedBudget(into: store)
        seedDayPlan(into: store)
    }

    /// Something between them.
    ///
    /// A blank trip's budget is nought, so without this the countdown's
    /// `packedSummary` drops its money clause on every seeded run and the
    /// ordinary three-clause sentence — the one a real trip shows — could not
    /// be photographed at all. €8,000 to match `CheckTrip`'s fixture, so the
    /// screenshots and the assertions are talking about the same trip.
    ///
    /// Guarded on nought rather than on the itinerary, so it never stomps a
    /// budget somebody typed in.
    @MainActor
    static func seedBudget(into store: TripStore) {
        guard store.budget == 0 else { return }
        store.budget = 8_000
    }

    /// Somewhere to be.
    ///
    /// Sixty nights against the blank trip's sixty-one days, so nothing runs
    /// past the return date — the overrun panel is its own state and shouldn't
    /// fire here by accident.
    ///
    /// "Ayutthaya · Pai" is deliberate. It is the stop that names two places,
    /// so the seed exercises `Segment.places` rather than only the easy
    /// single-word titles, and it is the pair that made AYU unreachable.
    ///
    /// Idempotent, like `seedMoments`.
    @MainActor
    static func seedItinerary(into store: TripStore) {
        guard store.legs.isEmpty else { return }
        let seeds: [(String, Currency, [(String, Int)])] = [
            ("Thailand", .thb, [("Bangkok", 4), ("Ayutthaya · Pai", 6),
                                ("Chiang Mai", 7), ("Chiang Rai", 5)]),
            ("Vietnam", .vnd, [("Huế", 6), ("Hội An", 7), ("Ho Chi Minh City", 7)]),
            ("South Korea", .krw, [("Seoul", 8), ("Busan", 6), ("Jeju", 4)])
        ]
        for (country, currency, stops) in seeds {
            guard let first = stops.first else { continue }
            guard store.addLeg(country: country, currency: currency,
                               firstStop: first.0, nights: first.1) != nil,
                  let legID = store.legs.last?.id else { continue }
            for stop in stops.dropFirst() {
                _ = store.addSegment(title: stop.0, nights: stop.1, toLeg: legID)
            }
        }
    }

    /// Hours on the day the trip is sitting on, so "Today together" has
    /// something to count and B3 isn't photographed empty every time.
    ///
    /// Guarded on the day rather than on the itinerary, so relaunching with a
    /// different `-day n` fills that day too.
    @MainActor
    static func seedDayPlan(into store: TripStore) {
        let day = store.dayNumber
        guard store.plan(forDay: day) == nil else { return }
        store.setBlurb("Slow start, then the long way round to the river.", forDay: day)
        store.setOccasion("Market day", forDay: day)
        store.setLodging(title: "The guesthouse with the blue door",
                         note: "Second floor, the room at the back", forDay: day)
        let hours: [(String, String, String)] = [
            ("08:30", "Coffee at the corner", "The one that opens early"),
            ("11:00", "The old town on foot", ""),
            ("15:30", "Back indoors for the heat", ""),
            ("19:00", "Dinner at the night market", "Cash only")
        ]
        for (time, title, note) in hours {
            _ = store.addItem(time: time, title: title, note: note, toDay: day)
        }
    }

    /// Everything a fresh install wouldn't have.
    ///
    /// The letter drop and the shelf have to go too, or a reset trip isn't a
    /// first launch — letters left in the drop are collected back onto the
    /// empty trip on the next wake.
    static func reset() {
        // Through `Storage`, not `UserDefaults.standard`: they were the same
        // thing, and the seam is what let that change — the trip and the shelf
        // are protected files now.
        //
        // And through `Storage.appKeys` and `forget(_:)`, not four string
        // literals and a `removeObject` written out again down here. See the
        // notes on both: this file isn't compiled by `run-checks.sh`, so a list
        // kept here is a list nothing can check, and a reset that knows *where*
        // each key lives is one that stops working the next time one moves.
        for key in Storage.appKeys { Storage.forget(key) }
        // The widget lives in another process and another container, so
        // without this a reset trip keeps drawing the last run's day on the
        // Home Screen.
        WidgetSnapshot.clear(from: Storage.shared)
        reloadWidgetTimelines()
        LoopbackSyncTransport().erase()
        LoopbackLetterDropTransport().erase()
        // Photos and scans too, or a "reset trip" is a first launch with the
        // last run's pictures still in it. Both through the object that owns the
        // folder — the scans used to be a path literal written out here, which
        // is the same failure `Storage.appKeys` exists to prevent one layer up:
        // rename the directory and this goes on faithfully clearing the old one.
        PhotoStore.shared.eraseAll()
        ScanVault.shared.eraseAll()
    }
}

/// What `RootView` draws once a trip is closed: the shelf, in place of the
/// tabs, with the trip that was just closed landing on it.
///
/// Everything is prepared *before* the shelf is drawn: named, opened,
/// seeded and closed. The shelf takes its landing on appear, and a child's
/// `onAppear` fires before its host's, so a shelf drawn straight away would
/// look for the landing before any trip had been closed. `-seedItinerary`
/// adds located waypoints and moments, so every clause of the "put away today"
/// line is on screen. `-settled` takes the landing first, for the shelf as it
/// looks on any later visit. The host re-runs its seeders afterwards, and
/// every one of them is idempotent.
private struct BetweenPreview: View {
    @EnvironmentObject private var store: TripStore
    @State private var ready = false

    var body: some View {
        if ready {
            NavigationStack { ShelfView() }
        } else {
            Palette.bg.onAppear {
                DebugScreen.seedShelf(into: store)
                DebugScreen.nameTheTravellers(in: store)
                if store.isLive {
                    DebugScreen.applyDay(to: store)
                    DebugScreen.seedTripIfAsked(into: store)
                    if DebugScreen.wantsItinerary {
                        DebugScreen.seedWaypoints(into: store)
                        DebugScreen.seedMoments(into: store)
                    }
                    if DebugScreen.wantsPlan { DebugScreen.seedPlan(into: store) }
                    // Opened first, as every trip the UI can finish is. A
                    // plain launch afterwards then lands on `RootView`'s
                    // between-trips branch rather than on onboarding.
                    store.hasOpened = true
                    store.closeTrip()
                }
                if ProcessInfo.processInfo.arguments.contains("-settled") {
                    _ = store.takeJustShelved()
                }
                ready = true
            }
        }
    }
}

/// Runs `BookPDF.write` and reports what it made, in words and on stdout.
private struct ExportProbe: View {
    @EnvironmentObject private var store: TripStore
    let cancelAt: Double?
    @State private var report = "Building…"
    @State private var progressSeen: [Double] = []

    var body: some View {
        Text(report)
            .font(Typeface.mono(12))
            .padding()
            .task {
                // After the host's seeding, which runs in `onAppear`.
                try? await Task.sleep(for: .seconds(2))
                let started = Date()
                let job = Task { @MainActor in
                    await BookPDF.write(plan: store.bookPlan, store: store, baseName: "probe") { fraction in
                        progressSeen.append(fraction)
                        report = "Building \(Int(fraction * 100))%"
                    }
                }
                if let cancelAt {
                    while (progressSeen.last ?? 0) < cancelAt { try? await Task.sleep(for: .milliseconds(20)) }
                    job.cancel()
                }
                let urls = await job.value ?? []
                // Every cover style beside the export, to compare them.
                if let spec = CoverSpec(pages: store.bookPlan.pageCount) {
                    for style in CoverStyle.allCases {
                        _ = BookPDF.writeCover(spec, store: store,
                                               to: Storage.exportDirectory.appendingPathComponent("cover-\(style.rawValue).pdf"),
                                               style: style)
                    }
                }
                let left = (try? FileManager.default.contentsOfDirectory(atPath: Storage.exportDirectory.path)) ?? []
                report = """
                files: \(urls.map(\.lastPathComponent))
                progress updates: \(progressSeen.count)
                seconds: \(Int(Date().timeIntervalSince(started)))
                left in export dir: \(left)
                dir: \(Storage.exportDirectory.path)
                """
                print("EXPORTPROBE\n" + report)
            }
    }
}

/// The plan sheet over a live trip, with a plan in it. Built before it is
/// drawn, because `PlanTripView` takes its store at `init`.
private struct PlanPreview: View {
    @EnvironmentObject private var store: TripStore
    @State private var sketch: TripStore?

    var body: some View {
        if let sketch {
            PlanTripView(plan: sketch)
        } else {
            Palette.bg.onAppear {
                DebugScreen.seedShelf(into: store)
                DebugScreen.nameTheTravellers(in: store)
                DebugScreen.seedPlan(into: store)
                sketch = store.openPlan()
            }
        }
    }
}

/// `ArrivalFlow` as it opens after "Start the next trip": a trip closed, then
/// `beginNextTrip`. Held back until that has happened, because the flow reads
/// the role and the names on appear, and a child's `onAppear` fires before its
/// host's.
///
/// The last trip had a budget and two show-this cards, so "Coming along" has
/// rows to decline — a blank trip carries nothing worth listing, and the
/// route would photograph the list with only the switches in it.
/// `atDates` opens on the name-and-dates step with a country already in,
/// which is what draws the growing spine and the suggested name.
private struct NextTripPreview: View {
    @EnvironmentObject private var store: TripStore
    var atDates = false
    @State private var ready = false

    var body: some View {
        if ready {
            ArrivalFlow(startAt: atDates ? 1 : 0, returning: true)
        } else {
            Palette.bg.onAppear {
                DebugScreen.seedShelf(into: store)
                DebugScreen.nameTheTravellers(in: store)
                if store.isLive {
                    if store.budget == 0 { store.budget = 4_200 }
                    if store.showCards.isEmpty {
                        _ = store.addShowCard(native: "Tôi bị dị ứng đậu phộng",
                                              english: "I am allergic to peanuts",
                                              shortName: "Peanut allergy")
                        _ = store.addShowCard(native: "Xin đưa tôi đến bệnh viện",
                                              english: "Please take me to a hospital",
                                              shortName: "Hospital")
                    }
                    // `-planned`: the next trip starts from a sketch, so the
                    // destination step opens on the plan's countries.
                    if DebugScreen.wantsPlan { DebugScreen.seedPlan(into: store) }
                    store.hasOpened = true
                    store.closeTrip()
                }
                store.beginNextTrip()
                if atDates, store.legs.isEmpty {
                    _ = store.addLeg(country: "Vietnam", currency: .vnd,
                                     firstStop: "Hội An", nights: 7)
                }
                ready = true
            }
        }
    }
}

struct DebugScreenHost: View {
    @EnvironmentObject private var store: TripStore
    let id: String

    /// A draft to photograph the composer with. Reuses one if it's already
    /// there, so relaunching doesn't leave a pile of empty letters behind.
    private var composeDraft: Letter {
        store.writerDrafts.first
            ?? store.startLetter(title: "On being tired of each other", condition: .day(44))
    }

    var body: some View {
        screen.onAppear {
            DebugScreen.applyDay(to: store)
            DebugScreen.seedTripIfAsked(into: store)
            if ["moments", "momentslist", "trailmap", "nudge", "stamp", "stampletters", "printfile",
                "replay", "ending", "entry", "editororphan", "placestamp"].contains(id) {
                if DebugScreen.wantsItinerary { DebugScreen.seedWaypoints(into: store) }
                DebugScreen.seedMoments(into: store)
            }
            // A stamp whose stop went in a merge: the stop is taken out of the
            // document directly, the way a merged itinerary would arrive,
            // rather than through `removeSegment`, which takes its stamps.
            if ["editororphan", "placestamp"].contains(id),
               let hue = store.itinerary.allSegments.first(where: { $0.title == "Huế" }) {
                store.itinerary.removeSegment(hue.id)
            }
            if DebugScreen.wantsSpending { DebugScreen.seedSpending(into: store) }
            if DebugScreen.wantsLetters { DebugScreen.seedLetters(into: store) }
            if DebugScreen.wantsNoBudget { store.budget = 0 }
            if DebugScreen.wantsJournal {
                DebugScreen.nameTheTravellers(in: store)
                if DebugScreen.wantsItinerary { DebugScreen.seedWaypoints(into: store) }
                DebugScreen.seedMoments(into: store)
                DebugScreen.seedJournal(into: store)
                DebugScreen.seedMeetingPlaces(into: store)
                DebugScreen.seedOpenerMoment(into: store)
                DebugScreen.seedWorstPages(into: store)
                DebugScreen.earnWaypointsSoFar(in: store)
                if id == "savedpostcard" {
                    DebugScreen.trimToAWeekOfPages(in: store)
                }
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch id {
        case "arrival1":
            FirstOpenView {}
        case "arrival":
            // The whole flow, opened at a step — `-screen arrival -step 2`.
            // The steps below are photographed standalone, which can't show
            // what the chrome around them is missing.
            ArrivalFlow(startAt: DebugScreen.value(for: "-step").flatMap(Int.init) ?? 0)
        case "who":
            // The role picker and the name fields are one screen, so `-screen
            // names` is gone with the step it photographed.
            WhosePhoneView(participant: .constant(.one),
                           mine: .constant(""), theirs: .constant(""),
                           onChange: { _ in }, onContinue: {})
        case "writingto":
            WritingToView(recipient: .constant(.two)) {}
        case "widget":
            WidgetGallery()
        case "today":
            // B1 as itself, without walking onboarding to reach it.
            MainTabs(initialTab: .today)
        case "todayother":
            // G1 · the traveller the letters aren't for. `adopt` is what empties
            // the letterbox, so this is the real state and not a hidden one.
            MainTabs(initialTab: .today)
                .onAppear { store.adopt(.two) }
        case "arrival2":
            WhatsInsideView(onAdjust: {}) {}
        case "arrival2observer":
            // The observer's manifest is three rows, and which three depends on
            // the store rather than on a flag the view was handed.
            WhatsInsideView {}
                .onAppear { store.participant = .writer }
        case "firststop":
            FirstStopView(onPlan: {}, onStart: {})
        case "setup":
            TripSetupView(mode: .onboarding) {}
        case "adjust":
            NavigationStack { TripSetupView(mode: .adjust) {} }
        case "settings":
            NavigationStack { TripSetupView() }
        case "itinerary":
            NavigationStack { ItineraryView() }
        case "editor", "editororphan":
            ItineraryEditorView()
        case "countryedit", "renamestop", "addstop":
            // Each needs something to edit; an empty trip gets the editor.
            if let leg = store.legs.first, let stop = leg.segments.first {
                switch id {
                case "countryedit": CountryEditorView(leg: leg)
                case "renamestop": RenameStopView(segment: stop)
                default: AddStopView(leg: leg, initialTitle: "Chiang Rai")
                }
            } else {
                ItineraryEditorView()
            }
        case "placestamp":
            if let stamp = store.orphanedWaypoints.first {
                PlaceStampView(stamp: stamp)
            } else {
                ItineraryEditorView()
            }
        case "day":
            // Needs a stop to be a day *of*, so an empty trip gets the
            // itinerary editor instead of a crash.
            if let segment = store.currentSegment ?? store.legs.first?.segments.first {
                NavigationStack { DayDetailView(day: store.dayNumber, segment: segment) }
            } else {
                ItineraryEditorView()
            }
        case "dayplan":
            // The editor for the day `-day n` put the trip on. Standalone,
            // because the only other way in is a tap on B3.
            DayPlanEditorView(day: store.dayNumber, city: store.currentCity)
        case "letters":
            NavigationStack { LettersView() }
        case "letter":
            // Every route below that reads a record by index falls back to the
            // list it lives on, because the app ships with no trip inside it
            // and an index into an empty collection is a crash rather than an
            // empty screenshot.
            if let letter = store.newestOpenLetter ?? store.letters.first {
                LetterReaderView(letter: letter)
            } else {
                NavigationStack { LettersView() }
            }
        case "stamp", "stampletters":
            // `stampletters` is the arrival that opened two at once, which is
            // the other shape the panel takes: needs `-seedLetters`.
            if let stamp = store.stamps.first(where: { $0.index == 7 }) ?? store.stamps.first {
                StampEarnedView(stamp: stamp,
                                unlockedLetters: id == "stampletters"
                                    ? Array(store.letters.prefix(2))
                                    : store.letters.filter { $0.number == stamp.unlocksLetter },
                                onReadLetter: { _ in },
                                onKeepMoment: { _ in })
            } else {
                NavigationStack { TrailView() }
            }
        case "moment":
            // The composer, standalone. Its three states are "no position yet",
            // "the phone has one" and "a photo is attached", and only the
            // simulator's location setting moves between the first two.
            MomentComposerView()
        case "moments":
            // A trail with moments on it. `-resetTrip` leaves none — a screen
            // whose whole subject is user-created records has nothing to
            // photograph unless something creates them.
            // Seeded in `body` after the day and the itinerary, not here: a
            // child's `onAppear` fires first, which filed every moment on a
            // blank trip's day 1 whatever `-day` and `-seedItinerary` said.
            NavigationStack { TrailView() }
        case "nudge":
            // Today with the next stop inside the arrival radius. Needs the
            // simulator's location set near Chiang Mai (CNX is next once BKK
            // and AYU are seeded as earned) and location already granted —
            // the nudge never asks.
            MainTabs()
        case "trailmap":
            // The full-screen trail with the first stamp's card up, so the
            // card is photographed rather than the prompt every time.
            NavigationStack {
                TrailMapView(initialSelection: store.orderedStamps.first.map { .stamp($0.id) })
            }
        case "momentslist":
            // Every moment, past the three the trail lists.
            NavigationStack { MomentsView() }
        case "addexpense":
            AddExpenseView()
        case "settle":
            SettleUpView()
        case "entry":
            // `-entryDay n` writes that night instead of tonight — a missed
            // one, with two photographed moments kept on it, so the strip
            // that fills the extra photographs has something to fill them
            // from. Nothing else seeds a moment with a photograph.
            if let day = DebugScreen.value(for: "-entryDay").flatMap(Int.init) {
                TonightEntryView(day: day)
                    .onAppear { DebugScreen.seedPhotographedMoments(onDay: day, into: store) }
            } else {
                TonightEntryView()
            }
        case "meetingpoint":
            MeetingPointPicker()
        case "document":
            // Seeded into the store rather than handed to the view.
            //
            // It used to construct the screen around a fixture the store had
            // never heard of, because nothing could put a document in there —
            // which is what drew "DOCUMENT 1 OF 0", since the total came off
            // `store.documents` while the document did not. There is a mutation
            // now, so the route uses it and the two agree by construction.
            NavigationStack {
                if let document = store.documents.first {
                    DocumentDetailView(documentID: document.id, index: 0)
                } else {
                    PapersView(showingSeparated: .constant(false))
                }
            }
            .onAppear { DebugScreen.seedDocuments(into: store) }
        case "documents":
            // Papers with papers in it — the list, the badges and the add
            // control, which is the branch the empty state hides.
            NavigationStack { PapersView(showingSeparated: .constant(false)) }
                .onAppear { DebugScreen.seedDocuments(into: store) }
        case "documentedit":
            // New rather than edit: the blank editor is where the badge chips
            // and the first field row are, and it is the screen somebody meets
            // before they have typed anything.
            DocumentEditorView(editing: nil)
        case "documentfull":
            DocumentEditorView(editing: DebugScreen.sampleDocument)
        case "documentclosed":
            // A trip that has been shelved: values cleared, scans gone, labels
            // still there. The one state that can only be reached by doing
            // something irreversible, so it would otherwise never be looked at.
            NavigationStack {
                if let document = store.documents.first {
                    DocumentDetailView(documentID: document.id, index: 0)
                } else {
                    PapersView(showingSeparated: .constant(false))
                }
            }
            .onAppear {
                DebugScreen.seedDocuments(into: store)
                store.closeTrip()
            }
        case "showthis":
            ShowThisView()
        case "showcards":
            ShowCardsView()
        case "showcard":
            // New rather than edit: it is the branch with the language label on
            // an empty field, which is the half `-day n` can move.
            ShowCardEditorView()
        case "papers":
            // Its own route at last. Papers is a whole tab and could only be
            // reached by two *fallbacks* — `-screen document` on a trip with no
            // documents, and `-screen country` in a country the app can't speak
            // for — so the screen you got was never the screen you asked for,
            // and the one branch worth checking here (no meeting point agreed)
            // could only be reached by accident.
            NavigationStack { PapersView(showingSeparated: .constant(false)) }
        case "separated":
            SeparatedView()
        case "country":
            // Straight to the card, because reaching it otherwise is Papers,
            // a scroll and a tap — and it is the one new screen whose risk is
            // entirely typographic. `-day n` moves which country it draws.
            if let facts = CountryFacts.lookup(store.currentCountry) {
                NavigationStack { CountryCardView(facts: facts) }
            } else {
                // The honest branch: a leg the app can't speak for has no card,
                // and Papers draws no row. Worth being able to photograph.
                NavigationStack { PapersView(showingSeparated: .constant(false)) }
            }
        case "sharing":
            NavigationStack { SharingSettingsView() }
        case "invite":
            // Onboarding's last step, which is otherwise reachable only by
            // walking the whole flow on a build with CloudKit on — and it is
            // the step that decides whether two people end up on one trip or
            // two, so it is worth being able to look at.
            InviteStepView {}
        case "join":
            // Otherwise unreachable: the only way in is a real `CKShare` link,
            // which needs a paid team, two iCloud accounts and a second phone.
            // A screen nothing can reach is a screen nothing checks — Today's
            // `notYet` branch had never been photographed for exactly this
            // reason — and this one is a confirmation for the single
            // irreversible act in the app that isn't closing a trip.
            //
            JoinTripView(invitation: CloudKitSyncTransport.Invitation(
                tripID: UUID(), slot: .two, title: "Somewhere warm"))
        case "joinasking":
            // The other branch: an invitation that doesn't say which slot the
            // joiner takes, so the picker is drawn and the answer is asked for
            // rather than guessed. Both phones defaulting to `.one` is the bug
            // the field exists to prevent.
            JoinTripView(invitation: CloudKitSyncTransport.Invitation(
                tripID: UUID(), slot: nil, title: "Somewhere warm"))
        // Phase 2
        case "book":
            // The journal list. It had no route at all, so the one screen that
            // draws a page's photograph as a *thumbnail* could only be reached
            // by walking onboarding — and a screen nothing can reach is a
            // screen nothing checks.
            NavigationStack { BookView() }
        case "bookpreview":
            // `-spread n` opens on that spread, since turning to one takes taps.
            NavigationStack {
                BookPreviewView(startAt: DebugScreen.value(for: "-spread").flatMap(Int.init) ?? 0,
                                holdingScrubAt: DebugScreen.value(for: "-scrubDay").flatMap(Int.init))
            }
        case "printfile":
            PrintFileView()
        case "exportbook":
            // The writer, run without the share sheet in front of it, so the
            // file can be pulled off the simulator and opened two pages up.
            // `-cancelAt 0.3` stops it partway, which is the half of the
            // progress button nobody can tap fast enough to check.
            ExportProbe(cancelAt: DebugScreen.value(for: "-cancelAt").flatMap(Double.init))
        case "ending":
            TripEndingView()
        case "savedpostcard":
            // The saved page on the night the book reaches another seven,
            // which is the only time it offers a postcard.
            // `-seedItinerary -seedJournal -day 14`.
            if let entry = store.myEntries.first(where: { $0.dayNumber == store.dayNumber }) {
                SavedPageView(entry: entry, pageNumber: store.bookPage(forDay: entry.dayNumber), minutes: 3) {}
            } else {
                TonightEntryView()
            }
        case "postcard":
            // The postcard sheet, opened on `-week n`, from the Book tab's
            // side — every week offered.
            PostcardPicker(week: DebugScreen.value(for: "-week").flatMap(Int.init)
                               ?? store.postcardWeek(forDay: store.dayNumber),
                           switchesWeeks: true)
        case "exportpostcard":
            // The image the sheet saves, written to the export directory
            // without Photos in front of it, so it can be pulled off the
            // simulator and checked for metadata.
            PostcardProbe(week: DebugScreen.value(for: "-week").flatMap(Int.init)
                              ?? store.postcardWeek(forDay: store.dayNumber))
        case "saved":
            if let entry = store.myEntries.first {
                SavedPageView(entry: entry, pageNumber: store.bookPage(forDay: entry.dayNumber), minutes: 2) {}
            } else {
                TonightEntryView()
            }
        // Every one of these is a home-mode screen, and home mode is a *store*
        // state, not a view. Without `participant = .writer` they drew as though
        // a traveller were holding the phone — which was invisible for as long
        // as nothing on them branched on it, and stopped being invisible the
        // moment the letters learned to say whether they had been posted.
        case "home":
            HomeTabs().onAppear { store.participant = .writer }
        case "compose":
            ComposeLetterView(letterID: composeDraft.id)
                .onAppear { store.participant = .writer }
        case "condition":
            ConditionPickerView(number: store.nextLetterNumber, selected: .day(44)) { _ in }
        case "sealedletter":
            if let id = store.sealedByWriter.first?.id ?? store.letters.first?.id {
                SealedConfirmationView(letterID: id) {}
                    .onAppear { store.participant = .writer }
            } else {
                LetterBoardView().onAppear { store.participant = .writer }
            }
        case "board":
            LetterBoardView().onAppear { store.participant = .writer }
        case "handover":
            HandoverView().onAppear { store.participant = .writer }
        case "undelivered":
            UndeliveredView().onAppear { store.participant = .writer }
        case "shelf":
            NavigationStack { ShelfView() }
                .onAppear {
                    DebugScreen.seedShelf(into: store)
                    if DebugScreen.wantsPlan {
                        DebugScreen.nameTheTravellers(in: store)
                        DebugScreen.seedPlan(into: store)
                    }
                }
        case "plan":
            PlanPreview()
        case "memory":
            // Today with "A year ago today" on it, from a seeded shelf.
            TodayView()
                .onAppear { DebugScreen.seedShelf(into: store) }
        case "reader":
            // The full-size book, at `-spread n`. A full-screen cover is a
            // tap the simulator can't make, so the route is the reader itself.
            ReaderRoute(start: DebugScreen.value(for: "-spread").flatMap(Int.init) ?? 0)
        case "memorybook":
            // What tapping that panel opens: the old trip's book, at the page
            // the memory came from. A tap the simulator can't make.
            MemoryBookRoute()
        case "replay":
            // Held at `-replayDay N` (default: halfway), so a frame can be
            // photographed without racing the timer.
            NavigationStack {
                Screen {
                    TrailReplayView(holdAtDay: DebugScreen.value(for: "-replayDay").flatMap(Int.init)
                                    ?? store.dayCount / 2)
                }
            }
        case "finish":
            // Seeded, because the line worth looking at on this screen is the
            // one that only exists when there is something to lose: shelving
            // empties the papers, and `papersLostOnClose` is nil on a reset
            // trip. Without this the route photographs the branch where the
            // sentence isn't there — which is how a screen with a conditional
            // warning on it gets signed off having never shown the warning.
            FinishTripView()
                .onAppear { DebugScreen.seedDocuments(into: store) }
        case "between":
            BetweenPreview()
        case "nexttrip":
            NextTripPreview()
        case "nexttripdates":
            NextTripPreview(atDates: true)
        case "archived":
            // A real encoded snapshot, not `Data()` — the screen now opens what
            // it is handed, so an undecodable blob photographs the "couldn't be
            // read" branch rather than the trip.
            ArchivedTripView(trip: store.library.byRecency.first
                             ?? ShelvedTrip(summary: store.summary,
                                            snapshot: (try? JSONEncoder().encode(store.snapshot)) ?? Data()))
        default:
            MainTabs(initialTab: Tab(rawValue: id) ?? .today)
        }
    }
}
/// `-screen reader`: the reader on a given spread, holding the id it hands back.
private struct ReaderRoute: View {
    @EnvironmentObject private var store: TripStore
    let start: Int
    @State private var spreadID: String?
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                BookReaderView(spreadID: $spreadID)
            } else {
                Palette.bg
            }
        }
        // After the host's seeding, which runs in its own `onAppear` once this
        // one has: the plan has to exist before a spread can be chosen.
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            let spreads = store.bookPlan.spreads
            spreadID = spreads.indices.contains(start) ? spreads[start].id : spreads.first?.id
            ready = true
        }
    }
}

/// `-screen memorybook`: seeds the shelf, then opens its first memory the way
/// the panel's tap does.
private struct MemoryBookRoute: View {
    @EnvironmentObject private var store: TripStore
    @State private var opening: MemoryOpening?

    var body: some View {
        Group {
            if let opening {
                MemoryBookView(opening: opening)
            } else {
                Palette.bg
            }
        }
        .onAppear {
            DebugScreen.seedShelf(into: store)
            if let first = store.library.memories(on: store.now).first,
               let trip = store.library.trip(first.tripID) {
                opening = MemoryOpening(trip: trip, memory: first)
            }
        }
    }
}

/// `-screen exportpostcard`: renders the week's first postcard to
/// `Storage.exportDirectory` and prints where it went.
private struct PostcardProbe: View {
    @EnvironmentObject private var store: TripStore
    let week: Int
    @State private var report = "drawing…"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Mono("Postcard · week \(week)", size: 10.5)
            Text(report).font(Typeface.body(13)).foregroundStyle(Palette.text)
            Spacer()
        }
        .padding(Space.gutter)
        .task {
            // After the host's seeding, which runs in its own `onAppear`.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let index = store.postcardSpreads(week: week).first,
                  let png = PostcardView.png(week: week, spreadIndex: index, store: store) else {
                report = "no page in week \(week)"
                print("postcard: no page in week \(week)")
                return
            }
            let url = Storage.exportDirectory.appendingPathComponent("postcard-week-\(week).png")
            do {
                try png.write(to: url)
                report = "\(png.count) bytes\n\(url.path)"
                print("postcard: \(png.count) bytes at \(url.path)")
            } catch {
                report = "failed: \(error)"
            }
        }
    }
}


#endif

