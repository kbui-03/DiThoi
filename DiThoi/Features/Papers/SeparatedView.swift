import SwiftUI

/// F4 · Separated. The 2am screen, dark so it survives a dying battery.
///
/// It reads this phone's position and works out how far it is from tonight's
/// meeting point. It shares nothing: `separatedSince` is on the phone-only half
/// of the store, and `LocationService.current` never enters a sync payload. The
/// copy stays inside that — no mutual beacon is described, because none
/// exists.
struct SeparatedView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // No signal chip here: the app never reads the radio, and this is
            // the screen where a decorative one would be worst.
            Spacer(minLength: 0).frame(height: 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("Separated · started \(startedAt)", size: 10, trackingRatio: 0.16, color: Palette.a300)

                    Display(text: headline, size: 40, color: Palette.n100)
                        .padding(.top, 10)
                        .padding(.bottom, Space.s3)

                    if store.meeting.isSet {
                        Panel(border: Palette.a400, padding: EdgeInsets(top: 16, leading: 17, bottom: 16, trailing: 17)) {
                            Text(store.meeting.place)
                                .font(Typeface.heading(22, .semibold))
                                .foregroundStyle(Palette.n100)
                            Aside(text: "\(store.meeting.detail)\(distanceSuffix)", size: 12.5, color: Palette.n300)
                                .padding(.top, 3)

                            // The divider and the caption belong to the script,
                            // so they go with it. Drawn unconditionally they
                            // produced a rule under nothing and the words "show
                            // this to a driver" over a blank — on the one screen
                            // where somebody really is holding the phone out.
                            if !store.meeting.localScript.isEmpty {
                                Rectangle().fill(Palette.darkDivider)
                                    .frame(height: 1)
                                    .padding(.vertical, Space.s3)

                                Text(store.meeting.localScript)
                                    .font(Typeface.heading(17, .semibold))
                                    .foregroundStyle(Palette.a300)
                                    .lineSpacing(4)
                                Mono("show this to a driver", size: 9.5, trackingRatio: 0.1, color: Palette.n400)
                                    .padding(.top, 5)
                            }
                        }
                    } else {
                        Panel(border: Palette.darkDivider, padding: EdgeInsets(top: 16, leading: 17, bottom: 16, trailing: 17)) {
                            Text("No meeting point")
                                .font(Typeface.heading(22, .semibold))
                                .foregroundStyle(Palette.n100)
                            // Nothing about what else is on this screen.
                            //
                            // The first version of this said "the distance below
                            // is still yours, and the emergency numbers are
                            // still here" — and on a blank trip there is no
                            // distance (location is off) and no numbers (no
                            // country). Writing replacement copy that makes its
                            // own uncomputed promises is the bug being fixed,
                            // one screen along. This says only what is true
                            // whatever else is or isn't here.
                            Aside(text: "Nobody agreed one for this trip, so there's nowhere for this screen to send you.",
                                  size: 12.5, color: Palette.n300)
                                .padding(.top, 3)
                        }
                    }

                    // Only about a meeting point. With none agreed there is
                    // nothing to be far from, and the card above already says
                    // so; a second panel saying "only you know" was the same
                    // sentence again over a screen that now also opens for the
                    // emergency numbers alone.
                    if let whereabouts {
                        Panel(border: Palette.darkDivider) {
                            Mono(whereabouts.label, size: 9.5, color: Palette.n400)
                            Text(whereabouts.value)
                                .font(Typeface.heading(19, .semibold))
                                .foregroundStyle(Palette.n100)
                                .padding(.top, 5)
                            Aside(text: whereabouts.note, size: 12, color: Palette.n300)
                                .padding(.top, 2)

                            if store.location.isDenied, store.meeting.hasLocation {
                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Mono("turn location on", size: 9.5, trackingRatio: 0.1, color: Palette.a300)
                                        .frame(minHeight: 40)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, Space.s3)
                    }

                    // Only for a country `CountryFacts` knows. Nothing at all
                    // is the right output for somewhere unknown: a missing
                    // number sends somebody to a hotel desk, a wrong one sends
                    // them nowhere.
                    if let facts = CountryFacts.lookup(store.currentCountry) {
                        Mono("Emergency · \(facts.country)", size: 9, trackingRatio: 0.12, color: Palette.n400)
                            .padding(.top, Space.s4)
                            .padding(.bottom, Space.s2)

                        CallTileRow(numbers: facts.emergency.map {
                            CallNumber(label: $0.label, number: $0.number)
                        },
                                    labelColor: Palette.n400,
                                    numberColor: Palette.n100,
                                    border: Palette.darkDivider)

                        // The two sentences, big enough to hold up. This is the
                        // screen they exist for: no signal, no shared language,
                        // and a stranger who has to understand in one look.
                        // `nil` where nobody has checked the script — see
                        // `CountryFacts.phrases`.
                        if let phrases = facts.phrases {
                            Mono("Show someone", size: 9, trackingRatio: 0.12, color: Palette.n400)
                                .padding(.top, Space.s4)
                                .padding(.bottom, Space.s2)

                            VStack(alignment: .leading, spacing: Space.s3) {
                                darkPhrase(phrases.doctor, "I need a doctor")
                                darkPhrase(phrases.lostPassport, "I've lost my passport")
                            }
                        }
                    }

                    // "Turning this on also texts home your city" was here.
                    // Nothing in the app sends a message, and `separatedSince`
                    // never enters a sync payload — this screen works out how
                    // far *this* phone is from the meeting point and tells
                    // nobody. Making it mutual is a real feature and a real
                    // channel; claiming it was neither.
                    // Only while it is true: without a pin nothing is followed.
                    if store.location.isTracking {
                        Aside(text: "Followed only while this screen is open.",
                              size: 12, color: Palette.n400)
                            .padding(.top, Space.s3)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            Button {
                store.endSeparated()
                dismiss()
            } label: {
                Text("We found each other")
                    .font(Typeface.heading(15, .semibold))
                    .foregroundStyle(Palette.a300)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.a400, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.n900.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            // On a relaunch into this screen it is already on, and tracking has
            // to be picked up again: `separatedSince` is saved, the location
            // manager isn't.
            if store.isSeparated { store.followMeetingPointIfPinned() } else { store.startSeparated() }
        }
        // The other phone can pin the point, or move it, mid-separation.
        .onChange(of: store.meeting) { store.followMeetingPointIfPinned() }
    }

    /// "Go to the / gate by the bridge", or something true when there is no
    /// gate and no bridge.
    ///
    /// The old version was `"Go to the\n" + detail.components(separatedBy: ",").first ?? "meeting point"`,
    /// and the fallback was unreachable: splitting `""` answers `[""]`, never
    /// nil, so a blank trip read "Go to the" over an empty line. Exactly the
    /// shape of `DayDetailView.cityName`'s `?? plan?.city`, which had the same
    /// bug for the same reason — a `??` behind a split can only fire if the
    /// split can actually produce nothing.
    private var headline: String {
        let first = store.meeting.detail
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !first.isEmpty { return "Go to the\n\(first)" }
        if store.meeting.isSet { return "Go to\n\(store.meeting.place)" }
        return "Stay where\nyou are"
    }

    /// One phrase on the dark ground: the local script first and large, the
    /// English under it small — the order somebody holding the phone out needs,
    /// rather than the order they can read.
    private func darkPhrase(_ script: String, _ english: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(script)
                .font(Typeface.heading(21, .semibold))
                .foregroundStyle(Palette.n100)
                .fixedSize(horizontal: false, vertical: true)
            Mono(english, size: 9.5, trackingRatio: 0.1, color: Palette.n400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// " · 700 m away" once the phone knows where it is, and nothing before.
    private var distanceSuffix: String {
        guard let distance = store.distanceToMeetingPoint else { return "" }
        return " · \(distance.walkingText) away"
    }

    /// What this phone can honestly say about the meeting point, or `nil`
    /// when there isn't one.
    private var whereabouts: (label: String, value: String, note: String)? {
        guard store.meeting.isSet else { return nil }
        // Nothing set a meeting point's position until the picker could pin
        // one, so this used to say "Finding you…" for ever: a search with
        // nothing to measure to, however well the phone knew where it was.
        guard store.meeting.hasLocation else {
            return ("No pin on the map",
                    "Use the written directions",
                    "Nobody pinned this spot, so the phone can't say how far.")
        }
        if store.location.isDenied {
            return ("Location is off",
                    "Use the written directions",
                    "Without location this screen still works — it just can't tell you how far.")
        }
        guard let distance = store.distanceToMeetingPoint else {
            return ("Finding you", "…",
                    "Only while this screen is open.")
        }
        return ("The meeting point",
                MeetingPoint.fromHere(distance, compass: store.bearingToMeetingPoint),
                "Worked out on this phone. Nothing leaves it.")
    }

    private var startedAt: String {
        (store.separatedSince ?? store.now).text("HH:mm")
    }

}

// `CallTile` lives in `Design/Components.swift`, with its colours as
// parameters: the country card draws the same tiles in daylight, and one tile
// on two grounds cannot regress on only one of them.
