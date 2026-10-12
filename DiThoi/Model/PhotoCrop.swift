import Foundation

// MARK: - Which square of a photograph the book gets

/// The printed page is square — `BookSpec` is 8 × 8 inches — so a photograph
/// held any other way is cropped on its way in. Until this existed nobody chose
/// which square: `BookSpreadView` centre-cropped at print time, `JournalPhoto`
/// centre-cropped into a *different* shape on screen, and the person who took
/// the photograph was told about neither.
///
/// Deliberately arithmetic. No CoreGraphics, no UIKit, `Double` throughout, so
/// `run-checks.sh` proves the clamping on macOS with no simulator — the same
/// arrangement `TripMark` has, and for the same reason: the failure here is a
/// rectangle that walks off the edge of the source, which is invisible in a
/// screenshot of a photograph that happens to be big enough.
///
/// Units are the source's own. The view builds one from `UIImage.size`, which
/// is points with the EXIF orientation already applied — see `PhotoCropView`,
/// which must not reach for `cgImage`.
struct PhotoCrop: Equatable {
    var sourceWidth: Double
    var sourceHeight: Double

    /// 1 = the square exactly fills the shorter edge. Larger zooms in.
    var zoom: Double = 1

    /// The square's centre, offset from the source's centre. Positive x moves
    /// the square right, positive y moves it down.
    var offsetX: Double = 0
    var offsetY: Double = 0

    /// Past this the square is a quarter of the short edge, which on any phone
    /// photograph is well under the book's 300 dpi. The crop screen *says* so
    /// rather than refusing it — somebody cropping tight to one face knows what
    /// they are doing, and `BookSpec.isSoft(square:)` is what tells them.
    static let maxZoom: Double = 4

    init(sourceWidth: Double, sourceHeight: Double,
         zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    // MARK: The square

    /// The square at zoom 1 — the largest one the photograph can hold.
    var fittedSide: Double { max(min(sourceWidth, sourceHeight), 0) }

    var side: Double { fittedSide / max(zoom, 1) }

    /// How far the square's centre may travel before it leaves the source. Zero
    /// on the short axis at zoom 1, which is why a landscape photograph pans
    /// sideways and not up and down until it is zoomed.
    var maxOffsetX: Double { max((sourceWidth - side) / 2, 0) }
    var maxOffsetY: Double { max((sourceHeight - side) / 2, 0) }

    var originX: Double { (sourceWidth - side) / 2 + offsetX }
    var originY: Double { (sourceHeight - side) / 2 + offsetY }

    // MARK: Staying inside the photograph

    /// Every mutation goes through this, so there is no state in which the
    /// square hangs over an edge — which means the view has no empty gap to
    /// render and no "what goes here" decision to make, and the renderer can
    /// draw the source at its natural size and simply offset it.
    ///
    /// Zoom is pinned first, because the offset limits are derived from `side`
    /// and `side` is derived from zoom. Doing it the other way round clamps
    /// against the limits of a zoom level that is about to be thrown away.
    func clamped() -> PhotoCrop {
        var copy = self
        copy.zoom = min(max(zoom.isFinite ? zoom : 1, 1), Self.maxZoom)
        let limitX = copy.maxOffsetX
        let limitY = copy.maxOffsetY
        copy.offsetX = min(max(offsetX.isFinite ? offsetX : 0, -limitX), limitX)
        copy.offsetY = min(max(offsetY.isFinite ? offsetY : 0, -limitY), limitY)
        return copy
    }

    /// What `clamped()` guarantees, written as a question so a check can ask it
    /// rather than restate the arithmetic it is checking.
    var isInsideSource: Bool {
        originX >= -0.0001 && originY >= -0.0001
            && originX + side <= sourceWidth + 0.0001
            && originY + side <= sourceHeight + 0.0001
    }

    /// True when the source is already the shape the page wants and nothing has
    /// been moved — the one case where cropping is a re-encode for nothing.
    var isUntouched: Bool {
        sourceWidth == sourceHeight && zoom == 1 && offsetX == 0 && offsetY == 0
    }

    // MARK: What it will print at

    /// Pixels along the chosen square's edge. `scale` is the source's own —
    /// `UIImage.size` is points, and a photograph off the picker is usually
    /// scale 1, but assuming that is how a retina asset silently reports a
    /// quarter of its resolution.
    func pixelSide(scale: Double = 1) -> Int { Int((side * scale).rounded()) }

    /// The warning the crop screen shows, computed rather than asserted.
    func isSoft(on spec: BookSpec = BookSpec(), scale: Double = 1) -> Bool {
        spec.isSoft(square: pixelSide(scale: scale))
    }
}
