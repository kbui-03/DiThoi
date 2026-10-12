import SwiftUI

/// C2 · Reading one. Paper-white, justified, and nothing on the screen that
/// reports back.
struct LetterReaderView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    let letter: Letter

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Mono("close", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 30)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        Mono("Letter No. \(letter.numberLabel)", size: 10, trackingRatio: 0.16, color: Palette.a700)
                        Rectangle().fill(Palette.accent)
                            .frame(width: 34, height: 1)
                            .padding(.vertical, 12)
                        Mono(provenance, size: 9.5, trackingRatio: 0.12)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.s4)

                    Text(letter.title)
                        .font(Typeface.heading(32).italic())
                        .tracking(-0.6)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s4)
                        .padding(.bottom, Space.s3)

                    ForEach(Array(letter.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(Typeface.body(14))
                            .lineSpacing(6)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Space.s3)
                    }

                    Text(letter.signature)
                        .font(Typeface.heading(19).italic())
                        .foregroundStyle(Palette.n800)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, Space.s1)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, Space.s6)
            }

            Rule()

            HStack(spacing: 12) {
                Mono(nextCondition, size: 9.5, trackingRatio: 0.1)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                OutlineButton(title: "Keep it", minHeight: 44, size: 14, fillsWidth: false, horizontalPadding: 16) {
                    dismiss()
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.n100)
    }

    private var provenance: String {
        let written = "written \(letter.writtenOn.text("d MMMM").lowercased())"
        guard let place = letter.openedPlace else { return written }
        return "\(written) · opened in \(place.lowercased())"
    }

    /// I6 · the footer of the last letter says the whole deal out loud, once:
    /// they were delivered, and nothing was ever reported back.
    private var nextCondition: String {
        if store.sealedLetters.isEmpty, store.hiddenLetterCount == 0 {
            let total = store.letters.count
            let words = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
                         "Eight", "Nine", "Ten", "Eleven", "Twelve"]
            let count = total < words.count ? words[total].lowercased() : "\(total)"
            return "\(count.prefix(1).uppercased() + count.dropFirst()) of \(count)\nall read, none reported"
        }
        guard let next = store.sealedLetters.first else {
            return "\(store.hiddenLetterCount) more\nand they won't say when"
        }
        switch next.condition {
        case .place(let name): return "Next one opens\nwhen you reach \(name)"
        case .day(let day): return "Next one opens\non day \(day)"
        case .stamp(let code): return "Next one opens\nwith the \(code) stamp"
        case .finalStamp: return "Next one opens\nwith the last stamp"
        case .nextOnline: return "Next one opens\nnext time you're online"
        case .hidden: return "Next one opens\nwhen it opens"
        }
    }
}
