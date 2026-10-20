import Foundation

/// The trip the model checks run against.
///
/// It lives in `Tools/` rather than in `DiThoi/Model/`, so it is compiled by
/// `run-checks.sh` and by nothing else — the app itself ships with no trip
/// inside it and seeds a blank one on a first launch.
///
/// Nothing here holds a calendar date. Every record is anchored to a trip-day
/// offset and materialised against a start date passed in, so a check can move
/// the trip around the calendar and expect the shape to follow.
enum CheckTrip {

    // MARK: - Defaults

    /// Eleven days back, so the trip opens on day 12 — far enough in to have a
    /// ledger, a journal and earned stamps behind it, and far enough from the
    /// end to still have unearned ones ahead.
    /// - Parameter now: taken rather than read from the clock, so a store built
    ///   with an injected clock builds against *its* today.
    static func defaultStart(now: Date = Date()) -> Date {
        let today = Calendar.trip.startOfDay(for: now)
        return Calendar.trip.date(byAdding: .day, value: -11, to: today) ?? today
    }

    /// Fixed, so two stores built from this fixture agree on which trip they
    /// are on before either has synced anything.
    static let defaultTripID = UUID(uuidString: "D1D17401-0000-4000-A000-000000000001")!
    static let defaultTripName = "Two months"

    static let defaultDayCount = 61
    static let defaultHomeCurrency: Currency = .eur
    static let defaultBudget: Double = 8_000

    /// Which slot the letters are addressed to. `adopt(_:)` deletes them if the
    /// phone turns out to be the other one, which is the behaviour under test.
    static let letterRecipient: Traveller = .one

    /// Names for the two slots, so check output reads as sentences.
    static let names = TripNames(one: StampedName(value: "Alex", updatedAt: .distantPast),
                                 two: StampedName(value: "Sam", updatedAt: .distantPast),
                                 observer: "Home")

    /// Materialises a trip day into a real moment.
    static func date(day: Int, hour: Int = 12, minute: Int = 0, start: Date) -> Date {
        let midnight = Calendar.trip.date(byAdding: .day, value: day - 1,
                                          to: Calendar.trip.startOfDay(for: start)) ?? start
        return Calendar.trip.date(byAdding: DateComponents(hour: hour, minute: minute),
                                  to: midnight) ?? midnight
    }

    // MARK: - The whole trip, as one value

    /// A full trip, ready to hand to `TripStore(snapshot:)`.
    static func snapshot(now: Date = Date()) -> TripSnapshot {
        let start = defaultStart(now: now)
        return TripSnapshot(
            tripID: defaultTripID,
            tripName: defaultTripName,
            participant: Participant(letterRecipient),
            names: names,
            origin: .packed,
            features: TripTemplate.someonesLeaving.features,
            template: .someonesLeaving,
            closedOn: nil,
            hasOpened: false,
            role: letterRecipient,
            start: start,
            dayCount: defaultDayCount,
            budget: defaultBudget,
            homeCurrency: defaultHomeCurrency,
            settingsUpdatedAt: .distantPast,
            itinerary: ItineraryDocument(legs: legs),
            expenses: expenses(start: start),
            stamps: stamps(start: start),
            meetingPoint: StampedMeetingPoint(value: meetingPoint(start: start),
                                              updatedAt: .distantPast, setBy: .one),
            meetingPlaces: [],
            settlements: [],
            journal: journal(start: start),
            moments: [],
            letters: letters(start: start),
            // The fixture is a traveller's phone, and its letters were addressed
            // to the slot it is. Same value `participant` carries, which is
            // exactly what a phone that has not changed hands looks like.
            lettersBelongTo: Participant(letterRecipient),
            // No key. A packed trip is one nobody has synced yet, and the
            // keyring is filled in by the first round — which is exactly the
            // state `post` has to refuse rather than send in clear.
            letterKeys: .blank,
            separatedSince: nil,
            ritualClock: RitualClock(),
            backfill: BackfillOffers(),
            dayPlans: dayPlans,
            documents: documents,
            showCards: showCards,
            sharingRules: sharingRules
        )
    }

    // MARK: - Itinerary

