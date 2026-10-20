import SwiftUI

/// C3 · A stamp unlocks. The one full-screen moment in the app — dark, still,
/// and only ever triggered by actually arriving somewhere.
struct StampEarnedView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    let stamp: Stamp
    let unlockedLetter: Letter?
    var onReadLetter: (Letter) -> Void
    /// "Keep a moment here" — arriving is the moment people most want to
    /// keep, and the screen used to end in two ways out and no way to. Nil
    /// where nothing can be kept (a debug route, a read-only phone).
    var onKeepMoment: ((Stamp) -> Void)? = nil

    @State private var sealVisible = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Mono("arrived", size: 10.5, trackingRatio: 0.1, color: Palette.n300)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 30)

            ScrollView {
                VStack(spacing: 0) {
                    Mono(countLine, size: 10, trackingRatio: 0.16, color: Palette.a300)

                    seal
                        .padding(.vertical, Space.s6)

                    Text(stamp.city)
                        .font(Typeface.heading(38))
                        .tracking(-0.76)
                        .foregroundStyle(Palette.n100)
                        .padding(.bottom, Space.s2)

                    Text(isLast ? finalNote : stamp.arrivalNote)
                        .font(Typeface.body(13.5).italic())
                        .foregroundStyle(Palette.n300)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 250)
                        .padding(.bottom, Space.s6)

                    if let letter = unlockedLetter {
                        Panel(border: Palette.a400) {
                            Mono(isLast ? "One letter left, and it's this one" : "Something came with it",
                                 size: 9.5, color: Palette.a300)
                            Text(isLast
                                 ? "No. \(letter.numberLabel) · written \(letter.writtenOn.dayMonth)"
                                 : "Letter No. \(letter.numberLabel) is open")
                                .font(Typeface.heading(19, .semibold))
                                .foregroundStyle(Palette.n100)
                                .padding(.top, 5)
                            Aside(text: isLast ? "before you'd even left, for after you'd finished" : letter.hint,
                                  size: 12.5, color: Palette.n300)
                                .padding(.top, 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                .padding(.bottom, Space.s6)
            }

            if let onKeepMoment {
                // Above the pair rather than a third beside it: three in a row
                // is "POLIC / E" at an accessibility size, and this is the one
                // most worth reaching. The presenter opens the composer once
                // this cover is gone, never while it is still animating out.
                Button {
                    onKeepMoment(stamp)
                    dismiss()
                } label: {
                    // In "See the trail"'s quieter ink: when a letter opened,
                    // "Read it" is the thing to do next and should stay the
                    // one accent on the screen.
                    Mono("Keep a moment here", size: 10, trackingRatio: 0.12, color: Palette.n300)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.n700, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 30)
                .padding(.bottom, 10)
            }

            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Mono("See the trail", size: 10, trackingRatio: 0.12, color: Palette.n300)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.n700, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let letter = unlockedLetter {
                    Button {
                        dismiss()
                        onReadLetter(letter)
                    } label: {
                        Mono("Read it", size: 10, trackingRatio: 0.12, color: Palette.a300)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.a400, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.n900.ignoresSafeArea())
        .onAppear {
            withGentleAnimation(.easeOut(duration: 0.9)) { sealVisible = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// I5 · the ending starts here. The last stamp is not a bigger version of
    /// the others — it is the one that says there are no more.
    private var isLast: Bool {
        store.orderedStamps.count > 0
            && store.earnedStamps.count == store.orderedStamps.count
            && stamp.index == store.orderedStamps.last?.index
    }

    private var countLine: String {
        let total = store.orderedStamps.count
        let label = "Stamp \(String(format: "%02d", stamp.index)) of \(total)"
        return isLast ? "\(label) · the last one" : label
    }

    private var finalNote: String {
        let places = store.earnedStamps.count
        return "That's all of them. \(Formatting.spelledCount(store.dayCount, "day", spellingUpTo: 0)), \(Formatting.decimal(Double(store.kilometresTravelled), places: 0)) km, \(Formatting.spelledCount(places, "place", spellingUpTo: 0)) you actually stood."
    }

    private var seal: some View {
        StampSeal(code: stamp.code, date: stamp.earnedOn ?? store.now, side: 186,
                  ring: Palette.a400, ink: Palette.a300, rule: Palette.a400)
            .scaleEffect(sealVisible ? 1 : 0.86)
            .opacity(sealVisible ? 1 : 0)
    }
}
