import SwiftUI

/// E1 / H2 · Tonight's entry. One line, one photo, a few tags — the line
/// first and ready to type, a question about the day greyed in it, and the
/// tags used most in this city already lit.
///
/// The photo is picked or taken, never chosen for you. Choosing would mean read
/// access to the whole camera roll; `PHPickerViewController` needs no
/// permission at all, and the camera asks only for itself (and add-only
/// access, to put what it took in the library too).
///
/// Spots kept in one tap today are offered here to finish — only today's, so
/// the evening prompt never turns into last week's chores.
struct TonightEntryView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    var day: Int?

    @State private var line = ""
    @State private var tags: Set<String> = []
    @State private var photoID: String?
    /// Optional, and closed until asked for: tonight is still photo → line →
    /// Done for anybody who never taps "+ another photo" or "+ a few more lines".
    @State private var extraPhotoIDs: [String] = []
    @State private var note = ""
    @State private var writingNote = false
    @State private var addingTag = false
    @State private var newTag = ""
    /// Which slot the picker is filling. One `photoIntake` with a target
    /// rather than two: two presentation modifiers on one view is the
    /// arrangement where the later swallows the earlier.
    @State private var pickingExtra = false
    /// Photographs this sheet wrote to disk — picked, taken or borrowed. Only
    /// these are ever deleted from here, and only once it is known which one
    /// the page kept: at save, or all of them if the sheet closes unsaved.
    ///
    /// It used to delete as it went. "swap" removed the file of a page that
    /// was already saved, so swap-then-Close left the page pointing at
    /// nothing; the file the page owns is now only ever let go by
    /// `save(entry:)` replacing it, or by the prune.
    @State private var madeHere: Set<String> = []
    /// Which copy each borrowed moment put on the page, so tapping it again
    /// takes that copy back off. A copy the page no longer holds — removed
    /// with the cross, or swapped away — simply isn't on the page any more.
    @State private var borrowed: [UUID: String] = [:]
    @State private var didSave = false
    @State private var confirmingRemoval = false
    @State private var pickingPhoto = false
    @State private var saved: JournalEntry?
    @State private var startedAt = Date()
    /// The question tonight's blank line asks, chosen once as the sheet
    /// opens. A new one each time it opens, and none while it is open: a
    /// placeholder that changed on a timer would move under somebody
    /// thinking about what to write.
    @State private var prompt = ""
    @State private var finishing: Moment?
    @FocusState private var lineFocused: Bool
    /// What the page was when the sheet opened, so leaving can tell an
    /// untouched page from one with work on it.
    @State private var opened = PageFields()
    @State private var askingToDiscard = false

    private struct PageFields: Equatable {
        var line = ""
        var tags: Set<String> = []
        var photoID: String?
        var extraPhotoIDs: [String] = []
        var note = ""
    }

    private var current: PageFields {
        PageFields(line: line, tags: tags, photoID: photoID,
                   extraPhotoIDs: extraPhotoIDs, note: note)
    }

    private var isDirty: Bool { saved == nil && !didSave && current != opened }

    private func close() {
        if isDirty { askingToDiscard = true } else { dismiss() }
    }

    /// Written to disk ahead of the save, so held against the prune until the
    /// sheet knows what the page kept.
    private func made(_ id: String) {
        madeHere.insert(id)
        PhotoStore.shared.hold(id)
    }

    private let limit = JournalEntry.lineLimit

    private var targetDay: Int { day ?? store.dayNumber }
    private var isTonight: Bool { targetDay == store.dayNumber }

    var body: some View {
        Group {
            if let saved {
                SavedPageView(entry: saved, pageNumber: pageNumber,
                              minutes: minutesTaken) { dismiss() }
            } else {
                composer
                    .guardsUnsavedWork(isDirty: isDirty, isAsking: $askingToDiscard,
                                       whatGoes: "The line, the tags and any photos you added go.") {
                        // `onDisappear` deletes what this sheet wrote.
                        dismiss()
                    }
            }
        }
        .background(Palette.bg)
        .onAppear {
            load()
            prompt = pickPrompt()
        }
        .onDisappear {
            defer { PhotoStore.shared.release(madeHere) }
            guard !didSave else { return }
            for id in madeHere { PhotoStore.shared.delete(id) }
        }
        .confirmationDialog("Take day \(targetDay) out of the book?", isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button("Remove the page", role: .destructive) {
                store.deleteEntry(day: targetDay)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The line and the photo go. You can write the night again afterwards.")
        }
        .sheet(item: $finishing) { moment in
            MomentComposerView(editing: moment)
        }
        .photoIntake(isPresented: $pickingPhoto) { square in
            if let saved = PhotoStore.shared.save(square) {
                made(saved)
                if pickingExtra {
                    if extraPhotoIDs.count < JournalEntry.extraPhotoLimit { extraPhotoIDs.append(saved) }
                } else {
                    photoID = saved
                }
            }
            pickingExtra = false
        }
        .alert("A tag of your own", isPresented: $addingTag) {
            TextField("one or two words", text: $newTag)
                .textInputAutocapitalization(.never)
            Button("Add") {
                if let tag = store.addTag(newTag) { tags.insert(tag) }
                newTag = ""
            }
            Button("Cancel", role: .cancel) { newTag = "" }
        } message: {
            Text("It joins the row for every night after this one.")
        }
    }

    // MARK: - The composer

    /// Line first. The screen used to open on the city at 32pt, an aside, a
    /// "finish it" row, the moments strip and its aside, and a full-width
    /// photo square — and only then the line, below the fold, on any night
    /// with a moment in it. Six sentences on it described the screen rather
    /// than the day. Now: one header line, the line, one row of everything
    /// that can go on the page as a picture, one row of tags, the button.
    private var composer: some View {
        VStack(spacing: 0) {
            SheetHeader(title: headerTitle, trailing: "Close") { close() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let subline {
                        Mono(subline, size: 10, color: Palette.a700)
                            .padding(.top, Space.s1)
                    }

                    TextField("", text: $line, prompt: Text(placeholder)
                        .font(Typeface.heading(23).resolved(for: typeSize))
                        .foregroundStyle(Palette.n500), axis: .vertical)
                        .font(Typeface.heading(23))
                        .tracking(-0.23)
                        .lineSpacing(6)
                        .foregroundStyle(Palette.text)
                        .focused($lineFocused)
                        .textInputAutocapitalization(.sentences)
                        .frame(minHeight: 58, alignment: .top)
                        .padding(.top, Space.s4)
                        .onChange(of: line) { _, newValue in
                            if newValue.count > limit { line = String(newValue.prefix(limit)) }
                            if newValue.contains("\n") { line = newValue.replacingOccurrences(of: "\n", with: " ") }
                        }
                        .accessibilityLabel("One line about the day")

                    Rectangle().fill(Palette.accent).frame(height: 1)
                        .padding(.top, Space.s2)

                    HStack(alignment: .firstTextBaseline) {
                        if !showsNote { noteArea }
                        Spacer(minLength: 8)
                        // Only once it is close: a "0 of 120" under an empty
                        // line is a number with nothing to say.
                        if line.count >= limit - 20 {
                            Mono("\(line.count) of \(limit)", size: 9.5, trackingRatio: 0.08)
                        }
                    }
                    if showsNote { noteArea }

                    pictureRow
                        .padding(.top, Space.s6)

                    if photoID != nil {
                        mainPhoto
                            .padding(.top, Space.s3)
                    }

                    tagRow
                        .padding(.top, Space.s6)

                    // A page that exists can be taken out. There was no way
                    // to do it: clearing the line read "Skip tonight" and left
                    // the page in the book.
                    if hasExistingPage {
                        Button { confirmingRemoval = true } label: {
                            Mono("remove this page", size: 9.5, trackingRatio: 0.1, color: Palette.n600)
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
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: Space.s2) {
                // The one sentence left that isn't about the screen: where
                // this page lives. It used to be "Private" in the corner.
                Mono("Yours alone · on this phone", size: 9.5, trackingRatio: 0.08, color: Palette.n500)
                    .multilineTextAlignment(.center)
                OutlineButton(title: canSave ? "Done" : (isTonight ? "Skip tonight" : "Not now"),
                              minHeight: 48, size: 15) {
                    save()
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .task {
            // The line is the ask, so it opens ready to type — on a new page,
            // at an ordinary text size. At an accessibility size the keyboard
            // would cover the picture row, and "start from a moment" would be
            // a feature nobody could see. After the sheet's own animation: a
            // focus asked for mid-presentation is dropped.
            guard line.isEmpty, !typeSize.isAccessibilitySize else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            lineFocused = true
        }
    }

    /// "Day 12 · Chiang Mai · p. 10" — what the header, a page line and a
    /// 32pt city used to say three times. A night written late says so on a
    /// line of its own under it: appended here it ran into "Close".
    ///
    /// At an accessibility size the header is the day alone and the rest
    /// moves down a line: in one line it wrapped "Chiang / Mai" into "Close".
    private var headerTitle: String {
        let day = "Day \(targetDay)"
        guard !typeSize.isAccessibilitySize else { return day }
        return ([day] + whereAndPage).joined(separator: " · ")
    }

    private var whereAndPage: [String] {
        var parts: [String] = []
        let city = store.city(forDay: targetDay)
        if !city.isEmpty, city != TripStore.unknownPlace { parts.append(city) }
        if let pageNumber { parts.append("p. \(pageNumber)") }
        return parts
    }

    /// The line under the header, when there is one: a night written late,
    /// and at an accessibility size the place and page the header gave up.
    private var subline: String? {
        var parts = typeSize.isAccessibilitySize ? whereAndPage : []
        if !isTonight { parts.append(parts.isEmpty ? "A night you missed" : "missed") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Pictures

    /// Everything that can put a picture on the page, in one row: the "+"
    /// for the library or the camera, then the night's moments, then — tonight
    /// only — the spots kept today and not yet written up.
    ///
    /// They were three things that looked unrelated: a strip with its own
    /// heading and aside, a full-width square, and a row of extras under it.
    /// It is one decision — what pictures go on tonight's page.
    ///
    /// Anything that grows here grows *below* the row — the chosen photograph,
    /// the extras — so the row never moves under a finger between two taps.
    private var pictureRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Mono(pictureHeading, size: 10)
                Spacer(minLength: 8)
                if !hasPhotoRoom {
                    Mono("the page is full", size: 9.5, trackingRatio: 0.08, color: Palette.n600)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.s2) {
                    if hasPhotoRoom {
                        Button {
                            pickingExtra = photoID != nil
                            pickingPhoto = true
                        } label: {
                            Hatching()
                                .frame(width: Self.tile, height: Self.tile)
                                .overlay(Text("+")
                                    .font(Typeface.heading(24))
                                    .foregroundStyle(Palette.n700))
                                .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photoID == nil ? "Choose tonight's photo" : "Add another photo")
                    }
                    ForEach(stripMoments) { moment in
                        let onPage = copyOnPage(moment) != nil
                        Button { borrow(moment) } label: { momentTile(moment, onPage: onPage) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(moment.note.isEmpty ? "A photograph from that day" : moment.note)
                            .accessibilityValue(onPage ? "On the page" : "")
                            .accessibilityHint(onPage ? "Takes its photograph off the page."
                                               : "Copies it onto the page. The moment stays as it is.")
                    }
                    if isTonight {
                        ForEach(store.unfinishedToday) { moment in
                            Button { finishing = moment } label: { unfinishedTile }
                                .buttonStyle(.plain)
                                .accessibilityLabel("A spot kept today, not written up yet")
                                .accessibilityHint("Opens it to finish")
                        }
                    }
                }
                // Room for the ring drawn outside a tile that is on the page.
                .padding(3)
            }
            .padding(.horizontal, -3)
        }
    }

    private static let tile: CGFloat = 62

    private var pictureHeading: String {
        let hasMoments = !stripMoments.isEmpty || (isTonight && !store.unfinishedToday.isEmpty)
        guard hasMoments else { return "Tonight's photo" }
        return isTonight ? "From today" : "From day \(targetDay)"
    }

    @ViewBuilder
    private func momentTile(_ moment: Moment, onPage: Bool) -> some View {
        if moment.photoID != nil {
            // The mount adds 6 a side; the tile is the mounted size, so a
            // photograph lines up with the "+" and the words beside it.
            JournalPhoto(photoID: moment.photoID, side: Self.tile - 12, usesThumbnail: true)
                .overlay(Rectangle().strokeBorder(Palette.accent, lineWidth: onPage ? 2 : 0).padding(-3))
                .opacity(onPage || hasPhotoRoom ? 1 : 0.45)
        } else {
            // A moment in words gives the page words, not a picture, so it is
            // drawn as words: wider, and growing downward rather than holding
            // one word and an ellipsis at an accessibility size.
            Text(moment.note)
                .font(Typeface.heading(12.5).capped(at: 1.4))
                .foregroundStyle(Palette.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .padding(8)
                .frame(width: 132, alignment: .topLeading)
                .frame(minHeight: Self.tile, alignment: .topLeading)
                .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
        }
    }

    /// A spot kept in one tap and never written up: nothing to copy, so it
    /// doesn't look like the tiles that copy. It opens the moment instead.
    private var unfinishedTile: some View {
        Mono("finish", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
            .frame(width: Self.tile, height: Self.tile)
            .overlay(Rectangle().strokeBorder(Palette.n500, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
    }

    /// The photograph the page opens on, once there is one — full width,
    /// because that is when it is worth the room. Tap to replace it; "swap"
    /// lets it go and the next one up takes its place.
    private var mainPhoto: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                pickingExtra = false
                pickingPhoto = true
            } label: {
                JournalPhoto(photoID: photoID)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tonight's photo. Tap to replace it.")

            HStack(alignment: .center, spacing: Space.s2) {
                ForEach(extraPhotoIDs, id: \.self) { id in
                    ZStack(alignment: .topTrailing) {
                        JournalPhoto(photoID: id, side: 56, usesThumbnail: true)
                        Button {
                            extraPhotoIDs.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Palette.bg))
                                .frame(width: 44, height: 44, alignment: .topTrailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 10, y: -10)
                        .accessibilityLabel("Take this photo off the page")
                    }
                }
                Spacer(minLength: 0)
                Button {
                    photoID = nil
                    // The next one up takes the main photograph's place, so a
                    // page is never extras around a hole.
                    if !extraPhotoIDs.isEmpty { photoID = extraPhotoIDs.removeFirst() }
                } label: {
                    Mono("swap", size: 9.5, trackingRatio: 0.1, color: Palette.a700)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Space.s2)
        }
    }

    // MARK: - Tags

    /// One row, scrolled sideways, with the ones lit from this city first —
    /// where the thumb already is. It was a wrapping block of nine under a
    /// heading, with a sentence explaining why some were lit.
    private var tagRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Mono("How it felt", size: 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    ForEach(chipOrder, id: \.self) { tag in
                        Chip(text: tag, selected: tags.contains(tag)) {
                            if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                    // The row was eight fixed words for good: suggestions
                    // come from what has been tagged, and only those eight
                    // ever could be.
                    Chip(text: "+ your own", selected: false) { addingTag = true }
                }
            }
        }
    }

    private var showsNote: Bool { writingNote || !note.isEmpty }

    /// A few more lines, under the one. Closed until asked for.
    @ViewBuilder
    private var noteArea: some View {
        if showsNote {
            VStack(alignment: .leading, spacing: 6) {
                Mono("A few more lines", size: 10)
                    .padding(.top, Space.s4)
                TextField("", text: $note, prompt: Text("Whatever didn't fit in one.")
                    .foregroundStyle(Palette.n500), axis: .vertical)
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.text)
                    .lineLimit(3...10)
                    .onChange(of: note) { _, value in
                        if value.count > JournalEntry.noteLimit { note = String(value.prefix(JournalEntry.noteLimit)) }
                    }
                Rectangle().fill(Palette.divider).frame(height: 1)
                HStack {
                    Spacer()
                    Mono("\(note.count) of \(JournalEntry.noteLimit)", size: 9.5, trackingRatio: 0.08)
                }
            }
        } else {
            Button { writingNote = true } label: {
                Mono("+ a few more lines", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - What's already filled in

    private var suggested: [String] { store.suggestedTags(forDay: targetDay) }

    /// The words offered when the trip has no history to draw on yet. Kept
    /// short, general and about how a day felt rather than where it happened,
    /// so they fit any trip.
    private static let vocabulary = [
        "tired", "quiet", "proud", "lost", "homesick",
        "strangers", "food", "long day"
    ]

    /// Suggestions first, then the rest of the vocabulary, so the pre-lit ones
    /// are where the thumb already is.
    private var chipOrder: [String] {
        let words = Self.vocabulary + store.customTags.filter { !Self.vocabulary.contains($0) }
        // Tags on this page that are neither — an older trip's own word — still
        // show, lit, so they can be turned off.
        let extra = tags.filter { !words.contains($0) }.sorted()
        return suggested + (words + extra).filter { !suggested.contains($0) }
    }

    /// A question about the day, greyed, so the page is never blank. Always
    /// a question, never an example: grey words that weren't a question would
    /// read as tonight's entry. It used to be yesterday's line.
    private var placeholder: String {
        prompt.isEmpty ? "One line about today" : prompt
    }

    private func pickPrompt() -> String {
        let prompts = store.linePrompts(forDay: targetDay)
        #if DEBUG
        // `-promptIndex n`, so a screenshot can show a chosen question rather
        // than whichever one came up.
        if let raw = UserDefaults.standard.string(forKey: "promptIndex"), let index = Int(raw),
           index >= 0, !prompts.isEmpty {
            return prompts[index % prompts.count]
        }
        #endif
        return prompts.randomElement() ?? ""
    }

    // MARK: - Saving

    /// Only deletes a file this page actually owns.
    // MARK: - Borrowing from today's moments

    /// The night's written-up moments: today's tonight, and that day's when a
    /// missed night is being written — the night they were kept is the night
    /// they belong to, whenever it gets its page.
    private var stripMoments: [Moment] {
        isTonight ? store.momentsToday : store.moments(onDay: targetDay)
    }

    /// The page has room for another photograph: the main one, or an extra.
    private var hasPhotoRoom: Bool {
        photoID == nil || extraPhotoIDs.count < JournalEntry.extraPhotoLimit
    }

    /// The copy this moment put on the page, if the page still holds it.
    private func copyOnPage(_ moment: Moment) -> String? {
        guard let copy = borrowed[moment.id], copy == photoID || extraPhotoIDs.contains(copy) else { return nil }
        return copy
    }

    /// The photograph as a **copy** under a fresh id — never the moment's own
    /// file, which `updateMoment` would delete the first time the moment's
    /// photo changed, taking the page's with it. The words go in only over an
    /// empty line: what somebody has already typed is theirs.
    ///
    /// The first fills the main photograph; once that is set, the next go to
    /// the extras, up to the page's three. Each tap used to land in the main
    /// slot, so a second moment replaced the first and the extras could only
    /// be filled from the library. A moment already on the page comes back
    /// off, by the rule "swap" keeps: the first extra moves up, so a page is
    /// never extras around a hole. The copy stays in `madeHere`, so an unsaved
    /// close still deletes it.
    private func borrow(_ moment: Moment) {
        if let copy = copyOnPage(moment) {
            if photoID == copy {
                photoID = extraPhotoIDs.isEmpty ? nil : extraPhotoIDs.removeFirst()
            } else {
                extraPhotoIDs.removeAll { $0 == copy }
            }
            borrowed[moment.id] = nil
            return
        }
        if let source = moment.photoID, hasPhotoRoom, let copy = PhotoStore.shared.duplicate(source) {
            made(copy)
            borrowed[moment.id] = copy
            if photoID == nil { photoID = copy } else { extraPhotoIDs.append(copy) }
        }
        // The line is not focused. Focusing it raised the keyboard and scrolled
        // the sheet to the field, which moved the strip out from under the
        // finger: the next tap meant for a moment landed on the main photo
        // and opened the library. The words are on the page to tap into.
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !moment.note.isEmpty {
            line = String(moment.note.prefix(limit))
        }
    }

    private var canSave: Bool { !line.trimmingCharacters(in: .whitespaces).isEmpty }

    private var minutesTaken: Int {
        max(Int(Date().timeIntervalSince(startedAt) / 60), 1)
    }

    /// Where this night lands in the book, as the book stands. It was the
    /// entry's position in the list — "page 12" for a night the book prints
    /// on pages 27 and 28. Nil when the trip prints no book.
    private var pageNumber: Int? { store.bookPage(forDay: targetDay) }

    private var hasExistingPage: Bool {
        store.myEntries.contains { $0.dayNumber == targetDay }
    }

    private func load() {
        startedAt = Date()
        guard let existing = store.myEntries.first(where: { $0.dayNumber == targetDay }) else {
            // Nothing pre-selects itself on a page that already exists —
            // that would be the app arguing with what was written.
            tags = Set(suggested)
            opened = current
            return
        }
        line = existing.line
        tags = Set(existing.tags)
        photoID = existing.photoID
        extraPhotoIDs = existing.extraPhotoIDs
        note = existing.note
        opened = current
    }

    private func save() {
        // "Skip tonight" with photos or tags chosen is leaving with work on
        // the page, and asks the same question Close does.
        guard canSave else { close(); return }
        let entry = JournalEntry(
            dayNumber: targetDay,
            date: store.date(forDay: targetDay),
            city: store.cityStamp(forDay: targetDay),
            line: line.trimmingCharacters(in: .whitespaces),
            tags: Array(tags).sorted(),
            // Derived. It was `photoID != nil || hasPhoto` over a flag that
            // started out `true`, so every new page written without a photo
            // was stored as having one.
            hasPhoto: photoID != nil,
            photoID: photoID,
            author: store.role,
            extraPhotoIDs: extraPhotoIDs,
            note: note
        )
        store.save(entry: entry)
        didSave = true
        // Whatever this sheet made and the page didn't keep. The page's own
        // previous photograph is `save(entry:)`'s to let go.
        for id in madeHere where !entry.allPhotoIDs.contains(id) { PhotoStore.shared.delete(id) }
        // Permission is asked the first time somebody has actually done the
        // thing the prompt would prompt for — not at launch, before there is
        // anything to explain it.
        Task { @MainActor in
            if store.features.nightlyPage, !store.ritual.isAuthorised {
                await store.ritual.requestPermission()
            }
            store.rescheduleRitual()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withGentleAnimation(.easeInOut(duration: 0.3)) { saved = entry }
    }
}

// MARK: - H3 · Saved

/// The page as it will be in the book, held on screen for as long as it is
/// wanted. No score, no streak, no "12 days in a row" — the only number is the
/// page, which is a fact about the book rather than a mark about anybody.
struct SavedPageView: View {
    @EnvironmentObject private var store: TripStore
    let entry: JournalEntry
    /// The book page the night starts on; nil when the trip prints no book.
    let pageNumber: Int?
    let minutes: Int
    var onDone: () -> Void
    /// The postcard sheet, open on this week.
    @State private var makingPostcard: Int?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Mono("\(pageNumber.map { "Page \($0)" } ?? "Day \(entry.dayNumber)") · \(Formatting.spelledCount(minutes, "minute", spellingUpTo: 0))",
                     size: 10, trackingRatio: 0.16, color: Palette.a700)

                Rectangle().fill(Palette.accent)
                    .frame(width: 40, height: 1)
                    .padding(.vertical, Space.s4)

                if let pageNumber, store.features.printedBooks {
                    // The spread itself, drawn by the view that draws the PDF.
                    // This screen said "the page as it will be in the book"
                    // over a layout of its own — a preview by different code,
                    // which is the one kind that can lie.
                    GeometryReader { geometry in
                        BookSpreadView(spread: .day(entryID: entry.id), width: geometry.size.width,
                                       leftPageNumber: pageNumber)
                            .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
                    }
                    .aspectRatio(2, contentMode: .fit)
                    .padding(.horizontal, -14)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pages \(pageNumber) and \(pageNumber + 1): \(entry.line)")
                } else {
                    JournalPhoto(photoID: entry.photoID)

                    Text(entry.line)
                        .font(Typeface.heading(26))
                        .tracking(-0.4)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, Space.s4)
                        .fixedSize(horizontal: false, vertical: true)

                    if !entry.tags.isEmpty {
                        Mono(entry.tags.joined(separator: " · "), size: 9.5, trackingRatio: 0.12)
                            .padding(.top, Space.s4)
                    }
                }

                Rectangle().fill(Palette.accent)
                    .frame(width: 40, height: 1)
                    .padding(.top, Space.s6)
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 0)

            // Offered on the night the book reaches another seven, and only
            // then: derived from the page just saved, so there is nothing to
            // remember having asked and nothing to ask again tomorrow. "Done"
            // stays the button; this is a line under it in the app's quieter
            // voice. It saves; it never says "send".
            if let week = store.postcardOffer(after: entry) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Aside(text: "A week of pages. Keep one as a postcard?", size: 12.5)
                    Spacer(minLength: 8)
                    Button { makingPostcard = week } label: {
                        Mono("Save a postcard", size: 10, color: Palette.a700)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s6)
            }

            OutlineButton(title: "Done", minHeight: 48) { onDone() }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .transition(.opacity)
        .sheet(isPresented: Binding(get: { makingPostcard != nil },
                                    set: { if !$0 { makingPostcard = nil } })) {
            if let makingPostcard {
                PostcardPicker(week: makingPostcard, switchesWeeks: false)
            }
        }
    }
}