    /// Day offsets, not dates. 20 + 26 + 14 = 60 nights, so day 61 is the last
    /// morning.
    static var legs: [Leg] {
        [
            Leg(country: "Thailand", currency: .thb, segments: [
                Segment(title: "Bangkok", startDay: 1, endDay: 5),
                Segment(title: "Ayutthaya · Pai", startDay: 5, endDay: 9),
                Segment(title: "Chiang Mai · Songkran", startDay: 9, endDay: 17),
                Segment(title: "Chiang Rai", startDay: 17, endDay: 21)
            ]),
            Leg(country: "Vietnam", currency: .vnd, segments: [
                Segment(title: "Hanoi · Hà Giang loop", startDay: 21, endDay: 32),
                Segment(title: "Hội An · Đà Nẵng", startDay: 32, endDay: 41),
                Segment(title: "Sài Gòn · Mekong", startDay: 41, endDay: 47)
            ]),
            Leg(country: "South Korea", currency: .krw, segments: [
                Segment(title: "Seoul", startDay: 47, endDay: 55),
                Segment(title: "Busan", startDay: 55, endDay: 58),
                Segment(title: "Jeju", startDay: 58, endDay: 61)
            ])
        ]
    }

    // MARK: - Day plans

    /// Three, deliberately out of day order, so the checks exercise the sort
    /// rather than the array's own order.
    static var dayPlans: [DayPlan] {
        [
            DayPlan(
                dayNumber: 12,
                city: "Chiang Mai",
                occasion: "Songkran",
                blurb: "Water fight from dawn. Walk the moat anticlockwise and you reach the east gate around dusk.",
                items: [
                    PlanItem(time: "07:30", title: "Breakfast at the corner shophouse", note: "Closes at 2pm. Cash only."),
                    PlanItem(time: "10:00", title: "Buy water guns", note: "Dry bag for the phones."),
                    PlanItem(time: "12:00", title: "The moat, anticlockwise", note: "Soaked within the minute."),
                    PlanItem(time: "19:00", title: "Tha Phae Gate", note: "Loud. Agree a meeting point first.")
                ],
                lodgingTitle: "Guesthouse · booking 4471",
                lodgingNote: "Address card ready in Thai · 8 min walk from the gate"
            ),
            DayPlan(
                dayNumber: 13,
                city: "Chiang Mai",
                occasion: "Songkran",
                blurb: "Day two of the water. Quieter in the morning, busiest by three.",
                items: [
                    PlanItem(time: "06:40", title: "Wat Phra Singh, early", note: "Before the street wakes up. Shoulders covered."),
                    PlanItem(time: "11:00", title: "Dry hour at the market", note: "Everything under cover."),
                    PlanItem(time: "15:00", title: "Back out", note: "The Nimman end is calmer.")
                ],
                lodgingTitle: "Guesthouse · booking 4471",
                lodgingNote: "Same room, two more nights"
            ),
            DayPlan(
                dayNumber: 11,
                city: "Pai",
                occasion: nil,
                blurb: "Last morning in the valley. The road down is 762 curves.",
                items: [
                    PlanItem(time: "08:00", title: "Coffee at the bridge", note: "Fog burns off around nine."),
                    PlanItem(time: "11:30", title: "Minibus to Chiang Mai", note: "Sit at the front."),
                    PlanItem(time: "16:00", title: "Check in", note: "Old teak house. Room off the courtyard.")
                ],
                lodgingTitle: "Guesthouse · booking 4471",
                lodgingNote: "First of four nights"
            )
        ]
    }

    // MARK: - Letters

    /// Twelve, all sealed: a letter on a traveller's phone was sealed before
    /// they left, which is what it means for it to be there at all.
    static func letters(start: Date) -> [Letter] {
        drafted(start: start).map { letter in
            var sealed = letter
            sealed.sealedAt = letter.writtenOn
            return sealed
        }
    }

