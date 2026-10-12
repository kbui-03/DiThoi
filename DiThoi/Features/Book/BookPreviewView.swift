import SwiftUI

/// I1 · the book, page by page.
///
/// The thing every journal page has been written toward, finally visible as an
/// object. Swipe turns a spread; the contents list jumps to a country.
struct BookPreviewView: View {
    @EnvironmentObject private var store: TripStore
    /// Set when the shelf reopens a closed trip. The book still draws in full —
    /// it is the reason to reopen one — and the export still runs, because
    /// writing a PDF touches nothing in the trip. What it changes is the word
    /// "draft" and what `PrintFileView` is allowed to offer.
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var index: Int
    @State private var showingPrintFile = false
    /// The book full size, in landscape.
    @State private var reading = false
    /// The day under the finger while the page bar is being scrubbed; nil
    /// otherwise, which is what takes the bubble away.
    @State private var scrubDay: Int?

    /// - Parameter startAt: the spread to open on. Zero everywhere but the
    ///   debug route, which takes `-spread n` so any spread can be photographed.
    /// - Parameter holdingScrubAt: the debug route's `-scrubDay n`, which
    ///   draws the bubble held — `simctl` can't hold a drag still.
    init(startAt: Int = 0, holdingScrubAt: Int? = nil) {
        _index = State(initialValue: startAt)
        _scrubDay = State(initialValue: holdingScrubAt)
    }

