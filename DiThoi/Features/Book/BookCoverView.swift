import SwiftUI

/// Which ground the cover is printed on.
///
/// `.paper` is the app: cream boards, ink type, green only where the app uses
/// it — as a stripe and a hairline. The spine is the stripe the shelf draws
/// down every book, so the printed book stands on a real shelf the way it
/// stands on the app's. `.ink` is the app's other register, the one its
/// deliberate dark screens use — the stamp, Separated, the lock — and it hides
/// wear better than a pale cover does.
enum CoverStyle: String, CaseIterable, Identifiable {
    case paper, ink
    var id: String { rawValue }

    /// The cover's cream: the colour of a well-loved book's paper — warm,
    /// a little toned, more parchment than yellow (hue 38°, saturation 11%).
    ///
    /// Deliberately not `Palette.bg`. The app's cream is near-white on a
    /// screen and would print as plain white board; a cover wants a tone
    /// definite enough to survive the press and to read as paper on a shelf.
    static let cream = Color(hex: 0xEDE3D3)

    var ground: Color { self == .paper ? Self.cream : Palette.text }
    var type: Color { self == .paper ? Palette.text : Palette.bg }
    var quiet: Color { self == .paper ? Palette.n700 : Palette.n400 }
    var aside: Color { self == .paper ? Palette.n700 : Palette.n300 }
    /// The trip mark's walked colour on this ground — `MarkGround`'s pairing.
    var walked: Color { Color(hex: self == .paper ? TripMarkInk.accentLight : TripMarkInk.accentDark) }
    var trailLine: Color { self == .paper ? Palette.n400 : Palette.n700 }
    var spine: Color { self == .paper ? Palette.a700 : Palette.a800 }
    /// The cover's own cream on the green, so the spine's type and the
    /// boards are visibly the same paper.
    var spineType: Color { self == .paper ? Self.cream : Palette.bg }
}

/// The case-wrap cover, flat: back board, spine, front board, and the cloth
/// round them, drawn to `CoverSpec` — which is Lulu's template, in numbers.
///
/// The same view draws the preview on the print screen and the cover PDF, for
/// the reason `BookSpreadView` draws both: a preview drawn by other code is a
/// preview that can lie.
///
/// Laid out the way the app lays out a screen — a tracked label, the serif
/// title, a hairline, an italic aside — with the trip mark as the hairline:
/// one walked line that starts on the back, crosses the spine and ends in its
/// dot on the front. The ground runs to every edge, because the outer 0.625 in
/// folds round the boards; type stays in the safe areas, and the back leaves
/// Lulu's barcode box empty.
struct BookCoverView: View {
    @EnvironmentObject private var store: TripStore
    let spec: CoverSpec
    /// The whole sheet's width in points; everything scales off it.
    let width: CGFloat
    /// Volume and count, when the book is cut into more than one.
    var volume: (number: Int, of: Int)?
    var style: CoverStyle = .paper

    private var k: CGFloat { width / CGFloat(spec.totalWidth) }
    private var height: CGFloat { CGFloat(spec.totalHeight) * k }
    /// A point of type at the cover's printed size, scaled like everything else.
    private func pt(_ points: CGFloat) -> CGFloat { points / 72 * k }
    private func x(_ inches: Double) -> CGFloat { CGFloat(inches) * k }

    /// The height the mark runs at, in inches from the top of the sheet: two
    /// thirds down the boards, where the app's screens put their rule under
    /// the title.
    private var markY: Double { CoverSpec.wrap + CoverSpec.boardHeight * 0.66 }
    /// The spine colour reaches a sixteenth past each fold, so a book bound a
    /// millimetre off still shows green on the spine and cream on the boards.
    private let spineOverrun = 0.0625

    var body: some View {
        ZStack(alignment: .topLeading) {
            style.ground

            Rectangle()
                .fill(style.spine)
                .frame(width: x(spec.spine + spineOverrun * 2), height: height)
                .offset(x: x(spec.spineBox.x - spineOverrun))

            mark

            place(frontAbove) { frontTop }
            place(frontBelow) { frontBottom }
            place(backAbove) { backTop }
            place(backBelow) { backBottom }
            place(signOffBox) {
                Mono("Đi thôi — let's go", size: pt(8), trackingRatio: 0.16, color: style.quiet)
                    .frame(maxHeight: .infinity, alignment: .bottomLeading)
            }
            if let area = spec.spineTypeArea {
                place(area) { spineType(area) }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        // A printed cover: its type follows the cover's size, not the
        // reader's text-size setting. See `BookSpreadView`.
        .environment(\.dynamicTypeSize, .large)
    }

    private func place<Content: View>(_ box: CoverSpec.Box, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: x(box.width), height: x(box.height), alignment: .topLeading)
            .offset(x: x(box.x), y: x(box.y))
    }

    // MARK: - The regions, either side of the mark

    private let gap = 0.22

    private var frontAbove: CoverSpec.Box {
        let safe = spec.frontSafe
        return CoverSpec.Box(x: safe.x, y: safe.y, width: safe.width, height: markY - gap - safe.y)
    }

    private var frontBelow: CoverSpec.Box {
        let safe = spec.frontSafe
        return CoverSpec.Box(x: safe.x, y: markY + gap, width: safe.width, height: safe.maxY - markY - gap)
    }

    private var backAbove: CoverSpec.Box {
        let art = spec.backArtwork
        return CoverSpec.Box(x: art.x, y: art.y, width: art.width, height: markY - gap - art.y)
    }

    /// Between the mark and the barcode band, full width.
    private var backBelow: CoverSpec.Box {
        let art = spec.backArtwork
        return CoverSpec.Box(x: art.x, y: markY + gap, width: art.width, height: max(art.maxY - markY - gap, 0))
    }

    /// The bottom-left corner of the back, beside — never in — the barcode box.
    private var signOffBox: CoverSpec.Box {
        let safe = spec.backSafe
        return CoverSpec.Box(x: safe.x, y: spec.barcode.y, width: spec.barcode.x - safe.x - 0.25,
                             height: spec.barcode.height)
    }

    // MARK: - The mark

    /// The trip mark, walked to the end: one hairline from the back's safe
    /// edge, across the spine, to its dot on the front under the title. Over
    /// the spine it is drawn in the ground's colour so it reads as one line
    /// across the green.
    private var mark: some View {
        let y = x(markY)
        let start = x(spec.backSafe.x)
        let end = x(spec.frontSafe.x) + pt(64)
        let spineFrom = x(spec.spineBox.x - spineOverrun)
        let spineTo = x(spec.spineBox.maxX + spineOverrun)
        let stroke = pt(1.6)
        let dot = pt(9)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(style.walked)
                .frame(width: spineFrom - start, height: stroke)
                .offset(x: start, y: y - stroke / 2)
            Rectangle().fill(style.ground)
                .frame(width: spineTo - spineFrom, height: stroke)
                .offset(x: spineFrom, y: y - stroke / 2)
            Rectangle().fill(style.walked)
                .frame(width: end - spineTo, height: stroke)
                .offset(x: spineTo, y: y - stroke / 2)
            Circle().fill(style.walked)
                .frame(width: dot, height: dot)
                .offset(x: end - dot / 2, y: y - dot / 2)
        }
    }

