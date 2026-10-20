import SwiftUI

/// The first screen of the next trip: where next.
///
/// It used to open on "Who's holding this phone", which on a second trip is
/// the one question with an answer already filled in — while where they were
/// going waited three steps further on. Now the place leads. Who is holding
/// the phone is a line with "change" on it, and what came over from the last
/// trip is a list that can be declined a row at a time.
///
/// A returning traveller only (`SetupStep.destination`). A first launch still
/// asks who first, because that answer decides the whole app, and the
/// observer sets no trip parameters to lead with.
struct NextTripDestinationView: View {
    @EnvironmentObject private var store: TripStore

    let carried: TripStore.CarriedOver
    @Binding var choice: TripStore.CarryChoice
    var onChangeWho: () -> Void
    var onContinue: () -> Void

    @State private var country = ""
    @State private var firstStop = ""
    @State private var currency: Currency?
    /// Set once a chip is tapped, so the guess stops following the country
    /// being typed. A choice somebody made is not revised under them.
    @State private var currencyChosen = false

    private var trimmedCountry: String { country.trimmingCharacters(in: .whitespaces) }
    private var trimmedStop: String { firstStop.trimmingCharacters(in: .whitespaces) }

    /// Both or neither — `AddCountryView.isComplete`'s rule, without the stamp.
    /// A country with no stop can't become a leg, and making one up would be a
    /// stop somebody has to find and delete. A currency is needed too, since
    /// a leg's currency drives every conversion on it.
    private var canContinue: Bool {
        let both = !trimmedCountry.isEmpty && !trimmedStop.isEmpty && currency != nil
        let neither = trimmedCountry.isEmpty && trimmedStop.isEmpty
        return both || neither || !store.legs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Screen(context: "before you go") {
                Mono("The next trip", size: 10.5)

                Display(text: "Where next?", size: 40)
                    .padding(.top, 8)
                    .padding(.bottom, Space.s3)

                whoRow

                SectionRule(top: Space.s3)

                if store.legs.isEmpty {
                    destinationFields
                } else {
                    plannedRows
                }

                SectionRule()

                comingAlong
            }

            VStack {
                OutlineButton(title: "Next") {
                    addLegIfAsked()
                    onContinue()
                }
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.4)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
            .background(Palette.bg)
        }
        .background(Palette.bg)
        .onChange(of: country) { _, typed in
            guard !currencyChosen else { return }
            currency = Currency.likely(forCountry: typed)
        }
    }

    // MARK: - Who

    private var whoRow: some View {
        Button(action: onChangeWho) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.myName)'s phone")
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: "Travelling with \(store.otherName), same as last time",
                          size: 11.5, color: Palette.n600)
                }
                Spacer(minLength: 8)
                Mono("change", size: 10, trackingRatio: 0.08, color: Palette.a700)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Change who is holding this phone, or what you're both called")
    }

    // MARK: - Where

    private var destinationFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Country", size: 10).padding(.bottom, 4)
            UnderlinedField(text: $country, placeholder: "Japan")

            Mono("First stop", size: 10)
                .padding(.top, Space.s3)
                .padding(.bottom, 4)
            UnderlinedField(text: $firstStop, placeholder: "Tokyo")

            if !trimmedCountry.isEmpty {
                Mono("They spend", size: 10)
                    .padding(.top, Space.s3)
                    .padding(.bottom, 7)
                CurrencyChips(selected: currency,
                              suggested: [Currency.likely(forCountry: trimmedCountry),
                                          store.homeCurrency]) {
                    currency = $0
                    currencyChosen = true
                }
            }

            Aside(text: hint, size: 12)
                .padding(.top, Space.s3)
        }
    }

    /// Says what is missing rather than greying the button in silence.
    private var hint: String {
        if trimmedCountry.isEmpty && trimmedStop.isEmpty {
            return "Not sure yet? Leave it — the whole itinerary is two steps away."
        }
        if trimmedCountry.isEmpty { return "Which country is \(trimmedStop) in?" }
        if trimmedStop.isEmpty { return "And the first place in \(trimmedCountry)?" }
        if currency == nil { return "Pick what they spend there. Nothing here guesses a currency it can't check." }
        return "More countries and stops come on the next steps."
    }

    /// What is already in, when they come back to this step. No fields: a
    /// second "Next" must not add the same country twice.
    private var plannedRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.legs) { leg in
                DetailRow(title: leg.country, subtitle: leg.segments.first?.title,
                          titleSize: 17) {
                    Mono("\(Formatting.spelledCount(leg.nights, "night", spellingUpTo: 0))", size: 10.5, trackingRatio: 0.08, color: Palette.a700)
                }
            }
            Aside(text: "More countries and stops come on the next steps.", size: 12)
                .padding(.top, Space.s2)
        }
    }

    private func addLegIfAsked() {
        guard store.legs.isEmpty, !trimmedCountry.isEmpty, !trimmedStop.isEmpty,
              let currency else { return }
        _ = store.addLeg(country: trimmedCountry, currency: currency,
                         firstStop: trimmedStop, nights: min(7, store.dayCount))
    }

    // MARK: - What comes along

    /// One row per thing that came over and has something in it. A budget of
    /// nought isn't offered back, and a trip with no cards lists none.
    private var comingAlong: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Not "from last time": when the trip was sketched ahead, the
            // money on these rows is the plan's.
            Mono("Coming along", size: 10).padding(.bottom, 4)

            if carried.budget > 0 {
                carryRow("Budget \(carried.homeCurrency.formatRounded(carried.budget))",
                         "the whole trip, split by the days", isOn: $choice.budget)
            }
            carryRow("Money in \(carried.homeCurrency.code)",
                     "what the budget and every total are shown in", isOn: $choice.currency)
            ForEach(carried.cards) { card in
                carryRow(card.shortName, "show-this card", isOn: cardBinding(card.id))
            }
            carryRow("The same switches", switchesLine, isOn: $choice.features, last: true)

            Aside(text: "Untick anything that stays behind. It can all be changed later too.",
                  size: 12)
                .padding(.top, Space.s3)
        }
    }

    private var switchesLine: String {
        let on = carried.features.rows.filter(\.on).map { $0.title.lowercased() }
        return on.isEmpty ? "everything off" : on.joined(separator: ", ")
    }

    private func cardBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { !choice.droppedCards.contains(id) },
                set: { keep in
                    if keep { choice.droppedCards.remove(id) } else { choice.droppedCards.insert(id) }
                })
    }

    private func carryRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>,
                          last: Bool = false) -> some View {
        VStack(spacing: 0) {
            Button {
                isOn.wrappedValue.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Typeface.heading(16, .semibold))
                            .foregroundStyle(isOn.wrappedValue ? Palette.text : Palette.n600)
                        Aside(text: subtitle, size: 11.5, color: Palette.n600)
                    }
                    Spacer(minLength: 8)
                    Tag(text: isOn.wrappedValue ? "coming" : "left behind", active: isOn.wrappedValue)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOn.wrappedValue ? "coming along" : "left behind")
            if !last { Rule() }
        }
    }
}
