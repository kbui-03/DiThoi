import SwiftUI

/// Every moment, where the trail lists only the newest few, grouped by where
/// each run of them was kept.
///
/// Newest first, like the trail's own list, so the row that pushed here is the
/// top of what it opens. The book prints them the other way round; that is a
/// finished object read front to back, and this is a list somebody is adding to.
/// The heading names the place, so the rows under it don't say it again.
struct MomentsView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var composing = false
    @State private var editing: Moment?
    @State private var deleted: Moment?
    @State private var kept: Moment?

    private var canMark: Bool { !isReadOnly && store.isLive && !store.isObserver }

    var body: some View {
        Screen(context: .syncState) {
            MarkMomentLabel("Along the way", size: 10.5, canMark: canMark,
                            onKeepSpot: {
                                let fix = store.location.current.flatMap(TrailView.fresh)?.coordinate
                                kept = store.addMoment(note: "", latitude: fix?.latitude ?? 0,
                                                       longitude: fix?.longitude ?? 0)
                            }) {
                composing = true
            }

            Display(text: headline, size: 38)
                .padding(.top, 8)
                .padding(.bottom, Space.s3)

            if store.orderedMoments.isEmpty {
                // Reachable by deleting the last one from here.
                Aside(text: "Anything worth keeping that isn't a stamp goes here, and prints in your book, beside the days it happened.",
                      size: 12.5)
            } else {
                if canMark {
                    Aside(text: "Tap one to open it; hold it to edit or delete.", size: 11.5)
                        .padding(.bottom, Space.s2)
                }
                // Built once per pass and handed down — a derived value read
                // from `body` is not re-derived per row.
                ForEach(Moment.groupedByStop(store.moments)) { group in
                    SectionRule(top: Space.s3, bottom: Space.s2)
                    HStack(alignment: .firstTextBaseline) {
                        Mono(group.heading, size: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%02d", group.moments.count))
                            .font(Typeface.mono(11))
                            .monospacedDigit()
                            .foregroundStyle(Palette.a700)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    ForEach(group.moments) { moment in
                        Button {
                            editing = moment
                        } label: {
                            MomentRow(moment: moment, showsPlace: false)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMark)
                        .modifier(MomentRowMenu(canEdit: canMark,
                                                onEdit: { editing = moment },
                                                onDelete: {
                                                    store.deleteMoment(moment.id)
                                                    deleted = moment
                                                }))
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $composing) {
            MomentComposerView()
        }
        .sheet(item: $editing) { moment in
            MomentComposerView(editing: moment) { deleted = $0 }
        }
        .momentUndo($deleted)
        .spotKept($kept)
    }

    private var headline: String {
        // `spelledCount` agrees the noun and capitalises, so a single one
        // reads "One moment" rather than "One moments".
        // And "Zero moments kept" is a count of nothing stated as an answer.
        let count = store.orderedMoments.count
        return count == 0 ? "Nothing\nkept yet" : "\(Formatting.spelledCount(count, "moment"))\nkept"
    }
}
