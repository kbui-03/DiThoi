import SwiftUI

/// E2 · Looking back. Two books, same trip, different halves of it.
struct BookView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var writing = false
    @State private var editing: JournalEntry?
    /// What the print screen will say, measured here while there is still
    /// time to act on it. Off the main thread, and only when a photograph or
    /// a moment changes.
    @State private var readiness: PrintReadiness?
    @State private var finishingMoment: Moment?
    @State private var makingPostcard = false

    var body: some View {
        NavigationStack {
            Screen(context: .syncState) {
                if case .before = store.phase {
                    notYet
                } else {
                    soFar
                }
            }
            .sheet(isPresented: $writing) { TonightEntryView() }
            .sheet(item: $finishingMoment) { moment in MomentComposerView(editing: moment) }
            .task(id: readinessKey) { await measure() }
            .sheet(item: $editing) { entry in TonightEntryView(day: entry.dayNumber) }
        }
    }

    // MARK: - Before departure

    /// Before day 1 there is no book to show. `dayNumber` pins the days before
    /// departure to 1, so this tab said "One day in" nine days early and
    /// offered day 1 as tonight's page. Today's "Not yet", in the book's words,
    /// and nothing to tap: the store refuses the page either way.
    @ViewBuilder
    private var notYet: some View {
        HStack(alignment: .firstTextBaseline) {
            Mono("Not yet", size: 10.5, color: Palette.a700)
            Spacer()
            Mono(store.start.shortDate, size: 10.5)
        }

        Display(text: "No pages yet", size: 38)
            .padding(.top, 8)
            .padding(.bottom, 4)

        Aside(text: store.bookNotYetLine, size: 12.5)
            .padding(.bottom, Space.s3)

        Rule()
    }

    // MARK: - So far

    @ViewBuilder
    private var soFar: some View {
        HStack(alignment: .firstTextBaseline) {
            Mono("Your book, so far", size: 10.5)
            Spacer()
            // Nights, not pages: a night is a spread, and the row
            // below gives the book's own page count.
            Mono(Formatting.spelledCount(store.nightsWritten, "night", spellingUpTo: 0) + " written",
                 size: 10.5, color: Palette.a700)
        }

        Display(text: daysInHeadline, size: 38)
            .padding(.top, 8)
            .padding(.bottom, 4)

        Aside(text: missedLine, size: 12.5)
            .padding(.bottom, Space.s3)

        BackfillOffer(writing: $editing)

        if store.features.printedBooks, store.nightsWritten > 0 {
            NavigationLink {
                BookPreviewView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("See it as a book")
                            .font(Typeface.heading(17, .semibold))
                            .foregroundStyle(Palette.text)
                        Aside(text: "\(store.bookPlan.pageCount) pages, \(store.bookPlan.spec.trimLabel)",
                              size: 11.5, color: Palette.n600)
                    }
                    Spacer()
                    Mono("preview", size: 10, trackingRatio: 0.08, color: Palette.a700)
                }
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        // A week of the book as a picture to keep. Always here, any
        // week; the saved page offers it once more on the night the
        // book reaches another seven. It writes nothing to the trip,
        // so a shelved trip makes one too.
        if store.features.printedBooks, !store.isObserver, let latest = store.postcardWeeks.last {
            Button { makingPostcard = true } label: {
                HStack {
                    Text("Make a postcard")
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Mono("week \(latest) ready", size: 10, trackingRatio: 0.08, color: Palette.a700)
                }
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $makingPostcard) {
                PostcardPicker(week: latest, switchesWeeks: true)
            }
        }

        if let line = readiness?.earlyLine, canFix {
            Button(action: fixFirst) {
                VStack(alignment: .leading, spacing: 2) {
                    Aside(text: line, size: 12, color: Palette.n700)
                    Mono("fix the first", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the first one to fix")
            .padding(.bottom, Space.s2)
        }

        Rule()

        // Grouped the way the book is: a heading wherever the country
        // changes, so Thailand on the way back is its own run, as it
        // is in the contents.
        ForEach(timeline, id: \.day) { row in
            if let heading = row.heading {
                Mono(heading, size: 9.5, trackingRatio: 0.14, color: Palette.a700)
                    .padding(.top, Space.s4)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                Rule()
            }
            entryRow(row)
            Rule()
        }

        // Two panels stood here: "<them> is writing theirs too" and
        // "Two books, <date> · They arrive on the same day." Journals
        // never leave the phone they were written on, so neither
        // sentence was anything this phone could know.
    }

    // MARK: - Before it prints

    /// Only while the trip is on and making a book: that is when a soft
    /// photograph can still be taken again.
    private var canFix: Bool { store.features.printedBooks && store.isLive && !isReadOnly }

    /// Everything the line depends on: each photograph that could print, and
    /// how many moments are unfinished.
    private var readinessKey: [String] {
        store.myEntries.flatMap(\.allPhotoIDs) + store.printedMoments.compactMap(\.photoID)
            + ["unfinished \(store.unfinishedMoments.count)"]
    }

    /// The headers are read off the main thread and remembered per photograph
    /// — an id names one file for good — so the tab never re-reads them on a
    /// redraw. `printReadiness` read every one of them five times a pass on
    /// the print screen once; this is the lesson kept.
    private func measure() async {
        guard canFix else { readiness = nil; return }
        let ids = readinessKey.dropLast()
        await Task.detached(priority: .utility) {
            for id in ids { _ = PhotoStore.shared.pixelShortEdge(id) }
        }.value
        guard !Task.isCancelled else { return }
        readiness = store.printReadiness { PhotoStore.shared.pixelShortEdge($0) }
    }

    /// The first soft photograph's night or moment, else the oldest unfinished
    /// moment. Fixing it moves the line on to the next.
    private func fixFirst() {
        if let id = readiness?.softRecords.first {
            if let entry = store.myEntries.first(where: { $0.id == id }) {
                editing = entry
            } else if let moment = store.moment(id) {
                finishingMoment = moment
            }
        } else if let oldest = store.unfinishedMoments.last {
            finishingMoment = oldest
        }
    }

    // MARK: - Timeline

    private struct Row {
        let day: Int
        let entry: JournalEntry?
        /// The country, on the first row of each run of it.
        var heading: String?
    }

    private var timeline: [Row] {
        let entries = store.myEntries
        let legs = store.legs
        // The leg a day belongs to, with the last leg keeping the day they fly
        // home — `BookPlan`'s rule, so the list and the book agree.
        func leg(forDay day: Int) -> Leg? {
            for (index, leg) in legs.enumerated()
            where day >= leg.startDay && (index == legs.count - 1 || day < leg.endDay) {
                return leg
            }
            return nil
        }
        var rows: [Row] = []
        var previous: UUID?
        for day in stride(from: store.dayNumber, through: 1, by: -1) {
            let here = leg(forDay: day)
            let heading = here != nil && here?.id != previous ? here?.country : nil
            previous = here?.id
            rows.append(Row(day: day, entry: entries.first { $0.dayNumber == day }, heading: heading))
        }
        return rows
    }

    @ViewBuilder
    private func entryRow(_ row: Row) -> some View {
        Button {
            if row.day == store.dayNumber && row.entry == nil {
                writing = true
            } else if let entry = row.entry {
                editing = entry
            } else {
                editing = JournalEntry(dayNumber: row.day, date: store.date(forDay: row.day),
                                       city: store.cityStamp(forDay: row.day), line: "", tags: [],
                                       hasPhoto: false, author: store.role)
            }
        } label: {
            HStack(alignment: row.entry == nil ? .center : .top, spacing: Space.s3) {
                if row.entry?.hasPhoto == true {
                    JournalPhoto(photoID: row.entry?.photoID, side: 52, usesThumbnail: true)
                } else {
                    VStack {
                        Mono("no\npage", size: 8, trackingRatio: 0.08, color: Palette.n500)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 52, height: 52)
                    .overlay(
                        Rectangle().strokeBorder(Palette.n400, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Mono("Day \(row.day)\(cityFragment(row))", size: 9.5, trackingRatio: 0.1,
                         color: row.entry == nil ? Palette.n500 : (row.day == store.dayNumber ? Palette.a700 : Palette.n600))

                    if let entry = row.entry, !entry.line.isEmpty {
                        Text(entry.line)
                            .font(Typeface.heading(16, .semibold))
                            .foregroundStyle(Palette.text)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                    } else if row.day == store.dayNumber {
                        Aside(text: "Not written yet. One photo, one line.", size: 12.5)
                    } else {
                        Aside(text: "Skipped. Add it later if you feel like it.", size: 12.5, color: Palette.n600)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cityFragment(_ row: Row) -> String {
        guard let entry = row.entry, let city = store.city(of: entry) else { return "" }
        return " · \(city)"
    }

    /// "One day in", "Twelve days in", "150 days in".
    ///
    /// The plural is `Formatting`'s to get right. This wrote " days in" into
    /// the string, so the first day of every trip read "One days in" — and it
    /// spelled out any number at all, so a long trip's 38pt headline was
    /// "Three thousand six hundred and fifty days in". `ItineraryView` had
    /// guarded the second half and not the first; now neither is anyone's here.
    private var daysInHeadline: String {
        "\(Formatting.spelledCount(store.dayNumber, "day")) in"
    }

    private var missedLine: String {
        let missed = store.missedNights
        if missed == 0 { return "Not one night missed so far." }
        return "You've missed \(Formatting.spelledCount(missed, "night", spellingUpTo: 0)). Nobody minds; the book skips them."
    }
}

// MARK: - H4 · after a missed night

/// Asked once, about last night only, and never again.
///
/// The design forgives missed nights everywhere else, so this is the single
/// place the app mentions one — and "Leave it" is a real answer that costs
/// nothing, which is why the copy says so.
struct BackfillOffer: View {
    @EnvironmentObject private var store: TripStore
    @Binding var writing: JournalEntry?

    var body: some View {
        if let day = store.backfillCandidate {
            Panel {
                Mono("Yesterday has no page", size: 9.5)
                Text("Want to add day \(day)?")
                    .font(Typeface.heading(19, .semibold))
                    .foregroundStyle(Palette.text)
                    .padding(.top, 5)
                // It promised "the photos are still on the phone, sorted by hour".
                // The app's access to Photos is add-only, so it cannot sort or
                // even see them; the sentence now promises only what is true.
                Text("Leave it if you like — the book closes the gap.")
                    .font(Typeface.body(12.5))
                    .foregroundStyle(Palette.n700)
                    .lineSpacing(4)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.s2) {
                    OutlineButton(title: "Add it", minHeight: 44, size: 14) {
                        store.markBackfillOffered(day)
                        writing = JournalEntry(dayNumber: day, date: store.date(forDay: day),
                                               city: store.cityStamp(forDay: day), line: "", tags: [],
                                               hasPhoto: false, author: store.role)
                    }
                    OutlineButton(title: "Leave it", minHeight: 44, size: 14,
                                  border: Palette.divider, foreground: Palette.text) {
                        store.markBackfillOffered(day)
                    }
                }
                .padding(.top, Space.s3)

                Mono("asked once · never again", size: 9, trackingRatio: 0.1, color: Palette.n500)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.s2)
            }
            .padding(.bottom, Space.s3)
        }
    }
}
