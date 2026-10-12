import SwiftUI

/// K1 · the shelf. Past trips are spines, because the output of this app is
/// books.
///
/// Only one trip is ever live. That is a product decision and a sync decision
/// at the same time: archived trips don't sync, don't notify and don't drop
/// pins, so a round still ships one payload however many books are on the
/// shelf.
///
/// It is two screens drawn by one view. With a trip open, it is reached from
/// Papers and its one action is finishing that trip. Once the trip is closed,
/// `RootView` puts it in place of the tabs: the app sits **between trips**,
/// and the one action is the next one. It used to stay in the tabs, drawn as
/// if still running, with the same trip on the shelf twice ("live" spine
/// tagged "closed", then again as an archived row). The only way on from
/// there was a second flow that asked for everything onboarding asks for,
/// except the itinerary.
struct ShelfView: View {
    @EnvironmentObject private var store: TripStore
    @State private var reading: ShelvedTrip?
    @State private var remembering: MemoryOpening?
    @State private var finishing = false
    /// The trip `closeTrip()` just put away, landing on the shelf. Held here
    /// for as long as this screen is up; `justShelved` on the store is the
    /// one-shot signal, and taking it is what stops the landing replaying.
    @State private var arriving: ShelvedTrip?
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The plan open for editing, in the keyless store that sketches it.
    @State private var planning: PlanSession?

    private struct PlanSession: Identifiable {
        let id = UUID()
        let store: TripStore
    }

    /// Sketched ahead, and not by the observer, who sets no trip parameters.
    private var plan: ShelvedTrip? { store.library.plan }
    private var canPlan: Bool { !store.isObserver }

