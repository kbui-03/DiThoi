import SwiftUI

/// Every line of the ledger, by day — pushed from Money's "The whole ledger".
///
/// Money only ever showed the newest six, so anything older could be neither
/// corrected nor deleted. This is where the rest lives, and where it leaves
/// the phone as a spreadsheet.
struct LedgerView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var filter: Filter = .all
    @State private var editingExpense: Expense?
    @State private var undoable: Expense?
    @State private var undoTimer: Task<Void, Never>?
    @State private var exported: [URL] = []
    @State private var sharing = false
    @State private var exportFailed = false

    enum Filter: Hashable {
        case all
        case country(String)
        case settlements
    }

    var body: some View {
        VStack(spacing: 0) {
            Screen {
                Mono(countLine, size: 10.5)

                filters
                    .padding(.top, Space.s2)

                let days = filteredDays
                if days.isEmpty {
                    Aside(text: filter == .all ? "Nothing logged yet." : "Nothing here yet.", size: 12)
                        .padding(.top, Space.s4)
                }

                ForEach(days, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Mono(store.ledgerHeading(forDay: group.day), size: 10, color: Palette.text)
                            Spacer(minLength: 8)
                            if let total = store.ledgerTotal(forDay: group.day) {
                                Text(total)
                                    .font(Typeface.mono(12))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.bottom, 5)
                        Rule(color: Palette.text)

                        ForEach(group.lines) { expense in
                            LedgerLine(expense: expense, showsDay: false,
                                       onEdit: { editingExpense = expense },
                                       onDelete: { remove(expense) })
                        }
                    }
                    .padding(.top, Space.s4)
                }

                if !store.ledger.isEmpty {
                    OutlineButton(title: "Export as a spreadsheet", minHeight: 46, size: 15,
                                  border: Palette.divider, foreground: Palette.text) {
                        export()
                    }
                    .padding(.top, Space.s6)

                    Aside(text: "Every line, with \(store.homeCurrency.name.lowercased())s worked out at today's rates. The file is deleted from this phone once it's been shared.",
                          size: 11.5)
                        .padding(.top, Space.s2)
                }
            }

            if let undoable {
                UndoBanner(text: "Deleted \(undoable.currency.format(undoable.amount)) · \(undoable.note)") {
                    store.restore(undoable.id)
                    undoTimer?.cancel()
                    self.undoable = nil
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .gentleAnimation(.easeInOut(duration: 0.2), value: undoable)
        .onDisappear {
            undoTimer?.cancel()
            undoTimer = nil
            undoable = nil
        }
        .sheet(item: $editingExpense) { line in
            AddExpenseView(editing: line, onDelete: { remove($0) })
        }
        .sheet(isPresented: $sharing) {
            ShareSheet(items: exported) {
                // The whole ledger in one file: once it has gone wherever it
                // was going, the copy left here goes too (§3.6).
                Storage.clearExports()
                exported = []
            }
        }
        .alert("The spreadsheet couldn't be made", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was shared. Try again in a moment.")
        }
    }

    // MARK: - Pieces

    private var countLine: String {
        let lines = store.ledger.count
        let noun = lines == 1 ? "line" : "lines"
        return "Ledger · \(lines) \(noun) · \(store.homeTextRounded(store.spentHome))"
    }

    /// All, each country with something in it, and settlements when there
    /// have been any — never a chip that would filter down to nothing.
    @ViewBuilder
    private var filters: some View {
        let countries = store.countries.map(\.name).filter { name in
            store.ledger.contains { store.country(of: $0) == name }
        }
        let hasSettlements = store.ledger.contains { $0.kind == .transfer }
        if !countries.isEmpty || hasSettlements {
            FlowRow(spacing: Space.s2) {
                Chip(text: "All", selected: filter == .all) { filter = .all }
                ForEach(countries, id: \.self) { name in
                    Chip(text: name, selected: filter == .country(name)) { filter = .country(name) }
                }
                if hasSettlements {
                    Chip(text: "Settlements", selected: filter == .settlements) { filter = .settlements }
                }
            }
        }
    }

    private var filteredDays: [(day: Int, lines: [Expense])] {
        store.ledgerDays.compactMap { group in
            let lines = group.lines.filter { line in
                switch filter {
                case .all: true
                case .country(let name): store.country(of: line) == name
                case .settlements: line.kind == .transfer
                }
            }
            return lines.isEmpty ? nil : (group.day, lines)
        }
    }

    // MARK: - Acting

    private func export() {
        guard let url = store.writeLedgerCSV() else {
            exportFailed = true
            return
        }
        exported = [url]
        sharing = true
    }

    private func remove(_ expense: Expense) {
        store.delete(expense.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        undoable = expense
        undoTimer?.cancel()
        // `@MainActor`: a view method carries no isolation of its own (§4.4).
        undoTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            undoable = nil
        }
    }
}

/// One ledger line, as Money and the ledger both draw it.
///
/// Tapping opens the editor, where the category is one of the choices. It used
/// to cycle the category in place — a surprising, mutating default on the
/// commonest gesture, with no way to see what it had done but to read the
/// subtitle again. Holding offers Delete, with the undo the screen draws.
///
/// A settlement opens nothing: its id and amount belong to the proposal both
/// of them agreed, so it is drawn plain rather than as a button that silently
/// does nothing. A line finer than its currency can be typed in — which
/// nothing in the app writes — can't be reopened, but can still be deleted.
struct LedgerLine: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    let expense: Expense
    /// "· yesterday" in the subtitle, for the recent lines on Money. The
    /// ledger has a heading for each day instead.
    var showsDay: Bool = true
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if isReadOnly || !store.isLive || expense.kind != .spend {
            row
        } else if expense.isEditable {
            Button(action: onEdit) {
                row.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens it to edit")
            .contextMenu {
                Button("Delete", role: .destructive, action: onDelete)
            }
        } else {
            row
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Delete", role: .destructive, action: onDelete)
                }
        }
    }

    private var row: some View {
        DetailRow(title: expense.note.isEmpty ? "Untitled" : expense.note,
                  subtitle: subtitle) {
            Text(expense.currency.format(expense.amount))
                .font(Typeface.mono(13))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
        }
    }

    private var subtitle: String {
        if expense.kind == .transfer, let payer = expense.payer.traveller {
            let agreed = store.settlements.first { $0.id == expense.id }?.confirmedInPerson == true
                ? " · agreed together" : ""
            return "\(store.name(for: payer)) → \(store.name(for: payer.other))\(agreed)"
        }
        let guessed = expense.categoryWasCorrected ? "" : " · guessed"
        let when = showsDay ? " · \(dayWord)" : ""
        return "\(store.label(for: expense.payer)) · \(expense.category.label.lowercased())\(guessed)\(when)"
    }

    private var dayWord: String {
        let day = store.dayNumber(for: expense.date)
        let today = store.trueDayNumber
        if day == today { return "today" }
        if day == today - 1 { return "yesterday" }
        if day < 1 { return "before we left" }
        return expense.date.text("d MMM")
    }
}
