import Foundation

// The seeded demo trip, commented out.
//
// The app ships with no trip inside it: a first launch is a blank trip, and
// onboarding asks for the dates, the budget, the currency and the itinerary.
// Nothing below is compiled, referenced or reachable.
//
// It is kept rather than deleted because it is a worked example of the shape
// every collection expects — day offsets instead of calendar dates, letters
// sealed against conditions, waypoints carrying codes and coordinates. To use
// it again, uncomment the block and call it from the seeding branch of
// `TripStore.init`. `Tools/CheckTrip.swift` is the neutral fixture the checks
// build their trip from, and is the closer model to copy.

/*
/// Everything a filled-in trip ships with.
///
/// Nothing here holds a calendar date. Every seeded record is anchored to a
/// trip-day offset and materialised against whatever departure date the
/// travellers enter, so moving the dates moves the whole trip.
enum SampleTrip {

    // MARK: - Defaults the setup screen opens on

    /// Puts the app in the state the prototype shows — twelve days in — while
    /// still being a real date the travellers can change.
    /// - Parameter now: takes the moment rather than reading the clock, so a
    ///   store built with an injected clock seeds against *its* today rather
    ///   than the machine's.
    static func defaultStart(now: Date = Date()) -> Date {
        let today = Calendar.trip.startOfDay(for: now)
        return Calendar.trip.date(byAdding: .day, value: -11, to: today) ?? today
    }

    /// Fixed, so both phones seeded from the same build agree on which trip
    /// they are on before either of them has synced anything.
    static let defaultTripID = UUID(uuidString: "D1D17401-0000-4000-A000-000000000001")!
    static let defaultTripName = "Đi Thôi"

    static let defaultDayCount = 61
    static let defaultHomeCurrency: Currency = .eur
    /// Who the packed letters were sealed for. The seed can't ask — onboarding
    /// hasn't run yet — so it names the slot instead of leaving it implicit in
    /// whatever `role` happens to default to, and `adopt(_:)` throws the letters
    /// away if the phone turns out to be the other one.
    static let letterRecipient: Traveller = .one
    /// Two people, sixty-one days, three countries — and near enough the pace
    /// the seeded ledger is actually running at, so the app opens on a trip
    /// that is roughly on budget rather than already blown.
    static let defaultBudget: Double = 8_000

    // `trailKilometres`, `pinsDropped` and `offlineMapSize` were here. The
    // first was a constant printed under the words "and counting" — it is
    // computed from the stamps now. The other two counted pins the app never
    // dropped and measured maps it has never held.

    /// Materialises a trip day into a real moment.
    static func date(day: Int, hour: Int = 12, minute: Int = 0, start: Date) -> Date {
        let midnight = Calendar.trip.date(byAdding: .day, value: day - 1, to: Calendar.trip.startOfDay(for: start)) ?? start
        return Calendar.trip.date(byAdding: DateComponents(hour: hour, minute: minute), to: midnight) ?? midnight
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

    static var dayPlans: [DayPlan] {
        [
            DayPlan(
                dayNumber: 12,
                city: "Chiang Mai",
                occasion: "Songkran",
                blurb: "Water fight from dawn. The moat is the whole point — walk it anticlockwise and you end up at Tha Phae Gate around dusk, which is where the speakers are.",
                items: [
                    PlanItem(time: "07:30", title: "Khao soi at Khun Yai", note: "Closes at 2pm and sells out by 11. Cash only."),
                    PlanItem(time: "10:00", title: "Buy the water guns", note: "Not the cheap ones. Bag for the phones."),
                    PlanItem(time: "12:00", title: "The moat, anticlockwise", note: "You will be soaked in ninety seconds. Accept it early."),
                    PlanItem(time: "19:00", title: "Tha Phae Gate", note: "Loud. Stay together — this is where phones get lost.")
                ],
                lodgingTitle: "Baan Orapin · booking 4471",
                lodgingNote: "Address card ready in Thai · 8 min walk from the gate"
            ),
            DayPlan(
                dayNumber: 13,
                city: "Chiang Mai",
                occasion: "Songkran",
                blurb: "Day two of the water. Quieter in the morning, unbearable by three. The temples still run their own ceremonies before any of it starts.",
                items: [
                    PlanItem(time: "06:40", title: "Alms at Wat Phra Singh", note: "Before the street wakes up. Shoulders covered."),
                    PlanItem(time: "11:00", title: "Dry hour at the Sunday market", note: "Everything under cover. Buy the fisherman trousers."),
                    PlanItem(time: "15:00", title: "Back into it", note: "The Nimman end is calmer if you've had enough.")
                ],
                lodgingTitle: "Baan Orapin · booking 4471",
                lodgingNote: "Same room, two more nights"
            ),
            DayPlan(
                dayNumber: 11,
                city: "Pai",
                occasion: nil,
                blurb: "Last morning in the valley. The bus down is the 762 curves everyone warns you about, and they are right.",
                items: [
                    PlanItem(time: "08:00", title: "Coffee at the bridge", note: "Fog burns off around nine. Wait for it."),
                    PlanItem(time: "11:30", title: "Minibus to Chiang Mai", note: "Sit at the front. Bag of ginger sweets, not a joke."),
                    PlanItem(time: "16:00", title: "Check in at Baan Orapin", note: "Old teak house. Ask for the room off the courtyard.")
                ],
                lodgingTitle: "Baan Orapin · booking 4471",
                lodgingNote: "First of four nights"
            )
        ]
    }

    // MARK: - Letters

    /// Every letter arrives sealed: that is what it means for one to be on a
    /// traveller's phone at all. Said once, here, rather than
    /// twelve times in the list below.
    static func letters(start: Date) -> [Letter] {
        drafted(start: start).map { letter in
            var sealed = letter
            sealed.sealedAt = letter.writtenOn
            return sealed
        }
    }

    private static func drafted(start: Date) -> [Letter] {
        func written(_ day: Int) -> Date { date(day: day, hour: 21, start: start) }
        func opened(_ day: Int, _ hour: Int, _ minute: Int) -> Date { date(day: day, hour: hour, minute: minute, start: start) }

        return [
            Letter(
                number: 1,
                title: "Before you take off",
                writtenOn: written(-14),
                condition: .place("Bangkok"),
                hint: "when the wheels are down",
                openedPlace: "Bangkok",
                openedOn: opened(1, 18, 20),
                paragraphs: [
                    "You're reading this in an airport, which means the hard part is over. The hard part was leaving, and you did it, and I watched you do it.",
                    "There are eleven more of these. You can't find them early — I checked, and then I asked someone cleverer than me to check again. They arrive when you arrive.",
                    "Eat something before you get on the train. You never do."
                ],
                signature: "— me, obviously"
            ),
            Letter(
                number: 2,
                title: "The bit about the tuk-tuk",
                writtenOn: written(-12),
                condition: .place("Ayutthaya"),
                hint: "when the ruins turn up",
                openedPlace: "Ayutthaya",
                openedOn: opened(5, 11, 5),
                paragraphs: [
                    "He will quote you three hundred baht and you will pay it, and then twenty minutes later you'll find out it should have been one-fifty. This is going to bother you for the rest of the afternoon.",
                    "Let it go faster than you want to. A hundred and fifty baht is under four euro and you are standing in a nine-hundred-year-old city.",
                    "Take the photo of Traveller two in front of the tree with the stone head in it. She won't ask you to."
                ],
                signature: "— me"
            ),
            Letter(
                number: 3,
                title: "On sleeping badly in Pai",
                writtenOn: written(-9),
                condition: .place("Pai"),
                hint: "when the valley gets quiet",
                openedPlace: "Pai",
                openedOn: opened(8, 22, 40),
                paragraphs: [
                    "Around week two the novelty runs out and you get one bad night where you lie there doing sums about money and wondering what you're doing. Everyone gets it. Nobody writes home about it.",
                    "It isn't a sign. It's day eleven and you've been on a bus. Sleep, and if you can't, walk to the bridge and look at the fog, and then sleep.",
                    "I'm not worried about you. I want that on record somewhere you can re-read."
                ],
                signature: "— me"
            ),
            Letter(
                number: 4,
                title: "Get completely soaked",
                writtenOn: written(-7),
                condition: .place("Chiang Mai"),
                hint: "when the water starts",
                openedPlace: "Chiang Mai",
                openedOn: opened(9, 17, 2),
                paragraphs: [
                    "Em à, if you're reading this then the phone knew you made it to Chiang Mai, which means the bus didn't fall off the mountain and I can stop refreshing the map.",
                    "You told me once you wanted to be somewhere loud enough that you couldn't hear yourself worry. Today is that place. Everyone in that city is going to throw water at you and none of them will apologise.",
                    "So: put the phone in the bag. Buy the expensive water gun, not the 20-baht one that breaks. Let Traveller two complain about her hair for one hour and then watch her love it more than you do.",
                    "I'm not there and that's fine. Two months is nothing. Go be twenty-four."
                ],
                signature: "— me, obviously"
            ),
            Letter(
                number: 5,
                title: "Opens in Hanoi",
                writtenOn: written(-6),
                condition: .place("Hanoi"),
                hint: "when you land, whenever that is",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "Second country. You've done this before now, which is a strange thing to be able to say about yourself.",
                    "The traffic doesn't stop for you. You walk into it slowly and steadily and it goes around you. There's a lesson in there and I'm not going to spell it out.",
                    "Find the place my mother told you about. The one with no sign."
                ],
                signature: "— me"
            ),
            Letter(
                number: 6,
                title: "Opens somewhere on water",
                writtenOn: written(-5),
                condition: .place("Hội An"),
                hint: "you'll know it when you're there",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "Of course it was here. You've been near water for six weeks and this is the one that counts — lanterns, a river, a boat you paid too much for.",
                    "Put a candle in and don't tell me what you wished for.",
                    "Halfway is behind you now. The second half goes faster. Everyone says that and it turns out to be true, which is annoying."
                ],
                signature: "— me"
            ),
            Letter(
                number: 7,
                title: "Opens on day 30",
                writtenOn: written(-4),
                condition: .day(30),
                hint: "halfway",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "Thirty days. You are exactly as far from me as you are going to get, and from here every day is one closer.",
                    "By now you have a routine, which is the thing you were most afraid you'd never have out there.",
                    "Ring your mother."
                ],
                signature: "— me"
            ),
            // Four sealed without saying when. The conditions are real —
            // they have to be, or the letters could never open themselves — but
            // `secretCondition` keeps them off the reading screen, so all
            // is a count.
            Letter(
                number: 8,
                title: "On the city I grew up next to",
                writtenOn: written(-4),
                condition: .place("Sài Gòn"),
                hint: "not yet",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "My mother left this city in 1979 and never went back, so everything I know about it I know secondhand, which is a strange thing to admit to someone who is standing in it.",
                    "Go to Bến Thành early, before it turns into a place for people like us. Then get out of District 1 entirely — the bit I've heard about my whole life is somewhere off Lê Văn Sỹ and I have no idea what it looks like now.",
                    "Send me nothing. Tell me when you're back."
                ],
                signature: "— me",
                secretCondition: true
            ),
            Letter(
                number: 9,
                title: "On being tired of each other",
                writtenOn: written(-3),
                condition: .day(44),
                hint: "not yet",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "Somewhere around now you two will have had the argument. Six weeks in a room together does that, and it doesn't mean anything.",
                    "Take a day apart. Genuinely — different neighbourhoods, no texting, meet at dinner. It isn't a rupture, it's maintenance.",
                    "Traveller two has never travelled like this before and you have. Be the patient one for one more week."
                ],
                signature: "— me",
                secretCondition: true
            ),
            Letter(
                number: 10,
                title: "Day fifty",
                writtenOn: written(-3),
                condition: .day(50),
                hint: "not yet",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "Eleven days left, which is about as long as a normal holiday, so you can stop measuring it in months now.",
                    "This is the part where people start planning the next one instead of being in this one. Don't. There's time for that on the plane.",
                    "Buy the thing you've walked past four times."
                ],
                signature: "— me",
                secretCondition: true
            ),
            Letter(
                number: 11,
                title: "The last country",
                writtenOn: written(-2),
                condition: .place("Seoul"),
                hint: "not yet",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "Third country, and the cold one. You'll have packed wrong; everybody packs wrong for this bit.",
                    "You're going to notice that you're good at this now — at the arriving, the working out where to eat, the not panicking. That's the thing you actually went for and nobody will be able to see it in the photographs.",
                    "Two weeks. I can wait two weeks."
                ],
                signature: "— me",
                secretCondition: true
            ),
            Letter(
                number: 12,
                title: "Opens with the last stamp",
                writtenOn: written(-2),
                condition: .finalStamp,
                hint: "Jeju · the final one",
                openedPlace: nil,
                openedOn: nil,
                paragraphs: [
                    "Last one. You're on an island with nothing left on the itinerary, which means the trip is over and you're still standing in it.",
                    "You are about to come home and be slightly unbearable about all of this for a month, and I am going to let you.",
                    "Come home. I'll be at arrivals with the wrong flowers."
                ],
                signature: "— me, obviously"
            )
        ]
    }

    // MARK: - Trail

    static func stamps(start: Date) -> [Stamp] {
        func on(_ day: Int, _ hour: Int, _ minute: Int) -> Date { date(day: day, hour: hour, minute: minute, start: start) }

        return [
            Stamp(code: "BKK", city: "Bangkok", index: 1, earnedOn: on(1, 18, 10),
                  arrivalNote: "Sixty-one days start here.", unlocksLetter: 1, latitude: 13.7563, longitude: 100.5018),
            Stamp(code: "AYU", city: "Ayutthaya", index: 2, earnedOn: on(5, 10, 40),
                  arrivalNote: "Nine hundred years of brick and nobody else awake.", unlocksLetter: 2, latitude: 14.3532, longitude: 100.5689),
            Stamp(code: "PAI", city: "Pai", index: 3, earnedOn: on(8, 16, 20),
                  arrivalNote: "762 curves. You counted the first forty.", unlocksLetter: 3, latitude: 19.3583, longitude: 98.44),
            Stamp(code: "CNX", city: "Chiang Mai", index: 4, earnedOn: on(9, 17, 2),
                  arrivalNote: "You're standing in it, and it's about to get very wet.", unlocksLetter: 4, latitude: 18.7883, longitude: 98.9853),
            Stamp(code: "CEI", city: "Chiang Rai", index: 5, earnedOn: nil,
                  arrivalNote: "The quiet north. Last stop before the border.", unlocksLetter: nil, latitude: 19.9105, longitude: 99.8406),
            Stamp(code: "HAN", city: "Hanoi", index: 6, earnedOn: nil,
                  arrivalNote: "Second country. The traffic goes around you.", unlocksLetter: 5, latitude: 21.0278, longitude: 105.8342),
            Stamp(code: "HOI", city: "Hội An", index: 7, earnedOn: nil,
                  arrivalNote: "You're standing in it. This one can't be faked from a hotel in Đà Nẵng.", unlocksLetter: 6, latitude: 15.8801, longitude: 108.338),
            Stamp(code: "SGN", city: "Sài Gòn", index: 8, earnedOn: nil,
                  arrivalNote: "Loud, hot, and the best coffee of the whole trip.", unlocksLetter: nil, latitude: 10.8231, longitude: 106.6297),
            Stamp(code: "SEL", city: "Seoul", index: 9, earnedOn: nil,
                  arrivalNote: "Third country. Bring a jacket — it's colder than you packed for.", unlocksLetter: nil, latitude: 37.5665, longitude: 126.978),
            Stamp(code: "PUS", city: "Busan", index: 10, earnedOn: nil,
                  arrivalNote: "The sea again, from the other end of the map.", unlocksLetter: nil, latitude: 35.1796, longitude: 129.0756),
            Stamp(code: "CJU", city: "Jeju", index: 11, earnedOn: nil,
                  arrivalNote: "The last one. Nothing left on the itinerary.", unlocksLetter: 12, latitude: 33.4996, longitude: 126.5312)
        ]
    }

    // MARK: - Expenses

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
            (6, 16, 450, .two, .mineOnly, "Market, hers"),
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
            (10, 21, 2600, .two, .evenly, "Baan Orapin deposit"),
            (11, 12, 890, .two, .evenly, "Khao soi and the market"),
            (11, 17, 3000, .one, .evenly, "Songkran supplies, dinner"),
            (11, 19, 3400, .one, .evenly, "Baan Orapin, balance"),
            // Day 12 — today
            (12, 8, 240, .one, .evenly, "Khao soi at Khun Yai"),
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

    static func journal(start: Date) -> [JournalEntry] {
        let lines: [(Int, String, String, [String], Traveller)] = [
            (11, "Pai", "Slept twelve hours and woke up in fog", ["tired", "quiet"], .one),
            (10, "the bus", "762 curves. Traveller two counted out loud until 40", ["strangers"], .one),
            (8, "Ayutthaya", "Rented bicycles with no brakes", ["proud"], .one),
            (11, "Pai", "The fog came all the way down to the road", ["quiet"], .two),
            (9, "Pai", "Traveller one made a friend at the bridge and I did not", ["strangers"], .two)
        ]

        return lines.map { day, city, line, tags, author in
            JournalEntry(dayNumber: day, date: date(day: day, hour: 22, minute: 10, start: start),
                         city: city, line: line, tags: tags, hasPhoto: true, photoID: nil, author: author)
        }
    }

    static let journalTags = ["soaked", "tired", "homesick", "proud", "khao soi", "strangers", "quiet", "lost"]

    // MARK: - Papers

    static var documents: [TravelDocument] {
        [
            TravelDocument(
                title: "Passport · Traveller one", subtitle: "Netherlands · expires 2031", badge: "2 scans", badgeIsAccent: true,
                owner: .one,
                fields: [
                    DocumentField(label: "Number", value: "NX4419 882"),
                    DocumentField(label: "Expires", value: "14 Aug 2031"),
                    DocumentField(label: "Blank pages", value: "9")
                ],
                footnoteTitle: "Next document",
                footnoteBody: "Vietnam e-visa · E12-4471. Print isn't required at Nội Bài, but border guards prefer paper. There's a copy in your backpack.",
                hasScan: true
            ),
            TravelDocument(
                title: "Passport · Traveller two", subtitle: "Netherlands · expires 2029", badge: "2 scans", badgeIsAccent: true,
                owner: .two,
                fields: [
                    DocumentField(label: "Number", value: "NX2087 441"),
                    DocumentField(label: "Expires", value: "2 Feb 2029"),
                    DocumentField(label: "Blank pages", value: "14")
                ],
                footnoteTitle: nil, footnoteBody: nil, hasScan: true
            ),
            TravelDocument(
                title: "Vietnam e-visa", subtitle: "90 days, single entry", badge: "valid", badgeIsAccent: true,
                owner: nil,
                fields: [
                    DocumentField(label: "Reference", value: "E12-4471"),
                    DocumentField(label: "Entry", value: "Nội Bài"),
                    DocumentField(label: "Nationality", value: "Dutch")
                ],
                footnoteTitle: "At the border",
                footnoteBody: "Paper copy is in the front pocket of the blue backpack. Don't join the fast-track queue — it costs money and saves nine minutes.",
                hasScan: true
            ),
            TravelDocument(
                title: "K-ETA · Korea", subtitle: "approved before you left", badge: "valid", badgeIsAccent: true,
                owner: nil,
                fields: [
                    DocumentField(label: "Reference", value: "KE-9920-3311"),
                    DocumentField(label: "Valid", value: "2 years")
                ],
                footnoteTitle: nil, footnoteBody: nil, hasScan: false
            ),
            TravelDocument(
                title: "Insurance", subtitle: "claim line, 24h", badge: "pdf", badgeIsAccent: false,
                owner: nil,
                fields: [
                    DocumentField(label: "Policy", value: "TW-4471-882"),
                    DocumentField(label: "Claim line", value: "+31 20 592 9292"),
                    DocumentField(label: "Medical cap", value: "€5,000,000")
                ],
                footnoteTitle: "Before you call",
                footnoteBody: "They will ask for the policy number and the date of the incident, in that order, and nothing else for the first five minutes.",
                hasScan: true
            ),
            TravelDocument(
                title: "Embassies", subtitle: "Bangkok · Hanoi · Seoul", badge: "call", badgeIsAccent: false,
                owner: nil,
                fields: [
                    DocumentField(label: "Bangkok", value: "02 309 5200"),
                    DocumentField(label: "Hanoi", value: "024 3831 5650"),
                    DocumentField(label: "Seoul", value: "02 311 8600")
                ],
                footnoteTitle: "These are the Dutch missions",
                footnoteBody: "They can replace a passport, contact your family, and not much else. Insurance handles the money.",
                hasScan: false
            )
        ]
    }

    /// The order is the order they are written in, numbered here rather than
    /// by hand: `index` is what survives a merge (the union hands back a
    /// dictionary's values), and five numbers kept in step by attention is five
    /// numbers that eventually aren't. The address stays first on purpose.
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
                native: "ช่วยพาไปที่\nบ้านอรพิน ถนนเจริญราษฎร์",
                english: "Please take me to Baan Orapin,\nCharoenrat Road.",
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
                footerNote: "Traveller two carries the spare · ambulance 1669",
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
                footerBody: "Traveller two 06 2451 8890",
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

    static let meetingPointOptions: [MeetingPoint] = [
        MeetingPoint(place: "Wat Phra Singh", detail: "north gate, by the ticket booth",
                     localScript: "วัดพระสิงห์ ประตูทางเหนือ", setAt: Date(), latitude: 18.7884, longitude: 98.9817),
        MeetingPoint(place: "Tha Phae Gate", detail: "the moat side, under the big screen",
                     localScript: "ประตูท่าแพ ฝั่งคูเมือง", setAt: Date(), latitude: 18.7877, longitude: 98.9931),
        MeetingPoint(place: "Baan Orapin", detail: "the guesthouse gate on Charoenrat Road",
                     localScript: "บ้านอรพิน ถนนเจริญราษฎร์", setAt: Date(), latitude: 18.793, longitude: 99.0043),
        MeetingPoint(place: "Warorot Market", detail: "the flower stalls at the river end",
                     localScript: "ตลาดวโรรส ฝั่งร้านดอกไม้", setAt: Date(), latitude: 18.7896, longitude: 99.0016)
    ]

    // Emergency numbers used to live here, as one country's numbers printed
    // under a label computed from the current leg. They come from
    // `CountryFacts` now, which returns nothing for a country it doesn't know.
    // Reaching the other traveller wants a real field on the trip — see
    // Review.md.
}
*/
