import Foundation

/// The questions the night's blank line asks, in grey, in place of an answer.
///
/// A placeholder is grey text in a field, and grey text in a field reads as
/// an answer somebody gave — the reason the suggested trip name is a button
/// and never a placeholder. What makes this one safe is that every prompt is
/// a question: it ends in "?", and a check holds every one of them to it.
///
/// It replaced yesterday's line, which was there so the page was never
/// blank. A question about the day does that and asks about *this* day.
enum LinePrompts {
    /// The field sets these at the line's own 23-point size, and wraps at
    /// about 28 characters on a phone — so two lines, never a paragraph. It
    /// was 44 first, which dropped "The dog that followed us the whole way
    /// up: what happened?" and left the day asking what they ate.
    static let limit = 60

    /// When the day has given nothing to ask about.
    static let generic = [
        "What did you eat?",
        "Who did you meet?",
        "What was the wrong turn?",
        "What made you laugh?",
        "What will you miss?"
    ]

    /// "Breakfast at the market: how was it?" — the name leads, so it is set
    /// as typed. Put mid-sentence it would need lowercasing, and "What was wat
    /// Phra Singh like?" is the price of guessing which words are names.
    static func about(_ title: String) -> String? {
        let title = trimmed(title)
        guard !title.isEmpty else { return nil }
        let prompt = "\(title.prefix(1).uppercased())\(title.dropFirst()): how was it?"
        return prompt.count <= limit ? prompt : nil
    }

    static func after(_ note: String) -> String? {
        let note = trimmed(note)
        guard !note.isEmpty else { return nil }
        let prompt = "\(note.prefix(1).uppercased())\(note.dropFirst()): what happened?"
        return prompt.count <= limit ? prompt : nil
    }

    /// "Night market?" would make "Night market?: how was it?".
    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?…:;,"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TripStore {
    /// What tonight's blank line asks: questions drawn from that day's own
    /// plan, arrival and moments, or the generic set when the day gave
    /// nothing. Only that day's — a missed night being written gets its own
    /// day's questions, not tonight's.
    func linePrompts(forDay day: Int) -> [String] {
        var prompts: [String] = []
        func add(_ prompt: String?) {
            if let prompt, !prompts.contains(prompt) { prompts.append(prompt) }
        }
        for stamp in earnedStamps where stamp.earnedOn.map(dayNumber(for:)) == day {
            add(LinePrompts.about("Arriving in \(stamp.city)"))
        }
        for item in plan(forDay: day)?.orderedItems ?? [] { add(LinePrompts.about(item.title)) }
        for moment in moments(onDay: day) { add(LinePrompts.after(moment.note)) }
        return prompts.isEmpty ? LinePrompts.generic : prompts
    }
}