    private var live: TripSummary { store.summary }
    private var archived: [ShelvedTrip] { store.library.byRecency }
    /// Between trips: the trip on the phone is closed, so it is on the shelf
    /// with the others and not drawn a second time as the live one.
    private var isBetween: Bool { !store.isLive }

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: isBetween ? .hidden : .syncState) {
                Mono(countLine, size: 10.5)

                Display(text: isBetween ? "Where next?" : "The shelf", size: 38)
                    .padding(.top, 8)
                    .padding(.bottom, Space.s3)

                if !isLanding {
                    memory.padding(.bottom, Space.s3)
                }

                spines

                Aside(text: isBetween
                          ? "Thickness is page count. Tap one to open it again."
                          : "Thickness is page count. The tall one is still being written.",
                      size: 11)
                    .padding(.top, Space.s1)

                if let arriving {
                    VStack(alignment: .leading, spacing: 3) {
                        Mono("Put away today", size: 9.5, color: Palette.a700)
                        Aside(text: arriving.summary.shelvedLine, size: 13)
                    }
                    .padding(.top, Space.s3)
                    .opacity(landed ? 1 : 0)
                    .gentleAnimation(.easeOut(duration: 0.4).delay(0.15), value: landed)
                }

                if isLanding {
                    memory.padding(.top, Space.s3)
                }

                SectionRule(top: Space.s4, bottom: Space.s2)

                if !isBetween {
                    liveRow
                }

                if canPlan {
                    if !isBetween { Rule() }
                    planRow
                }

                ForEach(Array(archived.enumerated()), id: \.element.id) { position, trip in
                    if position > 0 || !isBetween || canPlan { Rule() }
                    Button { reading = trip } label: {
                        summaryRow(trip.summary)
                    }
                    .buttonStyle(.plain)
                }

                Panel {
                    Mono(isBetween ? "Nothing is open" : "One at a time", size: 9.5)
                    Text(isBetween
                         ? "Every trip here is a book you can read. The next one starts where the first one did — who's holding the phone, its name, the dates and where you're going — with the names, the money and the show-this cards already filled in."
                         : "Only the live trip syncs, gets a nightly prompt, or drops pins. Archived ones are just books you can read.")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s3)
            }

            footer
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s2)
                .background(Palette.bg)
        }
        .background(Palette.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reading) { trip in ArchivedTripView(trip: trip) }
        .sheet(item: $remembering) { opening in MemoryBookView(opening: opening) }
        .sheet(isPresented: $finishing) { FinishTripView() }
        .sheet(item: $planning) { session in PlanTripView(plan: session.store) }
    }

    /// The plan's row, or the way to make one. Between trips with a plan, the
    /// footer is where it starts; this row is where it is changed.
    @ViewBuilder
    private var planRow: some View {
        if let plan {
            Button { openPlan() } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.summary.displayName)
                            .font(Typeface.heading(18, .semibold))
                            .foregroundStyle(Palette.text)
                            .multilineTextAlignment(.leading)
                        Aside(text: planLine(plan.summary), size: 11.5, color: Palette.n600)
                    }
                    Spacer(minLength: 8)
                    Tag(text: "planned")
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change the plan")
        } else {
            Button { openPlan() } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isBetween ? "Plan it for later" : "Plan the next trip")
                            .font(Typeface.heading(17, .semibold))
                            .foregroundStyle(Palette.text)
                        Aside(text: isBetween
                                  ? "Sketch it now, start it when you're ready"
                                  : "Sketch it now, start it when this one's on the shelf",
                              size: 11.5, color: Palette.n600)
                    }
                    Spacer(minLength: 8)
                    Mono("plan", size: 10, trackingRatio: 0.08, color: Palette.a700)
                }
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// "Starts in 43 days · VN · 14 days". The countdown is the store's, so
    /// the row and anything else that says it agree.
    private func planLine(_ summary: TripSummary) -> String {
        let when = store.planCountdown.map { $0.hasPrefix("was") ? $0 : "starts \($0)" } ?? ""
        return [when, summary.routeLine].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func openPlan() {
        guard let sketch = store.openPlan() ?? store.makePlan() else { return }
        planning = PlanSession(store: sketch)
    }

    /// One action, whichever screen this is. Between trips it starts the next
    /// one, which hands the phone to `ArrivalFlow` by clearing `hasOpened`.
    /// With a trip open it finishes that one, on a sheet that says what
    /// finishing costs before it does it.
    @ViewBuilder
    private var footer: some View {
        if isBetween, let plan {
            // The plan is what was waiting for this moment, so it is the
            // obvious button; something else is still one tap, and keeps it.
            VStack(spacing: Space.s1) {
                OutlineButton(title: "Start \(plan.summary.displayName)", minHeight: 52, size: 16) {
                    withGentleAnimation(.easeInOut(duration: 0.3)) { store.beginNextTrip() }
                }
                Button {
                    withGentleAnimation(.easeInOut(duration: 0.3)) { store.beginNextTrip(usingPlan: false) }
                } label: {
                    Mono("start something else instead", size: 10, trackingRatio: 0.08,
                         color: Palette.a700)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if isBetween {
            OutlineButton(title: "Start the next trip", minHeight: 52, size: 16) {
                withGentleAnimation(.easeInOut(duration: 0.3)) { store.beginNextTrip() }
            }
        } else if store.hasOpened {
            OutlineButton(title: "Finish this trip", minHeight: 48,
                          border: Palette.divider, foreground: Palette.text) {
                finishing = true
            }
        }
    }

    /// While a trip is landing, "a year ago today" moves below it. Above, at
    /// an accessibility size it pushed the shelf and the line under the fold,
    /// so the moment happened where nobody could see it. Also asks the
    /// store's pending signal, so the panel is already below on the first
    /// frame rather than jumping there when the landing is taken.
    private var isLanding: Bool {
        isBetween && (arriving != nil || store.justShelved != nil)
    }

    @ViewBuilder
    private var memory: some View {
        let memories = store.library.memories(on: store.now)
        if !memories.isEmpty, !store.isObserver {
            MemoryPanel(memories: memories) { remembering = $0 }
        }
    }

    // MARK: - Spines

    private var spines: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if !isBetween {
                spine(live, isLive: true)
            }
            ForEach(archived) { trip in
                Button { reading = trip } label: { spine(trip.summary, isLive: false) }
                    .buttonStyle(.plain)
                    .modifier(Landing(active: arriving?.id == trip.id, landed: landed))
            }
            // The next one, not yet a book: at the end, dashed, and empty.
            if let plan, canPlan {
                Button { openPlan() } label: {
                    SpineView(summary: plan.summary, isLive: false, isPlanned: true)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 212, alignment: .bottom)
        // The landing spine starts above this frame and drops into it, so it
        // comes in from the top of the shelf rather than across the panel and
        // the masthead above. Nothing at rest reaches the edge: the tallest
        // spine is 196 of these 212 points.
        .clipped()
        .overlay(alignment: .bottom) { Rule(color: Palette.text) }
        .onAppear(perform: land)
    }

    /// The moment the trip goes on the shelf.
    ///
    /// Only between trips, and only for the trip `closeTrip()` just named —
    /// taken from the store, so the landing plays once however often this
    /// screen is drawn. Late, so the root's cross-fade from the tabs has
    /// finished and the drop is something somebody sees. With Reduce Motion
    /// the book is simply there, and the haptic still says it landed.
    private func land() {
        guard isBetween, arriving == nil,
              let id = store.takeJustShelved(),
              let trip = archived.first(where: { $0.id == id }) else { return }
        arriving = trip
        guard !reduceMotion else {
            landed = true
            settle(trip)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                landed = true
            } completion: {
                settle(trip)
            }
        }
    }

    private func settle(_ trip: ShelvedTrip) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIAccessibility.post(notification: .announcement,
                             argument: "\(trip.summary.displayName) is on the shelf. \(trip.summary.shelvedLine)")
    }

    private func spine(_ summary: TripSummary, isLive: Bool) -> some View {
        SpineView(summary: summary, isLive: isLive)
    }

    // MARK: - Rows

    private var liveRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(live.displayName)
                    .font(Typeface.heading(18, .semibold))
                    .foregroundStyle(Palette.text)
                Aside(text: live.routeLine, size: 11.5, color: Palette.n600)
            }
            Spacer(minLength: 8)
            Tag(text: "live", active: true)
        }
        .padding(.vertical, 11)
    }

    private func summaryRow(_ summary: TripSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName)
                    .font(Typeface.heading(18, .semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.leading)
                Aside(text: summary.routeLine,
                      size: 11.5, color: Palette.n600)
            }
            Spacer(minLength: 8)
            Tag(text: "archived")
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var countLine: String {
        let total = archived.count + (isBetween ? 0 : 1)
        let count = Formatting.spelledCount(total, "trip")
        return isBetween ? "Between trips · \(count.lowercased())" : count
    }
}

