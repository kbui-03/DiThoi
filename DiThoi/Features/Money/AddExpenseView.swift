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

    @State private var digits = ""
    @State private var currency: Currency = .thb
    @State private var payer: Payer = .one
    @State private var split: Split = .evenly
    @State private var note = ""
    @State private var customShare: Double = 0.5
    /// 2.5 · a stay that repeats. One is the normal answer.
    @State private var nights = 1
    @State private var askingToDiscard = false
    /// Every field as the sheet opened. Nil until `onAppear` has filled them.
    @State private var opened: Fields?

    private struct Fields: Equatable {
        var digits: String, currency: Currency, payer: Payer, split: Split
        var note: String, customShare: Double, nights: Int
    }

    private var current: Fields {
        Fields(digits: digits, currency: currency, payer: payer, split: split,
               note: note, customShare: customShare, nights: nights)
    }

    private var isDirty: Bool { opened.map { $0 != current } ?? false }

    private var amount: Double { Double(digits) ?? 0 }

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

                    Mono("Who paid", size: 10).padding(.bottom, 8)
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

                    if amount > 0 {
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
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            Keypad(digits: $digits)
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
        .onAppear {
            defer { if opened == nil { opened = current } }
            guard let line = editing else {
                currency = store.localCurrency
                payer = store.role == .one ? .one : .two
                return
            }
            // Whole units only, which is why `Expense.isEditable` refuses a
            // fractional line rather than letting this round it.
            digits = String(Int(line.amount))
            currency = line.currency
            payer = line.payer
            split = line.split
            note = line.note == "Untitled" ? "" : line.note
            customShare = line.customShare
        }
    }

    // MARK: - Pieces

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currency.symbol)
                    .font(Typeface.heading(34))
                    .foregroundStyle(Palette.n500)
                Text(digits.isEmpty ? "0" : formattedDigits)
                    .font(Typeface.heading(62))
                    .tracking(-1.24)
                    .monospacedDigit()
                    .foregroundStyle(digits.isEmpty ? Palette.n400 : Palette.text)
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
                    currency = option
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

    private var formattedDigits: String {
        Formatting.decimal(amount, places: 0)
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

    /// What this amount is worth against the budget, priced off the trip's
    /// own numbers rather than a fixed scale.
    private var comparison: String {
        let home = store.inHome(amount, from: currency)
        guard home > 0, store.budgetPerDay > 0 else { return "" }
        // Everything is priced against the budget they set, so the verdict
        // means something different for a €2,000 trip than a €9,000 one.
        let share = home / store.budgetPerDay
        if share < 0.1 {
            return "Under a tenth of a day's budget."
        }
        if share < 1 {
            return "About \(Int((share * 100).rounded()))% of a day's budget — \(store.homeTextRounded(store.budgetPerDay)) is what a day is worth on this trip."
        }
        return "That's \(String(format: "%.1f", share)) days of budget, at \(store.homeTextRounded(store.budgetPerDay)) a day."
    }

    private func save() {
        // An edit keeps the line's id, its date and the country it was spent
        // in. The id is what makes the other phone read this as a correction
        // rather than a second expense; the date is where it sits in the trip,
        // which fixing a typo three days later must not move.
        let expense = Expense(id: editing?.id ?? UUID(),
                              date: editing?.date ?? store.now,
                              amount: amount, currency: currency,
                              payer: payer, split: split,
                              note: note.isEmpty ? "Untitled" : note,
                              // `countryNow`, not `currentCountry`: the
                              // em-dash there is a label, and a label written
                              // onto a ledger line is a country that does not
                              // exist. Empty means nobody had said yet, and
                              // `TripStore.country(of:)` resolves it later.
                              country: editing?.country ?? store.countryNow,
                              kind: editing?.kind ?? .spend,
                              customShare: customShare,
                              correctedCategory: editing?.correctedCategory)
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
struct Keypad: View {
    @Binding var digits: String

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0", "⌫"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(keys, id: \.self) { key in
                Button {
                    tap(key)
                } label: {
                    Text(key)
                        .font(Typeface.heading(22))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == "⌫" ? "Delete" : key)
            }
        }
    }

    private func tap(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch key {
        case "⌫":
            if !digits.isEmpty { digits.removeLast() }
        default:
            guard digits.count + key.count <= 12 else { return }
            if digits.isEmpty && key.hasPrefix("0") { return }
            digits += key
        }
    }
}
