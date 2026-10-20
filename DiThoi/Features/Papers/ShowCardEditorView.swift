import SwiftUI

/// The cards, as a list you can write, reorder and delete.
///
/// Both halves of a card are typed here. The app holds no translator: it names
/// the language of wherever they are and takes whatever is written.
///
/// Management only, reached from `edit` in the Papers section header. Papers
/// itself goes straight to `ShowThisView`, so handing the phone to somebody is
/// one tap and never a scroll through this list.
struct ShowCardsView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.dismiss) private var dismiss

    @State private var writing = false
    @State private var editing: ShowCard?
    /// Held for a few seconds after a delete so it can be taken back — the
    /// ledger's arrangement, and for the same reason: a card is a tombstone, so
    /// the undo is a real restore rather than a re-typing of what was written.
    @State private var undoable: ShowCard?
    @State private var undoTimer: Task<Void, Never>?

    private var cards: [ShowCard] { store.orderedShowCards }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Show-this cards", trailing: "Done") { dismiss() }

            List {
                if cards.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Display(text: "Nothing to\nshow yet", size: 30)
                            Aside(text: "A card is one sentence in \(languageName), and the same sentence in English underneath so you know what you're holding out. Where you're staying, what you can't eat, who to call.",
                                  size: 12.5)
                            Aside(text: "Write them before you need them — the moment you need one is not the moment to be typing.",
                                  size: 12.5)
                        }
                        .padding(.vertical, Space.s3)
                        .listRowBackground(Palette.bg)
                    }
                } else {
                    Section {
                        ForEach(cards) { card in
                            Button {
                                if !isReadOnly { editing = card }
                            } label: {
                                row(card)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Palette.bg)
                            // The ledger's arrangement, word for word: tap does
                            // the everyday thing, hold offers the two that
                            // change or remove it. Delete goes straight through
                            // — the banner underneath is the safety net, not a
                            // dialog.
                            .contextMenu {
                                if !isReadOnly {
                                    Button("Edit") { editing = card }
                                    Button("Delete", role: .destructive) { remove(card) }
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            store.moveShowCards(from: offsets, to: destination)
                        }

                        // A row rather than the section's `footer`, which draws
                        // its own white band under a `.plain` list and takes no
                        // `listRowBackground` — the paper stopped at the last
                        // card and the sentence sat on a white strip.
                        Aside(text: isReadOnly
                              ? "This trip is closed, so the cards are as they were written."
                              : "Tap a card to write it; hold it to edit or delete.",
                              size: 11.5)
                            .padding(.vertical, Space.s1)
                            .listRowBackground(Palette.bg)
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("In the order you swipe them")
                                .font(Typeface.heading(17, .semibold))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Mono("\(cards.count)", size: 10, trackingRatio: 0.08)
                        }
                        .textCase(nil)
                        .padding(.top, Space.s2)
                    }

                }

                if !isReadOnly {
                    Section {
                        Button { writing = true } label: {
                            Mono("+ write a card", size: 10, trackingRatio: 0.08, color: Palette.a700)
                                .frame(minHeight: 38)
                        }
                        .listRowBackground(Palette.bg)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(isReadOnly ? .inactive : .active))
            .scrollContentBackground(.hidden)
            .background(Palette.bg)

            if let undoable {
                UndoBanner(text: "Deleted \(undoable.shortName.isEmpty ? "untitled" : undoable.shortName)") {
                    store.restoreShowCard(undoable.id)
                    Task { await store.syncNow() }
                    undoTimer?.cancel()
                    self.undoable = nil
                }
            }
        }
        .background(Palette.bg)
        .gentleAnimation(.easeInOut(duration: 0.2), value: undoable)
        // The window belongs to this sheet. Without it the task outlives the
        // view and wakes ten seconds later to clear a `@State` nothing reads —
        // and an undo offer that survives the sheet closing is an offer about a
        // card you can no longer see.
        .onDisappear {
            undoTimer?.cancel()
            undoTimer = nil
            undoable = nil
        }
        .sheet(isPresented: $writing) { ShowCardEditorView(editing: nil) }
        .sheet(item: $editing) { card in ShowCardEditorView(editing: card) }
    }

    // MARK: - Deleting, and taking it back

    /// The ledger's `remove(_:)`, one collection over. No confirmation: the card
    /// is tombstoned rather than destroyed, and the banner is what stands in
    /// front of a mistake. Documents are the other way round for the opposite
    /// reason — deleting one takes its scans with it and nothing can undo that.
    private func remove(_ card: ShowCard) {
        store.deleteShowCard(card.id)
        Task { await store.syncNow() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        undoable = card
        undoTimer?.cancel()
        // `@MainActor`, explicitly. An ordinary method of a view struct carries
        // no isolation of its own — only `body` inherits it — so a bare
        // `Task { }` would clear SwiftUI state off the main thread.
        undoTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            undoable = nil
        }
    }

    private func row(_ card: ShowCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Mono(card.shortName.isEmpty ? "untitled" : card.shortName,
                     size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                Spacer()
                if isReadOnly {
                    EmptyView()
                } else {
                    Mono("edit", size: 9.5, trackingRatio: 0.08, color: Palette.n700)
                }
            }
            Text(card.native)
                .font(Typeface.heading(18, .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(2)
            Aside(text: card.english, size: 11.5)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// The language of wherever they are, or a name for not knowing.
    private var languageName: String { store.currentLanguage ?? "the local language" }
}

// MARK: - Writing one

/// New and edit in one sheet, the way `AddExpenseView` is — same seven fields,
/// and two copies of them would drift.
struct ShowCardEditorView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    var editing: ShowCard?

    @State private var native = ""
    @State private var english = ""
    @State private var shortName = ""
    @State private var footerTitle = ""
    @State private var footerBody = ""
    @State private var footerNote = ""
    @State private var showingFooter = false
    @State private var confirmingDelete = false
    @State private var askingToDiscard = false
    @FocusState private var focused: Bool

    private var isDirty: Bool {
        let typed: [String] = [native, english, shortName, footerTitle, footerBody, footerNote]
        let saved: [String] = [editing?.native ?? "", editing?.english ?? "",
                               editing?.shortName ?? "", editing?.footerTitle ?? "",
                               editing?.footerBody ?? "", editing?.footerNote ?? ""]
        return typed != saved
    }

    /// A card that reads in only one language is the one thing it must not be:
    /// half of it is for the stranger and half is for the person holding it out,
    /// and neither half can be inferred from the other.
    private var isComplete: Bool {
        !native.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What to call the language of wherever they are.
    ///
    /// A label, not a translation. `CountryFacts` answers `nil` for a country
    /// with no single honest answer and for one it has never heard of, and the
    /// fallback says exactly that rather than guessing.
    private var languageLabel: String { store.currentLanguage ?? "Local language" }

    /// The same answer inside a sentence. Not `languageLabel.lowercased()` —
    /// that reads "somebody who reads thai", and a language is a proper noun
    /// in a way "the local language" isn't.
    private var languagePhrase: String { store.currentLanguage ?? "the local language" }

    private var preview: ShowCard {
        ShowCard(native: native.isEmpty ? "…" : native,
                 english: english.isEmpty ? "…" : english,
                 footerTitle: footerTitle.isEmpty ? nil : footerTitle,
                 footerBody: footerBody.isEmpty ? nil : footerBody,
                 footerNote: footerNote.isEmpty ? nil : footerNote,
                 shortName: shortName)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: editing == nil ? "New card" : "Edit card",
                        trailing: "Cancel") {
                if isDirty { askingToDiscard = true } else { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono(store.currentLanguage == nil
                         ? "Wherever you are"
                         : "In \(store.currentCountry)", size: 10.5)

                    Display(text: editing == nil ? "One\nsentence" : "That card", size: 34)
                        .padding(.top, 8)
                        .padding(.bottom, Space.s3)

                    Mono(languageLabel, size: 10).padding(.bottom, 8)
                    // Not a sample sentence. Any real one would have to be in
                    // *some* language, and a Thai placeholder is what a phone
                    // standing in Busan would have shown — the field's whole
                    // job is to ask for a script the app can't supply.
                    TextField("", text: $native, prompt: Text("Write it in \(languagePhrase)")
                        .font(Typeface.heading(23).resolved(for: .large))
                        .foregroundStyle(Palette.n600),
                              axis: .vertical)
                        .font(Typeface.heading(23))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.bottom, 8)
                    Rectangle().fill(Palette.accent).frame(height: 1)

                    // Said plainly, because the app cannot check this and the
                    // card is only useful if somebody who reads the language did.
                    Aside(text: "Di Thôi doesn't translate — it only asks. Have somebody who reads \(languagePhrase) check it before you need it.",
                          size: 11.5)
                        .padding(.top, Space.s1)

                    Mono("English", size: 10)
                        .padding(.top, Space.s4)
                        .padding(.bottom, 8)
                    TextField("", text: $english, prompt: Text("Where is the nearest pharmacy?")
                        .font(Typeface.body(17).resolved(for: .large))
                        .foregroundStyle(Palette.n600),
                              axis: .vertical)
                        .font(Typeface.body(17))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1...5)
                        .padding(.bottom, 8)
                    Rectangle().fill(Palette.accent).frame(height: 1)
                    Aside(text: "What you're holding out, so you know which card is which.", size: 11.5)
                        .padding(.top, Space.s1)

                    WrittenField(label: "Name it, for the swipe", text: $shortName,
                                 placeholder: "pharmacy",
                                 note: "One word. It's the hint at the edge of the screen.",
                                 size: 19)
                        .padding(.top, Space.s4)

                    // Four of the five seeded cards have no footer, so it does
                    // not take up room until somebody asks for it.
                    Button {
                        withGentleAnimation(.easeInOut(duration: 0.2)) { showingFooter.toggle() }
                    } label: {
                        Mono(showingFooter ? "− the small print" : "+ add small print",
                             size: 10, trackingRatio: 0.08, color: Palette.a700)
                            .frame(minHeight: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Space.s3)

                    if showingFooter {
                        WrittenField(label: "Heading", text: $footerTitle,
                                     placeholder: "If it goes wrong", size: 17)
                            .padding(.bottom, Space.s3)
                        WrittenField(label: "The thing itself", text: $footerBody,
                                     placeholder: "What they need to know", size: 17)
                            .padding(.bottom, Space.s3)
                        WrittenField(label: "And a note", text: $footerNote,
                                     placeholder: "and anything after it", size: 15)
                    }

                    SectionRule(top: Space.s6, bottom: Space.s3)

                    Mono("As they'll see it", size: 10)
                    // The same view the stranger gets, not a drawing of it.
                    ShowCardFace(card: preview)
                        .padding(.vertical, Space.s4)
                        .frame(maxWidth: .infinity)
                        .background(Palette.n100)
                        .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
                        .padding(.top, Space.s2)

                    if editing != nil {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Mono("delete this card", size: 10, trackingRatio: 0.08, color: Palette.n700)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Space.s3)
                    }
                }
                .padding(.horizontal, Space.gutter)
            }

            OutlineButton(title: editing == nil ? "Add it" : "Save it") { save() }
                .disabled(!isComplete)
                .opacity(isComplete ? 1 : 0.4)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .onAppear(perform: load)
        .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard) { dismiss() }
        .confirmationDialog("Delete this card?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete it", role: .destructive) {
                if let editing { store.deleteShowCard(editing.id) }
                Task { await store.syncNow() }
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It goes from both phones. Nothing else on this screen changes.")
        }
    }

    private func load() {
        guard let editing else {
            focused = true
            return
        }
        native = editing.native
        english = editing.english
        shortName = editing.shortName
        footerTitle = editing.footerTitle ?? ""
        footerBody = editing.footerBody ?? ""
        footerNote = editing.footerNote ?? ""
        showingFooter = editing.footerTitle != nil
    }

    private func save() {
        func clean(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let name = clean(shortName) ?? "card"

        if var card = editing {
            // Taken whole and handed back, so `index` and `id` ride along
            // untouched — reordering and editing are separate mutations.
            card.native = native.trimmingCharacters(in: .whitespacesAndNewlines)
            card.english = english.trimmingCharacters(in: .whitespacesAndNewlines)
            card.shortName = name
            card.footerTitle = clean(footerTitle)
            card.footerBody = clean(footerBody)
            card.footerNote = clean(footerNote)
            store.updateShowCard(card)
        } else {
            store.addShowCard(native: native.trimmingCharacters(in: .whitespacesAndNewlines),
                              english: english.trimmingCharacters(in: .whitespacesAndNewlines),
                              shortName: name,
                              footerTitle: clean(footerTitle),
                              footerBody: clean(footerBody),
                              footerNote: clean(footerNote))
        }
        Task { await store.syncNow() }
        dismiss()
    }
}
