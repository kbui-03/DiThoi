import SwiftUI

/// F3 · Writing a document down.
///
/// New and edit in one sheet, the way `ShowCardEditorView` and `AddExpenseView`
/// are — the same fields, and two copies of them would drift.
///
/// **Behind the lock, like the screen that reads these back.** `PapersView` is
/// deliberately *not* locked: it holds the meeting point and the show-this
/// cards, which exist to be handed to a driver or a hotel desk. But a passport
/// number is a passport number whether it is being read or typed, and reaching
/// this from an unlocked tab would have put the vault's contents on the wrong
/// side of the gate — including every value already in it, the moment somebody
/// tapped `edit`. The rule is one sentence with no flag in it: anything that
/// shows or accepts a document's field values wraps its own body in `Locked`.
///
/// `Locked` brings `privacyCovered()` with it, which this needs on its own
/// account: a sheet is presented *above* the view that spawned it, so the
/// cover over the screen underneath does not sit over this one. Same reason
/// `ScanViewer` has its own.
struct DocumentEditorView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.dismiss) private var dismiss

    var editing: TravelDocument?

    @State private var title = ""
    @State private var subtitle = ""
    @State private var badge = ""
    @State private var owner: Traveller?
    @State private var fields: [DocumentField] = []
    @State private var footnoteTitle = ""
    @State private var footnoteBody = ""
    @State private var showingFootnote = false
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool

    /// The words that go on the row. Chips rather than a free-for-all, because
    /// the badge is a label at 10pt and "Passport (Alex's, the new one)" is not
    /// one — but typed underneath, because the app has no business deciding this
    /// is the complete list of papers somebody travels with.
    /// `OTHER` is on the end and seeds nothing, on purpose. Four named papers
    /// and a free field read as "these four, or type your own"; the fifth chip
    /// is the answer for a paper that has no name worth typing — a vaccination
    /// card, a rental agreement — and there is nothing generic to ask about one,
    /// so `suggestedFields` has no entry and `seedFields` no-ops.
    private static let suggestedBadges = ["PASSPORT", "VISA", "INSURANCE", "TICKET", "OTHER"]

    /// The questions each kind of paper usually answers, offered once when a
    /// blank one is opened.
    ///
    /// Seeding only. They are ordinary rows afterwards — renameable, removable,
    /// and nothing downstream reads them by name. A fixed set that could not be
    /// edited would be `CountryFacts` for a table that has no authority behind
    /// it.
    private static let suggestedFields: [String: [String]] = [
        "PASSPORT": ["Number", "Expires", "Nationality"],
        "VISA": ["Reference", "Entry", "Valid until"],
        "INSURANCE": ["Policy", "Claim line"],
        "TICKET": ["Reference", "Date"]
    ]

    private var isComplete: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Locked(reason: "Passport and visa numbers. This is the same vault the scans are in.") {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            SheetHeader(title: editing == nil ? "New document" : "Edit document",
                        trailing: "Cancel") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WrittenField(label: "What is it", text: $title,
                                 placeholder: "Passport",
                                 note: "The name on the row.", size: 26)

                    WrittenField(label: "And a line under it", text: $subtitle,
                                 placeholder: "The photo page",
                                 size: 17,
                                 capitalisation: .sentences)
                        .padding(.top, Space.s4)

                    Mono("Label", size: 10)
                        .padding(.top, Space.s4)
                        .padding(.bottom, 8)
                    badgeChips
                    TextField("", text: $badge,
                              prompt: Text("PASSPORT")
                                .font(Typeface.mono(13).resolved(for: .large))
                                .foregroundStyle(Palette.n600))
                        .font(Typeface.mono(13))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(Palette.text)
                        .padding(.top, Space.s2)
                        .padding(.bottom, 8)
                    Rectangle().fill(Palette.accent).frame(height: 1)

                    ownerRow

                    SectionRule(top: Space.s6, bottom: Space.s3)

                    Mono("What's on it", size: 10).padding(.bottom, 4)
                    Aside(text: "Whatever you'd be asked for at a desk with the document in a hotel safe.",
                          size: 11.5)
                        .padding(.bottom, Space.s2)

                    fieldRows

                    Button {
                        withGentleAnimation(.easeInOut(duration: 0.2)) {
                            fields.append(DocumentField(label: "", value: ""))
                        }
                    } label: {
                        Mono("+ another line", size: 10, trackingRatio: 0.08, color: Palette.a700)
                            .frame(minHeight: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    footnoteSection

                    if editing != nil {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Mono("delete this document", size: 10, trackingRatio: 0.08,
                                 color: Palette.n700)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Space.s4)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            OutlineButton(title: editing == nil ? "Add it" : "Save it") { save() }
                .disabled(!isComplete)
                .opacity(isComplete ? 1 : 0.4)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .onAppear(perform: load)
        .confirmationDialog("Delete this document?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete it", role: .destructive) {
                if let editing { store.deleteDocument(editing.id) }
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(deletionMessage)
        }
    }

    // MARK: - Pieces

    private var badgeChips: some View {
        // Wrapping, not a row: four uppercase words at an accessibility size do
        // not fit across a phone, and a chip clipped to "INSURAN" is the
        // "SONGKRA / N" shape one screen over.
        FlowRow(spacing: Space.s2) {
            ForEach(Self.suggestedBadges, id: \.self) { suggestion in
                Chip(text: suggestion, selected: badge == suggestion) {
                    withGentleAnimation(.easeInOut(duration: 0.15)) {
                        badge = badge == suggestion ? "" : suggestion
                        seedFields(for: suggestion)
                    }
                }
            }
        }
    }

    private var ownerRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Whose", size: 10)
                .padding(.top, Space.s4)
                .padding(.bottom, 8)
            FlowRow(spacing: Space.s2) {
                Chip(text: "Both of you", selected: owner == nil) { owner = nil }
                ForEach(Traveller.allCases, id: \.self) { traveller in
                    Chip(text: store.name(for: traveller), selected: owner == traveller) {
                        owner = traveller
                    }
                }
            }
        }
    }

    private var fieldRows: some View {
        ForEach($fields) { $field in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    // No width cap. It was `maxWidth: 130`, an absolute number
                    // that does not grow with the type factor, so at an
                    // accessibility size "Blank pages" rendered as "Blank p…" —
                    // in an editable field, where the truncation hides what the
                    // person typed rather than just abbreviating a heading. The
                    // field takes what is left after the control beside it,
                    // which is the same answer at every size.
                    TextField("", text: $field.label,
                              prompt: Text("Number")
                                .font(Typeface.mono(11).resolved(for: .large))
                                .foregroundStyle(Palette.n600))
                        .font(Typeface.mono(11))
                        .foregroundStyle(Palette.n700)
                    Spacer(minLength: Space.s2)
                    Button {
                        withGentleAnimation(.easeInOut(duration: 0.2)) {
                            fields.removeAll { $0.id == field.id }
                        }
                    } label: {
                        Mono("remove", size: 9, trackingRatio: 0.08, color: Palette.n600)
                            .padding(.vertical, 8)
                            .padding(.leading, Space.s2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                TextField("", text: $field.value,
                          prompt: Text("NX4419 882")
                            .font(Typeface.mono(15).resolved(for: .large))
                            .foregroundStyle(Palette.n600))
                    .font(Typeface.mono(15))
                    .monospacedDigit()
                    .autocorrectionDisabled()
                    .foregroundStyle(Palette.text)
                    .padding(.bottom, 6)
                Rule()
            }
            .padding(.bottom, Space.s3)
        }
    }

    private var footnoteSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withGentleAnimation(.easeInOut(duration: 0.2)) { showingFootnote.toggle() }
            } label: {
                Mono(showingFootnote ? "− the note" : "+ add a note",
                     size: 10, trackingRatio: 0.08, color: Palette.a700)
                    .frame(minHeight: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingFootnote {
                WrittenField(label: "Heading", text: $footnoteTitle,
                             placeholder: "At the border", size: 17,
                             capitalisation: .sentences)
                    .padding(.bottom, Space.s3)
                WrittenField(label: "The thing itself", text: $footnoteBody,
                             placeholder: "Where the paper copy is", size: 17,
                             capitalisation: .sentences)
            }
        }
        .padding(.top, Space.s2)
    }

    private var deletionMessage: String {
        guard let editing else { return "It goes from this phone." }
        return Self.deletionMessage(for: editing, in: store)
    }

    /// Says what goes with it, computed rather than written down — the scans are
    /// on disk and the row is not the only thing being deleted.
    ///
    /// Static because the dialog is asked in two places now: here, and from the
    /// hold menu on the Papers row. Two copies of a sentence that counts
    /// something are two counts that can disagree.
    static func deletionMessage(for document: TravelDocument, in store: TripStore) -> String {
        let scans = store.scanCount(for: document.id)
        guard scans > 0 else { return "It goes from this phone." }
        return "It and its \(Formatting.spelledCount(scans, "scan", spellingUpTo: 0)) go from this phone."
    }

    // MARK: - Loading and saving

    private func load() {
        guard let editing else {
            fields = [DocumentField(label: "", value: "")]
            focused = true
            return
        }
        title = editing.title
        subtitle = editing.subtitle
        badge = editing.badge
        owner = editing.owner
        fields = editing.fields
        footnoteTitle = editing.footnoteTitle ?? ""
        footnoteBody = editing.footnoteBody ?? ""
        showingFootnote = editing.footnoteTitle != nil
    }

    /// Fills the labels a blank document hasn't been given yet.
    ///
    /// Only over rows nobody has typed in. Tapping "VISA" after filling a
    /// passport in would otherwise rename the line the number is sitting on,
    /// which is the `DayPlanEditorView` mistake — a helpful default landing on
    /// top of somebody's actual answer.
    private func seedFields(for suggestion: String) {
        guard let labels = Self.suggestedFields[suggestion] else { return }
        let written = fields.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard written.isEmpty else { return }
        fields = labels.map { DocumentField(label: $0, value: "") }
    }

    private func save() {
        func clean(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        // A row nobody filled in is not a field. The editor opens with one
        // waiting and offers another after every entry, so most documents end
        // with an empty one on the bottom.
        let kept = fields.compactMap { field -> DocumentField? in
            let label = field.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty || !value.isEmpty else { return nil }
            return DocumentField(id: field.id, label: label, value: value)
        }

        var document = editing ?? TravelDocument(title: "")
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        document.badge = badge.trimmingCharacters(in: .whitespacesAndNewlines)
        document.owner = owner
        document.fields = kept
        document.footnoteTitle = showingFootnote ? clean(footnoteTitle) : nil
        document.footnoteBody = showingFootnote ? clean(footnoteBody) : nil

        // No `syncNow()` here, and that is the point: papers do not travel.
        // Every other editor in the app ends with one, so its absence is worth
        // a sentence rather than a reader assuming it was forgotten.
        if editing == nil {
            store.addDocument(document)
        } else {
            store.updateDocument(document)
        }
        dismiss()
    }
}
