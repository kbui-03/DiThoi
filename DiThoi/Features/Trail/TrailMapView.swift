import SwiftUI
import MapKit

/// The whole trail, to explore — pushed from the map on the trail.
///
/// The trail's own map takes no gestures, so until this screen the biggest
/// thing on it could only be looked at. Here it pans and zooms, and each mark
/// answers when tapped: a stamp says where and when, a moment opens.
///
/// Letters are never named on a card. This screen is drawn on the observer's
/// tab and in the shelf's reader as well, and "arriving here opens a letter"
/// on the wrong phone is a reference to a channel that isn't theirs.
struct TrailMapView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: TrailMark?
    @State private var recentre = 0
    @State private var editing: Moment?
    @State private var deleted: Moment?

    /// Preselected by the debug route, so the card can be photographed.
    var initialSelection: TrailMark?

    private var canMark: Bool { !isReadOnly && store.isLive && !store.isObserver }

    private var here: CLLocation? { canMark ? store.location.current.flatMap(TrailView.fresh) : nil }

    private var hasMarks: Bool {
        store.orderedStamps.contains(where: \.hasLocation) || store.orderedMoments.contains(where: \.hasLocation)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Stacked above the accessibility threshold, the `spentLabel`
            // shape: side by side at AX5 the title wrapped to "THE WHOLE /
            // TRAIL" against a verb that also said "the trail", and the two
            // read as one broken line.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.s2))
            layout {
                Mono("The whole trail", size: 10.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hasMarks {
                    Button { recentre += 1 } label: {
                        Mono("show all", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                            .padding(.leading, typeSize.isAccessibilitySize ? 0 : Space.s4)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show the whole trail")
                }
            }
            .padding(.horizontal, Space.gutter)

            TrailMap(stamps: store.orderedStamps, moments: store.orderedMoments,
                     here: here?.coordinate, interactive: true,
                     selection: $selection, recentre: recentre, planned: TrailMap.planned(in: store))
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            card
                .padding(.horizontal, Space.gutter)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.bg)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { moment in
            MomentComposerView(editing: moment) { gone in
                selection = nil
                deleted = gone
            }
        }
        .momentUndo($deleted)
        // `task(id:)`, not `onAppear`: the debug host seeds the stamps in its
        // own `onAppear`, which fires after this view's — so the selection
        // arrives on the second build, not the first.
        .task(id: initialSelection) { if let initialSelection { selection = initialSelection } }
        .task { if canMark { store.location.requestOnceIfAllowed() } }
    }

    // MARK: - The card

    @ViewBuilder
    private var card: some View {
        switch selection {
        case .stamp(let id):
            if let stamp = store.orderedStamps.first(where: { $0.id == id }) {
                stampCard(stamp)
            } else {
                prompt
            }
        case .moment(let id):
            if let moment = store.moments.first(where: { $0.id == id }) {
                momentCard(moment)
            } else {
                prompt
            }
        case nil:
            prompt
        }
    }

    /// Never blank, and honest about an empty map: "tap a mark" over a map
    /// with no marks sends somebody looking for something that isn't there.
    private var prompt: some View {
        Aside(text: hasMarks
              ? "Tap a mark. Filled is a stamp earned, dashed is still ahead, a diamond is a moment."
              : "Nothing on the map yet. Stamps and moments appear here once they have a position.",
              size: 12.5)
    }

    private func stampCard(_ stamp: Stamp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Mono(stamp.code, size: 10, color: stamp.earned ? Palette.a700 : Palette.n700)
            Text(stamp.city)
                .font(Typeface.heading(19, .semibold))
                .foregroundStyle(Palette.text)
            Aside(text: stampLine(stamp), size: 12.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func stampLine(_ stamp: Stamp) -> String {
        guard stamp.earned, let earnedOn = stamp.earnedOn else { return "Still ahead." }
        let day = store.dayNumber(for: earnedOn)
        return day >= 1 ? "Stamped \(earnedOn.dayMonth), day \(day)." : "Stamped \(earnedOn.dayMonth)."
    }

    private func momentCard(_ moment: Moment) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            MomentRow(moment: moment)
            if canMark {
                OutlineButton(title: "Open it", minHeight: 44, size: 14,
                              fillsWidth: false, horizontalPadding: 18) {
                    editing = moment
                }
            }
        }
    }
}
