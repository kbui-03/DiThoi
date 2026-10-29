import SwiftUI

/// A · Arrival.
///
/// Asks who is holding the phone first, because the answer changes the whole
/// app: the observer's side has no ledger, no journal and no dates of its own.
/// Names are collected on the same screen, so picking a role and correcting
/// what it is called are one step rather than two.
///
/// After that it stops asking for answers somebody already gave. A trip that
/// arrived filled in is confirmed; a trip that arrived empty is set up. Which
/// of those it is comes from `origin` rather than from counting what's inside,
/// so a trip being filled in *during* this flow can't change its own branch
/// halfway.
struct ArrivalFlow: View {
    @EnvironmentObject private var store: TripStore

    /// Which step to open on. Only ever anything but zero under `-screen
    /// arrival -step n`, which is how the flow gets photographed as a flow
    /// rather than as a set of screens with no chrome around them.
    @State private var index: Int
    @State private var adjusting = false
    @State private var planning = false
    @State private var participant: Participant = .one
    @State private var myName = ""
    @State private var theirName = ""
    @State private var recipient: Traveller = .one
    @State private var confirmingSlot = false
    /// Whether this phone has been through here before: a trip on the shelf,
    /// or a name already typed. Captured once, on appear, for the reason
    /// `origin` is stored. The `who` step writes the names, so asking again
    /// halfway would drop `hello` out from under the index and skip a step.
    @State private var returning: Bool?

    init(startAt: Int = 0, returning: Bool? = nil) {
        _index = State(initialValue: startAt)
        _returning = State(initialValue: returning)
    }

    /// Returning, and a traveller, when the flow opened — captured with
    /// `returning` for the same reason. Switching to the observer on the `who`
    /// step must not take `destination` away from behind the index.
    @State private var returningTraveller: Bool?
    /// Set from the destination step's "change", which inserts `who` directly
    /// after it.
    @State private var changingWho = false
    /// What the next trip brought over, and which of it is kept. Captured
    /// once, so a declined budget can be given back.
    @State private var carried: TripStore.CarriedOver?
    @State private var carryChoice = TripStore.CarryChoice()

    /// The registry lives in `Model/SetupSteps.swift`, where the checks can
    /// reach it. This view only draws the steps.
    private typealias Step = SetupStep

    private var context: SetupContext {
        SetupContext(isObserver: participant.isObserver,
                     isPacked: store.origin == .packed,
                     invites: invites,
                     returning: returning ?? false,
                     returningTraveller: returningTraveller ?? false,
                     changingWho: changingWho)
    }

    /// Branches on who they are and on what arrived, so it can't be walked by
    /// adding one to a raw value.
    private var steps: [Step] { SetupStep.steps(for: context) }

    /// Whether this flow ends by offering to pair the two phones.
    ///
    /// Not for the observer: the share is between the two travellers, and the
    /// person at home reaches them through the letter box instead. Not on a
    /// build with no CloudKit either — a step whose only control cannot work is
    /// a step that wastes somebody's first two minutes with the app.
    ///
    /// Safe to read from `steps`, which is recomputed constantly, because
    /// neither half moves during the flow: the transport is chosen once in
    /// `SyncCoordinator.init`. That is the same care `origin` needed and for
    /// the opposite reason — `origin` is stored precisely *because* counting
    /// what's inside the trip would change the answer mid-flow.
    private var invites: Bool {
        !participant.isObserver && store.sync.canInvite
    }

    private var step: Step { steps.indices.contains(index) ? steps[index] : .hello }