/// A spine dropping into its slot.
///
/// Applied *outside* `spine(_:isLive:)`, whose frame, rotation and clip are
/// arranged in an order that matters (see its doc). The offset is a render
/// transform too, so the slot keeps its layout space the whole way down and
/// the books either side never move.
private struct Landing: ViewModifier {
    let active: Bool
    let landed: Bool

    func body(content: Content) -> some View {
        let falling = active && !landed
        content
            .rotationEffect(.degrees(falling ? -6 : 0), anchor: .bottom)
            .offset(y: falling ? -212 : 0)
            .opacity(falling ? 0 : 1)
    }
}

/// One book on the shelf. Drawn by the shelf and by the setup step, where
/// the next trip's spine grows while it is being named, so both draw the
/// same book.
struct SpineView: View {
    /// The name fits the book, never the other way round.
    ///
    /// A spine's height is its trip's length and its thickness is its page
    /// count — the caption under this row says so out loud — so a long name on
    /// a short trip has to be made to fit rather than given a taller book.
    ///
    /// It used to `.fixedSize()` *after* the rotation. Rotation is a
    /// render-time transform and doesn't change layout size, so `fixedSize`
    /// read the label's **unrotated** ideal width: the whole string, one line,
    /// full point size, uncompressible. Nothing clipped it either, so a
    /// three-day trip called something long painted over its neighbours, through
    /// the baseline rule and up into the masthead. The width frame *before* the
    /// rotation is the fix — it is what gives `minimumScaleFactor` and the
    /// ellipsis a box to work in.
    let summary: TripSummary
    let isLive: Bool
    /// What the spine says instead of `summary.spine`. The setup step passes
    /// the year alone while the trip has no name: the fallback name is words
    /// for a sentence ("Finish this trip?"), and on a book it read as a title
    /// nobody gave.
    var label: String? = nil
    /// Sketched ahead and not begun: no paper, a dashed edge, no ribbon. A
    /// book that doesn't exist yet shouldn't look like one that does.
    var isPlanned = false

