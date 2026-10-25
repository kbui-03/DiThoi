import SwiftUI

/// A week of the book as a postcard: one spread the traveller chose, and under
/// it the week's stamp, where the week went, and the trip mark at its last day.
///
/// The spread is `BookSpreadView`, the view that draws the preview and the
/// PDF, so the postcard cannot disagree with the book. Pinned to `.large` for
/// the book's reason: it is a picture of paper, and paper does not grow with
/// the reader's text size.
struct PostcardView: View {
    @EnvironmentObject private var store: TripStore
    let week: Int
    let spreadIndex: Int
    /// The card's whole width. Everything scales off it, the spread's way.
    var width: CGFloat = PostcardView.renderWidth
    /// Full-size photographs, for the saved image; screen copies on screen.
    var forPrint = false

    static let renderWidth: CGFloat = 600
    /// 1,800 pixels across, which is a postcard at 300 dpi held at six inches.
    static let renderScale: CGFloat = 3

    private func u(_ points: CGFloat) -> CGFloat { points * width / Self.renderWidth }

    var body: some View {
        let spreads = store.bookPlan.spreads
        let days = store.postcardDays(week: week)
        let route = store.postcardRoute(week: week)
        return VStack(alignment: .leading, spacing: 0) {
            if spreads.indices.contains(spreadIndex) {
                BookSpreadView(spread: spreads[spreadIndex], width: width - u(48),
                               leftPageNumber: BookPlan.leftPage(ofSpreadAt: spreadIndex),
                               forPrint: forPrint)
                    .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
            }

            // The back of a card, folded under the picture.
            // A line, not a stroked rectangle: a rectangle one point tall
            // strokes both of its edges and the dashes interleave into a
            // zigzag.
            DashedLine()
                .stroke(Palette.n500, style: StrokeStyle(lineWidth: 1, dash: [u(4), u(3)]))
                .frame(height: 1)
                .padding(.top, u(18))
                .padding(.bottom, u(16))

            HStack(alignment: .center, spacing: u(16)) {
                if let stamp = store.postcardStamp(week: week) {
                    StampSeal(code: stamp.code, date: stamp.earnedOn, side: u(70), dateSize: u(7))
                }
                VStack(alignment: .leading, spacing: u(8)) {
                    Mono("\(store.displayName) · week \(week) · days \(days.lowerBound)–\(days.upperBound)",
                         size: u(9.5), trackingRatio: 0.14, color: Palette.n700)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !route.isEmpty {
                        Text(route.joined(separator: " → "))
                            .font(Typeface.heading(u(19)))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    TripMarkView(day: days.upperBound, of: store.dayCount,
                                 ahead: Palette.n300, walked: Palette.accent, height: u(7))
                }
            }
        }
        .padding(u(24))
        .frame(width: width)
        .background(CoverStyle.cream)
        .dynamicTypeSize(.large)
    }

    /// The postcard as a PNG. `pngData()` does write a small `eXIf` chunk —
    /// orientation, resolution, colour space and pixel size, read off a real
    /// export — and nothing else: no location, no date, no device. Nothing
    /// here names the traveller either.
    @MainActor
    static func png(week: Int, spreadIndex: Int, store: TripStore) -> Data? {
        let renderer = ImageRenderer(content:
            PostcardView(week: week, spreadIndex: spreadIndex, forPrint: true)
                .environmentObject(store))
        renderer.scale = renderScale
        renderer.proposedSize = ProposedViewSize(width: renderWidth, height: nil)
        return renderer.uiImage?.pngData()
    }
}

/// Choosing the week's postcard, and keeping it.
///
/// "Save to Photos" is the act. It used to be drafted as "Send one home", and
/// the app sends nothing — it can't, the journal is not a field on anything
/// that leaves the phone. Saved, it is the traveller's to send from Photos;
/// "Share…" is there for sending it on the spot, through the sheet the book
/// already exports through.
struct PostcardPicker: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var week: Int
    /// Whether the other weeks are offered. The Book tab's row offers them;
    /// the saved page offers the week just finished.
    let switchesWeeks: Bool
    @State private var page = 0
    @State private var outcome: Outcome?
    @State private var working = false
    @State private var sharing: [URL] = []

