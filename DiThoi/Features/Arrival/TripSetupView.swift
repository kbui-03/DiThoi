import SwiftUI

/// A3 · Trip setup. The three answers everything else is computed from: when
/// they go, what they've got, and the currency they think in.
///
/// One screen, three jobs — asking for the first time, being reopened mid-flow
/// to change what somebody else filled in, and living in settings for the rest
/// of the trip. `Mode` says which, rather than being inferred from whether a
/// closure is nil: the three differ in what they are allowed to offer.
struct TripSetupView: View {
    enum Mode {
        /// A blank trip, being answered for the first time.
        case onboarding
        /// Reopened from the arrival flow to change what was packed.
        case adjust
        /// The rest of the trip's life.
        case settings
        /// The next trip, sketched ahead in a keyless store (`makePlan`).
        /// Only what a plan holds: the name, the dates, the money and a way
        /// into the itinerary. Nothing about who holds the phone, sync, letters
        /// or finishing — a plan has none of those until it goes live.
        case plan
    }

    @EnvironmentObject private var store: TripStore
    @Environment(\.dynamicTypeSize) private var typeSize
    var mode: Mode = .settings
    /// How the flow moves on, when it is a step in one.
    var onContinue: (() -> Void)?
    /// `.plan` only: forgetting the plan. The sheet owns it, since the sheet
    /// is what has to close afterwards.
    var onRemovePlan: (() -> Void)?
    @State private var finishing = false
    @State private var planningItinerary = false
    @State private var confirmingRemoval = false
    @State private var budgetText = ""
    @State private var nameText = ""
    /// The trip's own name, kept apart from `nameText`, which is the person's.
    @State private var tripNameText = ""
    @State private var recipient: Traveller = .one
    /// Somebody picked but not yet taken, because taking it would delete
    /// letters.
    ///
    /// A `Participant` rather than a `Traveller`: becoming the observer throws
    /// letters away too, and while this was the narrower type that direction had
    /// no confirmation at all — a traveller's received post simply became the
    /// observer's outgoing set.
    @State private var pendingParticipant: Participant?
    @FocusState private var budgetFocused: Bool
    @FocusState private var nameFocused: Bool
    @FocusState private var tripNameFocused: Bool

    private var isSettings: Bool { mode == .settings }

    private var tripNameGiven: Bool {
        !tripNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: isSettings ? .syncState : mode == .plan ? .hidden : .text("before you go")) {
                Mono(kicker, size: 10.5)

                Display(text: "The trip", size: 40)
                    .padding(.top, 8)
                    .padding(.bottom, Space.s3)

                name
                SectionRule()

                if isSettings {
                    travellers
                    SectionRule(top: 0)
                }

                dates
                SectionRule()
                money

                // A trip with nowhere in it yet has no currencies to quote, and
                // an exchange-rate table with no rows in it is furniture.
                if !store.tripCurrencies.isEmpty {
                    SectionRule()
                    ratesBlock
                }

                if mode == .plan {
                    SectionRule()
                    planItinerary
                    SectionRule()
                    removePlan
                }

                if isSettings {
                    SectionRule()
                    featuresBlock
                    SectionRule()
                    syncBlock
                    SectionRule()
                    letterRules
                    if store.hasOpened, store.isLive {
                        SectionRule()
                        finish
                    }
                }
            }

