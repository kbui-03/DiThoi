import SwiftUI

/// Writing a day.
///
/// The trip's *shape* has always been editable — `ItineraryEditorView` moves
/// stops and nights around — but what happens inside a day was a constant
/// seeded from `SampleTrip`, which meant a fortnight in Lisbon opened with
/// Chiang Mai's Songkran plan or with nothing at all. This is the other half.
///
/// Everything commits through `TripStore`, one field at a time, on the way out
/// of the field rather than per keystroke: `save()` encodes the whole trip, and
/// a bound `TextField` writing on every letter is what the coalescing in
/// `TripStore.save` exists to survive rather than something to lean on.
struct DayPlanEditorView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    let day: Int
    /// Named by the caller, which knows the segment. Shown, never stored — the
    /// store seeds a new plan's `city` from the itinerary itself.
    let city: String

    @State private var blurb = ""
    @State private var occasion = ""
    @State private var lodgingTitle = ""
    @State private var lodgingNote = ""
    @State private var addingItem = false
    @State private var editingItem: PlanItem?
    @State private var confirmingRemoval: PlanItem?
    @State private var confirmingClear = false
    @FocusState private var blurbFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var plan: DayPlan? { store.plan(forDay: day) }
    /// By time, the way the day page draws them. Typing a time is the order.
    private var items: [PlanItem] { plan?.orderedItems ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Day \(day) · \(city)", trailing: "Done") {
                commit()
                Task { await store.syncNow() }
                dismiss()
            }

            List {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        Mono("The day, in a sentence", size: 10).padding(.bottom, 8)

                        // Never another day's actual words: a placeholder that
                        // could be real content reads as this day's plan until
                        // you notice the grey.
                        TextField("", text: $blurb, prompt: Text("A slow one. Market, then the river.")
                            .font(Typeface.body(14).resolved(for: .large))
                            .foregroundStyle(Palette.n600),
                                  axis: .vertical)
                            .font(Typeface.body(14))
                            .lineSpacing(4)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2...8)
                            .focused($blurbFocused)
                            .padding(.bottom, 8)

                        Rectangle().fill(Palette.accent).frame(height: 1)
                    }
                    .padding(.vertical, Space.s2)
                    .listRowBackground(Palette.bg)

                    WrittenField(label: "Occasion, if it's one", text: $occasion,
                                 placeholder: "Someone's birthday", size: 19)
                        .padding(.vertical, Space.s2)
                        .listRowBackground(Palette.bg)
                }

                Section {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            itemRow(item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Palette.bg)
                    }
                    // No dragging: the hours sort by their time, so the order
                    // is the clock's. No swipe-to-delete either, which this
                    // app uses nowhere: a removal that takes a confirmation on
                    // one screen shouldn't take a flick on the next.

                    Button {
                        addingItem = true
                    } label: {
                        Mono("+ add an hour", size: 10, trackingRatio: 0.08, color: Palette.a700)
                            .frame(minHeight: 38)
                    }
                    .listRowBackground(Palette.bg)
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("The hours")
                            .font(Typeface.heading(17, .semibold))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Mono(items.isEmpty ? "none yet" : "\(items.count)", size: 10, trackingRatio: 0.08)
                    }
                    .textCase(nil)
                    .padding(.top, Space.s2)
                }

                Section {
                    WrittenField(label: "Where you're sleeping", text: $lodgingTitle,
                                 placeholder: "The place with the blue door", size: 19)
                        .padding(.vertical, Space.s2)
                        .listRowBackground(Palette.bg)

                    WrittenField(label: "Anything worth remembering about it",
                                 text: $lodgingNote,
                                 placeholder: "Ask for the room at the back", size: 15)
                        .padding(.vertical, Space.s2)
                        .listRowBackground(Palette.bg)
                }

                if plan != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingClear = true
                        } label: {
                            Mono("clear this day", size: 10, trackingRatio: 0.08, color: Palette.n700)
                                .frame(minHeight: 38)
                        }
                        .listRowBackground(Palette.bg)

                        // A row, not the section's `footer:`, which draws its
                        // own white band where the paper stops (§3.12).
                        Aside(text: "Clears the sentence, the hours and the lodging for day \(day). The itinerary, the money and the trail are untouched.",
                              size: 11.5)
                            .padding(.top, Space.s1)
                            .listRowBackground(Palette.bg)
                            .listRowSeparator(.hidden, edges: .top)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
        }
        .background(Palette.bg)
        // Keyed on the day, not just `onAppear`. `@State` survives the view
        // struct being rebuilt with a different `day`, so a one-shot load left
        // the fields showing the day they were filled from while the header
        // named a different one — which is exactly what `-screen dayplan
        // -day 20` showed: Chiang Mai's Songkran under "Day 20 · Chiang Rai".
        .task(id: day) { load() }
        // Done isn't the only way out. A swipe down used to lose the
        // occasion and the lodging, which only `commit()` writes; this is the
        // setup screens' rule (§5.4), and `commit()` writes only what changed.
        .onDisappear { commit() }
        // Committed as the field is left, not per keystroke.
        .onChange(of: blurbFocused) { _, focused in
            if !focused { store.setBlurb(blurb, forDay: day) }
        }
        .sheet(isPresented: $addingItem) {
            PlanItemEditorView(day: day, city: city, editing: nil, onCommit: commit)
        }
        .sheet(item: $editingItem) { item in
            PlanItemEditorView(day: day, city: city, editing: item, onCommit: commit)
        }
        .confirmationDialog("Remove this hour?",
                            isPresented: Binding(get: { confirmingRemoval != nil },
                                                 set: { if !$0 { confirmingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Remove it", role: .destructive) {
                if let item = confirmingRemoval {
                    commit()
                    store.removeItem(item.id, fromDay: day)
                }
                confirmingRemoval = nil
            }
            Button("Keep it", role: .cancel) { confirmingRemoval = nil }
        } message: {
            Text(confirmingRemoval.map { "\($0.title) comes off day \(day)." } ?? "")
        }
        .confirmationDialog("Clear day \(day)?", isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button("Clear it", role: .destructive) {
                store.clearPlan(forDay: day)
                load()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everything written about this day goes, on both phones. Writing in it again brings it back.")
        }
    }

    /// One hour, as a row.
    ///
    /// Four things want this line — the time, the title, "remove" and the
    /// system's own drag handle — and at an accessibility size that broke
    /// "07:30" into "07 / :3 / 0". Past that point they stack instead: the
    /// time and the remove on one line, the title and the note under it.
    @ViewBuilder
    private func itemRow(_ item: PlanItem) -> some View {
        let time = Text(item.time.isEmpty ? "—" : item.time)
            .font(Typeface.mono(11))
            .monospacedDigit()
            .foregroundStyle(Palette.a700)
        let words = VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(Typeface.heading(16, .semibold))
                .foregroundStyle(Palette.text)
            if !item.note.isEmpty {
                Aside(text: item.note, size: 11.5)
            }
        }
        let remove = Button(role: .destructive) {
            confirmingRemoval = item
        } label: {
            Mono("remove", size: 9.5, trackingRatio: 0.08, color: Palette.n700)
        }
        .buttonStyle(.plain)

        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        time
                        Spacer(minLength: 8)
                        remove
                    }
                    words
                }
            } else {
                HStack(alignment: .top, spacing: Space.s3) {
                    time
                        .frame(width: 46, alignment: .leading)
                        .padding(.top, 2)
                    words
                    Spacer(minLength: 8)
                    remove
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func load() {
        blurb = plan?.blurb ?? ""
        occasion = plan?.occasion ?? ""
        lodgingTitle = plan?.lodgingTitle ?? ""
        lodgingNote = plan?.lodgingNote ?? ""
    }

    /// Writes the typed fields back before anything that reads the plan from
    /// the store — a move, a removal, a sub-sheet, or Done. Without it, a
    /// half-typed sentence sitting in `@State` is lost the moment the list
    /// mutates underneath it.
    private func commit() {
        if blurb != (plan?.blurb ?? "") { store.setBlurb(blurb, forDay: day) }
        if occasion != (plan?.occasion ?? "") { store.setOccasion(occasion, forDay: day) }
        if lodgingTitle != (plan?.lodgingTitle ?? "") || lodgingNote != (plan?.lodgingNote ?? "") {
            store.setLodging(title: lodgingTitle, note: lodgingNote, forDay: day)
        }
    }
}

// MARK: - One hour of it

/// New and edit in one sheet, the way `AddExpenseView` does it — the fields are
/// identical and two of them would drift.
private struct PlanItemEditorView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    let day: Int
    let city: String
    var editing: PlanItem?
    /// Flushes the parent's typed fields first, so adding an hour can't drop a
    /// sentence somebody was halfway through.
    var onCommit: () -> Void

    @State private var time = ""
    @State private var title = ""
    @State private var note = ""
    @State private var askingToDiscard = false
    @FocusState private var focused: Bool

    private var isComplete: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var isDirty: Bool {
        time != (editing?.time ?? "") || title != (editing?.title ?? "")
            || note != (editing?.note ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: editing == nil ? "New hour" : "Edit hour",
                        trailing: "Cancel") {
                if isDirty { askingToDiscard = true } else { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("Day \(day) · \(city)", size: 10.5)

                    Display(text: editing == nil ? "What's\nhappening" : "That hour", size: 34)
                        .padding(.top, 8)
                        .padding(.bottom, Space.s3)

                    TextField("", text: $title, prompt: Text("Breakfast at the market")
                        .font(Typeface.heading(23).resolved(for: .large))
                        .foregroundStyle(Palette.n600))
                        .font(Typeface.heading(23))
                        .foregroundStyle(Palette.text)
                        .focused($focused)
                        .frame(minHeight: 48)

                    Rectangle().fill(Palette.accent).frame(height: 1)

                    // Free text: the model stores a string and the screens
                    // print it in a 52pt monospace column, so "07:30" and
                    // "after dark" both fit a day nobody has booked.
                    Mono("When", size: 10)
                        .padding(.top, Space.s4)
                        .padding(.bottom, 4)
                    field($time, placeholder: "07:30")

                    Mono("Anything worth knowing", size: 10)
                        .padding(.top, Space.s3)
                        .padding(.bottom, 4)
                    field($note, placeholder: "Closes at 2pm. Cash only.")
                }
                .padding(.horizontal, Space.gutter)
            }

            OutlineButton(title: editing == nil ? "Add it" : "Save it") {
                onCommit()
                let cleanTime = time.trimmingCharacters(in: .whitespaces)
                let cleanTitle = title.trimmingCharacters(in: .whitespaces)
                let cleanNote = note.trimmingCharacters(in: .whitespaces)
                if var item = editing {
                    item.time = cleanTime
                    item.title = cleanTitle
                    item.note = cleanNote
                    store.updateItem(item, onDay: day)
                } else {
                    store.addItem(time: cleanTime, title: cleanTitle, note: cleanNote, toDay: day)
                }
                dismiss()
            }
            .disabled(!isComplete)
            .opacity(isComplete ? 1 : 0.4)
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard) { dismiss() }
        .onAppear {
            if let editing {
                time = editing.time
                title = editing.title
                note = editing.note
            }
            focused = editing == nil
        }
    }

    private func field(_ text: Binding<String>, placeholder: String) -> some View {
        VStack(spacing: 0) {
            TextField("", text: text, prompt: Text(placeholder)
                .font(Typeface.body(17).resolved(for: .large))
                .foregroundStyle(Palette.n600))
                .font(Typeface.body(17))
                .foregroundStyle(Palette.text)
                .frame(minHeight: 44)
            Rule()
        }
    }
}