    var body: some View {
        ZStack {
            switch step {
            case .hello:
                FirstOpenView { advance() }
                    .transition(.opacity)

            case .destination:
                NextTripDestinationView(carried: carried ?? store.carriedOver,
                                        choice: $carryChoice,
                                        onChangeWho: {
                                            changingWho = true
                                            advance()
                                        },
                                        onContinue: {
                                            if let carried { store.applyCarry(carryChoice, from: carried) }
                                            advance()
                                        })
                    .transition(.opacity)

            case .who:
                WhosePhoneView(kicker: context.returning ? "The next trip" : "First question",
                               participant: $participant,
                               mine: $myName,
                               theirs: $theirName,
                               onChange: { _ in loadNames() },
                               onContinue: {
                                   commitNames()
                                   advance()
                               })
                    .transition(.opacity)

            case .writingTo:
                WritingToView(recipient: $recipient) {
                    commitNames()
                    advance()
                }
                .transition(.opacity)

            case .inside:
                WhatsInsideView(onAdjust: store.origin == .packed && !participant.isObserver
                                    ? { adjusting = true } : nil) { finish() }
                    .transition(.opacity)

            case .dates:
                TripSetupView(mode: .onboarding) { advance() }
                    .transition(.opacity)

            case .itinerary:
                FirstStopView(onPlan: { planning = true }, onStart: { finish() })
                    .transition(.opacity)

            case .invite:
                InviteStepView { store.hasOpened = true }
                    .transition(.opacity)
            }
        }
        .background(Palette.bg)
        .overlay(alignment: .topLeading) { backButton }
        .sheet(isPresented: $adjusting) {
            NavigationStack {
                TripSetupView(mode: .adjust) { adjusting = false }
            }
        }
        .sheet(isPresented: $planning) {
            ItineraryEditorView()
        }
        .alert("Those letters are for \(store.name(for: store.role))",
               isPresented: $confirmingSlot) {
            Button("Keep them, I'm \(store.name(for: store.role))", role: .cancel) {
                participant = Participant(store.role)
                loadNames()
            }
            Button("Throw them away", role: .destructive) {
                applySlot()
            }
        } message: {
            Text(discardWarning)
        }
        .onAppear {
            if returning == nil {
                returning = !store.library.isEmpty
                    || !store.typedName(of: store.participant).isEmpty
            }
            if returningTraveller == nil {
                returningTraveller = (returning ?? false) && !store.participant.isObserver
                    && store.origin != .packed
            }
            if carried == nil { carried = store.carriedOver }
            participant = store.participant
            recipient = store.role
            loadNames()
        }
    }

