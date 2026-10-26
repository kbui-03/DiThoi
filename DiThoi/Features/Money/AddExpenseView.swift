import SwiftUI

/// B4 · Add an expense. Big number, three taps, done — and it works with a
/// rate that was cached hours ago.
///
/// Also the edit screen. One sheet rather than two, because an edit that looks
/// different from the thing it edits is a second place for the split rules and
/// the "is this cheap?" arithmetic to drift.
struct AddExpenseView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    /// The line being changed, or nil for a new one.
    var editing: Expense?
    /// Called with the line once it has been deleted from here, so the screen
    /// underneath can offer the undo — the sheet is gone before it could.
    var onDelete: ((Expense) -> Void)?

    @State private var entry = AmountEntry(currency: .thb)
    @State private var payer: Payer = .one
    @State private var split: Split = .evenly
    @State private var note = ""
    @State private var customShare: Double = 0.5
    /// 2.5 · a stay that repeats. One is the normal answer.
    @State private var nights = 1
    /// The trip day it is filed under; nil is today, whichever day that is
    /// when Save is pressed. Last night's dinner is logged the morning after.
    @State private var day: Int?
    /// The day the line had when the sheet opened, so an edit that doesn't
    /// move it keeps its exact moment and its country stamp.
    @State private var openedDay: Int?
    /// Nil follows the guess from the note; set means somebody chose.
    @State private var category: SpendCategory?
    @State private var askingToDiscard = false
    @State private var askingToDelete = false
    /// Every field as the sheet opened. Nil until `onAppear` has filled them.
    @State private var opened: Fields?

    private struct Fields: Equatable {
        var entry: AmountEntry, payer: Payer, split: Split
        var note: String, customShare: Double, nights: Int
        var day: Int?, category: SpendCategory?
    }

    private var current: Fields {
        Fields(entry: entry, payer: payer, split: split,
               note: note, customShare: customShare, nights: nights,
               day: day, category: category)
    }

    private var isDirty: Bool { opened.map { $0 != current } ?? false }

    private var amount: Double { entry.amount }
    private var chosenDay: Int { day ?? store.trueDayNumber }
    private var currency: Currency { entry.currency }

    /// What the note says it was, until somebody says otherwise.
    private var guessedCategory: SpendCategory {
        editing?.correctedCategory ?? SpendCategory.inferred(from: note)
    }

    /// Whoever didn't pay — the person a custom split is being carved out for.
    private var otherPerson: Traveller {
        payer == .two ? .one : .two
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: editing == nil ? "New expense" : "Edit expense",
                        leading: nil, trailing: "Cancel") {
                if isDirty { askingToDiscard = true } else { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    amountField
                    currencyPicker
                    SectionRule(top: Space.s4)

                    whenPicker

                    Mono("Who paid", size: 10)
                        .padding(.top, Space.s3)
                        .padding(.bottom, 8)
                    HStack(spacing: Space.s2) {
                        ForEach(Payer.allCases) { option in
                            SegmentTile(text: store.label(for: option), selected: payer == option) { payer = option }
                        }
                    }

                    Mono("Split", size: 10)
                        .padding(.top, Space.s3)
                        .padding(.bottom, 8)
                    HStack(spacing: Space.s2) {
                        ForEach(Split.allCases) { option in
                            SegmentTile(text: option.label, selected: split == option, serif: false) { split = option }
                        }
                    }

                    if split == .custom {
                        HStack {
                            Mono("\(store.name(for: otherPerson))'s share", size: 10)
                            Spacer()
                            Text("\(Int((customShare * 100).rounded()))%")
                                .font(Typeface.mono(12))
                                .monospacedDigit()
                                .foregroundStyle(Palette.a700)
                        }
                        .padding(.top, Space.s3)

                        Slider(value: $customShare, in: 0...1, step: 0.05)
                            .tint(Palette.accent)
                            .accessibilityLabel("\(store.name(for: otherPerson))'s share of this expense")
                    }

                    Mono("What for", size: 10)
                        .padding(.top, Space.s3)
                        .padding(.bottom, 6)
                    TextField("", text: $note, prompt: Text("Two water guns, the good ones")
                        .font(Typeface.body(15).resolved(for: typeSize))
                        .foregroundStyle(Palette.n500))
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.text)
                        .textInputAutocapitalization(.sentences)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) { Rule() }

                    categoryPicker

                    // 2.5 · the guesthouse you're in for four nights. One line
                    // becomes four dated a night apart, each its own entry, so
                    // any of them can still be edited or deleted on its own.
                    //
                    // Only when writing a new one: repeating is how a line gets
                    // made, not something a line has. Offering it here on an
                    // edit would have to mean either "turn this one into four"
                    // or "add three more", and neither is what the chip says.
                    if editing == nil {
                        Mono("How many nights", size: 10)
                            .padding(.top, Space.s3)
                            .padding(.bottom, 8)

                        HStack(spacing: Space.s2) {
                            ForEach([1, 2, 3, 4, 7], id: \.self) { count in
                                Chip(text: count == 1 ? "once" : "×\(count)", selected: nights == count) {
                                    nights = count
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        }

                        if nights > 1 {
                            Aside(text: "\(nights) lines, one a night, \(currency.format(amount)) each — \(currency.format(amount * Double(nights))) in total.",
                                  size: 11.5)
                                .padding(.top, Space.s2)
                        }
                    }

                    if let comparison = store.budgetComparison(forHome: store.inHome(amount, from: currency)) {
                        Panel(border: Palette.a300, fill: Palette.a100) {
                            Mono("Is this cheap?", size: 9.5, color: Palette.a700)
                            Text(comparison)
                                .font(Typeface.body(12.5))
                                .foregroundStyle(Palette.a800)
                                .lineSpacing(4)
                                .padding(.top, 5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Space.s4)
                    }

                    if editing != nil, onDelete != nil {
                        Button {
                            askingToDelete = true
                        } label: {
                            Mono("Delete this line", size: 10, trackingRatio: 0.1, color: Palette.n700)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Space.s4)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            Keypad(entry: $entry)
                .padding(.horizontal, Space.gutter)

            VStack {
                OutlineButton(title: saveTitle) { save() }
                    .opacity(amount > 0 ? 1 : 0.4)
                    .disabled(amount <= 0)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s2)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard,
                           whatGoes: editing == nil ? "This expense isn't recorded." : "Your changes go.") {
            dismiss()
        }
        .confirmationDialog("Delete this line?", isPresented: $askingToDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let line = editing else { return }
                onDelete?(line)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("You can take it back for a few seconds afterwards.")
        }
        .onAppear {
            // Filled again on a later `onAppear` only while nothing has been
            // touched: refreshing a default nobody has seen yet costs nothing,
            // and filling over what was typed would undo it.
            guard opened == nil || !isDirty else { return }
            defer { opened = current }
            guard let line = editing else {
                entry = AmountEntry(currency: store.localCurrency)
                payer = store.role == .one ? .one : .two
                return
            }
            // Only to the currency's own places, which is why
            // `Expense.isEditable` refuses a finer line rather than letting
            // this round it.
            entry = AmountEntry(amount: line.amount, currency: line.currency)
            payer = line.payer
            split = line.split
            note = line.note == "Untitled" ? "" : line.note
            customShare = line.customShare
            day = store.dayNumber(for: line.date)
            openedDay = day
            category = line.correctedCategory
        }
    }

    // MARK: - Pieces

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currency.symbol)
                    .font(Typeface.heading(34))
                    .foregroundStyle(Palette.n500)
                Text(entry.display)
                    .font(Typeface.heading(62))
                    .tracking(-1.24)
                    .monospacedDigit()
                    .foregroundStyle(entry.isEmpty ? Palette.n400 : Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.top, Space.s4)

            Rectangle().fill(Palette.accent)
                .frame(height: 1)
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s1)

            Aside(text: "≈ \(store.homeText(store.inHome(amount, from: currency)))", size: 12.5)
            RateStamp(size: 12.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Amount \(currency.format(amount))")
    }

    /// The currencies this itinerary will actually make them spend, plus the
    /// one they think in.
    private var pickerCurrencies: [Currency] {
        var options = store.tripCurrencies
        if !options.contains(store.homeCurrency) { options.append(store.homeCurrency) }
        return options
    }

    private var currencyPicker: some View {
        HStack(spacing: 6) {
            ForEach(pickerCurrencies) { option in
                Button {
                    entry.switchCurrency(to: option)
                } label: {
                    Mono(option.chipLabel, size: 11, trackingRatio: 0.06,
                         color: currency == option ? Palette.a700 : Palette.n600)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(currency == option ? Palette.a100 : .clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .strokeBorder(currency == option ? Palette.accent : Palette.divider, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Space.s3)
    }

    // MARK: - When, and what it counts as

    /// Today, yesterday, and every other day behind a menu — including
    /// "before we left" for the flights and the deposit. A line being edited
    /// keeps its own day on offer even when it is one this list wouldn't
    /// otherwise reach.
    private var dayChoices: [Int] {
        var days = store.expenseDays
        if let openedDay, !days.contains(openedDay) { days.append(openedDay) }
        return days
    }

    @ViewBuilder
    private var whenPicker: some View {
        let today = store.trueDayNumber
        let quick = [today, today - 1].filter { $0 >= 1 || $0 == today }
        let rest = dayChoices.filter { !quick.contains($0) }

        Mono("When", size: 10).padding(.bottom, 8)
        FlowRow(spacing: Space.s2) {
            ForEach(quick, id: \.self) { option in
                Chip(text: store.expenseDayLabel(option), selected: chosenDay == option) {
                    // Today is kept as "today" rather than as a number, so a
                    // sheet left open past midnight still files it today.
                    day = option == today && editing == nil ? nil : option
                }
            }
            if !rest.isEmpty {
                Menu {
                    ForEach(rest, id: \.self) { option in
                        Button(store.expenseDayLabel(option)) { day = option }
                    }
                } label: {
                    let picked = rest.contains(chosenDay)
                    Mono(picked ? "\(store.expenseDayLabel(chosenDay)) ▾" : "Earlier ▾",
                         size: 10, trackingRatio: 0.08,
                         color: picked ? Palette.a800 : Palette.n700)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(picked ? Palette.a100 : .clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .strokeBorder(picked ? Palette.accent : Palette.divider, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Another day")
            }
        }
    }

    /// 2.5 · what it went on. Never asked: the guess from the note is already
    /// selected, follows the note as it is typed, and is marked as a guess
    /// until somebody touches a chip. Touching the guessed one confirms it.
    @ViewBuilder
    private var categoryPicker: some View {
        Mono("Counts as", size: 10)
            .padding(.top, Space.s3)
            .padding(.bottom, 8)
        FlowRow(spacing: Space.s2) {
            ForEach(SpendCategory.allCases) { option in
                let isGuess = category == nil && option == guessedCategory
                Chip(text: isGuess ? "\(option.label) · guessed" : option.label,
                     selected: (category ?? guessedCategory) == option) {
                    category = option
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    private var saveTitle: String {
        guard amount > 0 else { return "Save" }
        let owed = Expense(date: store.now, amount: amount, currency: currency,
                           payer: payer, split: split, note: note,
                           country: store.countryNow, customShare: customShare)
            .balanceFactor * amount
        guard abs(owed) > 0.005 else { return "Save" }
        let who = owed > 0 ? Traveller.two : .one
        return "Save · \(store.name(for: who)) owes \(currency.format(abs(owed)))"
    }

    private func save() {
        // An edit keeps the line's id, and — unless its day was changed — its
        // exact moment and the country it was spent in. The id is what makes
        // the other phone read this as a correction rather than a second
        // expense; the date is where it sits in the trip, which fixing a typo
        // three days later must not move.
        //
        // A day somebody chose is different: they said when it was, so the
        // line is filed there and stamped with where they were *that* day.
        // That is the one time a stamped line is re-stamped, and it is the
        // person doing it, not a reader resolving it (§3.4).
        let keepsMoment = editing != nil && day == openedDay
        let date = keepsMoment ? editing!.date : store.expenseDate(forDay: chosenDay)
        let country = keepsMoment ? editing!.country : store.expenseCountry(forDay: chosenDay)
        let expense = Expense(id: editing?.id ?? UUID(),
                              date: date,
                              amount: amount, currency: currency,
                              payer: payer, split: split,
                              note: note.isEmpty ? "Untitled" : note,
                              // `countryNow`, not `currentCountry`: the
                              // em-dash there is a label, and a label written
                              // onto a ledger line is a country that does not
                              // exist. Empty means nobody had said yet, and
                              // `TripStore.country(of:)` resolves it later.
                              country: country,
                              kind: editing?.kind ?? .spend,
                              customShare: customShare,
                              correctedCategory: category ?? editing?.correctedCategory)
        if editing != nil {
            store.update(expense)
        } else if nights > 1 {
            store.addRepeating(expense, nights: nights)
        } else {
            store.add(expense)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Keypad

/// A numbers-only pad, because this screen is used one-handed with a wet phone.
///
/// The bottom-left key belongs to the currency: a point where it has cents,
/// "000" where it doesn't — €3.50 and ₫45,000 are both three taps from
/// nothing. What each key does is `AmountEntry`'s, where it is checked.
struct Keypad: View {
    @Binding var entry: AmountEntry

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(entry.keys.enumerated()), id: \.offset) { _, key in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    entry.press(key)
                } label: {
                    Text(face(key))
                        .font(Typeface.heading(22))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken(key))
            }
        }
    }

    private func face(_ key: AmountEntry.Key) -> String {
        switch key {
        case .digit(let digit): String(digit)
        case .thousands: "000"
        case .point: "."
        case .delete: "⌫"
        }
    }

    private func spoken(_ key: AmountEntry.Key) -> String {
        switch key {
        case .digit(let digit): String(digit)
        case .thousands: "Three zeros"
        case .point: "Decimal point"
        case .delete: "Delete"
        }
    }
}
