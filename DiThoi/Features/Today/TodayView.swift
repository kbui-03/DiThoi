import SwiftUI

/// B1 · Today, and G1 · the other traveller's today — the same screen, with the
/// letters absent and the ledger read from the other side.
struct TodayView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var readingLetter: Letter?
    @State private var writingEntry = false
    @State private var pickingMeetingPoint = false
    @State private var addingExpense = false
    @State private var going: Destination?
    @Environment(\.arrivalRequest) private var arrivalRequest
    /// Nudges waved away, by stamp. Not persisted: a relaunch in the same
    /// street may ask once more, which is a smaller cost than a stamp nobody
    /// was reminded of.
    @State private var notNow: Set<UUID> = []
    @State private var remembering: MemoryOpening?
    @State private var finishing = false

    private var plan: DayPlan? { store.todayPlan }

    /// Whether this phone may put a line in the ledger.
    ///
    /// `isReadOnly` is the courtesy and `isLive` is the state — the pairing the
    /// papers use. The ledger is genuinely two-way and carries no
    /// `guard !isObserver` in the store, and this screen isn't drawn in home
    /// mode or by the shelf, so this is defence rather than a branch anything
    /// reaches today — the same standing `ItineraryView`'s guard has.
    private var canAdd: Bool { !isReadOnly && store.isLive }

    /// Where this screen can push to.
    ///
    /// One destination rather than two `navigationDestination(isPresented:)`
    /// modifiers on the same view: stacked, the later one can swallow the
    /// earlier and the push silently does nothing.
    private enum Destination: Hashable { case itinerary, today, letters, book(spread: Int) }

    var body: some View {
        NavigationStack {
            Screen(context: .syncState) {
                if case .before(let daysUntil) = store.phase {
                    notYet(daysUntil: daysUntil)
                } else {
                    inProgress
                }
            }
            .navigationDestination(item: $going) { destination in
                switch destination {
                case .itinerary:
                    ItineraryView()
                case .today:
                    // No stop covering today — a trip with nowhere in it, or a
                    // day in a gap nobody planned. There is no day to show, so
                    // the list is the honest answer.
                    if let segment = store.todaySegment {
                        DayDetailView(day: store.dayNumber, segment: segment)
                    } else {
                        ItineraryView()
                    }
                case .letters:
                    LettersView()
                case .book(let spread):
                    BookPreviewView(startAt: spread)
                }
            }
            .sheet(item: $readingLetter) { letter in
                LetterReaderView(letter: letter)
            }
            .sheet(isPresented: $writingEntry) {
                TonightEntryView()
            }
            .sheet(isPresented: $pickingMeetingPoint) {
                MeetingPointPicker()
            }
            // The same sheet the Money tab opens, and it needs nothing from
            // here: `AddExpenseView` dates a new line to `store.now` and picks
            // up the local currency and who is holding the phone on appear.
            // One way to record money, reached from two places.
            .sheet(isPresented: $addingExpense) {
                AddExpenseView()
            }
            .sheet(item: $remembering) { opening in
                MemoryBookView(opening: opening)
            }
            .sheet(isPresented: $finishing) {
                FinishTripView()
            }
            // Never a prompt: only a phone that already said yes is asked.
            .task { if canAdd, !store.isObserver { store.location.requestOnceIfAllowed() } }
        }
    }

    // MARK: - Before they've left

    /// Everything is packed but the trip hasn't started. Counting down is the
    /// only honest thing this screen can do.
    @ViewBuilder
    private func notYet(daysUntil: Int) -> some View {
        // No dot. The dot is a claim that something has been walked, and
        // nothing has — parking it at the left edge would be a claim about
        // day zero.
        tripRule(showsDot: false)

        HStack(alignment: .firstTextBaseline) {
            Mono("Not yet", size: 10.5, color: Palette.a700)
            Spacer()
            Mono(store.start.shortDate, size: 10.5)
        }

        Display(text: daysUntil == 1 ? "Tomorrow" : "\(daysUntil) days\nto go", size: 44)
            .padding(.top, 10)
            .padding(.bottom, 2)

        // Asked of the store, so the sentence's branches can be checked. See
        // `packedSummary`: this read "61 days, 0 countries, €0 between you" on
        // every trip typed from scratch.
        Aside(text: store.packedSummary, size: 13)
            .padding(.bottom, Space.s3)

        SectionRule(top: 0)

        Button { going = .itinerary } label: {
            Panel(border: Palette.accent) {
                Mono("First stop", size: 9.5, color: Palette.a700)
                Text(firstStop?.title ?? "Nothing planned yet")
                    .font(Typeface.heading(19, .semibold))
                    .foregroundStyle(firstStop == nil ? Palette.n600 : Palette.text)
                    .padding(.top, 5)
                Aside(text: firstStopLine, size: 12.5)
                    .padding(.top, 2)
                // The panel speaks up only when it has nothing to show. With a
                // stop in it the named row directly below is the affordance,
                // and a second control saying the same words is noise.
                if firstStop == nil {
                    Mono("Plan the trip", size: 10, trackingRatio: 0.1, color: Palette.a700)
                        .padding(.top, 9)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full itinerary")

        planRow("The whole itinerary", detail: "\(Formatting.spelledCount(store.dayCount, "day", spellingUpTo: 0))",
                hint: "Opens the full itinerary") { going = .itinerary }

        Rule()

        memory

        Aside(text: "Nothing to write down until you're there. The letters open themselves.", size: 12)
            .padding(.top, Space.s3)
    }

    /// "A year ago today", from the shelf — below the day, never above it:
    /// today comes first. Before departure and between trips it is most of
    /// what this screen has to say, which is when it is most welcome.
    @ViewBuilder
    private var memory: some View {
        let memories = store.isObserver ? [] : store.library.memories(on: store.now)
        if !memories.isEmpty {
            MemoryPanel(memories: memories) { remembering = $0 }
                .padding(.top, Space.s3)
        }
    }

    // MARK: - On the trip

    @ViewBuilder
    private var inProgress: some View {
        tripRule()

        header

        Display(text: store.date(forDay: store.dayNumber).weekdayAndDate, size: 44)
            .padding(.top, 10)
            .padding(.bottom, 2)

        // `blurb` is a plain `String`, so `plan?.blurb` is non-nil for *any*
        // day that has a record — including one made by setting only an
        // occasion or a lodging. That drew an empty italic line and a full
        // section's padding under the date, on the app's first screen.
        if let blurb = plan?.blurb, !blurb.isEmpty {
            Aside(text: blurb, size: 13)
                .padding(.bottom, Space.s3)
        }

        SectionRule(top: 0)

        if store.isOverButOpen {
            homeAgain
        }

        if let near = nearStop {
            arrivalNudge(near)
        }

        if let done = store.countryJustFinished {
            countryDone(done.leg, nights: done.nights, spread: done.spread)
        }

        // The letter card sits above the day rather than in its place. It used
        // to *be* the day's slot on a phone with letters on it, and drew
        // nothing until one had opened — so a phone holding three sealed
        // letters had neither the day nor a way into the letters.
        letterCard

        togetherBlock

        if store.lettersVisible {
            lettersRow
        }

        planRows

        memory

        SectionRule(top: Space.s4)

        figures

        SectionRule()

        tonight

        // Nothing follows for a phone with no letters on it — not even a line
        // saying so, which would itself be a mention. What each side can see is
        // described on the sharing screen, which is the screen for it.
    }

    /// The app icon, unwrapped from its tile.
    ///
    /// The design's argument for the mark's geometry is that this is where it
    /// comes from — "the icon isn't decoration bolted on, it's the one diagram
    /// the product already uses" — so it is drawn by the same view and the same
    /// arithmetic the icon and the widget use.
    ///
    private func tripRule(showsDot: Bool = true) -> some View {
        TripMarkView(
            day: store.dayNumber, of: store.dayCount,
            ahead: Palette.n400, walked: Palette.accent,
            showsDot: showsDot, height: 9)
            .padding(.bottom, Space.s3)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // A plain label again. It was the only way into the itinerary from
            // this screen and a 10.5pt word is a poor door; the panel below and
            // the rows under it are the way in now.
            Mono(dayLabel, size: 10.5, color: Palette.a700)

            Spacer()
            Mono(store.lettersVisible ? store.currentCity : store.myName, size: 10.5)
        }
    }

    private var dayLabel: String {
        if case .after = store.phase { return "Home · \(Formatting.spelledCount(store.dayCount, "day", spellingUpTo: 0)) done" }
        return "Day \(store.dayNumber) of \(store.dayCount)"
    }

    // MARK: - The way into the plan

    /// The named row under a panel — the shape the letters' "All 12 · 3 open"
    /// row already has. Three of them now, so it is written once.
    private func planRow(_ title: String, detail: String, hint: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Mono(title, size: 10, trackingRatio: 0.1)
                Spacer()
                Mono(detail, size: 10, trackingRatio: 0.1, color: Palette.a700)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    // MARK: - Arriving

    /// The next stop, when the phone is inside its radius — from a fix the
    /// app already had permission for, never one it asked for here.
    private var nearStop: Stamp? {
        guard canAdd, store.features.stamps,
              let fix = store.location.current.flatMap(TrailView.fresh),
              let near = store.nearNextStop(latitude: fix.coordinate.latitude,
                                            longitude: fix.coordinate.longitude),
              !notNow.contains(near.id)
        else { return nil }
        return near
    }

    /// A suggestion, never an award: the button goes to the trail's own
    /// confirmation, because a stamp can't be undone and it opens letters.
    private func arrivalNudge(_ stamp: Stamp) -> some View {
        Panel(border: Palette.accent) {
            Mono("You look close", size: 9.5, color: Palette.a700)
            Text("Looks like you're in \(stamp.city)")
                .font(Typeface.heading(19, .semibold))
                .foregroundStyle(Palette.text)
                .padding(.top, 5)
            // Stacked above the accessibility threshold, button full width:
            // side by side at AX5 it read "Drop / the pin" in a box squeezed
            // against "not yet".
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                OutlineButton(title: "Drop the pin", minHeight: 44, size: 14,
                              fillsWidth: typeSize.isAccessibilitySize, horizontalPadding: 18) {
                    arrivalRequest.ask(stamp)
                }
                Button { notNow.insert(stamp.id) } label: {
                    Mono("not yet", size: 10, trackingRatio: 0.1, color: Palette.n700)
                        .frame(minHeight: 44)
                        .padding(.horizontal, Space.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Space.s2)
        }
        .padding(.bottom, Space.s3)
    }

    /// The rows under the block, on the trip.
    ///
    /// No day row: `togetherBlock` is drawn on every phone and the panel *is*
    /// the way to the day, so a second control to the same screen is noise.
    @ViewBuilder
    private var planRows: some View {
        planRow("The whole itinerary", detail: "\(Formatting.spelledCount(store.dayCount, "day", spellingUpTo: 0))",
                hint: "Opens the full itinerary") { going = .itinerary }
    }

    /// How much of the day is actually written down. Computed, because a line
    /// with a number in it has to have something behind the number.
    private var hourCount: Int { plan?.items.count ?? 0 }

    private var dayDetail: String {
        hourCount == 0 ? "nothing yet" : "\(Formatting.spelledCount(hourCount, "hour", spellingUpTo: 0))"
    }

    private var dayLine: String {
        hourCount == 0 ? "The whole day" : "The whole day · \(dayDetail)"
    }

    /// The trip's first stop, if anywhere has been planned at all.
    private var firstStop: Segment? { store.legs.first?.segments.first }

    /// "12 Jan · Thailand", or just the date on a trip with nowhere in it yet.
    ///
    /// The separator belongs to the country, not to the line. Written as one
    /// interpolation it drew "12 Jan · " on every trip typed from scratch — a
    /// dangling divider standing where the answer goes, which is the meeting
    /// point's ". Agreed at 00:53." exactly, one screen over.
    private var firstStopLine: String {
        guard let country = store.legs.first?.country,
              !country.trimmingCharacters(in: .whitespaces).isEmpty else {
            return store.start.shortDate
        }
        return "\(store.start.shortDate) · \(country)"
    }

    /// The newest letter that has opened, when one has.
    @ViewBuilder
    private var letterCard: some View {
        if store.lettersVisible, let letter = store.newestOpenLetter {
            Mono("A letter opened itself here", size: 10)
                .padding(.bottom, 9)

            Button {
                readingLetter = letter
            } label: {
                Panel(border: Palette.accent, padding: EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(letter.title)
                            .font(Typeface.heading(19, .semibold))
                            .tracking(-0.19)
                            .foregroundStyle(Palette.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Tag(text: "No. \(letter.numberLabel)", active: true)
                    }
                    Text(letter.paragraphs.first ?? "")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4.5)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                    Mono(stillSealed == 0 ? "Read the whole thing"
                                          : "Read the whole thing · \(stillSealed) still sealed",
                         size: 10, trackingRatio: 0.1, color: Palette.a700)
                        .padding(.top, 11)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Space.s3)
        }
    }

    private var stillSealed: Int { store.sealedLetters.count + store.hiddenLetterCount }

    /// The way into every letter, whether or not one has opened. It used to
    /// live inside the open-letter card, so a phone whose letters were all
    /// still sealed had no way to see them.
    ///
    /// The line under it is the anticipation: where the next one opens, which
    /// is most of what a sealed letter is for. Never a withheld one's.
    private var lettersRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            planRow("All \(store.letters.count)", detail: store.letterTally ?? "",
                    hint: "Opens the letters") { going = .letters }
            if let next = store.nextLetterLine {
                // Space under, none over: it belongs to the row above, and
                // centred between two rows it read as belonging to neither.
                Aside(text: next, size: 12)
                    .padding(.bottom, Space.s2)
            }
        }
    }

    /// The day after the last one, and every day after that until the trip is
    /// finished. Top of the screen, because it is the only thing Today still
    /// has to say that is new. Offered, never done: plenty of people want the
    /// trip open for a week of sorting photographs.
    private var homeAgain: some View {
        Button { finishing = true } label: {
            Panel(border: Palette.accent) {
                Mono(homeAgainKicker, size: 9.5, color: Palette.a700)
                Text("Put \(store.displayName) on the shelf?")
                    .font(Typeface.heading(19, .semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 5)
                Text("It stays readable, every screen of it, and the next trip starts with your names and the money already in.")
                    .font(Typeface.body(12.5))
                    .foregroundStyle(Palette.n700)
                    .lineSpacing(4)
                    .padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
                // A tappable `Panel` is pixel-identical to a dead one.
                Mono("Finish the trip", size: 10, trackingRatio: 0.1, color: Palette.a700)
                    .padding(.top, 11)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, Space.s3)
        .accessibilityHint("Opens the choice to shelve the trip or throw it away")
    }

    /// A country just ended, and here is what it came to in the book. Shown
    /// once — either answer retires it — on the two days after the leg ends,
    /// and it opens the preview on that country's own opener.
    private func countryDone(_ leg: Leg, nights: Int, spread: Int) -> some View {
        Panel(border: Palette.accent) {
            HStack(alignment: .firstTextBaseline) {
                Mono("\(leg.country) is done", size: 9.5, color: Palette.a700)
                Spacer(minLength: 8)
                Button {
                    withGentleAnimation(.easeInOut(duration: 0.25)) { store.markCountryDone(leg.id) }
                } label: {
                    Mono("not now", size: 9.5, trackingRatio: 0.08, color: Palette.n600)
                        .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                store.markCountryDone(leg.id)
                going = .book(spread: spread)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Formatting.spelledCount(nights, "night")) of it in the book")
                        .font(Typeface.heading(19, .semibold))
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                    Text("Its pages are laid out already, opener and all.")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                    Mono("See its pages", size: 10, trackingRatio: 0.1, color: Palette.a700)
                        .padding(.top, 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, Space.s3)
    }

    private var homeAgainKicker: String {
        guard case .after(let days) = store.phase else { return "Home again" }
        return days <= 1 ? "Home again" : "Home \(days) days"
    }

    @ViewBuilder
    private var togetherBlock: some View {
        Button { going = .today } label: {
            Panel {
                Mono("Today together", size: 9.5)
                // The first hour of the day, not the one at a literal "12:00".
                // That string match was written against a seeded day plan
                // whose hours happened to include noon; now the hours are
                // typed by hand, it would miss almost every time and quietly
                // fall through to the same `first` anyway.
                Text(plan?.orderedItems.first?.title ?? "Nothing planned")
                    .font(Typeface.heading(19, .semibold))
                    .foregroundStyle(Palette.text)
                    .padding(.top, 5)
                // The meeting point is attributable and a day plan isn't —
                // `DayPlan` has no author — so the line names the meeting point.
                Text(store.meetingLine)
                    .font(Typeface.body(12.5))
                    .foregroundStyle(Palette.n700)
                    .lineSpacing(4)
                    .padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
                // Where they sleep, which `DayDetailView` already shows under
                // the same word. The title only; the note stays on the day.
                if let lodging = plan?.lodgingTitle {
                    Text("Tonight · \(lodging)")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A tappable `Panel` is pixel-identical to a dead one, which
                // is what this was, so the way in has to be written down.
                Mono(dayLine, size: 10, trackingRatio: 0.1, color: Palette.a700)
                    .padding(.top, 11)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the whole day")
    }

    private var figures: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // `RateStamp` stays *outside* the button. It is itself a `Button` —
            // it kicks `store.rates.refresh()` — and a button inside a button
            // is a trap: it happens to work, and it is one refactor away from
            // swallowing the tap or stealing it. The meeting-point column
            // beside this one gets away with wrapping everything because it
            // holds no control of its own.
            VStack(alignment: .leading, spacing: 0) {
                if canAdd {
                    Button { addingExpense = true } label: {
                        spentColumn.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds an expense")
                } else {
                    spentColumn
                }
                RateStamp(size: 10.5, color: Palette.n600)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Palette.divider).frame(width: 1)

            Button {
                pickingMeetingPoint = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("Meeting point", size: 10)
                    // A trip that hasn't met anywhere yet has an empty place and
                    // a `.distantPast` stamp, so both halves have to say that
                    // rather than draw a blank title over a time from year one.
                    // This screen was the only one asking; Papers and Separated
                    // drew the blank and the year-one time, which is why the
                    // question is `MeetingPoint.isSet` now and not a private
                    // property here.
                    Text(store.meeting.isSet ? meetingTitle : "Not set yet")
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(store.meeting.isSet ? Palette.text : Palette.n600)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                        .padding(.top, 4)
                    Aside(text: store.meeting.isSet
                          ? "set \(store.meeting.setAt.text("HH:mm"))"
                          : "somewhere you can both walk to",
                          size: 11.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The place, and the bit of it on its own line when there is one. An
    /// empty detail left a blank second line under the place.
    private var meetingTitle: String {
        let detail = store.meeting.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? store.meeting.place : "\(store.meeting.place)\n\(detail)"
    }

    /// What the figure says, without the rate stamp under it.
    private var spentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            spentLabel
            // Asked of the store, so the "≈" and what it counts can be
            // checked. This filtered to the local currency, so a euro card
            // payment left the figure somebody had just tapped unmoved.
            Text(store.spentTodayText)
                .font(Typeface.heading(30))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                // The same treatment the keypad's own amount has, and for the
                // same reason: this is a half-width column, and at an
                // accessibility size a day like "≈฿19,379" broke across two
                // lines with the last digit alone on the second — "SONGKRA / N"
                // on a number, on the screen where misreading one matters.
                // Shrinking keeps it whole and as large as the column allows.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 3)
            // Asked of the store: with no budget there is no pace to be on.
            if let note = store.paceNote {
                Aside(text: note, size: 11.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "SPENT TODAY            + ADD"
    ///
    /// The corner verb every other screen uses, in a half-width column — so it
    /// stacks above the accessibility threshold, the `CallTileRow` trick.
    /// `Mono` is uncapped here and reaches about 31pt at AX5, where "SPENT
    /// TODAY" wraps on its own; a verb beside it on one line is "POLIC / E"
    /// waiting to happen.
    ///
    /// The label takes the width rather than a `Spacer` between the two,
    /// because a `Spacer` in the stacked branch would expand vertically and
    /// push them apart down the column.
    private var spentLabel: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.s2))
        return layout {
            Mono("Spent today", size: 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canAdd {
                Mono("+ add", size: 10, trackingRatio: 0.1, color: Palette.a700)
            }
        }
    }

    private var tonight: some View {
        HStack(spacing: 12) {
            if showsBook { book }
            VStack(alignment: .leading, spacing: 2) {
                Mono(store.lettersVisible ? "Tonight's entry" : "Your page tonight", size: 10)
                Text(entryTitle)
                    .font(Typeface.heading(17, .semibold))
                    .foregroundStyle(Palette.text)
                if showsBook {
                    Mono(Formatting.spelledCount(store.bookPlan.pageCount, "page", spellingUpTo: 0),
                         size: 9.5, color: Palette.n500)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            OutlineButton(title: store.todaysEntry == nil ? "Write" : "Edit",
                          minHeight: 44, size: 14, fillsWidth: false, horizontalPadding: 16) {
                writingEntry = true
            }
        }
    }

    /// The book the pages are becoming, standing beside the row that adds
    /// to it. Only once there is a page: a spine with nothing in it is a
    /// promise, and this is meant to be a fact.
    private var showsBook: Bool {
        store.features.printedBooks && store.nightsWritten > 0
    }

    /// The shelf's own `SpineView`, scaled down whole — the `growingSpine`
    /// arrangement from the setup step — so the book on Today is the same
    /// book that lands on the shelf: its height the trip's length, its
    /// thickness the pages. That arithmetic is the shelf's and stays so,
    /// which means it thickens over a week rather than overnight. The reward
    /// is the object, not a count of evenings.
    private var book: some View {
        let summary = store.summary
        let height: CGFloat = 64
        let scale = height / summary.spineHeight
        return SpineView(summary: summary, isLive: true)
            .gentleAnimation(.spring(response: 0.45, dampingFraction: 0.8), value: summary.pageCount)
            .scaleEffect(scale, anchor: .bottomLeading)
            .frame(width: summary.spineWidth * scale, height: height, alignment: .bottomLeading)
            // Decorative: the page count under the title says it in words.
            .accessibilityHidden(true)
    }

    private var entryTitle: String {
        if let entry = store.todaysEntry {
            return entry.line
        }
        if store.lettersVisible { return "One photo, one line" }
        return store.bookPage(forDay: store.dayNumber).map { "Page \($0) · yours alone" } ?? "One photo, one line · yours alone"
    }
}

// MARK: - Meeting point

/// Four seconds, once a morning.
///
/// The place is typed rather than picked from a list, because a fixed list is
/// only ever right in one city. Anywhere this trip has already met is one tap
/// away, and the local script follows the place rather than the screen.
struct MeetingPointPicker: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var place = ""
    @State private var detail = ""
    /// The same place in the local script, which is the half a driver can read.
    ///
    /// It was displayed long before it could be typed: the seeded places came
    /// with Thai, so the green line under a suggestion looked like something
    /// the app knew how to produce, and a place they wrote themselves could
    /// never have one. Twenty-six days of the trip are in countries whose
    /// script isn't Thai.
    @State private var script = ""
    /// Which place the script on screen belongs to.
    ///
    /// A phrase card belongs to one gate — leaving Wat Phra Singh's Thai under
    /// "Tha Phae Gate" is how somebody is driven to the wrong side of a city —
    /// so the script follows the place: change what's in "Where" and the script
    /// is whatever this trip knows about *that* place, or nothing.
    @State private var scriptPlace = ""
    @State private var askingToDiscard = false

    private var isDirty: Bool {
        typed != store.meeting.place
            || detail.trimmingCharacters(in: .whitespaces) != store.meeting.detail
            || script.trimmingCharacters(in: .whitespacesAndNewlines) != store.meeting.localScript
    }

    private var typedPoint: MeetingPoint {
        MeetingPoint(place: typed,
                     detail: detail.trimmingCharacters(in: .whitespaces),
                     localScript: script.trimmingCharacters(in: .whitespacesAndNewlines),
                     setAt: store.now)
    }

    /// "Done" used to be a bare `dismiss()`, so typing a place and tapping
    /// the word that says you are finished threw the place away. It keeps
    /// what was typed now; with "Where" emptied there is nothing to keep, and
    /// it asks.
    private func done() {
        guard isDirty else { dismiss(); return }
        if typed.isEmpty { askingToDiscard = true } else { save(typedPoint) }
    }

    /// Everywhere this trip has met, most recent first. A trip suggests nothing
    /// until it has a history of its own.
    ///
    /// `store.meetingPlaces` is the list; tonight's point is in it, and is here
    /// separately as well because a trip that met somewhere before this build
    /// remembered exactly one place and it is this one.
    private var suggestions: [MeetingPoint] {
        var seen: [MeetingPoint] = []
        func offer(_ option: MeetingPoint) {
            guard !option.placeKey.isEmpty,
                  !seen.contains(where: { $0.placeKey == option.placeKey })
            else { return }
            seen.append(option)
        }
        offer(store.meeting)
        store.meetingPlaces.forEach(offer)
        return seen
    }

    private var typed: String { place.trimmingCharacters(in: .whitespaces) }

    /// What to call the language of wherever they are — a label, not a
    /// translation. `CountryFacts` answers `nil` for a country with more than
    /// one honest answer and for one it has never heard of, and "Local script"
    /// says exactly that. Same rule as the show-this card editor, which asks
    /// for the same thing on the same terms.
    private var scriptLabel: String {
        store.currentLanguage.map { "In \($0) · optional" } ?? "Local script · optional"
    }

    private var scriptPhrase: String { store.currentLanguage ?? "the local language" }

    /// The script belongs to the place, so changing the place changes it.
    ///
    /// Keyed on the folded place rather than the raw text, so fixing the case
    /// of a name doesn't take its script off the screen.
    private func placeChanged() {
        let key = typed.lowercased()
        guard key != scriptPlace else { return }
        scriptPlace = key
        script = suggestions.first { $0.placeKey == key }?.localScript ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Tonight's meeting point", trailing: "Done") { done() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Aside(text: "Somewhere you can both walk to if the phones die.", size: 12.5)
                        .padding(.bottom, Space.s4)

                    WrittenField(label: "Where", text: $place,
                                 placeholder: "The bridge", size: 24)

                    WrittenField(label: "Which bit of it", text: $detail,
                                 placeholder: "north end, by the steps",
                                 note: "The part you say out loud when one of you is already standing there.",
                                 size: 17)
                        .padding(.top, Space.s4)

                    // Not a sample phrase: any real one would have to be in
                    // *some* script, and a Thai example is what a phone
                    // standing in Busan would have printed. The prompt names
                    // the language instead and the field asks for what only a
                    // person can supply.
                    WrittenField(label: scriptLabel, text: $script,
                                 placeholder: "Write it in \(scriptPhrase)",
                                 note: "What you hold up to a driver. Di Thôi doesn't translate — it only asks.",
                                 size: 19,
                                 ink: Palette.a700,
                                 capitalisation: .never)
                        .padding(.top, Space.s4)

                    if !suggestions.isEmpty {
                        Mono("Or somewhere you've used", size: 10)
                            .padding(.top, Space.s6)
                            .padding(.bottom, 9)

                        ForEach(suggestions, id: \.place) { option in
                            let isTonight = option.placeKey == store.meeting.placeKey
                            Button { save(option) } label: {
                                Panel(border: isTonight ? Palette.accent : Palette.divider,
                                      fill: isTonight ? Palette.a100 : .clear) {
                                    Text(option.place)
                                        .font(Typeface.heading(19, .semibold))
                                        .foregroundStyle(Palette.text)
                                    Aside(text: option.detail, size: 12)
                                        .padding(.top, 2)
                                    if !option.localScript.isEmpty {
                                        Text(option.localScript)
                                            .font(Typeface.heading(15, .semibold))
                                            .foregroundStyle(Palette.a700)
                                            .padding(.top, 6)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, Space.s2)
                        }
                    }

                    Aside(text: "Four seconds, once a morning.",
                          size: 12)
                        .padding(.top, Space.s3)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s6)
            }

            OutlineButton(title: "That's where", minHeight: 50, size: 15) {
                save(typedPoint)
            }
            .opacity(typed.isEmpty ? 0.4 : 1)
            .disabled(typed.isEmpty)
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard,
                           whatGoes: "Tonight's point stays as it was.") {
            dismiss()
        }
        .onAppear {
            place = store.meeting.place
            detail = store.meeting.detail
            script = store.meeting.localScript
            scriptPlace = store.meeting.placeKey
        }
        .onChange(of: place) { placeChanged() }
    }

    private func save(_ point: MeetingPoint) {
        store.setMeetingPoint(point)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Shared header for the app's sheets.
struct SheetHeader: View {
    let title: String
    var leading: String?
    var trailing: String?
    var onLeading: (() -> Void)?
    var onTrailing: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let leading, let onLeading {
                Button(action: onLeading) {
                    Mono(leading, size: 10.5, color: Palette.a700).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Mono(title, size: 10.5)
            }

            Spacer()

            if let trailing {
                Button(action: onTrailing) {
                    Mono(trailing, size: 10.5, color: Palette.a700).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.s2)
    }
}