    var body: some View {
        Text(label ?? summary.spine)
            // Capped for the reason `Mono.growthCap` is: this is type in a
            // fixed slot. Uncapped, a 13pt spine reaches 31pt at the largest
            // accessibility size — and its *line height* then exceeds the 26pt
            // width of a thin book, so it bleeds sideways as well as endways,
            // against a `spineHeight` that is a plain constant. Nothing is lost
            // to a reader who needs the size: the accessibility label below
            // reads the whole name and year however small this draws.
            .font(Typeface.heading(isLive ? 15 : 13, .semibold).capped(at: 1.3))
            .foregroundStyle(isLive ? Palette.text : isPlanned ? Palette.n600 : Palette.n700)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .truncationMode(.tail)
            // The label's own long axis, which the rotation turns into the
            // spine's height. Inset so the type doesn't touch either end board.
            .frame(width: summary.spineHeight - 16)
            .fixedSize(horizontal: false, vertical: true)
            .rotationEffect(.degrees(90))
            .frame(width: summary.spineWidth, height: summary.spineHeight)
            // The guarantee behind the arithmetic. Shrinking and truncating are
            // what make it fit; this is what means it cannot paint over the
            // book beside it even if one day they don't.
            .clipped()
            .background(isPlanned ? Color.clear : Palette.n100)
            .overlay(alignment: .leading) {
                if !isPlanned {
                    Rectangle().fill(isLive ? Palette.accent : Palette.n400).frame(width: 4)
                }
            }
            .overlay {
                if isPlanned {
                    Rectangle().strokeBorder(Palette.n500, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else {
                    Rectangle().strokeBorder(Palette.divider, lineWidth: 1)
                }
            }
            .accessibilityLabel("\(summary.displayName), \(summary.year), \(isLive ? "live" : isPlanned ? "planned" : "archived")")
    }
}

// MARK: - K8 · an archived trip

/// Everything, frozen. Every figure comes from the snapshot rather than the
/// live store, so an archived trip cannot drift and cannot be edited by
/// accident.
struct ArchivedTripView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: ShelvedTrip

    /// The closed trip, opened.
    ///
    /// A second store, built from the frozen snapshot with **no persistence
    /// key**, so nothing it does can reach disk. Pouring an archive into the
    /// running store instead would fire every `didSet { save() }` and write the
    /// archive over the live trip.
    ///
    /// A `SilentRitualScheduler` for the same class of reason: the real one
    /// talks to the shared notification centre, so an archived trip calling
    /// `cancelAll()` would cancel the *live* trip's evening prompt.
    @StateObject private var archived: TripStore
    /// False when the blob wouldn't decode — a trip written by a much older
    /// build, or one that got truncated. Better to say so than to open an empty
    /// book with somebody's name on it.
    private let opened: Bool

    init(trip: ShelvedTrip) {
        self.trip = trip
        let decoded = TripSnapshot.decode(trip.snapshot)
        opened = decoded != nil
        // A nil snapshot leaves the store on an empty trip, which is what the
        // "couldn't be read" branch below draws.
        _archived = StateObject(wrappedValue: TripStore(storeKey: nil,
                                                        snapshot: decoded,
                                                        ritual: SilentRitualScheduler()))
    }

    private var summary: TripSummary { trip.summary }

    var body: some View {
        NavigationStack {
            content
        }
        .environmentObject(archived)
        .environment(\.isReadOnly, true)
    }

    private var content: some View {
        VStack(spacing: 0) {
            SheetHeader(title: summary.displayName, trailing: "Close") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Mono("Archived · \(summary.countries.first ?? "—")", size: 10.5)
                        Spacer()
                        Tag(text: "frozen")
                    }

                    Display(text: summary.displayName, size: 34)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                    Aside(text: datesLine, size: 12.5)
                        .padding(.bottom, Space.s3)

                    // The trip's one picture: the trail as the book draws it,
                    // the same hairlines as its pages, its cover and the
                    // replay. Nothing when there was nowhere to draw between.
                    if opened, let map = archived.bookMap() {
                        TrailPicture(map: map, height: 200, labelsAll: true)
                            .accessibilityLabel("The trail of \(summary.displayName)")
                            .padding(.bottom, Space.s3)
                    }

                    SectionRule(top: Space.s2, bottom: Space.s2)

                    // No "printed" / "never printed": the app no longer
                    // orders prints, and the old orders never reached one.
                    factRow("The book", "\(summary.pageCount) pp")
                    factRow("Nights away", "\(summary.nightsAway)")
                    factRow("Stamps", "\(summary.stampsEarned) of \(summary.stampsTotal)")
                    factRow("Spent", summary.homeCurrency.formatRounded(summary.spentHome))
                    factRow("Letters", lettersLine, last: true)

                    // The three things worth going back into a finished trip
                    // for. They read the frozen snapshot, so the book, the
                    // letters and the ledger stay reachable after it closes.
                    if opened {
                        SectionRule(top: Space.s3, bottom: Space.s2)

                        Mono("Open it again", size: 10).padding(.bottom, 2)

                        // No figures on these rows. The frozen ones are listed
                        // directly above, and restating them here from the
                        // reopened trip put two different numbers for the same
                        // thing on one screen: "12 pp" against "3 pages"
                        // (spreads versus entries), and a spend that had been
                        // reconverted at today's rates rather than the ones it
                        // closed with. The summary is the authority for what
                        // this trip was; these rows are just the way in.
                        //
                        // The trail leads, because where they went is the first
                        // thing anybody reopens a finished trip for. There used
                        // to be a `HatchPanel` here captioned "the trail as it
                        // was · maps deleted, route kept" — a drawing of a
                        // screen that could not be opened, on a shelf whose own
                        // copy promises "you can open every screen of it
                        // whenever you like". `TrailView` was already read-only
                        // aware, so the panel was the only thing standing in
                        // for it.
                        browseRow("The trail") { TrailView(embedsNavigation: false) }
                        if !archived.trailReplay.isEmpty {
                            browseRow("Replay the trail") {
                                Screen { TrailReplayView() }
                                    .navigationTitle("")
                                    .navigationBarTitleDisplayMode(.inline)
                            }
                        }
                        if archived.features.printedBooks || archived.nightsWritten > 0 {
                            browseRow("The book") { BookPreviewView() }
                        }
                        if archived.lettersVisible {
                            browseRow("Letters") { LettersView() }
                        }
                        if archived.features.sharedLedger {
                            browseRow("The ledger", last: true) {
                                MoneyView(embedsNavigation: false)
                            }
                        }
                    }

                    Panel {
                        Text(opened
                             ? "Nothing here can be edited. It's the trip as you left it, except the papers: their numbers and scans were cleared when it closed."
                             : "This trip's contents couldn't be read — the summary above is all that's left of it. Nothing was deleted; a newer build may be able to open it.")
                            .font(Typeface.body(12.5))
                            .foregroundStyle(Palette.n700)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Space.s3)

                    if let synced = summary.lastSyncedAt {
                        Mono("last synced \(synced.shortDate), \(synced.text("HH:mm"))",
                             size: 9, trackingRatio: 0.1, color: Palette.n500)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, Space.s2)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s6)
            }
        }
        .background(Palette.bg)
    }

    private var datesLine: String {
        var text = summary.datesLine
        if let closed = summary.closedOn { text += " · closed \(closed.shortDayMonth)" }
        return text
    }

    private var lettersLine: String {
        let total = summary.lettersDelivered + summary.lettersSealed
        guard total > 0 else { return "none this trip" }
        return "\(summary.lettersDelivered) of \(total) landed"
    }

    /// A way back into one part of a closed trip. Same shape as `factRow`, but
    /// it goes somewhere.
    private func browseRow<Destination: View>(
        _ title: String, last: Bool = false,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                destination()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Mono("open", size: 10, trackingRatio: 0.08, color: Palette.a700)
                }
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !last { Rule() }
        }
    }

    private func factRow(_ title: String, _ value: String, accent: Bool = false, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(value)
                    .font(Typeface.mono(11))
                    .monospacedDigit()
                    .foregroundStyle(accent ? Palette.a700 : Palette.n600)
            }
            .padding(.vertical, 8)
            if !last { Rule() }
        }
    }
}

