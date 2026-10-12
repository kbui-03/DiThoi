import SwiftUI

/// The mark, drawn. The SwiftUI half of the pair described at the top of
/// Shared/TripMark.swift — `Tools/RenderIcons.swift` is the other, and both take
/// a `TripMarkGeometry` so the only thing left that can differ between the icon
/// and the app is a fill.
///
/// Everything scales off the *height*, so the rule always spans the full width
/// it is given while the stroke and the dot keep the cut's proportions. That is
/// what lets the same view be a 10pt bar under a headline and a 60pt circle on
/// the Lock Screen.
struct TripMarkView: View {
    var geometry: TripMarkGeometry
    var ahead: Color
    var walked: Color
    /// Defaults to whether this cut bleeds off its frame — see `TripMarkCut`.
    /// Callers should not normally set it; it is a property of the mark, not of
    /// who is drawing it.
    var overhangs: Bool?
    var height: CGFloat

    var body: some View {
        Canvas { context, size in
            // A Canvas has no intrinsic size; if it is ever handed a zero it
            // draws nothing and looks exactly like a colour mistake. This is
            // the `Rule().frame(width: 1)` failure mode, so refuse it loudly
            // rather than silently.
            guard size.width > 0, size.height > 0 else { return }

            let scale = size.height / geometry.height
            let stroke = geometry.strokeWidth * scale
            let radius = geometry.dotRadius * scale
            let midline = size.height / 2
            let top = midline - stroke / 2

            let walkedTo = geometry.progress * size.width
            // Only the *dot* is pulled inside. Clamping the rule as well would
            // paint a green stub at the left edge on day one, which is a claim
            // that a day has been walked before the trip has started — and it
            // is exactly the sort of thing that passes every assertion and only
            // shows up in a picture.
            let centre = (overhangs ?? geometry.cut.bleeds)
                ? walkedTo
                : min(max(walkedTo, radius), size.width - radius)

            context.fill(
                Path(CGRect(x: 0, y: top, width: size.width, height: stroke)),
                with: .color(ahead))
            context.fill(
                Path(CGRect(x: 0, y: top, width: walkedTo, height: stroke)),
                with: .color(walked))
            if geometry.showsDot {
                context.fill(
                    Path(ellipseIn: CGRect(x: centre - radius, y: midline - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(walked))
            }
        }
        .frame(height: height)
        // The line underneath already says "Day 38 of 61". A second element
        // saying the same thing is noise to somebody listening to the screen.
        .accessibilityHidden(true)
    }
}

extension TripMarkView {
    /// The rule unwrapped from its tile: the same mark, drawn as a progress
    /// bar for a day of the trip.
    init(day: Int, of dayCount: Int, ahead: Color, walked: Color,
         showsDot: Bool = true, height: CGFloat) {
        self.init(
            geometry: TripMarkGeometry(
                cut: .lockup,
                progress: TripMarkGeometry.progress(day: day, of: dayCount),
                showsDot: showsDot),
            ahead: ahead, walked: walked, height: height)
    }
}