    /// The way back. `advance()` only ever counts up, so without this the first
    /// answer would be permanent — and the one on the `who` step deletes
    /// letters at the end of the flow.
    ///
    /// Sized to its own text, so it only takes taps in the top-left corner. The
    /// steps below draw their own scrolling content right up to here.
    @ViewBuilder
    private var backButton: some View {
        if index > 0 {
            Button { back() } label: {
                Mono("← back", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                    .frame(height: 44, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .padding(.horizontal, Space.gutter)
            .padding(.top, 4)
            .accessibilityLabel("Back")
        }
    }

    private func advance() {
        withGentleAnimation(.easeInOut(duration: 0.3)) { index = min(index + 1, steps.count - 1) }
    }

    /// `steps` is a computed, branching array and the flow holds an index into
    /// it, so stepping back subtracts from that index — not from a raw value,
    /// which would walk into a step this flow doesn't have.
    private func back() {
        withGentleAnimation(.easeInOut(duration: 0.3)) { index = max(index - 1, 0) }
    }

    private func finish() {
        commitNames()
        // The last chance to say this out loud. Everything up to here can be
        // walked back; this can't.
        guard discardsLetters else {
            applySlot()
            return
        }
        confirmingSlot = true
    }

    /// The slot is taken, and then — if there is one — the flow carries on to
    /// the invitation rather than ending here.
    ///
    /// The order is the point. `commitSlot()` is what settles `role`, and the
    /// invitation names `role.other`; offering it any earlier would put a
    /// name on the link that the next tap could still change.
    ///
    /// `hasOpened` stays false until the last step is actually done with,
    /// because it is what ends the flow — `RootView` draws `ArrivalFlow` for
    /// exactly as long as it is unset.
    private func applySlot() {
        commitSlot()
        if steps.last == .invite && step != .invite {
            advance()
        } else {
            store.hasOpened = true
        }
    }

    /// Whether finishing would throw sealed letters away.
    private var discardsLetters: Bool {
        guard let mine = participant.traveller else { return false }
        return mine != store.role && !store.letters.isEmpty
    }

    private var discardWarning: String {
        let count = store.letters.count
        let addressee = store.name(for: store.role)
        let picked = participant.traveller.map { store.name(for: $0) } ?? myName
        return "\(Formatting.spelledCount(count, "sealed letter", spellingUpTo: 0)) on this phone \(count == 1 ? "was" : "were") addressed to \(addressee). Opening it as \(picked) deletes \(count == 1 ? "it" : "them") — not hides \(count == 1 ? "it" : "them") — and nothing can bring \(count == 1 ? "it" : "them") back."
    }

    /// The typed names, not the display ones. An unset slot has to arrive as an
    /// empty field with a placeholder behind it — loading "Traveller one" as a
    /// value gets typed into rather than replaced.
    private func loadNames() {
        myName = store.typedName(of: participant)
        theirName = participant.traveller.map { store.typedName(for: $0.other) } ?? ""
    }

    /// The reversible half, run on every continue.
    ///
    /// Applied here rather than as the fields are typed in, so backing out
    /// doesn't leave somebody half-renamed. Everything in here can be set again
    /// by going back and coming forward, which is why it is allowed to run more
    /// than once.
    private func commitNames() {
        store.participant = participant
        if let mine = participant.traveller {
            store.rename(mine, to: myName)
            store.rename(mine.other, to: theirName)
        } else {
            // The observer's address. Re-addressing moves where the next drop
            // is posted and deletes nothing.
            store.writeTo(recipient)
            store.renameObserver(to: myName)
        }
    }

    /// The half that cannot be undone, run once, at the end.
    ///
    /// `adopt(_:)` throws away every letter addressed to the slot this phone
    /// used to be, because declining to *draw* somebody else's letters still
    /// leaves them on this disk — which is the thing the addressed channel
    /// exists to stop.
    ///
    /// Split from `commitNames()` by reversibility rather than by convenience:
    /// the `who` step can be walked back, and tapping the wrong role would
    /// otherwise destroy sealed letters before the back button could be
    /// pressed.
    private func commitSlot() {
        guard let mine = participant.traveller else { return }
        store.adopt(mine)
    }
}

// MARK: - A1 · First open

struct FirstOpenView: View {
    @EnvironmentObject private var store: TripStore
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                Mono("Made for two people", size: 10.5, trackingRatio: 0.16, color: Palette.a700)

                Display(text: "Đi\nThôi", size: 78, tracking: -0.03)
                    .padding(.top, 12)

                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: 52, height: 1)
                    .padding(.vertical, 22)

                Text(blurb)
                    .font(Typeface.body(14.5))
                    .lineSpacing(5.5)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.s4)

                Aside(text: "No signal, no account and no password. Just the phone.", size: 13)
                    .padding(.bottom, Space.s6)

                OutlineButton(title: "Open it", minHeight: 52, size: 16, action: onContinue)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .background(Palette.bg)
    }

    /// Counted rather than transcribed, and every clause drops out when its
    /// count is zero — "0 countries, 0 sealed letters" would be a worse first
    /// sentence than not mentioning them.
    private var blurb: String {
        guard store.origin == .packed else {
            return "Two people, however long you're going for. Set the dates, say where you're going, and the rest is worked out from those two answers."
        }
        var clauses = ["\(store.names[.one]) and \(store.names[.two])"]
        if !store.legs.isEmpty {
            clauses.append("\(Formatting.spelledCount(store.legs.count, "country", plural: "countries", spellingUpTo: 0))")
        }
        var text = clauses.joined(separator: ", ") + ". The itinerary is already in."
        if !store.letters.isEmpty {
            text += " \(Formatting.spelledCount(store.letters.count, "letter", spellingUpTo: 0)) \(store.letters.count == 1 ? "is" : "are") sealed inside and open themselves when you arrive somewhere."
        }
        return text
    }
}

// MARK: - A2 · Who's holding this phone, and what they're called

