import Foundation
import CryptoKit
// For the zone and record ids the invitation flow keys off. Nothing here talks
// to CloudKit — `tripID(fromRecordName:)` is string handling, which is exactly
// why it lives in `Model/` where it can be checked.
import CloudKit
// For the day page's proof: the worst text the store accepts, set in the
// book's own typeface and measured. AppKit only for the font, CoreText for
// the setting — the same New York the app's `.serif` design resolves to.
import AppKit
import CoreText

/// Model-layer checks that run on macOS, so the trip maths can be verified
/// without a simulator. See Tools/run-checks.sh.
@main
struct Verify {
    @MainActor
    static func main() async {
        // Unbuffered, so a crash mid-run still shows which check it died on.
        setbuf(stdout, nil)

        // Everything this process stores goes somewhere disposable. It used to
        // write to `UserDefaults.standard` and to the developer's real
        // ~/Library/Application Support/DiThoi, and it didn't clean all of it
        // up — so a run could be influenced by what the last one left behind,
        // and running the checks changed the machine they ran on.
        Storage.useScratch(named: "dithoi.checks")
        // Named by the types that own them, for the reason `DebugScreen.reset`
        // now is: a second copy of a key is a second thing that can drift.
        Storage.forget(TripStore.storeKey)
        Storage.defaults.removeObject(forKey: RatesService.storeKey)

        let box = LoopbackSyncTransport(named: "checks")
        box.latency = .zero
        box.erase()
        // Built from the fixture rather than from whatever `init` seeds: the app
        // ships with no trip inside it, so a store with nothing to load is a
        // blank trip and there would be nothing here to check.
        let store = TripStore(snapshot: CheckTrip.snapshot(),
                              sync: SyncCoordinator(transport: box))
        var failures = 0
        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            print("\(condition ? "ok  " : "FAIL") \(label) \(detail)")
            if !condition { failures += 1 }
        }
        func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.005) -> Bool { abs(a - b) < tolerance }
        /// No gaps, no overlaps, starting on day 1 — the invariant reflow exists to keep.
        func isContiguous(_ itinerary: ItineraryDocument) -> Bool {
            var cursor = 1
            for segment in itinerary.allSegments {
                if segment.startDay != cursor { return false }
                if segment.endDay <= segment.startDay { return false }
                cursor = segment.endDay
            }
            return true
        }

        print("— defaults —")
        check("home currency is EUR", store.homeCurrency == .eur)
        check("budget is €8,000", store.budget == 8_000)
        check("61 days", store.dayCount == 61)
        check("opens on day 12", store.dayNumber == 12, "got \(store.dayNumber)")
        check("during the trip", store.phase == .during)
        check("current city is Chiang Mai", store.currentCity == "Chiang Mai", "got \(store.currentCity)")
        check("local currency is THB", store.localCurrency == .thb)
        check("trip currencies are THB/VND/KRW", store.tripCurrencies == [.thb, .vnd, .krw])
        let nights = store.legs.reduce(0) { $0 + $1.nights }
        check("nights + 1 == day count", nights + 1 == store.dayCount, "\(nights) nights")
        check("itinerary fits the trip", store.itineraryOverrun == 0)

        print("— rates —")
        check("starts on built-in rates", store.rates.snapshot.source == .builtIn)
        check("built-in disclaimer is honest",
              store.rates.disclaimer.contains("built-in"), "got '\(store.rates.disclaimer)'")
        let euro = store.rates.snapshot.convert(RateSnapshot.builtIn.perEuro(.thb), from: .thb, to: .eur)
        check("THB → EUR converts", near(euro, 1, 0.001), "got \(euro)")
        let roundTrip = store.rates.snapshot.convert(
            store.rates.snapshot.convert(250, from: .eur, to: .krw), from: .krw, to: .eur)
        check("conversion round-trips", near(roundTrip, 250, 0.001), "got \(roundTrip)")

        // The rates arrive from two endpoints nobody here controls — one of
        // them a public npm package republished daily, which cannot be pinned
        // to a version without freezing the rates — and the only validation was
        // `rate > 0`. Everything downstream is load-bearing: the budget
        // forecast, the per-day-by-country lines, and the `amountHome` written
        // into a settlement, which is a real transfer between two people. A rate
        // out by a factor of a thousand has to be refused, not half-applied.
        //
        // This is the integrity control for that dependency, so it is the thing
        // worth checking. The live values on the day it was written all sit well
        // inside the band; the failures it catches are decimal points, lost
        // thousands and an inverted table.
        for currency in Currency.allCases where currency != .eur {
            let anchor = RateSnapshot.builtIn.perEuro(currency)
            check("the rate the app shipped with is believable about \(currency.code)",
                  RatesService.isPlausible(anchor, for: currency))
            check("a \(currency.code) rate out by a thousand is not",
                  !RatesService.isPlausible(anchor * 1000, for: currency))
            check("nor one out by a thousand the other way (\(currency.code))",
                  !RatesService.isPlausible(anchor / 1000, for: currency))
            // Ordinary drift still has to get through, or the app pins itself
            // to the figures it was built with and the disclaimer starts lying.
            check("but ordinary drift still gets through (\(currency.code))",
                  RatesService.isPlausible(anchor * 1.4, for: currency)
                  && RatesService.isPlausible(anchor * 0.7, for: currency))
        }
        check("zero is refused", !RatesService.isPlausible(0, for: .thb))
        check("so is a negative rate", !RatesService.isPlausible(-38.35, for: .thb))
        check("and so is a number that isn't one",
              !RatesService.isPlausible(.nan, for: .thb)
              && !RatesService.isPlausible(.infinity, for: .thb))
        // An inverted table — euros-per-unit where units-per-euro was meant —
        // is the shape this catches most usefully, because every figure in it
        // is positive and the old check passed it.
        check("an inverted table is refused",
              !RatesService.isPlausible(1 / RateSnapshot.builtIn.perEuro(.thb), for: .thb))

        print("— money, in euros —")
        print("     spent \(store.homeTextRounded(store.spentHome)) of \(store.homeTextRounded(store.budget))  (\(Int((store.budgetFraction*100).rounded()))%)")
        if let th = store.spent(inCountry: "Thailand") { print("     Thailand \(th.currency.format(th.local))") }
        print("     today \(store.spentTodayText) ≈ \(store.homeTextRounded(store.spentTodayHome))")
        print("     a day is worth \(store.homeTextRounded(store.budgetPerDay))")
        print("     balance: \(store.name(for: store.debtor)) owes \(store.name(for: store.creditor)) \(store.homeText(store.balanceAmountHome))")
        check("Thailand total is ฿62,400", near(store.spent(inCountry: "Thailand")?.local ?? 0, 62_400, 0.5))
        // This used to read `spending.count == expenses.count` at a point where
        // the seeded ledger holds no transfers at all — an assertion of n == n
        // that would have passed just as happily if `spending` had never
        // filtered anything. Put a transfer in and watch it not count.
        do {
            let spendBefore = store.spentHome
            let linesBefore = store.spending.count
            store.add(Expense(date: store.now, amount: 2_000, currency: .thb, payer: .one,
                              split: .evenly, note: "Paid her back", country: "Thailand",
                              kind: .transfer))
            check("spend excludes transfers",
                  store.spending.count == linesBefore && near(store.spentHome, spendBefore, 0.01),
                  "a transfer moved the burn by \(store.spentHome - spendBefore)")
            check("but the ledger still has it",
                  store.expenses.live.count == linesBefore + 1)
            store.expenses.removeAll { $0.note == "Paid her back" }
        }
        check("balance is non-trivial", store.balanceAmountHome > 1)

        print("— the budget is the user's —")
        store.budget = 11_000
        check("day rate follows the budget", near(store.budgetPerDay, 11_000 / 61))
        check("fraction follows the budget", near(store.budgetFraction, store.spentHome / 11_000))
        store.budget = 8_000

        print("— rates drive the totals —")
        let before = store.spentHome
        // A stronger baht means the same bills cost more euros.
        store.rates.applyForTesting(RateSnapshot(
            perEuro: ["EUR": 1, "USD": 1.138, "GBP": 0.854, "THB": RateSnapshot.builtIn.perEuro(.thb) / 2, "VND": 29_900, "KRW": 1_666],
            updatedAt: Date(), source: .live))
        check("halving the rate doubles the euro total", near(store.spentHome, before * 2, 0.5),
              "\(Int(before)) -> \(Int(store.spentHome))")
        check("live disclaimer names an age",
              store.rates.disclaimer.contains("updated") || store.rates.disclaimer.contains("cached"),
              "got '\(store.rates.disclaimer)'")
        store.rates.applyForTesting(.builtIn)

        print("— moving the dates —")
        let newStart = Calendar.trip.date(byAdding: .day, value: 30, to: store.start)!
        store.setStart(newStart)
        check("today is now before departure", store.phase.isBefore, "phase \(store.phase)")
        check("everything written moved with it",
              store.expenses.allSatisfy { (1...12).contains(store.dayNumber(for: $0.date)) })
        check("stamps moved too", store.stamps.compactMap(\.earnedOn).allSatisfy { store.dayNumber(for: $0) <= 12 })
        store.setStart(CheckTrip.defaultStart())
        check("day 12 again after moving back", store.dayNumber == 12, "got \(store.dayNumber)")
        check("expenses land on days 1–12 again",
              Set(store.spending.map { store.dayNumber(for: $0.date) }) == Set(1...12))

        print("— changing the length —")
        store.setEnd(Calendar.trip.date(byAdding: .day, value: 29, to: store.start)!)
        check("30 days", store.dayCount == 30, "got \(store.dayCount)")
        check("itinerary overruns and says so", store.itineraryOverrun == 31, "got \(store.itineraryOverrun)")
        check("day rate rose", near(store.budgetPerDay, 8_000 / 30))
        store.setDayCount(61)
        check("back to 61", store.dayCount == 61 && store.itineraryOverrun == 0)

        print("— editing the itinerary —")
        let firstStop = store.legs[0].segments[0]
        let originalNights = firstStop.nights
        store.setNights(originalNights + 3, forSegment: firstStop.id)
        check("the stop got longer", store.legs[0].segments[0].nights == originalNights + 3)
        check("days stay contiguous after a resize", isContiguous(store.itinerary))
        check("everything after it shifted",
              store.legs[0].segments[1].startDay == firstStop.startDay + originalNights + 3)
        store.setNights(originalNights, forSegment: firstStop.id)

        let thailand = store.legs[0]
        store.moveSegments(inLeg: thailand.id, from: IndexSet(integer: 3), to: 0)
        check("reordering moves the stop", store.legs[0].segments[0].title == thailand.segments[3].title)
        check("days stay contiguous after a reorder", isContiguous(store.itinerary))
        store.moveSegments(inLeg: thailand.id, from: IndexSet(integer: 0), to: 4)

        let nightsBefore = store.itinerary.totalNights
        store.addSegment(title: "Hue", nights: 4, toLeg: store.legs[1].id)
        check("adding a stop adds its nights", store.itinerary.totalNights == nightsBefore + 4)
        check("days stay contiguous after an add", isContiguous(store.itinerary))
        let added = store.legs[1].segments.first { $0.title == "Hue" }!
        store.removeSegment(added.id)
        check("removing it puts the nights back", store.itinerary.totalNights == nightsBefore)
        check("days stay contiguous after a remove", isContiguous(store.itinerary))

        store.addLeg(country: "Cambodia", currency: .usd, firstStop: "Siem Reap", nights: 5)
        check("a new country lands at the end", store.legs.last?.country == "Cambodia")
        check("its currency joins the trip", store.tripCurrencies.contains(.usd))
        store.removeLeg(store.legs.last!.id)
        check("and comes back out again", store.legs.count == 3 && !store.tripCurrencies.contains(.usd))

        print("— settling, which takes both of them —")
        let spendBefore = store.spentHome
        let owed = store.balanceAmountHome
        let debtor = store.debtor
        store.role = debtor.other                     // the creditor raises it
        let proposal = store.proposeSettlement(note: "Settled in cash", in: .thb)
        check("a proposal exists", proposal != nil)
        check("it records who owes", proposal?.debtor == debtor)
        check("nothing has cleared yet", near(store.balanceAmountHome, owed),
              "balance moved to \(store.balanceAmountHome)")
        check("it's waiting on the other phone", store.pendingSettlement?.awaiting == debtor)
        check("this phone can't confirm its own", !store.settlementNeedsMyConfirmation)

        store.role = debtor                           // the debtor agrees
        check("now it's waiting on this one", store.settlementNeedsMyConfirmation)
        store.confirmSettlement(proposal!.id)
        check("balance clears to zero", near(store.netBalanceHome, 0), "left \(store.netBalanceHome)")
        check("settling doesn't change the burn", near(store.spentHome, spendBefore),
              "\(Int(spendBefore)) -> \(Int(store.spentHome))")
        store.applyConfirmedSettlements()
        check("applying twice is a no-op", near(store.netBalanceHome, 0))
        store.role = .one

        print("— custom split —")
        var custom = Expense(date: store.now, amount: 1000, currency: .thb, payer: .one,
                             split: .custom, note: "test", country: "Thailand", customShare: 0.25)
        check("custom share owed", near(custom.balanceFactor, 0.25))
        custom.split = .mineOnly
        check("mine only owes nothing", custom.balanceFactor == 0)
        custom.split = .evenly
        custom.payer = .two
        check("payer flips the sign", near(custom.balanceFactor, -0.5))

        print("— letters —")
        check("12 letters", store.letters.count == 12)
        check("4 open", store.openLetters.count == 4, "got \(store.openLetters.count)")
        check("visible sealed + hidden == 8", store.sealedLetters.count + store.hiddenLetterCount == 8)
        check("the other traveller doesn't merely not see them — she has none",
              { let phone = store.snapshot
                store.adopt(.two)
                let held = store.letters.count
                let visible = store.lettersVisible
                store.adopt(.one)
                store.letters = phone.letters
                return held == 0 && !visible }())

        print("— stamps —")
        check("11 stamps", store.stamps.count == 11)
        check("4 earned", store.earnedStamps.count == 4, "got \(store.earnedStamps.count)")
        check("Hội An is number 7", store.stamps.first { $0.code == "HOI" }?.index == 7)
        let unlocked = store.arrive(at: store.nextStamp!)
        check("arriving earns the stamp", store.earnedStamps.count == 5)
        check("Chiang Rai unlocks nothing", unlocked == nil, "got \(String(describing: unlocked?.number))")
        let hanoiLetter = store.arrive(at: store.nextStamp!)
        check("Hanoi opens letter 5", hanoiLetter?.number == 5, "got \(String(describing: hanoiLetter?.number))")
        check("that letter is now open", store.letters.first { $0.number == 5 }?.isOpen == true)

        print("— journal —")
        check("slot one has 3 pages", store.entries(for: .one).count == 3)
        check("slot two has 2 pages", store.entries(for: .two).count == 2)
        check("today is unwritten", store.todaysEntry == nil)
        store.save(entry: JournalEntry(dayNumber: 12, date: store.now, city: "Chiang Mai",
                                       line: "Wrong bus, better temple",
                                       tags: ["soaked"], hasPhoto: true, author: .one))
        check("today is written", store.todaysEntry != nil)
        check("page count grew", store.nightsWritten == 4, "got \(store.nightsWritten)")

        // `save(entry:)` keys on `(dayNumber, author)` and replaces in place.
        // Only the append branch was covered above, which is the half that
        // can't lose anything: the replace branch is the one that runs every
        // time somebody reopens last night's page from the book, and if it
        // ever appended instead, a page edited three times would print three
        // times.
        store.save(entry: JournalEntry(dayNumber: 12, date: store.now, city: "Chiang Mai",
                                       line: "She got me back twice as hard",
                                       tags: ["soaked"], hasPhoto: false, author: .one))
        check("re-saving the same night replaces it", store.nightsWritten == 4, "got \(store.nightsWritten)")
        check("and leaves exactly one page for that night",
              store.entries(for: .one).filter { $0.dayNumber == 12 }.count == 1)
        check("and the new words are what reads back",
              store.entries(for: .one).first { $0.dayNumber == 12 }?.line
                  == "She got me back twice as hard")

        // The key is the pair, not the day. Both of them writing about the
        // same night is two pages, which is the whole premise of the book.
        store.save(entry: JournalEntry(dayNumber: 12, date: store.now, city: "Chiang Mai",
                                       line: "A grandmother with a hose. No mercy.",
                                       tags: [], hasPhoto: false, author: .two))
        check("the other one writing the same night appends",
              store.entries(for: .two).count == 3, "got \(store.entries(for: .two).count)")
        check("and doesn't touch her pages", store.nightsWritten == 4, "got \(store.nightsWritten)")

        // Taking a page out. There was no way to: clearing the line read "Skip
        // tonight" and left the page in the book. The key is the same pair as
        // `save(entry:)`'s, so the other traveller's page for that night stays.
        do {
            let copy = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-delete-entry"))
            let theirsBefore = copy.entries(for: copy.role.other).count
            copy.deleteEntry(day: 12)
            check("removing a page takes this phone's page for that night",
                  !copy.myEntries.contains { $0.dayNumber == 12 } && copy.nightsWritten == 3,
                  "got \(copy.nightsWritten)")
            check("and leaves the other one's page for the same night",
                  copy.entries(for: copy.role.other).count == theirsBefore)
            copy.closeTrip()
            let before = copy.nightsWritten
            copy.deleteEntry(day: copy.myEntries.first?.dayNumber ?? 1)
            check("and a closed trip's pages can't be taken out", copy.nightsWritten == before)
        }

        // Swapping a page's photograph has to take the old file with it, or
        // the directory fills with pictures nothing points at and `prune`
        // never sees them as orphans until the trip closes.
        do {
            let photos = PhotoStore.shared
            let base = Storage.directory("Photos")
            for id in ["swap-old", "swap-new"] {
                try? Data("jpeg".utf8).write(to: base.appendingPathComponent("\(id).jpg"))
                try? Data("jpeg".utf8).write(to: base.appendingPathComponent("\(id)-thumb.jpg"))
            }
            let swap = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler())
            let night = JournalEntry(dayNumber: 4, date: swap.date(forDay: 4), city: "Bangkok",
                                     line: "The one with the photograph", tags: [],
                                     hasPhoto: true, photoID: "swap-old", author: swap.role)
            swap.save(entry: night)
            check("a page can carry a photograph", photos.exists("swap-old"))

            var replaced = night
            replaced.photoID = "swap-new"
            swap.save(entry: replaced)
            check("swapping it deletes the one it replaced", !photos.exists("swap-old"))
            check("and keeps the one that replaced it", photos.exists("swap-new"))
            check("and the page still points at the new one",
                  swap.entries(for: swap.role).first { $0.dayNumber == 4 }?.photoID == "swap-new")
            photos.delete("swap-new")
        }

        print("— who everybody is —")
        do {
            check("the packed trip arrived packed", store.origin == .packed)
            check("and named", store.name(for: .one) == "Alex" && store.name(for: .two) == "Sam")
            check("a payer has a name on it", store.label(for: .two) == "Sam")
            check("and 'both' isn't a person", store.label(for: .both) == "Both")

            store.rename(.one, to: "Kim")
            check("renaming a slot takes", store.name(for: .one) == "Kim")
            check("and leaves the other alone", store.name(for: .two) == "Sam")
            check("and doesn't touch the settings",
                  store.snapshot.settingsUpdatedAt == store.settingsUpdatedAt)

            store.rename(.one, to: "   ")
            check("a blank rename is refused", store.name(for: .one) == "Kim")
            check("and a name is never empty",
                  !store.name(for: .one).isEmpty && !store.name(for: .two).isEmpty
                      && !store.observerName.isEmpty)

            var unnamed = TripNames.blank
            check("an unnamed slot reads as a slot", unnamed[.two] == "Traveller two")
            unnamed.observer = ""
            check("and so does an unnamed observer", unnamed.observerName == "Home")

            // A snapshot round-trip, and then the same snapshot with the fields
            // stripped out of the JSON — the thing that actually happens when
            // a phone that saved before these existed opens this build.
            let encoded = (try? JSONEncoder().encode(store.snapshot)) ?? Data()
            check("names survive a round-trip",
                  TripSnapshot.decode(encoded)?.names == store.names)
            check("and so does the origin",
                  TripSnapshot.decode(encoded)?.origin == .packed)

            if var json = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
                json.removeValue(forKey: "names")
                json.removeValue(forKey: "origin")
                let stripped = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                let old = TripSnapshot.decode(stripped)
                check("a snapshot written before names still opens", old != nil)
                check("and falls back to an unnamed, unfilled trip",
                      old?.names == .blank && old?.origin == .blank)
            } else {
                check("the snapshot is a JSON object", false)
            }

            let payload = (try? JSONEncoder().encode(store.payload)) ?? Data()
            if var json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                json.removeValue(forKey: "names")
                let stripped = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                check("a payload written before names still decodes",
                      (try? JSONDecoder().decode(SyncPayload.self, from: stripped))?.names == .blank)
            } else {
                check("the payload is a JSON object", false)
            }

            // Onboarding renames on every continue and takes the slot only at
            // the very end, so that backing out of a wrong tap is possible at
            // all. That split only holds if renaming is genuinely harmless:
            // `adopt(_:)` is the one call allowed to delete letters.
            let lettersBefore = store.letters.count
            let roleBefore = store.role
            let otherBefore = store.name(for: store.role.other)
            store.rename(store.role.other, to: "Somebody else entirely")
            check("naming the other slot is not becoming them",
                  store.role == roleBefore && store.letters.count == lettersBefore,
                  "role \(store.role), \(store.letters.count) letters")
            store.rename(store.role.other, to: otherBefore)

            store.rename(.one, to: "Alex")
        }

        print("— two phones —")
        // A second store on the same box is the other traveller's phone, holding
        // the *same* trip — so it starts from this one's snapshot rather than
        // from whatever happens to be on disk.
        //
        // It used to be built with no snapshot and pick the saved trip up
        // implicitly, which only worked while writes were synchronous. Once they
        // were coalesced it seeded a fresh sample instead, minting new ids for
        // all eleven stamps; the merge unioned them by id, exactly as designed,
        // and the trip quietly ended up with three of everything. Depending on
        // disk timing to decide what a test is testing is the fragility this
        // whole section was supposed to lose.
        let otherBox = LoopbackSyncTransport(named: "checks")
        otherBox.latency = .zero
        let other = TripStore(storeKey: nil, snapshot: store.snapshot,
                              sync: SyncCoordinator(transport: otherBox),
                              ritual: SilentRitualScheduler(),
                              library: TripLibrary(key: "dithoi.library.checks-other"))
        other.role = .two

        do {
            // Both start from the same shared state.
            await store.syncNow()
            await other.syncNow()

            // Each adds a line while the other isn't looking.
            store.add(Expense(date: store.now, amount: 500, currency: .thb, payer: .one,
                              split: .evenly, note: "one's round", country: "Thailand"))
            other.add(Expense(date: other.now, amount: 300, currency: .thb, payer: .two,
                              split: .evenly, note: "two's round", country: "Thailand"))

            await store.syncNow()
            await other.syncNow()
            await store.syncNow()

            check("neither round was lost",
                  store.expenses.contains { $0.note == "two's round" } &&
                  store.expenses.contains { $0.note == "one's round" })
            check("both phones agree on the ledger",
                  Set(store.expenses.map(\.id)) == Set(other.expenses.map(\.id)),
                  "\(store.expenses.count) vs \(other.expenses.count)")

            // Both set a meeting point offline; the later one wins and is announced.
            store.setMeetingPoint(CheckTrip.meetingPointOptions[1])
            try? await Task.sleep(for: .milliseconds(20))
            other.setMeetingPoint(CheckTrip.meetingPointOptions[2])
            await other.syncNow()
            await store.syncNow()
            check("the later meeting point wins",
                  store.meeting.place == CheckTrip.meetingPointOptions[2].place,
                  "got \(store.meeting.place)")
            check("and the loser is told about it",
                  store.sync.notices.contains { $0.text.contains("meeting point") },
                  "notices: \(store.sync.notices.map(\.text))")
            // Losing the round is not the same as never having been there. The
            // place that lost has to stay somewhere both phones can offer it
            // back, or one of them typed a gate the app then forgot.
            await other.syncNow()
            let lost = CheckTrip.meetingPointOptions[1].place
            check("and the place that lost is still on both phones",
                  store.meetingPlaces.contains { $0.place == lost } &&
                  other.meetingPlaces.contains { $0.place == lost },
                  "here \(store.meetingPlaces.map(\.place)), there \(other.meetingPlaces.map(\.place))")
            check("and the two histories agree",
                  store.meetingPlaces.map(\.place) == other.meetingPlaces.map(\.place),
                  "\(store.meetingPlaces.map(\.place)) vs \(other.meetingPlaces.map(\.place))")

            // Each phone names itself in the same round. Both names have to
            // survive, which is what per-slot stamping buys over merging them
            // in the settings blob.
            store.rename(.one, to: "Kim")
            other.rename(.two, to: "Noor")
            await store.syncNow()
            await other.syncNow()
            await store.syncNow()
            check("both renames survived one round",
                  store.name(for: .one) == "Kim" && store.name(for: .two) == "Noor",
                  "\(store.name(for: .one)) / \(store.name(for: .two))")
            check("and both phones agree",
                  other.name(for: .one) == "Kim" && other.name(for: .two) == "Noor",
                  "\(other.name(for: .one)) / \(other.name(for: .two))")

            // A rename must not be able to win an argument about the dates.
            let datesBefore = store.start
            store.rename(.one, to: "Kimberley")
            try? await Task.sleep(for: .milliseconds(20))
            other.setStart(Calendar.trip.date(byAdding: .day, value: 3, to: other.start) ?? other.start)
            await other.syncNow()
            await store.syncNow()
            check("a rename doesn't move the dates",
                  store.start != datesBefore && store.start == other.start,
                  "\(store.start.shortDate) vs \(other.start.shortDate)")
            check("and the rename still stuck", store.name(for: .one) == "Kimberley")

            // The one at home is a third phone on the same channel, pushing
            // under a traveller's role. It must not be able to claim a slot it
            // has only ever read.
            // Same trip, third phone — so from this trip's snapshot, for the
            // same reason as `other` above.
            let atHome = TripStore(storeKey: nil, snapshot: store.snapshot,
                                   sync: SyncCoordinator(transport: {
                                       let box = LoopbackSyncTransport(named: "checks")
                                       box.latency = .zero; return box
                                   }()),
                                   letterPost: LoopbackLetterDropTransport(named: "checks-observer"),
                                   ritual: SilentRitualScheduler(),
                                   library: TripLibrary(key: "dithoi.library.checks-home"))
            atHome.participant = .writer
            atHome.role = .one
            await atHome.syncNow()
            await store.syncNow()
            check("the observer can't take a traveller's name",
                  store.name(for: .one) == "Kimberley", "got \(store.name(for: .one))")

            // A notice is written with whatever the merge just settled on, not
            // with whatever this phone happened to be holding.
            store.sync.notices.forEach(store.sync.dismiss)
            other.setStart(Calendar.trip.date(byAdding: .day, value: 1, to: other.start) ?? other.start)
            await other.syncNow()
            await store.syncNow()
            check("a notice uses the chosen name",
                  store.sync.notices.contains { $0.text.contains("Noor") },
                  "notices: \(store.sync.notices.map(\.text))")

            store.rename(.one, to: "Alex")
            other.rename(.two, to: "Sam")
            await store.syncNow()
            await other.syncNow()
            await store.syncNow()

            // An itinerary edited on one phone reaches the other.
            other.addSegment(title: "Ninh Binh", nights: 2, toLeg: other.legs[1].id)
            await other.syncNow()
            await store.syncNow()
            check("the itinerary crossed over",
                  store.itinerary.allSegments.contains { $0.title == "Ninh Binh" })

            // The journal never does.
            other.save(entry: JournalEntry(dayNumber: 3, date: other.now, city: "Bangkok",
                                           line: "Private to slot two", tags: [],
                                           hasPhoto: false, author: .two))
            await other.syncNow()
            await store.syncNow()
            check("journals never sync",
                  !store.journal.contains { $0.line == "Private to slot two" })

            // Nor do moments, for the same reason and by the same mechanism —
            // there is no field to carry them.
            other.addMoment(note: "The cat that sat on the map")
            await other.syncNow()
            await store.syncNow()
            check("moments never sync",
                  !store.moments.contains { $0.note == "The cat that sat on the map" },
                  "\(store.moments.count) here, \(other.moments.count) there")

            // Two trips are two trips. A payload from a different one is not a
            // conflict to merge, it's somebody else's book.
            let before = store.expenses.count
            var foreign = other.payload
            foreign.tripID = UUID()
            foreign.expenses.append(Expense(date: other.now, amount: 9_999, currency: .thb,
                                            payer: .one, split: .evenly,
                                            note: "Another trip entirely", country: "Nowhere"))
            let (result, refusalNotices) = SyncMerge.merge(local: store.payload, remote: foreign, as: .one)
            check("a payload from another trip is refused",
                  result.expenses.count == before &&
                  !result.expenses.contains { $0.note == "Another trip entirely" })
            check("and says so rather than silently doing nothing",
                  refusalNotices.contains { $0.text.contains("different trip") })
        }

        print("— a meeting point nobody agreed —")
        do {
            // A blank trip carries a `MeetingPoint` that exists without being an
            // answer: empty place, empty detail, `.distantPast`. Three screens
            // drew it as though somebody had chosen it. Papers printed
            // ". Agreed at 00:53." — a bare full stop where the place goes, and
            // year one put through a time formatter — and Separated, the 2am
            // screen, said "Go to the" over an empty card captioned "show this
            // to a driver". `TodayView` was asking the question correctly and
            // keeping the answer private, which is how the other two never got
            // it.
            let blank = TripStore(storeKey: nil,
                                  sync: SyncCoordinator(transport: {
                                      let box = LoopbackSyncTransport(named: "checks-nopoint")
                                      box.latency = .zero
                                      box.erase()
                                      return box
                                  }()),
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-nopoint"))
            check("a blank trip has agreed nowhere", !blank.meeting.isSet)
            check("and its stamp is not a time of day",
                  blank.meeting.setAt == .distantPast,
                  "\(blank.meeting.setAt)")

            // Whitespace is not a place. `isSet` reads `placeKey`, which trims,
            // so the three screens can't disagree about whether " " counts —
            // and `meetingLine` used to ask `place.isEmpty`, which says it does.
            blank.setMeetingPoint(MeetingPoint(place: "   ", detail: "", localScript: "",
                                               setAt: blank.now))
            check("a place of nothing but spaces is still nowhere", !blank.meeting.isSet)

            blank.setMeetingPoint(MeetingPoint(place: "The bridge", detail: "north end",
                                               localScript: "", setAt: blank.now))
            check("and a real one is set", blank.meeting.isSet)
            check("with a stamp somebody actually made",
                  blank.meeting.setAt > .distantPast)

            // The headline's fallback used to be unreachable: splitting "" gives
            // [""] and never nil, so `?? "meeting point"` could not fire and the
            // screen read "Go to the" over a blank line. Same shape as
            // `DayDetailView.cityName` — a `??` behind a split only fires if the
            // split can produce nothing.
            check("splitting an empty detail answers a blank, never nil",
                  "".components(separatedBy: ",").first == "")
        }

        print("— where they have met before —")
        do {
            // Tonight's meeting point is one value, and setting tomorrow's used
            // to be the end of yesterday's: the picker offered "somewhere
            // you've used" and could name exactly one place, whatever had been
            // typed before it. A gate you walked to and can describe is worth
            // more on day 40 than on day 12.
            let met = TripStore(storeKey: nil, snapshot: store.snapshot,
                                ritual: SilentRitualScheduler(),
                                library: TripLibrary(key: "dithoi.library.checks-met"))
            met.role = .one

            met.setMeetingPoint(MeetingPoint(place: "The bridge", detail: "north end, by the steps",
                                             localScript: "สะพาน", setAt: met.now))
            try? await Task.sleep(for: .milliseconds(20))
            met.setMeetingPoint(MeetingPoint(place: "Bến Thành Market", detail: "the clock tower",
                                             localScript: "", setAt: met.now))

            check("last night's place is still there",
                  met.meetingPlaces.contains { $0.place == "The bridge" },
                  met.meetingPlaces.map(\.place).joined(separator: ", "))
            check("and tonight's is too", met.meetingPlaces.contains { $0.place == "Bến Thành Market" })
            let places = met.meetingPlaces.map(\.place)
            check("most recent first",
                  (places.firstIndex(of: "Bến Thành Market") ?? .max)
                      < (places.firstIndex(of: "The bridge") ?? .max),
                  places.joined(separator: ", "))

            // Same gate, typed again with the detail corrected. One row, not
            // two: the place is the identity, and a list with "The bridge"
            // twice is a list nobody can pick from.
            try? await Task.sleep(for: .milliseconds(20))
            met.setMeetingPoint(MeetingPoint(place: "the BRIDGE  ", detail: "south end now",
                                             localScript: "สะพาน", setAt: met.now))
            check("the same place typed twice is one row",
                  met.meetingPlaces.filter { $0.placeKey == "the bridge" }.count == 1,
                  met.meetingPlaces.map(\.place).joined(separator: ", "))
            check("and it is the newer wording that survives",
                  met.meetingPlaces.first { $0.placeKey == "the bridge" }?.detail == "south end now")
            check("and it is stored as it will be read",
                  met.meetingPlaces.contains { $0.place == "the BRIDGE" },
                  met.meetingPlaces.map(\.place).joined(separator: ", "))

            // The script rides with the place it was written for. It was drawn
            // in green on three screens and typeable on none, so the only ones
            // that ever had one were the four the trip was packed with — in
            // Thai, for twenty-six days in Vietnam and fifteen in Korea.
            check("a place keeps the script it was written with",
                  met.meetingPlaces.first { $0.placeKey == "the bridge" }?.localScript == "สะพาน",
                  met.meetingPlaces.first { $0.placeKey == "the bridge" }?.localScript ?? "nothing")
            check("and a place written without one has none",
                  met.meetingPlaces.first { $0.placeKey == "bến thành market" }?.localScript.isEmpty == true)
            check("so no script sits under another place's name",
                  met.meetingPlaces.allSatisfy { point in
                      point.localScript.isEmpty ||
                      met.meetingPlaces.filter { $0.localScript == point.localScript }.count == 1
                  },
                  met.meetingPlaces.map { "\($0.place)/\($0.localScript)" }.joined(separator: ", "))

            // A place with no name is a row nobody can read, and a trip that
            // has never met anywhere carries exactly that.
            let blank = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-met-blank"))
            let heldBefore = blank.meetingPlaces.count
            blank.setMeetingPoint(MeetingPoint(place: "  ", detail: "", localScript: "", setAt: blank.now))
            check("a nameless place is never remembered",
                  blank.meetingPlaces.count == heldBefore &&
                  !blank.meetingPlaces.contains { $0.placeKey.isEmpty },
                  "\(blank.meetingPlaces.count) vs \(heldBefore)")

            // The observer's guard is on the whole call, so it can't write the
            // history round the back of it either.
            let home = TripStore(storeKey: nil, snapshot: met.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-met-home"))
            home.participant = .writer
            let known = home.meetingPlaces.count
            home.setMeetingPoint(MeetingPoint(place: "The kitchen", detail: "in Utrecht",
                                              localScript: "", setAt: home.now))
            check("home cannot write the history either",
                  home.meetingPlaces.count == known &&
                  !home.meetingPlaces.contains { $0.place == "The kitchen" },
                  home.meetingPlaces.map(\.place).joined(separator: ", "))

            // Dated, therefore moved by the dates. Every other dated collection
            // is shifted by `setStart`; one that isn't drifts out of the trip.
            let bridgeBefore = met.meetingPlaces.first { $0.placeKey == "the bridge" }?.setAt
            met.setStart(Calendar.trip.date(byAdding: .day, value: 4, to: met.start) ?? met.start)
            let bridgeAfter = met.meetingPlaces.first { $0.placeKey == "the bridge" }?.setAt
            let shifted = Calendar.trip.days(from: bridgeBefore ?? met.now, to: bridgeAfter ?? met.now)
            check("moving the dates moves the history with them", shifted == 4, "\(shifted) days")

            // And it is part of the trip, so it is part of what the trip is.
            let encoded = (try? JSONEncoder().encode(met.snapshot)) ?? Data()
            check("the history survives a round-trip",
                  TripSnapshot.decode(encoded)?.meetingPlaces.map(\.place) == met.meetingPlaces.map(\.place))
            if var json = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
                json.removeValue(forKey: "meetingPlaces")
                let stripped = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                let old = TripSnapshot.decode(stripped)
                check("a trip saved before it existed still opens", old != nil)
                check("and remembers nowhere rather than nothing at all",
                      old?.meetingPlaces.isEmpty == true)
            } else {
                check("the snapshot is a JSON object", false)
            }

            // A phone on the older build says nothing about the history. Saying
            // nothing must not read as "we have met nowhere" — the merge
            // unions, so an erasure here is one phone forgetting for both.
            let wire = (try? JSONEncoder().encode(met.payload)) ?? Data()
            if var json = try? JSONSerialization.jsonObject(with: wire) as? [String: Any] {
                json.removeValue(forKey: "meetingPlaces")
                let stripped = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                if let old = try? JSONDecoder().decode(SyncPayload.self, from: stripped) {
                    let merged = SyncMerge.merge(local: met.payload, remote: old, as: .one).payload
                    check("an older phone takes no place away",
                          Set(merged.meetingPlaces.map(\.placeKey))
                              .isSuperset(of: met.meetingPlaces.map(\.placeKey)),
                          merged.meetingPlaces.map(\.place).joined(separator: ", "))
                    // And what that phone *did* set still has to be offerable,
                    // since its own copy carried no history to bring it over.
                    var older = old
                    older.meetingPoint = StampedMeetingPoint(
                        value: MeetingPoint(place: "Gate 3", detail: "by the taxis",
                                            localScript: "", setAt: met.now),
                        updatedAt: met.now.addingTimeInterval(60), setBy: .two)
                    let after = SyncMerge.merge(local: met.payload, remote: older, as: .one).payload
                    check("and the point it did set joins the history",
                          after.meetingPlaces.contains { $0.place == "Gate 3" },
                          after.meetingPlaces.map(\.place).joined(separator: ", "))
                } else {
                    check("a payload written before the history still decodes", false)
                }
            } else {
                check("the payload is a JSON object", false)
            }
        }

        print("— where you are standing —")
        do {
            // The screen this feeds is the 2am one. It used to print Thailand's
            // numbers under a label computed from the current leg.
            check("Thailand's numbers are Thailand's",
                  CountryFacts.lookup("Thailand")?.emergencyLine == "191 police · 1669 medical")
            check("and Vietnam's are not",
                  CountryFacts.lookup("Vietnam")?.emergencyLine == "113 police · 115 medical · 114 fire")
            check("and Korea's are neither",
                  CountryFacts.lookup("South Korea")?.emergencyLine == "112 police · 119 medical")

            check("no two countries on this trip share a line",
                  Set(store.legs.compactMap { CountryFacts.lookup($0.country)?.emergencyLine }).count
                      == store.legs.count)

            // The itinerary editor asks for the country with a TextField, so
            // most of what people type will not be in the table.
            check("somewhere the app has never heard of returns nothing",
                  CountryFacts.lookup("Wakanda") == nil)
            check("and so does an empty country",
                  CountryFacts.lookup("") == nil && CountryFacts.lookup("   ") == nil)

            check("the spelling people use resolves",
                  CountryFacts.lookup("Korea") == CountryFacts.lookup("South Korea")
                      && CountryFacts.lookup("Việt Nam") == CountryFacts.lookup("Vietnam")
                      && CountryFacts.lookup("  the netherlands ") == CountryFacts.lookup("Netherlands"))
            // Same number, different country — the line matches, the name on
            // the label doesn't, which is the whole point of keeping `country`.
            check("the EU answers 112 everywhere",
                  ["Portugal", "Netherlands", "Spain", "Greece"].allSatisfy {
                      CountryFacts.lookup($0)?.emergencyLine == "112 for anything"
                  })
            check("but each one still says its own name",
                  CountryFacts.lookup("Holland")?.country == "Netherlands"
                      && CountryFacts.lookup("Portugal")?.country == "Portugal")

            // Every leg of the packed trip must be able to speak for itself, or
            // the screen goes quiet in a country they are actually visiting.
            check("every country the packed trip visits is covered",
                  store.legs.allSatisfy { CountryFacts.lookup($0.country) != nil },
                  store.legs.filter { CountryFacts.lookup($0.country) == nil }.map(\.country).joined(separator: ", "))
            check("and the name on the label is the name in the table",
                  store.legs.allSatisfy { CountryFacts.lookup($0.country)?.country == $0.country })
            check("a number is only ever digits",
                  CountryFacts.lookup("Thailand")?.emergency.allSatisfy {
                      $0.number.allSatisfy(\.isNumber) && !$0.number.isEmpty
                  } == true)

            // The card's other two columns. Both are optional per country, and
            // both are governed by the same rule the numbers are: say nothing
            // rather than say something that might be wrong.
            let table = CountryFacts.everyCountry

            // The invariant that keeps the phrases honest. A phrase is written
            // in one script, and the country that has no single language has no
            // single script either — so a country claiming phrases while
            // declining to name a language is claiming to know something it has
            // already said it doesn't.
            check("nothing has phrases without a language",
                  table.allSatisfy { $0.phrases == nil || $0.language != nil },
                  table.filter { $0.phrases != nil && $0.language == nil }
                      .map(\.country).joined(separator: ", "))
            check("and the ones with no single language stay quiet",
                  ["Belgium", "India", "Canada", "Switzerland", "South Africa", "Luxembourg"]
                      .allSatisfy { CountryFacts.lookup($0)?.phrases == nil })

            check("a phrase is never blank",
                  table.compactMap(\.phrases).allSatisfy {
                      !$0.doctor.trimmingCharacters(in: .whitespaces).isEmpty
                          && !$0.lostPassport.trimmingCharacters(in: .whitespaces).isEmpty
                  })
            // A phrase that came back as the English is a phrase nobody wrote —
            // the failure mode of a table filled in by copying the column
            // header down.
            check("and never just the English it stands in for",
                  table.compactMap(\.phrases).allSatisfy {
                      $0.doctor != "I need a doctor" && $0.lostPassport != "I've lost my passport"
                  })
            check("and the two are never the same sentence",
                  table.compactMap(\.phrases).allSatisfy { $0.doctor != $0.lostPassport })

            // Two countries can share a language label and not a script. Both
            // say "Mandarin"; one is written in traditional characters and the
            // other in simplified, which is why phrases hang off the country.
            check("a shared language label doesn't mean a shared script",
                  CountryFacts.lookup("Taiwan")?.phrases != CountryFacts.lookup("China")?.phrases)

            check("every country that names sockets names some",
                  table.compactMap(\.power).allSatisfy { !$0.sockets.isEmpty })
            check("and says what comes out of them",
                  table.compactMap(\.power).allSatisfy { $0.mains.contains("V") })
            check("sockets are single letters",
                  table.compactMap(\.power).allSatisfy {
                      $0.sockets.allSatisfy { $0.count == 1 && $0.allSatisfy(\.isLetter) }
                  })
            check("every country the packed trip visits knows its sockets",
                  store.legs.allSatisfy { CountryFacts.lookup($0.country)?.power != nil },
                  store.legs.filter { CountryFacts.lookup($0.country)?.power == nil }
                      .map(\.country).joined(separator: ", "))
            check("Korea runs at 60 Hz and Thailand at 50",
                  CountryFacts.lookup("South Korea")?.power?.mains == "220 V · 60 Hz"
                      && CountryFacts.lookup("Thailand")?.power?.mains == "230 V · 50 Hz")
            check("and the socket line reads as a line",
                  CountryFacts.lookup("South Korea")?.power?.socketLine == "Type C, F")

            // What Papers asks before drawing a row at all. A country the app
            // knows only two phone numbers about has no card worth opening —
            // the numbers are already on the Separated screen.
            check("a card is only offered when there is one",
                  CountryFacts.lookup("Thailand")?.hasCard == true
                      && CountryFacts.lookup("Sri Lanka")?.hasCard == true)
            check("and every leg of the packed trip has one",
                  store.legs.allSatisfy { CountryFacts.lookup($0.country)?.hasCard == true })
        }

        print("— what a transport has to do —")
        do {
            // Both CloudKit transports are written and neither has ever
            // executed, so what pins them is a written-down set of semantics
            // that the implementations which *do* run have to satisfy. Running
            // it here means the two can't quietly come to mean different
            // things — which is exactly what had happened to the old CloudKit
            // transport, where one fixed record name meant "the trip" while
            // every caller meant "this trip".
            let conformanceBox = LoopbackSyncTransport(named: "checks-conformance")
            conformanceBox.latency = .zero
            conformanceBox.erase()
            for result in await TransportConformance.sync(conformanceBox, tripID: UUID()) {
                check(result.label, result.passed, result.detail)
            }
            conformanceBox.erase()

            let conformancePost = LoopbackLetterDropTransport(named: "checks-conformance")
            conformancePost.erase()
            for result in await TransportConformance.letters(conformancePost, tripID: UUID()) {
                check(result.label, result.passed, result.detail)
            }
            conformancePost.erase()

            // The inert pair. They can be built and asked what they are, which
            // is all that is honest to claim about them on a machine with no
            // developer team — the suite above is waiting for the day there is
            // one.
            let cloud = CloudKitSyncTransport()
            check("the real transport says it isn't usable in this build",
                  !cloud.isAvailable && cloud.unavailableReason != nil)
            check("and refuses rather than pretending",
                  await { () -> Bool in
                      do { _ = try await cloud.pull(tripID: UUID()); return false }
                      catch { return true }
                  }())
            // The letter box gets the full switched-off contract rather than a
            // pair of ad-hoc lines, because the shape of its failure is what
            // `postLetters` and home mode both read.
            for result in await TransportConformance.inert(CloudKitLetterDropTransport(),
                                                           tripID: UUID()) {
                check(result.label, result.passed, result.detail)
            }

            // The line C1 was actually missing. `CloudKitLetterDropTransport`
            // has existed and compiled since Phase 2 and was constructed
            // nowhere: `TripStore` built a loopback unconditionally while
            // `SyncCoordinator` probed and picked, so switching iCloud on would
            // have moved the trip and left the letters on a file. Both branches,
            // because only one of them is reachable in this build.
            //
            // The no-iCloud branch used to be the file box, which wrote every
            // sealed letter in clear into the container root, in every backup.
            check("with no iCloud, letters go nowhere and say so",
                  chooseLetterTransport(cloudAvailable: false) is ClosedLetterDropTransport)
            check("and with iCloud they go to iCloud",
                  chooseLetterTransport(cloudAvailable: true) is CloudKitLetterDropTransport)
            check("a store picks the same way, rather than always the file",
                  TripStore(storeKey: nil, ritual: SilentRitualScheduler()).letterPost
                      is ClosedLetterDropTransport)
            for result in await TransportConformance.inert(ClosedLetterDropTransport(),
                                                           tripID: UUID()) {
                check("closed letterbox: " + result.label, result.passed, result.detail)
            }
            check("and the loopback admits it isn't a postal service",
                  LoopbackLetterDropTransport().unavailableReason?.isEmpty == false)

            // The sync line. The default coordinator used to fall back to the
            // loopback, which succeeds, so every screen said "synced just now"
            // about a file on this phone.
            let defaultSync = SyncCoordinator()
            check("with no iCloud, the trip's sync is CloudKit, switched off",
                  defaultSync.transport is CloudKitSyncTransport
                      && !defaultSync.transport.isAvailable)
            check("and the sync line says the trip is on this phone",
                  defaultSync.summary == "on this phone", defaultSync.summary)
            check("with the reason one tap further in",
                  defaultSync.detail?.isEmpty == false)
            check("and its transport isn't named as iCloud",
                  defaultSync.transportName == "Only on this phone")
            let offline = TripStore(storeKey: nil, ritual: SilentRitualScheduler())
            await offline.syncNow()
            check("a round on a build with no iCloud stamps nothing",
                  offline.sync.lastSyncedAt == nil)
            check("and still says on this phone afterwards",
                  offline.sync.summary == "on this phone")

            // A home phone with a closed letterbox: the post is skipped, so
            // the problem is the plain reason, not a refusal dressed as an
            // error.
            let closedHome = TripStore(storeKey: nil, ritual: SilentRitualScheduler())
            closedHome.participant = .writer
            closedHome.writeTo(.one)
            let closedDraft = closedHome.startLetter(title: "Waiting", condition: .nextOnline)
            closedHome.seal(closedDraft.id)
            await closedHome.postLetters()
            check("a closed letterbox isn't recorded as a failed post",
                  closedHome.lastPostFailure == nil && closedHome.lastPostedAt == nil)
            check("but the letters are stuck, and it says why",
                  closedHome.lettersAreStuck
                      && closedHome.letterPostProblem == ClosedLetterDropTransport().unavailableReason)
        }

        print("— no plaintext copies outside the store —")
        do {
            // The boxes earlier builds left in the container root are swept.
            let root = Storage.container
            let strays = ["loopback-shared.json", "letters-one.json", "letters-two.json"]
            for name in strays {
                try? Data("{}".utf8).write(to: root.appendingPathComponent(name))
            }
            let keeper = root.appendingPathComponent("keep-me.json")
            try? Data("{}".utf8).write(to: keeper)
            let swept = Storage.sweepStrayLoopbackFiles()
            check("the sweep removes every stray box in the root",
                  Set(swept) == Set(strays), "\(swept)")
            check("and nothing of them is left",
                  strays.allSatisfy { !FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) })
            check("and it leaves other files alone",
                  FileManager.default.fileExists(atPath: keeper.path))
            try? FileManager.default.removeItem(at: keeper)

            // The boxes the checks still use live in their own folder, out of
            // backups, never in the root.
            let box = LoopbackSyncTransport(named: "checks-where")
            box.latency = .zero
            try? await box.push(SyncPayload.empty(tripID: UUID()))
            let rootNames = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            check("a loopback box is not written to the container root",
                  !rootNames.contains("loopback-checks-where.json"))
            check("it is in the loopback folder",
                  FileManager.default.fileExists(atPath: Storage.loopbackDirectory
                      .appendingPathComponent("loopback-checks-where.json").path))
            let excluded = (try? Storage.loopbackDirectory
                .resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
            check("and that folder is out of backups", excluded == true)
            box.erase()
        }

        print("— two phones find the same trip —")
        do {
            // The bug this whole flow exists to remove, written down as the
            // thing that must not be true again: every phone mints its own
            // `tripID` on first launch, so two people who each walked
            // onboarding had two trips, and the failure was *silent* — the
            // second phone's pull found no record, which is indistinguishable
            // from being first, so it pushed its own blank trip and reported
            // success. Two phones, both saying synced, neither carrying a word
            // the other wrote.
            let mine = TripStore(storeKey: nil, ritual: SilentRitualScheduler())
            let theirs = TripStore(storeKey: nil, ritual: SilentRitualScheduler())
            check("two phones start on different trips",
                  mine.tripID != theirs.tripID,
                  "which is why an invitation has to move the id")

            // The record name is the only thing an invitation carries that
            // identifies the trip, so the mapping has to survive the round
            // trip. Adopting the wrong id is not a visible failure; it is the
            // silent one above, arrived at from the other end.
            let zone = CKRecordZone.ID(zoneName: CloudKitZone.zoneName,
                                       ownerName: CKCurrentUserDefaultName)
            let name = CloudKitZone.tripRecordID(theirs.tripID, in: zone).recordName
            check("a trip's record name reads back as that trip",
                  CloudKitZone.tripID(fromRecordName: name) == theirs.tripID)
            check("and a record that isn't a trip's answers nothing",
                  CloudKitZone.tripID(fromRecordName: "LetterDrop-\(UUID().uuidString)") == nil,
                  "letters live in the same zone, so the prefix is checked and not trimmed")
            check("and neither does a name with no id behind it",
                  CloudKitZone.tripID(fromRecordName: "Trip-not-a-uuid") == nil)

            // The join itself. Everything else in this section is about
            // learning the id; this is the one call that takes it on.
            let joined = theirs.tripID
            mine.joinTrip(joined, as: .two)
            check("joining takes on the other phone's trip", mine.tripID == joined,
                  "the id is the whole point — `SyncMerge` refuses a mismatch")
            check("and the slot the invitation named", mine.role == .two)
            check("and the trip is open rather than back at onboarding",
                  mine.hasOpened && mine.origin == .packed,
                  "it arrives packed, from the other phone")

            // A trip that was already here is shelved, not overwritten.
            // Joining somebody must not be a way to lose your own two months.
            let held = TripStore(storeKey: nil, ritual: SilentRitualScheduler())
            held.hasOpened = true
            held.tripName = "The one already here"
            let shelfBefore = held.library.shelf.count
            held.joinTrip(joined, as: .one)
            check("an open trip goes to the shelf rather than being lost",
                  held.library.shelf.count == shelfBefore + 1,
                  "\(shelfBefore) → \(held.library.shelf.count)")
            check("and what it cost was counted before it was spent",
                  held.tripID == joined)

            // Following the same link twice is ordinary — it is a message in
            // somebody's chat app — and must not shelve the trip and start over.
            let again = mine.library.shelf.count
            mine.offerInvitation(CloudKitSyncTransport.Invitation(
                tripID: joined, slot: .two, title: "Somewhere warm"))
            check("an invitation to the trip already here asks nothing",
                  mine.pendingInvitation == nil && mine.library.shelf.count == again)
            mine.offerInvitation(CloudKitSyncTransport.Invitation(
                tripID: UUID(), slot: .one, title: "A different trip"))
            check("but one to a different trip does", mine.pendingInvitation != nil)
            mine.declineInvitation()
            check("and declining leaves the trip alone",
                  mine.pendingInvitation == nil && mine.tripID == joined)

            // An invitation is a write, so the transport with nobody to invite
            // has to refuse it in the shape everything else refuses in —
            // `TransportConformance.inert`'s rule, one call over.
            let box = LoopbackSyncTransport(named: "checks-invitation")
            check("a transport with nobody to invite refuses",
                  await { () -> Bool in
                      do {
                          _ = try await box.invitation(to: UUID(), named: "Trip", inviting: .two)
                          return false
                      } catch let error as SyncError {
                          return error.isFatal
                      } catch { return false }
                  }(),
                  "a link that opens nothing is the 'Send to —' button again")
        }

        print("— a letter that doesn't get out —")
        do {
            // `postLetters` used to be `try?`. A sealed letter that never left
            // the phone was indistinguishable from a delivered one — same
            // haptic, same animation, same "N delivered" on the home screen.
            final class RefusingPost: LetterDropTransport {
                let name = "Refuses"
                var isAvailable: Bool { true }
                var unavailableReason: String? { nil }
                var posts = 0
                func post(_ drop: LetterDrop, to recipient: Traveller,
                          sealingTo key: Data?) async throws {
                    posts += 1
                    throw SyncError.transport("the wind took it")
                }
                func collect(tripID: UUID, for recipient: Traveller,
                             opening key: Curve25519.KeyAgreement.PrivateKey?) async throws -> LetterDrop? {
                    throw SyncError.transport("the wind took it")
                }
            }

            let refusing = RefusingPost()
            // `.blank`, so the one sealed letter counted below is the one
            // written here rather than twelve out of `SampleTrip`.
            let home = TripStore(storeKey: nil, letterPost: refusing,
                                 ritual: SilentRitualScheduler())
            home.participant = .writer
            home.writeTo(.one)
            let draft = home.startLetter(title: "Nothing gets out", condition: .nextOnline)
            home.updateDraft(draft.id, paragraphs: ["Sealed, and going nowhere."])
            home.seal(draft.id)

            check("nothing has been posted yet", home.lastPostedAt == nil)
            await home.postLetters()
            check("a post that fails is recorded", home.lastPostFailure != nil,
                  "the failure was swallowed")
            check("and does not count as having been sent", home.lastPostedAt == nil)
            check("so the writing side knows the letters are stuck", home.lettersAreStuck)
            check("and has a sentence to show for it",
                  home.letterPostProblem?.isEmpty == false)
            check("the letter itself is untouched — sealed, and still to go",
                  home.sealedByWriter.count == 1)

            // Every foreground re-posts, which is the retry. What was missing
            // was anybody knowing in between.
            let working = LoopbackLetterDropTransport(named: "checks-poststate")
            working.erase()
            let recovered = TripStore(storeKey: nil, snapshot: home.snapshot,
                                      letterPost: working, ritual: SilentRitualScheduler())
            recovered.participant = .writer
            await recovered.postLetters()
            check("a post that works clears the failure", recovered.lastPostFailure == nil)
            check("and stamps when it went", recovered.lastPostedAt != nil)
            // And still stuck, which is the whole of C1 in one assertion: the
            // write succeeded, and it succeeded into a file on this phone. A
            // loopback that reported itself a working postal service is exactly
            // how home mode came to promise deliveries it has never made.
            check("but a file on this phone is still not a postal service",
                  recovered.lettersAreStuck)
            check("and it says which of the two it is",
                  recovered.letterPostProblem == working.unavailableReason)
            working.erase()

            // The asymmetry, on purpose. Telling her a fetch failed tells her a
            // box exists, which is the one thing the addressing withholds.
            let her = TripStore(storeKey: nil, letterPost: refusing,
                                ritual: SilentRitualScheduler())
            her.adopt(.one)
            let arrived = await her.collectLetters()
            check("a failed collection is silent", arrived.isEmpty)
            check("and records nothing she could read as a letter box",
                  her.lastPostFailure == nil && her.lastPostedAt == nil)
        }

        print("— the evening ritual —")
        do {
            var clock = RitualClock()
            check("with nothing learned it falls back to 21:30",
                  clock.learnedMinute == RitualClock.fallbackMinute)
            check("and doesn't jitter until it has a habit",
                  clock.minute(forDay: 3) == RitualClock.fallbackMinute)

            // Three nights around 22:40, one stray 03:10 airport entry.
            func at(_ hour: Int, _ minute: Int) -> Date {
                Calendar.trip.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
            }
            clock.observe(at(22, 30))
            clock.observe(at(22, 50))
            clock.observe(at(22, 40))
            clock.observe(at(3, 10))
            check("the median ignores the 3am outlier",
                  clock.learnedMinute >= 22 * 60 && clock.learnedMinute <= 23 * 60,
                  "got \(clock.learnedMinute / 60):\(String(format: "%02d", clock.learnedMinute % 60))")
            check("it has learned something", clock.hasLearned)
            check("never at the same minute twice",
                  clock.minute(forDay: 34) != clock.minute(forDay: 35))
            check("but the same day always agrees with itself",
                  clock.minute(forDay: 34) == clock.minute(forDay: 34))
            check("and never before 17:00 or after 23:45",
                  (1...61).allSatisfy { clock.minute(forDay: $0) >= 17 * 60 && clock.minute(forDay: $0) <= 23 * 60 + 45 })

            // A fortnight is the window; older nights fall out of it.
            for _ in 0..<20 { clock.observe(at(19, 0)) }
            check("only the last fortnight counts",
                  clock.learnedMinute == 19 * 60, "got \(clock.learnedMinute)")

            // Crossing a border must not move the habit. Observations are
            // wall-clock minutes, so before this they were counted in whatever
            // zone the phone happened to be in — fly Amsterdam → Bangkok and a
            // learned 22:40 becomes 04:40, night after night, until the prompt
            // has quietly relocated to breakfast.
            let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
            let bangkok = TimeZone(identifier: "Asia/Bangkok")!
            var home = Calendar.trip
            home.timeZone = amsterdam

            var travelling = RitualClock()
            let nights = (0..<5).map { offset in
                home.date(from: DateComponents(year: 2027, month: 4, day: 3 + offset,
                                               hour: 22, minute: 40))!
            }
            for night in nights.prefix(3) { travelling.observe(night, in: amsterdam) }
            let learnedAtHome = travelling.learnedMinute
            check("the habit is half ten at night", learnedAtHome == 22 * 60 + 40,
                  "got \(learnedAtHome / 60):\(String(format: "%02d", learnedAtHome % 60))")

            // The same instants, now read on a phone that has flown.
            for night in nights.suffix(2) { travelling.observe(night, in: bangkok) }
            check("and it stays there after the flight",
                  travelling.learnedMinute == learnedAtHome,
                  "moved to \(travelling.learnedMinute / 60):\(String(format: "%02d", travelling.learnedMinute % 60))")
            check("because the clock remembers which zone it learned in",
                  travelling.zoneID == amsterdam.identifier)

            // A clock saved before zones existed keeps working.
            let legacy = RitualClock(observations: [22 * 60])
            check("a clock with no zone still answers", legacy.learnedMinute == 22 * 60)

            var offers = BackfillOffers()
            check("yesterday with no page is offered",
                  offers.candidate(today: 36, writtenDays: [34]) == 35)
            check("a written night is not",
                  offers.candidate(today: 36, writtenDays: [34, 35]) == nil)
            check("an older missed night is left alone",
                  offers.candidate(today: 36, writtenDays: [35]) == nil)
            offers.markOffered(35)
            check("asked once, never again",
                  offers.candidate(today: 36, writtenDays: [34]) == nil)

            // The store observes the clock only from tonight's page.
            let solo = TripStore(sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "ritual")),
                                 ritual: SilentRitualScheduler())
            let learnedBefore = solo.ritualClock.observations.count
            solo.save(entry: JournalEntry(dayNumber: solo.dayNumber, date: solo.now,
                                          city: "Chiang Mai", line: "Tonight", tags: [],
                                          hasPhoto: false, author: solo.role))
            check("tonight's page teaches the clock",
                  solo.ritualClock.observations.count == learnedBefore + 1)
            solo.save(entry: JournalEntry(dayNumber: 3, date: solo.date(forDay: 3),
                                          city: "Bangkok", line: "Backfilled", tags: [],
                                          hasPhoto: false, author: solo.role))
            check("backfilling day 3 at lunchtime does not",
                  solo.ritualClock.observations.count == learnedBefore + 1)
        }

        print("— the book —")
        do {
            let plan = store.bookPlan
            check("every written day is a spread",
                  plan.dayCountInBook == store.myEntries.count,
                  "\(plan.dayCountInBook) of \(store.myEntries.count)")
            // The insides of the covers are half of the first spread and half
            // of the last, and neither prints.
            check("page count is two per spread, less the insides of the covers",
                  plan.pageCount == plan.spreads.count * 2 - 2, "\(plan.pageCount) pages")
            check("it opens on the half-title, then the title spread, then the contents",
                  Array(plan.spreads.prefix(3)) == [.opening, .title, .contents(page: 0)])
            check("and the contents start on page 4, after the route",
                  plan.firstPage(ofSpread: BookSpread.contents(page: 0).id) == 4)
            let printedRows = BookPlan.contentsRows(plan.sections)
            check("the printed contents list every section past the front matter",
                  printedRows.count == plan.sections.count - 2
                      && printedRows.allSatisfy { $0.firstPage > 5 },
                  "\(printedRows.map(\.title))")
            check("and its first country row is on the page that opens it",
                  printedRows.first { $0.title != "Before we left" }.map { row in
                      guard case .countryOpener(_, let country, _, _, _, _, _, _, _) = plan.spreads[row.firstPage / 2] else { return false }
                      return row.title.hasPrefix(country)
                  } ?? false, "\(printedRows.first?.title ?? "—")")

            // Contents longer than a page turn onto the facing one, and longer
            // than a spread take another; no row is printed twice or dropped.
            for rows in [0, 1, 10, 11, 15, 20, 21, 29, 41] {
                let sections = (0..<rows).map { BookSection(title: "Row \($0)", firstPage: 10 + $0 * 2, lastPage: 11 + $0 * 2) }
                let spreads = BookPlan.contentsSpreadCount(rows: rows)
                let printed = (0..<spreads).flatMap { page in
                    (0..<2).flatMap { half in BookPlan.contentsRows(sections, page: page, half: half).map(\.title) }
                }
                check("\(rows) contents rows print once each, on \(spreads) spread\(spreads == 1 ? "" : "s")",
                      printed == sections.map(\.title)
                          && spreads == max(1, Int((Double(rows) / Double(BookPlan.contentsRowsPerPage * 2)).rounded(.up))),
                      "\(printed.count) of \(rows)")
            }

            // A trip of many short legs: two contents spreads, and the
            // numbers still point at the countries.
            let shortLegs = (0..<24).map { index in
                Leg(country: "Country \(index)", currency: .eur,
                    segments: [Segment(title: "Stop \(index)", startDay: 1 + index * 2, endDay: 3 + index * 2)])
            }
            let shortEntries = shortLegs.map { leg in
                JournalEntry(dayNumber: leg.startDay, date: store.now, city: leg.country,
                             line: "A night", tags: [], hasPhoto: false, author: store.role)
            }
            let tall = BookPlan.build(entries: shortEntries, legs: shortLegs, stamps: [])
            check("twenty-five rows take two contents spreads",
                  tall.contentsSpreadCount == 2, "\(tall.contentsSpreadCount)")
            check("and every country's row names the page its opener is on",
                  BookPlan.contentsRows(tall.sections).filter { $0.title.hasPrefix("Country") }.allSatisfy { row in
                      guard case .countryOpener(_, let country, _, _, _, _, _, _, _) = tall.spreads[row.firstPage / 2] else { return false }
                      return row.title.hasPrefix(country + " ·")
                  })

            // Nights with no page. The book used to close over them silently;
            // the page after a gap now says which days it skipped.
            let written = Set(store.myEntries.map(\.dayNumber))
            let lastWritten = written.max() ?? 0
            let expectedSkipped = lastWritten > 0 ? (1...lastWritten).filter { !written.contains($0) }.count : 0
            check("the missed nights add up to the days without a page",
                  plan.skippedDays == expectedSkipped, "\(plan.skippedDays) vs \(expectedSkipped)")
            check("and each gap ends the night before a written page",
                  plan.missedBefore.allSatisfy { id, days in
                      store.myEntries.first { $0.id == id }?.dayNumber == days.upperBound + 1
                  })
            check("and none is after the last page",
                  plan.missedBefore.values.allSatisfy { $0.upperBound < lastWritten })
            check("one missed night is a day, two are a range",
                  BookPlan.missedLine(13...13) == "Day 13 · no page"
                      && BookPlan.missedLine(13...14) == "Days 13–14 · no page")
            let gappy = [3, 4, 8].map { day in
                JournalEntry(dayNumber: day, date: store.now, city: "", line: "x", tags: [],
                             hasPhoto: false, author: store.role)
            }
            let gaps = BookPlan.build(entries: gappy, legs: store.legs, stamps: [])
            check("a gap before the first page counts from day 1, and between pages from the last",
                  gaps.missedBefore[gappy[0].id] == 1...2 && gaps.missedBefore[gappy[1].id] == nil
                      && gaps.missedBefore[gappy[2].id] == 5...7 && gaps.skippedDays == 5,
                  "\(gaps.missedBefore.values.map { "\($0)" })")
            check("and closes on the colophon", plan.spreads.last == .closing)
            check("page 1 is the half-title, a right-hand page on its own",
                  plan.firstPage(ofSpread: BookSpread.opening.id) == 1)

            // The bug this replaces: spreads numbered (1, 2), (3, 4), so a
            // day's photograph printed on a right-hand page and its line on the
            // back of the same leaf. Facing pages are an even page and the odd
            // one after it.
            let dayPages = plan.spreads.compactMap { spread -> Int? in
                guard case .day = spread else { return nil }
                return plan.firstPage(ofSpread: spread.id)
            }
            check("every day's photograph faces its line",
                  !dayPages.isEmpty && dayPages.allSatisfy { $0.isMultiple(of: 2) },
                  "\(dayPages.prefix(6))")

            // The last page with content on it is the one before the notes
            // pages and the colophon.
            let lastContent = BookPlan.leftPage(ofSpreadAt: plan.spreads.count - 1 - plan.notesSpreadCount) - 1
            check("contents cover every page up to the notes",
                  plan.sections.last?.lastPage == lastContent,
                  "ends at \(plan.sections.last?.lastPage ?? -1), content to \(lastContent)")
            check("sections never overlap",
                  zip(plan.sections, plan.sections.dropFirst()).allSatisfy { $0.lastPage < $1.firstPage })
            check("no page is written twice",
                  Set(plan.spreads.map(\.id)).count == plan.spreads.count)
            check("the book reaches the fewest pages a printer binds, in an even count",
                  plan.pageCount >= plan.spec.minimumPages && plan.pageCount.isMultiple(of: 2),
                  "\(plan.pageCount)")

            // The night before the flight home. `endDay` is the day they
            // leave, so that day is inside no leg, and the book used to send
            // its page to the back, after every country, under "Elsewhere".
            if let lastLeg = store.legs.last {
                let lastNight = JournalEntry(dayNumber: lastLeg.endDay, date: store.now,
                                             city: "Home soon", line: "Packing", tags: [],
                                             hasPhoto: false, author: store.role)
                let withLast = BookPlan.build(entries: store.myEntries + [lastNight],
                                              legs: store.legs, stamps: store.stamps)
                let page = withLast.firstPage(ofSpread: BookSpread.day(entryID: lastNight.id).id) ?? -1
                let home = withLast.sections.first { $0.firstPage <= page && page <= $0.lastPage }
                check("the last night of the trip is in the last country",
                      home?.title.hasPrefix(lastLeg.country) == true
                          && !withLast.sections.contains { $0.title.hasPrefix("Elsewhere") },
                      "\(home?.title ?? "nowhere")")
            }

            // Thailand → Laos → Thailand. The opener's ordinal was the leg's
            // position found by name with `firstIndex`, so the way back said
            // "First country" — and "3 countries" on the title page.
            if store.legs.count >= 3 {
                var legs = Array(store.legs.prefix(3))
                legs[2].country = legs[0].country
                let entries = legs.map { leg in
                    JournalEntry(dayNumber: leg.startDay, date: store.now, city: leg.country,
                                 line: "A night", tags: [], hasPhoto: false, author: store.role)
                }
                let twice = BookPlan.build(entries: entries, legs: legs, stamps: [])
                let labels = twice.spreads.compactMap { spread -> String? in
                    guard case .countryOpener(_, _, _, _, _, _, let ordinal, let visit, _) = spread else { return nil }
                    return BookPlan.openerLabel(ordinal: ordinal, visit: visit)
                }
                check("a country entered twice is welcomed back, not counted again",
                      labels == ["First country", "Second country", "Back again"], "\(labels)")
            }
            check("the title line counts countries, not legs, and spells both",
                  BookPlan.subtitle(days: 61, countries: 3) == "Sixty-one days, three countries"
                      && BookPlan.subtitle(days: 1, countries: 1) == "One day, one country",
                  BookPlan.subtitle(days: 61, countries: 3))
            check("and drops a clause with nothing in it",
                  BookPlan.subtitle(days: 14, countries: 0) == "Fourteen days")
            check("a section counts nights, and agrees with its number",
                  plan.sections.allSatisfy { !$0.title.contains(" days") && !$0.title.contains("1 nights") },
                  "\(plan.sections.map(\.title))")
            check("past the tenth country the ordinal is a number",
                  BookPlan.openerLabel(ordinal: 11, visit: 1) == "Country 11")

            // A page written somewhere the itinerary no longer covers still
            // belongs in the book. Losing one would be the worst bug this has.
            let orphaned = JournalEntry(dayNumber: store.dayCount + 40, date: store.now,
                                        city: "Nowhere", line: "Off the map", tags: [],
                                        hasPhoto: false, author: store.role)
            let withOrphan = BookPlan.build(entries: store.myEntries + [orphaned],
                                            legs: store.legs, stamps: store.stamps)
            check("a page off the itinerary is still in the book",
                  withOrphan.dayCountInBook == store.myEntries.count + 1)

            // Print maths: 8.5in + 0.125in bleed either side at 300 dpi.
            let spec = BookSpec()
            check("a full-bleed page wants 2,625 px", spec.fullBleedPixels == 2_625,
                  "got \(spec.fullBleedPixels)")
            check("and the trim is one a printer stocks", spec.trimLabel == "8.5 × 8.5 in · square",
                  spec.trimLabel)
            // Squares saved at 8 × 8 are 2,475 px, 283 dpi on this page. That
            // prints as well as 300, and a warning about every photograph
            // already on the phone would be the warning that carries nothing.
            check("a photo cropped for the old trim does not warn",
                  !spec.isSoft(square: 2_475), "\(spec.printedDPI(forSquare: 2_475)) dpi")

            // The check that matters is not the arithmetic, it is that the two
            // subsystems agree. This used to measure 2,600 px and 1,560 px —
            // neither of which the app could produce — while `PhotoStore` saved
            // at 2,048, so every real photo printed soft and every assertion
            // here passed. Measure what the store actually writes.
            let asSaved = PhotoMeasurement(id: UUID(), dayNumber: 34,
                                           pixels: PhotoStore.printLongEdge)
            check("a photo saved by this app prints sharp", !asSaved.isSoft(on: spec),
                  "\(asSaved.dpi(on: spec)) dpi at \(PhotoStore.printLongEdge) px")
            check("and the store keeps them at the book's own size",
                  PhotoStore.printLongEdge == spec.fullBleedPixels)

            let sharp = asSaved
            // A screenshot, or something that arrived over a messaging app.
            let soft = PhotoMeasurement(id: UUID(), dayNumber: 22, pixels: 1_560)
            check("a screenshot at 1,560 px still doesn't", soft.isSoft(on: spec),
                  "\(soft.dpi(on: spec)) dpi")
            check("and the thumbnail is nowhere near print size",
                  PhotoMeasurement(id: UUID(), dayNumber: 1,
                                   pixels: PhotoStore.thumbnailLongEdge).isSoft(on: spec))
            let readiness = PrintReadiness.measure(plan: plan, photos: [sharp, soft],
                                                  entriesWithoutPhoto: 1)
            check("and the print screen names the day", readiness.softPhotos == [22])
            check("a clean book says nothing",
                  PrintReadiness.measure(plan: plan, photos: [sharp], entriesWithoutPhoto: 0).isClean)

            // The printed page has to be square. `BookPDF` draws each half of a
            // spread scaled by `bleedScale` on both axes; it used to use a
            // different ratio for each, so every page came out 1.5% taller than
            // wide — invisible on screen, permanent in a bound book.
            let media = spec.mediaPoints
            let drawnWidth = spec.trimPoints * 2 * spec.bleedScale
            let drawnHeight = spec.trimPoints * spec.bleedScale
            check("bleed scales both axes by the same amount",
                  near(drawnWidth / 2, drawnHeight, 0.0001),
                  "\(drawnWidth / 2) wide vs \(drawnHeight) tall per page")
            check("and a page covers its media box exactly",
                  near(drawnHeight, media, 0.0001), "\(drawnHeight) into \(media)")
            check("so the artwork overflows the trim on every edge",
                  spec.bleedScale > 1 &&
                  near((spec.trimPoints * spec.bleedScale - spec.trimPoints) / 2,
                       spec.bleedPoints, 0.0001))

            let long = BookPlan.build(entries: store.myEntries, legs: store.legs,
                                      stamps: store.stamps, volumes: 2)
            check("two volumes split the days",
                  long.pagesPerVolume.count == 2 && long.pagesPerVolume.allSatisfy { $0 > 0 },
                  "\(long.pagesPerVolume)")

            // The stamps used to be one fixed grid, and everything past about
            // the twentieth was clipped off the page in silence. Walk every
            // page back out and count what it draws.
            for earned in [1, 16, 17, 48, 49, 100] {
                let spreads = BookPlan.stampSpreadCount(earned: earned)
                var drawn: [Int] = []
                for page in 0..<spreads {
                    for half in 0..<2 {
                        if let range = BookPlan.stampRange(spread: page, half: half, earned: earned) {
                            drawn += Array(range)
                        }
                    }
                }
                check("every earned stamp reaches a page, once",
                      drawn == Array(0..<earned), "\(earned) earned, drew \(drawn.count)")
                check("and no stamp page is printed empty",
                      (0..<spreads).allSatisfy { page in
                          (0..<2).contains { half in
                              !(BookPlan.stampRange(spread: page, half: half, earned: earned)?.isEmpty ?? true)
                          }
                      })
            }
            check("nothing earned, no stamps spread",
                  BookPlan.stampSpreadCount(earned: 0) == 0
                      && BookPlan.build(entries: store.myEntries, legs: store.legs,
                                        stamps: store.stamps.map { var s = $0; s.earnedOn = nil; return s })
                          .stampSpreadCount == 0)
        }

        print("— letters, from the other side —")
        do {
            let post = LoopbackLetterDropTransport(named: "checks-letters")
            post.erase()
            // Both phones off the same fixture, so they agree on the trip id
            // the letter box is keyed on.
            let his = TripStore(snapshot: CheckTrip.snapshot(),
                                sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "checks-writer")),
                                letterPost: post, ritual: SilentRitualScheduler())
            his.participant = .writer
            his.writeTo(.one)
            his.letters = []

            let draft = his.startLetter(title: "On the city I grew up next to",
                                        condition: .place("Sài Gòn"))
            his.updateDraft(draft.id, paragraphs: ["Go to Bến Thành early."])
            check("a draft is not sealed", his.writerDrafts.count == 1 && his.sealedByWriter.isEmpty)

            await his.postLetters()
            let dropped = try? await post.collect(tripID: his.tripID, for: his.role, opening: nil)
            check("and a draft never travels", (dropped?.letters.count ?? 0) == 0)

            his.seal(draft.id)
            check("sealing is one-way", his.letters.first { $0.id == draft.id }?.isSealed == true)
            his.updateDraft(draft.id, title: "Changed my mind")
            check("and a sealed letter can't be edited",
                  his.letters.first { $0.id == draft.id }?.title == "On the city I grew up next to")

            await his.postLetters()

            // Her side of the same channel.
            let hers = TripStore(snapshot: CheckTrip.snapshot(),
                                 sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "checks-her")),
                                 letterPost: post, ritual: SilentRitualScheduler())
            // Both sides share this machine's UserDefaults, so say which phone
            // this one is rather than inheriting whatever was saved last.
            hers.participant = .one
            hers.role = .one
            hers.letters = []
            hers.stamps = CheckTrip.stamps(start: hers.start)
            let arrived = await hers.collectLetters()
            check("it reaches her sealed", hers.letters.count == 1)
            check("and doesn't open in Chiang Mai", arrived.isEmpty && hers.letters[0].isOpen == false)

            // The type that carries it has nowhere to put a read receipt.
            let sealedFields = Mirror(reflecting: SealedLetter(hers.letters[0], sealedAt: hers.now))
                .children.compactMap(\.label)
            check("the drop has no field for whether she read it",
                  !sealedFields.contains("openedOn") && !sealedFields.contains("openedPlace")
                  && !sealedFields.contains("receivedAt"),
                  "\(sealedFields)")

            // Standing in Sài Gòn is what opens it — nothing else.
            if let sgn = hers.stamps.first(where: { $0.city == "Sài Gòn" }) {
                hers.arrive(at: sgn)
            }
            let opened = hers.openDueLetters()
            check("arriving opens it", opened.count == 1 && hers.letters[0].isOpen)
            check("and she records where, for her own book",
                  hers.letters[0].openedPlace != nil)

            // Collecting again must not un-open it or duplicate it.
            await hers.collectLetters()
            check("a second collection is a no-op",
                  hers.letters.count == 1 && hers.letters[0].isOpen)

            // And nothing she does can travel back up the channel.
            let after = try? await post.collect(tripID: his.tripID, for: his.role, opening: nil)
            check("her read state never reaches his drop",
                  (after?.letters.count ?? 0) == 1)

            // J9 · a place she has already passed is a dead condition.
            var moment = hers.letterMoment
            check("Sài Gòn is now spent",
                  !LetterCondition.place("Sài Gòn").canStillFire(moment))
            check("Seoul is still live",
                  LetterCondition.place("Seoul").canStillFire(moment))
            check("and yesterday is gone",
                  !LetterCondition.day(hers.dayNumber - 1).canStillFire(moment))
            check("\"next time she's online\" can never miss",
                  LetterCondition.nextOnline.canStillFire(moment))
            moment.justArrived = true
            check("and fires on arrival", LetterCondition.nextOnline.isMet(moment))

            // J10 · the one that never opened.
            let stranded = his.startLetter(title: "Never sent", condition: .place("Ninh Binh"))
            his.seal(stranded.id)
            // Wind his copy of the trip past its end, which is the only state
            // in which "never landed" is a fact rather than a prediction.
            his.setDayCount(1)
            check("a condition that never came true stays sealed",
                  his.undeliveredLetters.contains { $0.id == stranded.id })

            post.erase()
        }

        print("— the letter box is addressed —")
        do {
            let post = LoopbackLetterDropTransport(named: "checks-address")
            post.erase()

            func phone(_ box: String) -> TripStore {
                Storage.forget("dithoi.trip.v3")
                let store = TripStore(snapshot: CheckTrip.snapshot(),
                                      sync: SyncCoordinator(transport: {
                                          let b = LoopbackSyncTransport(named: box)
                                          b.latency = .zero
                                          b.erase()
                                          return b
                                      }()),
                                      letterPost: post,
                                      ritual: SilentRitualScheduler(),
                                      library: TripLibrary(key: "dithoi.library.\(box)"))
                store.letters = []
                return store
            }

            // One observer, writing to the second slot rather than the first —
            // which is the thing that could not be expressed at all before.
            let home = phone("checks-addr-home")
            home.participant = .writer
            home.writeTo(.two)
            let one = home.startLetter(title: "For the other one", condition: .nextOnline)
            home.seal(one.id)
            await home.postLetters()

            let addressee = phone("checks-addr-to")
            addressee.adopt(.two)
            await addressee.collectLetters()
            check("a letter reaches the traveller it was addressed to",
                  addressee.letters.count == 1, "got \(addressee.letters.count)")
            check("and the recipient is a real choice, not the first slot",
                  addressee.role == .two)

            let other = phone("checks-addr-not")
            other.adopt(.one)
            await other.collectLetters()
            check("the other traveller collects nothing at all",
                  other.letters.isEmpty, "got \(other.letters.count)")
            check("so there is nothing on her phone to hide",
                  !other.lettersVisible)
            check("while the phone that has one shows it",
                  addressee.lettersVisible)

            // Re-addressing sends the same sealed set somewhere else.
            home.writeTo(.one)
            await home.postLetters()
            await other.collectLetters()
            check("re-addressing delivers to the new phone", other.letters.count == 1)

            // A drop written before the box had addresses still opens, and reads
            // as post for the slot there was only one of.
            let legacy = """
            {"tripID":"\(home.tripID.uuidString)","letters":[],"updatedAt":0}
            """
            let decoded = try? JSONDecoder().decode(LetterDrop.self, from: Data(legacy.utf8))
            check("a drop posted before addresses still decodes", decoded != nil)
            check("and reads as post for the packed recipient",
                  decoded?.recipient == CheckTrip.letterRecipient)

            post.erase()
            Storage.forget("dithoi.trip.v3")
        }

        print("— the vault's key —")
        do {
            // None of this had coverage. `DocumentStore` imports UIKit, so it is
            // the one file `run-checks.sh` skips — and it was where the crypto
            // lived, which made the single unrecoverable failure in the app the
            // single unchecked one. The crypto is `DocumentCrypto` now, on its
            // own Keychain account so this never touches the app's real key.
            let crypto = DocumentCrypto(service: "com.lovedones.dithoi.checks",
                                        account: "checks-\(UUID().uuidString)")
            defer { crypto.discardKey() }

            let secret = Data("the photo page".utf8)
            let sealed = (try? crypto.seal(secret)) ?? Data()
            check("a scan seals", !sealed.isEmpty && sealed != secret)
            check("and opens again", (try? crypto.open(sealed)) == secret)

            // Sealing twice must reuse the key, not mint a second one over the
            // first. `existingOrFreshKey` returning a fresh key on every call
            // would pass a round-trip check inside one call and lose every file
            // written before it.
            let second = (try? crypto.seal(Data("the visa".utf8))) ?? Data()
            check("a second scan opens too",
                  (try? crypto.open(second)) == Data("the visa".utf8))
            check("and the first one still opens, so the key was not replaced",
                  (try? crypto.open(sealed)) == secret)

            // A read must never create a key. This is the one that mattered:
            // `key()` minted on any nil from `loadKey()`, and `loadKey()`
            // answered nil for every non-success status — so an unreachable
            // Keychain looked like a first run, a fresh key went in over the
            // real one, and every scan on the phone became noise. Silently.
            let empty = DocumentCrypto(service: "com.lovedones.dithoi.checks",
                                       account: "checks-empty-\(UUID().uuidString)")
            defer { empty.discardKey() }
            var openFailed = false
            do { _ = try empty.open(sealed) } catch { openFailed = true }
            check("opening with no key at all fails", openFailed)
            check("and does not leave a key behind it",
                  (try? empty.existingKey()) ?? nil == nil)

            // Bytes that were never sealed, and bytes sealed under a different
            // key, both have to come back as undecryptable rather than as
            // nothing — the screen says different things about the two.
            let stranger = DocumentCrypto(service: "com.lovedones.dithoi.checks",
                                          account: "checks-other-\(UUID().uuidString)")
            defer { stranger.discardKey() }
            _ = try? stranger.seal(Data("mine".utf8))
            var wrongKey: DocumentCrypto.Failure?
            do { _ = try stranger.open(sealed) } catch { wrongKey = error as? DocumentCrypto.Failure }
            check("somebody else's key cannot open this scan",
                  wrongKey == .undecryptable, "\(String(describing: wrongKey))")

            var garbage: DocumentCrypto.Failure?
            do { _ = try crypto.open(Data([0, 1, 2, 3])) } catch { garbage = error as? DocumentCrypto.Failure }
            check("and neither can rubbish", garbage == .undecryptable)

            // "No key yet" is the only status allowed to read as nil. Everything
            // else has to throw, because that is the distinction the whole fix
            // rests on.
            check("an absent key is nil, not an error",
                  ((try? empty.existingKey()) ?? nil) == nil)
        }

        print("— changing hands empties the letterbox —")
        do {
            // `adopt(_:)` used to ask `traveller != role`, which is the right
            // question on a traveller's phone and the wrong one on the
            // observer's: there `role` is the traveller written *to*, and
            // `writeTo(_:)` moves it freely. So an observer writing to slot two,
            // tapping "traveller two", answered "nothing changed" — and became
            // that traveller still holding every letter they had written.
            //
            // The call site asked its own copy of the same wrong question, so it
            // skipped the confirmation as well. Both go through
            // `lettersBelongTo` now.
            func blank(_ box: String) -> TripStore {
                Storage.forget("dithoi.trip.v3")
                return TripStore(snapshot: CheckTrip.snapshot(),
                                 sync: SyncCoordinator(transport: {
                                     let b = LoopbackSyncTransport(named: box)
                                     b.latency = .zero
                                     b.erase()
                                     return b
                                 }()),
                                 letterPost: LoopbackLetterDropTransport(named: box),
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.\(box)"))
            }

            // An observer, writing to slot two, who then takes slot two.
            let home = blank("checks-hands-home")
            home.letters = []
            home.becomeObserver()
            home.writeTo(.two)
            let sealed = home.startLetter(title: "Sealed", condition: .day(40))
            home.seal(sealed.id)
            let draft = home.startLetter(title: "Still a draft", condition: .day(50))
            check("the writer has letters to lose",
                  home.letters.count == 2 && home.letters.contains { $0.id == draft.id })
            check("and the app knows they would be lost",
                  home.adoptionDiscardsLetters(becoming: Participant(.two)))

            home.adopt(.two)
            check("becoming the traveller you were writing to empties the box",
                  home.letters.isEmpty, "kept \(home.letters.count)")
            check("including the drafts, which were never posted anywhere",
                  !home.letters.contains { $0.id == draft.id })
            check("and the phone really is that traveller now",
                  !home.isObserver && home.role == .two)

            // An observer who wrote to *both* slots must not carry either set
            // across. This is the one the old guard could not even express.
            let both = blank("checks-hands-both")
            both.letters = []
            both.becomeObserver()
            both.writeTo(.one)
            both.seal(both.startLetter(title: "For one", condition: .day(10)).id)
            both.writeTo(.two)
            both.seal(both.startLetter(title: "For two", condition: .day(20)).id)
            check("the archive holds letters for both slots", both.letters.count == 2)
            both.adopt(.two)
            check("adopting one slot keeps neither slot's letters",
                  both.letters.isEmpty, "kept \(both.letters.count)")

            // The mirror: a traveller's received post must not become the
            // observer's outgoing set, or `postLetters` re-posts somebody else's
            // letters under a new address as if this phone had written them.
            let traveller = blank("checks-hands-back")
            check("the fixture arrives with post", !traveller.letters.isEmpty)
            check("and the app knows becoming the observer loses it",
                  traveller.adoptionDiscardsLetters(becoming: .writer))
            traveller.becomeObserver()
            check("going home empties the box too",
                  traveller.letters.isEmpty, "kept \(traveller.letters.count)")
            check("so there is nothing to re-post as your own",
                  traveller.sealedByWriter.isEmpty)

            // And the case that must *not* fire: re-picking who you already are
            // is not a change, so nothing is thrown away.
            let same = blank("checks-hands-same")
            let held = same.letters.count
            check("a phone that has not changed hands has something to keep", held > 0)
            check("and re-picking the same person is not a change",
                  !same.adoptionDiscardsLetters(becoming: same.participant))
            same.adopt(CheckTrip.letterRecipient)
            check("so re-adopting your own slot keeps every letter",
                  same.letters.count == held, "kept \(same.letters.count) of \(held)")

            // `ArrivalFlow.commitNames()` writes `participant` on every
            // continue, reversibly, so the flow can draw home mode before
            // anything is committed. A guard that compared against `participant`
            // would therefore read as "already them" by the time the
            // irreversible half ran — which is why the field is its own.
            let flow = blank("checks-hands-flow")
            let carried = flow.letters.count
            flow.participant = .writer                    // what commitNames does
            check("a reversible participant write does not empty the box",
                  flow.letters.count == carried)
            check("and the irreversible half still knows the box is not theirs",
                  flow.adoptionDiscardsLetters(becoming: .writer))
            flow.becomeObserver()                         // what commitSlot does
            check("so committing it empties the box after all", flow.letters.isEmpty)

            Storage.forget("dithoi.trip.v3")
        }

        print("— what it went on —")
        do {
            check("a guesthouse is a stay",
                  SpendCategory.inferred(from: "Guesthouse, Bangkok") == .stay)
            check("khao soi is food",
                  SpendCategory.inferred(from: "Khao soi at Khun Yai") == .food)
            check("a bus is transport",
                  SpendCategory.inferred(from: "Bus to Pai") == .transport)
            check("temples are tickets",
                  SpendCategory.inferred(from: "Temples") == .tickets)
            check("and a shrug is everything else",
                  SpendCategory.inferred(from: "Untitled") == .other)

            let totals = store.spendByCategory
            check("categories add up to the spending",
                  near(totals.reduce(0) { $0 + $1.home }, store.spentHome, 0.01),
                  "\(store.homeTextRounded(totals.reduce(0) { $0 + $1.home })) vs \(store.homeTextRounded(store.spentHome))")
            check("and are ordered biggest first",
                  zip(totals, totals.dropFirst()).allSatisfy { $0.home >= $1.home })

            // A correction sticks; re-inference must not overwrite it.
            if let line = store.spending.first(where: { $0.note.contains("Guesthouse") }) {
                check("it was guessed as a stay", line.category == .stay && !line.categoryWasCorrected)
                store.correctCategory(.other, for: line.id)
                let corrected = store.expenses.first { $0.id == line.id }
                check("a correction wins over the guess", corrected?.category == .other)
                check("and is distinguishable from one", corrected?.categoryWasCorrected == true)
                store.correctCategory(.stay, for: line.id)
            }

            // Four nights in one guesthouse is four lines, not one.
            let ledgerBefore = store.expenses.count
            let stay = Expense(date: store.now, amount: 800, currency: .thb, payer: .one,
                               split: .evenly, note: "Baan Orapin", country: "Thailand")
            let written = store.addRepeating(stay, nights: 4)
            check("a four-night stay writes four lines", written.count == 4)
            check("each on its own night",
                  Set(written.map { store.dayNumber(for: $0.date) }).count == 4)
            check("and each with its own id", Set(written.map(\.id)).count == 4)
            check("the ledger grew by four", store.expenses.count == ledgerBefore + 4)
            for line in written { store.expenses.removeAll { $0.id == line.id } }
        }

        print("— correcting the ledger —")
        do {
            let spentBefore = store.spentHome
            let balanceBefore = store.netBalanceHome
            let typo = Expense(date: store.now, amount: 8_000, currency: .thb, payer: .one,
                               split: .evenly, note: "Meant to be 800", country: "Thailand")
            store.add(typo)
            check("a typo lands in the ledger", store.spentHome > spentBefore)

            // Editing keeps the id, so the other phone reads a correction
            // rather than a second expense.
            var fixed = typo
            fixed.amount = 800
            store.update(fixed)
            check("editing keeps the line's id",
                  store.expenses.filter { $0.id == typo.id }.count == 1)
            check("and the totals follow the corrected amount",
                  near(store.spentHome, spentBefore + store.inHome(800, from: .thb), 0.01))

            store.delete(typo.id)
            check("deleting leaves the spending", near(store.spentHome, spentBefore, 0.01))
            check("and the balance", near(store.netBalanceHome, balanceBefore, 0.01))
            check("but the record is still there, as a tombstone",
                  store.expenses.contains { $0.id == typo.id },
                  "a removal can't beat the other phone's copy on the next round")
            check("and nothing draws it", !store.expenses.live.contains { $0.id == typo.id })

            store.restore(typo.id)
            check("undo puts it back", store.expenses.live.contains { $0.id == typo.id })
            store.delete(typo.id)

            // What `SyncableRecord.deletedAt` was built for, and what nothing
            // had ever exercised: a delete on one phone against an edit on the
            // other, in the same round.
            let boxA = LoopbackSyncTransport(named: "checks-delete")
            let boxB = LoopbackSyncTransport(named: "checks-delete")
            boxA.latency = .zero; boxB.latency = .zero; boxA.erase()
            Storage.forget("dithoi.trip.checks-delete")
            let hers = TripStore(storeKey: nil,
                                 sync: SyncCoordinator(transport: boxA),
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-delete"))
            let his = TripStore(storeKey: nil, snapshot: hers.snapshot,
                                sync: SyncCoordinator(transport: boxB),
                                ritual: SilentRitualScheduler(),
                                library: TripLibrary(key: "dithoi.library.checks-delete"))
            his.role = .two

            let shared = Expense(date: hers.now, amount: 500, currency: .thb, payer: .one,
                                 split: .evenly, note: "Contested round", country: "Thailand")
            hers.add(shared)
            await hers.syncNow()
            await his.syncNow()
            check("both phones have the line",
                  his.expenses.live.contains { $0.id == shared.id })

            // He edits it; she deletes it, later.
            var hisEdit = shared
            hisEdit.amount = 700
            his.update(hisEdit)
            try? await Task.sleep(for: .milliseconds(20))
            hers.delete(shared.id)

            await his.syncNow()
            await hers.syncNow()
            await his.syncNow()

            check("the later delete beats the earlier edit",
                  !his.expenses.live.contains { $0.id == shared.id },
                  "his ledger still shows it")
            check("and both phones agree it's gone",
                  !hers.expenses.live.contains { $0.id == shared.id })
            check("without either of them losing the record",
                  hers.expenses.contains { $0.id == shared.id }
                      && his.expenses.contains { $0.id == shared.id })

            // The true negative. Without this, the check above would pass just
            // as happily if his edit had never reached the box at all — which
            // is how an assertion ends up proving nothing. Run it the other way
            // round and the later write must win again, in the other direction.
            try? await Task.sleep(for: .milliseconds(20))
            var laterEdit = shared
            laterEdit.amount = 900
            his.update(laterEdit)
            await his.syncNow()
            await hers.syncNow()
            check("and an edit later than the delete brings it back",
                  hers.expenses.live.first { $0.id == shared.id }?.amount == 900,
                  "so the winner is the later write, not always the delete")
            boxA.erase()

            // What the edit sheet will and won't reopen.
            check("a whole-unit spend is editable", typo.isEditable)
            check("a transfer is not — its id belongs to the settlement",
                  store.expenses.first { $0.kind == .transfer }?.isEditable == false)
            var fractional = typo
            fractional.amount = 12.5
            check("and neither is an amount the keypad can't type",
                  !fractional.isEditable)
        }

        print("— more than one trip —")
        do {
            let library = TripLibrary(key: "dithoi.library.checks")
            library.erase()
            let phone = TripStore(sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "checks-shelf")),
                                  ritual: SilentRitualScheduler(), library: library)
            // The second slot, so "carries who is holding the phone" can't
            // pass by landing on the default.
            phone.participant = .two
            phone.adopt(.two)
            phone.letters = CheckTrip.letters(start: phone.start)
            phone.journal = CheckTrip.journal(start: phone.start)
            phone.hasOpened = true
            let firstID = phone.tripID
            let pagesBefore = phone.nightsWritten
            let lettersBefore = phone.letters.count

            check("one trip is live to start with", phone.isLive && library.isEmpty)

            phone.homeCurrency = .gbp
            phone.budget = 4_200
            let namesBefore = phone.names
            let featuresBefore = phone.features

            // The next trip is asked for, never implied: on a live trip it
            // does nothing until the close has happened.
            phone.beginNextTrip()
            check("a live trip isn't replaced without being closed",
                  phone.tripID == firstID && phone.isLive && library.isEmpty)

            phone.closeTrip()
            check("closing leaves the phone between trips",
                  !phone.isLive && phone.hasOpened && library.shelf.count == 1)
            phone.beginNextTrip()
            check("the old trip went to the shelf once", library.shelf.count == 1)
            check("and it kept its pages",
                  library.trip(firstID)?.summary.pageCount != nil && pagesBefore > 0)
            check("the new one has a different id", phone.tripID != firstID)
            check("and is empty", phone.journal.isEmpty && phone.expenses.isEmpty
                      && phone.itinerary.legs.isEmpty)
            check("and nobody packed it", phone.origin == .blank)
            check("and onboarding asks for it again", !phone.hasOpened && phone.tripName.isEmpty)
            check("the same people, holding the same phone",
                  phone.names == namesBefore && phone.participant == .two && phone.role == .two
                      && phone.lettersBelongTo == .two)
            check("the same money", phone.homeCurrency == .gbp && phone.budget == 4_200)
            check("the same switches", phone.features == featuresBefore)
            check("only one trip is live",
                  phone.isLive && library.shelf.allSatisfy { $0.summary.status == .archived })

            // An archived trip is the app it was, not a report about it.
            if let shelved = library.trip(firstID), let snapshot = TripSnapshot.decode(shelved.snapshot) {
                check("the frozen snapshot still has the journal",
                      snapshot.journal.count > 0)
                check("and the letters", snapshot.letters.count == lettersBefore)
                check("and its own trip id", snapshot.tripID == firstID)
            } else {
                check("the frozen snapshot decodes", false)
            }

            phone.closeTrip()
            check("closing stops it syncing", !phone.isLive)

            // The old version of this compared `phone.payload.expenses.count`
            // against itself plus the line just added — which is computed from
            // local state and so was true whether or not anything was pushed.
            // Ask the box what it is holding instead.
            let box = LoopbackSyncTransport(named: "checks-closed")
            box.latency = .zero
            box.erase()
            phone.sync.useForTesting(box)
            phone.add(Expense(date: phone.now, amount: 10, currency: .eur, payer: .one,
                              split: .evenly, note: "After closing", country: "Portugal"))
            await phone.syncNow()
            let pushed = try? await box.pull(tripID: phone.tripID)
            check("a closed trip never pushes", pushed == nil,
                  "the box holds \(pushed?.expenses.count ?? 0) lines from an archived trip")
            box.erase()
            check("and both trips are on the shelf", library.shelf.count == 2)
            library.erase()
        }

        print("— a store that can't write —")
        do {
            // Opening an archived trip means a second store holding somebody
            // else's frozen trip. Every @Published here saves on didSet, so
            // without a key that store would write the archive over the live
            // one on its first mutation — which is why the old snapshot-adopting
            // path was removed rather than wired up.
            let liveKey = "dithoi.trip.checks-readonly"
            Storage.forget(liveKey)
            let live = TripStore(storeKey: liveKey, snapshot: CheckTrip.snapshot(),
                                 sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "checks-ro")),
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-ro"))
            live.tripName = "The live one"
            // Writes are coalesced now — a burst of mutations costs one encode
            // rather than one each — so ask for it rather than racing the timer.
            // `flushAndWait`, not `flush` and a sleep: `flush` dispatches and
            // returns, and 120 ms was a guess that failed the first time the
            // machine was busy building something else.
            _ = await live.flushAndWait()
            let saved = TripSnapshot.load(key: liveKey)
            check("a store with a key writes itself", saved?.tripName == "The live one")

            var frozen = live.snapshot
            frozen.tripName = "The archived one"
            frozen.closedOn = Date()
            let reader = TripStore(storeKey: nil, snapshot: frozen,
                                   sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "checks-ro")),
                                   ritual: SilentRitualScheduler(),
                                   library: TripLibrary(key: "dithoi.library.checks-ro"))
            check("a store with no key opens the snapshot it was handed",
                  reader.tripName == "The archived one")
            check("and knows it isn't live", !reader.isLive && !reader.persists)

            reader.tripName = "Scribbled on"
            reader.expenses = []
            reader.flush()
            try? await Task.sleep(for: .milliseconds(120))
            check("and writing to it leaves the live trip alone",
                  TripSnapshot.load(key: liveKey)?.tripName == "The live one",
                  "got \(TripSnapshot.load(key: liveKey)?.tripName ?? "nothing")")
            check("and never wrote itself anywhere",
                  TripSnapshot.load(key: liveKey)?.expenses.isEmpty == false)

            Storage.forget(liveKey)
        }

        print("— what a closed trip lets you back into —")
        do {
            // The gates `ArchivedTripView` draws its browse rows behind. The
            // trail is unconditional; the other three ask the reopened trip
            // rather than the frozen summary, so a trip that never had a ledger
            // doesn't offer one.
            func offersBook(_ trip: TripStore) -> Bool {
                trip.features.printedBooks || trip.nightsWritten > 0
            }

            let packed = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                   ritual: SilentRitualScheduler())
            let reopened = TripStore(storeKey: nil, snapshot: packed.snapshot,
                                     ritual: SilentRitualScheduler())
            check("a reopened packed trip offers its book", offersBook(reopened))
            check("and its letters", reopened.lettersVisible)
            check("and its ledger", reopened.features.sharedLedger)

            // `.justTheMoney` prints nothing and carries no letters, so two of
            // the three rows have to disappear rather than open something empty.
            var thin = packed.snapshot
            thin.features = TripTemplate.justTheMoney.features
            thin.journal = []
            thin.letters = []
            let money = TripStore(storeKey: nil, snapshot: thin,
                                  ritual: SilentRitualScheduler())
            check("a trip that printed nothing doesn't offer a book", !offersBook(money))
            check("and one with no letters doesn't offer letters", !money.lettersVisible)
            check("but the ledger it did keep still opens", money.features.sharedLedger)

            // The failure branch. `ArchivedTripView` hides every row when the
            // blob won't decode, rather than opening an empty book under
            // somebody's name.
            check("a blob that isn't a trip opens nothing",
                  TripSnapshot.decode(Data("not a trip".utf8)) == nil)
            check("and neither does an empty one", TripSnapshot.decode(Data()) == nil)
        }

        print("— photos nobody points at —")
        do {
            let photos = PhotoStore(directoryName: "PruneCheck")
            let base = Storage.directory("PruneCheck")
            func put(_ id: String) {
                try? Data("jpeg".utf8).write(to: base.appendingPathComponent("\(id).jpg"))
                try? Data("jpeg".utf8).write(to: base.appendingPathComponent("\(id)-thumb.jpg"))
            }
            for id in ["live", "archived", "orphan-one", "orphan-two"] { put(id) }
            check("four photos on disk", photos.storedIDs.count == 4, "got \(photos.storedIDs)")

            let removed = photos.prune(keeping: ["live", "archived"])
            check("the orphans go", photos.storedIDs == ["live", "archived"],
                  "left \(photos.storedIDs)")
            check("and their thumbnails with them", removed == 4, "removed \(removed) files")
            check("what is still referenced stays", photos.exists("live") && photos.exists("archived"))

            // The trap. The shelf reopens closed books and draws their
            // photographs, so a keep-set built from the live journal alone would
            // delete the pictures out of every finished book — a far worse bug
            // than the leak it fixes.
            let library = TripLibrary(key: "dithoi.library.checks-prune")
            library.erase()
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(), library: library)
            phone.journal = [JournalEntry(dayNumber: 1, date: phone.now, city: "Bangkok",
                                          line: "Live page", tags: [], hasPhoto: true,
                                          photoID: "live", author: phone.role)]

            var closed = phone.snapshot
            closed.tripID = UUID()
            closed.journal = [JournalEntry(dayNumber: 1, date: phone.now, city: "Lisbon",
                                           line: "Archived page", tags: [], hasPhoto: true,
                                           photoID: "archived", author: phone.role)]
            library.archive(TripSummary(id: closed.tripID, name: "Last year", start: closed.start,
                                        dayCount: 14, countries: ["Portugal"], pageCount: 2,
                                        nightsAway: 13, stampsEarned: 0, stampsTotal: 0,
                                        spentHome: 0, homeCurrency: .eur, lettersDelivered: 0,
                                        lettersSealed: 0, status: .archived, closedOn: phone.now,
                                        printedOn: nil, lastSyncedAt: nil),
                            snapshot: (try? JSONEncoder().encode(closed)) ?? Data())

            check("the keep-set reaches onto the shelf",
                  phone.referencedPhotoIDs == ["live", "archived"],
                  "got \(phone.referencedPhotoIDs)")

            // And the same trap one collection over. A moment carries a
            // photograph exactly as a page does, so the keep-set has to walk
            // both — in the live trip *and* in every snapshot on the shelf.
            // Doing only the live half kills the pictures on the first launch
            // after a trip closes, which is when the book is being printed.
            for id in ["moment-live", "moment-archived"] { put(id) }
            phone.addMoment(note: "The noodle stall with no name", photoID: "moment-live")

            var closedWithMoment = closed
            closedWithMoment.moments = [Moment(capturedAt: phone.now, dayNumber: 3, city: "Lisbon",
                                               note: "The tiles on that wall", hasPhoto: true,
                                               photoID: "moment-archived")]
            library.erase()
            library.archive(TripSummary(id: closedWithMoment.tripID, name: "Last year",
                                        start: closedWithMoment.start,
                                        dayCount: 14, countries: ["Portugal"], pageCount: 2,
                                        nightsAway: 13, stampsEarned: 0, stampsTotal: 0,
                                        spentHome: 0, homeCurrency: .eur, lettersDelivered: 0,
                                        lettersSealed: 0, status: .archived, closedOn: phone.now,
                                        printedOn: nil, lastSyncedAt: nil),
                            snapshot: (try? JSONEncoder().encode(closedWithMoment)) ?? Data())

            check("a moment's photograph is kept, here and on the shelf",
                  phone.referencedPhotoIDs
                      == ["live", "archived", "moment-live", "moment-archived"],
                  "got \(phone.referencedPhotoIDs.sorted())")
            check("so a prune leaves all four alone",
                  photos.prune(keeping: phone.referencedPhotoIDs) == 0,
                  "left \(photos.storedIDs.sorted())")

            // Deleting one is a real delete — a moment has no merge to lose, so
            // it has no reason to leave a tombstone behind. Once the record is
            // gone the photograph stops being referenced, and the next prune
            // is what actually reclaims it.
            let doomed = phone.moments.first
            phone.deleteMoment(doomed?.id ?? UUID())
            check("deleting a moment removes the record, not tombstones it",
                  phone.moments.isEmpty, "\(phone.moments.count) left")
            check("and its photograph stops being referenced",
                  !phone.referencedPhotoIDs.contains("moment-live"),
                  "\(phone.referencedPhotoIDs.sorted())")
            // The undo window. The file is the prune's to take, not the
            // delete's — so for ten seconds it is still there to come back to.
            check("but the photograph is still on disk until a prune",
                  photos.storedIDs.contains("moment-live"), "\(photos.storedIDs.sorted())")
            if let doomed {
                check("undo puts the same moment back",
                      phone.restoreMoment(doomed)
                          && phone.moments.map(\.id) == [doomed.id]
                          && phone.moments.first?.photoID == "moment-live"
                          && phone.moments.first?.note == doomed.note)
                check("and a second undo adds nothing",
                      !phone.restoreMoment(doomed) && phone.moments.count == 1)
                check("so the prune spares it again",
                      photos.prune(keeping: phone.referencedPhotoIDs) == 0
                          && photos.storedIDs.contains("moment-live"))
                phone.deleteMoment(doomed.id)
            }
            // `prune` counts files, and a photograph is two — itself and its
            // thumbnail — so the assertion is about the id, not the number.
            let reclaimed = photos.prune(keeping: phone.referencedPhotoIDs)
            check("once the offer is gone, the prune takes the file",
                  reclaimed > 0 && !photos.storedIDs.contains("moment-live"),
                  "\(reclaimed) files, left \(photos.storedIDs.sorted())")
            library.erase()
            photos.eraseAll()
            check("and erasing leaves nothing behind", photos.storedIDs.isEmpty)
        }

        print("— a letter opens once, and in the right place —")
        do {
            let hers = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-open"))
            hers.participant = .one
            hers.letters = []
            hers.stamps = CheckTrip.stamps(start: hers.start)

            // A draft has no business being openable. `arrive(at:)` reaches
            // `open(letterNumber:)` directly, so a stamp pointing at one used to
            // mark a letter that was still being written as read.
            let draft = Letter(number: 90, title: "Still writing this", writtenOn: hers.now,
                               condition: .nextOnline, hint: "", paragraphs: [],
                               signature: "", sealedAt: nil)
            hers.letters = [draft]
            hers.open(letterNumber: 90, place: "Bangkok")
            check("an unsealed letter can't be opened", hers.letters[0].isOpen == false)

            hers.letters = [{ var sealed = draft; sealed.sealedAt = hers.now; return sealed }()]
            hers.open(letterNumber: 90, place: "Bangkok")
            check("and a sealed one can", hers.letters[0].isOpen)

            // The observer is shown the trail too, so the same path is reachable
            // on the phone that wrote the letters.
            let his = TripStore(storeKey: nil, snapshot: store.snapshot,
                                ritual: SilentRitualScheduler(),
                                library: TripLibrary(key: "dithoi.library.checks-open"))
            his.participant = .writer
            his.letters = [{ var sealed = draft; sealed.sealedAt = his.now; return sealed }()]
            his.open(letterNumber: 90, place: "Bangkok")
            check("and the one who wrote it can't open it on her behalf",
                  his.letters[0].isOpen == false)

            // Where the condition was met, not where the plan says she is. A
            // letter keyed to Hội An fires on the stamp; the itinerary can have
            // her somewhere else that day, and her book records the place.
            let far = TripStore(storeKey: nil, snapshot: store.snapshot,
                                ritual: SilentRitualScheduler(),
                                library: TripLibrary(key: "dithoi.library.checks-open"))
            far.participant = .one
            far.stamps = CheckTrip.stamps(start: far.start)
            if let hoiAn = far.stamps.first(where: { $0.city == "Hội An" }) {
                far.letters = [Letter(number: 91, title: "For Hội An", writtenOn: far.now,
                                      condition: .place("Hội An"), hint: "", paragraphs: [],
                                      signature: "", sealedAt: far.now)]
                far.arrive(at: hoiAn)
                let opened = far.openDueLetters()
                check("a letter records the place that opened it",
                      opened.first?.openedPlace == "Hội An",
                      "got \(opened.first?.openedPlace ?? "nothing") while standing in \(far.currentCity)")
            } else {
                check("Hội An is a stamp on this trip", false)
            }
        }

        print("— a trip nobody packed comes with nothing —")
        do {
            let blank = TripStore(storeKey: nil,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-blankcontent"))
            check("no day plans", blank.dayPlans.isEmpty)
            check("no papers", blank.documents.isEmpty)
            check("no show-this cards", blank.showCards.isEmpty)
            check("and no sharing rules", blank.sharingRules.isEmpty)
            check("while the packed one has all four",
                  !store.dayPlans.isEmpty && !store.documents.isEmpty
                      && !store.showCards.isEmpty && !store.sharingRules.isEmpty)

            // Starting a second trip from a packed one must not carry the first
            // one's papers into the second one's country.
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-blankcontent"))
            phone.hasOpened = true
            let cardsBefore = phone.orderedShowCards
            phone.closeTrip()
            phone.beginNextTrip()
            check("and a new trip doesn't inherit the last one's papers or plans",
                  phone.documents.isEmpty && phone.dayPlans.isEmpty)
            // The cards are for whoever reads them, not for a country.
            check("but it keeps the show-this cards, in order",
                  phone.orderedShowCards.map(\.english) == cardsBefore.map(\.english)
                      && !cardsBefore.isEmpty)
            check("as new records, so no tombstone on the other phone can take them",
                  Set(phone.showCards.map(\.id)).isDisjoint(with: cardsBefore.map(\.id))
                      && phone.showCards.allSatisfy { !$0.isDeleted && $0.updatedAt > .distantPast })

            // These travel in the snapshot, so an archived trip still opens with
            // the papers it had.
            let reopened = TripStore(storeKey: nil, snapshot: store.snapshot,
                                     ritual: SilentRitualScheduler(),
                                     library: TripLibrary(key: "dithoi.library.checks-blankcontent"))
            check("but an archived trip keeps its own",
                  reopened.documents.count == store.documents.count
                      && reopened.dayPlans.count == store.dayPlans.count)
        }

        print("— putting a trip away —")
        do {
            let library = TripLibrary(key: "dithoi.library.checks-shelving")
            library.erase()
            let phone = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                  ritual: SilentRitualScheduler(), library: library)
            phone.hasOpened = true

            var blank = phone.summary
            blank.countries = []
            blank.pageCount = 0
            blank.kilometres = 0
            blank.moments = nil
            blank.dayCount = 61
            check("an empty trip's line is its length and nothing else",
                  blank.shelvedLine == "61 days", blank.shelvedLine)
            blank.dayCount = 1
            check("and one day is a day", blank.shelvedLine == "1 day", blank.shelvedLine)

            var full = blank
            full.dayCount = 61
            full.countries = ["Thailand", "Laos", "Thailand"]
            full.kilometres = 4_212
            full.pageCount = 38
            full.moments = 12
            check("a country entered twice is one country",
                  full.shelvedLine == "61 days · 2 countries · 4,212 km · 38 pages · 12 moments",
                  full.shelvedLine)

            // The two new fields are the first added since shelves were
            // written, and `TripSummary` decodes synthetically: a missing
            // non-optional key throws, and the whole shelf goes with it.
            if let encoded = try? JSONEncoder().encode(full),
               var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] {
                object["kilometres"] = nil
                object["moments"] = nil
                let stripped = try? JSONSerialization.data(withJSONObject: object)
                let old = stripped.flatMap { try? JSONDecoder().decode(TripSummary.self, from: $0) }
                check("a summary frozen before kilometres and moments still opens",
                      old != nil && old?.kilometres == nil && old?.moments == nil)
                check("and says nothing it doesn't know",
                      old?.shelvedLine == "61 days · 2 countries · 38 pages", old?.shelvedLine ?? "nil")
            } else {
                check("a summary encodes", false)
            }

            check("nothing has landed before anything is closed", phone.justShelved == nil)
            let id = phone.tripID
            phone.closeTrip()
            check("closing names the trip for the shelf to land", phone.justShelved == id)
            check("the landing is taken once", phone.takeJustShelved() == id)
            check("and only once", phone.takeJustShelved() == nil)
            check("the shelved summary carries the moments",
                  library.trip(id)?.summary.moments == phone.moments.count)

            let other = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                  ritual: SilentRitualScheduler(), library: library)
            other.hasOpened = true
            other.beginNextTrip(discarding: true)
            check("throwing a trip away lands nothing", other.justShelved == nil)
            library.erase()
        }

        print("— the next trip, where to first —")
        do {
            func steps(observer: Bool = false, returning: Bool = false,
                       traveller: Bool = false, changing: Bool = false) -> [SetupStep] {
                SetupStep.steps(for: SetupContext(isObserver: observer, isPacked: false,
                                                  invites: false, returning: returning,
                                                  returningTraveller: traveller,
                                                  changingWho: changing))
            }
            check("a first launch asks who first",
                  steps() == [.hello, .who, .dates, .itinerary], "\(steps())")
            check("a returning traveller is asked where next",
                  steps(returning: true, traveller: true) == [.destination, .dates, .itinerary],
                  "\(steps(returning: true, traveller: true))")
            check("and who only once they say it changed",
                  steps(returning: true, traveller: true, changing: true)
                      == [.destination, .who, .dates, .itinerary])
            check("a returning observer is asked nothing about the trip",
                  steps(observer: true, returning: true) == [.who, .writingTo, .inside])
            // Switching to the observer on the `who` step, after the flow
            // captured a returning traveller: everything up to and including
            // the step on screen has to stay where it was.
            let before = steps(returning: true, traveller: true, changing: true)
            let after = steps(observer: true, returning: true, traveller: true, changing: true)
            let onScreen = before.firstIndex(of: .who) ?? 0
            check("becoming the observer halfway moves nothing behind the index",
                  Array(after.prefix(onScreen + 1)) == Array(before.prefix(onScreen + 1)),
                  "\(before) → \(after)")

            check("Thailand spends baht", Currency.likely(forCountry: "Thailand") == .thb)
            check("south korea spends won, however it is typed",
                  Currency.likely(forCountry: "south korea") == .krw)
            check("Portugal spends euros", Currency.likely(forCountry: "Portugal") == .eur)
            check("and a country with no rate here gets no guess",
                  Currency.likely(forCountry: "Peru") == nil
                      && Currency.likely(forCountry: "Japan") == nil)

            let library = TripLibrary(key: "dithoi.library.checks-nexttrip")
            library.erase()
            let phone = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                  ritual: SilentRitualScheduler(), library: library)
            phone.hasOpened = true
            phone.budget = 4_200
            phone.homeCurrency = .gbp
            let allergy = phone.addShowCard(native: "Tôi bị dị ứng đậu phộng",
                                            english: "I am allergic to peanuts",
                                            shortName: "Peanut allergy")
            phone.closeTrip()
            phone.beginNextTrip()
            check("an empty trip suggests no name", phone.suggestedTripName == nil)
            let yy = "'" + phone.start.text("yy")
            _ = phone.addLeg(country: "Thailand", currency: .thb, firstStop: "Bangkok", nights: 4)
            check("one country names the trip after it",
                  phone.suggestedTripName == "Thailand \(yy)", phone.suggestedTripName ?? "nil")
            _ = phone.addLeg(country: "Laos", currency: .thb, firstStop: "Luang Prabang", nights: 4)
            _ = phone.addLeg(country: "Thailand", currency: .thb, firstStop: "Chiang Mai", nights: 4)
            check("a country entered twice is named once",
                  phone.suggestedTripName == "Thailand & Laos \(yy)", phone.suggestedTripName ?? "nil")
            _ = phone.addLeg(country: "Vietnam", currency: .vnd, firstStop: "Hanoi", nights: 4)
            check("and three or more say so",
                  phone.suggestedTripName == "Thailand, Laos & more \(yy)", phone.suggestedTripName ?? "nil")

            let carried = phone.carriedOver
            let card = carried.cards.first { $0.shortName == allergy.shortName }
            check("the card came over under a new id",
                  card != nil && card?.id != allergy.id)
            var choice = TripStore.CarryChoice()
            choice.budget = false
            choice.currency = false
            choice.features = false
            if let card { choice.droppedCards = [card.id] }
            phone.applyCarry(choice, from: carried)
            check("declining the money leaves a blank trip's",
                  phone.budget == 0 && phone.homeCurrency == .eur)
            check("declining the switches leaves init's",
                  phone.features == TripTemplate.someonesLeaving.features)
            check("a declined card is tombstoned, not removed",
                  phone.showCards.first { $0.id == card?.id }?.isDeleted == true)
            let settingsStamp = phone.settingsUpdatedAt
            phone.applyCarry(choice, from: carried)
            check("applying the same choice twice writes nothing",
                  phone.settingsUpdatedAt == settingsStamp)
            phone.applyCarry(TripStore.CarryChoice(), from: carried)
            check("and ticking them again gives it all back",
                  phone.budget == 4_200 && phone.homeCurrency == .gbp
                      && phone.features == carried.features
                      && phone.showCards.first { $0.id == card?.id }?.isDeleted == false)
            library.erase()
        }

        print("— a trip sketched ahead —")
        do {
            let library = TripLibrary(key: "dithoi.library.checks-plan")
            library.erase()
            let live = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                 ritual: SilentRitualScheduler(), library: library)
            live.hasOpened = true
            live.budget = 4_200
            live.homeCurrency = .gbp
            let liveEnd = live.end

            let plan = live.makePlan()
            check("a live trip can sketch the next one", plan != nil && library.plan != nil)
            check("which is saved the moment it exists, as planned",
                  library.plan?.summary.status == .planned)
            check("and there is one at a time", live.makePlan() == nil)
            if let plan {
                check("it carries who everybody is and the money",
                      plan.names == live.names && plan.participant == live.participant
                          && plan.budget == 4_200 && plan.homeCurrency == .gbp)
                check("and starts the day after this trip ends",
                      Calendar.trip.days(from: liveEnd, to: plan.start) == 1)
                check("with nothing private in it",
                      plan.journal.isEmpty && plan.letters.isEmpty && plan.documents.isEmpty
                          && plan.moments.isEmpty && plan.expenses.isEmpty)
                check("and it cannot write the live trip's files", !plan.persists)

                // The reason it has to be keyless: a store with a key prunes
                // the scans against its own documents, which here are none.
                let passport = UUID()
                _ = try? ScanVault.shared.write(Data("page".utf8), for: passport, at: 0)
                plan.pruneOrphanedScans()
                plan.pruneOrphanedPhotos()
                check("editing a plan never prunes anything",
                      ScanVault.shared.pageCount(for: passport) == 1)
                ScanVault.shared.deleteAll(for: passport)

                plan.tripName = "Vietnam, slowly"
                plan.setDayCount(14)
                _ = plan.addLeg(country: "Vietnam", currency: .vnd, firstStop: "Hội An", nights: 5)
                plan.savePlan()
            }

            let reread = TripLibrary(key: "dithoi.library.checks-plan")
            check("a plan survives a relaunch",
                  reread.plan?.summary.name == "Vietnam, slowly" && reread.plan?.summary.dayCount == 14)
            check("and the shelf beside it is untouched", reread.shelf.isEmpty)

            let observer = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                     ritual: SilentRitualScheduler(),
                                     library: TripLibrary(key: "dithoi.library.checks-plan-observer"))
            observer.participant = .writer
            check("the observer sketches nothing", observer.makePlan() == nil)

            check("the countdown says today", TripStore.countdown(days: 0) == "today")
            check("tomorrow", TripStore.countdown(days: 1) == "tomorrow")
            check("and a date that went by, plainly",
                  TripStore.countdown(days: -3) == "was due 3 days ago"
                      && TripStore.countdown(days: 43) == "in 43 days")

            // Starting something else keeps the plan for later.
            let firstID = live.tripID
            live.closeTrip()
            live.beginNextTrip(usingPlan: false)
            check("starting something else keeps the plan",
                  library.plan != nil && live.legs.isEmpty && live.tripName.isEmpty)

            // And the plan, when it goes live, is the trip.
            let other = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                  ritual: SilentRitualScheduler(), library: library)
            other.hasOpened = true
            let planID = library.plan.flatMap { TripSnapshot.decode($0.snapshot)?.tripID }
            other.closeTrip()
            other.beginNextTrip()
            check("starting the plan takes its name, dates and itinerary",
                  other.tripName == "Vietnam, slowly" && other.dayCount == 14
                      && other.legs.map(\.country) == ["Vietnam"])
            check("and its money", other.budget == 4_200 && other.homeCurrency == .gbp)
            check("under a new trip id", other.tripID != planID && other.tripID != firstID)
            check("and the plan is gone", library.plan == nil)
            check("and it still goes through onboarding", !other.hasOpened)

            // Throwing the current trip away makes the plan next, too.
            let again = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                  ritual: SilentRitualScheduler(), library: library)
            again.hasOpened = true
            if let sketch = again.makePlan() {
                sketch.tripName = "Somewhere else"
                sketch.savePlan()
            }
            again.beginNextTrip(discarding: true)
            check("throwing a trip away makes the plan next",
                  again.tripName == "Somewhere else" && library.plan == nil)

            library.erase()
            check("erasing the library takes the plan", TripLibrary(key: "dithoi.library.checks-plan").plan == nil)
        }

        print("— throwing a trip away —")
        do {
            let library = TripLibrary(key: "dithoi.library.checks-discard")
            library.erase()
            let phone = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                  ritual: SilentRitualScheduler(), library: library)
            phone.hasOpened = true
            let firstID = phone.tripID
            phone.beginNextTrip(discarding: true)
            check("discarding shelves nothing", library.isEmpty)
            check("and leaves a new, empty trip for onboarding",
                  phone.tripID != firstID && phone.isLive && !phone.hasOpened
                      && phone.expenses.isEmpty && phone.letters.isEmpty && phone.documents.isEmpty)
            library.erase()
        }

        print("— home cannot drop a pin —")
        do {
            // The observer's phone draws the trail, which is the whole point of
            // the tab — and it drew "I'm standing in it" with it. Nothing in the
            // model refused, so a pin dropped from a kitchen in Utrecht earned
            // the stamp, opened the letter sealed to that city, added its leg to
            // the distance and synced all three to both other phones. Hiding the
            // button is the courtesy; this is the guarantee.
            let home = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-observer"))
            home.participant = .writer
            home.writeTo(.one)

            guard let next = home.nextStamp else {
                check("there was a stamp left to earn", false)
                return
            }
            let earnedBefore = home.earnedStamps.count
            let openBefore = home.letters.filter(\.isOpen).count
            let letter = home.arrive(at: next)

            check("the observer's arrival earns nothing", letter == nil)
            check("and the trail does not move",
                  home.earnedStamps.count == earnedBefore,
                  "\(earnedBefore) -> \(home.earnedStamps.count)")
            check("and no letter opens with it",
                  home.letters.filter(\.isOpen).count == openBefore)

            // Same phone, same slot, one field different — otherwise this
            // proves only that `next` was unearnable to begin with.
            let travelling = TripStore(storeKey: nil, snapshot: store.snapshot,
                                       ritual: SilentRitualScheduler(),
                                       library: TripLibrary(key: "dithoi.library.checks-observer"))
            travelling.participant = .one
            travelling.role = .one
            if let sameStamp = travelling.nextStamp {
                travelling.arrive(at: sameStamp)
                check("while a traveller standing there earns it",
                      travelling.earnedStamps.count == earnedBefore + 1)
            } else {
                check("the traveller had the same stamp ahead of them", false)
            }

            // `setBy` is `role`, and in home mode `role` is the traveller being
            // written *to* — so an observer's meeting point would arrive on both
            // phones over one of their names.
            let meetingBefore = home.meetingPoint.updatedAt
            home.setMeetingPoint(MeetingPoint(place: "The kitchen", detail: "by the kettle",
                                              localScript: "", setAt: home.now))
            check("and cannot set the meeting point either",
                  home.meetingPoint.updatedAt == meetingBefore
                      && home.meeting.place != "The kitchen",
                  home.meeting.place)
        }

        print("— writing a day —")
        do {
            let writing = TripStore(storeKey: nil, snapshot: store.snapshot,
                                    ritual: SilentRitualScheduler(),
                                    library: TripLibrary(key: "dithoi.library.checks-plans"))
            // Day 20 is inside the trip and `SampleTrip` says nothing about it,
            // so this is the mint-a-plan branch rather than the edit-one branch.
            check("day 20 starts blank", writing.plan(forDay: 20) == nil)

            writing.setBlurb("Slow morning, then the ferry.", forDay: 20)
            check("writing a sentence makes a day", writing.plan(forDay: 20)?.blurb.isEmpty == false)
            check("and it is stamped, so it can win a merge",
                  (writing.plan(forDay: 20)?.updatedAt ?? .distantPast) > .distantPast)
            check("and it knows which city it was written about",
                  writing.plan(forDay: 20)?.city == writing.city(forDay: 20),
                  writing.plan(forDay: 20)?.city ?? "—")

            let first = writing.addItem(time: "07:30", title: "Coffee", note: "", toDay: 20)
            writing.addItem(time: "14:00", title: "Ferry", note: "Buy the ticket at the pier", toDay: 20)
            check("hours go on the day", writing.plan(forDay: 20)?.items.count == 2)

            writing.moveItems(onDay: 20, from: IndexSet(integer: 1), to: 0)
            check("and can be reordered", writing.plan(forDay: 20)?.items.first?.title == "Ferry")

            writing.removeItem(first.id, fromDay: 20)
            check("and removed", writing.plan(forDay: 20)?.items.count == 1)

            // An occasion of "" would draw a blank chip on B3, which is a
            // different claim from having no occasion at all.
            writing.setOccasion("   ", forDay: 20)
            check("an empty occasion is no occasion", writing.plan(forDay: 20)?.occasion == nil)
            writing.setOccasion("Songkran", forDay: 20)
            check("and a real one sticks", writing.plan(forDay: 20)?.occasion == "Songkran")

            writing.clearPlan(forDay: 20)
            check("clearing it stops it drawing", writing.plan(forDay: 20) == nil)
            check("but keeps the record, so the clear can beat an edit",
                  writing.dayPlans.contains { $0.dayNumber == 20 })
            writing.setBlurb("Changed our minds.", forDay: 20)
            check("and writing in it again brings it back",
                  writing.plan(forDay: 20)?.blurb == "Changed our minds.")
            check("without minting a second record for the same day",
                  writing.dayPlans.filter { $0.dayNumber == 20 }.count == 1)

            // Two phones, one box. The plans and the cards are on the payload
            // now, which is what the sharing screen has always said.
            let boxA = LoopbackSyncTransport(named: "checks-plans")
            let boxB = LoopbackSyncTransport(named: "checks-plans")
            boxA.latency = .zero; boxB.latency = .zero; boxA.erase()
            let hers = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 sync: SyncCoordinator(transport: boxA),
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-plans"))
            let his = TripStore(storeKey: nil, snapshot: hers.snapshot,
                                sync: SyncCoordinator(transport: boxB),
                                ritual: SilentRitualScheduler(),
                                library: TripLibrary(key: "dithoi.library.checks-plans"))
            hers.role = .one
            his.role = .two

            hers.setBlurb("Her idea for day 21.", forDay: 21)
            his.setBlurb("His idea for day 22.", forDay: 22)
            await hers.syncNow()
            await his.syncNow()
            await hers.syncNow()

            check("a day written on one phone reaches the other",
                  his.plan(forDay: 21)?.blurb == "Her idea for day 21.")
            check("and both edits survive the round",
                  hers.plan(forDay: 22)?.blurb == "His idea for day 22."
                      && hers.plan(forDay: 21)?.blurb == "Her idea for day 21.")

            // The one the tombstone exists for.
            his.setBlurb("His second thoughts.", forDay: 21)
            try? await Task.sleep(for: .milliseconds(20))
            hers.clearPlan(forDay: 21)
            await his.syncNow()
            await hers.syncNow()
            await his.syncNow()
            check("a later clear beats an earlier edit", his.plan(forDay: 21) == nil,
                  his.plan(forDay: 21)?.blurb ?? "")
            await hers.syncNow()
            await his.syncNow()
            check("and does not walk back in on the next round",
                  his.plan(forDay: 21) == nil && hers.plan(forDay: 21) == nil)
        }

        print("— the cards they hand over —")
        do {
            let cards = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-cards"))
            check("the packed trip ships five", cards.orderedShowCards.count == 5)
            check("with the address first", cards.orderedShowCards.first?.shortName == "address")
            // Seeded cards were all `index: 0` before this, which sorted by
            // nothing at all once a merge had shuffled the array.
            check("and every card in its own slot",
                  Set(cards.orderedShowCards.map(\.index)).count == 5,
                  "\(cards.orderedShowCards.map(\.index))")

            let written = cards.addShowCard(native: "Tôi bị dị ứng đậu phộng",
                                            english: "I have a peanut allergy.",
                                            shortName: "peanuts vn")
            check("a written card goes on the end",
                  cards.orderedShowCards.last?.id == written.id)
            check("and is stamped", written.updatedAt > .distantPast)

            cards.moveShowCards(from: IndexSet(integer: 5), to: 0)
            check("reordering puts it first", cards.orderedShowCards.first?.id == written.id)
            check("and renumbers rather than reshuffling an array",
                  cards.orderedShowCards.map(\.index) == Array(0..<6),
                  "\(cards.orderedShowCards.map(\.index))")

            cards.deleteShowCard(written.id)
            check("deleting one stops it drawing",
                  !cards.orderedShowCards.contains { $0.id == written.id })
            check("but keeps the record", cards.showCards.contains { $0.id == written.id })

            // Which is what lets the hold menu's delete go straight through with
            // a banner behind it rather than a dialog in front of it. The fresh
            // stamp is the load-bearing half: without it the other phone's
            // tombstone is the later write and merges the card back out.
            let tombstoned = cards.showCards.first { $0.id == written.id }?.updatedAt
            cards.restoreShowCard(written.id)
            check("and taking it back puts it where it was",
                  cards.orderedShowCards.first?.id == written.id,
                  "\(cards.orderedShowCards.map(\.shortName))")
            check("with a stamp later than the delete's, so the merge keeps it",
                  (cards.showCards.first { $0.id == written.id }?.updatedAt ?? .distantPast)
                      >= (tombstoned ?? .distantPast))
            cards.deleteShowCard(written.id)

            // Two phones again, because a card written in Hanoi is no use on
            // the phone that isn't holding it.
            let boxA = LoopbackSyncTransport(named: "checks-cards")
            let boxB = LoopbackSyncTransport(named: "checks-cards")
            boxA.latency = .zero; boxB.latency = .zero; boxA.erase()
            let hers = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 sync: SyncCoordinator(transport: boxA),
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-cards"))
            let his = TripStore(storeKey: nil, snapshot: hers.snapshot,
                                sync: SyncCoordinator(transport: boxB),
                                ritual: SilentRitualScheduler(),
                                library: TripLibrary(key: "dithoi.library.checks-cards"))
            hers.role = .one
            his.role = .two

            let hospital = hers.addShowCard(native: "Xin đưa tôi đến bệnh viện",
                                            english: "Please take me to a hospital.",
                                            shortName: "hospital")
            await hers.syncNow()
            await his.syncNow()
            check("a card written on one phone reaches the other",
                  his.orderedShowCards.contains { $0.id == hospital.id })
            check("in the same order it was written in",
                  his.orderedShowCards.map(\.shortName) == hers.orderedShowCards.map(\.shortName),
                  "\(his.orderedShowCards.map(\.shortName))")

            // The language is a label, not a translation, and it is only ever
            // as good as the country somebody typed.
            check("Thailand speaks Thai", CountryFacts.lookup("Thailand")?.language == "Thai")
            check("Vietnam speaks Vietnamese", CountryFacts.lookup("Việt Nam")?.language == "Vietnamese")
            check("South Korea speaks Korean", CountryFacts.lookup("Korea")?.language == "Korean")
            check("the Netherlands still normalises", CountryFacts.lookup("the netherlands")?.language == "Dutch")
            // Rule 1, applied to a second column: a country with no single
            // honest answer says nothing rather than picking one of four.
            check("Belgium names no language", CountryFacts.lookup("Belgium")?.language == nil)
            check("and neither does India", CountryFacts.lookup("India")?.language == nil)
            check("nor a country nobody has heard of", CountryFacts.lookup("Freedonia") == nil)
            check("an emergency number is still there for the ones that say nothing",
                  CountryFacts.lookup("Belgium")?.emergencyLine == "112 for anything")

            // What the editor's first field is labelled, on the trip that ships.
            check("on day 12 the card editor asks for Thai", cards.currentLanguage == "Thai")
            let inVietnam = TripStore(storeKey: nil, snapshot: store.snapshot,
                                      ritual: SilentRitualScheduler(),
                                      library: TripLibrary(key: "dithoi.library.checks-cards"))
            inVietnam.setStart(Calendar.trip.date(byAdding: .day, value: -34, to: inVietnam.now) ?? inVietnam.start)
            check("and by day 35 it asks for Vietnamese", inVietnam.currentLanguage == "Vietnamese",
                  "\(inVietnam.currentCountry) -> \(inVietnam.currentLanguage ?? "nil")")
        }

        print("— a payload from the older build —")
        do {
            // Both collections are new on the wire. A phone that hasn't updated
            // pushes a payload without them, and "absent" has to mean "nothing
            // to say" — decoding it as `[]` would let one stale phone clear
            // every day plan and every card off the other on the next round.
            let encoded = (try? JSONEncoder().encode(store.payload)) ?? Data()
            if var json = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
                json.removeValue(forKey: "dayPlans")
                json.removeValue(forKey: "showCards")
                let stripped = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                let old = try? JSONDecoder().decode(SyncPayload.self, from: stripped)
                check("a payload written before day plans still decodes", old != nil)

                // And the merge treats it as nothing said, not as an erasure.
                if let old {
                    let merged = SyncMerge.merge(local: store.payload, remote: old, as: .one).payload
                    check("and takes nothing away",
                          merged.dayPlans.count == store.dayPlans.count
                              && merged.showCards.count == store.showCards.count,
                          "\(merged.dayPlans.count) plans, \(merged.showCards.count) cards")
                }
            } else {
                check("the payload is a JSON object", false)
            }
        }

        print("— and counting —")
        do {
            // The trail's headline was the constant 1,840, printed under the
            // words "and counting" on the screen whose whole subject is
            // accumulated distance. The stamps have always carried coordinates.
            let travelled = store.kilometresTravelled
            print("     \(travelled) km along \(store.earnedStamps.count) of \(store.stamps.count) stamps")
            // The trail is eleven places, and a merge unions by id — so a second
            // store that seeded its own copy of the stamps instead of starting
            // from this trip's snapshot would silently give the trip two or
            // three of everything. It did, for two runs, and the only visible
            // symptom was a distance that stopped moving.
            check("the trail is still eleven places",
                  store.stamps.count == 11 &&
                  Set(store.stamps.map(\.code)).count == 11,
                  "got \(store.stamps.count): \(store.orderedStamps.map(\.code))")
            check("distance is counted, not written down", travelled > 0)
            check("and it is the right order of magnitude for northern Thailand",
                  (100...2_000).contains(travelled), "got \(travelled) km")

            // It has to move when the trail does — that is the whole claim.
            // On a copy, so this section leaves the shared store exactly as it
            // found it rather than quietly earning a stamp for everything after
            // it.
            let walking = TripStore(storeKey: nil, snapshot: store.snapshot,
                                    ritual: SilentRitualScheduler(),
                                    library: TripLibrary(key: "dithoi.library.checks-km"))
            let before = walking.kilometresTravelled
            if let next = walking.nextStamp {
                walking.arrive(at: next)
                check("earning a stamp moves it", walking.kilometresTravelled > before,
                      "\(before) -> \(walking.kilometresTravelled)")
            } else {
                check("there was a stamp left to earn", false)
            }
            check("and the trip it was copied from is untouched",
                  store.kilometresTravelled == before)

            // One place you have stood is not a distance travelled, and "0 km
            // and counting" would be a sentence assembled without reading the
            // number in it.
            let unstarted = TripStore(storeKey: nil,
                                      ritual: SilentRitualScheduler(),
                                      library: TripLibrary(key: "dithoi.library.checks-km"))
            check("nowhere yet is no distance", unstarted.kilometresTravelled == 0)

            let bangkok = CheckTrip.stamps(start: store.start)[0]
            let hanoi = CheckTrip.stamps(start: store.start).first { $0.city == "Hanoi" }
            check("Bangkok to Hanoi is about a thousand kilometres",
                  (900...1_100).contains(Int(bangkok.kilometres(to: hanoi ?? bangkok))),
                  "got \(Int(bangkok.kilometres(to: hanoi ?? bangkok)))")
            check("and a stamp is no distance from itself",
                  bangkok.kilometres(to: bangkok) < 0.001)
        }

        print("— what the app already knows about a day —")
        do {
            // The day page's footer: "฿4,180 · 14 km · 3 moments". Every figure
            // computed, every clause dropping when it has nothing to say.
            let copy = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-facts"))
            let first = copy.dayFacts(forDay: 1)
            let baht = copy.expenses(onDay: 1).reduce(0) { $0 + $1.amount }
            check("a baht day sums in baht", first.currency == .thb && baht > 0 && first.spent == baht,
                  "\(first.spent) of \(baht) \(String(describing: first.currency))")
            check("and is exact, with no ≈",
                  !first.converted && first.line?.hasPrefix(Currency.thb.format(baht)) == true,
                  first.line ?? "nil")

            // A card payment in euros on a baht day: the page says it converted.
            copy.add(Expense(date: CheckTrip.date(day: 1, hour: 22, start: copy.start),
                             amount: 20, currency: .eur, payer: .one, split: .evenly,
                             note: "Card", country: "Thailand"))
            let mixed = copy.dayFacts(forDay: 1)
            check("a euro line on a baht day makes it approximate",
                  mixed.converted && mixed.line?.hasPrefix("≈฿") == true, mixed.line ?? "nil")

            // A night in Thailand reads in baht whichever country today is in.
            check("a day's money is in that day's currency, not today's",
                  copy.dayFacts(forDay: 2).currency == copy.leg(forDay: 2)?.currency)

            // The kilometres are the trail's, shared out by day: the pages
            // add up to the headline, never to a second answer.
            let walked = copy.kilometresWalked
            check("the days' kilometres add up to the trail's",
                  walked.values.reduce(0, +) == copy.kilometresTravelled,
                  "\(walked.values.reduce(0, +)) of \(copy.kilometresTravelled)")
            if let next = copy.nextStamp {
                copy.arrive(at: next)
                check("and still do after another arrival",
                      copy.kilometresWalked.values.reduce(0, +) == copy.kilometresTravelled)
            }
            check("only the days somebody arrived on carry any",
                  walked.keys.allSatisfy { day in
                      copy.earnedStamps.contains { $0.earnedOn.map(copy.dayNumber(for:)) == day }
                  })

            // Each clause on its own, and nothing left over when all drop.
            check("a day with nothing in it has no line", DayFacts().line == nil)
            check("one moment agrees with its noun",
                  DayFacts(moments: 1).line == "1 moment", DayFacts(moments: 1).line ?? "nil")
            check("a quiet day drops the kilometres",
                  DayFacts(spent: 100, currency: .thb, moments: 2).line == "฿100 · 2 moments",
                  DayFacts(spent: 100, currency: .thb, moments: 2).line ?? "nil")
            check("and money with no currency is not money", DayFacts(spent: 100).line == nil)

            let blank = TripStore(storeKey: nil,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-facts"))
            check("a blank trip knows nothing about its first day",
                  blank.dayFacts(forDay: 1).line == nil)

            // The facts give way to the tags a clause at a time, money last.
            let full = DayFacts(spent: 1_240, currency: .thb, kilometres: 14, moments: 3)
            check("the line drops from the end, money last",
                  full.lines == ["฿1,240 · 14 km · 3 moments", "฿1,240 · 14 km", "฿1,240"],
                  full.lines.joined(separator: " / "))

            // In the page's own mono, at every size the page is drawn at: the
            // last thing the facts can shrink to leaves the tags most of the
            // line, and an ordinary day prints whole beside two tags.
            let worst = DayFacts(spent: 12_345_678, currency: .vnd, converted: true,
                                 kilometres: 2_745, moments: 12)
            for (where_, unit) in [("print", 612 / DayTextPage.side), ("phone", 190 / DayTextPage.side),
                                   ("small phone", 160 / DayTextPage.side)] {
                let size = CGFloat((9.5 * unit).rounded())
                func width(_ text: String, tracking: Double = DayFacts.tracking) -> Double {
                    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
                    let set = NSAttributedString(string: text.uppercased(), attributes: [
                        .font: font, .kern: size * CGFloat(tracking)
                    ])
                    let line = CTLineCreateWithAttributedString(set as CFAttributedString)
                    return Double(CTLineGetTypographicBounds(line, nil, nil, nil)) / unit
                }
                let shortest = worst.lines.last ?? ""
                check("the shortest facts leave the tags most of the line, \(where_)",
                      width(shortest) <= DayTextPage.width * 0.4,
                      "\(Int(width(shortest))) of \(Int(DayTextPage.width * 0.4)) · \(shortest)")
                // The printed page holds an ordinary day whole beside two
                // tags. A phone preview rounds its type up to whole points, so
                // there the same day may give up its last clause — the text
                // box's own scales differ between the two the same way — but
                // never more than that.
                let tags = width("Tired · proud", tracking: 0.14) + 8
                let kept = where_ == "print" ? full.lines[0] : full.lines[1]
                check("and an ordinary day keeps \(where_ == "print" ? "every clause" : "two clauses") beside two tags, \(where_)",
                      tags + width(kept) <= DayTextPage.width,
                      "\(Int(tags + width(kept))) of \(Int(DayTextPage.width))")
            }
        }

        print("— the blank line asks a question —")
        do {
            // Grey text in a field reads as an answer somebody gave. What makes
            // the night's placeholder safe is that it is always a question.
            let days = Array(1...store.dayCount)
            let all = days.flatMap { store.linePrompts(forDay: $0) }
            check("every prompt is a question", all.allSatisfy { $0.hasSuffix("?") },
                  all.first { !$0.hasSuffix("?") } ?? "")
            check("and fits the field", all.allSatisfy { $0.count <= LinePrompts.limit },
                  all.first { $0.count > LinePrompts.limit } ?? "")
            check("no day asks the same thing twice",
                  days.allSatisfy { Set(store.linePrompts(forDay: $0)).count == store.linePrompts(forDay: $0).count })

            // Only that day's: a missed night gets its own questions.
            let fromItsOwnDay = days.allSatisfy { day in
                var allowed = Set(LinePrompts.generic)
                for item in store.plan(forDay: day)?.items ?? [] {
                    if let prompt = LinePrompts.about(item.title) { allowed.insert(prompt) }
                }
                for stamp in store.earnedStamps where stamp.earnedOn.map(store.dayNumber(for:)) == day {
                    if let prompt = LinePrompts.about("Arriving in \(stamp.city)") { allowed.insert(prompt) }
                }
                for moment in store.moments(onDay: day) {
                    if let prompt = LinePrompts.after(moment.note) { allowed.insert(prompt) }
                }
                return Set(store.linePrompts(forDay: day)).isSubset(of: allowed)
            }
            check("each day asks only about itself", fromItsOwnDay)
            let planned = days.first { day in
                (store.plan(forDay: day)?.items ?? []).contains { LinePrompts.about($0.title) != nil }
            }
            check("a day with a plan asks about it",
                  planned.map { store.linePrompts(forDay: $0) != LinePrompts.generic } ?? false,
                  planned.map { store.linePrompts(forDay: $0).joined(separator: " / ") } ?? "no planned day")

            let blank = TripStore(storeKey: nil,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-prompts"))
            check("a blank trip asks the ordinary questions",
                  blank.linePrompts(forDay: 1) == LinePrompts.generic)
            check("a title's own punctuation doesn't double up",
                  LinePrompts.about("Night market?") == "Night market: how was it?",
                  LinePrompts.about("Night market?") ?? "nil")
            check("a name is set as typed",
                  LinePrompts.about("Wat Phra Singh") == "Wat Phra Singh: how was it?")
            check("and a note too long to ask about isn't asked",
                  LinePrompts.after(String(repeating: "a", count: 50)) == nil)
        }

        print("— the page bar scrubs by date —")
        do {
            let nights = store.bookNights
            let days = Array(1...store.dayCount)
            let landed = days.compactMap { store.bookSpreadIndex(forDay: $0) }
            check("the book has nights to scrub to", !nights.isEmpty, "\(nights.count)")
            check("every day of the trip lands somewhere",
                  landed.count == days.count && landed.allSatisfy(store.bookPlan.spreads.indices.contains))
            check("and always on a night, never on a title or a map",
                  landed.allSatisfy { store.bookDay(ofSpreadAt: $0) != nil })
            check("a written night lands on its own spread",
                  nights.allSatisfy { store.bookSpreadIndex(forDay: $0.day) == $0.index })
            check("later in the trip is never earlier in the book",
                  zip(landed, landed.dropFirst()).allSatisfy { $0 <= $1 })
            if let missed = days.first(where: { day in !nights.contains { $0.day == day } }) {
                check("a missed night says so", store.scrubLabel(forDay: missed).hasSuffix("no page"),
                      store.scrubLabel(forDay: missed))
            }
            if let written = nights.first {
                check("and a written one says where it is",
                      store.scrubLabel(forDay: written.day).contains("p. \(store.bookPage(forDay: written.day) ?? -1)"),
                      store.scrubLabel(forDay: written.day))
            }
            let blank = TripStore(storeKey: nil,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-scrub"))
            check("an empty book has nowhere to scrub to", blank.bookSpreadIndex(forDay: 1) == nil)
            check("and a blank trip's label leaves the place out, not a dash",
                  !blank.scrubLabel(forDay: 1).contains(TripStore.unknownPlace),
                  blank.scrubLabel(forDay: 1))
        }

        print("— a postcard of the week, offered and never stored —")
        do {
            let writing = TripStore(storeKey: nil, snapshot: store.snapshot,
                                    ritual: SilentRitualScheduler(),
                                    library: TripLibrary(key: "dithoi.library.checks-postcard"))
            func page(_ day: Int) -> JournalEntry {
                JournalEntry(dayNumber: day, date: writing.date(forDay: day), city: writing.city(forDay: day),
                             line: "Day \(day)", tags: [], hasPhoto: false, author: writing.role)
            }
            let tonight = writing.dayNumber
            writing.journal = []
            let before = (1...writing.dayCount).filter { $0 != writing.dayNumber }
            for day in before.prefix(6) { writing.save(entry: page(day)) }
            check("six nights are not a week", writing.postcardOffer(after: page(before[5])) == nil)
            writing.save(entry: page(tonight))
            check("the seventh, written tonight, offers its week",
                  writing.postcardOffer(after: page(tonight)) == writing.postcardWeek(forDay: tonight),
                  "\(String(describing: writing.postcardOffer(after: page(tonight))))")
            // `tonight` is whatever day the shared store's clock has reached
            // by here, so the other nights are picked around it.
            let others = (1...writing.dayCount).filter { $0 != tonight }
            let eighth = others.first { day in !writing.myEntries.contains { $0.dayNumber == day } } ?? 1
            writing.save(entry: page(eighth))
            check("and the eighth does not", writing.postcardOffer(after: page(eighth)) == nil,
                  "\(writing.nightsWritten) nights")

            // Catching up is not an occasion.
            writing.journal = []
            for day in others.prefix(7) { writing.save(entry: page(day)) }
            check("a seventh night written late is not offered",
                  writing.nightsWritten == 7 && writing.postcardOffer(after: page(others[6])) == nil)

            let weeks = writing.postcardWeeks
            check("every week offered has a page in it",
                  !weeks.isEmpty && weeks.allSatisfy { !writing.postcardSpreads(week: $0).isEmpty })
            check("and only that week's pages",
                  weeks.allSatisfy { week in
                      writing.postcardSpreads(week: week).allSatisfy {
                          writing.bookDay(ofSpreadAt: $0).map(writing.postcardDays(week: week).contains) ?? false
                      }
                  })
            let otherSlot = writing.role.other
            check("and only this phone's",
                  weeks.allSatisfy { week in
                      writing.postcardSpreads(week: week).allSatisfy { index in
                          guard case .day(let id) = writing.bookPlan.spreads[index] else { return false }
                          return writing.entry(id)?.author != otherSlot
                      }
                  })
            check("the last week stops at the last day",
                  writing.postcardDays(week: writing.postcardWeek(forDay: writing.dayCount)).upperBound
                      == writing.dayCount)
            let routes = (1...writing.postcardWeek(forDay: writing.dayCount)).map(writing.postcardRoute(week:))
            check("a route names each place once", routes.allSatisfy { Set($0).count == $0.count })
            check("and the week's seal was earned that week",
                  (1...writing.postcardWeek(forDay: writing.dayCount)).allSatisfy { week in
                      writing.postcardStamp(week: week).flatMap(\.earnedOn)
                          .map { writing.postcardDays(week: week).contains(writing.dayNumber(for: $0)) } ?? true
                  })

            // Never the observer, never a closed trip.
            writing.journal = []
            for day in before.prefix(6) { writing.save(entry: page(day)) }
            writing.save(entry: page(tonight))
            let travellerSees = writing.postcardOffer(after: page(tonight)) != nil
            let holder = writing.participant
            writing.participant = .writer
            check("the observer is never offered one",
                  travellerSees && writing.postcardOffer(after: page(tonight)) == nil)
            writing.participant = holder
            writing.closeTrip()
            check("nor is a closed trip", writing.postcardOffer(after: page(tonight)) == nil)
        }

        print("— moving the clock, not the trip —")
        do {
            // Every one of these used to be untestable. `now` was `Date()`, so
            // the only lever was moving the trip's start date around today —
            // which can't reach the last day, midnight, or another timezone.
            // One frozen trip, many moments. Seeding derives the departure date
            // from the clock, so a store built at a later moment would simply
            // be a later trip that still opens on day 12 — the trip has to hold
            // still for moving the clock to mean anything.
            let frozen = store.snapshot
            let departure = frozen.start

            func phone(at moment: Date) -> TripStore {
                TripStore(storeKey: nil, snapshot: frozen, clock: { moment },
                          sync: SyncCoordinator(transport: {
                              let b = LoopbackSyncTransport(named: "checks-clock")
                              b.latency = .zero; return b
                          }()),
                          ritual: SilentRitualScheduler(),
                          library: TripLibrary(key: "dithoi.library.checks-clock"))
            }

            func day(_ n: Int) -> Date {
                Calendar.trip.date(byAdding: DateComponents(day: n - 1, hour: 12),
                                   to: departure) ?? departure
            }

            let midTrip = phone(at: day(12))
            check("the clock decides which day it is", midTrip.dayNumber == 12,
                  "got \(midTrip.dayNumber)")
            check("and it isn't the last one", !midTrip.isFinalDay)

            let lastDay = phone(at: day(61))
            check("the last day is reachable at all", lastDay.dayNumber == 61 && lastDay.isFinalDay,
                  "day \(lastDay.dayNumber)")

            // One minute either side of midnight, which no amount of moving the
            // start date could ever have expressed.
            let eve = Calendar.trip.date(byAdding: DateComponents(day: 11, hour: 23, minute: 59),
                                         to: departure)!
            let past = Calendar.trip.date(byAdding: DateComponents(day: 12, minute: 1),
                                          to: departure)!
            check("midnight rolls the day over",
                  phone(at: eve).dayNumber == 12 && phone(at: past).dayNumber == 13,
                  "\(phone(at: eve).dayNumber) then \(phone(at: past).dayNumber)")

            // J10 · "the one that never opened" is only a fact once the trip is
            // over, and until the clock could be moved there was no way to get
            // a store into that state at all.
            let afterwards = phone(at: Calendar.trip.date(byAdding: .day, value: 70, to: departure)!)
            check("and the trip can be over", afterwards.phase.isAfter)
            check("only then does a letter count as never delivered",
                  midTrip.undeliveredLetters.isEmpty && !afterwards.undeliveredLetters.isEmpty,
                  "\(midTrip.undeliveredLetters.count) mid-trip, \(afterwards.undeliveredLetters.count) after")
        }

        print("— a drop is sealed to the phone it is addressed to —")
        do {
            // The record name carries the recipient, and the old comment on
            // `CloudKitLetterDropTransport` called that the lock. It isn't:
            // both travellers are participants in the same shared zone and both
            // know `tripID` — it is on the payload — so the name is derivable,
            // and the zone's *owner* can read every record in their own zone
            // regardless. The addressing stops the wrong phone from learning a
            // box exists. This is what stops it reading one.
            let tripID = UUID()
            let hers = LetterKeyStore(account: "checks-seal-hers-\(UUID().uuidString)")
            let his = LetterKeyStore(account: "checks-seal-his-\(UUID().uuidString)")
            defer { hers.discard(); his.discard() }

            let sealed = SealedLetter(
                Letter(number: 1, title: "For you", writtenOn: Date(),
                       condition: .nextOnline, hint: "soon",
                       paragraphs: ["Something only she should read."],
                       signature: "— me", sealedAt: Date()),
                sealedAt: Date())
            let drop = LetterDrop(tripID: tripID, recipient: .one,
                                  letters: [sealed], updatedAt: Date())

            let ciphertext = try? LetterSeal.seal(drop, to: .one, using: hers.publicKey)
            check("a drop seals", ciphertext != nil)

            // The letter's words must not be sitting in the bytes. This is the
            // whole claim, so it is checked against the bytes rather than
            // against the API.
            if let ciphertext {
                let plain = Data("Something only she should read.".utf8)
                check("and the words are not in what goes over the wire",
                      ciphertext.range(of: plain) == nil)
            }

            let opened = ciphertext.flatMap {
                try? LetterSeal.open($0, as: .one, tripID: tripID,
                                     with: try hers.privateKey())
            }
            check("the addressed phone opens it", opened?.letters.count == 1)
            check("with the letter intact",
                  opened?.letters.first?.paragraphs == sealed.paragraphs)

            // The other traveller is a participant in the same zone. Holding the
            // ciphertext is exactly the position they are in.
            var otherOpened: LetterDrop?
            if let ciphertext {
                otherOpened = try? LetterSeal.open(ciphertext, as: .one, tripID: tripID,
                                                   with: try his.privateKey())
            }
            check("the other traveller's key opens nothing", otherOpened == nil)

            // Bound to the trip and the slot, so a drop cannot be replayed into
            // another trip or read as the other slot's post even by the phone
            // that legitimately holds the key.
            var wrongSlot: LetterDrop?
            var wrongTrip: LetterDrop?
            if let ciphertext {
                wrongSlot = try? LetterSeal.open(ciphertext, as: .two, tripID: tripID,
                                                 with: try hers.privateKey())
                wrongTrip = try? LetterSeal.open(ciphertext, as: .one, tripID: UUID(),
                                                 with: try hers.privateKey())
            }
            check("and it cannot be read as the other slot's post", wrongSlot == nil)
            check("nor replayed into another trip", wrongTrip == nil)

            // Two seals of the same drop must differ — an ephemeral key per
            // seal, so identical post doesn't produce identical bytes anybody
            // watching the zone could match against.
            let again = try? LetterSeal.seal(drop, to: .one, using: hers.publicKey)
            check("two seals of one drop are not the same bytes",
                  ciphertext != nil && again != nil && ciphertext != again)

            // A recipient who hasn't synced yet has published no key. Posting in
            // clear then would be the failure this whole change exists to stop,
            // so it has to be refused and named.
            var refusal: LetterSeal.Failure?
            do { _ = try LetterSeal.seal(drop, to: .one, using: nil) }
            catch { refusal = error as? LetterSeal.Failure }
            check("a drop with nowhere sealed to go is refused, not sent in clear",
                  refusal == .noRecipientKey, "\(String(describing: refusal))")

            // And the private half is not in anything that leaves the phone.
            let payloadFields = Mirror(reflecting: SyncPayload.empty()).children
                .compactMap(\.label)
            check("the payload carries no private key",
                  !payloadFields.contains { $0.lowercased().contains("private") })
            let ring = Mirror(reflecting: LetterKeyring.blank).children.compactMap(\.label)
            check("and the keyring is one public key per slot",
                  ring.sorted() == ["one", "two"], "\(ring)")
        }

        print("— the private half is not in the preferences —")
        do {
            // The whole trip used to be JSON in `UserDefaults.standard`: the
            // journal, every letter's full text, the moments, the ledger — and
            // through the shelf, every archived trip as well. That is the app's
            // preferences plist. It is in every iCloud and Finder backup, it is
            // plaintext, and it carries the default protection class, so it is
            // readable whenever the phone has been unlocked once since boot.
            //
            // Meanwhile the passport scans got AES-GCM and a backup exclusion.
            // `Review.md` §2.3 named the asymmetry and only the photograph half
            // was ever fixed. This is the other half.
            let key = "dithoi.trip.checks-protected"
            let shelfKey = "dithoi.library.checks-protected"
            Storage.forget(key)
            Storage.forget(shelfKey)

            let phone = TripStore(storeKey: key,
                                  snapshot: CheckTrip.snapshot(),
                                  sync: SyncCoordinator(transport: {
                                      let box = LoopbackSyncTransport(named: "checks-protected")
                                      box.erase()
                                      return box
                                  }()),
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: shelfKey))
            phone.save(entry: JournalEntry(dayNumber: 20, date: phone.now, city: "Hội An",
                                           line: "Something nobody else gets to read",
                                           tags: [], hasPhoto: false, author: phone.role))
            // Awaited: the write is deliberately off the main actor, so a
            // synchronous `flush()` here would be read before the bytes landed.
            await phone.flushAndWait()

            check("nothing about the trip is left in the preferences",
                  Storage.defaults.data(forKey: key) == nil)
            check("and the file has it instead",
                  ((try? Storage.readProtected(named: key)) ?? nil) != nil)

            // The point of the file is that another store reads the same trip.
            // Losing that would be trading a privacy problem for a data-loss
            // one, which is the trade `PhotoStore` already made once by mistake.
            let reopened = TripSnapshot.stored(key: key)
            var reread: TripSnapshot?
            if case .trip(let s) = reopened { reread = s }
            check("and a second store reads the same trip back",
                  reread?.tripID == phone.tripID)
            check("with the page that was written to it",
                  reread?.journal.contains { $0.line.contains("nobody else gets to read") } == true)

            // The shelf is the larger half: a phone two trips in holds more
            // private text in closed books than in the live one.
            phone.closeTrip()
            check("a closed trip goes to the file too",
                  ((try? Storage.readProtected(named: shelfKey)) ?? nil) != nil)
            check("and not to the preferences",
                  Storage.defaults.data(forKey: shelfKey) == nil)

            Storage.forget(key)
            Storage.forget(shelfKey)
        }

        print("— a trip written by the old build moves across —")
        do {
            // An install that already ran the `UserDefaults` build has its trip
            // in the plist and nothing in the file. It must arrive intact, and
            // the old copy must not be removed until the new one has been read
            // back — a remove on faith loses the trip whenever the write failed,
            // and the write can now fail, because a protected file is refused
            // while the phone is locked.
            let key = "dithoi.trip.checks-migration"
            Storage.forget(key)

            let legacy = (try? JSONEncoder().encode(CheckTrip.snapshot())) ?? Data()
            Storage.defaults.set(legacy, forKey: key)
            check("the old build's trip is in the preferences to start with",
                  Storage.defaults.data(forKey: key) == legacy)

            let found = TripSnapshot.stored(key: key)
            var moved: TripSnapshot?
            if case .trip(let s) = found { moved = s }
            check("it opens", moved?.tripID == CheckTrip.defaultTripID)
            check("its journal came with it", moved?.journal.isEmpty == false)
            check("its letters came with it", moved?.letters.isEmpty == false)
            check("the file now holds it byte for byte",
                  ((try? Storage.readProtected(named: key)) ?? nil) == legacy)
            check("and only then is the preferences copy gone",
                  Storage.defaults.data(forKey: key) == nil)

            // Running again is a no-op rather than a second migration over the
            // top of whatever has been written since.
            let after = TripSnapshot.stored(key: key)
            var again: TripSnapshot?
            if case .trip(let s) = after { again = s }
            check("a second launch migrates nothing and loses nothing",
                  again?.tripID == CheckTrip.defaultTripID)

            // A trip at both addresses keeps the file. The file is what the app
            // writes now, so it is by definition the newer of the two.
            Storage.defaults.set(Data("older".utf8), forKey: key)
            _ = TripSnapshot.stored(key: key)
            check("a stale preferences copy never wins over the file",
                  ((try? Storage.readProtected(named: key)) ?? nil) == legacy
                  && Storage.defaults.data(forKey: key) == nil)

            Storage.forget(key)
        }

        print("— a saved trip is never written over —")
        do {
            let key = "dithoi.trip.checks-fault"

            // Field by field with defaults, which is what the type has always
            // claimed. Strip each key in turn: every one of them has to survive,
            // because a throw here isn't a missing field, it's a lost trip —
            // `load` swallows it and the store re-seeds the sample over the top.
            let encoded = (try? JSONEncoder().encode(store.snapshot)) ?? Data()
            if let json = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
                var lost: [String] = []
                for field in json.keys {
                    var stripped = json
                    stripped.removeValue(forKey: field)
                    let data = (try? JSONSerialization.data(withJSONObject: stripped)) ?? Data()
                    if TripSnapshot.decode(data) == nil { lost.append(field) }
                }
                check("a snapshot missing any one field still opens", lost.isEmpty,
                      lost.isEmpty ? "\(json.count) fields" : "lost on: \(lost.joined(separator: ", "))")
            } else {
                check("the snapshot is a JSON object", false)
            }

            // And the part no default can rescue: bytes that aren't a trip at
            // all. "Nothing saved" and "saved and unreadable" used to be the
            // same answer — `nil` — and both re-seeded.
            try? Storage.writeProtected(Data("not a trip".utf8), named: key)
            check("unreadable is not the same as absent",
                  { if case .unreadable = TripSnapshot.stored(key: key) { return true }; return false }())
            check("and absent is still absent",
                  { if case .none = TripSnapshot.stored(key: "dithoi.trip.nothing-here") { return true }
                    return false }())

            let faulted = TripStore(storeKey: key,
                                    sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "checks-fault")),
                                    ritual: SilentRitualScheduler(),
                                    library: TripLibrary(key: "dithoi.library.checks-fault"))
            check("a store that met one says so", faulted.storageFault)
            faulted.tripName = "Scribbled over the top"
            check("and refuses to write, so the bytes survive",
                  ((try? Storage.readProtected(named: key)) ?? nil) == Data("not a trip".utf8),
                  "the unreadable trip was overwritten")
            Storage.forget(key)
        }

        print("— a trip nobody packed —")
        do {
            // What a first launch actually gets. The app ships with no trip
            // inside it, so this is the only branch `init` can take when
            // nothing is saved and no snapshot is handed in.
            Storage.forget("dithoi.trip.v3")
            let fresh = TripStore(
                                  sync: SyncCoordinator(transport: {
                                      let box = LoopbackSyncTransport(named: "checks-blank")
                                      box.latency = .zero
                                      box.erase()
                                      return box
                                  }()),
                                  letterPost: LoopbackLetterDropTransport(named: "checks-blank"),
                                  library: TripLibrary(key: "dithoi.library.checks-blank"))
            check("it starts with nowhere in it", fresh.legs.isEmpty)
            check("and nothing sealed", fresh.letters.isEmpty)
            check("and no pages", fresh.journal.isEmpty && fresh.expenses.isEmpty)
            check("and no budget to have spent", fresh.budget == 0)
            check("onboarding hasn't run", !fresh.hasOpened)
            check("and it knows nobody packed it", fresh.origin == .blank)
            check("nobody is named yet",
                  fresh.names.one.value.isEmpty && fresh.names.two.value.isEmpty)
            check("but a name is still never empty",
                  fresh.name(for: .one) == "Traveller one"
                      && fresh.name(for: .two) == "Traveller two")

            fresh.rename(.one, to: "Kim")
            check("naming yourself takes on a blank trip", fresh.name(for: .one) == "Kim")
            check("and the other slot stays a slot", fresh.name(for: .two) == "Traveller two")

            // `origin` is stored, so building the plan during onboarding must
            // not change the branch onboarding is standing in.
            fresh.addLeg(country: "Portugal", currency: .eur, firstStop: "Lisbon", nights: 4)
            check("the plan can be built from empty", fresh.legs.count == 1)
            check("adding a country doesn't refill the trip", fresh.origin == .blank)

            // A trip that arrived filled in is one that came off a snapshot,
            // which is the only way `.packed` is reachable now.
            Storage.forget("dithoi.trip.v3")
            let handed = TripStore(snapshot: CheckTrip.snapshot())
            check("a handed-over trip arrives filled in", handed.origin == .packed)
            check("and arrives with somewhere in it", !handed.legs.isEmpty)
        }

        print("— the mark —")
        do {
            // The design's three lists, transcribed once. Every size it names,
            // including the four iPad ones this iPhone-only app never emits —
            // the table is the design's and should be complete where it happens
            // to be unused.
            for pixels in [1024, 180, 167, 152] {
                check("\(pixels) takes the large cut", TripMarkCut.forIcon(pixels: pixels) == .large)
            }
            for pixels in [120, 87, 80, 76] {
                check("\(pixels) takes the medium cut", TripMarkCut.forIcon(pixels: pixels) == .medium)
            }
            for pixels in [60, 58, 40, 29] {
                check("\(pixels) takes the small cut", TripMarkCut.forIcon(pixels: pixels) == .small)
            }

            let cuts: [(TripMarkCut, Double, Double)] = [
                (.large, 30, 110), (.medium, 44, 130), (.small, 66, 164),
                (.circular, 56, 150), (.tinted, 34, 116), (.lockup, 14, 19)
            ]
            for (cut, stroke, radius) in cuts {
                check("\(cut.rawValue) is \(Int(stroke)) · r\(Int(radius))",
                      cut.strokeWidth == stroke && cut.dotRadius == radius)
            }

            // Deliberately not centred: "far enough along to read as a journey
            // underway, never centred."
            check("the dot sits on 635 of 1024",
                  TripMarkGeometry.iconProgress * 1024 == 635)
            check("which is 62%, and not the middle",
                  near(TripMarkGeometry.iconProgress, 0.62, 0.0005)
                      && TripMarkGeometry.iconProgress != 0.5)

            // What a scaled file gets wrong. These are the numbers that decide
            // whether the three cuts were worth having.
            for slot in IconSlot.iPhone(.any) {
                let scale = Double(slot.pixels) / 1024
                let stroke = slot.cut.strokeWidth * scale
                let radius = slot.cut.dotRadius * scale
                check("\(slot.pixels)px rule is \(String(format: "%.2f", stroke))px, not a grey smear",
                      stroke >= 2.5)
                check("\(slot.pixels)px dot is a dot, not a bulge in the rule",
                      radius > stroke)
                check("\(slot.pixels)px mark doesn't clip",
                      TripMarkGeometry.iconProgress * Double(slot.pixels) + radius <= Double(slot.pixels))
            }

            // Every slot has a file, every file has a slot, and no two slots
            // claim the same filename — the catalogue and the disk are one list.
            let slots = IconSlot.all
            check("the catalogue is 11 slots", slots.count == 11, "\(slots.count)")
            check("no two slots write the same file",
                  Set(slots.map(\.filename)).count == slots.count)
            check("the App Store slot is the only marketing one",
                  slots.filter { $0.idiom == "ios-marketing" }.count == 1)
            check("the appearance slots are one 1024 each",
                  IconSlot.iPhone(.dark).count == 1 && IconSlot.iPhone(.tinted).count == 1)
            // One file across the whole ramp, so it can't take the cut its own
            // pixel size asks for. See the comment on IconSlot.iPhone.
            check("and take the middle cut, so they survive 40px",
                  IconSlot.iPhone(.dark)[0].cut == .medium
                      && IconSlot.iPhone(.tinted)[0].cut == .medium)

            // The notification badge is a second axis from size — the design
            // says no green survives at that scale, and a generator keyed on
            // pixels alone would ship one.
            let badges = IconSlot.iPhone(.any).filter { $0.role == .notification }
            check("both 20pt slots go flat white on grey",
                  badges.count == 2 && badges.allSatisfy { $0.ground == .badge })
            check("and nothing else does",
                  IconSlot.iPhone(.any).filter { $0.ground == .badge }.count == 2)
            check("the tinted tile is two values and no hue",
                  MarkGround.tinted.background == 0x000000
                      && MarkGround.tinted.walked == 0xFFFFFF
                      && MarkGround.tinted.ahead == TripMarkInk.white(TripMarkInk.aheadFraction))

            // Day 1 has walked nothing; the last day is solid end to end with
            // the dot's centre exactly on the edge, which is what makes the
            // widget's half-leaving dot arithmetic rather than a fudge.
            check("day 1 of 61 is nothing walked",
                  TripMarkGeometry.progress(day: 1, of: 61) == 0)
            check("day 61 of 61 is the whole rule",
                  TripMarkGeometry.progress(day: 61, of: 61) == 1)
            check("day 38 of 61 is 37/60",
                  near(TripMarkGeometry.progress(day: 38, of: 61), 37.0 / 60.0, 1e-12))
            check("a one-day trip is already over",
                  TripMarkGeometry.progress(day: 1, of: 1) == 1)
            check("and days outside the trip clamp",
                  TripMarkGeometry.progress(day: 0, of: 61) == 0
                      && TripMarkGeometry.progress(day: 62, of: 61) == 1)
            let finalDay = TripMarkGeometry(cut: .lockup, progress: 1)
            check("on the last day the dot's centre is on the frame edge",
                  finalDay.dotX == finalDay.width)
            // Which is a flourish only where there is an edge to leave through.
            check("the tile cuts bleed and the lockup doesn't",
                  TripMarkCut.large.bleeds && TripMarkCut.circular.bleeds
                      && TripMarkCut.tinted.bleeds && !TripMarkCut.lockup.bleeds)
        }

        print("— what the widget is told —")
        do {
            Storage.forget("dithoi.trip.v3")
            let day12 = TripStore(snapshot: CheckTrip.snapshot(),
                                  sync: SyncCoordinator(transport: LoopbackSyncTransport(named: "checks-widget")),
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-widget"))

            /// The trip as it will be on a given day, without moving the trip.
            func onDay(_ day: Int) -> WidgetSnapshot {
                day12.widgetSnapshot(on: day12.date(forDay: day))
            }

            let twelve = onDay(12)
            check("day 12 is Chiang Mai", twelve.city == "Chiang Mai", twelve.city)
            check("with Hanoi 9 days off",
                  twelve.nextCity == "Hanoi" && twelve.daysUntilNextCity == 9,
                  "\(twelve.nextCity ?? "—") in \(twelve.daysUntilNextCity ?? -1)")
            check("and it says so in one sentence",
                  twelve.headline == "Chiang Mai · 9 days until Hanoi", twelve.headline)
            check("the kicker is the app's own line",
                  twelve.kicker == "Day 12 of 61", twelve.kicker)

            // The design's widget prints "Hội An · 11 days until Seoul" on day
            // 38. Hội An runs 32–41 and South Korea opens on 47, so it is 9 —
            // the "61 days over a 72-day range" bug, one screen later. Compute.
            let thirtyEight = onDay(38)
            check("day 38 is Hội An · 9 days until Seoul (the design says 11)",
                  thirtyEight.headline == "Hội An · 9 days until Seoul",
                  thirtyEight.headline)

            // Already in the last country: fall through to the next segment, so
            // the line still says something.
            let fifty = onDay(50)
            check("day 50 is Seoul, with Busan 5 days off",
                  fifty.city == "Seoul" && fifty.nextCity == "Busan" && fifty.daysUntilNextCity == 5,
                  "\(fifty.headline)")

            // The last stop has no next place, and the clause is dropped rather
            // than invented. Day 61 is also inside no segment — `endDay` is the
            // day they leave — so this is the check that keeps the final
            // morning from reading "—".
            let last = onDay(61)
            check("the last day names nowhere else",
                  last.nextCity == nil && last.headline == "Jeju", last.headline)
            check("and the rule is solid", last.progress == 1)
            check("the app agrees about where they are on the way home",
                  day12.city(forDay: 61) == "Jeju" && day12.city(forDay: 62) == "Jeju",
                  day12.city(forDay: 61))

            // A day past the end. `dayNumber` clamps, `phase` does not.
            let afterwards = day12.widgetSnapshot(on: day12.date(forDay: 70))
            check("past the end it says they're home",
                  afterwards.phase == .after && afterwards.dayNumber == 61
                      && afterwards.kicker == "Home · 61 days done", afterwards.kicker)
            check("and stops naming a next place", afterwards.nextCity == nil)

            // Before departure the next stop *is* the current city, so counting
            // down to it twice would read as two journeys.
            let before = day12.widgetSnapshot(on: day12.date(forDay: -5))
            check("before departure it counts down",
                  before.phase == .before && before.kicker == "6 days to go", before.kicker)
            check("and holds the dot back, because nothing is walked yet",
                  !before.showsDot && before.progress == 0)
            check("naming the first stop once",
                  before.headline == "Bangkok" && before.nextCity == nil, before.headline)
            let eve = day12.widgetSnapshot(on: day12.date(forDay: 0))
            check("the night before is Tomorrow", eve.kicker == "Tomorrow", eve.kicker)

            // The published run: today first, one entry per day, and it stops
            // once there is nothing left to say.
            let days = day12.widgetSnapshots
            check("it publishes 24 days ahead", days.count == AppGroup.horizon, "\(days.count)")
            check("starting today", days[0].dayNumber == 12)
            check("one calendar day apart",
                  zip(days, days.dropFirst()).allSatisfy {
                      Calendar.trip.days(from: $0.date, to: $1.date) == 1
                  })
            check("and a future entry moves the city, not just the number",
                  days.contains { $0.city == "Hanoi" })

            day12.setStart(Calendar.trip.date(byAdding: .day, value: -59, to: day12.now) ?? day12.now)
            let tail = day12.widgetSnapshots
            check("near the end it stops at the last thing worth saying",
                  tail.count < AppGroup.horizon && tail[tail.count - 1].phase == .after,
                  "\(tail.count)")

            // A wire format between two processes. A decoder that quietly drops
            // `nextCity` would pin a stale city on the Home Screen forever, and
            // nothing on any screen in the app would show it.
            let wire = try? JSONEncoder().encode(days)
            let back = wire.flatMap { try? JSONDecoder().decode([WidgetSnapshot].self, from: $0) }
            check("it survives the trip through JSON", back == days)
        }

        print("— what is already on the phone —")
        do {
            func summary(_ change: (inout TripSnapshot) -> Void = { _ in }) -> String {
                var snapshot = CheckTrip.snapshot()
                change(&snapshot)
                return TripStore(storeKey: nil, snapshot: snapshot,
                                 ritual: SilentRitualScheduler()).packedSummary
            }

            let packed = summary()
            check("a packed trip names the days, the countries and the budget",
                  packed.hasPrefix("61 days, 3 countries, ")
                      && packed.hasSuffix(". It's all already on the phone."),
                  packed)

            // The bug. A trip typed from scratch has no countries and no
            // budget, and the sentence stated both as though nought were an
            // answer — then promised that all of it was already on the phone.
            let nothing = summary {
                $0.itinerary = ItineraryDocument(legs: [])
                $0.budget = 0
            }
            check("with nothing in it, no count of nothing is stated",
                  !nothing.contains("0 countries") && !nothing.contains("countr")
                      && !nothing.contains("€0"),
                  nothing)
            check("and nothing is promised about what's on the phone",
                  !nothing.contains("already on the phone"), nothing)
            check("but it still says how long the trip is",
                  nothing == "61 days. Nothing else is settled yet, and nothing has to be.",
                  nothing)

            // Nothing forced the noun to agree, so this read "1 countries" —
            // the "One days in" bug, in the numeral branch.
            let single = summary { $0.itinerary = ItineraryDocument(legs: Array($0.itinerary.legs.prefix(1))) }
            check("one country is singular",
                  single.contains("1 country") && !single.contains("1 countries"),
                  single)

            // Each clause drops on its own, and the promise survives either one
            // surviving: it is about what was named, not about the itinerary.
            let unbudgeted = summary { $0.budget = 0 }
            check("a trip with no budget doesn't price itself at nought",
                  !unbudgeted.contains("€0") && unbudgeted.contains("3 countries"),
                  unbudgeted)
            check("and still says it's on the phone, because something is",
                  unbudgeted.hasSuffix("It's all already on the phone."), unbudgeted)

            let unplanned = summary { $0.itinerary = ItineraryDocument(legs: []) }
            check("a trip with a budget and nowhere to go keeps the budget",
                  !unplanned.contains("countr")
                      && unplanned.hasSuffix("It's all already on the phone."),
                  unplanned)

            // `dayCount` clamps to 1...3650, so one day is reachable and is the
            // other half of the agreement.
            let oneDay = summary { $0.dayCount = 1 }
            check("a one-day trip is one day",
                  oneDay.hasPrefix("1 day, "), oneDay)
        }

        print("— a line spent before the trip had anywhere in it —")
        do {
            let fixture = CheckTrip.snapshot()
            /// Day 12, with the ledger emptied and — unless asked otherwise —
            /// the itinerary taken out, which is the state every trip starts
            /// in: `TripStore.init` always seeds a blank one.
            func blank(withItinerary keep: Bool = false) -> TripStore {
                var snapshot = fixture
                if !keep { snapshot.itinerary = ItineraryDocument(legs: []) }
                let made = TripStore(storeKey: nil, snapshot: snapshot,
                                     clock: { Calendar.trip.date(byAdding: .day, value: 11,
                                                                 to: fixture.start)! },
                                     ritual: SilentRitualScheduler())
                made.expenses.removeAll()
                return made
            }

            let nowhere = blank()
            check("a screen still has a label to draw",
                  nowhere.currentCountry == TripStore.unknownPlace, nowhere.currentCountry)
            check("but a record is stamped with nothing at all",
                  nowhere.countryNow.isEmpty, "'\(nowhere.countryNow)'")

            nowhere.add(Expense(date: nowhere.now, amount: 250, currency: .thb, payer: .one,
                                split: .evenly, note: "noodles", country: nowhere.countryNow))
            let line = nowhere.expenses.live[0]
            check("so the em-dash never reaches the ledger",
                  line.country.isEmpty && line.country != TripStore.unknownPlace,
                  "'\(line.country)'")
            check("and nothing claims to know where it was spent",
                  nowhere.country(of: line) == nil)

            // The point of resolving rather than stamping: the money was spent
            // in Thailand whether or not Thailand had been typed in yet.
            let later = blank(withItinerary: true)
            later.add(line)
            check("once the itinerary exists the line joins the country it was spent in",
                  later.country(of: line) == "Thailand", later.country(of: line) ?? "nil")
            check("and shows up in what that country cost",
                  later.spent(inCountry: "Thailand").map { Int($0.local) } == 250,
                  "\(later.spent(inCountry: "Thailand")?.local ?? -1)")
            check("and in the per-day line",
                  later.perDayByCountry.contains { $0.country == "Thailand" },
                  "\(later.perDayByCountry.map(\.country))")

            // A ledger saved by the build that let the label through.
            var legacy = line
            legacy.country = TripStore.unknownPlace
            check("a line already stamped with the em-dash resolves the same way",
                  later.country(of: legacy) == "Thailand", later.country(of: legacy) ?? "nil")

            // And the other half: a stamp is a record, not a guess. Dragging a
            // stop must not re-file what was already spent.
            var stamped = line
            stamped.country = "Thailand"
            let vietnamDay = blank(withItinerary: true)
            check("a stamped line is never re-resolved",
                  vietnamDay.country(of: stamped) == "Thailand"
                      && vietnamDay.leg(forDay: 60)?.country == "South Korea",
                  vietnamDay.country(of: stamped) ?? "nil")

            // The last day of the trip falls inside no leg, the same half-open
            // gap `lastKnownSegment` exists for.
            var onTheWayHome = line
            onTheWayHome.date = later.date(forDay: 61)
            onTheWayHome.country = ""
            check("the morning they fly home still resolves",
                  later.country(of: onTheWayHome) == "South Korea",
                  later.country(of: onTheWayHome) ?? "nil")

            // A settlement carries the country it was raised in, and must not
            // carry the label either.
            let settling = blank()
            settling.add(Expense(date: settling.now, amount: 400, currency: .thb, payer: .one,
                                 split: .evenly, note: "room", country: settling.countryNow))
            let proposal = settling.proposeSettlement(note: "square up")
            check("a settlement raised with nowhere in the trip stamps nothing",
                  proposal?.country.isEmpty == true, "'\(proposal?.country ?? "nil")'")
        }

        print("— what today cost, in the money in hand —")
        do {
            let fixture = CheckTrip.snapshot()
            /// Day 12 of the packed trip, with the ledger emptied so each
            /// assertion below is about the lines it puts there itself.
            func onDayTwelve(legs keep: Bool = true) -> TripStore {
                var snapshot = fixture
                if !keep { snapshot.itinerary = ItineraryDocument(legs: []) }
                let made = TripStore(storeKey: nil, snapshot: snapshot,
                                     clock: { Calendar.trip.date(byAdding: .day, value: 11,
                                                                 to: fixture.start)! },
                                     ritual: SilentRitualScheduler())
                made.expenses.removeAll()
                return made
            }
            func spend(_ store: TripStore, _ amount: Double, _ currency: Currency,
                       _ note: String, kind: ExpenseKind = .spend, day: Int? = nil) {
                store.add(Expense(date: day.map { store.date(forDay: $0) } ?? store.now,
                                  amount: amount, currency: currency, payer: .one,
                                  split: .evenly, note: note, country: "Thailand", kind: kind))
            }

            let day12 = onDayTwelve()
            check("day 12 is spent in baht", day12.localCurrency == .thb, day12.localCurrency.code)
            check("a day with nothing on it is exact",
                  day12.spentTodayText == "฿0" && !day12.spentTodayIsConverted,
                  day12.spentTodayText)

            spend(day12, 250, .thb, "noodles")
            check("cash in the local currency is counted, and not approximated",
                  near(day12.spentTodayInLocal, 250) && day12.spentTodayText == "฿250"
                      && !day12.spentTodayIsConverted,
                  day12.spentTodayText)

            // The bug this exists for. It filtered on `currency == localCurrency`,
            // so a card payment left the figure at ฿250 — on the 30pt number
            // somebody had just tapped to add it.
            spend(day12, 20, .eur, "the flight")
            let euroInBaht = day12.inLocal(20, from: .eur)
            check("a payment in another currency moves the figure",
                  near(day12.spentTodayInLocal, 250 + euroInBaht, 0.5),
                  "\(Int(day12.spentTodayInLocal))")
            check("and it is no longer the local-cash-only answer",
                  !near(day12.spentTodayInLocal, 250, 1))
            check("saying it meant a rate, so it says so",
                  day12.spentTodayIsConverted && day12.spentTodayText.hasPrefix("≈"),
                  day12.spentTodayText)

            // What the figure must go on refusing.
            spend(day12, 500, .thb, "paid her back", kind: .transfer)
            check("a settlement between them is not spending",
                  near(day12.spentTodayInLocal, 250 + euroInBaht, 0.5),
                  "\(Int(day12.spentTodayInLocal))")

            spend(day12, 999, .thb, "yesterday", day: 11)
            check("and yesterday is not today",
                  near(day12.spentTodayInLocal, 250 + euroInBaht, 0.5),
                  "\(Int(day12.spentTodayInLocal))")

            let noodles = day12.expenses.live.first { $0.note == "noodles" }!
            day12.delete(noodles.id)
            check("a deleted line stops counting",
                  near(day12.spentTodayInLocal, euroInBaht, 0.5),
                  "\(Int(day12.spentTodayInLocal))")
            day12.restore(noodles.id)
            check("and counts again when it comes back",
                  near(day12.spentTodayInLocal, 250 + euroInBaht, 0.5),
                  "\(Int(day12.spentTodayInLocal))")

            // Baht carries no decimals, so the rounded branch is invisible on
            // the ordinary leg. It shows on one whose currency is the home one,
            // which is where an estimate would otherwise print its cents.
            let athome = onDayTwelve(legs: false)
            check("with nowhere in the trip the money in hand is the home one",
                  athome.localCurrency == .eur, athome.localCurrency.code)
            spend(athome, 20, .eur, "lunch")
            check("an exact euro figure keeps its cents",
                  athome.spentTodayText == "€20.00", athome.spentTodayText)
            spend(athome, 250, .thb, "cash")
            check("an estimate drops them, because ≈€26.43 argues with itself",
                  athome.spentTodayIsConverted && !athome.spentTodayText.contains("."),
                  athome.spentTodayText)
        }

        print("— the stop Today's panel opens —")
        do {
            // `todaySegment` is the lenient lookup B1's panel pushes to.
            // `contains(day:)` is half-open — `endDay` is the day they leave —
            // so the strict `currentSegment` answers nil on the last morning of
            // the trip, which is exactly when somebody opens the day to check
            // what time the flight is.
            let packed = CheckTrip.snapshot()
            func sitting(onDay day: Int) -> TripStore {
                TripStore(storeKey: nil, snapshot: packed,
                          clock: { Calendar.trip.date(byAdding: .day, value: day - 1,
                                                      to: packed.start)! },
                          ritual: SilentRitualScheduler())
            }

            let midTrip = sitting(onDay: 12)
            check("mid-trip it opens the stop they're standing in",
                  midTrip.todaySegment?.id == midTrip.currentSegment?.id
                      && midTrip.todaySegment?.primaryPlace == "Chiang Mai",
                  midTrip.todaySegment?.title ?? "nil")

            let lastMorning = sitting(onDay: 61)
            check("on the last morning the strict lookup gives up",
                  lastMorning.currentSegment == nil)
            check("and the panel still opens the last stop",
                  lastMorning.todaySegment?.primaryPlace == "Jeju",
                  lastMorning.todaySegment?.title ?? "nil")
            check("which is the answer the city was already giving",
                  lastMorning.todaySegment?.primaryPlace == lastMorning.currentCity)

            // Nowhere in the trip at all — which is every trip, until somebody
            // types one in. Nil, and B1 draws the itinerary rather than pushing
            // to a day that has no stop behind it.
            var emptied = packed
            emptied.itinerary = ItineraryDocument(legs: [])
            let nowhere = TripStore(storeKey: nil, snapshot: emptied,
                                    ritual: SilentRitualScheduler())
            check("with nowhere in the trip there is no stop to open",
                  nowhere.todaySegment == nil && nowhere.currentSegment == nil)
            check("and the city says so too", nowhere.currentCity == "—",
                  nowhere.currentCity)
        }

        print("— and what it is never told —")
        do {
            // Same trick as the sealed-letter check above, one channel over.
            // `SyncPayload` keeps its promise by not having the fields; so does
            // this, and here is the proof.
            let fields = Mirror(reflecting: WidgetSnapshot.placeholder).children
            let labels = fields.compactMap(\.label)
            let forbidden = ["letter", "journal", "entry", "note", "photo",
                             "document", "passport", "message", "body", "text", "title"]
            check("the widget's snapshot has no field for anything private",
                  !labels.contains { label in
                      forbidden.contains { label.lowercased().contains($0) }
                  }, "\(labels)")

            // The structural half, and the stronger one: a value with no
            // collection in it cannot carry a journal however anybody later
            // decides to name a field.
            let allowed: [Any.Type] = [Int.self, String.self, Bool.self, Double.self,
                                       Date.self, WidgetSnapshot.Phase.self,
                                       Optional<String>.self, Optional<Int>.self]
            let strays = fields.filter { child in
                !allowed.contains { $0 == type(of: child.value) }
            }
            check("and carries nothing but scalars, so it never could",
                  strays.isEmpty,
                  "\(strays.compactMap(\.label))")

            // The group container is addressed like the letter box: one key,
            // and the trip is not in it. This is what catches somebody later
            // "tidying" the trip blob into the shared suite because the widget
            // would find it convenient.
            let shared = Storage.shared
            check("the app and the widget do not share a suite",
                  shared !== Storage.defaults)
            let ours = (shared?.dictionaryRepresentation().keys ?? [:].keys)
                .filter { $0.hasPrefix("dithoi.") }
                .sorted()
            check("and the group holds exactly one key",
                  ours == [AppGroup.snapshotKey], "\(ours)")
        }

        print("— a waypoint knows its stop —")
        do {
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-joins"))

            // Nine of the eleven name exactly one stop and are named by exactly
            // one stamp, so they join on the way in.
            let joined = phone.stamps.live.filter { $0.segmentID != nil }
            check("the waypoints that can name their stop do",
                  joined.count == 9, "\(joined.count) of \(phone.stamps.live.count)")

            // And two of them cannot. "Ayutthaya · Pai" is one stop holding two
            // waypoints, so claiming it for either would be a guess — the kind
            // that had to be made destructively, once, at decode time, if the
            // waypoint had been moved inside the segment instead. Here it is
            // simply declined, and the string match carries on until somebody
            // says which is which in the editor.
            let ambiguous = phone.stamps.live.filter { ["AYU", "PAI"].contains($0.code) }
            check("and the pair that share one stop are left alone",
                  ambiguous.count == 2 && ambiguous.allSatisfy { $0.segmentID == nil },
                  "\(ambiguous.map { "\($0.code):\($0.segmentID == nil ? "—" : "joined")" })")
            check("but they still resolve, the way they always did",
                  ambiguous.allSatisfy { phone.segment(for: $0)?.title == "Ayutthaya · Pai" },
                  "\(ambiguous.compactMap { phone.segment(for: $0)?.title })")

            // Running it again changes nothing, which is what lets it run on
            // every launch and after every merge.
            let before = phone.stamps.map(\.segmentID)
            let stamped = phone.stamps.map(\.updatedAt)
            phone.backfillWaypointJoins()
            check("joining twice joins nothing twice",
                  phone.stamps.map(\.segmentID) == before)
            check("and is not an edit anybody made",
                  phone.stamps.map(\.updatedAt) == stamped)

            // A stop that was merged away leaves a waypoint pointing at
            // nothing. That is legal at rest: it falls back to the name and
            // keeps drawing, the way an orphaned page still prints.
            if let index = phone.stamps.firstIndex(where: { $0.code == "CNX" }) {
                phone.stamps[index].segmentID = UUID()
                check("a waypoint whose stop is gone still finds one by name",
                      phone.segment(for: phone.stamps[index])?.title == "Chiang Mai · Songkran",
                      "\(phone.segment(for: phone.stamps[index])?.title ?? "—")")
            } else {
                check("there was a Chiang Mai waypoint", false)
            }

            // The id wins over the name when both would answer — which is the
            // whole point, and the half a substring match got wrong.
            if let bangkok = phone.stamps.live.first(where: { $0.code == "BKK" }),
               let seoul = phone.itinerary.allSegments.first(where: { $0.title == "Seoul" }) {
                var moved = bangkok
                moved.segmentID = seoul.id
                check("a waypoint that names its stop is not second-guessed by its city",
                      phone.segment(for: moved)?.title == "Seoul",
                      "\(phone.segment(for: moved)?.title ?? "—")")
            } else {
                check("there was a Bangkok waypoint and a Seoul stop", false)
            }
        }

        print("— a waypoint's number comes from the plan —")
        do {
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-reflow"))
            func numbers() -> [Int] { phone.orderedStamps.map(\.index) }
            func codes() -> [String] { phone.orderedStamps.map(\.code) }

            let count = phone.stamps.live.count
            check("the numbers run one to n with no gaps",
                  numbers() == Array(1...count), "\(numbers())")
            check("and no two waypoints share one",
                  Set(numbers()).count == numbers().count)

            // Nothing has moved, so nothing should have been renumbered — an
            // un-joined trip has to sort exactly the way it always did.
            phone.reflowWaypoints()
            check("a plan nobody touched renumbers nothing",
                  codes() == ["BKK", "AYU", "PAI", "CNX", "CEI", "HAN", "HOI", "SGN", "SEL", "PUS", "CJU"],
                  "\(codes())")

            // Move the last stop of Thailand to the front of it. Chiang Rai
            // has to come with it, because the number follows the plan.
            let thailand = phone.legs[0]
            let before = phone.stamps.first { $0.code == "CEI" }?.updatedAt
            phone.moveSegments(inLeg: thailand.id, from: IndexSet(integer: 3), to: 0)
            check("moving a stop renumbers the waypoints",
                  codes().first == "CEI", "\(codes())")
            check("and the numbers still run one to n",
                  numbers() == Array(1...count), "\(numbers())")
            check("and renumbering is an edit, so the other phone keeps it",
                  phone.stamps.first { $0.code == "CEI" }?.updatedAt != before)

            // Put it back, then remove a stop from the middle. The gap closes.
            phone.moveSegments(inLeg: thailand.id, from: IndexSet(integer: 0), to: 4)
            if let bangkok = phone.itinerary.allSegments.first(where: { $0.title == "Bangkok" }) {
                phone.removeSegment(bangkok.id)
                check("removing a stop closes the gap it left",
                      numbers() == Array(1...phone.stamps.live.count), "\(numbers())")
                check("and the waypoint it held is still there, on its name",
                      phone.orderedStamps.contains { $0.code == "BKK" },
                      "\(codes())")
            } else {
                check("there was a Bangkok stop", false)
            }
        }

        print("— what a waypoint costs to take away —")
        do {
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-waypoints"))

            // Earned is the one that is simply refused. It is a record of
            // somebody standing somewhere, and three other numbers are built
            // on it.
            guard let earned = phone.earnedStamps.first else {
                check("there was an earned waypoint", false)
                return
            }
            check("an earned waypoint says why it can't be changed",
                  phone.waypointIsLocked(earned) != nil, "\(phone.waypointIsLocked(earned) ?? "nil")")
            check("and refuses to be removed", phone.removeWaypoint(earned.id) == false)
            check("and refuses to be re-coded",
                  phone.updateWaypoint(earned.id, code: "XXX") == false)
            check("and is still there afterwards",
                  phone.stamps.live.contains { $0.id == earned.id })

            // An unearned one a sealed letter names can go — but the cost is
            // said out loud first, with the number.
            guard let hoiAn = phone.stamps.live.first(where: { $0.code == "HOI" }) else {
                check("there was a Hội An waypoint", false)
                return
            }
            let cost = phone.removalCost(ofWaypoint: hoiAn)
            check("removing one a sealed letter waits on names the letter",
                  cost?.contains("06") == true, "\(cost ?? "nothing said")")

            // And once it is gone, the letter has to *read* as stranded.
            // "Not earned yet" and "will never exist" were the same sentence
            // until the moment knew which waypoints the trip still had.
            check("it can be removed anyway", phone.removeWaypoint(hoiAn.id))
            let moment = phone.letterMoment
            check("and the condition then reads as dead, not as waiting",
                  LetterCondition.stamp("HOI").canStillFire(moment) == false,
                  "\(LetterCondition.stamp("HOI").deadReason(moment) ?? "still live")")
            check("and says the stamp is gone rather than that it passed",
                  LetterCondition.stamp("HOI").deadReason(moment) == "that stamp is gone",
                  "\(LetterCondition.stamp("HOI").deadReason(moment) ?? "nil")")
            if let waiting = phone.nextStamp {
                check("while one still on the trip is still waiting",
                      LetterCondition.stamp(waiting.code).canStillFire(moment),
                      "\(waiting.code)")
            } else {
                check("there was a waypoint still to earn", false)
            }

            // Codes are unique, and short enough for the circle they print in.
            guard let stop = phone.itinerary.allSegments.first(where: { $0.title == "Seoul" }) else {
                check("there was a Seoul stop", false)
                return
            }
            check("a code already in use is refused",
                  phone.addWaypoint(code: "CEI", city: "Somewhere", arrivalNote: "",
                                    toSegment: stop.id) == nil)
            check("and one too long for the book's circle is too",
                  phone.addWaypoint(code: "TOOLONG", city: "Somewhere", arrivalNote: "",
                                    toSegment: stop.id) == nil)
            // A stop that names two places holds two stamps — "Ayutthaya · Pai"
            // is one, and every screen has to be able to reach both of them.
            // This was `first` once: the editor drew PAI under the stop it
            // shares with AYU, and AYU could not be opened, corrected or
            // removed anywhere in the app. Every check here passed anyway, because
            // both still resolved to a stop and both still sorted — which is all
            // they were asking. The screenshot is what noticed.
            guard let shared = phone.itinerary.allSegments.first(where: { $0.title == "Ayutthaya · Pai" }) else {
                check("there was a stop naming two places", false)
                return
            }
            check("a stop naming two places shows both its stamps",
                  phone.waypoints(forSegment: shared.id).map(\.code) == ["AYU", "PAI"],
                  "\(phone.waypoints(forSegment: shared.id).map(\.code))")
            check("and every waypoint is reachable from the stop it belongs to",
                  Set(phone.itinerary.allSegments.flatMap { phone.waypoints(forSegment: $0.id) }.map(\.id))
                      == Set(phone.stamps.live.map(\.id)),
                  "\(phone.stamps.live.count) live")
            check("and a stop can be given another",
                  phone.addWaypoint(code: "ZZ", city: "Somewhere else", arrivalNote: "",
                                    toSegment: stop.id) != nil)

            // Both sheets that make a stop hand one back, so both can stamp it
            // where it is typed. `addLeg` returned nothing for a long time, and
            // on a blank trip the country sheet is the *only* way to make a
            // stop — so the first stop of every country was the one stop whose
            // stamp had to be added afterwards, from a different sheet.
            do {
                let typed = TripStore(storeKey: nil,
                                      ritual: SilentRitualScheduler(),
                                      library: TripLibrary(key: "dithoi.library.checks-first-stop"))
                let firstStop = typed.addLeg(country: "Portugal", currency: .eur,
                                             firstStop: "Lisbon", nights: 4)
                check("the country sheet's first stop comes back to its caller",
                      firstStop?.title == "Lisbon", "\(String(describing: firstStop?.title))")
                check("with the days it has after the reflow, not before",
                      firstStop?.startDay == typed.legs.first?.segments.first?.startDay &&
                      firstStop?.endDay == typed.legs.first?.segments.first?.endDay,
                      "\(String(describing: firstStop))")
                check("so it can be stamped in the same breath",
                      firstStop.flatMap {
                          typed.addWaypoint(code: "LIS", city: "Lisbon",
                                            arrivalNote: "You're standing in it.",
                                            toSegment: $0.id)
                      } != nil)
                check("and the stamp joins that stop by id, not by name",
                      firstStop.map { typed.waypoints(forSegment: $0.id).map(\.code) } == ["LIS"],
                      "\(typed.orderedStamps.map(\.code))")
                Storage.forget("dithoi.library.checks-first-stop")
            }

            // A new one on a stop with none, which is the whole point of the
            // half: a trip nobody packed can now have a trail.
            let blank = TripStore(storeKey: nil,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-waypoints-blank"))
            blank.addLeg(country: "Portugal", currency: .eur, firstStop: "Lisbon", nights: 4)
            blank.addSegment(title: "Porto", nights: 3,
                             toLeg: blank.legs.first?.id ?? UUID())
            check("a trip nobody packed starts with no trail at all",
                  blank.orderedStamps.isEmpty)
            for (code, city) in [("LIS", "Lisbon"), ("OPO", "Porto")] {
                guard let segment = blank.itinerary.allSegments.first(where: { $0.title == city }) else { continue }
                blank.addWaypoint(code: code, city: city, arrivalNote: "You're standing in it.",
                                  toSegment: segment.id)
            }
            check("and can be given one, a stop at a time",
                  blank.orderedStamps.map(\.code) == ["LIS", "OPO"],
                  "\(blank.orderedStamps.map(\.code))")
            check("numbered from the plan, not from the typing",
                  blank.orderedStamps.map(\.index) == [1, 2],
                  "\(blank.orderedStamps.map(\.index))")

            // Reorder the stops and the numbers follow.
            blank.moveSegments(inLeg: blank.legs[0].id, from: IndexSet(integer: 1), to: 0)
            check("and they follow the stops when those move",
                  blank.orderedStamps.map(\.code) == ["OPO", "LIS"],
                  "\(blank.orderedStamps.map(\.code))")

            // A waypoint typed rather than packed has no coordinate, so
            // standing in it is the only chance to record one.
            guard let next = blank.nextStamp else {
                check("there was a waypoint to earn", false)
                return
            }
            check("a typed waypoint starts with no position", !next.hasLocation)
            blank.arrive(at: next)
            check("and earning it without a fix leaves it that way, rather than at zero-zero",
                  blank.earnedStamps.first?.hasLocation == false,
                  "\(blank.earnedStamps.first?.latitude ?? -1)")
        }

        print("— four holes the review found —")
        do {
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-holes"))

            // 1 · A waypoint with no position used to zero the legs on *both*
            // sides of it, because `kilometres(to:)` answers 0 when either end
            // is unlocated. A trip whose waypoints were typed has nothing but
            // those, so the headline stopped growing under "and counting".
            let before = phone.kilometresTravelled
            check("the trail has a distance to begin with", before > 0, "\(before) km")
            if let index = phone.stamps.firstIndex(where: { $0.earned && $0.code == "AYU" }) {
                phone.stamps[index].latitude = 0
                phone.stamps[index].longitude = 0
                let after = phone.kilometresTravelled
                check("a waypoint with no position is skipped, not counted as zero",
                      after > 0, "\(before) km -> \(after) km")
                check("and the trail still measures the places it does know",
                      after != before, "\(after) km")
            } else {
                check("there was an earned waypoint to strip", false)
            }

            // 2 · Appending was refused when it would take a `.finalStamp`
            // letter back. Removing the last unearned waypoint does the
            // opposite — it completes the trail and opens that letter on the
            // spot — and only one of the two guards existed.
            let solo = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-final"))
            for stamp in solo.stamps.live where !stamp.earned && stamp.code != "CJU" {
                solo.stamps[solo.stamps.firstIndex { $0.id == stamp.id }!].deletedAt = solo.now
            }
            guard let last = solo.stamps.live.first(where: { !$0.earned }) else {
                check("one waypoint was left unearned", false)
                return
            }
            let openBefore = solo.letters.filter(\.isOpen).count
            check("removing the last unstood-in stop is refused",
                  solo.removalRefusal(ofWaypoint: last) != nil,
                  "\(solo.removalRefusal(ofWaypoint: last) ?? "allowed")")
            check("and the removal does not go through",
                  solo.removeWaypoint(last.id) == false)
            check("so no letter opens where nobody chose",
                  solo.letters.filter(\.isOpen).count == openBefore)

            // 3 · A removed code came free again, because `stamps.live` cannot
            // see a tombstone — so letter 06 could be handed to a stamp in
            // Busan that the writer never picked.
            let reuse = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-reuse"))
            guard let hoi = reuse.stamps.live.first(where: { $0.code == "HOI" }),
                  let busan = reuse.itinerary.allSegments.first(where: { $0.title == "Busan" }) else {
                check("there was a Hội An waypoint and a Busan stop", false)
                return
            }
            // Sealed to the *code*, which is the case the guard is about. The
            // packed trip's letter 06 depends on Hội An through the stamp's own
            // `unlocksLetter`, and that goes into the tombstone with it.
            reuse.letters.append(Letter(number: 99, title: "For the old town",
                                        writtenOn: reuse.now, condition: .stamp("HOI"),
                                        hint: "opens with the hoi stamp",
                                        paragraphs: ["Written before you left."],
                                        signature: "— me", sealedAt: reuse.now))
            check("the sealed letter's stamp can be removed", reuse.removeWaypoint(hoi.id))
            check("but its code cannot be given to another stop",
                  reuse.codeIsAvailable("HOI") == false)
            check("and adding one with it is refused",
                  reuse.addWaypoint(code: "HOI", city: "Busan", arrivalNote: "",
                                    toSegment: busan.id) == nil)
            // A place is the place, though — a new waypoint for the same city
            // firing the letter sealed to that city is right.
            check("while the city stays usable, because a place is the place",
                  reuse.addWaypoint(code: "HA", city: "Hội An", arrivalNote: "",
                                    toSegment: busan.id) != nil)

            // 4 · The print warning lists days, and a page and a moment on one
            // day are two soft photographs and one day to go and look at.
            let spec = BookSpec()
            let soft = PrintReadiness.measure(
                plan: phone.bookPlan,
                photos: [PhotoMeasurement(id: UUID(), dayNumber: 22, pixels: 800),
                         PhotoMeasurement(id: UUID(), dayNumber: 22, pixels: 900),
                         PhotoMeasurement(id: UUID(), dayNumber: 31, pixels: 700)],
                entriesWithoutPhoto: 0)
            check("a day with two soft photographs is named once",
                  soft.softSummary?.hasPrefix("Day 22 and day 31") == true,
                  "\(soft.softSummary ?? "nothing")")
            check("and both photographs are still counted",
                  soft.softPhotos.count == 3, "\(soft.softPhotos)")
            _ = spec
        }

        print("— moments print with their country —")
        do {
            // They used to be one section at the back, so a day-12 moment
            // printed a hundred pages after day 12. Built from the plan alone,
            // so every arrangement can be walked without a store.
            let legs = store.legs
            let entries = store.myEntries
            func moment(_ day: Int, photo: Bool = false, _ note: String = "A moment") -> Moment {
                Moment(capturedAt: store.start.addingTimeInterval(Double(day) * 86_400 + 3_600),
                       dayNumber: day, city: "", note: note, hasPhoto: photo,
                       photoID: photo ? "photo-\(day)-\(note)" : nil)
            }
            // Every moment a page draws: on a moments spread, or carried by its
            // country's opener.
            func drawn(_ spreads: [BookSpread]) -> [UUID] {
                spreads.flatMap { spread -> [UUID] in
                    switch spread {
                    case .moments(_, _, _, let left, let right): return left + right
                    case .countryOpener(_, _, _, _, _, _, _, _, let carried): return carried
                    default: return []
                    }
                }
            }
            func legIndex(forDay day: Int) -> Int? {
                legs.indices.first { day >= legs[$0].startDay && ($0 == legs.count - 1 || day < legs[$0].endDay) }
            }
            func lastContent(_ plan: BookPlan) -> Int {
                BookPlan.leftPage(ofSpreadAt: plan.spreads.count - 1 - plan.notesSpreadCount) - 1
            }

            let none = BookPlan.build(entries: entries, legs: legs, stamps: store.stamps)
            check("a book with no moments has no moments spreads",
                  none.momentSpreadCount == 0 && !none.sections.contains { $0.title.hasPrefix("Along the way") },
                  "\(none.sections.map(\.title))")

            // Six to a spread, so these are the boundaries: one, a full spread,
            // one past a full spread, and four spreads' worth — spread across
            // the whole trip, every third one a photograph.
            let span = max(store.dayCount, 1)
            for count in [1, 6, 7, 25] {
                let moments = (0..<count).map { moment(1 + $0 * span / count, photo: $0 % 3 == 0, "Moment \($0)") }
                let plan = BookPlan.build(entries: entries, legs: legs, stamps: store.stamps, moments: moments)

                // The reversal: walk the spreads back out and read what the
                // pages actually draw. A cap or an off-by-one loses records
                // silently, and this is what refuses to let it.
                check("every moment reaches exactly one page, in the order it happened",
                      drawn(plan.spreads) == moments.map(\.id),
                      "\(count) moments, drew \(drawn(plan.spreads).count)")
                let weights = Dictionary(uniqueKeysWithValues: moments.map {
                    ($0.id, BookPlan.momentWeight(hasPhoto: $0.photoID != nil))
                })
                check("and no page holds more than it can",
                      plan.spreads.allSatisfy { spread in
                          guard case .moments(_, _, _, let left, let right) = spread else { return true }
                          return [left, right].allSatisfy {
                              $0.reduce(0) { $0 + (weights[$1] ?? 0) } <= BookPlan.momentPageCapacity
                          } && !left.isEmpty
                      })
                check("and each one prints inside its own country's section",
                      moments.allSatisfy { moment in
                          guard let leg = legIndex(forDay: moment.dayNumber),
                                let index = plan.spreadIndex(containing: moment.id) else { return false }
                          let page = BookPlan.leftPage(ofSpreadAt: index)
                          let section = plan.sections.first { $0.firstPage <= page && page <= $0.lastPage }
                          return section?.title.hasPrefix(legs[leg].country) == true
                      })
                check("and after that country's last night, not at the back",
                      plan.spreads.enumerated().allSatisfy { index, spread in
                          guard case .moments(let group, _, _, _, _) = spread,
                                let leg = legs.first(where: { $0.id.uuidString == group }) else { return true }
                          let lastDay = plan.spreads.lastIndex { item in
                              guard case .day(let id) = item, let entry = entries.first(where: { $0.id == id }) else { return false }
                              return legIndex(forDay: entry.dayNumber).map { legs[$0].id } == leg.id
                          }
                          return lastDay.map { $0 < index } ?? true
                      } && plan.spreads.lastIndex { if case .moments = $0 { return true }; return false }
                          .map { $0 < (plan.spreads.firstIndex { if case .wholeTrip = $0 { return true }; return false } ?? .max) } ?? true)
                check("and there is no moments section of its own",
                      !plan.sections.contains { $0.title.hasPrefix("Along the way") },
                      "\(plan.sections.map(\.title))")
                check("the contents still cover every page up to the notes",
                      plan.sections.last?.lastPage == lastContent(plan),
                      "\(plan.sections.last?.lastPage ?? -1) of \(lastContent(plan))")
                check("and no section overlaps the one before it",
                      zip(plan.sections, plan.sections.dropFirst()).allSatisfy { $0.lastPage < $1.firstPage },
                      "\(plan.sections.map(\.pageRange))")
                check("and no spread is drawn twice",
                      Set(plan.spreads.map(\.id)).count == plan.spreads.count)
                check("and a moment is not counted as a day",
                      plan.dayCountInBook == entries.count)
                check("and every spread is one of the kinds the book counts",
                      3 + plan.contentsSpreadCount + plan.countryOpenerCount + plan.dayCountInBook
                          + plan.momentSpreadCount + plan.endmatterCount + plan.notesSpreadCount
                          == plan.spreads.count, "\(plan.spreads.count)")
            }

            // An odd page leaves the facing one for notes, rather than a
            // heading over nothing. Three in words is one page, and more than
            // an opener carries.
            let single = BookPlan.build(entries: entries, legs: legs, stamps: store.stamps,
                                        moments: [moment(3, "One"), moment(3, "Two"), moment(3, "Three")])
            check("a single page of moments faces a ruled page",
                  single.spreads.contains { if case .moments(_, _, _, let l, let r) = $0 { return l.count == 3 && r.isEmpty }; return false })

            // A short group rides on its country's opener instead.
            let carriedPlan = BookPlan.build(entries: entries, legs: legs, stamps: store.stamps,
                                             moments: [moment(3, "The noodle stall"), moment(4, "Rain")])
            check("two short moments print on the opener, not a spread of their own",
                  carriedPlan.momentSpreadCount == 0
                      && carriedPlan.spreads.contains {
                          if case .countryOpener(_, _, _, _, _, _, _, _, let carried) = $0 { return carried.count == 2 }
                          return false
                      })
            let long = String(repeating: "a", count: OpenerMoments.noteLimit + 1)
            let cases: [(String, [Moment], Bool)] = [
                ("nothing", [], false),
                ("one in words", [moment(3, "One")], true),
                ("two in words", [moment(3, "One"), moment(3, "Two")], true),
                ("three in words", [moment(3, "One"), moment(3, "Two"), moment(3, "Three")], false),
                ("one with a photo", [moment(3, photo: true, "One")], true),
                ("a photo and words", [moment(3, photo: true, "One"), moment(3, "Two")], false),
                ("two photos", [moment(3, photo: true, "One"), moment(3, photo: true, "Two")], false),
                ("a note past the limit", [moment(3, long)], false)
            ]
            for (name, group, expected) in cases {
                check("an opener carries \(name): \(expected)", BookPlan.openerCarries(group) == expected)
            }
            check("a country with one or two places lists its stops under the map, and three is a map",
                  BookPlan.openerListsStops(locatedPlaces: 1) && BookPlan.openerListsStops(locatedPlaces: 2)
                      && !BookPlan.openerListsStops(locatedPlaces: 3))
            check("and are found there",
                  carriedPlan.spreadIndex(containing: drawn(carriedPlan.spreads)[0])
                      .map { if case .countryOpener = carriedPlan.spreads[$0] { return true }; return false } ?? false)

            // At the airport, before day 1: they open the book, ahead of the
            // first country.
            let early = [moment(-2, "At Schiphol"), moment(0, "On the plane"), moment(3)]
            let withEarly = BookPlan.build(entries: entries, legs: legs, stamps: store.stamps, moments: early)
            let firstOpener = withEarly.spreads.firstIndex { if case .countryOpener = $0 { return true }; return false } ?? -1
            let beforeIndex = withEarly.spreads.firstIndex { if case .moments("before", _, _, _, _) = $0 { return true }; return false } ?? .max
            check("moments from before departure come before the first country",
                  beforeIndex < firstOpener && withEarly.sections.contains { $0.title == "Before we left" },
                  "\(beforeIndex) vs \(firstOpener)")
            check("and are not filed under it",
                  drawn(withEarly.spreads).prefix(2).elementsEqual(early.prefix(2).map(\.id)))

            // After the last day it is the last country's, the way a page is:
            // the last leg keeps every day from its start on.
            let late = moment(store.dayCount + 40, "After the flight")
            let withLate = BookPlan.build(entries: entries, legs: legs, stamps: store.stamps, moments: [late])
            check("a moment after the last day is the last country's",
                  withLate.spreadIndex(containing: late.id).map { index in
                      switch withLate.spreads[index] {
                      case .moments(let group, _, _, _, _): return group == legs.last?.id.uuidString
                      case .countryOpener(let id, _, _, _, _, _, _, _, _): return id == legs.last?.id
                      default: return false
                      }
                  } ?? false)
            // On no itinerary at all, like an orphaned page: kept, under Elsewhere.
            let stray = moment(5, "Off the map")
            let withStray = BookPlan.build(entries: [], legs: [], stamps: [], moments: [stray])
            check("a moment with no country to go in is still in the book, under Elsewhere",
                  drawn(withStray.spreads) == [stray.id] && withStray.sections.contains { $0.title == "Elsewhere" },
                  "\(withStray.sections.map(\.title))")

            // A country nobody wrote a night in, but somebody kept a moment.
            if legs.count >= 2 {
                let quiet = legs[1]
                let unwritten = entries.filter { legIndex(forDay: $0.dayNumber) != 1 }
                let plan = BookPlan.build(entries: unwritten, legs: legs, stamps: store.stamps,
                                          moments: [moment(quiet.startDay)])
                check("a country with a moment and no page still opens",
                      plan.spreads.contains { if case .countryOpener(let id, _, _, _, _, _, _, _, _) = $0 { return id == quiet.id }; return false })
            }

            // Cut into volumes: a country's moments stay with its days.
            let many = (0..<25).map { moment(1 + $0 * span / 25, "Moment \($0)") }
            for volumes in [2, 3] {
                let plan = BookPlan.build(entries: entries, legs: legs, stamps: store.stamps,
                                          moments: many, volumes: volumes)
                // Right after something of the same country in the same file:
                // its last night, its opener, or its previous moments page.
                func belongs(_ spread: BookSpread, to group: String) -> Bool {
                    switch spread {
                    case .day(let id):
                        guard let day = entries.first(where: { $0.id == id })?.dayNumber,
                              let leg = legIndex(forDay: day) else { return false }
                        return legs[leg].id.uuidString == group
                    case .countryOpener(let id, _, _, _, _, _, _, _, _): return id.uuidString == group
                    case .moments(let other, _, _, _, _): return other == group
                    default: return false
                    }
                }
                check("in \(volumes) volumes, a country's moments follow its last night in the same file",
                      plan.volumeSpreads.allSatisfy { volume in
                          volume.indices.allSatisfy { index in
                              guard case .moments(let group, _, _, _, _) = volume[index],
                                    UUID(uuidString: group) != nil else { return true }
                              return index > 0 && belongs(volume[index - 1], to: group)
                          }
                      })
                check("and every moment is in exactly one volume",
                      plan.volumeSpreads.flatMap(drawn) == many.map(\.id))
            }
        }

        print("— the book and the rest of the app —")
        do {
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-connect"))

            // Where we said we'd meet: the list the picker keeps, printed.
            let before = phone.bookPlan
            check("no meeting places, no spread and no contents row",
                  phone.meetingPlaces.isEmpty ? (before.meetingSpreadCount == 0
                      && !before.sections.contains { $0.title == "Where we said we'd meet" }) : true)
            for (index, name) in ["The bridge", "Gate 3", "The blue door", "The pier", "Café Ba"].enumerated() {
                phone.setMeetingPoint(MeetingPoint(place: name, detail: "Detail \(index)",
                                                   localScript: "", setAt: phone.now))
            }
            let withPlaces = phone.bookPlan
            check("setting a meeting point rebuilds the book",
                  withPlaces == phone.freshBookPlan() && withPlaces.meetingSpreadCount > 0,
                  "\(withPlaces.meetingSpreadCount) spreads")
            check("and lists them under their own heading, before the whole trip",
                  BookPlan.contentsRows(withPlaces.sections).suffix(2).map(\.title)
                      == ["Where we said we'd meet", "The whole trip"],
                  "\(withPlaces.sections.map(\.title))")
            let places = phone.bookMeetingPlaces
            for count in [1, 4, 5, 12, 13] {
                let spreads = BookPlan.pagedSpreadCount(count: count, perPage: BookPlan.meetingPlacesPerPage)
                var drawn: [Int] = []
                for page in 0..<spreads {
                    for half in 0..<2 {
                        if let range = BookPlan.pagedRange(spread: page, half: half, count: count,
                                                           perPage: BookPlan.meetingPlacesPerPage) {
                            drawn += Array(range)
                        }
                    }
                }
                check("\(count) meeting places each print once", drawn == Array(0..<count), "\(drawn)")
            }
            check("a place nobody set never prints",
                  BookPlan.meetingPlacesInOrder([MeetingPoint(place: "  ", detail: "", localScript: "",
                                                              setAt: phone.now)]).isEmpty)
            let earlier = MeetingPoint(place: "Zebra crossing", detail: "", localScript: "",
                                       setAt: phone.now.addingTimeInterval(-86_400))
            check("and they print oldest first",
                  BookPlan.meetingPlacesInOrder(places + [earlier]).first?.place == "Zebra crossing")
            check("every spread is still one of the kinds the book counts",
                  3 + withPlaces.contentsSpreadCount + withPlaces.countryOpenerCount + withPlaces.dayCountInBook
                      + withPlaces.momentSpreadCount + withPlaces.endmatterCount + withPlaces.notesSpreadCount
                      == withPlaces.spreads.count)

            // A year ago today opens the book at the page it remembers.
            if let entry = phone.myEntries.first {
                let index = withPlaces.spreadIndex(containing: entry.id)
                check("a night's page is found in its book",
                      index.map { withPlaces.spreads[$0] == .day(entryID: entry.id) } ?? false)
            }
            let kept = phone.addMoment(note: "The one to remember")
            if let kept {
                let index = phone.bookPlan.spreadIndex(containing: kept.id)
                check("and so is a moment, on a moments page or carried by its opener",
                      index.map { spread in
                          switch phone.bookPlan.spreads[spread] {
                          case .moments(_, _, _, let l, let r): return (l + r).contains(kept.id)
                          case .countryOpener(_, _, _, _, _, _, _, _, let carried): return carried.contains(kept.id)
                          default: return false
                          }
                      } ?? false)
            }
            check("and something the book doesn't print is nowhere",
                  withPlaces.spreadIndex(containing: UUID()) == nil
                      && BookPlan.empty.spreadIndex(containing: phone.myEntries.first?.id ?? UUID()) == nil)

            // A missed night's composer offers that night's moments, finished
            // ones only.
            let unfinished = phone.addMoment(note: "")
            let onDay = phone.moments(onDay: phone.dayNumber)
            check("a night's strip holds that night's written-up moments",
                  onDay.contains { $0.id == kept?.id } && !onDay.contains { $0.id == unfinished?.id },
                  "\(onDay.map(\.note))")
            check("and nothing from another night",
                  phone.moments(onDay: phone.dayNumber + 1).allSatisfy { $0.dayNumber == phone.dayNumber + 1 })

            // The Book tab's early line.
            func readiness(_ soft: [Int], unfinished: Int) -> PrintReadiness {
                PrintReadiness(pageCount: 24, softPhotos: soft, missingPhotos: 0, estimatedMegabytes: 1,
                               unfinishedMoments: unfinished)
            }
            check("nothing to fix, no line", readiness([], unfinished: 0).earlyLine == nil)
            check("one soft photo names its day",
                  readiness([17], unfinished: 0).earlyLine == "Before it prints: a photo on day 17 is small for its page.",
                  readiness([17], unfinished: 0).earlyLine ?? "nil")
            check("two on one day are one day",
                  readiness([17, 17, 22], unfinished: 0).earlyLine
                      == "Before it prints: photos on day 17 and day 22 are small for their pages.",
                  readiness([17, 17, 22], unfinished: 0).earlyLine ?? "nil")
            check("an unfinished moment alone",
                  readiness([], unfinished: 1).earlyLine == "Before it prints: one moment has nothing in it yet.")
            check("and both, with the count spelled",
                  readiness([4], unfinished: 3).earlyLine
                      == "Before it prints: a photo on day 4 is small for its page, and three moments have nothing in them yet.",
                  readiness([4], unfinished: 3).earlyLine ?? "nil")
            check("and a moment from before they left is not 'day -2'",
                  readiness([-2], unfinished: 0).earlyLine?.contains("the days before you left") == true)
            let measured = PrintReadiness.measure(
                plan: withPlaces,
                photos: [PhotoMeasurement(id: UUID(), dayNumber: 22, pixels: 700),
                         PhotoMeasurement(id: UUID(), dayNumber: 9, pixels: 600),
                         PhotoMeasurement(id: UUID(), dayNumber: 30, pixels: 4_000)],
                entriesWithoutPhoto: 0)
            check("the soft records are named, earliest day first, and the sharp one isn't",
                  measured.softRecords.count == 2 && measured.softPhotos.sorted() == [9, 22])
        }

        print("— a moment is not a stamp —")
        do {
            // The whole argument for a second type. A moment records that
            // somebody stopped somewhere; it is not a waypoint with a place in
            // the order, and it is not a key a letter can be sealed to. If any
            // of these move, a noodle stall has become "Next stop" and a letter
            // has opened at one.
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-moments"))
            let earnedBefore = phone.earnedStamps.count
            let totalBefore = phone.orderedStamps.count
            let kmBefore = phone.kilometresTravelled
            let openBefore = phone.letters.filter(\.isOpen).count
            let nextBefore = phone.nextStamp?.code

            // Half a continent from the last stamp, which is what would show up
            // in the distance if a moment ever counted toward it.
            phone.addMoment(note: "The best coffee of the whole trip",
                            latitude: 35.6762, longitude: 139.6503)
            phone.addMoment(note: "Missed the last bus")

            check("a moment earns nothing", phone.earnedStamps.count == earnedBefore,
                  "\(earnedBefore) -> \(phone.earnedStamps.count)")
            check("and does not move the denominator",
                  phone.orderedStamps.count == totalBefore,
                  "\(totalBefore) -> \(phone.orderedStamps.count)")
            check("and walks nobody anywhere",
                  phone.kilometresTravelled == kmBefore,
                  "\(kmBefore) -> \(phone.kilometresTravelled) km")
            check("and opens no letter",
                  phone.letters.filter(\.isOpen).count == openBefore)
            check("and is never the next stop", phone.nextStamp?.code == nextBefore,
                  "\(nextBefore ?? "—") -> \(phone.nextStamp?.code ?? "—")")
            check("but it is kept", phone.moments.count == 2, "\(phone.moments.count)")

            // The type cannot be tombstoned into a syncable record: without
            // `updatedAt` it cannot conform to `SyncableRecord`, so it cannot
            // be `merged(with:)`, so it cannot be unioned into a payload by
            // somebody tidying. Same trick as the sealed letter's read receipt.
            let fields = Mirror(reflecting: Moment(capturedAt: phone.now, dayNumber: 1,
                                                   city: "Bangkok", note: ""))
                .children.compactMap(\.label)
            check("a moment has nothing to merge with",
                  !fields.contains("updatedAt") && !fields.contains("deletedAt"),
                  "\(fields)")

            // And the observer is standing in their own kitchen.
            let home = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-moments-home"))
            home.participant = .writer
            home.writeTo(.one)
            check("home cannot keep one",
                  home.addMoment(note: "Thinking about you") == nil && home.moments.isEmpty,
                  "\(home.moments.count)")

            // At the airport, five days early. `dayNumber` clamps to 1, so the
            // moment used to be filed as day 1 in the first stop's city — a
            // place they had not reached, printed in the book as if they had.
            let early = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  clock: { Calendar.trip.date(byAdding: .day, value: -5,
                                                              to: store.snapshot.start)! },
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-moments-early"))
            let schiphol = early.addMoment(note: "Gate D7, far too early")
            check("a moment before departure is kept", schiphol != nil)
            check("on its true day, not day 1",
                  schiphol?.dayNumber == -4 && schiphol?.isBeforeDeparture == true,
                  "\(schiphol?.dayNumber ?? 99)")
            check("and in no city it hadn't reached",
                  schiphol?.city == "" && schiphol?.place == nil, schiphol?.city ?? "nil")
            check("and says so rather than printing a separator",
                  schiphol?.caption == "before we left", schiphol?.caption ?? "nil")
            if let schiphol {
                early.setStart(Calendar.trip.date(byAdding: .day, value: 3, to: early.start)!)
                let moved = early.moments.first { $0.id == schiphol.id }
                check("a later departure keeps it before departure",
                      moved?.isBeforeDeparture == true && moved?.dayNumber == -4)
            }

            // A trip with nowhere in it — which every first launch is. The
            // em-dash is what a label says; `countryNow` already learned not
            // to write it into a record.
            let blank = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-moments-blank"))
            for leg in blank.legs { blank.removeLeg(leg.id) }
            let nowhere = blank.addMoment(note: "Somewhere")
            check("a moment on a blank trip stores no em-dash",
                  nowhere?.city == "" && nowhere?.caption == "day \(blank.dayNumber)",
                  "\(nowhere?.city ?? "nil") / \(nowhere?.caption ?? "nil")")
            check("and one on a planned trip names the stop",
                  phone.moments.last?.caption == "day \(phone.dayNumber) · \(phone.currentCity)",
                  phone.moments.last?.caption ?? "nil")
            check("a legacy em-dash reads as no place",
                  Moment(capturedAt: phone.now, dayNumber: 2, city: "—", note: "").caption == "day 2")

            // The full list, grouped by where each run of moments was kept.
            func kept(_ day: Int, _ city: String, _ hour: Int) -> Moment {
                Moment(capturedAt: Calendar.trip.date(byAdding: .hour, value: day * 24 + hour,
                                                      to: store.snapshot.start)!,
                       dayNumber: day, city: city, note: "\(city) \(day)")
            }
            let run = [kept(-2, "", 9), kept(3, "Bangkok", 10), kept(4, "Bangkok", 9),
                       kept(9, "Chiang Mai", 12), kept(9, "", 18), kept(40, "Bangkok", 8)]
            let groups = Moment.groupedByStop(run.shuffled())
            check("moments group by consecutive place, newest first",
                  groups.map(\.heading) == ["Bangkok · day 40", "Day 9", "Chiang Mai · day 9",
                                            "Bangkok · days 3–4", "Before we left"],
                  "\(groups.map(\.heading))")
            check("and newest first inside a group",
                  groups.first { $0.heading == "Bangkok · days 3–4" }?.moments.map(\.dayNumber) == [4, 3])
            check("a group's id is borrowed, not minted",
                  Moment.groupedByStop(run).map(\.id) == Moment.groupedByStop(run.reversed()).map(\.id)
                      && Set(groups.map(\.id)).isSubset(of: Set(run.map(\.id))))

            // One formula for distance, used by the headline and by Next stop.
            let bkk = (13.7563, 100.5018), cnx = (18.7883, 98.9853)
            let km = Geo.kilometres(bkk.0, bkk.1, cnx.0, cnx.1)
            check("Bangkok to Chiang Mai is about 580 km", (560...600).contains(Int(km)), "\(Int(km))")
            let a = Stamp(code: "BKK", city: "Bangkok", index: 0, arrivalNote: "",
                          latitude: bkk.0, longitude: bkk.1)
            let b = Stamp(code: "CNX", city: "Chiang Mai", index: 1, arrivalNote: "",
                          latitude: cnx.0, longitude: cnx.1)
            check("and a stamp measures with the same one", a.kilometres(to: b) == km)
            if phone.nextStamp?.hasLocation == false {
                check("no distance to a waypoint nobody placed",
                      phone.kilometresToNextStop(fromLatitude: cnx.0, longitude: cnx.1) == nil)
            } else if let next = phone.nextStamp {
                check("the distance to the next stop is measured from here",
                      phone.kilometresToNextStop(fromLatitude: next.latitude, longitude: next.longitude) == 0)
            }

            // "You look close" — a suggestion the dialog still has to confirm.
            let near = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-moments-near"))
            if let next = near.nextStamp {
                check("no nudge toward a stop nobody placed",
                      next.hasLocation || near.nearNextStop(latitude: 18.79, longitude: 98.99) == nil)
                near.stamps = near.stamps.map { stamp in
                    guard stamp.id == next.id else { return stamp }
                    var placed = stamp
                    placed.latitude = 18.7883
                    placed.longitude = 98.9853
                    return placed
                }
                check("a fix inside the radius suggests the next stop",
                      near.nearNextStop(latitude: 18.80, longitude: 99.02)?.id == next.id)
                check("one outside it suggests nothing",
                      near.nearNextStop(latitude: 18.95, longitude: 99.20) == nil)
                _ = near.arrive(at: near.stamps.first { $0.id == next.id }!)
                check("an earned stop is never suggested again",
                      near.nearNextStop(latitude: 18.7883, longitude: 98.9853)?.id != next.id)
            }
            let nearHome = TripStore(storeKey: nil, snapshot: store.snapshot,
                                     ritual: SilentRitualScheduler(),
                                     library: TripLibrary(key: "dithoi.library.checks-moments-nearhome"))
            nearHome.participant = .writer
            nearHome.writeTo(.one)
            nearHome.stamps = nearHome.stamps.map { var s = $0; s.latitude = 18.7883; s.longitude = 98.9853; return s }
            check("the observer is never nudged",
                  nearHome.nearNextStop(latitude: 18.7883, longitude: 98.9853) == nil)
            early.stamps = early.stamps.map { var s = $0; s.latitude = 18.7883; s.longitude = 98.9853; return s }
            check("nor anybody before departure",
                  early.nearNextStop(latitude: 18.7883, longitude: 98.9853) == nil)

            // A moment kept on the stamp screen is filed under the stamp.
            let atStamp = phone.addMoment(note: "Here at last", city: "  Huế ")
            check("a moment can be filed under a stamp's city",
                  atStamp?.city == "Huế", atStamp?.city ?? "nil")
            check("but not before departure",
                  early.addMoment(note: "", city: "Huế")?.city == "")

            // "Just keep the spot": nothing written, no photograph — kept, and
            // left out of the book until it is finished.
            let book = TripStore(storeKey: nil, snapshot: store.snapshot,
                                 ritual: SilentRitualScheduler(),
                                 library: TripLibrary(key: "dithoi.library.checks-moments-book"))
            book.addMoment(note: "Written")
            let spot = book.addMoment(note: "   ")
            check("a spot with nothing in it is unfinished",
                  spot?.isUnfinished == true && book.moments.count == 2)
            check("and doesn't print",
                  book.printedMoments.map(\.id) == book.moments.filter { !$0.isUnfinished }.map(\.id)
                      && book.printedMoments.count == 1)
            check("and the print screen says so",
                  book.printReadiness(photoPixels: { _ in nil }).unfinishedMoments
                      == (book.features.printedBooks ? 1 : 0))
            check("tonight's page is offered today's",
                  book.unfinishedToday.map(\.id) == [spot?.id].compactMap { $0 })
            if var finished = spot {
                finished.note = "The bus with the goat"
                book.updateMoment(finished)
                check("finishing it puts it in the book",
                      book.printedMoments.count == 2 && book.unfinishedMoments.isEmpty)
            }
            check("the line names one, or spells the count",
                  PrintReadiness(pageCount: 1, softPhotos: [], missingPhotos: 0, estimatedMegabytes: 1,
                                 unfinishedMoments: 1).unfinishedLine?.hasPrefix("One moment with nothing in it") == true
                      && PrintReadiness(pageCount: 1, softPhotos: [], missingPhotos: 0, estimatedMegabytes: 1,
                                        unfinishedMoments: 3).unfinishedLine?.hasPrefix("Three moments with nothing in them") == true
                      && PrintReadiness(pageCount: 1, softPhotos: [], missingPhotos: 0,
                                        estimatedMegabytes: 1).unfinishedLine == nil)

            // The replay: the trail, day by day, ending on the trail's own number.
            let played = TripStore(storeKey: nil, snapshot: store.snapshot,
                                   ritual: SilentRitualScheduler(),
                                   library: TripLibrary(key: "dithoi.library.checks-replay"))
            let replay = played.trailReplay
            let frames = replay.days.map { replay.frame(atDay: $0) }
            check("the replay starts with nothing earned",
                  replay.frame(atDay: replay.days.lowerBound).stamps.isEmpty
                      || replay.stamps.contains { played.dayNumber(for: $0.earnedOn ?? .distantPast) < 1 })
            check("and ends on the trail's own headline",
                  replay.last.kilometres == played.kilometresTravelled
                      && Set(replay.last.stamps.map(\.id)) == Set(played.earnedStamps.map(\.id)),
                  "\(replay.last.kilometres) vs \(played.kilometresTravelled)")
            check("and never goes backwards",
                  zip(frames, frames.dropFirst()).allSatisfy {
                      $0.stamps.count <= $1.stamps.count && $0.kilometres <= $1.kilometres
                          && $0.moments.count <= $1.moments.count
                  })
            let gate = Moment(capturedAt: Calendar.trip.date(byAdding: .day, value: -2, to: played.start)!,
                              dayNumber: -1, city: "", note: "Gate D7", latitude: 52.31, longitude: 4.77)
            let withGate = TrailReplay(stamps: [], moments: [gate], start: played.start, dayCount: 10)
            check("a moment before departure is day 0 of the replay",
                  withGate.days.lowerBound == 0 && withGate.frame(atDay: 0).moments.map(\.id) == [gate.id])
            check("a trail with no positions has nothing to replay",
                  TrailReplay(stamps: played.stamps.map { var s = $0; s.latitude = 0; s.longitude = 0; return s },
                              moments: [], start: played.start, dayCount: 10).isEmpty)

            // Tonight's page borrows a moment's photograph as a copy, never the file.
            let copies = PhotoStore(directoryName: "DuplicateCheck")
            copies.eraseAll()
            let copyBase = Storage.directory("DuplicateCheck")
            try? Data("jpeg".utf8).write(to: copyBase.appendingPathComponent("original.jpg"))
            try? Data("jpeg".utf8).write(to: copyBase.appendingPathComponent("original-thumb.jpg"))
            let copied = copies.duplicate("original")
            check("a borrowed photograph is a new file",
                  copied != nil && copied != "original" && copies.exists(copied ?? ""))
            copies.delete("original")
            check("and survives the original being deleted",
                  copies.exists(copied ?? "") && !copies.exists("original"))
            copies.eraseAll()

            let tonight = TripStore(storeKey: nil, snapshot: store.snapshot,
                                    ritual: SilentRitualScheduler(),
                                    library: TripLibrary(key: "dithoi.library.checks-tonight"))
            tonight.addMoment(note: "Written up")
            tonight.addMoment(note: "")
            tonight.restoreMoment(Moment(capturedAt: Calendar.trip.date(byAdding: .day, value: -1, to: tonight.now)!,
                                         dayNumber: 2, city: "Bangkok", note: "Yesterday"))
            check("tonight's page offers today's written-up moments only",
                  tonight.momentsToday.map(\.note) == ["Written up"])

            // A year ago today, from the shelf.
            let memoryDay = Calendar.trip.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 20))!
            func shelved(_ moments: [Moment], _ pages: [JournalEntry], role: Traveller = .one,
                         observer: Bool = false) -> ShelvedTrip {
                var snap = store.snapshot
                snap.tripID = UUID()
                snap.moments = moments
                snap.journal = pages
                snap.role = role
                snap.participant = observer ? .writer : .one
                return ShelvedTrip(summary: TripSummary(id: snap.tripID, name: "Last spring", start: snap.start,
                                                        dayCount: 14, countries: [], pageCount: 0,
                                                        nightsAway: 13, stampsEarned: 0, stampsTotal: 0,
                                                        spentHome: 0, homeCurrency: .eur, lettersDelivered: 0,
                                                        lettersSealed: 0, status: .archived, closedOn: nil,
                                                        printedOn: nil, lastSyncedAt: nil),
                                   snapshot: (try? JSONEncoder().encode(snap)) ?? Data())
            }
            func on(_ y: Int, _ m: Int, _ d: Int) -> Date {
                Calendar.trip.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
            }
            let lastYear = Moment(capturedAt: on(2026, 3, 14), dayNumber: 5, city: "Hội An", note: "Lanterns")
            let thisYear = Moment(capturedAt: on(2027, 3, 14), dayNumber: 5, city: "Hội An", note: "Too new")
            let blankSpot = Moment(capturedAt: on(2025, 3, 14), dayNumber: 5, city: "Huế", note: "")
            let mine = JournalEntry(dayNumber: 5, date: on(2025, 3, 14), city: "Huế", line: "Rain all day",
                                    tags: [], hasPhoto: false, photoID: nil, author: .one)
            let theirs = JournalEntry(dayNumber: 5, date: on(2025, 3, 14), city: "Huế", line: "Not mine",
                                      tags: [], hasPhoto: false, photoID: nil, author: .two)
            let shelf = [shelved([lastYear, thisYear, blankSpot], [mine, theirs])]
            let found = TripLibrary.memories(in: shelf, on: memoryDay)
            check("a year ago today finds last year's moment and my page",
                  found.map(\.words) == ["Lanterns", "Rain all day"], "\(found.map(\.words))")
            check("and says how long ago",
                  found.map(\.heading) == ["A year ago today", "Two years ago today"])
            check("never this year's, an empty spot, or the other traveller's page",
                  !found.contains { ["Too new", "", "Not mine"].contains($0.words) })
            check("a memory's id is the record's",
                  found.map(\.id) == [lastYear.id, mine.id]
                      && TripLibrary.memories(in: shelf, on: memoryDay).map(\.id) == found.map(\.id))
            check("an observer's shelf remembers nothing",
                  TripLibrary.memories(in: [shelved([lastYear], [], observer: true)], on: memoryDay).isEmpty)
            let leap = Moment(capturedAt: on(2024, 2, 29), dayNumber: 3, city: "Seoul", note: "Leap day")
            check("29 February is quiet on the 28th and the 1st",
                  TripLibrary.memories(in: [shelved([leap], [])], on: on(2025, 2, 28)).isEmpty
                      && TripLibrary.memories(in: [shelved([leap], [])], on: on(2025, 3, 1)).isEmpty
                      && TripLibrary.memories(in: [shelved([leap], [])], on: on(2028, 2, 29)).count == 1)
            check("an empty shelf has no memories", TripLibrary.memories(in: [], on: memoryDay).isEmpty)

            // Closed: the snapshot is frozen and names these photographs.
            blank.closeTrip()
            let countBefore = blank.moments.count
            check("a closed trip keeps no new moment",
                  blank.addMoment(note: "After the end") == nil && blank.moments.count == countBefore)
            if let first = blank.moments.first {
                blank.deleteMoment(first.id)
                check("and deletes none it already had", blank.moments.count == countBefore)
            }
            check("and restores none", !blank.restoreMoment(kept(2, "Lisbon", 0)))
            check("the observer restores none", !home.restoreMoment(kept(2, "Lisbon", 0)))
        }

        print("— the payload carries exactly what it is allowed to —")
        do {
            // The third structural promise, after the sealed letter's missing
            // read receipt and the widget's scalars-only snapshot. Until now
            // the journal's absence was asserted only behaviourally — one store
            // writes a page, the other syncs, the page isn't there. That check
            // is real, but it only fails once somebody has already shipped the
            // field and written a test that exercises it.
            //
            // This is the list, written down. Adding to the payload now means
            // editing this array, in the open, on purpose.
            // `letterKeys` was added deliberately, which is what this array is
            // for: it holds the travellers' **public** keys so the observer can
            // seal a drop to the phone it is addressed to. A public key is
            // public by construction, the private half never leaves the
            // Keychain, and without it the letters in a shared CloudKit zone are
            // readable by the other traveller and unconditionally by the zone's
            // owner. Nothing about any letter is here.
            let allowed = ["tripID", "settings", "names", "itinerary", "expenses", "stamps",
                           "meetingPoint", "meetingPlaces", "settlements", "dayPlans", "showCards",
                           "letterKeys"]
            let labels = Mirror(reflecting: SyncPayload.empty()).children.compactMap(\.label)
            check("the payload carries exactly what it is allowed to",
                  labels == allowed, "\(labels)")

            // And the screen that tells somebody what travels has to agree with
            // it. The old list was written down by hand in `SampleTrip` — six
            // sentences somebody typed, stored per trip, and *empty on every
            // trip made through onboarding*, so the screen promising the
            // journal stays private listed nothing at all. Derived now, and
            // pinned to the payload rather than to a copywriter.
            let travels = store.whatTravels
            check("the sharing screen has something to say on a real trip",
                  !travels.isEmpty)
            check("nothing claims to be shared that the payload doesn't carry",
                  travels.filter(\.isShared).allSatisfy { line in
                      !line.fields.isEmpty && line.fields.allSatisfy(labels.contains)
                  },
                  "\(travels.filter(\.isShared).flatMap(\.fields).filter { !labels.contains($0) })")
            check("and nothing kept private is on the payload after all",
                  travels.filter { !$0.isShared }.allSatisfy(\.fields.isEmpty),
                  "a private line naming a payload field is a promise the merge breaks")
            // The four that must never travel, named so a future field can't
            // quietly join them without this failing.
            for absent in ["journal", "letters", "moments", "documents"] {
                check("  \(absent) is not on the payload", !labels.contains(absent))
            }
        }

        print("— the book's map and its moments —")
        do {
            // The map is arithmetic so it can be swept. A point off the page is
            // invisible in a screenshot of one trip and certain in some other.
            func stamp(_ code: String, _ lat: Double, _ lon: Double, _ index: Int) -> Stamp {
                Stamp(code: code, city: code, index: index, earnedOn: Date(), arrivalNote: "",
                      latitude: lat, longitude: lon)
            }
            let shapes: [(String, [Stamp])] = [
                ("Thailand to Korea", [stamp("BKK", 13.75, 100.50, 1), stamp("CNX", 18.79, 98.98, 2),
                                       stamp("HUE", 16.46, 107.59, 3), stamp("SEL", 37.57, 126.98, 4)]),
                ("north to south", [stamp("OSL", 59.91, 10.75, 1), stamp("ROM", 41.90, 12.50, 2)]),
                ("across the antimeridian", [stamp("SUV", -18.14, 178.44, 1), stamp("APW", -13.83, -171.76, 2)]),
                ("two stamps in one spot and one elsewhere", [stamp("A", 10, 10, 1), stamp("B", 10, 10, 2),
                                                             stamp("C", 11, 12, 3)]),
                ("near the pole", [stamp("LYR", 78.22, 15.65, 1), stamp("NAL", 78.92, 11.93, 2)])
            ]
            for (name, stamps) in shapes {
                let map = BookMap.fit(stamps, padding: 0.1)
                let inside = map?.marks.allSatisfy {
                    (0.1 - 1e-9...0.9 + 1e-9).contains($0.point.x) && (0.1 - 1e-9...0.9 + 1e-9).contains($0.point.y)
                } ?? false
                check("the map keeps every place on the page: \(name)", inside,
                      "\(map?.marks.map { ($0.code, $0.point.x, $0.point.y) } ?? [])")
            }
            // Two points always fill the square, so the short way round needs a
            // third to show: drawn the long way, Tonga lands west of Fiji.
            if let pacific = BookMap.fit([stamp("SUV", -18.14, 178.44, 1), stamp("TBU", -21.14, -175.20, 2),
                                          stamp("APW", -13.83, -171.76, 3)]) {
                let x = pacific.marks.map(\.point.x)
                check("and Fiji, Tonga, Samoa run west to east, the short way", x[0] < x[1] && x[1] < x[2], "\(x)")
            }
            if let tall = BookMap.fit(shapes[1].1) {
                let dx = abs(tall.marks[0].point.x - tall.marks[1].point.x)
                let dy = abs(tall.marks[0].point.y - tall.marks[1].point.y)
                check("and keeps its shape: Oslo to Rome stays tall", dy > dx * 3 && tall.marks[0].point.y < tall.marks[1].point.y,
                      "dx \(dx) dy \(dy)")
            }
            // Names never print through each other, and a place visited twice
            // is named once.
            if let route = BookMap.fit(shapes[0].1 + [stamp("AYU", 14.35, 100.57, 5), stamp("BK2", 13.75, 100.50, 6)]) {
                let labels = route.labels(all: true)
                let boxes = labels.map { label -> (ClosedRange<Double>, ClosedRange<Double>) in
                    let x = label.onLeft ? (label.point.x - 0.32)...(label.point.x - 0.02)
                                         : (label.point.x + 0.02)...(label.point.x + 0.32)
                    return (x, (label.point.y - 0.025)...(label.point.y + 0.025))
                }
                let clear = zip(boxes.indices, boxes).allSatisfy { i, a in
                    boxes[(i + 1)...].allSatisfy { b in !(a.0.overlaps(b.0) && a.1.overlaps(b.1)) }
                }
                check("no two names on the map print over each other", clear, "\(labels.map(\.text))")
                check("and every name stays on the page",
                      boxes.allSatisfy { $0.0.lowerBound >= 0 && $0.0.upperBound <= 1 })
                check("and Bangkok out and home is one name",
                      labels.filter { $0.text == "BKK" || $0.text == "BK2" }.count == 1, "\(labels.map(\.text))")
            }
            // A gap wide enough to clear a moment's diamond still keeps every
            // name clear of every other and on the page.
            if let route = BookMap.fit(shapes[0].1 + [stamp("AYU", 14.35, 100.57, 5)]) {
                let gap = 0.06
                let labels = route.labels(all: true, gap: gap)
                let boxes = labels.map { label -> (ClosedRange<Double>, ClosedRange<Double>) in
                    let x = label.onLeft ? (label.point.x - gap - 0.3)...(label.point.x - gap)
                                         : (label.point.x + gap)...(label.point.x + gap + 0.3)
                    return (x, (label.point.y - 0.025)...(label.point.y + 0.025))
                }
                check("with a wider gap, names still never print over each other",
                      zip(boxes.indices, boxes).allSatisfy { i, a in
                          boxes[(i + 1)...].allSatisfy { b in !(a.0.overlaps(b.0) && a.1.overlaps(b.1)) }
                      } && boxes.allSatisfy { $0.0.lowerBound >= 0 && $0.0.upperBound <= 1 },
                      "\(labels.map(\.text))")
            }
            check("one place is a dot, not a trail",
                  BookMap.fit([stamp("A", 10, 10, 1), stamp("B", 10, 10, 2)]) == nil
                      && BookMap.fit([stamp("A", 10, 10, 1)]) == nil)
            check("an unearned or unplaced stamp is not drawn",
                  BookMap.fit([stamp("A", 10, 10, 1),
                               Stamp(code: "B", city: "B", index: 2, arrivalNote: "", latitude: 20, longitude: 20),
                               stamp("C", 0, 0, 3)]) == nil)

            // An opener frames its own country. Fitted to the whole trip,
            // Vietnam's opener was one green dot beside the jump to Seoul.
            let trip = [stamp("BKK", 13.75, 100.50, 1), stamp("CNX", 18.79, 98.98, 2),
                        stamp("HAN", 21.03, 105.85, 3), stamp("HUE", 16.46, 107.59, 4),
                        stamp("HOI", 15.88, 108.33, 5), stamp("SEL", 37.57, 126.98, 6)]
            let vietnam = Set(trip[2...4].map(\.id))
            if let opener = BookMap.fit(trip, highlighting: vietnam, framing: vietnam),
               let whole = BookMap.fit(trip, highlighting: vietnam) {
                let own = opener.marks.filter { vietnam.contains($0.id) }
                func extent(_ marks: [BookMap.Mark]) -> Double {
                    let xs = marks.map(\.point.x), ys = marks.map(\.point.y)
                    return max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
                }
                check("an opener's own stops stay inside the margins",
                      own.allSatisfy { (0.1 - 1e-9...0.9 + 1e-9).contains($0.point.x) && (0.1 - 1e-9...0.9 + 1e-9).contains($0.point.y) },
                      "\(own.map { ($0.code, $0.point.x, $0.point.y) })")
                check("and fill the map rather than sitting in a corner of it",
                      extent(own) >= 0.6,
                      "\(extent(own)) framed, \(extent(whole.marks.filter { vietnam.contains($0.id) })) unframed")
                check("while the rest of the route runs off the edge",
                      opener.marks.contains { $0.code == "SEL" && ($0.point.y < 0 || $0.point.x > 1) })
                check("and no name is printed for a place past the edge",
                      opener.labels(all: false).allSatisfy { label in vietnam.contains(label.id) }
                          && opener.labels(all: true).allSatisfy { (0...1).contains($0.point.x) && (0...1).contains($0.point.y) })
                check("the whole-trip map is unchanged by any of it",
                      BookMap.fit(trip) == BookMap.fit(trip, framing: []))
            }
            // A country with one stop is a dot in a city-sized frame, not an
            // infinite zoom: centred, with its neighbours off the page.
            let hue = Set([trip[3].id])
            if let one = BookMap.fit(trip, highlighting: hue, framing: hue),
               let dot = one.marks.first(where: { $0.code == "HUE" }) {
                check("a one-stop country is centred on its map",
                      near(dot.point.x, 0.5, 1e-9) && near(dot.point.y, 0.5, 1e-9), "\(dot.point)")
            } else {
                check("a one-stop country still has a map", false)
            }
            check("a frame naming nowhere drawn is no map",
                  BookMap.fit(trip, framing: [UUID()]) == nil)
            // Moments ride on the same projection, and move nothing.
            let onBangkok = Moment(capturedAt: Date(), dayNumber: 2, city: "Bangkok", note: "x",
                                   latitude: 13.75, longitude: 100.50)
            let farAway = Moment(capturedAt: Date(), dayNumber: 3, city: "Doha", note: "layover",
                                 latitude: 25.27, longitude: 51.52)
            if let plain = BookMap.fit(trip), let withMoments = BookMap.fit(trip, moments: [onBangkok, farAway]) {
                let bkk = withMoments.marks.first { $0.code == "BKK" }?.point
                let diamond = withMoments.moments.first { $0.id == onBangkok.id }?.point
                check("a moment where a stamp is lands on the stamp's point",
                      bkk.map { b in diamond.map { near(b.x, $0.x, 1e-9) && near(b.y, $0.y, 1e-9) } ?? false } ?? false)
                check("and a layover half a world away doesn't move the frame",
                      plain.marks == withMoments.marks)
                check("and no moment is ever named",
                      withMoments.labels(all: true).allSatisfy { label in withMoments.marks.contains { $0.id == label.id } })
            }
            check("a moment with no position isn't drawn",
                  BookMap.fit(trip, moments: [Moment(capturedAt: Date(), dayNumber: 1, city: "", note: "x")])?.moments.isEmpty == true)
            // The replay's first frame may be the only place yet.
            if let lone = BookMap.fit([trip[0]], allowsSinglePlace: true) {
                check("a replay of one place is a centred dot",
                      near(lone.marks[0].point.x, 0.5, 1e-9) && near(lone.marks[0].point.y, 0.5, 1e-9))
            } else {
                check("a replay of one place still draws", false)
            }
            check("while the book still refuses one place",
                  BookMap.fit([trip[0]]) == nil)

            // Framing across the antimeridian: Tonga and Samoa, with Fiji the
            // context to the west.
            let pacificTrip = [stamp("SUV", -18.14, 178.44, 1), stamp("TBU", -21.14, -175.20, 2),
                               stamp("APW", -13.83, -171.76, 3)]
            let polynesia = Set(pacificTrip[1...2].map(\.id))
            if let framed = BookMap.fit(pacificTrip, highlighting: polynesia, framing: polynesia) {
                let x = framed.marks.map(\.point.x)
                check("framing across the antimeridian keeps the short way round",
                      x[0] < x[1] && x[1] < x[2] && x[0] < 0.1, "\(x)")
            }

            // Moments are packed by what they hold. Walk every arrangement of
            // up to eight and make sure each lands once, in order, and that no
            // page holds more than it can.
            for count in 0...8 {
                for mask in 0..<(1 << count) {
                    let flags = (0..<count).map { mask & (1 << $0) != 0 }
                    let pages = BookPlan.momentPages(photoFlags: flags)
                    let flat = pages.flatMap { Array($0) }
                    guard flat == Array(0..<count),
                          pages.allSatisfy({ page in
                              page.reduce(0) { $0 + BookPlan.momentWeight(hasPhoto: flags[$1]) }
                                  <= BookPlan.momentPageCapacity && !page.isEmpty
                          })
                    else {
                        check("every moment lands on one page, in order, within the page", false, "\(flags)")
                        continue
                    }
                }
            }
            check("every moment lands on one page, in order, within the page", true)
            check("three in words to a page, two photographs, or one of each",
                  BookPlan.momentPages(photoFlags: [false, false, false]).count == 1
                      && BookPlan.momentPages(photoFlags: [true, true]).count == 1
                      && BookPlan.momentPages(photoFlags: [true, false]).count == 1
                      && BookPlan.momentPages(photoFlags: [true, true, true]).count == 2)
        }

        print("— a page with more on it —")
        do {
            let library = TripLibrary(key: "dithoi.library.checks-page-extras")
            library.erase()
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(), library: library)
            // Old pages carry neither key, and `JournalEntry` decodes the rest
            // with `decode`: a throw there re-seeds the trip.
            let plain = JournalEntry(dayNumber: 3, date: phone.now, city: "Bangkok", line: "Old page",
                                     tags: [], hasPhoto: false, author: phone.role)
            if let data = try? JSONEncoder().encode(plain),
               var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                object.removeValue(forKey: "extraPhotoIDs")
                object.removeValue(forKey: "note")
                let stripped = try? JSONSerialization.data(withJSONObject: object)
                let back = stripped.flatMap { try? JSONDecoder().decode(JournalEntry.self, from: $0) }
                check("a page saved before extras existed still opens",
                      back?.line == "Old page" && back?.extraPhotoIDs == [] && back?.note == "")
            }

            // The store holds the page's limits, not the composer.
            phone.save(entry: JournalEntry(dayNumber: 30, date: phone.now, city: "Hội An",
                                           line: String(repeating: "a", count: 200), tags: [],
                                           hasPhoto: true, photoID: nil, author: phone.role,
                                           extraPhotoIDs: ["x1", "x2", "x3"],
                                           note: "  " + String(repeating: "n", count: 400) + "  "))
            let saved = phone.myEntries.first { $0.dayNumber == 30 }
            check("a page with only extra photographs gets a main one",
                  saved?.photoID == "x1" && saved?.extraPhotoIDs == ["x2", "x3"] && saved?.hasPhoto == true,
                  "\(saved?.allPhotoIDs ?? [])")
            check("and the line and note are held to what the page has room for",
                  saved?.line.count == JournalEntry.lineLimit && saved?.note.count == JournalEntry.noteLimit
                      && saved?.note.first == "n")
            check("every photograph on a page is kept from the prune",
                  Set(["x1", "x2", "x3"]).isSubset(of: phone.referencedPhotoIDs))
            phone.save(entry: JournalEntry(dayNumber: 31, date: phone.now, city: "Hội An", line: "Five",
                                           tags: [], hasPhoto: true, photoID: "y0", author: phone.role,
                                           extraPhotoIDs: ["y1", "y2", "y3", "y4"]))
            check("and a page holds three at most",
                  phone.myEntries.first { $0.dayNumber == 31 }?.allPhotoIDs == ["y0", "y1", "y2"])

            // The shelf half: a closed trip's book prints from these.
            phone.closeTrip()
            phone.beginNextTrip()
            check("and still kept once the trip is on the shelf",
                  Set(["x2", "x3", "y2"]).isSubset(of: phone.referencedPhotoIDs))
            library.erase()

            for count in 0...4 {
                for note in [false, true] {
                    let layout = DaySpreadLayout(photoCount: count, hasNote: note)
                    let expected: DaySpreadLayout.Photos = count == 0 ? .quiet
                        : count == 1 ? .single : .contact(count: min(count, 3))
                    check("a page of \(count) photographs\(note ? " and a note" : "") has one layout",
                          layout.photos == expected && layout.hasNote == note)
                }
            }
            // A photograph a third of the page wide needs a third of the pixels.
            let small = PhotoMeasurement(id: UUID(), dayNumber: 4, pixels: 1_000,
                                         printedFraction: DaySpreadLayout.contactSmallFraction)
            let full = PhotoMeasurement(id: UUID(), dayNumber: 4, pixels: 1_000)
            check("a small photograph is measured at the size it prints",
                  !small.isSoft(on: BookSpec()) && full.isSoft(on: BookSpec()),
                  "\(small.dpi(on: BookSpec())) vs \(full.dpi(on: BookSpec())) dpi")

            let tagger = TripStore(storeKey: nil, snapshot: store.snapshot,
                                   ritual: SilentRitualScheduler(),
                                   library: TripLibrary(key: "dithoi.library.checks-tags"))
            tagger.addTag("  Monsoon ")
            tagger.addTag("monsoon")
            tagger.addTag("   ")
            check("a tag of their own is kept once, as typed but lower-case",
                  tagger.customTags == ["monsoon"], "\(tagger.customTags)")
        }

        print("— a country, finished —")
        do {
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-country-done"))
            if phone.legs.count >= 2, let first = phone.legs.first {
                let start = Calendar.trip.startOfDay(for: phone.now)
                func moveTo(_ day: Int) {
                    if let date = Calendar.trip.date(byAdding: .day, value: -(day - 1), to: start) { phone.setStart(date) }
                }
                phone.save(entry: JournalEntry(dayNumber: first.startDay, date: phone.now, city: "x",
                                               line: "A night", tags: [], hasPhoto: false, author: phone.role))
                moveTo(first.endDay - 1)
                check("a country still going is not finished", phone.countryJustFinished == nil)
                moveTo(first.endDay)
                let done = phone.countryJustFinished
                check("the day after it ends, it is", done?.leg.id == first.id && (done?.nights ?? 0) > 0,
                      "\(done?.leg.country ?? "nothing")")
                check("and it points at its own opener",
                      done.map { phone.bookPlan.spreads[$0.spread].id == "leg-\(first.id)" } == true)
                phone.markCountryDone(first.id)
                check("and once seen, never again", phone.countryJustFinished == nil)
                moveTo(first.endDay + 4)
                check("nor days later", phone.countryJustFinished == nil)
            }
        }

        print("— the cover, against Lulu's own templates —")
        do {
            // Read off the five templates in Tools/LuluTemplates/, downloaded
            // from Lulu's cover service for this product. If Lulu changes the
            // product, these are the numbers that move, and this is where it
            // shows.
            let templates: [(pages: Int, spine: Double, width: Double, height: Double)] = [
                (24, 0.25, 19, 10.25), (84, 0.25, 19, 10.25), (140, 0.5, 19.25, 10.25),
                (300, 0.938, 19.688, 10.25), (500, 1.375, 20.125, 10.25)
            ]
            for template in templates {
                let cover = CoverSpec(pages: template.pages)
                check("a \(template.pages)-page cover is the size Lulu's template is",
                      cover.map { near($0.spine, template.spine, 0.001) && near($0.totalWidth, template.width, 0.001)
                          && near($0.totalHeight, template.height, 0.001) } == true,
                      cover.map { "\($0.totalWidth) × \($0.totalHeight), spine \($0.spine)" } ?? "none")
            }
            check("the table's overlapping rows are settled by the templates",
                  CoverSpec.spineWidth(pages: 84) == 0.25 && CoverSpec.spineWidth(pages: 86) == 0.5
                      && CoverSpec.spineWidth(pages: 140) == 0.5 && CoverSpec.spineWidth(pages: 142) == 0.625)
            let widths = stride(from: 24, to: 800, by: 2).compactMap(CoverSpec.spineWidth)
            check("every page count Lulu binds has a spine, and a thicker book never has a thinner one",
                  widths.count == (800 - 24) / 2 && zip(widths, widths.dropFirst()).allSatisfy { $0 <= $1 })
            check("and nothing outside it, nor the 800 the table can't agree on",
                  CoverSpec(pages: 22) == nil && CoverSpec(pages: 800) == nil && CoverSpec(pages: 802) == nil)

            if let cover = CoverSpec(pages: 132) {
                check("back, spine and front sit edge to edge inside the wrap",
                      near(cover.back.maxX, cover.spineBox.x, 1e-9) && near(cover.spineBox.maxX, cover.front.x, 1e-9)
                          && near(cover.front.maxX + CoverSpec.wrap, cover.totalWidth, 1e-9))
                check("the barcode box sits inside the back's safe area, against the spine side",
                      cover.barcode.x >= cover.backSafe.x && near(cover.barcode.maxX, cover.backSafe.maxX, 1e-9)
                          && near(cover.barcode.maxY, cover.backSafe.maxY, 1e-9))
                check("and the back's artwork never reaches it",
                      cover.backArtwork.maxY < cover.barcode.y)
                check("a half-inch spine carries type, inset from both boards",
                      cover.spineTypeArea.map { $0.x > cover.spineBox.x && $0.maxX < cover.spineBox.maxX } == true)
            }
            check("a quarter-inch spine carries none", CoverSpec(pages: 60)?.spineTypeArea == nil)
            check("and the size reads the way the template prints it",
                  CoverSpec(pages: 140)?.sizeLabel == "19.25 × 10.25 in · spine 0.5 in",
                  CoverSpec(pages: 140)?.sizeLabel ?? "")
        }

        print("— the book is built once, and never stale —")
        do {
            let phone = TripStore(storeKey: nil, snapshot: store.snapshot,
                                  ritual: SilentRitualScheduler(),
                                  library: TripLibrary(key: "dithoi.library.checks-book-cache"))
            // Reading is free once it's built: Today, the composer and every
            // spread of the preview read the plan, many times a pass.
            _ = phone.bookPlan
            let before = phone.bookPlanBuilds
            for _ in 0..<50 { _ = phone.bookPlan; _ = phone.countryJustFinished }
            check("reading the book fifty times builds it no more",
                  phone.bookPlanBuilds == before, "\(phone.bookPlanBuilds - before) builds")
            let day = phone.dayNumber + 1
            _ = phone.bookPage(forDay: day)
            let afterPage = phone.bookPlanBuilds
            for _ in 0..<50 { _ = phone.bookPage(forDay: day) }
            check("and the composer's page number, asked on every keystroke, is built once",
                  phone.bookPlanBuilds == afterPage)

            // The other half: every edit the book is made of drops the cache.
            // A plan that outlived its inputs would print last week's book.
            func fresh(_ label: String) {
                check("the cached book matches a fresh one after \(label)",
                      phone.bookPlan == phone.freshBookPlan(),
                      "\(phone.bookPlan.dayCountInBook) nights cached vs \(phone.freshBookPlan().dayCountInBook) fresh")
            }
            phone.save(entry: JournalEntry(dayNumber: 2, date: phone.now, city: "Bangkok", line: "Added",
                                           tags: [], hasPhoto: false, author: phone.role))
            fresh("a page is written")
            let page = phone.bookPage(forDay: 2)
            check("and the page number moves with it",
                  page != nil && page == phone.bookPlan.firstPage(
                      ofSpread: BookSpread.day(entryID: phone.myEntries.first { $0.dayNumber == 2 }!.id).id))
            phone.deleteEntry(day: 2)
            fresh("a page is taken out")
            let moment = phone.addMoment(note: "Cached?")
            fresh("a moment is kept")
            if let moment {
                var edited = moment
                edited.note = "Edited"
                phone.updateMoment(edited)
                fresh("a moment is edited")
                phone.deleteMoment(moment.id)
                fresh("a moment is deleted")
            }
            if let segment = phone.itinerary.allSegments.first {
                phone.setNights(segment.nights + 3, forSegment: segment.id)
                fresh("a stop is lengthened")
            }
            if let index = phone.stamps.firstIndex(where: { !$0.earned }) {
                phone.stamps[index].earnedOn = phone.now
                fresh("a stamp is earned")
            }
            phone.features.volumes = 2
            fresh("the book is cut in two")
            phone.features.stamps.toggle()
            fresh("the stamps are switched")
            phone.role = phone.role.other
            fresh("the phone changes hands")
            phone.features.printedBooks = false
            check("and a book switched off is empty", phone.bookPlan == .empty)
        }

        print("— the day page holds whatever the store accepts —")
        do {
            // The book's serif, as `Font.system(design: .serif)` resolves it.
            func serif(_ size: CGFloat) -> CTFont {
                let base = NSFont.systemFont(ofSize: size)
                let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
                return (NSFont(descriptor: descriptor, size: size) ?? base) as CTFont
            }
            // SwiftUI rounds every font to whole points (`TypeScale.points`), so
            // the sizes are rounded here too, at each scale the page is drawn at.
            func paragraph(_ text: String, size: Double, spacing: Double, unit: Double) -> NSAttributedString {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = CGFloat(spacing * unit)
                style.lineBreakMode = .byWordWrapping
                return NSAttributedString(string: text, attributes: [
                    .font: serif(CGFloat((size * unit).rounded())),
                    .paragraphStyle: style
                ])
            }
            func height(_ text: NSAttributedString, width: Double) -> Double {
                let setter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
                let size = CTFramesetterSuggestFrameSizeWithConstraints(
                    setter, CFRange(location: 0, length: 0), nil,
                    CGSize(width: width, height: .greatestFiniteMagnitude), nil)
                return Double(size.height)
            }
            // How tall the page's text is at a scale, in the page's units.
            func textHeight(line: String, note: String, scale: Double, unit: Double) -> Double {
                let width = DayTextPage.width * unit
                if note.isEmpty {
                    return height(paragraph(line, size: DayTextPage.lineAlone * scale,
                                            spacing: DayTextPage.lineAloneSpacing * scale, unit: unit),
                                  width: width) / unit
                }
                let top = height(paragraph(line, size: DayTextPage.lineWithNote * scale,
                                           spacing: DayTextPage.lineWithNoteSpacing * scale, unit: unit), width: width)
                let bottom = height(paragraph(note, size: DayTextPage.note * scale,
                                              spacing: DayTextPage.noteSpacing * scale, unit: unit), width: width)
                return (top + bottom) / unit + DayTextPage.lineToNote * scale
            }

            // The worst the store lets onto a page: every limit reached, in the
            // widest letters, as one word no line can break, as words, and as
            // emoji — a grapheme each, so 120 of them is a legal line.
            let line = JournalEntry.lineLimit, note = JournalEntry.noteLimit
            let worst: [(String, String, String)] = [
                ("Ws", String(repeating: "W", count: line), String(repeating: "W", count: note)),
                ("one unbroken word", String(repeating: "m", count: line), String(repeating: "m", count: note)),
                ("wide words", String(String(repeating: "MWMW ", count: 30).prefix(line)),
                 String(String(repeating: "MWMW ", count: 60).prefix(note))),
                ("emoji", String(repeating: "🏝", count: line), String(repeating: "🏝", count: note))
            ]
            // Drawn at print size (an 8.5-inch page, 612 points) and at the
            // size the preview draws a page on a phone. Rounding to whole
            // points means a small page is not just a scaled big one.
            let units: [(String, Double)] = [("print", 612 / DayTextPage.side), ("phone", 190 / DayTextPage.side), ("small phone", 160 / DayTextPage.side)]
            let smallest = DayTextPage.scales.last ?? 1
            for (name, lineText, noteText) in worst {
                for (where_, unit) in units {
                    let alone = textHeight(line: lineText, note: "", scale: smallest, unit: unit)
                    check("the longest line in \(name) fits the page at its smallest size, \(where_)",
                          alone <= DayTextPage.textHeight(hasNote: false),
                          "\(Int(alone)) of \(Int(DayTextPage.textHeight(hasNote: false)))")
                    let both = textHeight(line: lineText, note: noteText, scale: smallest, unit: unit)
                    check("and with the longest note under it, \(where_)",
                          both <= DayTextPage.textHeight(hasNote: true),
                          "\(Int(both)) of \(Int(DayTextPage.textHeight(hasNote: true)))")
                    // A day with an occasion gives a line to it.
                    check("and both still fit under an occasion, \(where_)",
                          alone <= DayTextPage.textHeight(hasNote: false, hasOccasion: true)
                              && both <= DayTextPage.textHeight(hasNote: true, hasOccasion: true),
                          "\(Int(alone)) of \(Int(DayTextPage.textHeight(hasNote: false, hasOccasion: true))), \(Int(both)) of \(Int(DayTextPage.textHeight(hasNote: true, hasOccasion: true)))")
                }
            }
            // And an ordinary page is set at full size, not shrunk to be safe.
            let ordinary = textHeight(line: "Got lost twice, ate well three times.", note: "",
                                      scale: 1, unit: 612 / DayTextPage.side)
            check("an ordinary line is set at the full size",
                  ordinary <= DayTextPage.textHeight(hasNote: false), "\(Int(ordinary))")
            // Size follows length: a short line is set larger than a long one
            // that fits, and never the other way round.
            let caps = (1...JournalEntry.lineLimit).map {
                DayTextPage.maxScale(forLine: String(repeating: "a", count: $0), hasNote: false)
            }
            check("a line is never set larger for being longer",
                  zip(caps, caps.dropFirst()).allSatisfy { $0 >= $1 } && caps.first! > caps.last!,
                  "\(Set(caps).sorted())")
            check("and every size the ladder reaches is one the page tries",
                  [DayTextPage.maxScale(forLine: "x", hasNote: false),
                   DayTextPage.maxScale(forLine: "x", hasNote: true)].allSatisfy(DayTextPage.scales.contains))
            check("and the smallest size is still the one proven above",
                  DayTextPage.scales(forLine: String(repeating: "W", count: line), hasNote: false).last
                      == DayTextPage.scales.last)
            // An ordinary line at each step's limit fits at that step's size,
            // so a short line really is set large rather than falling back.
            let prose = String(repeating: "Rain all day and noodles by the river, then the night bus north. ", count: 3)
            let ordinaryNote = String(prose.prefix(100))
            for limit in [DayTextPage.shortLine, DayTextPage.mediumLine] {
                let text = String(prose.prefix(limit))
                let cap = DayTextPage.maxScale(forLine: text, hasNote: false)
                for (where_, unit) in units {
                    let height = textHeight(line: text, note: "", scale: cap, unit: unit)
                    check("a \(limit)-character line fits at \(cap)×, \(where_)",
                          height <= DayTextPage.textHeight(hasNote: false),
                          "\(Int(height)) of \(Int(DayTextPage.textHeight(hasNote: false)))")
                    check("and under an occasion, \(where_)",
                          height <= DayTextPage.textHeight(hasNote: false, hasOccasion: true),
                          "\(Int(height)) of \(Int(DayTextPage.textHeight(hasNote: false, hasOccasion: true)))")
                }
            }
            let shortWithNote = String(prose.prefix(DayTextPage.shortLineWithNote))
            let noteCap = DayTextPage.maxScale(forLine: shortWithNote, hasNote: true)
            for (where_, unit) in units {
                let height = textHeight(line: shortWithNote, note: ordinaryNote, scale: noteCap, unit: unit)
                check("and a short line over an ordinary note fits at \(noteCap)×, \(where_)",
                      height <= DayTextPage.textHeight(hasNote: true, hasOccasion: true),
                      "\(Int(height)) of \(Int(DayTextPage.textHeight(hasNote: true, hasOccasion: true)))")
            }
            // A short group of moments on an opener fits its band: two at the
            // note limit in words, or one beside its thumbnail.
            let opener = String(prose.prefix(OpenerMoments.noteLimit))
            for (where_, unit) in units {
                let words = height(paragraph(opener, size: OpenerMoments.note, spacing: OpenerMoments.noteSpacing,
                                             unit: unit), width: OpenerMoments.width * unit) / unit
                let two = (words + OpenerMoments.caption) * 2 + OpenerMoments.tileGap
                check("two moments at the limit fit an opener, \(where_)",
                      two <= OpenerMoments.band, "\(Int(two)) of \(Int(OpenerMoments.band))")
                let beside = height(paragraph(opener, size: OpenerMoments.note, spacing: OpenerMoments.noteSpacing,
                                              unit: unit),
                                    width: (OpenerMoments.width - OpenerMoments.thumb - OpenerMoments.thumbGap) * unit) / unit
                let photographed = max(OpenerMoments.thumb, beside + OpenerMoments.caption)
                check("and one beside its photograph, \(where_)",
                      photographed <= OpenerMoments.band, "\(Int(photographed)) of \(Int(OpenerMoments.band))")
            }
            check("the box and everything around it fill the page exactly",
                  DayTextPage.headingLine + DayTextPage.ruleAbovePlain + DayTextPage.mark + DayTextPage.ruleBelowPlain
                      + DayTextPage.textHeight(hasNote: false) + DayTextPage.footerGap + DayTextPage.footer
                      == DayTextPage.side - DayTextPage.margin * 2)
            check("and with an occasion line too",
                  DayTextPage.headingLine + DayTextPage.occasionLine + DayTextPage.ruleAboveWithNote + DayTextPage.mark
                      + DayTextPage.ruleBelowWithNote + DayTextPage.textHeight(hasNote: true, hasOccasion: true)
                      + DayTextPage.footerGap + DayTextPage.footer
                      == DayTextPage.side - DayTextPage.margin * 2)
            // The mark replaced a 1-unit rule and paid for its extra height
            // out of the gaps around it. The box the proofs above measure
            // against must be exactly the box it was.
            check("the trip mark took nothing from the text box",
                  DayTextPage.textHeight(hasNote: false) == 177
                      && DayTextPage.textHeight(hasNote: true) == 191
                      && DayTextPage.textHeight(hasNote: false, hasOccasion: true) == 162
                      && DayTextPage.textHeight(hasNote: true, hasOccasion: true) == 176,
                  "\(DayTextPage.textHeight(hasNote: false)), \(DayTextPage.textHeight(hasNote: true))")
        }

        print("— every spread lands in exactly one volume —")
        do {
            // `pagesPerVolume` used to be arithmetic over counters while the
            // export wrote one file whatever the count. Volumes are real
            // spreads now, so the check is the accounting identity over them:
            // every day of the book is in exactly one volume, in order, and
            // each volume is a book a printer will bind.
            func bodyIDs(_ spreads: [BookSpread]) -> [String] {
                spreads.compactMap { spread in
                    switch spread {
                    case .countryOpener, .day: return spread.id
                    default: return nil
                    }
                }
            }
            for volumes in [1, 2, 3] {
                for withStamps in [true, false] {
                    let plan = BookPlan.build(entries: store.myEntries, legs: store.legs,
                                              stamps: store.stamps, volumes: volumes,
                                              includeStamps: withStamps)
                    let counted = 3 + plan.contentsSpreadCount + plan.countryOpenerCount + plan.dayCountInBook
                        + plan.momentSpreadCount + plan.endmatterCount + plan.notesSpreadCount
                    check("every spread is one of the kinds the book counts",
                          counted == plan.spreads.count,
                          "\(volumes) vol, stamps \(withStamps): counted \(counted) of \(plan.spreads.count)")
                    check("the volumes hold the whole book, in order, once",
                          plan.volumeSpreads.flatMap(bodyIDs) == bodyIDs(plan.spreads),
                          "\(volumes) vol")
                    check("and each one opens and closes like a book, its contents included",
                          plan.volumeSpreads.allSatisfy {
                              Array($0.prefix(3)) == [.opening, .title, .contents(page: 0)] && $0.last == .closing
                          })
                    // Each file is numbered from its own page 1, so each prints
                    // its own contents: a section's first page has to be the
                    // spread it names, in that volume.
                    check("and each volume's contents point into that volume",
                          zip(plan.volumeSpreads, plan.volumeSections).allSatisfy { spreads, sections in
                              BookPlan.contentsRows(sections).allSatisfy { section in
                                  let index = section.firstPage / 2
                                  guard spreads.indices.contains(index) else { return false }
                                  switch spreads[index] {
                                  case .countryOpener(_, let country, _, _, _, _, _, _, _):
                                      return section.title.hasPrefix(country)
                                  case .stamps: return section.title == "The stamps"
                                  case .wholeTrip: return section.title == "The whole trip"
                                  // A volume can open partway through a country:
                                  // its first row is that country, continued.
                                  case .day(let id):
                                      guard let day = store.myEntries.first(where: { $0.id == id })?.dayNumber else { return false }
                                      let leg = store.legs.firstIndex { day >= $0.startDay && ($0.id == store.legs.last?.id || day < $0.endDay) }
                                      return leg.map { section.title.hasPrefix(store.legs[$0].country) } ?? section.title.hasPrefix("Elsewhere")
                                  case .moments: return section.title == "Before we left" || section.title.hasPrefix("Elsewhere")
                                  default: return false
                                  }
                              }
                          }, "\(volumes) vol")
                    // A volume that opens partway through a country says so,
                    // and no other section does.
                    check("a country a volume opens partway through is listed as continued, and only then",
                          zip(plan.volumeSpreads, plan.volumeSections).allSatisfy { spreads, sections in
                              BookPlan.contentsRows(sections).allSatisfy { section in
                                  let midCountry: Bool
                                  switch spreads[section.firstPage / 2] {
                                  case .day, .moments:
                                      midCountry = !section.title.hasPrefix("Elsewhere") && section.title != "Before we left"
                                  default:
                                      midCountry = false
                                  }
                                  return midCountry == section.title.hasSuffix(", continued")
                              }
                          }, "\(volumes) vol: \(plan.volumeSections.map { $0.map(\.title) })")
                    check("and their sections never overlap, and end where the content does",
                          zip(plan.volumeSpreads, plan.volumeSections).allSatisfy { spreads, sections in
                              let notes = spreads.filter { if case .notes = $0 { return true }; return false }.count
                              return zip(sections, sections.dropFirst()).allSatisfy { $0.lastPage < $1.firstPage }
                                  && sections.last?.lastPage == BookPlan.leftPage(ofSpreadAt: spreads.count - 1 - notes) - 1
                          })
                    check("and each one is bindable",
                          plan.pagesPerVolume.allSatisfy {
                              $0 >= plan.spec.minimumPages && $0.isMultiple(of: 2)
                          }, "\(plan.pagesPerVolume)")
                    check("and the back of the book is in the last volume alone",
                          plan.volumeSpreads.dropLast().allSatisfy { volume in
                              !volume.contains {
                                  switch $0 {
                                  case .stamps, .meetingPlaces, .wholeTrip: return true
                                  default: return false
                                  }
                              }
                          })
                    check("and no volume ends on a country with none of its days",
                          plan.volumeSpreads.allSatisfy { volume in
                              guard let last = bodyIDs(volume).last else { return true }
                              return !last.hasPrefix("leg-")
                          })
                }
            }
        }

        print("— a country entered twice —")
        do {
            // Thailand → Laos → Thailand. An ordinary route, and the one shape
            // that breaks anything keyed off "*the* leg for this country":
            // `spent(inCountry:)` found the first Thai leg and `perDayByCountry`
            // emitted a row per leg, so the money screen drew two Thailand rows
            // each showing every baht spent in Thailand, under two different day
            // counts — and the per-day comparison then found Thailand both
            // cheapest and dearest and suppressed itself.
            var snapshot = CheckTrip.snapshot()
            snapshot.itinerary = ItineraryDocument(legs: [
                Leg(country: "Thailand", currency: .thb, segments: [
                    Segment(title: "Bangkok", startDay: 1, endDay: 8)
                ]),
                Leg(country: "Laos", currency: .thb, segments: [
                    Segment(title: "Luang Prabang", startDay: 8, endDay: 15)
                ]),
                Leg(country: "Thailand", currency: .thb, segments: [
                    Segment(title: "Chiang Mai", startDay: 15, endDay: 22)
                ])
            ])
            snapshot.expenses = [
                Expense(date: snapshot.start, amount: 3_000, currency: .thb,
                        payer: .one, split: .evenly, note: "guesthouse", country: "Thailand"),
                Expense(date: Calendar.trip.date(byAdding: .day, value: 16, to: snapshot.start)!,
                        amount: 1_000, currency: .thb,
                        payer: .one, split: .evenly, note: "noodles", country: "Thailand")
            ]
            let twice = TripStore(storeKey: nil, snapshot: snapshot,
                                  clock: { Calendar.trip.date(byAdding: .day, value: 20, to: snapshot.start)! },
                                  ritual: SilentRitualScheduler())

            check("a country visited twice is one country",
                  twice.countries.map(\.name) == ["Thailand", "Laos"],
                  "\(twice.countries.map(\.name))")
            check("and keeps both its legs",
                  twice.legs(inCountry: "Thailand").count == 2,
                  "\(twice.legs(inCountry: "Thailand").count)")
            check("its money is counted once, not once per leg",
                  near(twice.spent(inCountry: "Thailand")?.local ?? 0, 4_000, 0.5),
                  "got \(twice.spent(inCountry: "Thailand")?.local ?? -1)")
            let thai = twice.perDayByCountry.filter { $0.country == "Thailand" }
            check("and it gets one per-day row, not two",
                  thai.count == 1, "\(twice.perDayByCountry.map(\.country))")
            check("over the days of both visits",
                  thai.first?.days == twice.daysSpent(inCountry: "Thailand"),
                  "\(thai.first?.days ?? -1) against \(twice.daysSpent(inCountry: "Thailand"))")
        }

        print("— a reset spares the shelf —")
        do {
            // `closeTrip()` freezes a snapshot and leaves the live journal
            // alone, and does not send the app back through onboarding — so
            // "Empty this trip" is still one tap away, naming exactly the files
            // the book that was just shelved is made of. `resetTrip` used to
            // delete every photo the journal and the moments pointed at.
            var snapshot = CheckTrip.snapshot()
            snapshot.journal = [JournalEntry(dayNumber: 3, date: snapshot.start, city: "Bangkok",
                                             line: "the one with the fan", tags: [],
                                             hasPhoto: true, photoID: "shelved-page", author: .one)]
            snapshot.moments = [Moment(capturedAt: snapshot.start, dayNumber: 3, city: "Bangkok",
                                       note: "the noodle stall", hasPhoto: true,
                                       photoID: "shelved-moment")]
            // Real files, in the folder `PhotoStore` reads. The bug is about
            // what is left on disk, so asserting on `referencedPhotoIDs` would
            // pass against the broken version — the shelf still *names* the
            // photographs it no longer has.
            let photos = Storage.directory("Photos")
            for id in ["shelved-page", "shelved-moment", "loose"] {
                try? Data("jpeg".utf8).write(to: photos.appendingPathComponent("\(id).jpg"))
            }

            let library = TripLibrary(key: "dithoi.checks.shelf")
            library.erase()
            // A store with a key, because `pruneOrphanedPhotos()` refuses to
            // delete anything on a keyless one — that store is the shelf's
            // reader and has no business tidying the app's container. Storage
            // is pointed at the scratch suite, so this writes nowhere real.
            let closing = TripStore(storeKey: "dithoi.checks.reset", snapshot: snapshot,
                                    ritual: SilentRitualScheduler(), library: library)
            closing.closeTrip()
            check("closing keeps the pages it archived",
                  closing.referencedPhotoIDs.isSuperset(of: ["shelved-page", "shelved-moment"]),
                  "\(closing.referencedPhotoIDs.sorted())")

            // Throwing a trip away is `beginNextTrip(discarding:)`; on a trip
            // that was already shelved it must still leave the shelf's files.
            closing.beginNextTrip(discarding: true)
            // The live trip is empty, so anything surviving below is surviving
            // because the shelf still points at it — which is the whole point.
            check("and emptying the trip afterwards leaves the files alone",
                  PhotoStore.shared.exists("shelved-page") && PhotoStore.shared.exists("shelved-moment"),
                  "\(PhotoStore.shared.storedIDs.sorted())")
            check("while still sweeping up what nothing points at",
                  !PhotoStore.shared.exists("loose"))
            check("and the trip itself really is empty",
                  closing.journal.isEmpty && closing.moments.isEmpty && !closing.hasOpened)
            library.erase()
            PhotoStore.shared.eraseAll()
            Storage.defaults.removeObject(forKey: "dithoi.checks.reset")
        }

        print("— an edit is all of it or none of it —")
        do {
            let store = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                  ritual: SilentRitualScheduler())
            guard let target = store.stamps.live.first(where: { !$0.earned }) else {
                check("a fixture with an unearned waypoint", false); return
            }
            let originalCode = target.code
            let draft = store.startLetter(title: "for the last stop",
                                          condition: .stamp(originalCode))
            // A good code and an empty city. It used to write the code and
            // re-key the drafts before the city's guard turned it down, then
            // return false without ever reaching `updatedAt` — so the change
            // was invisible to the merge and the other phone handed the old
            // code straight back, over a letter now pointing elsewhere.
            let accepted = store.updateWaypoint(target.id, code: "ZZZ", city: "   ")
            let after = store.stamps.first { $0.id == target.id }
            check("a refused edit is refused", accepted == false)
            check("and changes nothing",
                  after?.code == originalCode, "code is \(after?.code ?? "—")")
            check("and leaves the drafts keyed where they were",
                  store.letters.first { $0.id == draft.id }?.condition == .stamp(originalCode),
                  "\(store.letters.first { $0.id == draft.id }?.condition.summary ?? "—")")
            check("while a whole edit still lands",
                  store.updateWaypoint(target.id, code: "ZZZ", city: "Somewhere")
                      && store.stamps.first { $0.id == target.id }?.code == "ZZZ")
        }

        print("— derived ids are stable —")
        do {
            // A `BookSection` used to carry a stored UUID minted inside
            // `BookPlan.build`, which is derived and rebuilt on every read — so
            // the contents list had new identity every pass and nothing could
            // be compared against it. The same reason `Silence.id` is its span.
            let first = store.bookPlan
            let second = store.bookPlan
            check("two builds of one book agree on their sections",
                  first.sections.map(\.id) == second.sections.map(\.id),
                  "\(first.sections.map(\.id))")
            check("and the ids tell the sections apart",
                  Set(first.sections.map(\.id)).count == first.sections.count)
            check("and the spreads too",
                  first.spreads.map(\.id) == second.spreads.map(\.id))
        }

        print("— one way to split a stop's title —")
        do {
            // Nine places split on `" · "` and only one of them trimmed, so a
            // title typed with irregular spacing resolved in the app and not in
            // the book.
            let ragged = Segment(title: "Ayutthaya ·  Pai ", startDay: 1, endDay: 5)
            check("a raggedly-typed title still names two places",
                  ragged.places == ["Ayutthaya", "Pai"], "\(ragged.places)")
            check("and the first of them is the headline",
                  ragged.primaryPlace == "Ayutthaya", ragged.primaryPlace)
            check("and both are findable by name",
                  ragged.names(city: "Pai") && ragged.names(city: "Ayutthaya"))
            check("but a substring isn't a name",
                  !Segment(title: "Ha Long Bay", startDay: 1, endDay: 2).names(city: "Ha Long"))
            check("and a stop nobody named answers nothing",
                  Segment(title: "  ", startDay: 1, endDay: 2).places.isEmpty)

            // A second ragged stop with no waypoint on it, so the assertions
            // below can't be satisfied by a `Stamp.city` that happens to carry
            // the same string. Everything about "Railay" comes from the title.
            let alsoRagged = Segment(title: "Krabi ·  Railay ", startDay: 5, endDay: 9)
            var snapshot = CheckTrip.snapshot()
            snapshot.itinerary = ItineraryDocument(legs: [
                Leg(country: "Thailand", currency: .thb, segments: [ragged, alsoRagged])
            ])
            snapshot.stamps = [Stamp(code: "PAI", city: "Pai", index: 1,
                                     arrivalNote: "", segmentID: nil)]
            let store = TripStore(storeKey: nil, snapshot: snapshot,
                                  ritual: SilentRitualScheduler())
            // `segment(namingCity:)` only, not `segment(for:)`: the latter
            // prefers the stored id, and `backfillWaypointJoins()` will have
            // attached one — so it would answer correctly even with the name
            // match broken.
            check("the app finds a stop by a name in its title",
                  store.segment(namingCity: "Railay")?.id == alsoRagged.id)
            check("the letters know that place is still on the trip",
                  store.letterMoment.knownPlaces.contains("Railay"),
                  "\(store.letterMoment.knownPlaces.sorted())")
            // The book attributes a waypoint with no join by the names its
            // stops carry, which has to be the same list.
            let plan = BookPlan.build(
                entries: [JournalEntry(dayNumber: 2, date: snapshot.start, city: "Pai",
                                       line: "x", tags: [], hasPhoto: false, author: .one)],
                legs: store.legs,
                stamps: [Stamp(code: "PAI", city: "Pai", index: 1,
                               earnedOn: snapshot.start, arrivalNote: "")])
            let openers = plan.spreads.compactMap { spread -> Int? in
                if case .countryOpener(_, _, _, let stamps, _, _, _, _, _) = spread { return stamps }
                return nil
            }
            check("and so does the book", openers == [1], "\(openers)")
        }

        print("— a city can be visited twice; a code can't be —")
        do {
            // The code is the letter's address, so two stops can't share one.
            // The friction was never the rule — it was being refused *after*
            // typing the obvious answer — so a repeat visit is offered a code
            // derived from the first one's, and the note says whose it is.
            var snapshot = CheckTrip.snapshot()
            snapshot.itinerary = ItineraryDocument(legs: [
                Leg(country: "Thailand", currency: .thb, segments: [
                    Segment(title: "Bangkok", startDay: 1, endDay: 4),
                    Segment(title: "Chiang Mai", startDay: 4, endDay: 8),
                    // The way home. An ordinary route, and the whole point.
                    Segment(title: "Bangkok", startDay: 8, endDay: 11),
                    Segment(title: "Hội An", startDay: 11, endDay: 14),
                ])
            ])
            snapshot.stamps = []
            snapshot.letters = []
            let store = TripStore(storeKey: nil, snapshot: snapshot,
                                  ritual: SilentRitualScheduler())
            let stops = store.legs[0].segments

            check("a city nobody has stamped is offered its own letters",
                  store.suggestedCode(forCity: "Bangkok") == "BAN",
                  store.suggestedCode(forCity: "Bangkok"))
            store.addWaypoint(code: "BKK", city: "Bangkok", arrivalNote: "",
                              toSegment: stops[0].id)

            check("and the code it was actually given is taken",
                  !store.codeIsAvailable("BKK"))
            check("so the second Bangkok is offered the first one's code and a digit",
                  store.suggestedCode(forCity: "Bangkok") == "BKK2",
                  store.suggestedCode(forCity: "Bangkok"))
            check("which the app will accept", store.codeIsAvailable("BKK2"))

            // The note names the first visit, so `BKK2` isn't a label with no
            // story. It has to be found by city, not by code.
            check("and the first visit is findable by its city",
                  store.waypoint(forCity: "Bangkok")?.code == "BKK",
                  store.waypoint(forCity: "Bangkok")?.code ?? "—")
            check("however it was typed",
                  store.waypoint(forCity: "  bangkok ")?.code == "BKK")

            store.addWaypoint(code: "BKK2", city: "Bangkok", arrivalNote: "",
                              toSegment: stops[2].id)
            check("two visits to one city are two stamps",
                  store.orderedStamps.filter { $0.city == "Bangkok" }.count == 2)
            check("and a third would be offered the next digit",
                  store.suggestedCode(forCity: "Bangkok") == "BKK3",
                  store.suggestedCode(forCity: "Bangkok"))

            // The code prints inside a circle in a bound book, so it is letters
            // only — a city that isn't written in them still has to answer.
            check("a diacritic doesn't reach the code",
                  store.suggestedCode(forCity: "Hội An") == "HOI",
                  store.suggestedCode(forCity: "Hội An"))
            check("and a name too short to cut isn't guessed at",
                  store.suggestedCode(forCity: "Y").isEmpty)
            check("nor is a blank one", store.suggestedCode(forCity: "  ").isEmpty)
            check("every suggestion it makes is one it would accept",
                  ["Bangkok", "Chiang Mai", "Hội An", "Krabi"]
                      .map { store.suggestedCode(forCity: $0) }
                      .allSatisfy { $0.isEmpty || store.codeIsAvailable($0) })

            // A stop and its stamp are made in one sheet now, so the stop has
            // to come back from the store to hang the stamp off.
            let made = store.addSegment(title: "Pai", nights: 3, toLeg: store.legs[0].id)
            check("adding a stop hands it back", made != nil)
            check("and hands back the days it has after the reflow, not before",
                  made.map { store.legs[0].segments.contains($0) } == true)
            check("so a stamp can be hung off it in the same breath",
                  made.flatMap {
                      store.addWaypoint(code: "PAI", city: "Pai", arrivalNote: "",
                                        toSegment: $0.id)
                  } != nil)
        }

        print("— papers are not on the wire —")
        do {
            // The structural half of the promise, and the companion to the
            // moment check above. `TravelDocument.fields` holds passport
            // numbers; without `updatedAt` the type cannot conform to
            // `SyncableRecord`, so it cannot be `merged(with:)`, so nobody can
            // union it into a `SyncPayload` without first adding the field
            // here, in the open, on purpose. The pinned payload array further
            // down is the other end of the same rope.
            let fields = Mirror(reflecting: TravelDocument(title: "Passport"))
                .children.compactMap(\.label)
            check("a document has nothing to merge with",
                  !fields.contains("updatedAt") && !fields.contains("deletedAt"),
                  "\(fields)")

            // A dropped key must cost a field and never the trip. The
            // synthesized decode requires every key, and one missing key throws
            // out of `TripSnapshot`'s `decodeIfPresent([TravelDocument])`,
            // which `TripSnapshot.decode` swallows with `try?` — so the whole
            // trip reads as unreadable and the store starts a fresh one over
            // the top of it.
            let full = TravelDocument(title: "Passport", subtitle: "The photo page",
                                      badge: "PASSPORT", owner: .one,
                                      fields: [DocumentField(label: "Number", value: "NX4419 882")])
            let encoded = (try? JSONEncoder().encode(full)) ?? Data()
            let object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] ?? [:]
            check("it encodes something to strip", !object.isEmpty)
            let survives = object.keys.sorted().allSatisfy { key in
                var stripped = object
                stripped.removeValue(forKey: key)
                let short = (try? JSONSerialization.data(withJSONObject: stripped)) ?? Data()
                return (try? JSONDecoder().decode(TravelDocument.self, from: short)) != nil
            }
            check("and decodes with any one field missing", survives, "\(object.keys.sorted())")
        }

        print("— a closed trip carries no passport number —")
        do {
            let closing = TripStore(storeKey: "dithoi.trip.checks-papers",
                                    snapshot: CheckTrip.snapshot(),
                                    ritual: SilentRitualScheduler(),
                                    library: TripLibrary(key: "dithoi.library.checks-papers"))
            let before = closing.documents
            check("the trip arrives carrying numbers",
                  before.contains { $0.holdsAnything }, "\(before.count) documents")
            let labelsBefore = before.flatMap { $0.fields.map(\.label) }

            // Asked of the store, so the dialog and the deletion cannot
            // disagree — the `adoptionDiscardsLetters(becoming:)` shape.
            let loss = closing.papersLostOnClose
            check("and says what closing will cost before it does it",
                  loss?.documents == before.filter(\.holdsAnything).count,
                  "\(String(describing: loss))")

            closing.closeTrip()

            check("closing clears every value",
                  closing.documents.allSatisfy { !$0.holdsAnything },
                  "\(closing.documents.filter(\.holdsAnything).map(\.title))")
            // The rows and their labels survive, which is what lets the screen
            // say it was emptied rather than the document vanishing and the
            // shelf's "every screen reopens" promise failing in silence.
            check("and keeps the rows",
                  closing.documents.count == before.count, "\(closing.documents.count)")
            check("and the labels on them",
                  closing.documents.flatMap { $0.fields.map(\.label) } == labelsBefore)

            // The shelved copy is the one that matters: it is what a reopened
            // trip is decoded from, and it is what stays on the phone for good.
            let shelved = closing.library.shelf.compactMap { TripSnapshot.decode($0.snapshot) }
            check("and the copy on the shelf carries none either",
                  shelved.allSatisfy { $0.documents.allSatisfy { !$0.holdsAnything } },
                  "\(shelved.count) shelved")
            check("with nothing left to lose by closing again",
                  closing.papersLostOnClose == nil,
                  "\(String(describing: closing.papersLostOnClose))")

            // The dialog that reports all of the above puts the trip's name in
            // a sentence, and a blank trip has none — which drew "Close ?", a
            // bare question mark where the name goes. The same shape as the
            // meeting point's ". Agreed at 00:53.", and only a screenshot
            // showed it.
            closing.tripName = ""
            check("a trip with no name still reads as one",
                  closing.displayName == "this trip", closing.displayName)
            closing.tripName = "  "
            check("and whitespace is not a name either",
                  closing.displayName == "this trip", closing.displayName)
            closing.tripName = "Thailand"
            check("and one that has a name keeps it",
                  closing.displayName == "Thailand", closing.displayName)

            // The same question asked of a trip nothing has open. `displayName`
            // lives on the store, and the shelf's archived rows never reach one
            // — they read a frozen `TripSummary`. So the spine of a trip that
            // was never named drew " · 2026", with the accessibility label
            // reading ", 2026, archived" underneath it.
            var frozen = closing.summary
            check("a summary of a named trip says its name",
                  frozen.displayName == "Thailand", frozen.displayName)
            check("and its spine carries the year",
                  frozen.spine == "Thailand · \(frozen.year)", frozen.spine)
            frozen.name = ""
            check("a summary of an unnamed one reads as one",
                  frozen.displayName == "this trip", frozen.displayName)
            check("and its spine never starts with the separator",
                  frozen.spine == "this trip · \(frozen.year)", frozen.spine)
            frozen.name = "  "
            check("whitespace is not a name here either",
                  frozen.displayName == "this trip", frozen.displayName)

            Storage.forget("dithoi.trip.checks-papers")
            Storage.forget("dithoi.library.checks-papers")
        }

        print("— a scan nothing names is not kept —")
        do {
            // Its own folder inside the scratch container and its own Keychain
            // account, so this never touches the app's real scans or the key
            // they are sealed with. Same shape as the vault's key checks above.
            let crypto = DocumentCrypto(service: "com.lovedones.dithoi.checks",
                                        account: "scans-\(UUID().uuidString)")
            defer { crypto.discardKey() }
            let vault = ScanVault(directoryName: "checks-scans-\(UUID().uuidString)",
                                  crypto: crypto)
            defer { vault.eraseAll() }

            let kept = UUID()
            let dropped = UUID()
            for index in 0..<3 {
                _ = try? vault.write(Data("kept \(index)".utf8), for: kept, at: index)
            }
            for index in 0..<2 {
                _ = try? vault.write(Data("dropped \(index)".utf8), for: dropped, at: index)
            }
            check("pages land under the document they belong to",
                  vault.pageCount(for: kept) == 3 && vault.pageCount(for: dropped) == 2,
                  "\(vault.pageCount(for: kept)) / \(vault.pageCount(for: dropped))")
            check("and open again",
                  {
                      guard case .data(let bytes) = vault.decrypted(vault.pageIDs(for: kept)[1])
                      else { return false }
                      return bytes == Data("kept 1".utf8)
                  }())

            let removed = vault.prune(keeping: [kept])
            check("a prune takes the document nothing names", removed == 2, "got \(removed)")
            check("and leaves the one it does", vault.pageCount(for: kept) == 3,
                  "\(vault.pageCount(for: kept))")
            check("a page that is gone reads as missing, not as unopenable",
                  {
                      if case .missing = vault.decrypted("\(dropped.uuidString)-000") { return true }
                      return false
                  }())

            // The guard that stops the shelf's reader store — which holds a
            // *different* trip's document ids — taking the live trip's scans
            // with it on the way past.
            let reader = TripStore(storeKey: nil, snapshot: CheckTrip.snapshot(),
                                   ritual: SilentRitualScheduler(),
                                   library: TripLibrary(key: "dithoi.library.checks-reader"))
            check("a store that cannot write prunes nothing",
                  reader.pruneOrphanedScans() == 0)

            // Deleting a document takes its pages with it. `deleteAll(for:)`
            // had no callers at all before there was a way to delete a row, so
            // every scan ever written stayed on the phone.
            let deleted = vault.deleteAll(for: kept)
            check("deleting a document takes its scans", deleted == 3, "got \(deleted)")
            check("and the folder is empty after it",
                  vault.pageCount(for: kept) == 0 && vault.pageCount(for: dropped) == 0)

            Storage.forget("dithoi.library.checks-reader")
        }

        print("— pages come back in the order they went in —")
        do {
            let crypto = DocumentCrypto(service: "com.lovedones.dithoi.checks",
                                        account: "order-\(UUID().uuidString)")
            defer { crypto.discardKey() }
            let vault = ScanVault(directoryName: "checks-order-\(UUID().uuidString)",
                                  crypto: crypto)
            defer { vault.eraseAll() }

            func read(_ document: UUID) -> [String] {
                vault.pageIDs(for: document).map { pageID in
                    guard case .data(let bytes) = vault.decrypted(pageID) else { return "?" }
                    return String(decoding: bytes, as: UTF8.self)
                }
            }

            let document = UUID()
            var wrote = true
            for index in 0..<12 {
                wrote = wrote && (try? vault.write(Data("page \(index)".utf8), for: document,
                                                   at: vault.nextIndex(for: document))) != nil
            }
            check("twelve pages write", wrote)
            check("and come back in order", read(document) == (0..<12).map { "page \($0)" },
                  "\(read(document))")

            // `nextIndex` is one past the highest, not the count. They agree
            // until something is removed from the middle, and then a count
            // collides with a name that already exists and overwrites it.
            check("and the next index is one past the last", vault.nextIndex(for: document) == 12,
                  "\(vault.nextIndex(for: document))")

            // The sort is on the parsed index, not on the filename, and this is
            // the case that tells the two apart. Inside the zero padding they
            // agree — "008" really does sort before "011" — so a check that
            // stopped at twelve pages would pass over a lexicographic sort and
            // prove nothing. Past it they diverge: "1000" sorts *before* "999",
            // because '1' < '9'.
            let deep = UUID()
            for index in [998, 999, 1000, 1001] {
                _ = try? vault.write(Data("page \(index)".utf8), for: deep, at: index)
            }
            check("and past the width of the padding, where a name-sort disagrees",
                  read(deep) == [998, 999, 1000, 1001].map { "page \($0)" }, "\(read(deep))")
            check("with the next index still one past the last",
                  vault.nextIndex(for: deep) == 1002, "\(vault.nextIndex(for: deep))")
        }

        print("— a count and the noun it governs —")
        do {
            // The bug: the number is a *word*, so nothing in the sentence makes
            // the noun agree with it, and both callers wrote the plural in.
            check("one is singular", Formatting.spelledCount(1, "day") == "One day",
                  Formatting.spelledCount(1, "day"))
            check("and everything else is not",
                  Formatting.spelledCount(2, "day") == "Two days",
                  Formatting.spelledCount(2, "day"))
            check("including nought", Formatting.spelledCount(0, "day") == "Zero days",
                  Formatting.spelledCount(0, "day"))
            check("hyphenated numbers keep their hyphen",
                  Formatting.spelledCount(61, "day") == "Sixty-one days",
                  Formatting.spelledCount(61, "day"))

            // The other half of the sentence the two copies disagreed about.
            check("a hundred still spells out",
                  !Formatting.spelledCount(100, "day").contains("100"),
                  Formatting.spelledCount(100, "day"))
            check("past it a numeral is kinder than a 38pt headline",
                  Formatting.spelledCount(101, "day") == "101 days",
                  Formatting.spelledCount(101, "day"))
            check("and the longest trip the store allows doesn't spell itself out",
                  Formatting.spelledCount(3_650, "day") == "3650 days",
                  Formatting.spelledCount(3_650, "day"))
            check("the numeral branch pluralises too",
                  Formatting.spelledCount(1, "day", spellingUpTo: 0) == "1 day",
                  Formatting.spelledCount(1, "day", spellingUpTo: 0))

            check("an irregular plural can be given",
                  Formatting.spelledCount(2, "penny", plural: "pence") == "Two pence",
                  Formatting.spelledCount(2, "penny", plural: "pence"))
            check("and is not used for one",
                  Formatting.spelledCount(1, "penny", plural: "pence") == "One penny",
                  Formatting.spelledCount(1, "penny", plural: "pence"))

            // Both headlines, end to end. `dayNumber` clamps to 1...dayCount
            // and `dayCount` to 1...3650, so one is the reachable degenerate
            // case on both screens and neither can be nought.
            check("the book's headline reads on day one",
                  "\(Formatting.spelledCount(1, "day")) in" == "One day in",
                  "\(Formatting.spelledCount(1, "day")) in")
            check("and on a twelfth",
                  "\(Formatting.spelledCount(12, "day")) in" == "Twelve days in",
                  "\(Formatting.spelledCount(12, "day")) in")
            check("the itinerary's headline reads on a one-day trip",
                  Formatting.spelledCount(1, "day") == "One day")
            check("and on a sixty-one-day one",
                  Formatting.spelledCount(61, "day") == "Sixty-one days")

            // Against the live store rather than a literal, so the claim is
            // that the noun agrees with whatever day the narrative has left it
            // on — asserting a particular day here reads as a check of this
            // helper and is really a check of every mutation above it.
            let day = store.dayNumber
            check("the live store's book headline agrees with its own day number",
                  "\(Formatting.spelledCount(day, "day")) in"
                  .hasSuffix(day == 1 ? "day in" : "days in"),
                  "day \(day): \(Formatting.spelledCount(day, "day")) in")
            let span = store.dayCount
            check("and the itinerary's agrees with its own day count",
                  Formatting.spelledCount(span, "day")
                  .hasSuffix(span == 1 ? "day" : "days"),
                  "\(span): \(Formatting.spelledCount(span, "day"))")
        }

        print("— the square the book gets —")
        do {
            // Landscape, the shape a phone is usually held in, and the one the
            // square page has to take a bite out of.
            let wide = PhotoCrop(sourceWidth: 4032, sourceHeight: 3024)
            check("zoom 1 takes the whole short edge", wide.side == 3024, "\(wide.side)")
            check("centred, so an uncropped landscape loses the same off each end",
                  wide.originX == 504 && wide.originY == 0,
                  "\(wide.originX), \(wide.originY)")
            check("and cannot pan up or down until it is zoomed", wide.maxOffsetY == 0)
            check("but can pan sideways", wide.maxOffsetX == 504, "\(wide.maxOffsetX)")

            // Portrait mirrors it. Written out rather than asserted by symmetry:
            // the axes are separate code and only one of them was ever wrong.
            let tall = PhotoCrop(sourceWidth: 3024, sourceHeight: 4032)
            check("portrait mirrors it", tall.side == 3024 && tall.originY == 504 && tall.originX == 0,
                  "\(tall.side) at \(tall.originX), \(tall.originY)")
            check("and pans up and down instead", tall.maxOffsetY == 504 && tall.maxOffsetX == 0)

            // The whole reason this is arithmetic in Model/ rather than gesture
            // handling in a view: a square that walks off the edge of the source
            // is invisible in a screenshot of a photograph big enough to hide it.
            let shovedRight = PhotoCrop(sourceWidth: 4032, sourceHeight: 3024,
                                        offsetX: 99_999).clamped()
            check("panning to the right extreme stops on the edge",
                  shovedRight.originX + shovedRight.side == 4032,
                  "\(shovedRight.originX + shovedRight.side)")
            let shovedLeft = PhotoCrop(sourceWidth: 4032, sourceHeight: 3024,
                                       offsetX: -99_999).clamped()
            check("and the left extreme stops on nought", shovedLeft.originX == 0,
                  "\(shovedLeft.originX)")

            check("zoom clamps up from below one",
                  PhotoCrop(sourceWidth: 4032, sourceHeight: 3024, zoom: 0.2).clamped().zoom == 1)
            check("and down from above the ceiling",
                  PhotoCrop(sourceWidth: 4032, sourceHeight: 3024, zoom: 40).clamped().zoom
                  == PhotoCrop.maxZoom)
            check("a NaN can't get in either",
                  PhotoCrop(sourceWidth: 4032, sourceHeight: 3024,
                            zoom: .nan, offsetX: .nan).clamped().isInsideSource)

            // A sweep, because the clamping is two limits derived from a third
            // number and the failure is one combination rather than one axis.
            var escaped: [String] = []
            for width in [4032.0, 3024.0, 1000.0, 1.0] {
                for height in [3024.0, 4032.0, 1000.0, 1.0] {
                    for zoom in [0.5, 1, 1.7, 3, 4, 9] as [Double] {
                        for offset in [-5000.0, -700, 0, 700, 5000] {
                            let crop = PhotoCrop(sourceWidth: width, sourceHeight: height,
                                                 zoom: zoom, offsetX: offset, offsetY: -offset)
                                .clamped()
                            if !crop.isInsideSource {
                                escaped.append("\(width)x\(height) z\(zoom) o\(offset)")
                            }
                        }
                    }
                }
            }
            check("and the square is inside the photograph at every zoom and offset",
                  escaped.isEmpty, "\(escaped.prefix(3))")

            // Zoom is pinned before the offsets, because the offset limits are
            // derived from `side` and `side` is derived from zoom. The other
            // order clamps against a zoom level about to be thrown away.
            let zoomedAndShoved = PhotoCrop(sourceWidth: 4032, sourceHeight: 3024,
                                            zoom: 2, offsetY: 9_999).clamped()
            check("zooming in opens the axis that had no room",
                  zoomedAndShoved.originY + zoomedAndShoved.side == 3024,
                  "\(zoomedAndShoved.originY + zoomedAndShoved.side)")

            let square = PhotoCrop(sourceWidth: 2475, sourceHeight: 2475)
            check("a source already square is untouched", square.isUntouched)
            check("and a landscape one is not",
                  !PhotoCrop(sourceWidth: 4032, sourceHeight: 3024).isUntouched)

            // The crop screen's warning and the print screen's warning are the
            // same arithmetic on `BookSpec`, so they cannot disagree about the
            // same square — which is what "a sentence with a number in it has to
            // compute the number" means one screen earlier than usual.
            let spec = BookSpec()
            check("a full-height crop of a phone photograph prints clean",
                  !wide.isSoft(on: spec), "\(spec.printedDPI(forSquare: wide.pixelSide()))")
            let tight = PhotoCrop(sourceWidth: 4032, sourceHeight: 3024,
                                  zoom: PhotoCrop.maxZoom).clamped()
            check("and cropped to the ceiling it prints soft",
                  tight.isSoft(on: spec), "\(spec.printedDPI(forSquare: tight.pixelSide()))")
            check("the two ways of asking agree",
                  PhotoMeasurement(id: UUID(), dayNumber: 1, pixels: tight.pixelSide())
                      .isSoft(on: spec) == tight.isSoft(on: spec))
            check("and the scale is not assumed to be one",
                  PhotoCrop(sourceWidth: 620, sourceHeight: 620).pixelSide(scale: 4) == 2480,
                  "\(PhotoCrop(sourceWidth: 620, sourceHeight: 620).pixelSide(scale: 4))")
        }

        print("— the print check measures the edge the page stretches —")
        do {
            // The page is square and fills, so a photograph is cropped to its
            // *short* edge and that is what is scaled to 8.25 inches. Measuring
            // the long one said a 2475 x 1856 landscape was clean at 300 dpi
            // while it printed at about 225 — a warning that answered about an
            // axis the book throws away.
            let spec = BookSpec()
            check("the long edge of a landscape page calls it clean",
                  !spec.isSoft(square: 2475))
            check("while the edge that is actually stretched is soft",
                  spec.isSoft(square: 1856), "\(spec.printedDPI(forSquare: 1856)) dpi")

            // Through the readiness the print screen actually reads. The
            // fixture's pages carry no photo ids — nothing here can write a
            // JPEG — so the measurements are handed in directly rather than
            // pulled off entries that have none.
            let landscape = PhotoMeasurement(id: UUID(), dayNumber: 22, pixels: 1856)
            let squared = PhotoMeasurement(id: UUID(), dayNumber: 22, pixels: 2475)
            let soft = PrintReadiness.measure(plan: store.bookPlan, photos: [landscape],
                                              entriesWithoutPhoto: 0)
            let clean = PrintReadiness.measure(plan: store.bookPlan, photos: [squared],
                                               entriesWithoutPhoto: 0)
            check("so readiness flags the page a long-edge measurement passed",
                  !soft.isClean && clean.isClean,
                  "soft \(soft.softPhotos), clean \(clean.softPhotos)")

            // And the store's own path still runs, with the closure it is given
            // being the only source of pixels.
            check("readiness asks the caller for every photograph it measures",
                  store.printReadiness { _ in nil }.missingPhotos > 0,
                  "\(store.printReadiness { _ in nil }.missingPhotos)")
        }

        print("— a reset names the keys the app uses —")
        do {
            // Four string literals were written out again in `DebugScreen`,
            // while every one of them already had a constant. Bump
            // `TripStore.storeKey` and the reset goes on clearing the old one —
            // and every screenshot after it carries the previous run's trip.
            let cleared = Storage.appKeys
            check("the reset clears the trip", cleared.contains(TripStore.storeKey))
            check("the rates", cleared.contains(RatesService.storeKey))
            check("the sync stamp", cleared.contains(SyncCoordinator.stampKey))
            check("and the shelf", cleared.contains(TripLibrary.defaultKey))
            check("and the plan", cleared.contains(TripLibrary.planKey))
            check("and names each of them once",
                  Set(cleared).count == cleared.count, "\(cleared)")
        }

        // Before `exit`, not in a `defer` — `exit` doesn't unwind, so a defer
        // here would never run and the scratch would quietly become permanent.
        Storage.discardScratch()

        print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
