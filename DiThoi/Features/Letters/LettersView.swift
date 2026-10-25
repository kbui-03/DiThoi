import SwiftUI

/// C1 · The letter box. Sealed ones show only their condition, and nothing
/// leaves this phone when one is read.
struct LettersView: View {
    @EnvironmentObject private var store: TripStore
    @State private var reading: Letter?

    var body: some View {
        Screen(context: .syncState) {
            HStack(alignment: .firstTextBaseline) {
                Mono("From home", size: 10.5)
                Spacer()
                Mono("\(store.openLetters.count) open · \(store.sealedLetters.count + store.hiddenLetterCount) sealed",
                     size: 10.5, color: Palette.a700)
            }

            Display(text: "Letters", size: 38)
                .padding(.top, 8)
                .padding(.bottom, Space.s3)

            Rule(color: Palette.text)

            ForEach(store.openLetters) { letter in
                Button {
                    reading = letter
                } label: {
                    HStack(alignment: .top, spacing: Space.s3) {
                        Text(letter.numberLabel)
                            .font(Typeface.mono(11))
                            .monospacedDigit()
                            .foregroundStyle(Palette.a700)
                            .frame(width: 26, alignment: .leading)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(letter.title)
                                .font(Typeface.heading(17, .semibold))
                                .foregroundStyle(Palette.text)
                                .multilineTextAlignment(.leading)
                            Aside(text: openedCaption(letter), size: 11.5)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rule()
            }

            Mono("Still sealed", size: 10)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s2)

            Rule()

            ForEach(store.sealedLetters) { letter in
                HStack(alignment: .top, spacing: Space.s3) {
                    Text(letter.numberLabel)
                        .font(Typeface.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.n500)
                        .frame(width: 26, alignment: .leading)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(letter.condition.summary)
                            .font(Typeface.heading(16, .semibold))
                            .foregroundStyle(Palette.n600)
                        Aside(text: letter.hint, size: 11, color: Palette.n500)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Letter \(letter.number), sealed. \(letter.condition.summary).")

                DashedRule()
            }

            if store.hiddenLetterCount > 0 {
                Mono("+ \(store.hiddenLetterCount) more you can't see yet", size: 10, trackingRatio: 0.1, color: Palette.n500)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.s2)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reading) { letter in
            LetterReaderView(letter: letter)
        }
    }

    private func openedCaption(_ letter: Letter) -> String {
        let place = letter.openedPlace ?? "somewhere"
        guard let openedOn = letter.openedOn else { return place }
        let day = store.dayNumber(for: openedOn)
        return day == store.dayNumber ? "\(place) · opened today" : "\(place) · \(openedOn.dayMonth)"
    }
}

/// Dashed hairline used only for the sealed letters. One `DashedLine`, not
/// a bordered one-point box, which drew its top and bottom edges as two rows
/// of dashes that met in a zigzag.
struct DashedRule: View {
    var body: some View {
        DashedLine()
            .stroke(Palette.n300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
    }
}
