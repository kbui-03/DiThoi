import SwiftUI

/// I7 · day 61. The last screen the app ever shows unprompted.
///
/// Every figure on it is one the app already knows; nothing here is written
/// down, and the closing panel is a promise it then keeps — the ritual is
/// cancelled the moment this appears.
struct TripEndingView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var readingBook = false
    @State private var finishing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Mono("\(store.currentCity) → home", size: 10.5, trackingRatio: 0.1)
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
                    Mono("Day \(store.dayCount) of \(store.dayCount)", size: 10.5, trackingRatio: 0.16,
                         color: Palette.a700)

                    Display(text: "That's the\nwhole trip", size: 52, tracking: -0.03)
                        .padding(.top, 14)

                    Rectangle().fill(Palette.accent)
                        .frame(width: 52, height: 1)
                        .padding(.vertical, Space.s4)

                    // The picture of the goodbye: the whole route drawing
                    // itself once, with "again" after. Only when there is a
                    // trail with a position in it — an empty map animating
                    // nothing is not a picture of anything.
                    if !store.trailReplay.isEmpty {
                        TrailReplayView(height: 236, showsKilometres: false)
                            .padding(.bottom, Space.s4)
                    }

                    figures

                    SectionRule(top: Space.s6, bottom: Space.s4)

                    if store.features.printedBooks, store.nightsWritten > 0 {
                        book
                    }

                    Panel {
                        Mono("This app is finished", size: 9.5)
                        Text("It stops asking for a page today. Everything stays on the phone to read whenever, and it'll be here if either of you ever leaves for two months again.")
                            .font(Typeface.body(12.5))
                            .foregroundStyle(Palette.n700)
                            .lineSpacing(4)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Space.s4)

                    if store.isLive {
                        finish
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, Space.s6)
            }

            VStack(spacing: 4) {
                Mono("Đi thôi", size: 9.5, trackingRatio: 0.12)
                Text("— let's go")
                    .font(Typeface.body(11).italic())
                    .foregroundStyle(Palette.n500)
            }
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .sheet(isPresented: $readingBook) { NavigationStack { BookPreviewView() } }
        .sheet(isPresented: $finishing) { FinishTripView() }
        // Finishing takes the tabs this cover sits on away, so the cover goes
        // with them rather than being left over a view that has gone.
        .onChange(of: store.isLive) { _, live in if !live { dismiss() } }
        .onChange(of: store.hasOpened) { _, opened in if !opened { dismiss() } }
        .onAppear {
            // The one promise on this screen the app can keep by itself.
            store.ritual.cancelAll()
        }
    }

    private var figures: some View {
        VStack(spacing: Space.s4) {
            // Nights, not pages: the book's page count also holds the title,
            // the openers and the back, which nobody wrote.
            pair(figure("Nights written", "\(store.nightsWritten)"),
                 figure("Kilometres", Formatting.decimal(Double(store.kilometresTravelled), places: 0)))
            pair(figure("Spent, all in", store.homeTextRounded(store.spentHome)),
                 figure(balanceLabel, balanceValue))
        }
    }

    /// A hairline between two figures. It needs a height of its own — a `Rule`
    /// asked to be one point wide and infinitely tall draws a dot.
    private func pair<L: View, R: View>(_ left: L, _ right: R) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            left
            Rectangle().fill(Palette.divider).frame(width: 1, height: 52)
            right
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Mono(label, size: 9.5, trackingRatio: 0.14)
            Text(value)
                .font(Typeface.heading(34))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Settled · even" is a different fact from "€41 outstanding", and the
    /// label has to change with the number — otherwise the last screen of the
    /// trip says a debt is settled while showing its size.
    private var isSquare: Bool { store.balanceAmountHome < 0.01 }
    private var balanceLabel: String { isSquare ? "Settled" : "\(store.name(for: store.debtor)) still owes" }
    private var balanceValue: String {
        isSquare ? "even" : store.homeTextRounded(store.balanceAmountHome)
    }

    /// The book, to look through. This was "The books aren't ordered yet ·
    /// One tap", over an order that set a flag on this phone and reached no
    /// printer — and "Both books are ordered · Two boxes at the door back
    /// home, about a fortnight from now" once it had been tapped.
    private var book: some View {
        Button { readingBook = true } label: {
            HStack(spacing: Space.s4) {
                spine(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("See the book")
                        .font(Typeface.heading(19, .semibold))
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                    Aside(text: "\(store.bookPlan.pageCount) pages, page by page. The print file is in there too.",
                          size: 12)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The way on, once they're ready. Offered, never done: the trip stays
    /// open for as long as they like, and it has to — a closed trip can export
    /// its book but can no longer order one, so the row says to do that first.
    private var finish: some View {
        Button { finishing = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Put it on the shelf")
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: "Whenever you're ready, and then the next one. The book stays on the shelf to read and export.",
                          size: 11.5, color: Palette.n600)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Mono("finish", size: 10, trackingRatio: 0.08, color: Palette.a700)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Space.s3)
    }

    private func spine(_ colour: Color) -> some View {
        Rectangle()
            .fill(Palette.n100)
            .frame(width: 44, height: 62)
            .overlay(alignment: .leading) { Rectangle().fill(colour).frame(width: 3) }
            .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
    }
}
