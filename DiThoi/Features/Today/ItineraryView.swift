import SwiftUI

/// B2 · Every day of it. The legs are day offsets, so this screen is drawn
/// against whatever dates the travellers set.
struct ItineraryView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var editing = false

    var body: some View {
        Screen(context: .syncState) {
            HStack(alignment: .firstTextBaseline) {
                Mono("\(store.start.shortDayMonth) – \(store.end.shortDayMonth)", size: 10.5)
                Spacer()
                // Guarded here as well as in the store. This screen is drawn
                // on the observer's tab, and the editor it opens now makes
                // stamps — which is a claim about somebody else's trip.
                //
                // And not drawn over an empty trip, where "edit" asks a reader
                // to edit what: the empty state's own button is the way in.
                if !isReadOnly && !store.legs.isEmpty {
                    Button { editing = true } label: {
                        // The padding goes on the label, before the shape, so
                        // a near-miss on a 10.5pt word still lands.
                        Mono("edit", size: 10.5, color: Palette.a700)
                            .padding(.leading, Space.s4)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Display(text: spelledDayCount, size: 38)
                .padding(.top, 8)
                .padding(.bottom, Space.s3)

            if store.legs.isEmpty {
                emptyState
            } else {
                itinerary
            }
        }
        .sheet(isPresented: $editing) { ItineraryEditorView() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Nowhere in the trip yet — which is every trip, until somebody types one.
    ///
    /// There was no branch here at all: the screen drew the date range, the
    /// spelled day count and an aside about dragging a city, over nothing to
    /// drag. The app ships with no trip inside it, so this was the state every
    /// new trip opened in.
    @ViewBuilder
    private var emptyState: some View {
        Panel {
            Mono("The plan", size: 9.5, color: Palette.a700)
            Text("Nothing planned yet")
                .font(Typeface.heading(19, .semibold))
                .foregroundStyle(Palette.text)
                .padding(.top, 5)
            Text("The ledger, the papers and the nightly page all work with nowhere in the plan. Add somewhere whenever you know.")
                .font(Typeface.body(12.5))
                .foregroundStyle(Palette.n700)
                .lineSpacing(4)
                .padding(.top, 5)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Guarded for the reason the corner verb is. An observer looking at a
        // trip nobody has filled in sees the panel and no button.
        if !isReadOnly {
            OutlineButton(title: "Plan the trip") { editing = true }
                .padding(.top, Space.s3)
        }
    }

    @ViewBuilder
    private var itinerary: some View {
        ForEach(Array(store.legs.enumerated()), id: \.element.id) { index, leg in
            legHeader(leg)
                .padding(.top, index == 0 ? 0 : Space.s3)

            ForEach(Array(leg.segments.enumerated()), id: \.element.id) { segmentIndex, segment in
                segmentRow(segment, isLast: segmentIndex == leg.segments.count - 1)
            }
        }

        if store.itineraryOverrun > 0 {
            Panel(border: Palette.a300, fill: Palette.a100) {
                Mono("Past your return date", size: 9.5, color: Palette.a700)
                Text("\(store.itineraryOverrun == 1 ? "The last day of this itinerary falls" : "The last \(store.itineraryOverrun) days of this itinerary fall") after you're due home. Change the dates in the trip settings, or drop a stop.")
                    .font(Typeface.body(12.5))
                    .foregroundStyle(Palette.a800)
                    .lineSpacing(4)
                    .padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.s3)
        }

        // Inside this branch: with no legs it describes a gesture on nothing.
        Aside(text: "Nothing here is booked except the flights. Drag a city and the days re-flow.", size: 12)
            .padding(.top, Space.s3)
    }

    private func legHeader(_ leg: Leg) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(leg.country)
                    .font(Typeface.heading(20, .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Mono("\(Formatting.spelledCount(leg.nights, "night", spellingUpTo: 0)) · \(leg.currency.symbol)", size: 10, trackingRatio: 0.08)
            }
            Rule(color: Palette.text)
        }
    }

    @ViewBuilder
    private func segmentRow(_ segment: Segment, isLast: Bool) -> some View {
        let current = segment.contains(day: store.dayNumber)
        let beyondReturn = segment.startDay > store.dayCount

        NavigationLink {
            DayDetailView(day: current ? store.dayNumber : segment.startDay, segment: segment)
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(segment.title)
                        .font(current ? Typeface.heading(15, .semibold) : Typeface.body(13))
                        .foregroundStyle(beyondReturn ? Palette.n500 : Palette.text)
                    Spacer(minLength: 8)
                    if current {
                        Mono("you're here", size: 10, trackingRatio: 0.06, color: Palette.a700)
                    } else {
                        Text(dateRange(segment))
                            .font(Typeface.mono(11))
                            .monospacedDigit()
                            .foregroundStyle(beyondReturn ? Palette.n400 : Palette.n600)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, current ? 8 : 0)
                .background(current ? Palette.a100 : .clear)
                .padding(.horizontal, current ? -8 : 0)

                if !isLast { Rule() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dateRange(_ segment: Segment) -> String {
        let from = store.date(forDay: segment.startDay)
        let to = store.date(forDay: segment.endDay)
        return "\(from.shortDayMonth) – \(to.shortDayMonth)"
    }

    /// "One day", "Sixty-one days", "150 days". The numeral past a hundred was
    /// this screen's own guard and is now `Formatting`'s, along with the plural
    /// it was missing on a one-day trip.
    private var spelledDayCount: String {
        Formatting.spelledCount(store.dayCount, "day")
    }
}