    /// Seven with a visible condition, four with a secret one, and one on the
    /// final stamp — enough shapes for the gating checks to have something to
    /// disagree about.
    private static func drafted(start: Date) -> [Letter] {
        func written(_ day: Int) -> Date { date(day: day, hour: 21, start: start) }
        func opened(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            date(day: day, hour: hour, minute: minute, start: start)
        }

        return [
            Letter(number: 1, title: "Before you take off", writtenOn: written(-14),
                   condition: .place("Bangkok"), hint: "when the wheels are down",
                   openedPlace: "Bangkok", openedOn: opened(1, 18, 20),
                   paragraphs: ["First one. Eat something before the train."],
                   signature: "— me"),
            Letter(number: 2, title: "The one about the tuk-tuk", writtenOn: written(-12),
                   condition: .place("Ayutthaya"), hint: "when the ruins turn up",
                   openedPlace: "Ayutthaya", openedOn: opened(5, 11, 5),
                   paragraphs: ["Agree the fare first. Then let it go."],
                   signature: "— me"),
            Letter(number: 3, title: "On sleeping badly", writtenOn: written(-9),
                   condition: .place("Pai"), hint: "when the valley gets quiet",
                   openedPlace: "Pai", openedOn: opened(8, 22, 40),
                   paragraphs: ["Around week two the novelty runs out for a night. It passes."],
                   signature: "— me"),
            Letter(number: 4, title: "Get completely soaked", writtenOn: written(-7),
                   condition: .place("Chiang Mai"), hint: "when the water starts",
                   openedPlace: "Chiang Mai", openedOn: opened(9, 17, 2),
                   paragraphs: ["Phone in the bag. Buy the expensive water gun."],
                   signature: "— me"),
            Letter(number: 5, title: "Opens in Hanoi", writtenOn: written(-6),
                   condition: .place("Hanoi"), hint: "when you land, whenever that is",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Second country. Walk into the traffic slowly and it goes around you."],
                   signature: "— me"),
            Letter(number: 6, title: "Opens somewhere on water", writtenOn: written(-5),
                   condition: .place("Hội An"), hint: "you'll know it when you're there",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Halfway is behind you. The second half goes faster."],
                   signature: "— me"),
            Letter(number: 7, title: "Opens on day 30", writtenOn: written(-4),
                   condition: .day(30), hint: "halfway",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Thirty days. From here every one is a day closer."],
                   signature: "— me"),
            // Four sealed without saying when. The conditions are real — they
            // have to be, or the letters could never open themselves — but
            // `secretCondition` keeps them off the traveller's screen, so all
            // that is ever shown is a count.
            Letter(number: 8, title: "On a city I've only heard about", writtenOn: written(-4),
                   condition: .place("Sài Gòn"), hint: "not yet",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Go early, then get out of the first district entirely."],
                   signature: "— me", secretCondition: true),
            Letter(number: 9, title: "On being tired of each other", writtenOn: written(-3),
                   condition: .day(44), hint: "not yet",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Take a day apart. It's maintenance, not a rupture."],
                   signature: "— me", secretCondition: true),
            Letter(number: 10, title: "Day fifty", writtenOn: written(-3),
                   condition: .day(50), hint: "not yet",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Eleven days left. Buy the thing you've walked past four times."],
                   signature: "— me", secretCondition: true),
            Letter(number: 11, title: "The last country", writtenOn: written(-2),
                   condition: .place("Seoul"), hint: "not yet",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Third country, and the cold one. Everybody packs wrong for it."],
                   signature: "— me", secretCondition: true),
            Letter(number: 12, title: "Opens with the last stamp", writtenOn: written(-2),
                   condition: .finalStamp, hint: "Jeju · the final one",
                   openedPlace: nil, openedOn: nil,
                   paragraphs: ["Nothing left on the itinerary, and you're still standing in it."],
                   signature: "— me")
        ]
    }

    // MARK: - Trail

