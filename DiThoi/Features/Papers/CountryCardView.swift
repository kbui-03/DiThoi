import SwiftUI

/// F5 · the country card. What the app can say for certain about where they are
/// standing, in daylight.
///
/// Everything here comes out of `CountryFacts`, which holds only what is still
/// true in five years — so this screen has no opening hours, no taxi fares and
/// no consulate, and the reasons are written down where the data lives rather
/// than here. Nothing on it is computed from the trip except *which* country to
/// ask about.
///
/// The Separated screen shows the same numbers and the same two phrases on a
/// dark ground at 2am. This is the version you read before you need it.
struct CountryCardView: View {
    @EnvironmentObject private var store: TripStore

    /// Passed in rather than looked up here, because `PapersView` has to run
    /// the same lookup to decide whether to draw a row at all — and a row that
    /// opens an empty card is the failure this whole file exists to avoid.
    let facts: CountryFacts

    var body: some View {
        Screen(context: .syncState) {
            // Not "Nothing here changes", which said the same thing as the
            // line three rows down and read like a broken screen. This is the
            // fact worth leading with: every word on this card is on the
            // phone already.
            Mono("Works with no signal", size: 10.5)

            Display(text: facts.country, size: 34)
                .padding(.top, 8)
                .padding(.bottom, 2)

            Aside(text: "The things worth knowing that don't go out of date.", size: 12.5)
                .padding(.bottom, Space.s4)

            emergency

            if let phrases = facts.phrases {
                SectionRule(top: Space.s4, bottom: Space.s2)
                self.phrases(phrases)
            }

            if let power = facts.power {
                SectionRule(top: Space.s4, bottom: Space.s2)
                self.power(power)
            }

            SectionRule(top: Space.s4, bottom: Space.s3)

            Aside(text: closingLine, size: 12)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pieces

    private var emergency: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Emergency", size: 10)
                .padding(.bottom, Space.s2)

            CallTileRow(numbers: facts.emergency.map {
                CallNumber(label: $0.label, number: $0.number)
            })

            Aside(text: "Tap one to dial it.", size: 11.5)
                .padding(.top, Space.s2)
        }
    }

    private func phrases(_ phrases: CountryFacts.Phrases) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Two sentences\(facts.language.map { " in \($0)" } ?? "")", size: 10)
                .padding(.bottom, Space.s3)

            phrase(phrases.doctor, "I need a doctor")
            phrase(phrases.lostPassport, "I've lost my passport")

            // Said out loud for the same reason the show-this card editor says
            // it: the app cannot read these back, and two sentences somebody
            // else wrote are not a translator. Anything beyond this pair is a
            // conversation, and a conversation needs a person.
            Aside(text: "These two are written into the app and checked. It can't translate anything else — for that, find someone who speaks both.",
                  size: 11.5)
                .padding(.top, Space.s2)
        }
    }

    /// The script large and first, the English small beneath it. Somebody
    /// holding the phone out needs the top line to be the one that works.
    private func phrase(_ script: String, _ english: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(script)
                .font(Typeface.heading(22, .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Mono(english, size: 9.5, trackingRatio: 0.1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Space.s3)
    }

    private func power(_ power: CountryFacts.Power) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Power", size: 10)
                .padding(.bottom, Space.s2)

            Panel {
                Text(power.socketLine)
                    .font(Typeface.heading(19, .semibold))
                    .foregroundStyle(Palette.text)
                Text(power.mains)
                    .font(Typeface.mono(12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.n700)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Not "your plug won't fit": the app never asks where anybody is
            // from — no nationality on a trip, no home country on a leg — so
            // that sentence would be a guess.
            Aside(text: "Which of these your charger has is worth checking before the flight, not after.",
                  size: 11.5)
                .padding(.top, Space.s2)
        }
    }

    /// Says which leg this is about, so a card read on the wrong day is
    /// obviously the wrong card. `currentCountry` is derived from the itinerary
    /// segment covering today, and it moves when they do.
    private var closingLine: String {
        "This is where the itinerary has you today. It changes with the leg, not with the phone."
    }
}
