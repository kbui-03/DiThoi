import SwiftUI
import MapKit

/// D1 · The trail. One trail, both of them, and the only screen that can hand
/// out a stamp.
struct TrailView: View {
    @EnvironmentObject private var store: TripStore
    /// False when the shelf pushes this inside its own stack. As a tab root it
    /// needs a navigation container; pushed, it would be a second one.
    var embedsNavigation: Bool = true
    /// Home mode and the shelf both set this. Everything on the screen still
    /// draws; the one control that hands out a stamp does not.
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.arrivalRequest) private var arrivalRequest
    @State private var earned: Stamp?
    @State private var unlocked: [Letter] = []
    @State private var showingStamp = false
    @State private var readingLetter: Letter?
    /// The waypoint the dialog is asking about.
    ///
    /// Held rather than re-read. `arrive()` used to ask the store for
    /// `nextStamp` again, and between drawing the panel and the tap a sync
    /// round can add a waypoint and `reflowWaypoints()` can renumber — so the
    /// pin could land on a city the dialog never named, under a sentence
    /// promising it can't be undone.
    @State private var arriving: Stamp?
    @State private var composingMoment = false
    @State private var editingMoment: Moment?
    @State private var deletedMoment: Moment?
    @State private var keptSpot: Moment?
    /// "Keep a moment here", tapped on the stamp screen. Held until the cover
    /// has gone, then handed to `composingAt` — a sheet started while a
    /// full-screen cover is still animating out is the `PhotoIntake` race.
    @State private var keepingAt: Stamp?
    @State private var composingAt: Stamp?
    /// One destination for every push, never two `isPresented:` — stacked,
    /// the later swallows the earlier and the push silently does nothing,
    /// which is how `TodayView` once had a dead control.
    @State private var going: TrailDestination?

    /// How many moments the trail itself lists. The rest are one row away,
    /// because a list that grows with the trip is what used to push the way
    /// to make one off the bottom of the screen.
    static let momentsShown = 3

    /// Whether a moment can be made from here at all. `isReadOnly` is the
    /// courtesy the shelf and home mode inject; `isLive` is the state, since a
    /// trip closed a minute ago is still on screen and injects nothing.
    private var canMark: Bool { !isReadOnly && store.isLive && !store.isObserver }

    /// A position worth drawing: this phone's own, on a traveller's live trip,
    /// and recent. On the observer's phone it would put their kitchen on
    /// somebody else's trail — the reason `arrive(at:)` refuses them.
    private var here: CLLocation? { canMark ? store.location.current.flatMap(TrailView.fresh) : nil }

    /// Fifteen minutes. A distance is a claim about now, and a number without
    /// its age pretends to be current.
    static func fresh(_ location: CLLocation) -> CLLocation? {
        -location.timestamp.timeIntervalSinceNow < 15 * 60 ? location : nil
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 4)

    /// Before the second earned waypoint there is no distance yet, so the
    /// headline changes shape rather than printing "0 km and counting".
    private var headline: String {
        let km = store.kilometresTravelled
        guard km > 0 else { return "The trail\nstarts here" }
        return "\(Formatting.decimal(Double(km), places: 0)) km\nand counting"
    }

    @ViewBuilder
    var body: some View {
        if embedsNavigation {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        Screen(context: .syncState) {
            // The way to keep a moment lives up here, above the map. At the
            // bottom it sat under every stamp and every moment so far, so the
            // further the trip went the further away it got — for the one
            // thing that is only ever worth doing in the next ten seconds.
            MarkMomentLabel("The trail so far", size: 10.5, canMark: canMark,
                            onKeepSpot: keepSpot) {
                composingMoment = true
            }

            // Counted along the waypoints they have earned, so "and counting"
            // is a number that actually grows.
            Display(text: headline, size: 38)
                .padding(.top, 8)
                .padding(.bottom, 12)

            mapDoor

            // No pin count here: the stamps are counted two rows down, from the
            // waypoints that were actually earned.

            SectionRule(top: Space.s4)

            // A trip with no waypoints yet has nothing to count and no grid to
            // draw, so the tally and the empty band both go — "00 / 0" over a
            // gap says less than one sentence does.
            if store.orderedStamps.isEmpty {
                Mono("Stamps", size: 10)
                    .padding(.bottom, 6)
                Aside(text: "Waypoints are made on the stop they belong to, in the itinerary. Arriving at one earns its stamp.",
                      size: 12.5)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Mono("Stamps earned", size: 10)
                    Spacer()
                    Text("\(String(format: "%02d", store.earnedStamps.count)) / \(store.orderedStamps.count)")
                        .font(Typeface.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.a700)
                }
                .padding(.bottom, 12)

                LazyVGrid(columns: columns, spacing: Space.s2) {
                    ForEach(store.orderedStamps) { stamp in
                        StampBadge(stamp: stamp, isLatest: stamp.id == store.earnedStamps.last?.id)
                    }
                }
            }

            SectionRule(top: Space.s3, bottom: Space.s2)

            if let next = store.nextStamp, !isReadOnly {
                Panel(border: Palette.accent) {
                    Mono("Next stop", size: 9.5, color: Palette.a700)
                    Text(next.city)
                        .font(Typeface.heading(19, .semibold))
                        .foregroundStyle(Palette.text)
                        .padding(.top, 5)
                    if let distance = distance(to: next) {
                        // Inside the arrival radius the line says so, in the
                        // accent: the nudge Today shows, said where the button
                        // already is. Still only words — the tap is the same.
                        let close = isClose(to: next)
                        Mono(close ? "you look close · \(distance)" : distance,
                             size: 10, trackingRatio: 0.1, color: close ? Palette.a700 : Palette.n700)
                            .padding(.top, 3)
                    }
                    Aside(text: arrivalPromise(at: next), size: 12.5)
                        .padding(.top, 2)

                    OutlineButton(title: "I'm standing in it", minHeight: 46, size: 15) {
                        // Asked here rather than on the tap that earns it, so
                        // the fix has the length of the confirmation to arrive.
                        // A waypoint somebody typed carries no coordinate, and
                        // standing in it is the one moment the phone can supply
                        // one — `arrive(at:)` had the mechanism and, until this
                        // line, no source: `current` is nil unless Separated
                        // happens to be running.
                        store.location.requestOnce()
                        arriving = next
                    }
                    .padding(.top, Space.s3)
                }
                .padding(.bottom, Space.s3)
            }

            momentsSection
        }
        .confirmationDialog("Drop a pin in \(arriving?.city ?? "")?",
                            isPresented: Binding(get: { arriving != nil },
                                                 set: { if !$0 { arriving = nil } }),
                            titleVisibility: .visible) {
            Button("Yes, we're here") { arrive() }
            Button("Not yet", role: .cancel) { arriving = nil }
        } message: {
            Text("A stamp can't be undone, and anything sealed to this place opens for good.")
        }
        .fullScreenCover(isPresented: $showingStamp, onDismiss: {
            composingAt = keepingAt
            keepingAt = nil
        }) {
            if let earned {
                StampEarnedView(stamp: earned, unlockedLetters: unlocked,
                                onReadLetter: { readingLetter = $0 },
                                onKeepMoment: canMark ? { keepingAt = $0 } : nil)
            }
        }
        .sheet(item: $composingAt) { stamp in
            MomentComposerView(arrivedAt: stamp)
        }
        .sheet(item: $readingLetter) { letter in
            LetterReaderView(letter: letter)
        }
        .sheet(isPresented: $composingMoment) {
            MomentComposerView()
        }
        .sheet(item: $editingMoment) { moment in
            MomentComposerView(editing: moment) { deletedMoment = $0 }
        }
        .navigationDestination(item: $going) { destination in
            switch destination {
            case .map: TrailMapView()
            case .allMoments: MomentsView()
            }
        }
        .momentUndo($deletedMoment)
        .spotKept($keptSpot)
        // Never a prompt: the trail is opened on any afternoon, and the ask
        // belongs to the act that needs a position. Only a phone that already
        // said yes is asked for a fix.
        .task { if canMark { store.location.requestOnceIfAllowed() } }
        // Today's nudge lands here as the dialog this screen already has —
        // re-checked against `nextStamp`, because a sync round can have moved
        // the order between the tap on Today and this screen appearing.
        .onAppear(perform: takeArrivalRequest)
        .onChange(of: arrivalRequest.asked?.id) { takeArrivalRequest() }
    }

    private func takeArrivalRequest() {
        guard let asked = arrivalRequest.asked else { return }
        arrivalRequest.answered()
        guard canMark, let next = store.nextStamp, next.id == asked.id, !next.earned else { return }
        store.location.requestOnce()
        arriving = next
    }

    /// One tap, no sheet: the time and wherever the phone last knew it was.
    /// No waiting here — the composer's version waits for a fix; this one is
    /// for the moment there is no time to wait, and says "no position" if so.
    private func keepSpot() {
        let fix = here?.coordinate
        keptSpot = store.addMoment(note: "", latitude: fix?.latitude ?? 0,
                                   longitude: fix?.longitude ?? 0)
    }

    private func delete(_ moment: Moment) {
        store.deleteMoment(moment.id)
        deletedMoment = moment
    }

    private func isClose(to next: Stamp) -> Bool {
        guard let here else { return false }
        return store.nearNextStop(latitude: here.coordinate.latitude,
                                  longitude: here.coordinate.longitude)?.id == next.id
    }

    /// "180 km from here", or nothing: no fix, a stale one, or a waypoint
    /// nobody gave a position to — every typed one — all draw no line rather
    /// than "— km".
    private func distance(to next: Stamp) -> String? {
        guard let here,
              let km = store.kilometresToNextStop(fromLatitude: here.coordinate.latitude,
                                                  longitude: here.coordinate.longitude)
        else { return nil }
        return km < 1 ? "under a kilometre from here"
            : "\(Formatting.decimal(Double(km), places: 0)) km from here"
    }

    /// Everything the itinerary never planned for.
    ///
    /// Below the stamps rather than above them, because the stamps are what the
    /// trip is shaped like and these are what happened in between. The observer
    /// sees none of it: their phone holds no moments, and a heading over an
    /// empty list would be a reference to something that isn't theirs.
    @ViewBuilder
    private var momentsSection: some View {
        if !isReadOnly {
            SectionRule(top: Space.s4)

            HStack(alignment: .firstTextBaseline) {
                Mono("Moments", size: 10)
                Spacer()
                if canMark, !store.unfinishedMoments.isEmpty {
                    Mono("\(store.unfinishedMoments.count) to finish", size: 10, color: Palette.a700)
                        .padding(.trailing, Space.s2)
                }
                if !store.moments.isEmpty {
                    Text("\(String(format: "%02d", store.moments.count))")
                        .font(Typeface.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.a700)
                }
            }
            .padding(.bottom, 12)

            if store.orderedMoments.isEmpty {
                Aside(text: "Anything worth keeping that isn't a stamp — a meal, a wrong turn, somebody you met. It stays on this phone and prints in your book, beside the days it happened.",
                      size: 12.5)
                    .padding(.bottom, Space.s3)

                // The large target stays where there is nothing yet, which is
                // where a first-time reader is looking. Once there is a list,
                // the verb at the top of the screen is the way in.
                if canMark {
                    OutlineButton(title: "Mark this one", minHeight: 46, size: 15) {
                        composingMoment = true
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(store.orderedMoments.prefix(Self.momentsShown)) { moment in
                        Button {
                            editingMoment = moment
                        } label: {
                            MomentRow(moment: moment)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMark)
                        .modifier(MomentRowMenu(canEdit: canMark,
                                                onEdit: { editingMoment = moment },
                                                onDelete: { delete(moment) }))
                    }
                }

                if canMark {
                    Aside(text: "Tap one to open it; hold it to edit or delete.", size: 11.5)
                        .padding(.top, Space.s1)
                }

                if store.orderedMoments.count > Self.momentsShown {
                    Button {
                        going = .allMoments
                    } label: {
                        HStack {
                            Mono("All \(store.orderedMoments.count)", size: 10, trackingRatio: 0.1)
                            Spacer()
                            Mono("\(Self.momentsShown) shown · see them all", size: 10,
                                 trackingRatio: 0.1, color: Palette.a700)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens every moment")
                }
            }
        }
    }

    /// The map, or, when nothing on it could be placed, a frame saying what
    /// fills it.
    ///
    /// Nothing located used to mean a map of Bangkok, the sample trip's first
    /// city, on every trip. Now the plan frames it, and with no stop the city
    /// list knows either, there is no map to open: a door onto an empty sea
    /// is the "00 / 0 over a gap" the stamps below refused.
    @ViewBuilder
    private var mapDoor: some View {
        // Read once: `itineraryPositions` walks the city list.
        let planned = TrailMap.planned(in: store)
        if planned.isEmpty, here == nil,
           !store.orderedStamps.contains(where: \.hasLocation),
           !store.orderedMoments.contains(where: \.hasLocation) {
            Aside(text: "The map starts with the first place it can find. Add a stop in the itinerary.",
                  size: 12.5)
                .multilineTextAlignment(.center)
                .padding(Space.s6)
                .frame(maxWidth: .infinity, minHeight: 236)
                .overlay(Rectangle().strokeBorder(Palette.n500, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        } else {
                // A door, now. A tappable frame is pixel-identical to a dead one,
                // so it says so in its corner — clear of the Maps logo and the
                // legal link, which sit bottom-leading.
                Button { going = .map } label: {
                    TrailMap(stamps: store.orderedStamps, moments: store.orderedMoments,
                             here: here?.coordinate, planned: planned)
                        .frame(height: 236)
                        .overlay(alignment: .topTrailing) {
                            Mono("open the map", size: 9.5, trackingRatio: 0.1, color: Palette.a700)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Palette.bg.opacity(0.92))
                                .padding(6)
                        }
                        .padding(6)
                        .background(Palette.surface)
                        .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the whole trail, to explore")
        }
    }

    /// What arriving opens, asked of the letters themselves. This used to read
    /// `unlocksLetter`, which only the packed trip ever set, so on a real trip
    /// it said "nothing else" over a stop with three letters sealed to it.
    /// The count never includes a withheld condition, which the store sees to.
    private func arrivalPromise(at stamp: Stamp) -> String {
        let count = store.lettersVisible ? store.lettersOpening(onArrivalAt: stamp).count : 0
        switch count {
        // "Nothing else" is a promise the phone can't make while a letter's
        // condition is withheld from it. The letter box already says one is.
        case 0: return store.hiddenLetterCount > 0 ? "A stamp, as far as you can tell." : "A stamp, and nothing else."
        case 1: return "Arriving here opens a letter."
        default:
            return "Arriving here opens \(Formatting.spelledCount(count, "letter").lowercased())."
        }
    }

    /// The waypoint the dialog named, not whichever one is next by the time the
    /// tap lands.
    private func arrive() {
        guard let target = arriving else { return }
        arriving = nil
        let letters = store.arrive(at: target)
        earned = store.stamps.first { $0.id == target.id }
        unlocked = store.lettersVisible ? letters : []
        showingStamp = true
    }
}

/// A mark on the full-screen map that somebody tapped.
enum TrailMark: Hashable {
    case stamp(UUID)
    case moment(UUID)
}

/// Today asking the trail to put its arrival question: "Looks like you're in
/// Huế — drop the pin?" becomes the trail's own confirmation, not a second
/// way to earn a stamp. `MainTabs` owns the value and switches the tab.
struct ArrivalRequest {
    var asked: Stamp?
    var ask: (Stamp) -> Void = { _ in }
    var answered: () -> Void = {}
}

private struct ArrivalRequestKey: EnvironmentKey {
    static let defaultValue = ArrivalRequest()
}

extension EnvironmentValues {
    var arrivalRequest: ArrivalRequest {
        get { self[ArrivalRequestKey.self] }
        set { self[ArrivalRequestKey.self] = newValue }
    }
}

/// Where the trail pushes to.
enum TrailDestination: Hashable {
    case map, allMoments
}

/// A round seal — solid once earned, dashed while it's still ahead of them.
struct StampBadge: View {
    let stamp: Stamp
    var isLatest: Bool = false

    private var colour: Color {
        guard stamp.earned else { return Palette.n500 }
        return isLatest ? Palette.a800 : Palette.a700
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(Circle().fill(isLatest ? Palette.a100 : .clear))
            .overlay(
                Circle().strokeBorder(
                    stamp.earned ? Palette.accent : Palette.n400,
                    style: StrokeStyle(lineWidth: 1, dash: stamp.earned ? [] : [3, 3])
                )
            )
            .overlay {
                VStack(spacing: 1) {
                    Text(stamp.code)
                        .font(Typeface.heading(15, .semibold).capped(at: 1.2))
                        .foregroundStyle(colour)
                    if stamp.earned, let earnedOn = stamp.earnedOn {
                        Text(earnedOn.stampDate)
                            .font(Typeface.mono(7.5).capped(at: 1.2))
                            .tracking(0.4)
                            .foregroundStyle(colour)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Keep the type off the ring.
                .padding(.horizontal, 6)
            }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stamp.earned
                            ? "\(stamp.city), stamped \(stamp.earnedOn?.dayMonth ?? "")"
                            : "\(stamp.city), not yet")
    }
}


/// A screen's mono label with "+ mark a moment" in the corner.
///
/// The `spentLabel` shape from Today: the corner verb every other screen uses,
/// stacked under the label above the accessibility threshold, where `Mono` is
/// uncapped and a verb beside a label on one line is "POLIC / E" waiting to
/// happen. The padding goes on the verb before its shape, because it is a 10pt
/// word a few points above a map.
struct MarkMomentLabel: View {
    let title: String
    var size: CGFloat
    var canMark: Bool
    /// Held rather than tapped: keep the spot now, write it up later.
    var onKeepSpot: (() -> Void)?
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, size: CGFloat, canMark: Bool,
         onKeepSpot: (() -> Void)? = nil, action: @escaping () -> Void) {
        self.title = title
        self.size = size
        self.canMark = canMark
        self.onKeepSpot = onKeepSpot
        self.action = action
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.s2))
        layout {
            Mono(title, size: size)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canMark {
                Button(action: action) {
                    Mono("+ mark a moment", size: size, trackingRatio: 0.1, color: Palette.a700)
                        .padding(.leading, typeSize.isAccessibilitySize ? 0 : Space.s4)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark a moment")
                .contextMenu {
                    Button("Mark a moment", action: action)
                    if let onKeepSpot {
                        Button("Just keep the spot", action: onKeepSpot)
                    }
                }
                .accessibilityAction(named: "Just keep the spot") { onKeepSpot?() }
            }
        }
    }
}

/// One moment, in the list under the stamps.
///
/// A thumbnail rather than the full photograph: this is a list, and the page it
/// prints on is where the picture is meant to be looked at.
struct MomentRow: View {
    let moment: Moment
    /// False under a heading that already names the place.
    var showsPlace: Bool = true

    /// Under a heading, the row says only what the heading doesn't. Before
    /// departure the heading already says "Before we left", and there is no
    /// day number worth printing, so the row carries the date.
    private var caption: String {
        guard !showsPlace else { return moment.caption }
        return moment.isBeforeDeparture ? moment.capturedAt.stampDate : "day \(moment.dayNumber)"
    }

    private var line: String {
        if moment.isUnfinished { return "Nothing written yet" }
        return moment.note.isEmpty ? "A photograph, and no words" : moment.note
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            // Square by construction now — `JournalPhoto` takes a side rather
            // than a height, so the stand-in and the photograph are the same
            // shape and this no longer has to square it off from outside.
            JournalPhoto(photoID: moment.photoID, side: 44, usesThumbnail: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(line)
                    .font(Typeface.heading(15))
                    .italic(moment.isUnfinished)
                    .foregroundStyle(moment.isUnfinished ? Palette.n600 : Palette.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Mono("\(caption)\(moment.hasLocation ? "" : " · no position")",
                     size: 9.5, trackingRatio: 0.08)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line), \(moment.caption)")
    }
}

/// The trail so far. MapKit needs tiles from the network; with none, it draws
/// grey and the route and pins still read — which is the same promise the rest
/// of the app makes.
struct TrailMap: View {
    let stamps: [Stamp]
    /// Drawn, but never part of the trail: no polyline, no framing, and a mark
    /// that cannot be mistaken for either kind of stamp.
    var moments: [Moment] = []
    /// This phone, when the screen has a fix it trusts. A fourth mark, and
    /// like a moment it never moves the framing — opened at home before
    /// departure, the trail would otherwise zoom out to include Utrecht.
    var here: CLLocationCoordinate2D?
    /// The full-screen map pans, zooms and takes taps. The one on the trail
    /// takes none: it is a door, and the whole frame is the handle.
    var interactive = false
    var selection: Binding<TrailMark?> = .constant(nil)
    /// Bumped by the full-screen map's "show all" to put the camera back.
    var recentre = 0
    /// A fixed frame, for the replay: the whole finished trail from the first
    /// day, so the route draws itself *across* the map. Left to follow the
    /// earned stamps, day 8 was a close-up of Bangkok with the rest of the
    /// trip nowhere on screen.
    var framing: [Stamp]? = nil
    /// Where the plan goes, for framing a trail no waypoint has a position
    /// on yet. Never drawn: a plan is not a place anybody has been, and
    /// marks for it would read as stamps still ahead.
    var planned: [CLLocationCoordinate2D] = []

    private var earned: [Stamp] { stamps.filter { $0.earned && $0.hasLocation } }
    private var ahead: [Stamp] { stamps.filter { !$0.earned && $0.hasLocation } }
    private var located: [Moment] { moments.filter(\.hasLocation) }

    private var route: [CLLocationCoordinate2D] {
        earned.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The camera, held rather than handed over once.
    ///
    /// This was `Map(initialPosition:)`, which is read at first layout and
    /// never again — and the map takes no gestures, so nothing else could move
    /// it either. Dropping a pin in Huế while the frame was still around
    /// Bangkok left the new mark off the edge for the rest of the visit to the
    /// tab, on the one screen whose whole subject is that it grew.
    @State private var camera: MapCameraPosition?
    /// How much latitude the full-screen map is showing, as of the last
    /// gesture's end. Below `thumbnailSpan` a moment with a photograph draws
    /// the photograph; above it, dozens of them would tile over the route.
    @State private var span: Double = .infinity

    /// About a city. Named, so the threshold is one number.
    static let thumbnailSpan = 0.35

    private var showsThumbnails: Bool { interactive && span < Self.thumbnailSpan }

    var body: some View {
        Map(position: Binding(get: { camera ?? .region(region) },
                              set: { camera = $0 })) {
            if route.count > 1 {
                MapPolyline(coordinates: route)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(ahead) { stamp in
                Annotation(stamp.code, coordinate: CLLocationCoordinate2D(latitude: stamp.latitude, longitude: stamp.longitude)) {
                    mark(.stamp(stamp.id), label: "\(stamp.city), still ahead") {
                        Circle()
                            .strokeBorder(Palette.n500, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .frame(width: 9, height: 9)
                    }
                }
                .annotationTitles(.hidden)
            }
            // Under the stamps, and a different shape from both of them — a
            // filled circle is earned, a dashed one is still ahead, and a
            // moment is neither.
            ForEach(located) { moment in
                Annotation(moment.place ?? "", coordinate: CLLocationCoordinate2D(latitude: moment.latitude, longitude: moment.longitude)) {
                    mark(.moment(moment.id), label: "A moment, \(moment.caption)") {
                        // Still a diamond when it carries a photograph: the
                        // shape is what says "moment", on a map where filled
                        // means earned and dashed means ahead.
                        if showsThumbnails, moment.photoID != nil {
                            JournalPhoto(photoID: moment.photoID, side: 22, usesThumbnail: true)
                                .overlay(Rectangle().strokeBorder(Palette.n600, lineWidth: 1))
                                .rotationEffect(.degrees(45))
                        } else {
                            Rectangle()
                                .strokeBorder(Palette.n600, lineWidth: 1)
                                .frame(width: 6, height: 6)
                                .rotationEffect(.degrees(45))
                        }
                    }
                }
                .annotationTitles(.hidden)
            }
            ForEach(earned) { stamp in
                Annotation(stamp.code, coordinate: CLLocationCoordinate2D(latitude: stamp.latitude, longitude: stamp.longitude)) {
                    mark(.stamp(stamp.id), label: "\(stamp.city), stamped") {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 1.5))
                    }
                }
                .annotationTitles(.hidden)
            }
            // Solid ink with a pale halo: not accent (earned), not dashed
            // (ahead), not a diamond (a moment). Last, so it sits on top.
            if let here {
                Annotation("You", coordinate: here) {
                    Circle()
                        .fill(Palette.n800)
                        .frame(width: 9, height: 9)
                        .background(Circle().fill(Palette.n800.opacity(0.15)).frame(width: 22, height: 22))
                        .accessibilityLabel("You are here")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            if interactive {
                MapCompass()
                MapScaleView()
            }
        }
        .mapControlVisibility(interactive ? .automatic : .hidden)
        .allowsHitTesting(interactive)
        .onMapCameraChange(frequency: .onEnd) { context in
            guard interactive else { return }
            span = context.region.span.latitudeDelta
        }
        .onChange(of: recentre) {
            withGentleAnimation(.easeInOut(duration: 0.45)) { camera = .region(region) }
        }
        // A stamp earned, or one gaining a position, changes what "the trail so
        // far" is. Animated, so the reframe reads as the trail growing rather
        // than as the screen jumping.
        .onChange(of: earned.count) {
            withGentleAnimation(.easeInOut(duration: 0.45)) { camera = .region(region) }
        }
        .accessibilityLabel(located.isEmpty
                            ? "Map of the trail so far, \(Formatting.spelledCount(earned.count, "place", spellingUpTo: 0)) visited"
                            : "Map of the trail so far, \(Formatting.spelledCount(earned.count, "place", spellingUpTo: 0)) visited and \(Formatting.spelledCount(located.count, "moment", spellingUpTo: 0))")
    }

    /// A mark, and on the full-screen map a button that selects it. The hit
    /// area is padded well past the few points the mark draws, because a 6pt
    /// diamond is not a target anybody can hit.
    @ViewBuilder
    private func mark<Mark: View>(_ id: TrailMark, label: String,
                                  @ViewBuilder _ drawn: () -> Mark) -> some View {
        let isSelected = selection.wrappedValue == id
        let drawnMark = drawn()
            .scaleEffect(isSelected ? 1.6 : 1)
            .frame(width: interactive ? 36 : nil, height: interactive ? 36 : nil)
            .contentShape(Rectangle())
        if interactive {
            Button { selection.wrappedValue = isSelected ? nil : id } label: { drawnMark }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            drawnMark
        }
    }

    /// Frame where they have actually been, plus wherever they're going next.
    /// Fitting the whole trip would put six weeks of empty ocean on a screen
    /// titled "the trail so far".
    private var region: MKCoordinateRegion {
        if let framing, framing.contains(where: \.hasLocation) {
            return Self.region(fitting: framing.filter(\.hasLocation).map(\.coordinate))
        }
        var located = earned
        if let next = ahead.first { located.append(next) }
        if located.count < 2 { located = stamps.filter(\.hasLocation) }
        // Nothing on the trail knows where it is: frame where the plan goes.
        // This was a fixed box over Bangkok, the sample trip's first city,
        // on every trip. The trail draws a frame instead of a map when even
        // the plan can't be placed, so the world view below is a backstop.
        if located.isEmpty, !planned.isEmpty { return Self.region(fitting: planned) }
        return Self.region(fitting: located.map(\.coordinate))
    }

    /// The box around some points, with room at the edges and never tighter
    /// than about a region of a country.
    private static func region(fitting located: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !located.isEmpty else { return MKCoordinateRegion(.world) }
        let lats = located.map(\.latitude), lons = located.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, 1.2),
                                   longitudeDelta: max((maxLon - minLon) * 1.6, 1.2))
        )
    }
}

extension TrailMap {
    /// The plan's stops, only while no waypoint has a position of its own:
    /// once one does, the trail frames itself. Asked by both maps.
    static func planned(in store: TripStore) -> [CLLocationCoordinate2D] {
        guard !store.orderedStamps.contains(where: \.hasLocation) else { return [] }
        return store.itineraryPositions.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

private extension Stamp {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