    /// Eleven waypoints, four earned. "Ayutthaya · Pai" is one stop holding
    /// two of them, which is the case a `first` lookup used to lose.
    static func stamps(start: Date) -> [Stamp] {
        func on(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            date(day: day, hour: hour, minute: minute, start: start)
        }

        return [
            Stamp(code: "BKK", city: "Bangkok", index: 1, earnedOn: on(1, 18, 10),
                  arrivalNote: "Sixty-one days start here.", unlocksLetter: 1,
                  latitude: 13.7563, longitude: 100.5018),
            Stamp(code: "AYU", city: "Ayutthaya", index: 2, earnedOn: on(5, 10, 40),
                  arrivalNote: "Nine hundred years of brick and nobody else awake.", unlocksLetter: 2,
                  latitude: 14.3532, longitude: 100.5689),
            Stamp(code: "PAI", city: "Pai", index: 3, earnedOn: on(8, 16, 20),
                  arrivalNote: "762 curves. You counted the first forty.", unlocksLetter: 3,
                  latitude: 19.3583, longitude: 98.44),
            Stamp(code: "CNX", city: "Chiang Mai", index: 4, earnedOn: on(9, 17, 2),
                  arrivalNote: "Standing in it, and about to get very wet.", unlocksLetter: 4,
                  latitude: 18.7883, longitude: 98.9853),
            Stamp(code: "CEI", city: "Chiang Rai", index: 5, earnedOn: nil,
                  arrivalNote: "The quiet north. Last stop before the border.", unlocksLetter: nil,
                  latitude: 19.9105, longitude: 99.8406),
            Stamp(code: "HAN", city: "Hanoi", index: 6, earnedOn: nil,
                  arrivalNote: "Second country. The traffic goes around you.", unlocksLetter: 5,
                  latitude: 21.0278, longitude: 105.8342),
            Stamp(code: "HOI", city: "Hội An", index: 7, earnedOn: nil,
                  arrivalNote: "This one can't be earned from a hotel in Đà Nẵng.", unlocksLetter: 6,
                  latitude: 15.8801, longitude: 108.338),
            Stamp(code: "SGN", city: "Sài Gòn", index: 8, earnedOn: nil,
                  arrivalNote: "Loud, hot, and the best coffee of the trip.", unlocksLetter: nil,
                  latitude: 10.8231, longitude: 106.6297),
            Stamp(code: "SEL", city: "Seoul", index: 9, earnedOn: nil,
                  arrivalNote: "Third country. Colder than you packed for.", unlocksLetter: nil,
                  latitude: 37.5665, longitude: 126.978),
            Stamp(code: "PUS", city: "Busan", index: 10, earnedOn: nil,
                  arrivalNote: "The sea again, from the other end of the map.", unlocksLetter: nil,
                  latitude: 35.1796, longitude: 129.0756),
            Stamp(code: "CJU", city: "Jeju", index: 11, earnedOn: nil,
                  arrivalNote: "The last one. Nothing left on the itinerary.", unlocksLetter: 12,
                  latitude: 33.4996, longitude: 126.5312)
        ]
    }

    // MARK: - Expenses

    /// Thirty-one lines in one currency, split between the two slots, so the
    /// balance is non-trivial and the country total is a round number to
    /// assert against.
    static func expenses(start: Date) -> [Expense] {
        // day, hour, amount, payer, split, note
        let lines: [(Int, Int, Double, Payer, Split, String)] = [
            (1, 19, 3200, .one, .evenly, "Guesthouse, Bangkok"),
            (1, 21, 980, .two, .evenly, "First dinner"),
            (2, 11, 1450, .one, .evenly, "Temples"),
            (2, 13, 620, .two, .evenly, "Lunch"),
            (2, 20, 3600, .one, .evenly, "Guesthouse, second night"),
            (3, 15, 1180, .one, .evenly, "River boat"),
            (3, 19, 3200, .one, .evenly, "Guesthouse, third night"),
            (4, 9, 890, .two, .evenly, "Street food"),
            (4, 14, 2400, .one, .evenly, "Train to Ayutthaya"),
            (4, 18, 4200, .two, .evenly, "Ayutthaya guesthouse"),
            (5, 10, 760, .one, .evenly, "Bicycles, no brakes"),
            (5, 19, 2600, .two, .evenly, "Guesthouse"),
            (6, 12, 2980, .two, .evenly, "Transfers north"),
            (6, 16, 450, .two, .mineOnly, "Market, theirs"),
            (6, 20, 1320, .one, .evenly, "Dinner"),
            (7, 8, 4800, .two, .evenly, "Bus to Pai"),
            (7, 19, 1100, .two, .evenly, "Food, Pai"),
            (8, 11, 980, .one, .evenly, "Scooter, one day"),
            (8, 19, 2200, .two, .evenly, "Hostel"),
            (8, 20, 3500, .two, .evenly, "Hostel, two more nights"),
            (9, 13, 1600, .one, .evenly, "Hot springs"),
            (9, 20, 720, .two, .evenly, "Dinner"),
            (10, 9, 5200, .one, .evenly, "Bus down + Chiang Mai room"),
            (10, 20, 1340, .two, .evenly, "Dinner, old town"),
            (10, 21, 2600, .two, .evenly, "Guesthouse deposit"),
            (11, 12, 890, .two, .evenly, "Noodles and the market"),
            (11, 17, 3000, .one, .evenly, "Songkran supplies, dinner"),
            (11, 19, 3400, .one, .evenly, "Guesthouse, balance"),
            // Day 12 — today
            (12, 8, 240, .one, .evenly, "Breakfast"),
            (12, 10, 620, .one, .evenly, "Two water guns, the good ones"),
            (12, 14, 380, .one, .evenly, "Dry bags and a poncho")
        ]

        return lines.map { day, hour, amount, payer, split, note in
            Expense(date: date(day: day, hour: hour, start: start),
                    amount: amount, currency: .thb, payer: payer, split: split,
                    note: note, country: "Thailand")
        }
    }

