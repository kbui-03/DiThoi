import SwiftUI

/// "Who's holding this phone", drawn once for the three places that ask it:
/// arrival, the new-trip flow and settings.
///
/// Full-width rows rather than three tiles across. All three answers have to
/// fit one screen at any text size, and tiles collide at the accessibility end
/// — and the choice changes the whole app, so it earns the room.
struct ParticipantPicker: View {
    @EnvironmentObject private var store: TripStore
    @Binding var selection: Participant
    /// What a slot is called in a form that hasn't been committed yet.
    ///
    /// Arrival collects the role and the names on one screen, so a name being
    /// typed above has to reach the row below it — otherwise the screen shows
    /// two answers to the same question. Return `nil` to fall back to the
    /// store, which is what the callers that only pick a role do.
    var draftName: (Participant) -> String? = { _ in nil }
    /// Fired after the binding changes, for callers that have to re-arm
    /// something — the evening prompt only exists on a traveller's phone.
    var onChange: (Participant) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule(color: Palette.text)

            ForEach(Participant.allCases) { option in
                Button {
                    guard selection != option else { return }
                    selection = option
                    onChange(option)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: option))
                                .font(Typeface.heading(18, .semibold))
                                .foregroundStyle(Palette.text)
                            Aside(text: selection == option ? "this phone · \(option.subtitle)" : option.subtitle,
                                  size: 11.5, color: Palette.n600)
                        }
                        Spacer(minLength: 8)
                        Tag(text: option.tag, active: selection == option)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)

                Rule()
            }
        }
    }

    /// A slot nobody has named yet reads as "Traveller one", not as a gap.
    private func label(for option: Participant) -> String {
        let draft = (draftName(option) ?? "").trimmingCharacters(in: .whitespaces)
        let name = draft.isEmpty ? store.name(of: option) : draft
        return name.isEmpty ? option.genericName : name
    }
}

/// Who the observer is writing to.
///
/// Not a preference: it is the address the letter box is keyed on, so a letter
/// sealed while this is wrong is posted where nobody will look for it.
struct RecipientPicker: View {
    @EnvironmentObject private var store: TripStore
    @Binding var recipient: Traveller
    var onChange: (Traveller) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule(color: Palette.text)

            ForEach(Traveller.allCases) { who in
                Button {
                    guard recipient != who else { return }
                    recipient = who
                    onChange(who)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name(for: who))
                                .font(Typeface.heading(18, .semibold))
                                .foregroundStyle(Palette.text)
                            Aside(text: recipient == who ? "your letters go to this phone" : "travelling",
                                  size: 11.5, color: Palette.n600)
                        }
                        Spacer(minLength: 8)
                        Tag(text: recipient == who ? "writing to" : "not this one",
                            active: recipient == who)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(recipient == who ? [.isButton, .isSelected] : .isButton)

                Rule()
            }
        }
    }
}

/// The names behind the picker.
///
/// You name yourself, and the other slot is a courtesy rather than a question
/// you have to answer: the other phone names itself, and because names merge
/// slot by slot on their own stamps, whichever answer is later wins without
/// touching the dates, the budget or anything else.
struct ParticipantNames: View {
    let participant: Participant
    @Binding var mine: String
    @Binding var theirs: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WrittenField(label: "You", text: $mine,
                         placeholder: participant.genericName,
                         note: mineNote)

            if let other = participant.traveller?.other {
                WrittenField(label: "The other one", text: $theirs,
                             placeholder: TripNames.fallback(other),
                             note: "Optional. Their phone can say so itself, and the later answer wins.")
                    .padding(.top, Space.s4)
            }
        }
    }

    private var mineNote: String {
        participant.isObserver
            ? "What the letters are signed with, and nothing else. It stays on this phone."
            : "Goes on the ledger, the book's spine plate and every line that mentions you."
    }
}