    private enum Outcome {
        case saved, refused, failed

        var line: String {
            switch self {
            case .saved: "Saved to your Photos. It's yours to send."
            case .refused: "Photos access is off, so nothing was saved. It can be turned on in Settings."
            case .failed: "It couldn't be drawn, so nothing was saved."
            }
        }
    }

    init(week: Int, switchesWeeks: Bool) {
        _week = State(initialValue: week)
        self.switchesWeeks = switchesWeeks
    }

    var body: some View {
        let spreads = store.postcardSpreads(week: week)
        return VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "A postcard of the week", trailing: "Close") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Display(text: "Week \(week)", size: 30)
                        .padding(.top, Space.s2)

                    if switchesWeeks, store.postcardWeeks.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.postcardWeeks, id: \.self) { option in
                                    Chip(text: "Week \(option)", selected: option == week) {
                                        week = option
                                        page = 0
                                        outcome = nil
                                    }
                                }
                            }
                        }
                        .padding(.top, Space.s2)
                    }

                    if spreads.isEmpty {
                        Aside(text: "No night of this week has a page yet.")
                            .padding(.top, Space.s3)
                    } else {
                        TabView(selection: $page) {
                            ForEach(Array(spreads.enumerated()), id: \.offset) { position, index in
                                PostcardView(week: week, spreadIndex: index,
                                             width: UIScreen.main.bounds.width - Space.gutter * 2)
                                    .tag(position)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: (UIScreen.main.bounds.width - Space.gutter * 2) * 0.72)
                        .padding(.top, Space.s3)

                        HStack {
                            Mono(spreads.count == 1 ? "One night this week"
                                 : "Night \(page + 1) of \(spreads.count) · swipe to choose",
                                 size: 9.5, trackingRatio: 0.1)
                            Spacer()
                        }
                        .padding(.top, Space.s1)

                        OutlineButton(title: working ? "Saving…" : "Save to Photos") {
                            save(spreads)
                        }
                        .disabled(working)
                        .padding(.top, Space.s4)

                        if let outcome {
                            Aside(text: outcome.line, color: outcome == .saved ? Palette.a700 : Palette.n700)
                                .padding(.top, Space.s2)
                        }

                        Button { share(spreads) } label: {
                            Mono("Share…", size: 10.5, color: Palette.a700)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Space.s1)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s6)
            }
        }
        .background(Palette.bg)
        .sheet(isPresented: Binding(get: { !sharing.isEmpty }, set: { if !$0 { sharing = [] } })) {
            ShareSheet(items: sharing) {
                // The file is the week's pages; it goes as soon as the sheet
                // is done with it, the way the exported book does.
                Storage.clearExports()
                sharing = []
            }
        }
    }

    private func chosen(_ spreads: [Int]) -> Int? {
        spreads.indices.contains(page) ? spreads[page] : spreads.first
    }

    private func save(_ spreads: [Int]) {
        guard let index = chosen(spreads) else { return }
        guard let png = PostcardView.png(week: week, spreadIndex: index, store: store) else {
            outcome = .failed
            return
        }
        working = true
        PhotoLibrary.add(png: png) { saved in
            working = false
            outcome = saved ? .saved : .refused
            if saved { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    private func share(_ spreads: [Int]) {
        guard let index = chosen(spreads),
              let png = PostcardView.png(week: week, spreadIndex: index, store: store) else {
            outcome = .failed
            return
        }
        Storage.clearExports()
        // Named for the week, never the traveller: the name travels with it.
        let url = Storage.exportDirectory.appendingPathComponent("postcard-week-\(week).png")
        do {
            try png.write(to: url, options: .completeFileProtectionUnlessOpen)
            sharing = [url]
        } catch {
            outcome = .failed
        }
    }
}