    // MARK: - Journal

    /// Three pages for one slot and two for the other, so the book's per-author
    /// filter has something to filter.
    static func journal(start: Date) -> [JournalEntry] {
        let lines: [(Int, String, String, [String], Traveller)] = [
            (11, "Pai", "Slept twelve hours and woke up in fog", ["tired", "quiet"], .one),
            (10, "the bus", "762 curves, counted out loud until 40", ["strangers"], .one),
            (8, "Ayutthaya", "Rented bicycles with no brakes", ["proud"], .one),
            (11, "Pai", "The fog came all the way down to the road", ["quiet"], .two),
            (9, "Pai", "Made a friend at the bridge", ["strangers"], .two)
        ]

        return lines.map { day, city, line, tags, author in
            JournalEntry(dayNumber: day, date: date(day: day, hour: 22, minute: 10, start: start),
                         city: city, line: line, tags: tags, hasPhoto: true, photoID: nil,
                         author: author)
        }
    }

    // MARK: - Papers

    static var documents: [TravelDocument] {
        [
            TravelDocument(
                title: "Passport · Alex", subtitle: "Netherlands · expires 2031",
                badge: "PASSPORT",
                owner: .one,
                fields: [
                    DocumentField(label: "Number", value: "NX4419 882"),
                    DocumentField(label: "Expires", value: "14 Aug 2031"),
                    DocumentField(label: "Blank pages", value: "9")
                ],
                footnoteTitle: "Next document",
                footnoteBody: "Vietnam e-visa · E12-4471. Paper isn't required at the border, but a copy is in the backpack."
            ),
            TravelDocument(
                title: "Passport · Sam", subtitle: "Netherlands · expires 2029",
                badge: "PASSPORT",
                owner: .two,
                fields: [
                    DocumentField(label: "Number", value: "NX2087 441"),
                    DocumentField(label: "Expires", value: "2 Feb 2029"),
                    DocumentField(label: "Blank pages", value: "14")
                ],
                footnoteTitle: nil, footnoteBody: nil
            ),
            TravelDocument(
                title: "Vietnam e-visa", subtitle: "90 days, single entry",
                badge: "VISA",
                owner: nil,
                fields: [
                    DocumentField(label: "Reference", value: "E12-4471"),
                    DocumentField(label: "Entry", value: "Nội Bài"),
                    DocumentField(label: "Nationality", value: "Dutch")
                ],
                footnoteTitle: "At the border",
                footnoteBody: "Paper copy is in the front pocket of the blue backpack."
            ),
            TravelDocument(
                title: "K-ETA · Korea", subtitle: "approved before departure",
                badge: "VISA",
                owner: nil,
                fields: [
                    DocumentField(label: "Reference", value: "KE-9920-3311"),
                    DocumentField(label: "Valid", value: "2 years")
                ],
                footnoteTitle: nil, footnoteBody: nil
            ),
            TravelDocument(
                title: "Insurance", subtitle: "claim line, 24h",
                badge: "INSURANCE",
                owner: nil,
                fields: [
                    DocumentField(label: "Policy", value: "TW-4471-882"),
                    DocumentField(label: "Claim line", value: "+31 20 592 9292"),
                    DocumentField(label: "Medical cap", value: "€5,000,000")
                ],
                footnoteTitle: "Before you call",
                footnoteBody: "They ask for the policy number and the date of the incident, in that order."
            ),
            TravelDocument(
                title: "Embassies", subtitle: "Bangkok · Hanoi · Seoul",
                badge: "EMBASSY",
                owner: nil,
                fields: [
                    DocumentField(label: "Bangkok", value: "02 309 5200"),
                    DocumentField(label: "Hanoi", value: "024 3831 5650"),
                    DocumentField(label: "Seoul", value: "02 311 8600")
                ],
                footnoteTitle: "These are the Dutch missions",
                footnoteBody: "They can replace a passport and contact your family. Insurance handles the money."
            )
        ]
    }

