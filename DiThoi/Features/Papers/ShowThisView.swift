import SwiftUI

/// F3 · Hand the phone over. Screen goes to full brightness, everything else
/// gets out of the way, and it swipes between the cards.
struct ShowThisView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    /// Put back on the way out, rather than switched on: whatever else wanted
    /// the screen awake still does.
    @State private var previousIdleTimer = false

    /// Ordered and tombstone-free. The raw array comes back from a merge in
    /// whatever order a dictionary chose, and these are read by a stranger
    /// under pressure — the address belongs first.
    private var cards: [ShowCard] { store.orderedShowCards }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Mono("brightness max", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                Spacer()
                Button { dismiss() } label: {
                    Mono("close", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, Space.gutter)

            TabView(selection: $index) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { cardIndex, card in
                    ShowCardFace(card: card,
                                 caption: "Show this · card \(cardIndex + 1) of \(cards.count)")
                        .tag(cardIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Mono(index > 0 ? "← \(cards[index - 1].shortName)" : " ", size: 10, trackingRatio: 0.12)
                Spacer()
                Mono(index < cards.count - 1 ? "\(cards[index + 1].shortName) →" : " ",
                     size: 10, trackingRatio: 0.12, color: Palette.a700)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.n100.ignoresSafeArea())
        // Held out to a stranger, the phone dimmed and then locked mid-read,
        // and a locked phone in somebody else's hand is a phone to hand back.
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimer
        }
        // The cards can be deleted now, including by the other phone mid-sync.
        // Both swipe hints index this array directly.
        .onChange(of: cards.count) { _, count in
            index = min(index, max(count - 1, 0))
        }
    }
}

/// The card itself, as a stranger sees it.
///
/// Its own view because the editor draws it too, live, while it is being
/// written. A preview rendered by different code from the thing it previews is
/// a preview that can lie — the same reason `BookSpreadView` draws both the
/// book on screen and the file that goes to the printer.
struct ShowCardFace: View {
    let card: ShowCard
    var caption: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if let caption {
                Mono(caption, size: 10, trackingRatio: 0.16)
            }

            Rectangle().fill(Palette.accent)
                .frame(width: 40, height: 1)
                .padding(.top, caption == nil ? 0 : Space.s4)
                .padding(.bottom, Space.s6)

            Text(card.native)
                .font(Typeface.heading(40, .semibold))
                .tracking(-0.4)
                .lineSpacing(12)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)

            Rectangle().fill(Palette.accent)
                .frame(width: 40, height: 1)
                .padding(.top, Space.s6)
                .padding(.bottom, Space.s4)

            Text(card.english)
                .font(Typeface.body(14).italic())
                .foregroundStyle(Palette.n700)
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            if let title = card.footerTitle {
                Panel {
                    VStack(spacing: 4) {
                        Mono(title, size: 9.5)
                        if let body = card.footerBody {
                            Text(body)
                                .font(Typeface.heading(19, .semibold))
                                .foregroundStyle(Palette.text)
                        }
                        if let note = card.footerNote {
                            Aside(text: note, size: 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
                .padding(.top, Space.s8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
    }
}
