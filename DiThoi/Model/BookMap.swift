import Foundation

/// The trail as the book draws it: hairlines between the places they stood,
/// no basemap, fitted into a square.
///
/// Arithmetic only — `Double` throughout and no CoreGraphics, the `TripMark`
/// arrangement — because the way this fails is a point walking off the edge of
/// the page, which a screenshot of one trip will not show and a sweep over
/// every shape of trip will. The view multiplies by its side and draws.
///
/// The country openers used to print a hatched panel captioned "the trail,
/// drawn from every stamp you earned · hairline, no basemap" in its place: the
/// design file's note for this, bound into the book.
struct BookMap: Equatable {
    /// A position in the unit square, `y` growing downward the way a page does.
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    struct Mark: Equatable, Identifiable {
        var id: UUID
        var code: String
        var city: String
        var point: Point
        /// Drawn in the accent and named — this country's stops on its opener.
        var highlighted: Bool
    }

    /// Route order, which is the order the line joins them in.
    var marks: [Mark]

    /// A moment, in the app's own mark: a hollow diamond off the line.
    struct MomentMark: Equatable, Identifiable {
        var id: UUID
        var point: Point
    }

    /// Projected like the stamps, but never joined by the line, never named,
    /// and never counted toward the frame — one kept at a layover airport
    /// would otherwise reframe the whole trail, the rule the trail's own map
    /// already keeps.
    var moments: [MomentMark] = []

    /// The earned stamps that have a position, fitted into the square with
    /// `padding` left clear on every side.
    ///
    /// Nil with fewer than two distinct places: one point is a dot, not a
    /// trail, and the page sets the stops as type instead.
    ///
    /// - The projection is equirectangular with longitude scaled by the cosine
    ///   of the middle latitude — at the scale of one trip that is the shape a
    ///   reader recognises, and it needs nothing a map library knows.
    /// - A trip that crosses the antimeridian (Fiji to Samoa) is unwrapped
    ///   first, or it would be drawn the long way round the planet.
    /// - The aspect is kept: a trip that runs north–south stays tall.
    ///
    /// - Parameters:
    ///   - framing: the marks the square is fitted to. Empty fits all of them.
    ///     A country opener frames its own country: fitted to the whole trip,
    ///     Vietnam's opener was one green dot beside the jump to Seoul. The
    ///     rest of the route is still projected, lands outside the square,
    ///     and the page clips it — so it runs faintly off the edge toward
    ///     where they came from and where they went.
    ///   - minimumSpan: when framing, the fewest degrees the square shows, so
    ///     a country with one stop is a dot in a city-sized frame rather than
    ///     an infinite zoom onto a point.
    ///   - moments: drawn as diamonds where they have a position.
    ///   - allowsSinglePlace: a trail of one place is a dot in a city-sized
    ///     frame rather than no picture. The replay asks for it — its first
    ///     frame may be the only place yet — and the book doesn't: an opener
    ///     with one place on the whole trip sets its stops as type.
    static func fit(_ stamps: [Stamp], highlighting: Set<UUID> = [],
                    framing: Set<UUID> = [],
                    moments: [Moment] = [],
                    allowsSinglePlace: Bool = false,
                    padding: Double = 0.1, minimumSpan: Double = 1.5) -> BookMap? {
        let located = stamps.filter { $0.earned && $0.hasLocation }.sorted { $0.index < $1.index }
        let distinct = Set(located.map { "\($0.latitude),\($0.longitude)" })
        guard distinct.count >= (allowsSinglePlace ? 1 : 2) else { return nil }
        let framed = framing.isEmpty ? Array(located.indices) : located.indices.filter { framing.contains(located[$0].id) }
        guard !framed.isEmpty else { return nil }

        // Unwrap across the antimeridian when the short way round is across it.
        let rawLongitudes = located.map(\.longitude)
        let crosses = (rawLongitudes.max() ?? 0) - (rawLongitudes.min() ?? 0) > 180
        func unwrap(_ longitude: Double) -> Double { crosses && longitude < 0 ? longitude + 360 : longitude }
        let longitudes = rawLongitudes.map(unwrap)
        let latitudes = located.map(\.latitude)

        let framedLatitudes = framed.map { latitudes[$0] }
        let middle = ((framedLatitudes.max() ?? 0) + (framedLatitudes.min() ?? 0)) / 2
        let squeeze = max(cos(middle * .pi / 180), 0.05)
        let xs = longitudes.map { $0 * squeeze }
        let ys = latitudes.map { -$0 }

        let frameXs = framed.map { xs[$0] }, frameYs = framed.map { ys[$0] }
        let minX = frameXs.min() ?? 0, maxX = frameXs.max() ?? 0
        let minY = frameYs.min() ?? 0, maxY = frameYs.max() ?? 0
        let span = max(maxX - minX, maxY - minY,
                       framing.isEmpty && !allowsSinglePlace ? 0 : minimumSpan)
        guard span > 0 else { return nil }

        let inner = 1 - padding * 2
        let scale = inner / span
        // Centre the shorter axis.
        let offsetX = padding + (inner - (maxX - minX) * scale) / 2
        let offsetY = padding + (inner - (maxY - minY) * scale) / 2

        let marks = located.enumerated().map { index, stamp in
            Mark(id: stamp.id, code: stamp.code, city: stamp.city,
                 point: Point(x: offsetX + (xs[index] - minX) * scale,
                              y: offsetY + (ys[index] - minY) * scale),
                 highlighted: highlighting.contains(stamp.id))
        }
        let momentMarks = moments.filter(\.hasLocation).map { moment in
            MomentMark(id: moment.id,
                       point: Point(x: offsetX + (unwrap(moment.longitude) * squeeze - minX) * scale,
                                    y: offsetY + (-moment.latitude - minY) * scale))
        }
        return BookMap(marks: marks, moments: momentMarks)
    }

