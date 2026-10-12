import SwiftUI

/// J1 · the observer's home screen.
///
/// The same app, the observer's role: where the travellers are, and which of
/// the letters are still sealed. That is the whole list — no journal, no
/// ledger, no live position, and nothing anywhere on this side that
/// says whether a letter was read.
struct HomeView: View {
    @EnvironmentObject private var store: TripStore
    @State private var writing: Letter?
    @State private var showingHandover = false
    @State private var showingUndelivered = false
    @State private var finishing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Screen(context: .syncState) {
                    HStack(alignment: .firstTextBaseline) {
                        Mono(dayLine, size: 10.5, color: Palette.a700)
                        Spacer()
                        Mono("Writing side", size: 10.5)
                    }

                    Display(text: whereabouts, size: 38)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    Aside(text: pinsLine, size: 12.5)
                        .padding(.bottom, Space.s3)

                    // Pins, not a position: which cities the phone
                    // agreed they stood in, at the moment it agreed — never
                    // where they are now.
                    HatchPanel(height: 172, caption: "their trail\n·\npins only, no live position")

                    SectionRule(top: Space.s4)

                    HStack(alignment: .firstTextBaseline) {
                        Mono("Your letters", size: 10)
                        Spacer()
                        Mono(tally, size: 10.5, trackingRatio: 0.06, color: Palette.a700)
                    }
                    .padding(.bottom, 9)

                    if let problem = store.letterPostProblem {
                        postalService(problem)
                    }

                    Rule(color: Palette.text)

                    ForEach(letterRows) { letter in
                        letterRow(letter)
                        Rule()
                    }

                    if let gap = nextGap {
                        Panel {
                            Mono("Gap coming up", size: 9.5)
                            Text("Nothing between day \(gap.fromDay) and day \(gap.toDay)")
                                .font(Typeface.heading(17, .semibold))
                                .foregroundStyle(Palette.text)
                                .padding(.top, 4)
                            Aside(text: "\(spelled(gap.days)) days with nothing due.", size: 12)
                                .padding(.top, 2)
                        }
                        .padding(.top, Space.s3)
                    }

                    if store.phase.isBefore {
                        Button { showingHandover = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Before they go")
                                        .font(Typeface.heading(17, .semibold))
                                        .foregroundStyle(Palette.text)
                                    Aside(text: "What's on their phone already", size: 11.5, color: Palette.n600)
                                }
                                Spacer()
                                Mono("check", size: 10, trackingRatio: 0.08, color: Palette.a700)
                            }
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Space.s3)
                    }

                    if !store.undeliveredLetters.isEmpty {
                        Button { showingUndelivered = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("One never landed")
                                        .font(Typeface.heading(17, .semibold))
                                        .foregroundStyle(Palette.text)
                                    Aside(text: "The trip is over and No. \(store.undeliveredLetters[0].numberLabel) is still sealed",
                                          size: 11.5, color: Palette.n600)
                                }
                                Spacer()
                                Mono("open", size: 10, trackingRatio: 0.08, color: Palette.a700)
                            }
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Space.s3)
                    }

                    SectionRule()
                    neverSent

                    // The observer's only way out of a trip. Home mode has no
                    // Papers tab, so no shelf and no settings, and until this
                    // row the phone at home was on its first trip for good.
                    if store.isLive {
                        SectionRule()
                        finishRow
                    }
                }

                OutlineButton(title: "Write a letter", minHeight: 48) {
                    writing = store.startLetter(title: "", condition: defaultCondition)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s2)
                .background(Palette.bg)
            }
            .background(Palette.bg)
            .sheet(item: $writing) { letter in ComposeLetterView(letterID: letter.id) }
            .sheet(isPresented: $showingHandover) { HandoverView() }
            .sheet(isPresented: $showingUndelivered) { UndeliveredView() }
            .sheet(isPresented: $finishing) { FinishTripView() }
        }
    }

    private var finishRow: some View {
        Button { finishing = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish this trip")
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: store.phase.isAfter
                              ? "They're home. Put it on the shelf with your letters in it"
                              : "Put it on the shelf, or throw it away",
                          size: 11.5, color: Palette.n600)
                }
                Spacer()
                Mono("finish", size: 10, trackingRatio: 0.08, color: Palette.a700)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - What this side is told

    private var dayLine: String {
        switch store.phase {
        case .before(let days): "\(days) day\(days == 1 ? "" : "s") to go"
        case .during: "Day \(store.dayNumber) of \(store.dayCount)"
        case .after: "The trip is over"
        }
    }

    private var whereabouts: String {
        guard store.phase == .during else {
            return store.phase.isBefore ? "Not gone\nyet" : "They're\nhome"
        }
        let city = store.earnedStamps.last?.city ?? store.currentCity
        return "They're in\n\(city)"
    }

    private var pinsLine: String {
        let earned = store.earnedStamps.count
        guard earned > 0 else { return "No pins yet. The first one lands when they do." }
        guard let last = store.earnedStamps.last, let on = last.earnedOn else {
            return "\(earned) places so far."
        }
        return "\(earned) place\(earned == 1 ? "" : "s") so far. The last one landed \(on.dayMonth)."
    }

    /// The next few that will land, then the last couple that did.
    ///
    /// Both halves are kept: a list of only what's coming reads like a to-do
    /// list, and one of only what's landed reads like a receipt. They want to
    /// know what's next and that the last one arrived.
    private var letterRows: [Letter] {
        let moment = store.letterMoment
        let sealed = store.sealedByWriter
        let delivered = sealed.filter { $0.condition.isMet(moment) }.sorted { $0.number > $1.number }
        let waiting = sealed.filter { !$0.condition.isMet(moment) }.sorted { $0.number < $1.number }
        return Array(waiting.prefix(3)) + Array(delivered.prefix(2))
    }

    @ViewBuilder
    private func letterRow(_ letter: Letter) -> some View {
        let landed = letter.condition.isMet(store.letterMoment)
        HStack(alignment: .top, spacing: Space.s3) {
            Text(letter.numberLabel)
                .font(Typeface.mono(11))
                .monospacedDigit()
                .foregroundStyle(landed ? Palette.a700 : Palette.n500)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 26, alignment: .leading)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(landed ? deliveredHeadline(letter) : letter.condition.summary)
                    .font(Typeface.heading(16, .semibold))
                    .foregroundStyle(landed ? Palette.text : Palette.n600)
                    .multilineTextAlignment(.leading)
                Aside(text: landed
                      ? (store.lettersAreStuck
                         ? "the moment came · this one hasn't been sent"
                         : "arrived · nothing about whether it was read")
                      : "sealed · \(estimate(letter))",
                      size: 11, color: Palette.n500)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    /// What this phone knows about the sealed set, which is two separate things
    /// and used to be printed as one.
    ///
    /// `deliveredCount` is condition arithmetic over synced trip state — a real
    /// prediction that the letter's moment has come, not a fixture. What it has
    /// never known is whether the drop *left this phone*, and "delivered"
    /// asserts both. When the postal service isn't running, the second half is
    /// false for every letter, always, so the word has to change with it.
    private var tally: String {
        let due = store.deliveredCount
        let sealed = store.stillSealedCount
        return store.lettersAreStuck
            ? "\(due) due · \(sealed) not yet"
            : "\(due) delivered · \(sealed) sealed"
    }

    private func deliveredHeadline(_ letter: Letter) -> String {
        // Same split, one row down. "Delivered in Hội An" is a claim about a
        // journey; "their Hội An days" is a claim about the calendar, which is
        // all this phone can see when nothing is leaving it.
        guard !store.lettersAreStuck else { return dueHeadline(letter) }
        switch letter.condition {
        case .place(let name): return "Delivered in \(name)"
        case .day(let day): return "Delivered on day \(day)"
        case .stamp(let code): return "Delivered with \(code)"
        case .finalStamp: return "Delivered with the last stamp"
        case .nextOnline: return "Delivered when they came online"
        case .hidden: return "Delivered"
        }
    }

    private func dueHeadline(_ letter: Letter) -> String {
        switch letter.condition {
        case .place(let name): "Due in \(name)"
        case .day(let day): "Due on day \(day)"
        case .stamp(let code): "Due with \(code)"
        case .finalStamp: "Due with the last stamp"
        case .nextOnline: "Due the next time they're online"
        case .hidden: "Due"
        }
    }

    /// J1b · the sentence the writing side never had.
    ///
    /// The sync step has said "isn't switched on for this build" since
    /// the shelf's old new-trip flow was written; the letters said nothing at all, while every
    /// other line on this screen described a delivery. Whichever half is broken
    /// — no postal service in this build, or a post that failed — this is where
    /// it gets said, once, without an alarm.
    private func postalService(_ problem: String) -> some View {
        Panel(border: Palette.n400) {
            Mono("Not posted yet", size: 9.5)
            Text(problem)
                .font(Typeface.body(12.5))
                .foregroundStyle(Palette.n700)
                .lineSpacing(4)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            Aside(text: "Nothing is lost — they're written and sealed, and they go the moment there's a way to send them.",
                  size: 11.5)
                .padding(.top, 6)
        }
        .padding(.bottom, Space.s3)
    }

    private func estimate(_ letter: Letter) -> String {
        guard let placement = store.letterSchedule.placements.first(where: { $0.id == letter.id })
        else { return "no date yet" }
        let away = placement.day - store.dayNumber
        if away <= 0 { return "any day now" }
        if away == 1 { return "about a day out" }
        return "about \(spelled(away)) days out"
    }

    private var nextGap: LetterSchedule.Silence? {
        store.letterSchedule.silences.first { $0.toDay > store.dayNumber }
    }

    private var defaultCondition: LetterCondition {
        // Mid-trip, the only condition guaranteed to fire is the one that waits
        // for the other phone to be online, so that is what a new letter opens
        // on once the trip has started.
        store.phase == .during ? .nextOnline : .day(min(store.dayNumber + 7, store.dayCount))
    }

    private func spelled(_ number: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "eleven", "twelve"]
        return number < words.count ? words[number] : "\(number)"
    }

    /// J8 · what this side is never sent. Written out rather than implied,
    /// because the absence is the feature.
    private var neverSent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("What you will never be sent", size: 10)
                .padding(.bottom, 6)
            Text("that it was opened · that it was read twice · where they are right now · anything they wrote")
                .font(Typeface.body(12).italic())
                .foregroundStyle(Palette.n600)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Mono("Delivered, not read.", size: 9.5, trackingRatio: 0.1, color: Palette.n500)
                .padding(.top, Space.s3)
        }
    }
}