            if let onContinue {
                VStack {
                    OutlineButton(title: mode == .adjust ? "That's right" : "Next") {
                        commitBudget()
                        commitTripName()
                        onContinue()
                    }
                    // Only the first time. A trip that arrived packed has a name
                    // already, and settings must never refuse to let go of a
                    // screen — but a blank trip leaving here unnamed is the one
                    // that prints a spine reading " · 2026" two months later.
                    .disabled(mode == .onboarding && !tripNameGiven)
                    .opacity(mode == .onboarding && !tripNameGiven ? 0.4 : 1)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
                .background(Palette.bg)
            }
        }
        .background(Palette.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            budgetText = wholeNumber(store.budget)
            loadName()
            tripNameText = store.tripName
            recipient = store.role
        }
        .onChange(of: budgetFocused) { _, focused in
            if !focused { commitBudget() }
        }
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
        .onChange(of: tripNameFocused) { _, focused in
            if !focused { commitTripName() }
        }
        // Losing focus is the ordinary commit, and leaving with the keyboard
        // still up is not a way to lose what was typed. All three are
        // idempotent — each writes the store and reloads its own field — so
        // running them again on the way out costs nothing.
        .onDisappear {
            commitBudget()
            commitName()
            commitTripName()
        }
        .alert(discardTitle,
               isPresented: Binding(get: { pendingParticipant != nil },
                                    set: { if !$0 { pendingParticipant = nil } })) {
            Button("Keep them", role: .cancel) {
                // Nothing to put back: the picker's binding no longer commits,
                // so the highlight never moved. It used to, which is why this
                // branch had to write `Participant(store.role)` — a line that
                // was itself wrong on the observer's phone, where `role` is the
                // traveller written to rather than who is holding it.
                pendingParticipant = nil
            }
            Button("Throw them away", role: .destructive) {
                if let who = pendingParticipant { commit(who) }
                pendingParticipant = nil
            }
        } message: {
            Text(discardWarning)
        }
    }

    /// Takes the identity, once it has been allowed to happen.
    ///
    /// Both directions go through the store rather than through the binding:
    /// `participant` is what decides whether the letters on this phone still
    /// belong to whoever is holding it.
    private func commit(_ who: Participant) {
        if let traveller = who.traveller {
            store.adopt(traveller)
        } else {
            store.becomeObserver()
        }
        settleParticipant()
    }

    /// Everything that follows a change of who is holding the phone, once the
    /// change has actually been allowed to happen.
    private func settleParticipant() {
        store.rescheduleRitual()
        loadName()
        recipient = store.role
    }

    /// Named for what is on this phone now, not for `role`.
    ///
    /// `role` is the addressee on a traveller's phone and the *recipient* on the
    /// observer's, so a title built from it said "Those letters are for Mai" on
    /// the phone that wrote them.
    private var discardTitle: String {
        store.isObserver
            ? "You wrote those letters"
            : "Those letters are for \(store.name(of: store.participant))"
    }

    private var discardWarning: String {
        let count = store.letters.count
        let them = count == 1 ? "it" : "them"
        let letters = "\(Formatting.spelledCount(count, "letter", spellingUpTo: 0)) on this phone"
        let picked = pendingParticipant.map { store.name(of: $0) } ?? ""
        let whose = store.isObserver
            ? "\(letters) \(count == 1 ? "is" : "are") the copy you wrote"
            : "\(letters) \(count == 1 ? "was" : "were") addressed to you"
        return "\(whose). Becoming \(picked) deletes \(them) — not hides \(them) — and nothing can bring \(them) back."
    }

    private var kicker: String {
        switch mode {
        case .onboarding: "Three answers, then it's yours"
        case .adjust: "Change anything that's wrong"
        case .settings: "Set once, then forget"
        case .plan: "Sketched ahead · only on this phone"
        }
    }

    // MARK: - The name

    /// What the trip is called.
    ///
    /// Every trip is named here now, first or fifth, because every trip is set
    /// up through `ArrivalFlow`. It was once only on the shelf's own new-trip
    /// flow, which meant every *first* trip
    /// carried an empty name — and the name is what the spine, the book's title
    /// page and the exported file are built from.
    ///
    /// Committed on losing focus rather than bound straight to `store.tripName`,
    /// which saves on every `didSet`.
    private var name: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mode == .onboarding || mode == .plan {
                growingSpine
                    .padding(.bottom, Space.s3)
            }

            Mono("Name it", size: 10).padding(.bottom, 8)

            TextField("", text: $tripNameText, prompt: Text("Two months")
                .font(Typeface.heading(26).resolved(for: typeSize))
                .foregroundStyle(Palette.n400))
                .font(Typeface.heading(26))
                .foregroundStyle(Palette.text)
                .focused($tripNameFocused)
                .padding(.bottom, 8)

            Rectangle().fill(Palette.accent).frame(height: 1)

            Aside(text: "This ends up on the spine.", size: 11.5)
                .padding(.top, Space.s1)

            if let suggestion = nameSuggestion {
                // Not a `Chip`: that sets its label in capitals, and the
                // label here is the name exactly as tapping it will set it.
                Button {
                    tripNameText = suggestion
                    commitTripName()
                } label: {
                    Text("Call it “\(suggestion)”")
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.a800)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                            .strokeBorder(Palette.accent, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, Space.s2)
            }
        }
    }

    /// Offered while the field is empty and somewhere is in the trip. A chip
    /// and never the placeholder: grey text in a field reads as a value, and
    /// this one would read as a name nobody gave. Onboarding and settings
    /// both, since an unnamed trip is the same gap in either.
    private var nameSuggestion: String? {
        guard mode != .adjust,
              tripNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return store.suggestedTripName
    }

    /// The trip's book, on the shelf beside the last few, drawn while it is
    /// being named. The name on the spine is the *draft* — what is in the
    /// field now, before it commits — and the height follows the dates, so
    /// "This ends up on the spine" is shown rather than said.
    ///
    /// The same `SpineView` the shelf draws, scaled down whole so the type
    /// shrinks with the book rather than being re-set at a new size. Scaling
    /// is a render transform, so the frames around it do the layout: the
    /// shelf is drawn at full size and the outer frame claims its scaled
    /// height.
    private var growingSpine: some View {
        let scale = 0.6
        var draft = store.summary
        draft.name = tripNameText
        return HStack(alignment: .bottom, spacing: 9) {
            SpineView(summary: draft, isLive: true,
                      label: tripNameText.trimmingCharacters(in: .whitespaces).isEmpty
                          ? draft.year : nil)
            ForEach(store.library.byRecency.prefix(3)) { trip in
                SpineView(summary: trip.summary, isLive: false)
            }
        }
        .frame(height: 212, alignment: .bottom)
        .gentleAnimation(.spring(response: 0.45, dampingFraction: 0.8), value: store.dayCount)
        .scaleEffect(scale, anchor: .bottomLeading)
        .frame(height: 212 * scale, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rule(color: Palette.text) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The book this trip becomes: \(draft.displayName), \(Formatting.spelledCount(draft.dayCount, "day", spellingUpTo: 0))")
    }

    private func commitTripName() {
        store.tripName = tripNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        tripNameText = store.tripName
    }

    // MARK: - Travellers

    private var travellers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Who's holding this phone", size: 10).padding(.bottom, 7)

            // One build serves three phones — two travelling, one at home — so
            // who you are is a switch rather than three builds. Picking the
            // observer swaps the whole app for home mode.
            ParticipantPicker(selection: Binding(
                get: { store.participant },
                // Deliberately inert. This used to commit, so the highlight
                // moved before anything had been asked and the cancel branch had
                // to write the old value back by hand — which it did through
                // `role`, and got wrong on the observer's phone. `onChange`
                // below is the only thing that takes an identity now, so the row
                // lights up when the change actually happened.
                set: { _ in }
            ), onChange:  { option in
                // Changing who holds this phone throws away any letters on it —
                // a traveller's were addressed to the slot it was, and the
                // observer's are the archive of what that phone wrote.
                //
                // So the change never runs straight off the tap: somebody may be
                // tapping another row to see what it says. Ask first — and only
                // when there is something to lose, because a confirmation on a
                // phone holding no letters is a dialog about nothing.
                //
                // The question is asked of the store, so the guard here and the
                // deletion in `adopt` cannot drift apart. Asking it here — as
                // `traveller != store.role` — is what let an observer writing to
                // slot two become traveller two with no dialog at all, keeping
                // every letter they had written.
                guard store.adoptionDiscardsLetters(becoming: option) else {
                    commit(option)
                    return
                }
                pendingParticipant = option
            })

            WrittenField(label: "What you're called", text: $nameText,
                         placeholder: store.participant.genericName,
                         note: "Only this phone can change this one.",
                         size: 22)
                .focused($nameFocused)
                .padding(.top, Space.s3)

            Aside(text: "Observer is home mode: their pins and the letters you've sealed, and nothing else.",
                  size: 11.5)
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s3)

            if store.isObserver {
                Mono("Writing to", size: 10).padding(.bottom, 7)

                RecipientPicker(recipient: Binding(
                    get: { recipient },
                    set: { recipient = $0 }
                )) { who in
                    store.writeTo(who)
                }

                Aside(text: "Where sealed letters are posted. Change it and everything already sealed goes to the new phone on the next round.",
                      size: 11.5)
                    .padding(.top, Space.s2)
                    .padding(.bottom, Space.s3)
            }
        }
    }

    /// The typed name, so an unset slot shows its placeholder rather than
    /// pre-filling the fallback as something to type into.
    private func loadName() {
        nameText = store.typedName(of: store.participant)
    }

    private func commitName() {
        if let traveller = store.participant.traveller {
            store.rename(traveller, to: nameText)
        } else {
            store.renameObserver(to: nameText)
        }
        loadName()
    }

    // MARK: - Dates

    private var dates: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("When", size: 10).padding(.bottom, 4)

            DatePicker(
                selection: Binding(
                    get: { store.start },
                    set: { store.setStart($0) }
                ),
                displayedComponents: .date
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Leaving")
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: "Everything already written down moves with it", size: 11.5, color: Palette.n600)
                }
            }
            .datePickerStyle(.compact)
            .padding(.vertical, 8)

            Rule()

            DatePicker(
                selection: Binding(
                    get: { store.end },
                    set: { store.setEnd($0) }
                ),
                in: store.start...,
                displayedComponents: .date
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Home again")
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: "The last day you're away", size: 11.5, color: Palette.n600)
                }
            }
            .datePickerStyle(.compact)
            .padding(.vertical, 8)

            Rule()

            // Not an input — the answer to the two above it, and the number the
            // rest of the app counts in.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("That's \(Formatting.spelledCount(store.dayCount, "day", spellingUpTo: 0))")
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: "\(store.start.shortDate) – \(store.end.shortDate)", size: 11.5, color: Palette.n600)
                }
                Spacer()
                Mono("computed", size: 10, trackingRatio: 0.08, color: Palette.a700)
            }
            .padding(.vertical, 10)

            if store.itineraryOverrun > 0 {
                Panel(border: Palette.a300, fill: Palette.a100) {
                    Mono("The itinerary is longer than the trip", size: 9.5, color: Palette.a700)
                    Text("It runs \(Formatting.spelledCount(store.itineraryOverrun, "day", spellingUpTo: 0)) past your return. The last stops won't fit — move the return date or drop a city.")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.a800)
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)
            }
        }
    }

    // MARK: - Money

    private var money: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Money", size: 10).padding(.bottom, 7)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.homeCurrency.symbol)
                    .font(Typeface.heading(30))
                    .foregroundStyle(Palette.n500)

                TextField("", text: $budgetText, prompt: Text("0")
                    .font(Typeface.heading(44).resolved(for: typeSize))
                    .foregroundStyle(Palette.n400))
                    .font(Typeface.heading(44))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .keyboardType(.numberPad)
                    .focused($budgetFocused)
                    .onSubmit { commitBudget() }
                    .accessibilityLabel("Total budget in \(store.homeCurrency.name)")
            }
            .padding(.bottom, Space.s2)

            Rectangle().fill(Palette.accent).frame(height: 1)

            Aside(text: "\(store.homeCurrency.formatRounded(store.budgetPerDay)) a day across \(Formatting.spelledCount(store.dayCount, "day", spellingUpTo: 0)), between the two of you.",
                  size: 12.5)
                .padding(.top, Space.s1)

            Mono("Home currency", size: 10)
                .padding(.top, Space.s3)
                .padding(.bottom, 7)

            HStack(spacing: Space.s2) {
                ForEach(Currency.homeOptions) { option in
                    SegmentTile(text: "\(option.symbol) \(option.code)",
                                selected: store.homeCurrency == option, serif: false) {
                        store.homeCurrency = option
                        budgetText = wholeNumber(store.budget)
                    }
                }
            }
        }
    }

    // MARK: - Rates

    private var ratesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Mono("Exchange rates", size: 10)
                Spacer()
                if store.rates.isRefreshing {
                    ProgressView().controlSize(.mini).tint(Palette.a700)
                } else {
                    Mono(store.rates.snapshot.source == .live ? "live" : "built in",
                         size: 10, trackingRatio: 0.08, color: Palette.a700)
                }
            }
            .padding(.bottom, 8)

            ForEach(store.tripCurrencies) { currency in
                HStack {
                    Text(currency.name)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Text(rateLine(currency))
                        .font(Typeface.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Palette.n700)
                }
                .padding(.vertical, 7)

                Rule()
            }

            Aside(text: store.rates.detail, size: 12)
                .padding(.top, Space.s2)

            OutlineButton(title: store.rates.isRefreshing ? "Checking…" : "Check for new rates",
                          minHeight: 46, size: 15) {
                Task { await store.rates.refresh() }
            }
            .disabled(store.rates.isRefreshing)
            .padding(.top, Space.s3)
        }
    }

    private func rateLine(_ currency: Currency) -> String {
        let rate = store.fromHome(1, to: currency)
        return "1 \(store.homeCurrency.code) = \(Formatting.decimal(rate, places: rate >= 100 ? 0 : 3)) \(currency.code)"
    }

    // MARK: - Sync

    private var syncBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Mono("The other phone", size: 10)
                Spacer()
                Mono(store.sync.isShared ? "shared" : "on this phone",
                     size: 10, trackingRatio: 0.08,
                     color: store.sync.isShared ? Palette.a700 : Palette.n600)
            }
            .padding(.bottom, 8)

            DetailRow(title: store.sync.transport.name,
                      subtitle: store.sync.summary, titleSize: 16, showsRule: false) {
                if store.sync.isSyncing {
                    ProgressView().controlSize(.mini).tint(Palette.a700)
                }
            }

            OutlineButton(title: store.sync.isSyncing ? "Syncing…" : "Sync now",
                          minHeight: 46, size: 15) {
                Task { await store.syncNow() }
            }
            .disabled(store.sync.isSyncing)
            .padding(.top, Space.s2)

            // The second place somebody looks for "get the other phone on
            // this", after Papers — this block is already titled with the other
            // phone, and until now the only thing it offered was syncing with
            // a phone that might never have been invited. "Sync now" on a trip
            // nobody has joined is a button that succeeds at doing nothing.
            //
            // A link across rather than the control itself: the invitation and
            // what travels are one screen, and a second Send button is a second
            // thing to keep in step with the first.
            if store.sync.canInvite {
                NavigationLink {
                    SharingSettingsView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invite \(store.otherName)")
                                .font(Typeface.heading(16, .semibold))
                                .foregroundStyle(Palette.text)
                            Aside(text: "If they aren't on this trip yet", size: 11.5,
                                  color: Palette.n600)
                        }
                        Spacer()
                        Mono("invite", size: 10, trackingRatio: 0.08, color: Palette.a700)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, Space.s3)
            }

            Aside(text: "Money, plans, the trail and the meeting point are shared both ways. Your journal and anything from home are not.",
                  size: 12)
                .padding(.top, Space.s2)
        }
    }

    // MARK: - Letters

    private var letterRules: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Letters open when", size: 10).padding(.bottom, 8)

            FlowRow(spacing: Space.s2) {
                ForEach(["you arrive somewhere", "day 30", "the last stamp"], id: \.self) { rule in
                    Mono(rule, size: 10, trackingRatio: 0.08, color: Palette.a700)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.accent, lineWidth: 1))
                }
            }

            Aside(text: "Only whoever's at home can change these, and they can't see when you read them.", size: 12)
                .padding(.top, Space.s3)
        }
    }

    // MARK: - A plan's itinerary, and forgetting it

    private var planItinerary: some View {
        Button { planningItinerary = true } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where it goes")
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: itineraryLine, size: 11.5, color: Palette.n600)
                }
                Spacer(minLength: 8)
                Mono(store.legs.isEmpty ? "add" : "edit", size: 10, trackingRatio: 0.08,
                     color: Palette.a700)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $planningItinerary) {
            ItineraryEditorView().environmentObject(store)
        }
    }

    private var itineraryLine: String {
        let stops = store.legs.flatMap(\.segments).count
        guard !store.legs.isEmpty else { return "Countries and stops, whenever you know them" }
        let countries = store.countries.map(\.name).joined(separator: " · ")
        return "\(countries) · \(Formatting.spelledCount(stops, "stop", spellingUpTo: 0))"
    }

    private var removePlan: some View {
        Button { confirmingRemoval = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forget this plan")
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: "It was only ever on this phone", size: 11.5, color: Palette.n600)
                }
                Spacer()
                Mono("forget", size: 10, trackingRatio: 0.08, color: Palette.a700)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .confirmationDialog("Forget \(store.displayName)?", isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button("Forget it", role: .destructive) { onRemovePlan?() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The name, the dates and the itinerary you sketched go. Nothing else is touched.")
        }
    }

    // MARK: - What this trip bothers with

    /// The five switches, here because nothing else asks for them any more.
    ///
    /// They used to be the last step of the shelf's own new-trip flow, after
    /// a template that preset them, and nowhere else: a trip could only
    /// change what it bothered with by being a different trip. A next trip
    /// now carries the last one's switches, and this is where they change.
    private var featuresBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("What this trip bothers with", size: 10).padding(.bottom, 4)

            featureToggle("Letters", "sealed by whoever stays home", \.letters)
            featureToggle("Nightly page", "photo, one line, three taps", \.nightlyPage)
            featureToggle("Stamps", "places, GPS only", \.stamps)
            featureToggle("Printed books", "one each, 8 × 8 in", \.printedBooks)
            featureToggle("Shared ledger", "split, settle, convert", \.sharedLedger, last: true)

            Aside(text: "Anything off here is off everywhere — no empty tab, no greyed-out button, no reminder that it exists. Nothing is deleted by switching it off.",
                  size: 12)
                .padding(.top, Space.s3)
        }
    }

    private func featureToggle(_ title: String, _ subtitle: String,
                               _ path: WritableKeyPath<TripFeatures, Bool>,
                               last: Bool = false) -> some View {
        VStack(spacing: 0) {
            Button {
                store.features[keyPath: path].toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Typeface.heading(16, .semibold))
                            .foregroundStyle(Palette.text)
                        Aside(text: subtitle, size: 11.5, color: Palette.n600)
                    }
                    Spacer(minLength: 8)
                    Tag(text: store.features[keyPath: path] ? "on" : "off",
                        active: store.features[keyPath: path])
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !last { Rule() }
        }
    }

    // MARK: - Finishing

    /// Where "Empty this trip" was. Emptying is one of the two answers on the
    /// finishing sheet now, beside shelving, so a trip is never thrown away
    /// from a row that doesn't mention the shelf is there.
    private var finish: some View {
        Button {
            finishing = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish this trip")
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: "Put it on the shelf, or throw it away, and start the next",
                          size: 11.5, color: Palette.n600)
                }
                Spacer()
                Mono("finish", size: 10, trackingRatio: 0.08, color: Palette.a700)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $finishing) { FinishTripView() }
    }

    // MARK: - Budget field

    private func commitBudget() {
        let digits = budgetText.filter(\.isNumber)
        let value = Double(digits) ?? 0
        store.budget = max(value, 0)
        budgetText = wholeNumber(store.budget)
    }

    private func wholeNumber(_ value: Double) -> String {
        Formatting.decimal(value.rounded(), places: 0, grouping: false)
    }
}

/// Wrapping row of chips — the prototype's `flex-wrap` groups.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