/// The role and the names, on one screen.
///
/// They were two steps, which meant picking a role you could see was labelled
/// wrong and having to continue past it to fix the label. The picker reads from
/// `TripNames`, so the field above and the row below are the same value.
struct WhosePhoneView: View {
    var kicker = "First question"
    @Binding var participant: Participant
    @Binding var mine: String
    @Binding var theirs: String
    var onChange: (Participant) -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: "before you go") {
                Mono(kicker, size: 10.5)

                Display(text: "Who's holding\nthis phone", size: 40)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ParticipantPicker(selection: $participant,
                                  draftName: draftName,
                                  onChange: onChange)

                Panel(border: Palette.accent) {
                    Mono(participant.isObserver ? "What an observer gets" : "What a traveller gets",
                         size: 9.5, color: Palette.a700)
                    Text(explainer)
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s4)

                SectionRule()

                Mono("So it can say your name", size: 10.5)
                    .padding(.bottom, Space.s3)

                ParticipantNames(participant: participant, mine: $mine, theirs: $theirs)

                Aside(text: "Changeable at any point, from the trip screen.", size: 12.5)
                    .padding(.top, Space.s3)
            }

            VStack {
                OutlineButton(title: "That's me", action: onContinue)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
            .background(Palette.bg)
        }
        .background(Palette.bg)
    }

    private var explainer: String {
        participant.isObserver
            ? "Their trail, and the letters you seal for them. No ledger, no journal, no dates of your own, and no record of when a letter was read."
            : "The plan, the shared ledger, your own journal, and whatever has been sealed for you."
    }

    /// The fields below feed the rows above, so a name typed here shows up on
    /// the row it belongs to before anything is committed.
    private func draftName(_ option: Participant) -> String? {
        if option == participant { return mine }
        if let other = participant.traveller?.other, option == Participant(other) { return theirs }
        return nil
    }
}

// MARK: - A2b · Who the letters are for

/// The observer's extra step. The letter box is addressed, so posting to the
/// wrong slot doesn't surface as an error anywhere — the letters simply land
/// where nobody looks for them, and nothing reports back to say so.
struct WritingToView: View {
    @Binding var recipient: Traveller
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: "before they go") {
                Mono("One-way, and only to one of them", size: 10.5)

                Display(text: "Who are you\nwriting to", size: 40)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Aside(text: "Sealed letters go to this phone and no other. The other traveller's copy of the app has no notion of them, including that they exist.",
                      size: 12.5)
                    .padding(.bottom, Space.s3)

                RecipientPicker(recipient: $recipient)

                Panel {
                    Mono("Nothing comes back", size: 9.5)
                    Text("You'll see when a letter's condition has been met, because that can be worked out from the trip itself. You won't see when one was opened, or whether it was.")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s4)
            }

            VStack {
                OutlineButton(title: "Next", action: onContinue)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
            .background(Palette.bg)
        }
        .background(Palette.bg)
    }
}

// MARK: - A3 · What's already inside

struct WhatsInsideView: View {
    @EnvironmentObject private var store: TripStore
    /// Nil for the observer, who owns none of these answers, and for a trip
    /// that arrived empty, where there is nothing yet to disagree with.
    var onAdjust: (() -> Void)?
    var onStart: () -> Void

