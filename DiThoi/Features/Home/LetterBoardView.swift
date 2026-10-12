import SwiftUI

/// J5 · the board. Where twelve letters land across sixty-one days.
///
/// Most of the writing happens in the nights before departure, and the part
/// that is hard to hold in your head is the shape: which weeks have something
/// in them and which are silent. So the shape is the screen.
struct LetterBoardView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var writing: Letter?

    private var schedule: LetterSchedule { store.letterSchedule }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Screen(context: store.phase.isBefore ? "before they go" : "home") {
                    HStack(alignment: .firstTextBaseline) {
                        Mono(occasion, size: 10.5, color: Palette.a700)
                        Spacer()
                        Mono("\(schedule.sealedCount) / \(schedule.total)", size: 10.5)
                    }

                    Display(text: "Where they\nland", size: 36)
                        .padding(.top, 10)
                        .padding(.bottom, Space.s3)

                    timeline
                        .padding(.bottom, Space.s2)

                    Aside(text: "Filled circles are sealed. Hollow ones are still just conditions with nothing behind them.",
                          size: 11.5)

                    SectionRule()

                    if !stillToWrite.isEmpty {
                        Mono("Still to write", size: 10).padding(.bottom, 7)
                        Rule(color: Palette.text)
                        ForEach(stillToWrite) { letter in
                            row(letter)
                            Rule()
                        }
                    }

                    if !sealed.isEmpty {
                        Mono("Sealed", size: 10)
                            .padding(.top, stillToWrite.isEmpty ? 0 : Space.s4)
                            .padding(.bottom, 7)
                        Rule(color: Palette.text)
                        ForEach(sealed) { letter in
                            row(letter)
                            Rule()
                        }
                    }

                    if !schedule.silences.isEmpty {
                        Aside(text: silenceLine, size: 12)
                            .padding(.top, Space.s3)
                    }
                }

                OutlineButton(title: nextAction, minHeight: 48) {
                    if let draft = store.writerDrafts.first {
                        writing = draft
                    } else {
                        writing = store.startLetter(title: "", condition: suggestedCondition)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s2)
                .background(Palette.bg)
            }
            .background(Palette.bg)
            .sheet(item: $writing) { letter in ComposeLetterView(letterID: letter.id) }
        }
    }

    // MARK: - The line

    /// The timeline is drawn at absolute offsets, which is the one place in the
    /// app where Dynamic Type can collide two labels rather than reflow them.
    /// Every offset below is multiplied by this, and the frame grows with it.
    private var k: CGFloat { min(TypeScale.factor(for: typeSize), 1.7) }

    private var timeline: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Palette.text)
                    .frame(height: 1)
                    .offset(y: 44 * k)

                // Every gap is drawn; only the longest is named. Four labels on
                // a 330pt line overlap into nonsense, and the one worth reading
                // is the one you'd actually write into.
                ForEach(schedule.silences) { silence in
                    let from = x(silence.fromDay, in: width)
                    let to = x(silence.toDay, in: width)
                    Rectangle()
                        .fill(Palette.n400)
                        .frame(width: max(to - from, 1), height: 1)
                        .opacity(0.7)
                        .offset(x: from, y: 56 * k)
                    if silence.id == longestSilence?.id {
                        Mono("\(silence.days) quiet days", size: 9, trackingRatio: 0.08, color: Palette.n500)
                            .lineLimit(1)
                            .offset(x: from + 2, y: 60 * k)
                    }
                }

                ForEach(schedule.placements) { placement in
                    // Filled means sealed. Filled has to be visible against warm
                    // paper, so it's the accent itself rather than its lightest
                    // tint.
                    Circle()
                        .fill(placement.sealed ? Palette.accent : Color.clear)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle().strokeBorder(placement.sealed ? Palette.accent : Palette.n400,
                                                  style: StrokeStyle(lineWidth: 1,
                                                                     dash: placement.sealed ? [] : [2, 2]))
                        )
                        .offset(x: x(placement.day, in: width) - 4.5, y: 24 * k)
                }

                Mono("day 1", size: 9, trackingRatio: 0.1).offset(y: 82 * k)
                Mono("day \(store.dayCount)", size: 9, trackingRatio: 0.1)
                    .frame(width: width, alignment: .trailing)
                    .offset(y: 82 * k)
            }
        }
        .frame(height: 100 * k)
    }

    private var longestSilence: LetterSchedule.Silence? {
        schedule.silences.max { $0.days < $1.days }
    }

    private func x(_ day: Int, in width: CGFloat) -> CGFloat {
        guard store.dayCount > 1 else { return 0 }
        let fraction = Double(min(max(day, 1), store.dayCount) - 1) / Double(store.dayCount - 1)
        return width * fraction
    }

    // MARK: - Rows

    private var stillToWrite: [Letter] { store.writerDrafts }
    private var sealed: [Letter] { store.sealedByWriter.sorted { $0.number < $1.number } }

    @ViewBuilder
    private func row(_ letter: Letter) -> some View {
        Button { writing = letter } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                Text(letter.numberLabel)
                    .font(Typeface.mono(11))
                    .monospacedDigit()
                    .foregroundStyle(letter.isSealed ? Palette.a700 : Palette.n500)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 26, alignment: .leading)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(letter.title.isEmpty ? letter.condition.summary : letter.title)
                        .font(Typeface.heading(16, .semibold))
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                    Aside(text: subtitle(letter), size: 11, color: Palette.n600)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(letter.isSealed)
    }

    private func subtitle(_ letter: Letter) -> String {
        let kind = letter.condition.kindLabel.lowercased()
        guard let placement = schedule.placements.first(where: { $0.id == letter.id }) else {
            return letter.isSealed ? "sealed · \(kind)" : "draft · \(kind)"
        }
        let when = "\(kind) · about day \(placement.day)"
        return letter.isSealed ? "sealed · \(when)" : "draft · \(when)"
    }

    // MARK: - Copy

    private var occasion: String {
        switch store.phase {
        case .before(let days):
            let nights = max(days, 1)
            return "\(nights) night\(nights == 1 ? "" : "s") before they go"
        case .during: return "Day \(store.dayNumber), out there"
        case .after: return "The trip is over"
        }
    }

    private var silenceLine: String {
        let count = schedule.silences.count
        let longest = schedule.silences.map(\.days).max() ?? 0
        return "\(count) stretch\(count == 1 ? "" : "es") with nothing in \(count == 1 ? "it" : "them"), the longest \(longest) days. You can leave them, or write into them later."
    }

    private var nextAction: String {
        if let draft = store.writerDrafts.first {
            return "Finish No. \(draft.numberLabel)"
        }
        return "Write No. \(String(format: "%02d", store.nextLetterNumber))"
    }

    private var suggestedCondition: LetterCondition {
        if store.phase == .during { return .nextOnline }
        // Aim at the middle of the longest silence — that's where a letter is
        // worth the most and where he is least likely to have thought of one.
        if let longest = schedule.silences.max(by: { $0.days < $1.days }) {
            return .day(longest.fromDay + longest.days / 2)
        }
        return .day(min(store.dayCount, max(store.dayCount / 2, 1)))
    }
}
