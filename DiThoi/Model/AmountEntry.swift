import Foundation

/// What the keypad has typed, as text, and what it is worth.
///
/// Text rather than a number because "3." and "3.50" are both answers to
/// "what is on the screen" that a `Double` can't hold: the point has to stay
/// visible after it is pressed, and so do the trailing zeros. Kept here rather
/// than in the view so the rules are checked: a currency without cents gets
/// no point, input stops at the currency's own number of places, and
/// switching currency never leaves an amount the new one can't write.
struct AmountEntry: Equatable {
    enum Key: Equatable {
        case digit(Int)
        /// "000", for baht, đồng and won, where a point would be a lie.
        case thousands
        case point
        case delete
    }

    private(set) var text = ""
    private(set) var currency: Currency

    /// Twelve characters, which is a trillion of anything — enough for a
    /// month of đồng and short enough that the headline still fits.
    static let maxLength = 12

    init(currency: Currency) {
        self.currency = currency
    }

    /// The text that puts `amount` back on screen. A line the currency can't
    /// write is refused upstream by `Expense.isEditable`, so the rounding here
    /// is only ever to the places the amount already has.
    init(amount: Double, currency: Currency) {
        self.currency = currency
        guard amount > 0 else { return }
        var written = Formatting.decimal(amount, places: currency.decimals, grouping: false)
        // "3.50" stays "3.50" — it was typed that way and reads as money — but
        // a whole amount in a currency with cents opens as "12", not "12.00",
        // so the first backspace deletes a digit somebody typed.
        if written.contains("."), amount == amount.rounded() {
            written = String(written.prefix { $0 != "." })
        }
        text = written
    }

    /// The keys this currency gets, in keypad order.
    var keys: [Key] {
        [.digit(1), .digit(2), .digit(3), .digit(4), .digit(5), .digit(6),
         .digit(7), .digit(8), .digit(9),
         currency.decimals > 0 ? .point : .thousands,
         .digit(0), .delete]
    }

    var amount: Double { Double(text) ?? 0 }
    var isEmpty: Bool { text.isEmpty }

    /// "1,250.5" — grouped like every other figure, with whatever has been
    /// typed after the point kept exactly as typed.
    var display: String {
        guard !text.isEmpty else { return "0" }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Formatting.decimal(Double(parts[0]) ?? 0, places: 0)
        return parts.count > 1 ? "\(whole).\(parts[1])" : whole
    }

    private var fraction: Substring? {
        guard let point = text.firstIndex(of: ".") else { return nil }
        return text[text.index(after: point)...]
    }

    mutating func press(_ key: Key) {
        switch key {
        case .delete:
            if !text.isEmpty { text.removeLast() }
        case .point:
            guard currency.decimals > 0, fraction == nil, text.count < Self.maxLength else { return }
            text = text.isEmpty ? "0." : text + "."
        case .thousands:
            append("000")
        case .digit(let digit):
            append(String(digit))
        }
    }

    private mutating func append(_ digits: String) {
        guard text.count + digits.count <= Self.maxLength else { return }
        if let fraction {
            guard fraction.count + digits.count <= currency.decimals else { return }
        } else if text.isEmpty || text == "0" {
            // No leading zeros: "0" then "5" is "5", and "000" on nothing is
            // nothing.
            guard digits.first != "0" else { return }
            text = ""
        }
        text += digits
    }

    /// Changes currency, dropping whatever the new one can't write — the
    /// cents, going from euros to baht. The headline shows it happen, which is
    /// what makes it a change somebody saw rather than a rounding they didn't.
    mutating func switchCurrency(to new: Currency) {
        currency = new
        guard let point = text.firstIndex(of: ".") else { return }
        if new.decimals == 0 {
            text = String(text[..<point])
        } else if let fraction, fraction.count > new.decimals {
            text = String(text.dropLast(fraction.count - new.decimals))
        }
    }
}