/// "A year ago today" — one memory from the shelf, and the way back into
/// the trip it came from. Drawn on Today and on the shelf, the same view in
/// both, so the two can't come to disagree about what a memory looks like.
struct MemoryPanel: View {
    let memories: [Memory]
    let open: (MemoryOpening) -> Void
    @EnvironmentObject private var store: TripStore

    var body: some View {
        if let first = memories.first, let trip = store.library.trip(first.tripID) {
            let more = memories.filter { $0.tripID == first.tripID }.count - 1
            Button { open(MemoryOpening(trip: trip, memory: first)) } label: {
                Panel {
                    HStack(alignment: .top, spacing: Space.s2) {
                        VStack(alignment: .leading, spacing: 4) {
                            Mono(first.heading, size: 9.5, color: Palette.a700)
                            if !first.words.isEmpty {
                                Text(first.words)
                                    .font(Typeface.heading(17).italic())
                                    .foregroundStyle(Palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Mono([first.place, first.tripName].compactMap { $0 }.joined(separator: " · "),
                                 size: 9.5, trackingRatio: 0.08)
                            if more > 0 {
                                Aside(text: more == 1 ? "and one more from that trip"
                                      : "and \(more) more from that trip", size: 11.5)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if first.photoID != nil {
                            JournalPhoto(photoID: first.photoID, side: 56, usesThumbnail: true)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(first.tripName)'s book at that page")
        }
    }
}

/// A memory, and the trip it came from: what tapping one opens.
struct MemoryOpening: Identifiable {
    let trip: ShelvedTrip
    let memory: Memory
    var id: UUID { memory.id }
}

/// "A year ago today", opened at the night it remembers.
///
/// It used to open the archived trip's page, a screen of figures with the book
/// one more tap and a swipe through every spread away — from a panel showing
/// one night's words. Now it is that night's spread, in the book, with the
/// whole trip one tap off. A memory the book doesn't print — a trip that
/// printed no book, a page since removed — opens the trip as before.
struct MemoryBookView: View {
    @Environment(\.dismiss) private var dismiss
    let opening: MemoryOpening
    /// The keyless reader store, as `ArchivedTripView` builds it and for the
    /// same reasons: nothing it does can reach disk, and a silent ritual so it
    /// can't cancel the live trip's evening prompt.
    @StateObject private var archived: TripStore
    private let opened: Bool
    @State private var showingTrip = false

    init(opening: MemoryOpening) {
        self.opening = opening
        let decoded = TripSnapshot.decode(opening.trip.snapshot)
        opened = decoded != nil
        _archived = StateObject(wrappedValue: TripStore(storeKey: nil, snapshot: decoded,
                                                        ritual: SilentRitualScheduler()))
    }

    var body: some View {
        // Read off the cached plan, so finding the page costs nothing extra.
        if !showingTrip, opened, let spread = archived.bookPlan.spreadIndex(containing: opening.memory.id) {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Mono(opening.memory.heading, size: 10.5)
                        Spacer()
                        Button { showingTrip = true } label: {
                            Mono("the whole trip", size: 10.5, color: Palette.a700)
                                .padding(.trailing, Space.s3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { dismiss() } label: {
                            Mono("Close", size: 10.5, color: Palette.a700).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, Space.gutter)
                    BookPreviewView(startAt: spread)
                }
                .background(Palette.bg)
            }
            .environmentObject(archived)
            .environment(\.isReadOnly, true)
        } else {
            ArchivedTripView(trip: opening.trip)
        }
    }
}
