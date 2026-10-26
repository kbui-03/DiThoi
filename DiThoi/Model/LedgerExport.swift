import Foundation

/// The ledger as a spreadsheet.
///
/// The whole ledger in one file, so it is handled the way the book is (§3.6):
/// written to `Storage.exportDirectory`, which is cleared before each build,
/// once the share sheet is done with it, and on background. Nothing else on
/// the phone keeps a copy.
///
/// Home money is worked out at today's rates, because those are the only
/// rates the phone has — it keeps no history of what a baht was worth on day
/// 3. The column says so in its heading rather than leaving a spreadsheet to
/// imply otherwise.
extension TripStore {

    /// One row per live line, oldest first, which is how a spreadsheet reads.
    var ledgerCSV: String {
        let homeColumn = "\(homeCurrency.code) at today's rate"
        let header = ["Date", "Day", "Country", "What for", "Counts as", "Guessed",
                      "Amount", "Currency", homeColumn, "Paid by", "Split",
                      "Other's share", "Kind"]
        var rows = [header]
        for line in ledger.reversed() {
            let isSettlement = line.kind == .transfer
            let paidBy: String = {
                if isSettlement, let payer = line.payer.traveller {
                    return "\(name(for: payer)) to \(name(for: payer.other))"
                }
                return label(for: line.payer)
            }()
            rows.append([
                line.date.text("yyyy-MM-dd HH:mm"),
                String(dayNumber(for: line.date)),
                country(of: line) ?? "",
                line.note,
                isSettlement ? "" : line.category.label,
                isSettlement ? "" : (line.categoryWasCorrected ? "no" : "yes"),
                Formatting.decimal(line.amount, places: line.currency.decimals, grouping: false),
                line.currency.code,
                Formatting.decimal(inHome(line), places: homeCurrency.decimals, grouping: false),
                paidBy,
                isSettlement ? "" : line.split.label.lowercased(),
                isSettlement ? "" : "\(Int((line.shareOwedByOther * 100).rounded()))%",
                isSettlement ? "settlement" : "spend"
            ])
        }
        // CRLF, which RFC 4180 asks for and every spreadsheet accepts.
        return rows.map { $0.map(LedgerExport.field).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    /// "Ledger — Thailand '26.csv". The name is the trip's display name with
    /// anything a file system objects to taken out — and plain "Ledger.csv"
    /// for a trip nobody named, rather than "Ledger — this trip.csv".
    var ledgerFileName: String {
        guard !tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Ledger.csv" }
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let name = displayName.components(separatedBy: unsafe).joined()
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Ledger.csv" : "Ledger — \(name).csv"
    }

    /// Writes the file and hands back where it went, or nil if it couldn't be
    /// written. Clears the export folder first, so there is only ever the one
    /// file being shared in it.
    func writeLedgerCSV() -> URL? {
        Storage.clearExports()
        let url = Storage.exportDirectory.appendingPathComponent(ledgerFileName)
        guard let data = ledgerCSV.data(using: .utf8) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

enum LedgerExport {
    /// One field, quoted when it has to be and defused when it would run.
    ///
    /// A note that starts with `=`, `+`, `-` or `@` is a formula to every
    /// spreadsheet that opens it — "=HYPERLINK(…)" typed as what a dinner was
    /// for is a link somebody clicks. A leading apostrophe makes it text.
    /// Amounts never start with one of those, because a ledger amount is never
    /// negative, so they are left alone.
    static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@\t\r".contains(first) {
            text = "'" + text
        }
        guard text.contains(where: { ",\"\r\n".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
