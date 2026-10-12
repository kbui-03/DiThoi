#if DEBUG
import SwiftUI
import WidgetKit

/// `-screen widget` — the four families at their real point sizes, on both
/// grounds, drawn by the same `DayWidgetView` the extension ships.
///
/// It exists because adding a widget to a Home Screen takes a long-press, a
/// search field and a drag, and each tool round-trip against the simulator
/// costs several seconds — so in practice nobody would look at it twice. The
/// two failures most likely here are invisible to the compiler and to every
/// assertion in `VerifyTrip`: the Lock Screen renders vibrant, which flattens
/// two greens into one flat bar, and the mark can vanish under an accessibility
/// text size. Both are obvious in a picture.
///
/// `-day N` moves the trip, so the walking dot is checkable here too.
struct WidgetGallery: View {
    @EnvironmentObject private var store: TripStore

    private var snapshot: WidgetSnapshot {
        store.widgetSnapshot(on: store.now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                // The Lock Screen goes first because it is the one nobody looks
                // at: it renders vibrant, which flattens everything to a single
                // luminance ramp, and the whole gallery is taller than the
                // screen. Whatever is at the bottom is what stops being checked.
                // These sit on black so a bar that has lost its second value is
                // obvious rather than merely subtle.
                Mono("Lock screen · vibrant", size: 10)
                HStack(alignment: .center, spacing: Space.s3) {
                    tile(.accessoryRectangular, 160, 72, .dark, ground: .black)
                    tile(.accessoryCircular, 76, 76, .dark, ground: .black)
                }

                // Stacked, not side by side: a medium tile is 338pt and the
                // screen is 393, so a row holding one of each would run off the
                // edge and the thing being checked would be the thing clipped.
                Mono("Home screen · light", size: 10)
                tile(.systemSmall, 158, 158, .light)
                tile(.systemMedium, 338, 158, .light)

                Mono("Home screen · dark", size: 10)
                tile(.systemSmall, 158, 158, .dark)
                tile(.systemMedium, 338, 158, .dark)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.surface)
        .onAppear { DebugScreen.applyDay(to: store) }
    }

    private func tile(_ family: WidgetFamily,
                      _ width: CGFloat, _ height: CGFloat,
                      _ scheme: ColorScheme,
                      ground: Color? = nil) -> some View {
        DayWidgetView(snapshot: snapshot, forcedFamily: family)
            .padding(family == .accessoryCircular ? 0 : 14)
            .frame(width: width, height: height)
            // `.containerBackground` only paints inside a real widget host, so
            // the ground is supplied here by the same view the extension names.
            .background {
                if let ground { ground } else { WidgetGround() }
            }
            .environment(\.colorScheme, scheme)
            .clipShape(RoundedRectangle(cornerRadius: family == .accessoryCircular ? height / 2 : 20))
    }
}
#endif