    /// True when something on the map is drawn in the accent — an opener's
    /// map, where everything else is the faint context around it.
    var hasHighlight: Bool { marks.contains(where: \.highlighted) }

    /// Where each name goes, so no two print over each other.
    ///
    /// A label sits to the right of its dot, or to the left near the right
    /// edge. One that would land on a label already placed tries the other
    /// side, and is dropped only if both are taken — Bangkok and Ayutthaya
    /// are seventy kilometres apart, a few points on a page, and printed
    /// their names through each other. A place visited twice is one dot and
    /// one name.
    struct Label: Equatable, Identifiable {
        var id: UUID
        var text: String
        var point: Point
        var onLeft: Bool
    }

    /// - Parameters:
    ///   - width: a label's width as a fraction of the square.
    ///   - height: its height, likewise.
    ///   - gap: between a dot and its name. The drawing passes one that clears
    ///     a moment's diamond, which a name used to touch.
    func labels(all: Bool, width: Double = 0.3, height: Double = 0.05, gap: Double = 0.02) -> [Label] {
        var placed: [(x: ClosedRange<Double>, y: ClosedRange<Double>)] = []
        var seen = Set<String>()
        var result: [Label] = []
        func box(_ mark: Mark, left: Bool) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
            let x = left ? (mark.point.x - gap - width)...(mark.point.x - gap)
                         : (mark.point.x + gap)...(mark.point.x + gap + width)
            return (x, (mark.point.y - height / 2)...(mark.point.y + height / 2))
        }
        func clashes(_ candidate: (x: ClosedRange<Double>, y: ClosedRange<Double>)) -> Bool {
            placed.contains { $0.x.overlaps(candidate.x) && $0.y.overlaps(candidate.y) }
        }
        // Highlighted names first, so the country the page is about keeps its
        // own when space runs out.
        for mark in marks.sorted(by: { $0.highlighted && !$1.highlighted }) {
            guard all || mark.highlighted else { continue }
            // A place past the edge of a framed map is clipped away; its name
            // would be a word with no dot.
            guard (0...1).contains(mark.point.x), (0...1).contains(mark.point.y) else { continue }
            guard seen.insert("\(mark.point.x),\(mark.point.y)").inserted else { continue }
            let preferLeft = mark.point.x + gap + width > 1
            for left in [preferLeft, !preferLeft] {
                let candidate = box(mark, left: left)
                guard candidate.x.lowerBound >= 0, candidate.x.upperBound <= 1, !clashes(candidate) else { continue }
                placed.append(candidate)
                result.append(Label(id: mark.id, text: all ? mark.code : mark.city,
                                    point: mark.point, onLeft: left))
                break
            }
        }
        return result
    }
}
