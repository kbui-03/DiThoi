import SwiftUI

/// D2 · Money. Three currencies, netted down to one number.
struct MoneyView: View {
    @EnvironmentObject private var store: TripStore
    /// False when the shelf pushes this inside its own stack. As a tab root it
    /// needs a navigation container; pushed, it would be a second one.
    var embedsNavigation: Bool = true
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var addingExpense = false
    @State private var settling = false
    @State private var editingExpense: Expense?
    /// Held for a few seconds after a delete so it can be taken back. A
    /// tombstone is reversible, so the undo is a real restore rather than a
    /// re-entry of what was typed.
    @State private var undoable: Expense?
    @State private var undoTimer: Task<Void, Never>?
    @State private var destination: Destination?
    /// Whether this visit offers to set a budget. Decided once as the screen
    /// appears, because counting the showing is what retires the offer — read
    /// live, the third visit would take it away while it was being read.
    @State private var showsBudgetNudge = false

    /// Pushed through one `navigationDestination(item:)` (§5.1).
    private enum Destination: Hashable {
        case ledger
        case tripSettings
    }

    @ViewBuilder
    var body: some View {
        if embedsNavigation {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Screen(context: .syncState) {
                // Assembled from the trip's own currencies rather than written
                // out, on the one screen whose subject is which they are.
                Mono(ledgerLine, size: 10.5)

                // "€1,627 of €8,000", or "€1,627 spent" — it read "of €0".
                Display(text: store.moneyHeadline, size: 38)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Aside(text: store.burnLine, size: 12.5)
                RateStamp(size: 11.5, color: Palette.n600)
                    .padding(.bottom, Space.s3)

                if store.hasBudget {
                    budgetBar
                } else if showsBudgetNudge {
                    budgetNudge
                }

                SectionRule(top: Space.s4)

                Mono("By country", size: 10)
                    .padding(.bottom, 9)

                // By country, not by leg. A trip that re-enters a country has
                // two legs there and one answer about what it cost.
                ForEach(Array(store.countries.enumerated()), id: \.element.name) { index, country in
                    countryRow(country.name, isLast: index == store.countries.count - 1)
                }

                if let comparison = perDayLine {
                    Aside(text: comparison, size: 12)
                        .padding(.top, Space.s2)
                }

                SectionRule()

                categories

                if let warning = forecast {
                    Panel(border: Palette.a300, fill: Palette.a100) {
                        Mono(warning.title, size: 9.5, color: Palette.a700)
                        Text(warning.body)
                            .font(Typeface.body(12.5))
                            .foregroundStyle(Palette.a800)
                            .lineSpacing(4)
                            .padding(.top, 5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Space.s3)
                }

                SectionRule()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Mono("Between you", size: 10)
                        Text(balanceHeadline)
                            .font(Typeface.heading(19, .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Spacer(minLength: 8)
                    if store.balanceAmountHome >= 0.01, !isReadOnly {
                        OutlineButton(title: "Settle", minHeight: 44, size: 14,
                                      fillsWidth: false, horizontalPadding: 16) {
                            settling = true
                        }
                    }
                }

                SectionRule()

                Mono("Recent", size: 10).padding(.bottom, 4)

                ForEach(recentExpenses) { expense in
                    LedgerLine(expense: expense,
                               onEdit: { editingExpense = expense },
                               onDelete: { remove(expense) })
                }

                // Everything older than the newest few, which used to be
                // unreachable — neither correctable nor deletable.
                if !store.ledger.isEmpty {
                    Button {
                        destination = .ledger
                    } label: {
                        HStack {
                            Text("The whole ledger · \(store.ledger.count) \(store.ledger.count == 1 ? "line" : "lines")")
                                .font(Typeface.heading(15, .semibold))
                                .foregroundStyle(Palette.a700)
                            Spacer()
                            Text("→")
                                .font(Typeface.heading(15))
                                .foregroundStyle(Palette.a700)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Aside(text: isReadOnly || !store.isLive
                      ? "This trip is closed, so the ledger is as they left it."
                      : "Tap a line to edit it; hold it to delete.",
                      size: 11.5)
                    .padding(.top, Space.s2)
            }

            if let undoable {
                undoBanner(undoable)
            }

            if !isReadOnly {
                OutlineButton(title: "Add an expense", minHeight: 50, size: 15) {
                    addingExpense = true
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s2)
                .background(Palette.bg)
            }
        }
        .gentleAnimation(.easeInOut(duration: 0.2), value: undoable)
        // The window belongs to the screen, not to the app. Without this the
        // task outlives the view: leaving the tab and coming back rebuilds the
        // state, and the orphan wakes ten seconds later to clear a `@State`
        // nothing reads. Clearing `undoable` too, because an undo offer that
        // survives leaving the screen is an offer about a line you can no
        // longer see.
        .onDisappear {
            undoTimer?.cancel()
            undoTimer = nil
            undoable = nil
        }
        .onAppear {
            showsBudgetNudge = store.offersBudgetNudge && !isReadOnly
            if showsBudgetNudge { store.noteBudgetNudgeShown() }
        }
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .ledger: LedgerView()
            case .tripSettings: TripSetupView()
            }
        }
        .sheet(isPresented: $addingExpense) { AddExpenseView() }
        .sheet(item: $editingExpense) { line in
            AddExpenseView(editing: line, onDelete: { remove($0) })
        }
        .sheet(isPresented: $settling) { SettleUpView() }
    }

    // MARK: - Deleting, and taking it back

    private func remove(_ expense: Expense) {
        store.delete(expense.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        undoable = expense
        undoTimer?.cancel()
        // `@MainActor`, explicitly. `remove(_:)` is an ordinary method of a view
        // struct and carries no isolation of its own — only `body` inherits it
        // from `View` — so a bare `Task { }` runs on the global executor and
        // this clears SwiftUI state from a background thread. The project builds
        // in Swift 5 mode, where nothing says so.
        undoTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            undoable = nil
        }
    }

    /// Ten seconds, then it stops offering. The line is still a tombstone
    /// rather than a hole, so nothing has actually been destroyed — but a
    /// banner that never goes away is a banner people stop reading.
    private func undoBanner(_ expense: Expense) -> some View {
        UndoBanner(text: "Deleted \(expense.currency.format(expense.amount)) · \(expense.note)") {
            store.restore(expense.id)
            undoTimer?.cancel()
            undoable = nil
        }
    }

    // MARK: - Pieces

    private var budgetBar: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Palette.a400)
                    .frame(width: geometry.size.width * store.budgetFraction)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 7)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.divider, lineWidth: 1))

            HStack {
                Mono("\(Int((store.budgetFraction * 100).rounded()))% spent", size: 9.5, trackingRatio: 0.08)
                Spacer()
                Mono("\(store.homeTextRounded(store.dailyAllowanceHome))/day left", size: 9.5, trackingRatio: 0.08)
            }
        }
    }

    /// No budget, so no pace to keep — said once a visit, three visits at
    /// most, and then left to Papers → The trip, where the budget always is.
    private var budgetNudge: some View {
        Button {
            destination = .tripSettings
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("No budget, so no pace to keep.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.n700)
                Text("Set one →")
                    .font(Typeface.body(13, .semibold))
                    .foregroundStyle(Palette.a700)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.s2)
            .frame(minHeight: 44)
            // Dashed above only: the section rule beneath is its other edge.
            .overlay(alignment: .top) { DashedLine().stroke(Palette.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No budget set. Set one.")
    }

    /// "Ledger · ฿ ₫ ₩", from the itinerary rather than from a literal.
    private var ledgerLine: String {
        let symbols = store.tripCurrencies.map(\.symbol).joined(separator: " ")
        return symbols.isEmpty ? "Ledger" : "Ledger · \(symbols)"
    }

    @ViewBuilder
    private func countryRow(_ country: String, isLast: Bool) -> some View {
        let spend = store.spentText(inCountry: country)
        let days = spend == nil ? 0 : store.daysSpent(inCountry: country)

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                // n500 was 2.63:1. A country they haven't reached yet should
                // read as quieter, not as unreadable.
                Text(spend == nil ? "\(country) · not yet" : "\(country) · \(Formatting.spelledCount(days, "day", spellingUpTo: 0))")
                    .font(Typeface.body(13))
                    .foregroundStyle(spend == nil ? Palette.n700 : Palette.text)
                Spacer()
                // Every line spent there, card payments in other money
                // included — "≈" when one needed a rate.
                Text(spend ?? "—")
                    .font(Typeface.mono(13))
                    .monospacedDigit()
                    .foregroundStyle(spend == nil ? Palette.n700 : Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            if let note = store.conversionNote(inCountry: country) {
                Aside(text: note, size: 11.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -4)
                    .padding(.bottom, 6)
            }
            if !isLast { Rule() }
        }
    }

    /// What the last country will cost at the current burn, worked out from
    /// the ledger rather than written down.
    private var forecast: (title: String, body: String)? {
        // Every sentence below is a verdict against the budget. With none,
        // "doesn't fit" was the only one it could reach.
        guard store.hasBudget, let last = store.legs.last else { return nil }
        let daysUntil = last.startDay - store.dayNumber
        guard daysUntil > 0, store.dayNumber > 0 else { return nil }

        let burnPerDay = store.spentHome / Double(store.dayNumber)
        let projected = store.spentHome + burnPerDay * Double(daysUntil)
        let leftOnArrival = max(store.budget - projected, 0)
        let nights = max(last.nights, 1)
        let perDay = leftOnArrival / Double(nights)

        let arrival = last.segments.first?.title ?? last.country
        let country = shortName(last.country)

        // At this burn the money is gone before they land, so the sentence has
        // to change shape — a per-day figure of zero reads as advice.
        guard leftOnArrival > 1 else {
            let over = projected - store.budget
            return ("\(country) doesn't fit",
                    "At this rate the budget runs out before \(arrival) — about \(store.homeTextRounded(over)) over, with \(Formatting.spelledCount(nights, "day", spellingUpTo: 0)) still to go.")
        }

        // "Comfortable" is relative to the budget they set, not a fixed figure.
        let comfortable = perDay >= store.budgetPerDay
        let title = comfortable ? "\(country) is covered" : "\(country) will be tight"
        let verdict = comfortable
            ? "above the trip average"
            : "below the trip average"
        let body = "At this rate you'll arrive in \(arrival) with \(store.homeTextRounded(leftOnArrival)) for \(Formatting.spelledCount(nights, "day", spellingUpTo: 0)). That's \(store.homeTextRounded(perDay))/day — \(verdict)."
        return (title, body)
    }

    private func shortName(_ country: String) -> String {
        country == "South Korea" ? "Korea" : country
    }

    private var balanceHeadline: String {
        guard store.balanceAmountHome >= 0.01 else { return "Square, for once" }
        return "\(store.name(for: store.debtor)) owes \(store.homeText(store.balanceAmountHome))"
    }

    // MARK: - 2.5 · what it went on

    /// Inferred from the note and corrected in the editor, where the guess is
    /// already selected — so it is never *asked* at the counter, which is the
    /// only moment a category picker would actually cost something.
    private var categories: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("What it went on", size: 10).padding(.bottom, 9)

            let rows = store.spendByCategory
            let biggest = rows.first?.home ?? 1

            if rows.isEmpty {
                Aside(text: "Nothing logged yet.", size: 12)
            } else {
                ForEach(rows, id: \.category) { row in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.category.label)
                                .font(Typeface.body(13))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Text(store.homeTextRounded(row.home))
                                .font(Typeface.mono(12))
                                .monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Palette.a400)
                                .frame(width: max(geometry.size.width * (row.home / max(biggest, 0.01)), 1))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 3)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    /// "€40/day in Thailand and €95 in Korea" — computed, and only once there
    /// are two countries with real spending in them to compare.
    private var perDayLine: String? {
        let rates = store.perDayByCountry
        guard rates.count >= 2,
              let cheapest = rates.min(by: { $0.perDay < $1.perDay }),
              let dearest = rates.max(by: { $0.perDay < $1.perDay }),
              cheapest.country != dearest.country
        else { return nil }
        return "\(store.homeTextRounded(cheapest.perDay))/day in \(shortName(cheapest.country)), \(store.homeTextRounded(dearest.perDay))/day in \(shortName(dearest.country))."
    }

    /// The newest few, in the ledger's own order (`TripStore.ledger`, which
    /// reads `.live` and tie-breaks on the id). The rest are one tap away.
    private var recentExpenses: [Expense] {
        Array(store.ledger.prefix(6))
    }
}
