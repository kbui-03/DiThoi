import SwiftUI

/// Somebody has shared their trip, and this phone is being asked to join it.
///
/// The one screen in the app that changes which trip this phone *is*. Every
/// other flow makes a trip, corrects one, or shelves one; this takes on
/// somebody else's `tripID`, which is the single thing that lets two phones
/// ever see the same trip. Until it runs, two people who both walked onboarding
/// have two trips that will never meet, however well the merge works.
///
/// It is still a confirmation — joining is a decision, and "not now" has to be
/// possible — but it no longer prints what joining costs. **Two things happen
/// here that it does not say out loud:** a trip already open on this phone is
/// shelved, and letters addressed to whoever this phone used to be are deleted
/// and cannot be recovered. `joinTrip` does both regardless, and
/// `joiningDiscards(becoming:)` still counts them for anyone putting the
/// sentence back. Removed on request; noted here rather than lost, because the
/// second one is the only irreversible act in the app outside closing a trip.
struct JoinTripView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    let invitation: CloudKitSyncTransport.Invitation

    /// Which traveller this phone becomes.
    ///
    /// Prefilled from the invitation, which is where the answer normally comes
    /// from — the person doing the inviting knows which of the two they are, so
    /// the invitee is the other one, and it rides on the share. The picker is
    /// for the invitation that doesn't say: an older link, or one made before
    /// the field existed. Defaulting silently in that case is how both phones
    /// end up on the same slot, which is the failure this whole flow exists to
    /// remove rather than relocate.
    @State private var slot: Traveller
    @State private var joining = false

    init(invitation: CloudKitSyncTransport.Invitation) {
        self.invitation = invitation
        _slot = State(initialValue: invitation.slot ?? .two)
    }

    private var tripName: String {
        let title = invitation.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "their trip" : title
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "An invitation", trailing: joining ? nil : "not now") {
                store.declineInvitation()
                dismiss()
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 14)

            Screen {
                Display(text: "Join\n\(tripName)", size: 34)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                Aside(text: "Both phones keep their own copy. What you write here shows up there, and the other way round.",
                      size: 12.5)
                    .padding(.bottom, Space.s3)

                Rule()

                if invitation.slot == nil {
                    // Asked, not guessed. See `slot`.
                    Mono("Which of you is this phone?", size: 10.5)
                        .padding(.top, Space.s3)
                    Picker("", selection: $slot) {
                        ForEach(Traveller.allCases) { who in
                            Text(store.name(for: who)).tag(who)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                } else {
                    DetailRow(title: "You'll be \(store.name(for: slot))",
                              subtitle: "The other phone said so when it made the invitation.",
                              titleSize: 17, showsRule: false) { EmptyView() }
                }

                OutlineButton(title: joining ? "Joining…" : "Join the trip") {
                    guard !joining else { return }
                    joining = true
                    Task { @MainActor in
                        await store.acceptInvitation(as: slot)
                        joining = false
                        // Left open on failure, with `joinFailure` drawn below,
                        // so the answer is on the screen that asked rather than
                        // behind a sheet that has already gone.
                        if store.pendingInvitation == nil { dismiss() }
                    }
                }
                .padding(.top, Space.s4)
                .disabled(joining)

                if let failure = store.joinFailure {
                    Text(failure)
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(4)
                        .padding(.top, Space.s3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .background(Palette.bg)
        .interactiveDismissDisabled(joining)
    }
}