// MARK: - J7 · the handover

/// The night before. Everything is already on the travelling phone, so the
/// screen's job is to say so and then get out of the way.
struct HandoverView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "The handover", trailing: "Close") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("Everything is on their phone", size: 10.5, trackingRatio: 0.16, color: Palette.a700)

                    Display(text: "Nothing left\nto do", size: 44, tracking: -0.025)
                        .padding(.top, 12)

                    Rectangle().fill(Palette.accent)
                        .frame(width: 52, height: 1)
                        .padding(.vertical, Space.s4)

                    row("Letters sealed", "\(store.sealedByWriter.count)")
                    row("Itinerary", "\(store.dayCount) days")
                    row("Stamps waiting", "\(store.orderedStamps.count)")
                    // Counted, not described. "both of them" was drawn for any
                    // non-empty list, so one document read as two and three
                    // read as two — the same shape as the design's "61 days"
                    // over a 72-day trip.
                    row("Papers", store.documents.isEmpty
                        ? "none"
                        : "\(store.documents.count)")
                    row("Books", store.features.printedBooks ? "2 · paid for" : "not this trip", last: true)

                    Panel(border: Palette.accent) {
                        Mono("From tomorrow", size: 9.5, color: Palette.a700)
                        Text("Your app becomes the quiet one")
                            .font(Typeface.heading(19, .semibold))
                            .foregroundStyle(Palette.text)
                            .padding(.top, 5)
                        Text("Home mode: their pins, which letters are still sealed, and nothing else. No read receipts, no location, no journal.")
                            .font(Typeface.body(12.5))
                            .foregroundStyle(Palette.n700)
                            .lineSpacing(4)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Space.s4)

                    if !store.writerDrafts.isEmpty {
                        Aside(text: "\(store.writerDrafts.count) draft\(store.writerDrafts.count == 1 ? "" : "s") still unsealed. A draft never travels — seal it or it isn't a letter.",
                              size: 12)
                            .padding(.top, Space.s3)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, Space.s6)
            }

            VStack(spacing: 3) {
                Mono("Hand the phone over at the gate.", size: 9.5, trackingRatio: 0.12)
                Mono("It explains itself.", size: 9.5, trackingRatio: 0.12)
            }
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
    }

    private func row(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Typeface.heading(17, .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(value)
                    .font(Typeface.mono(12.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.a700)
            }
            .padding(.vertical, 9)
            if !last { Rule() }
        }
    }
}

