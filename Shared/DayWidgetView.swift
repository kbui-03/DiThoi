import SwiftUI
import WidgetKit

/// The four lockups.
///
/// A widget cannot adopt the app's `.preferredColorScheme(.light)`, so unlike
/// every screen in the app this does follow the system appearance — using the
/// same two grounds the icon already defines rather than inventing a third.
///
/// It lives in `Shared/` and is built into both targets so `-screen widget` can
/// photograph it. Adding a widget to a Home Screen needs a long-press, a search
/// field and a drag, which is three tool round-trips of several seconds each and
/// nothing anybody will repeat — and the two things most likely to be silently
/// wrong here (the Lock Screen's vibrancy flattening two greens into one bar,
/// and the mark vanishing at an accessibility text size) are only ever visible
/// in a picture.
struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: WidgetSnapshot
    /// Set only by the debug harness. In the extension the environment is the
    /// authority, because only WidgetKit knows which size it asked for.
    var forcedFamily: WidgetFamily?

    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryCircular: circular
            case .systemMedium: medium.tile
            default: small.tile
            }
        }
        // One target per widget, every size: the whole tile is the door.
        // `RootView` decides whether the page can open and drops it if not.
        .widgetURL(snapshot.tapURL)
    }

    // MARK: - Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.kicker)
                .font(Typeface.mono(9.5))
                .tracking(9.5 * 0.14)
                .foregroundStyle(kickerColour)
            Spacer(minLength: 6)
            // The place, then the distance — not one sentence. At 158pt
            // "Hội An · 9 days until Seoul" wraps over three lines and pushes
            // the rule off the tile.
            Text(snapshot.place)
                .font(Typeface.heading(21))
                .tracking(-0.21)
                .foregroundStyle(textColour)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.leading)
            if let next = snapshot.nextLine {
                Text(next)
                    .font(Typeface.body(11).italic())
                    .foregroundStyle(mutedColour)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
            }
            Spacer(minLength: 10)
            rule(height: 9)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.kicker)
                    .font(Typeface.mono(9.5))
                    .tracking(9.5 * 0.14)
                    .foregroundStyle(kickerColour)
                Spacer(minLength: 8)
                Text(snapshot.tripName)
                    .font(Typeface.mono(9.5))
                    .tracking(9.5 * 0.14)
                    .foregroundStyle(mutedColour)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(snapshot.headline)
                .font(Typeface.heading(24))
                .tracking(-0.24)
                .foregroundStyle(textColour)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 12)
            rule(height: 10)
        }
    }

    // MARK: - Lock Screen

    /// Vibrant rendering flattens everything to a luminance ramp, so `a600` and
    /// `n400` would collapse into one bar and the mark would stop being a mark.
    /// Here the two values are separated by *opacity*, at the same fraction the
    /// tinted icon uses.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.kicker)
                .font(Typeface.mono(11))
                .tracking(11 * 0.12)
            // The place, not the whole sentence: at 160pt "Hội An · 9 days
            // until Seoul" truncates to "…until Se…", and a line that ends
            // mid-word is worse than a line that says less. How far along they
            // are is what the rule underneath is for.
            Text(snapshot.place)
                .font(Typeface.heading(16, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            TripMarkView(
                geometry: TripMarkGeometry(cut: .lockup,
                                           progress: snapshot.progress,
                                           showsDot: snapshot.showsDot),
                ahead: .white.opacity(TripMarkInk.aheadFraction),
                walked: .white,
                height: 6)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }

    /// The design's circular crop — the rule bleeds off both edges and the
    /// circle cuts it, which is why this cut pulls the dot in to 150 so it
    /// doesn't collide with the curve.
    private var circular: some View {
        GeometryReader { proxy in
            ZStack {
                AccessoryWidgetBackground()
                TripMarkView(
                    geometry: TripMarkGeometry(cut: .circular,
                                               progress: snapshot.progress,
                                               showsDot: snapshot.showsDot),
                    ahead: .white.opacity(TripMarkInk.aheadFraction),
                    walked: .white,
                    height: proxy.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
    }

    // MARK: - Parts

    private func rule(height: CGFloat) -> some View {
        TripMarkView(
            geometry: TripMarkGeometry(cut: .lockup,
                                       progress: snapshot.progress,
                                       showsDot: snapshot.showsDot),
            ahead: Color(hex: ground.ahead),
            walked: Color(hex: ground.walked),
            height: height)
    }

    private var ground: MarkGround { colorScheme == .dark ? .dark : .light }
    private var textColour: Color { colorScheme == .dark ? Palette.n100 : Palette.text }
    private var kickerColour: Color { colorScheme == .dark ? Palette.a300 : Palette.a700 }
    private var mutedColour: Color { colorScheme == .dark ? Palette.n500 : Palette.n600 }
}

private extension View {
    /// The Home Screen families share their padding and their ground.
    var tile: some View {
        padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { WidgetGround() }
    }
}

/// The tile ground. A view rather than a colour so the widget and the debug
/// harness cannot end up drawing different backgrounds behind the same mark.
struct WidgetGround: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Color(hex: colorScheme == .dark ? TripMarkInk.ink : TripMarkInk.cream)
    }
}