    var body: some View {
        // Built once per pass and handed down.
        //
        // It used to be a computed property reading `store.bookPlan`, which is
        // itself derived — so every mention of `plan` below re-sorted every
        // page, re-walked every leg and rebuilt every section. `body` mentions
        // it nine times.
        let plan = store.bookPlan

        return VStack(spacing: 0) {
            ScreenContext(tag: .syncState)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Mono("\(store.myName)'s copy · \(isReadOnly ? "as it closed" : "draft")", size: 10.5)
                        Spacer()
                        Mono("\(plan.pageCount) pp", size: 10.5, color: Palette.a700)
                    }

                    Display(text: "Your book", size: 34)
                        .padding(.top, 8)
                        .padding(.bottom, Space.s3)

                    if plan.spreads.isEmpty {
                        emptyBook
                    } else {
                        spreads(plan)
                        turner(plan)
                        Aside(text: "Swipe to turn. Tap the book to read it full size.",
                              size: 11)
                            .padding(.top, Space.s1)

                        SectionRule(top: Space.s4)
                        contents(plan)

                        if plan.volumes > 1 {
                            Panel {
                                Mono("\(Formatting.spelledCount(plan.volumes, "volume"))", size: 9.5)
                                Text(volumeLine(plan))
                                    .font(Typeface.body(12.5))
                                    .foregroundStyle(Palette.n700)
                                    .lineSpacing(4)
                                    .padding(.top, 5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, Space.s3)
                        }

                        if plan.skippedDays > 0 {
                            Aside(text: "\(plan.skippedDays) night\(plan.skippedDays == 1 ? "" : "s") without a page. The book closes over them.",
                                  size: 12)
                                .padding(.top, Space.s3)
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, 14)
                .padding(.bottom, Space.s6)
            }

            if !plan.spreads.isEmpty {
                OutlineButton(title: "Export · check the print file", minHeight: 48) {
                    showingPrintFile = true
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s2)
            }
        }
        .background(Palette.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Passed rather than inherited. The flag reaches this screen down a
        // `NavigationStack`, and a sheet is a new presentation — carrying it
        // across by hand is one line and doesn't depend on knowing which
        // environment values cross that boundary.
        .sheet(isPresented: $showingPrintFile) {
            PrintFileView().environment(\.isReadOnly, isReadOnly)
        }
        // Passed rather than inherited, for the same reason as the sheet. It
        // opens on this spread and hands back the one it closed on.
        .fullScreenCover(isPresented: $reading) {
            BookReaderView(spreadID: Binding(
                get: { store.bookPlan.spreads.indices.contains(index) ? store.bookPlan.spreads[index].id : nil },
                set: { id in
                    if let id, let found = store.bookPlan.spreads.firstIndex(where: { $0.id == id }) { index = found }
                }))
                .environmentObject(store)
                .environment(\.isReadOnly, isReadOnly)
        }
    }

    // MARK: - Pieces

    private var emptyBook: some View {
        Panel {
            Mono("Nothing in it yet", size: 9.5)
            Text("The book is the pages. Write one tonight and it starts here.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.n700)
                .lineSpacing(4)
                .padding(.top, 5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func spreads(_ plan: BookPlan) -> some View {
        GeometryReader { geometry in
            TabView(selection: $index) {
                ForEach(Array(plan.spreads.enumerated()), id: \.element.id) { position, spread in
                    BookSpreadView(spread: spread, width: geometry.size.width,
                                   leftPageNumber: BookPlan.leftPage(ofSpreadAt: position))
                        .padding(6)
                        .background(Palette.surface)
                        .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
                        .tag(position)
                        .contentShape(Rectangle())
                        .onTapGesture { reading = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens the book full size")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        // A spread is two 8-inch pages side by side, plus the 6pt frame.
        .aspectRatio(2, contentMode: .fit)
    }

    private func turner(_ plan: BookPlan) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Button { turn(-1, in: plan) } label: {
                    Mono(index > 0 ? "← \(pageLabel(index - 1, in: plan))" : " ", size: 9.5,
                         trackingRatio: 0.1, color: Palette.a700)
                        .frame(minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Spacer()
                Mono(index == 0 || index == plan.spreads.count - 1 ? "page \(pageLabel(index, in: plan))" : "pages \(pageLabel(index, in: plan))",
                     size: 9.5, trackingRatio: 0.1)
                Spacer()

                Button { turn(1, in: plan) } label: {
                    Mono(index < plan.spreads.count - 1 ? "\(pageLabel(index + 1, in: plan)) →" : " ",
                         size: 9.5, trackingRatio: 0.1, color: Palette.a700)
                        .frame(minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(index >= plan.spreads.count - 1)
            }

            scrubber
        }
        .padding(.top, Space.s1)
    }

    // MARK: - Scrubbing by date

    /// The page bar, as a timeline of the trip.
    ///
    /// It used to be a 3pt progress bar through the spreads, and nothing but
    /// a picture. Now it is dragged: across it is day 1 to the last day — the
    /// trip mark's axis, so the middle of the bar is the middle of the trip,
    /// not the middle of the page count — and the book follows the finger,
    /// landing on the night of that day or the next one written. The bubble
    /// says which, including "no page".
    private var scrubber: some View {
        let dayCount = max(store.dayCount, 1)
        let shown = scrubDay ?? currentDay
        let fraction = dayCount > 1 ? Double(shown - 1) / Double(dayCount - 1) : 1
        return GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.n300).frame(height: 3)
                Rectangle().fill(Palette.a400).frame(width: width * fraction, height: 3)
                if scrubDay != nil {
                    Circle().fill(Palette.accent)
                        .frame(width: 13, height: 13)
                        .offset(x: width * fraction - 6.5)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if let scrubDay {
                    Mono(store.scrubLabel(forDay: scrubDay), size: 9.5, trackingRatio: 0.1, color: Palette.bg)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Palette.text)
                        // Slides along with the finger and never off either
                        // end: its left edge sits at the same fraction of the
                        // room it has as the day is of the trip.
                        .alignmentGuide(.leading) { d in -fraction * max(width - d.width, 0) }
                        .offset(y: -22)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let along = min(max(value.location.x / max(width, 1), 0), 1)
                        scrub(to: Int((along * Double(dayCount - 1)).rounded()) + 1)
                    }
                    .onEnded { _ in scrubDay = nil }
            )
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityLabel("Jump to a day")
        .accessibilityValue(store.scrubLabel(forDay: currentDay))
        .accessibilityAdjustableAction { direction in
            let nights = store.bookNights
            let target: Int?
            switch direction {
            case .increment: target = nights.first { $0.index > index }?.index
            case .decrement: target = nights.last { $0.index < index }?.index
            @unknown default: target = nil
            }
            if let target { index = target }
        }
    }

    /// The day the spread on screen is a night of — or, for a spread that is
    /// not a night, the last night before it, so turning to a map or the
    /// stamps leaves the bar where the book was.
    private var currentDay: Int {
        store.bookNights.last { $0.index <= index }?.day ?? 1
    }

    private func scrub(to day: Int) {
        guard day != scrubDay else { return }
        scrubDay = day
        guard let target = store.bookSpreadIndex(forDay: day), target != index else { return }
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) { index = target }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// The printed pages a spread holds. The first and last are half-spreads —
    /// the other half is the inside of a cover — so they are one page each.
    private func pageLabel(_ position: Int, in plan: BookPlan) -> String {
        if position == 0 { return "1" }
        let left = BookPlan.leftPage(ofSpreadAt: position)
        if position == plan.spreads.count - 1 { return "\(left)" }
        return "\(left)–\(left + 1)"
    }

    private func turn(_ delta: Int, in plan: BookPlan) {
        let target = index + delta
        guard plan.spreads.indices.contains(target) else { return }
        withGentleAnimation(.easeInOut(duration: 0.28)) { index = target }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func contents(_ plan: BookPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Contents", size: 10).padding(.bottom, 2)

            ForEach(Array(plan.sections.enumerated()), id: \.element.id) { position, section in
                Button {
                    jump(to: section)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.title)
                            .font(Typeface.body(13))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(section.pageRange)
                            .font(Typeface.mono(11))
                            .monospacedDigit()
                            .foregroundStyle(isCurrent(section) ? Palette.a700 : Palette.n600)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if position < plan.sections.count - 1 { Rule() }
            }
        }
    }

    private func isCurrent(_ section: BookSection) -> Bool {
        let page = BookPlan.leftPage(ofSpreadAt: index)
        return page >= section.firstPage && page <= section.lastPage
    }

    /// Facing pages are an even page and the odd one after it, so a section
    /// starting on page `p` is on spread `p / 2`.
    private func jump(to section: BookSection) {
        withGentleAnimation(.easeInOut(duration: 0.28)) { index = section.firstPage / 2 }
    }

    private func volumeLine(_ plan: BookPlan) -> String {
        let pages = plan.pagesPerVolume.map(String.init).joined(separator: " and ")
        return "\(pages) pages. Each one opens and closes like a book of its own, and each is saved as its own file."
    }
}