    // MARK: - Front

    /// The label at the top, the title sitting on the mark — the app's screen
    /// header, at the size of a book.
    private var frontTop: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono(frontLabel, size: pt(8.5), trackingRatio: 0.18, color: style.quiet)
            Spacer(minLength: pt(18))
            Display(text: store.displayName.replacingOccurrences(of: " ", with: "\n"),
                    size: pt(46), color: style.type, tracking: -0.03)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }

    private var frontLabel: String {
        var parts = ["\(store.myName)'s copy", store.start.text("yyyy")]
        if let volume { parts.append("volume \(volume.number) of \(volume.of)") }
        return parts.joined(separator: " · ")
    }

    private var frontBottom: some View {
        VStack(alignment: .leading, spacing: pt(6)) {
            Text(BookPlan.subtitle(days: store.dayCount, countries: store.countries.count))
                .font(Typeface.body(pt(13)).italic())
                .foregroundStyle(style.aside)
            Mono("\(store.start.shortDayMonth) – \(store.end.shortDate)", size: pt(8),
                 trackingRatio: 0.16, color: style.quiet)
        }
    }

    // MARK: - Back

    /// The trail as the book draws it, above the mark.
    private var backTop: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            if let map = store.bookMap() {
                BookTrail(map: map, side: side, labelsAll: true, unit: pt(1.1),
                          line: style.trailLine, dot: style.walked, highlight: style.walked,
                          label: style.quiet, highlightLabel: style.quiet, moment: style.quiet)
                    // A moment kept far from every stamp projects outside the
                    // square; on a cover it would print over the artwork.
                    .clipped()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
            } else {
                Text(store.legs.map(\.country).joined(separator: " → "))
                    .font(Typeface.heading(pt(18)))
                    .foregroundStyle(style.type)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
            }
        }
    }

    /// The ending screen's figures, under the mark. Every one is something
    /// the trip already knows, and one with nothing in it is left out.
    private var backBottom: some View {
        var figures: [(String, String)] = [("Days", "\(store.dayCount)")]
        if store.kilometresTravelled > 0 {
            figures.append(("Kilometres", Formatting.decimal(Double(store.kilometresTravelled), places: 0)))
        }
        if !store.countries.isEmpty { figures.append(("Countries", "\(store.countries.count)")) }
        if store.features.stamps, !store.earnedStamps.isEmpty {
            figures.append(("Stamps", "\(store.earnedStamps.count) of \(store.orderedStamps.count)"))
        }
        return HStack(alignment: .top, spacing: pt(26)) {
            ForEach(figures, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: pt(2)) {
                    Mono(label, size: pt(6.5), trackingRatio: 0.16, color: style.quiet)
                    Text(value)
                        .font(Typeface.heading(pt(17)))
                        .monospacedDigit()
                        .foregroundStyle(style.type)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Spine

    /// Read top to bottom, as an English spine is: rotated a quarter turn
    /// clockwise. Laid out at the spine's length *before* the rotation — a
    /// rotation is a render transform and changes nothing about layout, which
    /// is the shelf's spine lesson.
    private func spineType(_ area: CoverSpec.Box) -> some View {
        let length = x(area.height)
        let thickness = x(area.width)
        return ZStack {
            HStack(spacing: pt(10)) {
                Text(store.displayName)
                    .font(Typeface.heading(min(thickness * 0.5, pt(13))))
                    .foregroundStyle(style.spineType)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: pt(10))
                Mono(volume.map { "\(store.start.text("yyyy")) · \($0.number)/\($0.of)" } ?? store.start.text("yyyy"),
                     size: min(thickness * 0.34, pt(8)), trackingRatio: 0.16, color: style.spineType.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: length, height: thickness)
            .rotationEffect(.degrees(90))
        }
        .frame(width: thickness, height: length)
    }
}