// MARK: - J10 · the one that never opened

/// Written, sealed, keyed to a city they cut. It stays sealed.
///
/// There is no button on this screen that fixes it, and that is the screen's
/// entire argument: a condition that can be re-keyed after the fact was never a
/// condition, and the eleven that did land only meant something because this
/// one could fail.
struct UndeliveredView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Still sealed", trailing: "Close") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("The trip is over", size: 10.5)

                    Display(text: headline, size: 36, tracking: -0.02)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    Aside(text: reason, size: 12.5)
                        .padding(.bottom, Space.s3)

                    ForEach(store.undeliveredLetters) { letter in
                        Panel(border: Palette.n400) {
                            HStack(alignment: .firstTextBaseline) {
                                Mono("Still sealed · No. \(letter.numberLabel)", size: 9.5)
                                Spacer()
                                Tag(text: "never sent")
                            }
                            Text(letter.title.isEmpty ? "Untitled" : letter.title)
                                .font(Typeface.heading(19, .semibold))
                                .foregroundStyle(Palette.n700)
                                .padding(.top, 6)
                                .multilineTextAlignment(.leading)
                            Text("It stays sealed. It can't be re-keyed to somewhere they did reach, and it can't be handed over now. Nobody will know it existed unless you say so.")
                                .font(Typeface.body(12.5))
                                .foregroundStyle(Palette.n700)
                                .lineSpacing(4)
                                .padding(.top, 6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, Space.s2)
                    }

                    SectionRule()

                    Mono("The \(store.sealedByWriter.count)", size: 10)
                        .padding(.bottom, 7)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 6),
                              spacing: Space.s2) {
                        ForEach(store.sealedByWriter) { letter in
                            let landed = letter.condition.isMet(store.letterMoment)
                            Text(letter.numberLabel)
                                .font(Typeface.mono(11))
                                .monospacedDigit()
                                .foregroundStyle(landed ? Palette.a700 : Palette.n500)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .background(Circle().fill(landed ? Palette.a100 : .clear))
                                .overlay(
                                    Circle().strokeBorder(landed ? Palette.accent : Palette.n400,
                                                          style: StrokeStyle(lineWidth: 1,
                                                                             dash: landed ? [] : [3, 3]))
                                )
                        }
                    }

                    Aside(text: rate, size: 12)
                        .padding(.top, Space.s3)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s6)
            }

            OutlineButton(title: "Keep it sealed", minHeight: 48,
                          border: Palette.divider, foreground: Palette.text) { dismiss() }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
    }

    private var written: Int { store.sealedByWriter.count }
    private var landed: Int { written - store.undeliveredLetters.count }

    private var headline: String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
                     "nine", "ten", "eleven", "twelve"]
        func word(_ n: Int) -> String { n < words.count ? words[n] : "\(n)" }
        let a = word(written), b = word(landed)
        return "\(a.prefix(1).uppercased() + a.dropFirst()) written,\n\(b) landed"
    }

    private var reason: String {
        guard let first = store.undeliveredLetters.first else { return "" }
        switch first.condition {
        case .place(let name):
            return "They never reached \(name). The letter keyed to it never fired."
        case .day(let day):
            return "Day \(day) never came round while the trip was still open."
        case .stamp(let code):
            return "The \(code) stamp was never earned."
        case .finalStamp:
            return "They didn't get all the stamps, so the last one never opened."
        case .nextOnline, .hidden:
            return "Its condition never came true."
        }
    }

    private var rate: String {
        "\(landed) of \(written) landed."
    }
}