    /// Numbered here rather than by hand: `index` is what survives a merge,
    /// since the union hands back a dictionary's values. The address card stays
    /// first.
    ///
    /// They carry no `updatedAt`, which leaves them at `.distantPast` — a card
    /// nobody has touched should lose to one somebody wrote.
    static var showCards: [ShowCard] {
        cards.enumerated().map { position, card in
            var numbered = card
            numbered.index = position
            return numbered
        }
    }

    private static var cards: [ShowCard] {
        [
            ShowCard(
                native: "ช่วยพาไปที่\nเกสต์เฮาส์ ถนนเจริญราษฎร์",
                english: "Please take me to the guesthouse,\nCharoenrat Road.",
                footerTitle: "If the driver doesn't know it",
                footerBody: "Near Wat Ket, the old teak house",
                footerNote: "guesthouse 053 243 677",
                shortName: "address"
            ),
            ShowCard(
                native: "ฉันแพ้ถั่วลิสง\nอย่างรุนแรง",
                english: "I have a severe peanut allergy.\nPlease, no peanuts or peanut oil.",
                footerTitle: "If it goes wrong",
                footerBody: "EpiPen · left hip pocket",
                footerNote: "spare in the other bag · ambulance 1669",
                shortName: "peanuts"
            ),
            ShowCard(
                native: "ฉันกินมังสวิรัติ\nไม่ใส่น้ำปลา",
                english: "I'm vegetarian.\nNo fish sauce, please.",
                footerTitle: "Worth knowing",
                footerBody: "Fish sauce is in almost everything",
                footerNote: "ask twice, kindly",
                shortName: "vegetarian"
            ),
            ShowCard(
                native: "ช่วยโทรหาเบอร์นี้ให้หน่อย",
                english: "Please call this number for me.",
                footerTitle: "Numbers",
                footerBody: "the other phone · 06 2451 8890",
                footerNote: "guesthouse 053 243 677",
                shortName: "call"
            ),
            ShowCard(
                native: "ฉันหลงทาง\nช่วยชี้ทางไปวัดพระสิงห์",
                english: "I'm lost.\nWhich way to Wat Phra Singh?",
                footerTitle: "The meeting point",
                footerBody: "North gate, by the ticket booth",
                footerNote: "walk, don't take a ride you didn't agree a price for",
                shortName: "lost"
            )
        ]
    }

    static var sharingRules: [SharingRule] {
        [
            SharingRule(title: "Money", detail: "every expense, both ways", state: "shared", isShared: true),
            SharingRule(title: "Plans & itinerary", detail: "either of you can change them", state: "shared", isShared: true),
            SharingRule(title: "Pins on the trail", detail: "one shared trail, both of you", state: "shared", isShared: true),
            SharingRule(title: "Your journal", detail: "until the books are printed", state: "private", isShared: false),
            SharingRule(title: "Live location", detail: "for moments, pins, the trail and Separated", state: "on demand", isShared: false),
            SharingRule(title: "Anything from home", detail: "whoever's at home sees none of this", state: "never", isShared: false)
        ]
    }

    // MARK: - Meeting point

    static func meetingPoint(start: Date) -> MeetingPoint {
        var point = meetingPointOptions[0]
        point.setAt = date(day: 12, hour: 8, minute: 12, start: start)
        return point
    }

    /// Four places in one city, so the history checks have somewhere to move
    /// between.
    static let meetingPointOptions: [MeetingPoint] = [
        MeetingPoint(place: "Wat Phra Singh", detail: "north gate, by the ticket booth",
                     localScript: "วัดพระสิงห์ ประตูทางเหนือ", setAt: Date(),
                     latitude: 18.7884, longitude: 98.9817),
        MeetingPoint(place: "Tha Phae Gate", detail: "the moat side, under the big screen",
                     localScript: "ประตูท่าแพ ฝั่งคูเมือง", setAt: Date(),
                     latitude: 18.7877, longitude: 98.9931),
        MeetingPoint(place: "The guesthouse", detail: "the gate on Charoenrat Road",
                     localScript: "เกสต์เฮาส์ ถนนเจริญราษฎร์", setAt: Date(),
                     latitude: 18.793, longitude: 99.0043),
        MeetingPoint(place: "Warorot Market", detail: "the flower stalls at the river end",
                     localScript: "ตลาดวโรรส ฝั่งร้านดอกไม้", setAt: Date(),
                     latitude: 18.7896, longitude: 99.0016)
    ]
}
