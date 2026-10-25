import SwiftUI

/// Editing the plan. Segments hold nights and order rather than dates, so
/// every edit here is a mutation plus a reflow, and the days follow.
struct ItineraryEditorView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var addingStopTo: Leg?
    @State private var addingCountry = false
    @State private var confirmingRemoval: Segment?
    @State private var addingWaypointTo: Segment?
    @State private var editingWaypoint: Stamp?
    @State private var editingCountry: Leg?
    @State private var renaming: Segment?
    @State private var placing: Stamp?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Editing the plan", trailing: "Done") {
                Task { await store.syncNow() }
                dismiss()
            }

            List {
                // First, not last: these hold the trail up until somebody
                // answers them, and below eleven stops nobody would.
                if !store.orphanedWaypoints.isEmpty {
                    Section {
                        orphans
                    }
                }

                ForEach(store.legs) { leg in
                    Section {
                        ForEach(leg.segments) { segment in
                            row(segment, in: leg)
                        }
                        .onMove { offsets, destination in
                            store.moveSegments(inLeg: leg.id, from: offsets, to: destination)
                        }

                        Button {
                            addingStopTo = leg
                        } label: {
                            Mono("+ add a stop in \(leg.country)", size: 10, trackingRatio: 0.08, color: Palette.a700)
                                .frame(minHeight: 38)
                        }
                        .listRowBackground(Palette.bg)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(leg.country)
                                    .font(Typeface.heading(17, .semibold))
                                    .foregroundStyle(Palette.text)
                                Spacer()
                                // The name, the money and removing the whole
                                // country all live behind this one word: they
                                // are answers about the country, not the stop.
                                Button { editingCountry = leg } label: {
                                    Mono("edit", size: 10, trackingRatio: 0.08, color: Palette.a700)
                                        .padding(.leading, Space.s4)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            Mono("\(Formatting.spelledCount(leg.nights, "night", spellingUpTo: 0)) · \(leg.currency.code)",
                                 size: 10, trackingRatio: 0.08)
                        }
                        .textCase(nil)
                        .padding(.top, Space.s2)
                    }
                }
                .onMove { offsets, destination in
                    store.moveLegs(from: offsets, to: destination)
                }


                Section {
                    Button {
                        addingCountry = true
                    } label: {
                        Mono("+ add a country", size: 10, trackingRatio: 0.08, color: Palette.a700)
                            .frame(minHeight: 38)
                    }
                    .listRowBackground(Palette.bg)
                }

                Section {
                    summary
                        .listRowBackground(Palette.bg)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
        }
        .background(Palette.bg)
        .sheet(item: $addingStopTo) { leg in
            AddStopView(leg: leg)
        }
        .sheet(item: $addingWaypointTo) { segment in
            WaypointEditorView(segment: segment)
        }
        .sheet(item: $editingWaypoint) { stamp in
            WaypointEditorView(segment: store.segment(for: stamp), stamp: stamp)
        }
        .sheet(isPresented: $addingCountry) {
            AddCountryView()
        }
        .sheet(item: $editingCountry) { leg in
            CountryEditorView(leg: leg)
        }
        .sheet(item: $renaming) { segment in
            RenameStopView(segment: segment)
        }
        .sheet(item: $placing) { stamp in
            PlaceStampView(stamp: stamp)
        }
    }

    // MARK: - Stamps with no stop

    /// A stamp whose stop went in a merge: the other phone removed the stop
    /// while this one stamped it. Unattended it is "next" on the trail and
    /// holds the last-stamp letter shut, so each one is put somewhere or let go.
    @ViewBuilder
    private var orphans: some View {
        VStack(alignment: .leading, spacing: 4) {
            Mono("Stamps with no stop", size: 10, color: Palette.a700)
            Aside(text: "Their stop was removed on the other phone. Put each one on a stop, or let it go.",
                  size: 12, color: Palette.n600)
        }
        .padding(.top, Space.s3)
        .listRowBackground(Palette.bg)

        ForEach(store.orphanedWaypoints) { stamp in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stamp.code)
                    .font(Typeface.mono(10.5))
                    .foregroundStyle(Palette.a700)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(Rectangle().strokeBorder(Palette.a300, lineWidth: 1))
                Mono(stamp.city, size: 9.5, trackingRatio: 0.08)
                Spacer(minLength: 0)
                Button { placing = stamp } label: {
                    Mono("place it", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                        .padding(.vertical, 8)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The removal and its guards are the stamp editor's, which
                // already says what a letter loses.
                Button { editingWaypoint = stamp } label: {
                    Mono("edit", size: 9.5, trackingRatio: 0.08, color: Palette.n600)
                        .padding(.vertical, 8)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Palette.bg)
        }
    }

    // MARK: - A stop

    @ViewBuilder
    private func row(_ segment: Segment, in leg: Leg) -> some View {
        // Read once: it walks every stamp and letter on the trip.
        let removal = store.removalSummary(ofSegments: [segment.id])
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(segment.title)
                    .font(Typeface.heading(16, .semibold))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text(range(segment))
                    .font(Typeface.mono(10.5))
                    .monospacedDigit()
                    .foregroundStyle(beyondReturn(segment) ? Palette.n400 : Palette.n600)
            }

            HStack(spacing: 10) {
                Stepper {
                    Mono("\(Formatting.spelledCount(segment.nights, "night", spellingUpTo: 0))",
                         size: 10, trackingRatio: 0.08, color: Palette.a700)
                } onIncrement: {
                    store.setNights(segment.nights + 1, forSegment: segment.id)
                } onDecrement: {
                    store.setNights(segment.nights - 1, forSegment: segment.id)
                }
                .labelsHidden()
                .fixedSize()

                Mono("\(Formatting.spelledCount(segment.nights, "night", spellingUpTo: 0))",
                     size: 10, trackingRatio: 0.08, color: Palette.a700)

                Spacer()

                Button {
                    renaming = segment
                } label: {
                    Mono("rename", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                        .padding(.vertical, 8)
                        .padding(.trailing, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Absent rather than greyed when it is refused, the way the
                // stamp's own remove is; the reason is said under the row.
                if removal.refusal == nil {
                    Button(role: .destructive) {
                        confirmingRemoval = segment
                    } label: {
                        Mono("remove", size: 9.5, trackingRatio: 0.08, color: Palette.n600)
                            .padding(.vertical, 8)
                            .padding(.leading, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let refusal = removal.refusal {
                Mono(refusal, size: 9, trackingRatio: 0.06, color: Palette.a700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            waypointRow(segment)

            // Written days a shortened stop no longer has. Kept, and back the
            // moment the nights are.
            let setAside = store.setAsidePlans(forSegment: segment.id)
            if !setAside.isEmpty {
                Mono(setAsideLine(setAside, in: segment), size: 9, trackingRatio: 0.06, color: Palette.n600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Palette.bg)
        .confirmationDialog("Remove \(confirmingRemoval?.title ?? "")?",
                            isPresented: Binding(get: { confirmingRemoval?.id == segment.id },
                                                 set: { if !$0 { confirmingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button(removal.stamps.isEmpty ? "Remove the stop" : "Remove the stop and its stamps",
                   role: .destructive) {
                store.removeSegment(segment.id)
                confirmingRemoval = nil
            }
            Button("Keep it", role: .cancel) { confirmingRemoval = nil }
        } message: {
            Text(Self.removalMessage(removal))
        }
    }

    /// What a removal takes, in one paragraph: the dialog has room for a
    /// message and nothing else. Shared with the country sheet.
    static func removalMessage(_ removal: TripStore.StopRemoval, leading: String = "The days after it move up.") -> String {
        var parts = [leading]
        if !removal.stamps.isEmpty {
            let codes = removal.stamps.map(\.code)
            parts.append(codes.count == 1
                         ? "Its \(codes[0]) stamp goes with it."
                         : "Its stamps go with it: \(codes.joined(separator: ", ")).")
        }
        if let cost = removal.letterCost { parts.append(cost) }
        if removal.planCount > 0 {
            parts.append(removal.planCount == 1
                         ? "The day written in it goes too, on both phones."
                         : "The \(Formatting.spelledCount(removal.planCount, "day").lowercased()) written in it go too, on both phones.")
        }
        parts.append("Money spent there stays where it is.")
        return parts.joined(separator: " ")
    }

    private func setAsideLine(_ plans: [DayPlan], in segment: Segment) -> String {
        let days = plans.compactMap(\.dayOfStop).map { "day \($0 + 1)" }
        let list = days.count == 1 ? days[0] : days.dropLast().joined(separator: ", ") + " and " + days.last!
        return days.count == 1
            ? "\(list)'s plan is set aside until the stop is that long again"
            : "the plans for \(list) are set aside until the stop is that long again"
    }

    // MARK: - The stamp on a stop

    /// The waypoint line under a stop.
    ///
    /// A stop and its stamp are the same answer asked twice — where are we
    /// going, and what does arriving there mean — so this is where the stamps
    /// are made, rather than on a screen of their own. It is also the only
    /// place a trip nobody packed can get a trail at all.
    @ViewBuilder
    private func waypointRow(_ segment: Segment) -> some View {
        // Read once. `waypoints(forSegment:)` resolves the stop of every stamp
        // on the trip, and this is drawn per row of the editor.
        let here = store.waypoints(forSegment: segment.id)

        // Every waypoint on the stop, not the first of them. A stop that names
        // two places holds two stamps, and drawing one of them puts the other
        // beyond reach of every screen there is.
        ForEach(here) { stamp in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stamp.code)
                    .font(Typeface.mono(10.5))
                    .foregroundStyle(Palette.a700)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(Rectangle().strokeBorder(Palette.a300, lineWidth: 1))

                if let locked = store.waypointIsLocked(stamp) {
                    // Earned. Static text and no controls at all, the way the
                    // badge on the trail is — this is a record, not a field.
                    Mono(locked, size: 9.5, trackingRatio: 0.08)
                    Spacer(minLength: 0)
                } else {
                    Mono(stamp.city, size: 9.5, trackingRatio: 0.08)
                    Spacer(minLength: 0)
                    Button {
                        editingWaypoint = stamp
                    } label: {
                        Mono("edit", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                            .padding(.vertical, 8)
                            .padding(.leading, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Said under the row rather than in a dialog nobody has opened yet:
            // the cost of removing it is a thing to know before deciding to.
            if let refusal = store.removalRefusal(ofWaypoint: stamp) {
                Mono(refusal, size: 9, trackingRatio: 0.06, color: Palette.a700)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let cost = store.removalCost(ofWaypoint: stamp) {
                Mono(cost, size: 9, trackingRatio: 0.06, color: Palette.n600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // Offered whether or not the stop already has one.
        //
        // The read path was made plural — "Ayutthaya · Pai" is one stop naming
        // two places and holding two stamps, and returning only the first put
        // AYU beyond reach of every screen. The *write* path was left singular,
        // so the state that fix exists for could only be reached on a trip that
        // arrived packed: a trip typed from scratch could never make the second
        // one. This editor's own copy says "A stop can name two places".
        //
        // Still refused once a `.finalStamp` letter has already opened, which
        // is `appendCost`'s job and not this row's.
        if !store.appendCost().refused {
            Button {
                addingWaypointTo = segment
            } label: {
                Mono(here.isEmpty ? "+ a stamp for this stop" : "+ another stamp for this stop",
                     size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                    .padding(.vertical, 8)
                    .padding(.trailing, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func range(_ segment: Segment) -> String {
        let from = store.date(forDay: segment.startDay)
        let to = store.date(forDay: segment.endDay)
        return "\(from.shortDayMonth) – \(to.shortDayMonth)"
    }

    private func beyondReturn(_ segment: Segment) -> Bool {
        segment.startDay > store.dayCount
    }

    // MARK: - Does it fit?

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Mono("The plan", size: 10)
                Spacer()
                Mono("\(Formatting.spelledCount(store.itinerary.totalNights, "night", spellingUpTo: 0))", size: 10, trackingRatio: 0.08, color: Palette.a700)
            }

            if store.itineraryOverrun > 0 {
                Aside(text: "That's \(Formatting.spelledCount(store.itineraryOverrun, "day", spellingUpTo: 0)) past the date you're due home.", size: 12)
                OutlineButton(title: "Move the return date to match", minHeight: 44, size: 14) {
                    store.matchDatesToItinerary()
                }
                .padding(.top, 4)
            } else if store.itinerary.lastDay < store.dayCount {
                let spare = store.dayCount - store.itinerary.lastDay
                Aside(text: "\(Formatting.spelledCount(spare, "day", spellingUpTo: 0)) of the trip \(spare == 1 ? "isn't" : "aren't") planned yet. That's allowed.", size: 12)
            } else {
                Aside(text: "The plan fills the trip exactly.", size: 12)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - The fields a stamp is

/// One underlined field. Three sheets in this file drew their own copy.
struct UnderlinedField: View {
    @Binding var text: String
    let placeholder: String
    /// The prompt is a `Text`, which takes a `Font` rather than a `TypeSpec`,
    /// so it has to be resolved by hand — against the reader's size, not a
    /// fixed `.large`, or at an accessibility size the grey prompt stays at
    /// 17pt under a label that has grown to three times that.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            TextField("", text: $text, prompt: Text(placeholder)
                .font(Typeface.body(17).resolved(for: typeSize))
                .foregroundStyle(Palette.n400))
                .font(Typeface.body(17))
                .foregroundStyle(Palette.text)
                .frame(minHeight: 44)
            Rule()
        }
    }
}

/// The answers a stamp is: its code, which of the stop's places it stands for,
/// and what it says on arrival.
///
/// Shared by the sheet that makes a stop and the one that edits its stamp, so
/// the two can't drift. They already had: the read path was made plural for
/// "Ayutthaya · Pai" while the write path stayed singular, and the state the
/// plural fix exists for could only be reached on a trip that arrived packed.
///
/// The place is a choice among the stop's own names rather than a text field.
/// On the ordinary stop there is one, so there is no control at all and the
/// city is the stop — a second field prefilled with a copy of the title asks a
/// question the stop has already answered. Only a stop naming two places has
/// anything to ask.
private struct StampFields: View {
    @EnvironmentObject private var store: TripStore

    /// The places the stop names — read off a `Segment` when there is one, and
    /// off the title still being typed when there isn't.
    let places: [String]
    /// The stamp being edited, so its own code doesn't read as taken.
    var excluding: UUID?

    @Binding var code: String
    @Binding var city: String
    @Binding var arrivalNote: String

    @State private var suggested = ""

    /// Only a stamp being made takes a suggested code. An existing one holds an
    /// answer somebody chose and a sealed letter may already name it.
    private var suggests: Bool { excluding == nil }

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// The stop's places, plus whatever this stamp already says when the two
    /// have drifted apart — a stop renamed after its stamp was made keeps the
    /// answer somebody chose. Rewriting it silently would move the city a
    /// `.place` letter is sealed to.
    private var options: [String] {
        var all: [String] = []
        for place in places where !all.contains(place) { all.append(place) }
        // Only a stamp that already exists can have drifted, and only its
        // answer is worth keeping. Offering the same escape hatch to a stamp
        // being made lets a half-typed title become an option: "Bangkok" typed
        // one letter at a time left `Ban` selected against `Bangkok`, because
        // the city was in this list by virtue of being in it.
        if !suggests {
            let current = city.trimmingCharacters(in: .whitespaces)
            if !current.isEmpty, !all.contains(current) { all.append(current) }
        }
        return all
    }

    /// The waypoint this city already has, when it isn't this one. A city can
    /// be entered twice — Bangkok out and Bangkok home — and the code can't.
    private var firstVisit: Stamp? {
        guard let already = store.waypoint(forCity: city), already.id != excluding else { return nil }
        return already
    }

    private var codeIsUsable: Bool {
        store.codeIsAvailable(trimmedCode, excluding: excluding)
    }

    /// Said before the field is filled in rather than after it is refused — a
    /// control that rejects what you typed without having said what it wanted
    /// is a control you learn by failing. On a city that has been here before,
    /// it says whose code the seeded one is a second of, because `BKK2` on its
    /// own is a label with no story.
    private var codeNote: String {
        if !trimmedCode.isEmpty, !(2...4).contains(trimmedCode.count) { return "two to four letters" }
        if !trimmedCode.isEmpty, !codeIsUsable { return "\(trimmedCode) is already on another stop" }
        if let already = firstVisit {
            return "\(already.code) is the first \(already.city). This one is another time you're here."
        }
        return "two to four letters — it prints inside a circle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Code", size: 10).padding(.bottom, 4)
            UnderlinedField(text: $code, placeholder: "CNX")
            Mono(codeNote, size: 9, trackingRatio: 0.06,
                 color: trimmedCode.isEmpty || codeIsUsable ? Palette.n600 : Palette.a700)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            if options.count > 1 {
                Mono("Which of them the stamp is for", size: 10)
                    .padding(.top, Space.s3)
                    .padding(.bottom, 7)
                FlowRow(spacing: Space.s2) {
                    ForEach(options, id: \.self) { place in
                        Chip(text: place, selected: city == place) { city = place }
                    }
                }
                Aside(text: "The stamp is for the one you have to be standing in.",
                      size: 11.5, color: Palette.n600)
                    .padding(.top, 5)
            }

            Mono("What it says when you get there", size: 10)
                .padding(.top, Space.s3)
                .padding(.bottom, 4)
            UnderlinedField(text: $arrivalNote, placeholder: "You're standing in it.")
        }
        .onAppear { settle() }
        .onChange(of: places) { _, _ in settle() }
        .onChange(of: city) { _, _ in suggest() }
    }

    /// Keeps the city an answer the stop can still give. A stop with one place
    /// has no picker, so nothing else would ever set it.
    private func settle() {
        let all = options
        if !all.contains(city) { city = all.first ?? "" }
        suggest()
    }

    /// Seeds the code, and stops the moment somebody types over it: the field
    /// is only followed while it still holds exactly what was last offered.
    private func suggest() {
        guard suggests else { return }
        let next = store.suggestedCode(forCity: city)
        if code.isEmpty || trimmedCode == suggested { code = next }
        suggested = next
    }
}

// MARK: - Adding

/// Whether the stop being typed will be on the map, said under its name.
///
/// Derived, never stored: the position goes on the stamp when one is made
/// (`addWaypoint`), and a stop with no stamp has nowhere it needs one. Said
/// because a stop the list can't find has no nudge and no distance until
/// somebody stands in it, and that should not be a surprise on the day.
private struct OnTheMapLine: View {
    @EnvironmentObject private var store: TripStore
    let places: [String]
    let country: String

    var body: some View {
        if let first = places.first, !country.trimmingCharacters(in: .whitespaces).isEmpty {
            let found = store.position(ofCity: first, inCountry: country)
            VStack(alignment: .leading, spacing: 2) {
                Mono(found.map { "on the map · \(Self.coordinate($0))" } ?? "not on the map yet",
                     size: 9.5, trackingRatio: 0.08, color: found == nil ? Palette.n600 : Palette.a700)
                Aside(text: found == nil
                      ? "It gets a position the first time you arrive."
                      : "From the city list on this phone. No signal needed.",
                      size: 11.5, color: Palette.n600)
            }
            .padding(.top, 6)
        }
    }

    private static func coordinate(_ position: CityPositions.Position) -> String {
        let lat = Formatting.decimal(abs(position.latitude), places: 2, grouping: false)
        let lon = Formatting.decimal(abs(position.longitude), places: 2, grouping: false)
        return "\(lat) \(position.latitude < 0 ? "S" : "N"), \(lon) \(position.longitude < 0 ? "W" : "E")"
    }
}

/// The whole stamp half of a sheet that makes a stop: the rule, the heading, the
/// sentence saying the code is optional, the warning when appending one costs
/// something, and the fields.
///
/// Shared by both sheets that make a stop, for the reason `StampFields` is
/// shared by both that make a stamp. `AddCountryView` used to have none of this
/// and a comment explaining why, so the *first* stop in every country was the
/// one stop in the app whose stamp had to be added afterwards, from a different
/// sheet, through a control on a row. The two are the same question and now ask
/// it the same way.
private struct StampSection: View {
    @EnvironmentObject private var store: TripStore

    let places: [String]
    @Binding var code: String
    @Binding var city: String
    @Binding var arrivalNote: String

    /// Absent once a `.finalStamp` letter has already opened — `appendCost`'s
    /// call, not this sheet's, and the stop itself is still allowed.
    var body: some View {
        let cost = store.appendCost()
        if !cost.refused {
            Rule().padding(.top, Space.s4)

            Mono("Its stamp", size: 10, color: Palette.a700)
                .padding(.top, Space.s4)
            Aside(text: "Leave the code empty for a stop that's only somewhere to sleep on the way through.",
                  size: 11.5, color: Palette.n600)
                .padding(.top, 4)
                .padding(.bottom, Space.s3)

            if let warning = cost.message {
                Panel(border: Palette.a300, fill: Palette.a100) {
                    Mono("Before you add this", size: 9.5, color: Palette.a700)
                    Aside(text: warning, size: 12.5)
                        .padding(.top, 4)
                }
                .padding(.bottom, Space.s3)
            }

            StampFields(places: places, code: $code, city: $city, arrivalNote: $arrivalNote)
        }
    }
}

/// A stop, and what arriving there means.
///
/// The stamp is asked for here rather than behind a second control on the row
/// afterwards, because a stop and its stamp are the same answer asked twice —
/// where are we going, and what does getting there mean. Asking separately also
/// meant the city was asked twice: once as the stop's title, and again as a
/// text field prefilled with a copy of it.
struct AddStopView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    let leg: Leg
    /// What the title starts as. Only `-screen addstop` passes one, so the
    /// "on the map" line can be photographed without a keyboard.
    var initialTitle = ""

    @State private var title = ""
    @State private var nights = 3
    @State private var code = ""
    @State private var city = ""
    @State private var arrivalNote = ""
    @State private var askingToDiscard = false
    @FocusState private var focused: Bool

    /// What somebody typed. The stamp's code and city seed themselves off the
    /// title, so they are not counted on their own.
    private var isDirty: Bool { !title.isEmpty || !arrivalNote.isEmpty }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var trimmedCode: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    /// One splitter, and this is the one. The stop has no segment yet, so the
    /// places come off the title being typed.
    private var places: [String] { Segment.places(in: title) }

    /// A stop may go in without a stamp — plenty are only somewhere to sleep on
    /// the way through. What it may not do is go in with a *refused* one, which
    /// would make the stop, drop the stamp, and report success.
    private var canAdd: Bool {
        !trimmedTitle.isEmpty && (trimmedCode.isEmpty || store.codeIsAvailable(trimmedCode))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New stop", trailing: "Cancel") {
                if isDirty { askingToDiscard = true } else { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("In \(leg.country)", size: 10.5)

                    Display(text: "Where next", size: 34)
                        .padding(.top, 8)
                        .padding(.bottom, Space.s3)

                    TextField("", text: $title, prompt: Text("Hue")
                        .font(Typeface.heading(23).resolved(for: .large))
                        .foregroundStyle(Palette.n400))
                        .font(Typeface.heading(23))
                        .foregroundStyle(Palette.text)
                        .focused($focused)
                        .frame(minHeight: 48)

                    Rectangle().fill(Palette.accent).frame(height: 1)

                    OnTheMapLine(places: places, country: leg.country)

                    HStack {
                        Mono("Nights", size: 10)
                        Spacer()
                        Stepper("", value: $nights, in: 1...120)
                            .labelsHidden()
                        Text("\(nights)")
                            .font(Typeface.mono(14))
                            .monospacedDigit()
                            .foregroundStyle(Palette.a700)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.top, Space.s4)

                    StampSection(places: places, code: $code, city: $city,
                                 arrivalNote: $arrivalNote)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            OutlineButton(title: "Add it") { add() }
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.4)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard) { dismiss() }
        .onAppear {
            if title.isEmpty { title = initialTitle }
            focused = initialTitle.isEmpty
        }
    }

    private func add() {
        let made = store.addSegment(title: trimmedTitle, nights: nights, toLeg: leg.id)
        if let made, !trimmedCode.isEmpty {
            store.addWaypoint(code: trimmedCode, city: city, arrivalNote: arrivalNote,
                              toSegment: made.id)
        }
        dismiss()
    }
}

private struct AddCountryView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var country = ""
    @State private var firstStop = ""
    /// The likely currency once the country is typed, until somebody picks
    /// one. It was baht for every new country.
    @State private var currency: Currency = .eur
    @State private var currencyChosen = false
    @State private var nights = 7
    @State private var code = ""
    @State private var city = ""
    @State private var arrivalNote = ""
    @State private var askingToDiscard = false

    private var isDirty: Bool { !country.isEmpty || !firstStop.isEmpty || !arrivalNote.isEmpty }

    private var trimmedCode: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    /// The same splitter the stop sheet uses, off the title still being typed —
    /// a country's first stop can name two places just as any other stop can.
    private var places: [String] { Segment.places(in: firstStop) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New country", trailing: "Cancel") {
                if isDirty { askingToDiscard = true } else { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Display(text: "Somewhere\nelse", size: 34)
                        .padding(.bottom, Space.s3)

                    Mono("Country", size: 10).padding(.bottom, 4)
                    UnderlinedField(text: $country, placeholder: "Cambodia")

                    Mono("First stop", size: 10)
                        .padding(.top, Space.s3)
                        .padding(.bottom, 4)
                    UnderlinedField(text: $firstStop, placeholder: "Siem Reap")
                    OnTheMapLine(places: places, country: country)

                    Mono("They spend", size: 10)
                        .padding(.top, Space.s3)
                        .padding(.bottom, 7)
                    // Only currencies the app can get a rate for.
                    CurrencyChips(selected: currency,
                                  suggested: [Currency.likely(forCountry: country),
                                              store.localCurrency, store.homeCurrency]) {
                        currency = $0
                        currencyChosen = true
                    }

                    HStack {
                        Mono("Nights", size: 10)
                        Spacer()
                        Stepper("", value: $nights, in: 1...120).labelsHidden()
                        Text("\(nights)")
                            .font(Typeface.mono(14))
                            .monospacedDigit()
                            .foregroundStyle(Palette.a700)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.top, Space.s4)

                    // Asked here rather than left to the row afterwards. A
                    // country's first stop is a stop, and this was the one place
                    // in the app where making one and saying what arriving there
                    // means were two separate trips through two different sheets.
                    StampSection(places: places, code: $code, city: $city,
                                 arrivalNote: $arrivalNote)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            OutlineButton(title: "Add it") { add() }
                .disabled(!isComplete)
                .opacity(isComplete ? 1 : 0.4)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard) { dismiss() }
        .onAppear { currency = store.localCurrency }
        // A suggestion, like the destination step's: it follows the country
        // until a chip is tapped, and is never applied behind a choice.
        .onChange(of: country) { _, typed in
            guard !currencyChosen, let likely = Currency.likely(forCountry: typed) else { return }
            currency = likely
        }
    }

    /// A leg may go in without a stamp on its first stop. What it may not do is
    /// go in with a *refused* one — the same rule `AddStopView.canAdd` holds, and
    /// for the same reason: making the leg and dropping the stamp would report
    /// success for something that didn't happen.
    private var isComplete: Bool {
        !country.trimmingCharacters(in: .whitespaces).isEmpty &&
        !firstStop.trimmingCharacters(in: .whitespaces).isEmpty &&
        (trimmedCode.isEmpty || store.codeIsAvailable(trimmedCode))
    }

    private func add() {
        let made = store.addLeg(country: country.trimmingCharacters(in: .whitespaces),
                                currency: currency,
                                firstStop: firstStop.trimmingCharacters(in: .whitespaces),
                                nights: nights)
        if let made, !trimmedCode.isEmpty {
            store.addWaypoint(code: trimmedCode, city: city, arrivalNote: arrivalNote,
                              toSegment: made.id)
        }
        dismiss()
    }
}

/// The stamp on one stop.
///
/// Reached from the itinerary editor and nowhere else, because a stamp is an
/// answer about the plan: what does arriving here mean, and does anything open
/// when it does. It doesn't offer which letter it opens: that is the writer's
/// question, asked on their own phone, and a second way to key a letter would
/// be a second thing for the two sides to disagree about.
private struct WaypointEditorView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    var segment: Segment?
    var stamp: Stamp?

    @State private var code = ""
    @State private var city = ""
    @State private var arrivalNote = ""
    @State private var confirmingRemoval = false
    @State private var askingToDiscard = false

    private var isNew: Bool { stamp == nil }

    /// A new stamp's code and city seed themselves, so only the note counts
    /// as typed; an existing one is dirty when any field moved.
    private var isDirty: Bool {
        guard let stamp else { return !arrivalNote.isEmpty }
        return code != stamp.code || city != stamp.city || arrivalNote != stamp.arrivalNote
    }

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var canSave: Bool {
        store.codeIsAvailable(trimmedCode, excluding: stamp?.id)
            && !city.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "A stamp for this stop" : "This stop's stamp",
                        trailing: "Cancel") {
                if isDirty { askingToDiscard = true } else { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Display(text: segment?.title ?? city, size: 30)
                        .padding(.bottom, Space.s3)

                    if isNew, let warning = store.appendCost().message {
                        Panel(border: Palette.a300, fill: Palette.a100) {
                            Mono("Before you add this", size: 9.5, color: Palette.a700)
                            Aside(text: warning, size: 12.5)
                                .padding(.top, 4)
                        }
                        .padding(.bottom, Space.s3)
                    }

                    StampFields(places: segment?.places ?? [], excluding: stamp?.id,
                                code: $code, city: $city, arrivalNote: $arrivalNote)

                    if !isNew, let stamp {
                        if let refusal = store.removalRefusal(ofWaypoint: stamp) {
                            Panel(border: Palette.a300, fill: Palette.a100) {
                                Mono("This one can't be removed", size: 9.5, color: Palette.a700)
                                Aside(text: refusal, size: 12.5).padding(.top, 4)
                            }
                            .padding(.top, Space.s4)
                        } else if let cost = store.removalCost(ofWaypoint: stamp) {
                            Panel(border: Palette.a300, fill: Palette.a100) {
                                Mono("Something is waiting on this", size: 9.5, color: Palette.a700)
                                Aside(text: cost, size: 12.5).padding(.top, 4)
                            }
                            .padding(.top, Space.s4)
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            HStack(spacing: 10) {
                // Absent rather than greyed. Greying is the pattern for a
                // picker of options; a destructive control that cannot fire is
                // a dead control, and those are worse than missing ones.
                if !isNew, let stamp, store.removalRefusal(ofWaypoint: stamp) == nil {
                    Button(role: .destructive) {
                        confirmingRemoval = true
                    } label: {
                        Mono("remove the stamp", size: 9.5, trackingRatio: 0.08, color: Palette.n600)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 8)
                OutlineButton(title: isNew ? "Add it" : "Save", minHeight: 46, size: 15,
                              fillsWidth: false, horizontalPadding: 22) {
                    save()
                }
                .disabled(!canSave)
                .opacity(canSave ? 0.999 : 0.4)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .task(id: stamp?.id) { load() }
        .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard) { dismiss() }
        .confirmationDialog("Remove this stamp?", isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button("Remove it", role: .destructive) {
                if let stamp { store.removeWaypoint(stamp.id) }
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(store.removalCost(ofWaypoint: stamp ?? Stamp(code: "", city: "", index: 0, arrivalNote: ""))
                 ?? "The stop stays. Nothing else on the trip changes.")
        }
    }

    /// Keyed on the waypoint by `.task(id:)`, and with no one-shot guard in
    /// front of it.
    ///
    /// A `loaded` flag used to sit here, which cancelled out the keying: `@State`
    /// survives the view being rebuilt with a different `stamp`, so the second
    /// waypoint on a stop would have opened showing the first one's code under
    /// its own header. That is the `DayPlanEditorView` bug, and `.task(id:)` is
    /// already the fix for it — the flag only stopped it working.
    private func load() {
        if let stamp {
            code = stamp.code
            city = stamp.city
            arrivalNote = stamp.arrivalNote
        } else if let segment {
            // The first half of a "Hội An · Đà Nẵng" is the one the stamp is
            // usually for. `StampFields` would settle on the same place; this
            // is here so the code it seeds has a city on the first pass.
            city = segment.primaryPlace
        }
    }

    private func save() {
        if let stamp {
            store.updateWaypoint(stamp.id, code: trimmedCode, city: city, arrivalNote: arrivalNote)
        } else if let segment {
            store.addWaypoint(code: trimmedCode, city: city, arrivalNote: arrivalNote,
                              toSegment: segment.id)
        }
        dismiss()
    }
}

// MARK: - Editing what exists

/// The country: its name, its money, and taking it out of the trip.
///
/// One sheet behind "edit" on the header, because all three are answers about
/// the country rather than any stop in it. It edits something that exists, so
/// it commits on the way out (§5.1) rather than behind a Save that a swipe
/// would skip.
struct CountryEditorView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    let leg: Leg

    @State private var country = ""
    @State private var currency: Currency = .eur
    @State private var confirmingRemoval = false
    @State private var removed = false

    /// The leg as it is now, not as it was when the sheet opened.
    private var live: Leg? { store.legs.first { $0.id == leg.id } }

    var body: some View {
        // Read once: it walks every stamp and letter on the trip.
        let removal = store.removalSummary(ofSegments: (live ?? leg).segments.map(\.id))
        VStack(spacing: 0) {
            SheetHeader(title: "This country", trailing: "Done") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Display(text: country.isEmpty ? leg.country : country, size: 30)
                        .padding(.bottom, Space.s3)

                    Mono("Country", size: 10).padding(.bottom, 4)
                    UnderlinedField(text: $country, placeholder: leg.country)

                    Mono("They spend", size: 10)
                        .padding(.top, Space.s3)
                        .padding(.bottom, 7)
                    CurrencyChips(selected: currency,
                                  suggested: [Currency.likely(forCountry: country), leg.currency,
                                              store.homeCurrency]) { currency = $0 }
                    Aside(text: "Changes what new lines are in. Lines already spent keep theirs.",
                          size: 11.5, color: Palette.n600)
                        .padding(.top, 5)

                    if let refusal = removal.refusal {
                        Panel(border: Palette.a300, fill: Palette.a100) {
                            Mono("This one can't be removed", size: 9.5, color: Palette.a700)
                            Aside(text: refusal, size: 12.5).padding(.top, 4)
                        }
                        .padding(.top, Space.s4)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            // Absent rather than greyed when it is refused: the panel above
            // says why.
            if removal.refusal == nil {
                HStack {
                    Button(role: .destructive) {
                        confirmingRemoval = true
                    } label: {
                        Mono("remove the country", size: 9.5, trackingRatio: 0.08, color: Palette.n600)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
            }
        }
        .background(Palette.bg)
        .task(id: leg.id) {
            country = leg.country
            currency = leg.currency
        }
        .onDisappear {
            guard !removed else { return }
            store.renameLeg(leg.id, country: country)
            store.setCurrency(currency, forLeg: leg.id)
        }
        .confirmationDialog("Remove \(leg.country)?", isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button(removal.stamps.isEmpty ? "Remove the country" : "Remove it and its stamps",
                   role: .destructive) {
                removed = store.removeLeg(leg.id)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            let stops = (live ?? leg).segments.count
            Text(ItineraryEditorView.removalMessage(
                removal,
                leading: stops == 1
                    ? "Its stop goes, and the days after it move up."
                    : "\(Formatting.spelledCount(stops, "stop")) go, and the days after them move up."))
        }
    }
}

/// A stop's name.
///
/// The stamps on it stay on it, and keep the cities their letters are sealed
/// to — the store sees to both. Commits on the way out, like every sheet that
/// edits something that exists.
struct RenameStopView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    let segment: Segment

    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Renaming a stop", trailing: "Done") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("Was \(segment.title)", size: 10.5)

                    TextField("", text: $title, prompt: Text(segment.title)
                        .font(Typeface.heading(23).resolved(for: .large))
                        .foregroundStyle(Palette.n400))
                        .font(Typeface.heading(23))
                        .foregroundStyle(Palette.text)
                        .focused($focused)
                        .frame(minHeight: 48)
                        .padding(.top, Space.s3)

                    Rectangle().fill(Palette.accent).frame(height: 1)

                    Aside(text: "Two places go on one stop with a dot between them: Hội An · Đà Nẵng. Its stamps stay on it.",
                          size: 11.5, color: Palette.n600)
                        .padding(.top, 6)
                }
                .padding(.horizontal, Space.gutter)
            }
        }
        .background(Palette.bg)
        .task(id: segment.id) {
            title = segment.title
            focused = true
        }
        .onDisappear { store.renameSegment(segment.id, title: title) }
    }
}

/// Puts a stamp whose stop is gone onto one that isn't.
struct PlaceStampView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    let stamp: Stamp

    @State private var chosen: UUID?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Placing a stamp", trailing: "Cancel") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("\(stamp.code) · \(stamp.city)", size: 10.5, color: Palette.a700)
                    Display(text: "Which stop is it for", size: 30)
                        .padding(.top, 8)
                        .padding(.bottom, Space.s3)

                    ForEach(store.legs) { leg in
                        Mono(leg.country, size: 10)
                            .padding(.top, Space.s2)
                            .padding(.bottom, 7)
                        FlowRow(spacing: Space.s2) {
                            ForEach(leg.segments) { segment in
                                Chip(text: segment.title, selected: chosen == segment.id) {
                                    chosen = segment.id
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            OutlineButton(title: "Put it there") {
                if let chosen { store.attachWaypoint(stamp.id, toSegment: chosen) }
                dismiss()
            }
            .disabled(chosen == nil)
            .opacity(chosen == nil ? 0.4 : 1)
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
    }
}
