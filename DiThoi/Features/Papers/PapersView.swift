import SwiftUI

/// F1 · The vault. Works with no signal, and never leaves the phone.
struct PapersView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @Binding var showingSeparated: Bool
    /// Two destinations, not one. Showing a card is the urgent thing and gets
    /// the row; writing one is a calm thing and gets the header's `edit`.
    @State private var showingCards = false
    @State private var managingCards = false
    @State private var writingFirstCard = false
    @State private var addingDocument = false
    /// The hold menu's two destinations. No undo behind the delete: a document
    /// is really removed and its scans go with it, so the confirmation is the
    /// only thing in front of it — the opposite arrangement to the ledger and
    /// the show-this cards, both of which are tombstoned and offer a banner.
    @State private var editingDocument: TravelDocument?
    @State private var deletingDocument: TravelDocument?

    /// The flag is the courtesy and `isLive` is the state: closing a trip empties
    /// the papers and leaves the app where it was, so an edit offered on an
    /// emptied document is a control over nothing.
    private var canEditDocuments: Bool { !isReadOnly && store.isLive }

    /// "The gate by the bridge. Agreed at 19:40." — with each half dropped when
    /// there is nothing to say, and nil when there is nothing at all.
    ///
    /// Both halves used to be unconditional, which is how a blank trip printed
    /// ". Agreed at 00:53.": the leading full stop belonged to an empty
    /// `detail`, and the time was `.distantPast` put through a formatter, which
    /// happily renders a date nobody chose as though somebody had.
    private var agreedLine: String? {
        let detail = store.meeting.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = detail.isEmpty
            ? nil
            : "\(detail.prefix(1).uppercased() + detail.dropFirst())."
        // `.distantPast` is the blank trip's seed, not a time of day.
        let agreed = store.meeting.setAt > .distantPast
            ? "Agreed at \(store.meeting.setAt.text("HH:mm"))."
            : nil
        let parts = [sentence, agreed].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            Screen(context: .syncState) {
                Mono("Works with no signal", size: 10.5)

                Display(text: "Papers", size: 38)
                    .padding(.top, 8)
                    .padding(.bottom, Space.s3)

                Panel(border: Palette.accent) {
                    Mono("If you're separated today", size: 9.5, color: Palette.a700)

                    // Nothing here is drawn about a point nobody has agreed.
                    //
                    // This card used to draw all of it unconditionally, so a
                    // blank trip got an empty headline and ". Agreed at 00:53."
                    // — a bare full stop where the place should be, and
                    // `.distantPast` rendered as a time somebody chose. Both
                    // halves of the same mistake: copy built from a value that
                    // exists without being an answer.
                    if store.meeting.isSet {
                        Text(store.meeting.place)
                            .font(Typeface.heading(20, .semibold))
                            .foregroundStyle(Palette.text)
                            .padding(.top, 5)
                        // No phone number here: the app is never given one, and
                        // a number it was never told is not a fact it can state.
                        // The half a driver can read, when there is one. Drawn
                        // here as well as on Separated because this is the tab
                        // that gets handed to a stranger, and it is the only
                        // line on it they have a chance of acting on. Nothing is
                        // drawn when the place has no script — the app can't
                        // write one.
                        if !store.meeting.localScript.isEmpty {
                            Text(store.meeting.localScript)
                                .font(Typeface.heading(16, .semibold))
                                .foregroundStyle(Palette.a700)
                                .padding(.top, 5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let line = agreedLine {
                            Text(line)
                                .font(Typeface.body(12))
                                .foregroundStyle(Palette.n700)
                                .lineSpacing(4)
                                .padding(.top, 5)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        OutlineButton(title: "We got separated", minHeight: 46, size: 15) {
                            store.startSeparated()
                            showingSeparated = true
                        }
                        .padding(.top, Space.s3)
                    } else {
                        Text("Nothing agreed yet")
                            .font(Typeface.heading(20, .semibold))
                            .foregroundStyle(Palette.text)
                            .padding(.top, 5)
                        Aside(text: "Pick somewhere you can both walk to on Today, and it shows up here for whoever is holding the phone.",
                              size: 12)
                            .padding(.top, 5)
                        // Offered for the emergency numbers and the two
                        // phrases, which are no less use on a night nobody
                        // agreed anywhere. Where the app knows neither a place
                        // nor the country, the screen would be a headline over
                        // nothing, so it isn't offered.
                        if store.canStartSeparated {
                            OutlineButton(title: "We got separated", minHeight: 46, size: 15) {
                                store.startSeparated()
                                showingSeparated = true
                            }
                            .padding(.top, Space.s3)
                        }
                    }
                }

                SectionRule(top: Space.s4)

                // Per-trip, so a new trip opens with no papers rather than
                // somebody else's. `add` sits in the header the way the
                // show-this section's `edit` does, rather than as a row —
                // the rows here are the thing you reach for in a hurry.
                HStack(alignment: .firstTextBaseline) {
                    Mono("Documents", size: 10)
                    Spacer(minLength: Space.s2)
                    // `isLive` as well as the flag: closing a trip empties the
                    // papers and leaves the app exactly where it was, so an
                    // `add` here would offer to start filling in a vault that
                    // had just been deliberately emptied.
                    if canEditDocuments {
                        Button { addingDocument = true } label: {
                            // Padded before `contentShape`, like the control
                            // below it: a 10pt word a few points above a 44pt
                            // row that opens a passport is a near-miss waiting
                            // to happen.
                            Mono("add", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                                .padding(.vertical, 10)
                                .padding(.leading, Space.s3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 2)

                if store.documents.isEmpty {
                    Aside(text: "Nothing packed yet. Passports, visas, insurance — whatever you'd want to hand over at a desk.",
                          size: 12.5)
                        .padding(.vertical, Space.s2)
                } else {
                    ForEach(Array(store.documents.enumerated()), id: \.element.id) { index, document in
                        NavigationLink {
                            DocumentDetailView(documentID: document.id, index: index)
                        } label: {
                            DetailRow(title: document.title, subtitle: document.subtitle,
                                      showsRule: index < store.documents.count - 1) {
                                scanBadge(for: document)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // The ledger's arrangement: tap does the everyday thing
                        // — here, opening it — and hold offers the two that
                        // change or remove it. Both used to be a tap, a scroll
                        // and a small grey word deeper in.
                        .contextMenu {
                            if canEditDocuments {
                                Button("Edit") { editingDocument = document }
                                Button("Delete", role: .destructive) { deletingDocument = document }
                            }
                        }
                    }

                    if canEditDocuments {
                        Aside(text: "Tap a document to open it; hold it to edit or delete.",
                              size: 11.5)
                            .padding(.top, Space.s2)
                    }
                }

                SectionRule()

                // A section like Documents above it, rather than one row doing
                // two jobs. The row is the verb you need in a hurry; writing a
                // card sits in the header, the way `ItineraryView` puts `edit`
                // beside the dates. This screen briefly had it the other way
                // round — the row opened the list and the cards themselves were
                // a scroll and a small grey button further in, on a tab that
                // has no lock in front of it, because somebody may be reaching
                // for it in a hurry.
                HStack(alignment: .firstTextBaseline) {
                    Mono("Show-this cards", size: 10)
                    Spacer(minLength: Space.s2)
                    // Nothing to manage until something is written, and the row
                    // below already offers that in one tap — two controls
                    // saying "write one" would just be two routes to the same
                    // sheet, one of them slower.
                    if !isReadOnly, !store.orderedShowCards.isEmpty {
                        Button { managingCards = true } label: {
                            // Padded before `contentShape`, so the target is
                            // bigger than the 10pt word. Elsewhere this control
                            // sits under a masthead with nothing tappable near
                            // it; here it is a few points above a row that
                            // opens a full-screen cover at maximum brightness,
                            // and a near-miss should not do that.
                            Mono("edit", size: 10, trackingRatio: 0.08, color: Palette.a700)
                                .padding(.vertical, 8)
                                .padding(.leading, 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 2)

                if store.orderedShowCards.isEmpty {
                    // No row onto an empty deck: the explanation belongs here,
                    // where somebody first meets the feature.
                    Aside(text: "Nothing written yet. A card is one sentence in \(languageName), and the same sentence in English underneath so you know what you're holding out — where you're staying, what you can't eat, who to call.",
                          size: 12.5)
                        .padding(.vertical, Space.s2)

                    if !isReadOnly {
                        Button {
                            writingFirstCard = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Write your first card")
                                        .font(Typeface.heading(17, .semibold))
                                        .foregroundStyle(Palette.text)
                                    // One line. The longer version wrapped and
                                    // left the trailing label floating against
                                    // nothing.
                                    Aside(text: "Before you need one", size: 11.5, color: Palette.n600)
                                }
                                Spacer(minLength: Space.s2)
                                Mono("write", size: 10, trackingRatio: 0.08, color: Palette.a700)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        showingCards = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hand the phone over")
                                    .font(Typeface.heading(17, .semibold))
                                    .foregroundStyle(Palette.text)
                                Aside(text: cardsSubtitle, size: 11.5, color: Palette.n600)
                            }
                            Spacer(minLength: Space.s2)
                            Mono("show", size: 10, trackingRatio: 0.08, color: Palette.a700)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Only when the app has something to put on it. `hasCard` asks
                // whether there is more here than the two phone numbers the
                // Separated screen already shows — so a country it knows only
                // by its emergency line draws no row rather than a row onto an
                // empty screen, which is rule 1 one level up.
                if let facts = CountryFacts.lookup(store.currentCountry), facts.hasCard {
                    Rule()

                    NavigationLink {
                        CountryCardView(facts: facts)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(facts.country)
                                    .font(Typeface.heading(17, .semibold))
                                    .foregroundStyle(Palette.text)
                                Aside(text: countrySubtitle(facts), size: 11.5, color: Palette.n600)
                            }
                            Spacer()
                            Mono("country", size: 10, trackingRatio: 0.08, color: Palette.a700)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Rule()

                // One door for everything that is about the trip rather than
                // carried for it. Papers is the tab handed to a stranger and
                // reached for in a hurry; setup, sharing and the shelf were
                // three rows of settings between the cards and the footer.
                NavigationLink {
                    TripHubView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trip")
                                .font(Typeface.heading(17, .semibold))
                                .foregroundStyle(Palette.text)
                            Aside(text: "Setup, sharing with \(store.otherName), the shelf",
                                  size: 11.5, color: Palette.n600)
                        }
                        Spacer()
                        Mono("trip", size: 10, trackingRatio: 0.08, color: Palette.a700)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                SectionRule()

                Aside(text: "Stored on the phone only. Never uploaded, never in anyone's cloud — including the one at home.", size: 12)
            }
            // The cards themselves, one tap from the tab, full brightness, no
            // list in between.
            .fullScreenCover(isPresented: $showingCards) {
                ShowThisView()
            }
            .sheet(isPresented: $managingCards) {
                ShowCardsView()
            }
            // Straight to the editor, not to a list with one button on it.
            .sheet(isPresented: $writingFirstCard) {
                ShowCardEditorView()
            }
            // The editor carries its own `Locked`, so this tab stays open while
            // the thing it presents does not. Papers is deliberately unlocked —
            // the meeting point and the show-this cards are for handing over —
            // and a passport number typed on an unlocked tab would put the
            // vault's contents on the wrong side of that.
            .sheet(isPresented: $addingDocument) {
                DocumentEditorView(editing: nil)
            }
            // Same editor, same lock. It carries its own `Locked`, which is what
            // lets an unlocked tab present it — the rule is that anything showing
            // or accepting a document's field values wraps its own body.
            .sheet(item: $editingDocument) { document in
                DocumentEditorView(editing: document)
            }
            // The editor's own dialog, word for word, asked of the same counter.
            // Nothing brings a document back: `deleteDocument` really removes and
            // takes the scans with it, which is why this one confirms where the
            // ledger's delete just goes.
            .confirmationDialog("Delete this document?",
                                isPresented: Binding(get: { deletingDocument != nil },
                                                     set: { if !$0 { deletingDocument = nil } }),
                                titleVisibility: .visible,
                                presenting: deletingDocument) { document in
                Button("Delete it", role: .destructive) {
                    store.deleteDocument(document.id)
                }
                Button("Keep it", role: .cancel) {}
            } message: { document in
                Text(DocumentEditorView.deletionMessage(for: document, in: store))
            }
        }
    }

    /// Only ever drawn when there is at least one, so it counts rather than
    /// describing the feature — the empty case has its own words above.
    private var cardsSubtitle: String {
        let count = store.orderedShowCards.count
        return "\(Formatting.spelledCount(count, "card", spellingUpTo: 0)), in the order you swipe them"
    }

    /// The language of wherever they are, or a name for not knowing.
    private var languageName: String { store.currentLanguage ?? "the local language" }

    /// Names what is actually on the card rather than describing it in general,
    /// so a country carrying only sockets doesn't promise phrases.
    private func countrySubtitle(_ facts: CountryFacts) -> String {
        var parts = ["Emergency numbers"]
        if facts.phrases != nil { parts.append("two sentences") }
        if facts.power != nil { parts.append("plugs") }
        return parts.joined(separator: " · ")
    }

    /// The badge counts the scans this phone actually holds, and falls back to
    /// whatever the document was labelled.
    ///
    /// The accent is derived from the count rather than stored beside it.
    /// `badgeIsAccent` was a second answer to a question the first line already
    /// computes, and once documents are typed by hand nobody is there to keep
    /// the two in step.
    private func scanBadge(for document: TravelDocument) -> some View {
        let pages = DocumentStore.shared.pageCount(for: document.id)
        return Mono(pages > 0 ? "\(Formatting.spelledCount(pages, "scan", spellingUpTo: 0))" : document.badge,
                    size: 10, trackingRatio: 0.08,
                    color: pages > 0 ? Palette.a700 : Palette.n600)
    }
}

/// The trip's settings, behind Papers' one "Trip" row.
///
/// The three rows Papers used to carry, moved as they were. Nothing here is
/// needed in a hurry, which is why it is a tap further in.
struct TripHubView: View {
    @EnvironmentObject private var store: TripStore

    var body: some View {
        Screen(context: .syncState) {
            Mono("\(store.displayName) · \(store.start.shortDayMonth) – \(store.end.shortDate)", size: 10.5)

            Display(text: "Trip", size: 38)
                .padding(.top, 8)
                .padding(.bottom, Space.s3)

            row(title: "Setup",
                subtitle: "Travellers, dates, currency, what prints at the end",
                action: "setup") { TripSetupView() }

            Rule()

            // The row has to name the invitation, because the screen behind
            // it leads with one. "What they can see / set on day one and never
            // asked about again" describes a privacy statement somebody reads
            // once, which is exactly what a person looking for "how do I get
            // them on this trip" would scroll straight past.
            //
            // Still gated: on a build that can't invite, the row describes what
            // the screen can actually do rather than promising a button that
            // isn't there.
            row(title: store.sync.canInvite ? "Invite \(store.otherName)"
                                            : "What \(store.otherName) can see",
                subtitle: store.sync.canInvite
                    ? "One trip on two phones, and what they can see of it"
                    : "Set on day one and never asked about again",
                action: store.sync.canInvite ? "invite" : "sharing") { SharingSettingsView() }

            Rule()

            row(title: "The shelf", subtitle: shelfSubtitle, action: "trips") { ShelfView() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shelfSubtitle: String {
        let past = store.library.shelf.count
        guard past > 0 else { return "This one is the only one so far" }
        return "\(past) closed · this one still open"
    }

    private func row<Destination: View>(title: String, subtitle: String, action: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(Palette.text)
                    Aside(text: subtitle, size: 11.5, color: Palette.n600)
                }
                Spacer()
                Mono(action, size: 10, trackingRatio: 0.08, color: Palette.a700)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// G2 · What the other traveller can see.
struct SharingSettingsView: View {
    @EnvironmentObject private var store: TripStore

    /// The invitation, once iCloud has handed one back. Held rather than made
    /// on the way into the share sheet, because making it is a round trip and a
    /// sheet that opens on an empty item is a sheet that has already failed.
    @State private var link: InviteLink?
    @State private var making = false
    @State private var inviteFailure: String?

    var body: some View {
        Screen(context: .syncState) {
            Mono("One trip, two phones", size: 10.5)

            // The headline is the body's. It said "Invite" on a build whose
            // first sentence is that nobody can be invited.
            Display(text: store.sync.canInvite ? "Invite\n\(store.otherName)"
                                               : "What \(store.otherName)\ncan see",
                    size: 36)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // About the link, so only where there is one.
            if store.sync.canInvite {
                Aside(text: "A link to this trip. Send it however you like — following it puts the trip on their phone, and the two keep each other up to date from then on.",
                      size: 12.5)
                    .padding(.bottom, Space.s3)
            }

            invite

            Mono("What they can see", size: 10.5)
                .padding(.top, Space.s6)
                .padding(.bottom, 10)

            Rule()

            // Derived, not stored. The written-down list was sample data and is
            // empty on every trip made through onboarding, so this screen spent
            // its life listing nothing — see `SharingLine`.
            ForEach(Array(store.whatTravels.enumerated()), id: \.element.id) { index, line in
                DetailRow(title: line.title, subtitle: line.detail, titleSize: 17,
                          showsRule: index < store.whatTravels.count - 1) {
                    Tag(text: line.state, active: line.isShared)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $link) { link in
            ShareSheet(items: [link.url])
        }
    }

    /// Getting the trip onto the other phone.
    ///
    /// This is the step everything else on this screen assumes has happened.
    /// Without it both phones mint their own `tripID` and sync quietly past
    /// each other — each one pushing, each one reporting success, neither
    /// carrying a word the other wrote. The rows below describe what the other
    /// traveller can see; this is what makes there *be* another traveller.
    ///
    /// Said plainly rather than disabled where it can't work. On a build with no
    /// CloudKit there is nobody to invite, and a button that explains itself
    /// only after being pressed is the shape of the passport screen's "Send
    /// to —", which said "Sent" and did nothing. The sentence replaces the
    /// control rather than sitting under a greyed-out one.
    @ViewBuilder
    private var invite: some View {
        if store.sync.canInvite {
            OutlineButton(title: making ? "Asking iCloud…"
                                        : "Send \(store.otherName) the link") {
                makeInvitation()
            }
            .disabled(making)

            if let inviteFailure {
                Text(inviteFailure)
                    .font(Typeface.body(12.5))
                    .foregroundStyle(Palette.text)
                    .lineSpacing(4)
                    .padding(.top, Space.s3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("This build keeps the trip on this phone, so there is nobody to invite yet. Everything below still works — it just has one phone to do it on.")
                .font(Typeface.body(12.5))
                .foregroundStyle(Palette.n700)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func makeInvitation() {
        guard !making else { return }
        making = true
        inviteFailure = nil
        Task { @MainActor in
            do {
                // `role.other` is the invitee by construction: whoever is
                // holding this phone is one of the two, so the person being
                // invited is the other one. It rides on the share so their
                // phone doesn't have to guess — both phones defaulting to
                // `.one` is the failure this carries the slot to prevent.
                let url = try await store.sync.invitation(to: store.tripID,
                                                          named: store.displayName,
                                                          inviting: store.role.other)
                link = InviteLink(url: url)
            } catch {
                inviteFailure = error.localizedDescription
            }
            making = false
        }
    }
}

/// So a link can drive `.sheet(item:)` without a retroactive `Identifiable` on
/// `URL` — which would be a conformance to a foreign type on behalf of the
/// whole module, for the sake of one sheet.
struct InviteLink: Identifiable {
    let id = UUID()
    let url: URL
}