    private var isObserver: Bool { store.isObserver }

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: "airplane mode") {
                Mono(isObserver ? "Packed before they left" : "Packed before you left", size: 10.5)

                Display(text: "Nothing here\nneeds wifi", size: 40)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                SectionRule(top: 0)

                if isObserver {
                    observerRows
                } else {
                    travellerRows
                }

                Panel(border: Palette.accent) {
                    Mono("One thing to do together", size: 9.5, color: Palette.a700)
                    Text(isObserver ? "Wait for their first pin" : "Pick tonight's meeting point")
                        .font(Typeface.heading(19, .semibold))
                        .foregroundStyle(Palette.text)
                        .padding(.top, 5)
                    Text(isObserver
                         ? "The trail fills in as they go. Nothing here asks them to check in, and nothing reports when a letter was opened."
                         : "Somewhere you can both walk to if the phones die. You'll set a new one each morning.")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s3)
            }

            VStack {
                OutlineButton(title: isObserver ? "Open it" : "Start day one", action: onStart)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
            .background(Palette.bg)
        }
        .background(Palette.bg)
    }

    /// The answers somebody already gave, shown so they can be disagreed with
    /// rather than asked for again.
    @ViewBuilder
    private var travellerRows: some View {
        DetailRow(title: "Dates", titleSize: 17) {
            Mono("\(store.start.shortDate) – \(store.end.shortDate)", size: 10.5,
                 trackingRatio: 0.08, color: Palette.a700)
        }
        DetailRow(title: "That's \(Formatting.spelledCount(store.dayCount, "day", spellingUpTo: 0))", titleSize: 17) {
            Mono("\(store.homeCurrency.formatRounded(store.budgetPerDay))/day",
                 size: 10.5, trackingRatio: 0.08)
        }
        DetailRow(title: "Budget", titleSize: 17) {
            Mono(store.homeCurrency.formatRounded(store.budget), size: 10.5,
                 trackingRatio: 0.08, color: Palette.a700)
        }

        // Sits with the three answers it changes rather than as a second button
        // at the foot, which cost enough of the viewport to clip the panel.
        if let onAdjust {
            Button(action: onAdjust) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Somebody else answered those")
                            .font(Typeface.heading(16, .semibold))
                            .foregroundStyle(Palette.text)
                        Aside(text: "Change the dates, the budget or the currency",
                              size: 11.5, color: Palette.n600)
                    }
                    Spacer()
                    Mono("adjust", size: 10, trackingRatio: 0.08, color: Palette.a700)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rule()
        }

        DetailRow(title: "Itinerary", titleSize: 17) {
            Mono("\(store.legs.flatMap(\.segments).count) stops", size: 10.5,
                 trackingRatio: 0.08, color: Palette.a700)
        }
        if store.features.letters, !store.letters.isEmpty {
            DetailRow(title: "Sealed letters", titleSize: 17) {
                Mono("\(store.letters.count)", size: 10.5, trackingRatio: 0.08, color: Palette.a700)
            }
        }
        DetailRow(title: "Papers", titleSize: 17) {
            Mono("\(store.documents.count)", size: 10.5, trackingRatio: 0.08)
        }
        DetailRow(title: "Show-this cards", titleSize: 17) {
            Mono("\(store.orderedShowCards.count)", size: 10.5, trackingRatio: 0.08)
        }
        DetailRow(title: "Meeting-point plan", titleSize: 17, showsRule: false) {
            Mono("Ready", size: 10.5, trackingRatio: 0.08)
        }
    }

    /// Three rows, because there are only three things the observer is shown.
    /// No dates, no budget, no ledger — not hidden, absent.
    @ViewBuilder
    private var observerRows: some View {
        DetailRow(title: "Their trail", titleSize: 17) {
            Mono("fills in as they go", size: 10.5, trackingRatio: 0.08, color: Palette.a700)
        }
        DetailRow(title: "Letters you've sealed", titleSize: 17) {
            Mono("\(store.sealedByWriter.count)", size: 10.5, trackingRatio: 0.08, color: Palette.a700)
        }
        DetailRow(title: "Read receipts", titleSize: 17, showsRule: false) {
            Mono("none, ever", size: 10.5, trackingRatio: 0.08)
        }
    }
}

// MARK: - A4 · The first stop

/// The last step for a trip that arrived empty. It hands off to the itinerary
/// editor rather than growing a second one — the editor already adds countries
/// and stops, and two ways to build a plan is two ways for it to disagree with
/// itself.
struct FirstStopView: View {
    @EnvironmentObject private var store: TripStore
    var onPlan: () -> Void
    var onStart: () -> Void

    private var stops: Int { store.legs.flatMap(\.segments).count }

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: "before you go") {
                Mono("Last one", size: 10.5)

                Display(text: "Where are\nyou going", size: 40)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Aside(text: "Countries first, then the stops inside them. Nights are what you set; the dates follow and re-flow whenever you move something.",
                      size: 12.5)
                    .padding(.bottom, Space.s3)

                SectionRule(top: 0)

                if store.legs.isEmpty {
                    DetailRow(title: "Nothing planned yet", titleSize: 17, showsRule: false) {
                        Mono("optional", size: 10.5, trackingRatio: 0.08)
                    }
                } else {
                    ForEach(store.legs) { leg in
                        DetailRow(title: leg.country, titleSize: 17) {
                            Mono("\(Formatting.spelledCount(leg.nights, "night", spellingUpTo: 0))", size: 10.5, trackingRatio: 0.08, color: Palette.a700)
                        }
                    }
                }

                Panel {
                    Mono("You can leave it empty", size: 9.5)
                    Text(store.legs.isEmpty
                         ? "The ledger, the papers and the nightly page all work with nowhere in the plan. Add somewhere whenever you know."
                         : "\(Formatting.spelledCount(stops, "stop", spellingUpTo: 0)) across \(Formatting.spelledCount(store.legs.count, "country", plural: "countries", spellingUpTo: 0)), and \(store.itineraryOverrun > 0 ? "that runs \(Formatting.spelledCount(store.itineraryOverrun, "day", spellingUpTo: 0)) past your return date" : "it fits inside your dates").")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s3)
            }

            VStack {
                OutlineButton(title: store.legs.isEmpty ? "Add a country" : "Change the plan",
                              minHeight: 46, size: 15, action: onPlan)
                    .padding(.bottom, Space.s2)
                OutlineButton(title: "Start day one", action: onStart)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
            .background(Palette.bg)
        }
        .background(Palette.bg)
    }
}

