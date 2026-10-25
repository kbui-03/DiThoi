import SwiftUI

/// B3 · One day.
struct DayDetailView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.dynamicTypeSize) private var typeSize
    let segment: Segment

    /// Which day of the stop is on screen.
    ///
    /// It moves, because `ItineraryView` can only ever link to a stop's *first*
    /// day — so days 2..n of a nine-night stay had no way in at all, which was
    /// survivable while this screen only read and isn't now that it writes.
    @State private var day: Int
    @State private var editing = false
    @State private var writingNight = false
    @State private var destination: Destination?

    /// Pushed through one `navigationDestination(item:)` (§5.1).
    private enum Destination: Hashable, Identifiable {
        case moments(Int)
        var id: Self { self }
    }

    init(day: Int, segment: Segment) {
        self.segment = segment
        _day = State(initialValue: day)
    }

    private var plan: DayPlan? { store.plan(forDay: day) }

    /// Every day of this stop. Half-open, because `endDay` is the day they
    /// leave — the same reason `Segment.contains(day:)` is.
    private var days: [Int] {
        Array(segment.startDay ..< max(segment.endDay, segment.startDay + 1))
    }

    private var blurb: String { plan?.blurb.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    /// The hours column is a fixed width, so it has to grow with the type or
    /// "07:30" wraps inside it — three lines for a timestamp, which is the
    /// board's timeline lesson in miniature. Capped, because past a point the
    /// column would take the whole width and leave nothing for the title.
    private var timeColumn: CGFloat { 52 * min(TypeScale.factor(for: typeSize), 1.7) }

    var body: some View {
        Screen(context: .syncState) {
            // Two items, not three. A third — the occasion — leaves three
            // things competing for one line, and at an accessibility size the
            // middle one breaks mid-word and lands on the button. The occasion
            // reads fine under the date, which is what it is about.
            HStack(alignment: .firstTextBaseline) {
                Mono("Day \(day) · \(cityName)", size: 10.5)
                Spacer(minLength: Space.s2)
                if !isReadOnly {
                    Button { editing = true } label: {
                        // The padding goes on the label, before the shape, so
                        // a near-miss on a 10.5pt word still lands.
                        Mono("edit", size: 10.5, color: Palette.a700)
                            .padding(.leading, Space.s4)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Display(text: store.date(forDay: day).dayMonth, size: 38)
                .padding(.top, 8)
                .padding(.bottom, plan?.occasion == nil ? Space.s2 : 4)

            if let occasion = plan?.occasion {
                Mono(occasion, size: 10.5, color: Palette.a700)
                    .padding(.bottom, Space.s2)
            }

            // A one-night stop has nothing to pick between.
            if days.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(days, id: \.self) { number in
                            Chip(text: "day \(number)", selected: number == day) {
                                withGentleAnimation(.easeInOut(duration: 0.2)) { day = number }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(.bottom, Space.s3)
            }

            Text(blurb.isEmpty
                 ? "Nothing written for this day yet. The plan is whatever you decide over breakfast."
                 : blurb)
                .font(Typeface.body(13))
                .lineSpacing(5)
                .foregroundStyle(blurb.isEmpty ? Palette.n600 : Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Space.s3)

            Rule()

            if let items = plan?.orderedItems, !items.isEmpty {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: Space.s3) {
                        Text(item.time)
                            .font(Typeface.mono(11))
                            .monospacedDigit()
                            .foregroundStyle(Palette.a700)
                            .frame(width: timeColumn, alignment: .leading)
                            .padding(.top, 3)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(Typeface.heading(17, .semibold))
                                .foregroundStyle(Palette.text)
                            // Typed by hand now, so it is routinely empty — and
                            // an empty `Aside` still draws its line spacing.
                            if !item.note.isEmpty {
                                Aside(text: item.note, size: 12)
                            }
                        }
                    }
                    .padding(.vertical, Space.s3)

                    Rule()
                }
            } else {
                Aside(text: "No hours pinned to this one.", size: 12.5)
                    .padding(.vertical, Space.s3)
                Rule()
            }

            if let title = plan?.lodgingTitle {
                Panel {
                    Mono("Tonight", size: 9.5)
                    Text(title)
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(Palette.text)
                        .padding(.top, 4)
                    if let note = plan?.lodgingNote {
                        Aside(text: note, size: 12).padding(.top, 2)
                    }
                }
                .padding(.top, Space.s3)
            }

            nightAndMoments

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Mono("Spent this day", size: 10)
                    Spacer()
                    Text(store.homeText(store.expenses(onDay: day).reduce(0) { $0 + store.inHome($1) }))
                        .font(Typeface.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Palette.a700)
                }
                RateStamp(size: 11)
            }
            .padding(.top, Space.s4)
        }
        .sheet(isPresented: $editing) {
            DayPlanEditorView(day: day, city: cityName)
        }
        .sheet(isPresented: $writingNight) {
            TonightEntryView(day: day)
        }
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .moments(let day): MomentsView(day: day)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The rest of the day

    /// That night's page and that day's moments, each a worded row (§5.1).
    ///
    /// The page is this phone's own — journals don't travel — so it is offered
    /// only where it could be written: a day that has come, on a traveller's
    /// live trip. A page already written is always offered.
    @ViewBuilder
    private var nightAndMoments: some View {
        let entry = store.myEntries.first { $0.dayNumber == day }
        let canWrite = !isReadOnly && store.isLive && !store.isObserver && day <= store.trueDayNumber
        let moments = store.moments(onDay: day)

        if entry != nil || canWrite {
            linkRow(label: "That night's page", title: entry.map(nightSummary) ?? "Not written yet",
                    verb: entry == nil ? "write it" : "open") { writingNight = true }
                .padding(.top, Space.s3)
            Rule()
        }
        if !moments.isEmpty {
            linkRow(label: "Moments that day",
                    title: Formatting.spelledCount(moments.count, "moment"),
                    verb: "see them") { destination = .moments(day) }
                .padding(.top, entry != nil || canWrite ? 0 : Space.s3)
            Rule()
        }
    }

    private func linkRow(label: String, title: String, verb: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Mono(label, size: 9.5)
                    Text(title)
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                }
                Spacer(minLength: Space.s2)
                Mono(verb, size: 10, color: Palette.a700)
            }
            .padding(.vertical, Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func nightSummary(_ entry: JournalEntry) -> String {
        let photos = (entry.hasPhoto ? 1 : 0) + entry.extraPhotoIDs.count
        return photos == 0 ? "Written"
            : "Written · \(Formatting.spelledCount(photos, "photo").lowercased())"
    }

    /// The stop covering this day, and only then what the plan was written
    /// about.
    ///
    /// The segment first. Plans are filed under their stop now and move with
    /// it, but `plan?.city` is still only what the day was written *about* —
    /// and it only answers for a day no segment covers.
    private var cityName: String {
        // `places` drops blanks, so `first` is genuinely nil for a stop nobody
        // named and the fallback below actually runs. Splitting the raw title
        // returned `[""]` for the same case, so `plan?.city` could never fire —
        // the documented behaviour was unreachable.
        segment.places.first ?? plan?.city ?? segment.title
    }
}