// MARK: - A5 · The other phone

/// The step that stops two people making two trips.
///
/// It exists because of a failure that had no symptom. Every phone mints its own
/// `tripID` on first launch, `SyncMerge` refuses a payload whose id doesn't
/// match, and nothing anywhere else moves an id between phones — so two people
/// who each walked this flow ended up with two trips that could never meet,
/// while both phones reported syncing perfectly. The machinery to cure it lives
/// in Papers, and asking here is what stops somebody needing the cure: this is
/// the moment both people are together, deciding to take a trip, and the moment
/// before either has typed anything worth losing.
///
/// Last, and after `commitSlot()`, because the person being invited is
/// `role.other` and `role` is not final until the slot is taken.
///
/// Skippable, in the flow's own idiom — `FirstStopView` lets somebody start with
/// no itinerary at all. Nobody should be held at a screen about a second phone
/// that may not exist yet.
struct InviteStepView: View {
    @EnvironmentObject private var store: TripStore
    var onStart: () -> Void

    @State private var link: InviteLink?
    @State private var making = false
    @State private var failure: String?
    /// Set once the share sheet has closed. It does **not** claim the link was
    /// sent — `UIActivityViewController` closing means the sheet is finished
    /// with, not that anything arrived. It only changes which button is the
    /// obvious one, which is a statement about this screen and not about the
    /// other phone.
    @State private var offered = false

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: "before you go") {
                Mono("One more thing", size: 10.5)

                Display(text: "Is \(store.otherName)\ncoming too?", size: 40)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Aside(text: "Send them a link and both phones carry the same trip — the money, the plans, the trail and tonight's meeting point, either of you can change any of it. Without it you each get a trip of your own, and they never meet.",
                      size: 12.5)
                    .padding(.bottom, Space.s3)

                SectionRule(top: 0)

                // No "they join as ⟨name⟩" row here. It was one, and the
                // headline three lines above already says the name — so it
                // read "Is Lynn coming too? … They join as Lynn", which is a
                // sentence that costs a row and answers nothing. What the slot
                // is actually for is keeping the two phones apart, and that is
                // the sentence below.
                DetailRow(title: "The link carries who they are",
                          subtitle: "So neither phone has to guess which of you is which — and neither of you ends up filed as the other.",
                          titleSize: 17, showsRule: false) { EmptyView() }

                Panel {
                    Mono("You can do this later", size: 9.5)
                    Text("It lives in Papers, under Trip, for whenever they're standing next to you.")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s3)

                if let failure {
                    Text(failure)
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(4)
                        .padding(.top, Space.s3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack {
                OutlineButton(title: making ? "Asking iCloud…"
                                  : offered ? "Send the link again"
                                            : "Send \(store.otherName) the link",
                              minHeight: 46, size: 15) { makeInvitation() }
                    .disabled(making)
                    .padding(.bottom, Space.s2)
                OutlineButton(title: offered ? "Start day one" : "Not now", action: onStart)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
            .background(Palette.bg)
        }
        .background(Palette.bg)
        .sheet(item: $link, onDismiss: { offered = true }) { link in
            ShareSheet(items: [link.url])
        }
    }

    private func makeInvitation() {
        guard !making else { return }
        making = true
        failure = nil
        Task { @MainActor in
            do {
                let url = try await store.sync.invitation(to: store.tripID,
                                                          named: store.displayName,
                                                          inviting: store.role.other)
                link = InviteLink(url: url)
            } catch {
                failure = error.localizedDescription
            }
            making = false
        }
    }
}
