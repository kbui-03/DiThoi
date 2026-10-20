import SwiftUI

/// J2 / J6 / J9 · writing one.
///
/// A draft is the observer's alone: it does not travel, it does not appear on the
/// traveller's phone in
/// any form, and it can be edited forever. Sealing is the one-way door — after
/// it, the condition is binding and there is no screen anywhere that un-seals a
/// letter.
struct ComposeLetterView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    let letterID: UUID

    @State private var title = ""
    @State private var body_ = ""
    @State private var signature = "— me, obviously"
    @State private var condition: LetterCondition = .nextOnline
    @State private var pickingCondition = false
    @State private var confirmingSeal = false
    @State private var sealed = false
    @State private var confirmingDiscard = false
    /// Set by Discard, so leaving doesn't save what was just thrown away.
    @State private var discarded = false
    @FocusState private var bodyFocused: Bool

    private var letter: Letter? { store.letters.first { $0.id == letterID } }

    var body: some View {
        Group {
            if sealed {
                SealedConfirmationView(letterID: letterID) { dismiss() }
            } else {
                composer
            }
        }
        .background(Palette.n100)
        .onAppear(perform: load)
        // A letter keeps itself. A swipe down used to keep the empty draft
        // "Write a letter" made and drop everything typed into it; now leaving
        // any way but Discard saves the draft, and a draft with nothing in it
        // goes rather than piling up as numbered blanks.
        .onDisappear {
            guard !sealed, !discarded else { return }
            persist()
            store.discardDraftIfEmpty(letterID)
        }
        .sheet(isPresented: $pickingCondition) {
            ConditionPickerView(number: letter?.number ?? store.nextLetterNumber,
                                selected: condition) { chosen in
                condition = chosen
                store.updateDraft(letterID, condition: chosen)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Letter No. \(numberLabel)",
                        leading: "Discard", trailing: "Save draft",
                        onLeading: { askToDiscard() }, onTrailing: { saveAndClose() })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Mono("Letter No. \(numberLabel)", size: 10.5)
                        Spacer()
                        Mono("Unsealed", size: 10.5)
                    }

                    // J9 · a letter written after they have gone has to
                    // travel, and it can only travel when the other phone
                    // finds signal. That limits which conditions are possible
                    // at all, so it is said here rather than discovered when
                    // nothing happens.
                    if store.phase == .during {
                        Panel(border: Palette.a300, fill: Palette.a100) {
                            Mono("This one has to travel", size: 9.5, color: Palette.a700)
                            Text(travelNote)
                                .font(Typeface.body(12.5))
                                .foregroundStyle(Palette.a800)
                                .lineSpacing(4)
                                .padding(.top, 5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Space.s3)
                    } else if let context = whatThatDayIsLike {
                        // J6 · most letters get written across a handful of
                        // nights before departure, and the hard part to hold in
                        // your head is what day 42 will feel like.
                        Panel {
                            Mono("What that day looks like", size: 9.5)
                            Text(context)
                                .font(Typeface.body(12.5))
                                .foregroundStyle(Palette.n700)
                                .lineSpacing(4)
                                .padding(.top, 5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Space.s3)
                    }

                    TextField("", text: $title, prompt: Text("A title they'll see before they open it")
                        .font(Typeface.heading(26).italic().resolved(for: typeSize))
                        .foregroundStyle(Palette.n400))
                        .font(Typeface.heading(26).italic())
                        .foregroundStyle(Palette.text)
                        .textInputAutocapitalization(.sentences)
                        .padding(.top, Space.s4)
                        .padding(.bottom, 8)

                    Rectangle().fill(Palette.accent).frame(height: 1)

                    Mono("a title they'll see before they open it", size: 9.5, trackingRatio: 0.1)
                        .padding(.top, Space.s1)

                    TextField("", text: $body_, prompt: Text("Write it.")
                        .font(Typeface.body(13.5).resolved(for: typeSize))
                        .foregroundStyle(Palette.n400), axis: .vertical)
                        .font(Typeface.body(13.5))
                        .lineSpacing(6)
                        .foregroundStyle(Palette.text)
                        .focused($bodyFocused)
                        .textInputAutocapitalization(.sentences)
                        .frame(minHeight: 200, alignment: .top)
                        .padding(.top, Space.s4)

                    SectionRule(top: Space.s4)

                    Button { pickingCondition = true } label: {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Mono("Opens when", size: 9.5)
                                Text(condition.summary)
                                    .font(Typeface.heading(18, .semibold))
                                    .foregroundStyle(Palette.text)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Tag(text: "change", active: true)
                        }
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Mono("Signed", size: 9.5)
                            TextField("", text: $signature)
                                .font(Typeface.heading(18, .semibold).italic())
                                .foregroundStyle(Palette.text)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.top, Space.s3)

                    Mono(countLine, size: 9.5, trackingRatio: 0.12)
                        .padding(.top, Space.s4)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)

            Rule()

            HStack(spacing: 10) {
                Mono("Sealing is final.\nYou won't be able to edit it.", size: 9, trackingRatio: 0.08)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                OutlineButton(title: "Seal it", minHeight: 48, size: 15,
                              fillsWidth: false, horizontalPadding: 22) {
                    confirmingSeal = true
                }
                .disabled(!canSeal)
            }
            .padding(.horizontal, 30)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.gutter)
        }
        .confirmationDialog("Throw this letter away?", isPresented: $confirmingDiscard,
                            titleVisibility: .visible) {
            Button("Throw it away", role: .destructive) { discard() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Letter No. \(numberLabel) and everything in it go. \"Save draft\" keeps it for later.")
        }
        .confirmationDialog("Seal letter No. \(numberLabel)?",
                            isPresented: $confirmingSeal, titleVisibility: .visible) {
            Button("Seal it") { seal() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("It goes out of your hands. \(condition.summary.replacingOccurrences(of: "Opens", with: "It opens")) — whether or not you're awake, and nothing comes back to say it was read.")
        }
    }

    // MARK: - Copy

    private var numberLabel: String {
        String(format: "%02d", letter?.number ?? store.nextLetterNumber)
    }

    private var canSeal: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !body_.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var countLine: String {
        let words = body_.split { $0.isWhitespace || $0.isNewline }.count
        return "\(words) word\(words == 1 ? "" : "s")"
    }

    private var travelNote: String {
        // Their phone's wifi is beside the point when the letter can't leave
        // this one. `lastSyncedAt` is this phone's round, and it is nil then.
        if store.lettersAreStuck, let why = store.letterPostProblem {
            return "\(why) A letter only fires once it reaches their phone, so a place they have already passed never will."
        }
        let synced = store.sync.lastSyncedAt.map { "Their phone last reached wifi \(age(of: $0))." }
            ?? "Their phone hasn't reached wifi yet."
        return "\(synced) A new letter only lands the next time they're online, so a place they have already passed will never fire."
    }

    private func age(of date: Date) -> String {
        let hours = Int(Date().timeIntervalSince(date) / 3600)
        if hours < 1 { return "less than an hour ago" }
        if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
        return "\(hours / 24) day\(hours / 24 == 1 ? "" : "s") ago"
    }

    /// Only worth saying when the condition has a day behind it — otherwise it
    /// would be a guess dressed as a fact.
    private var whatThatDayIsLike: String? {
        let day: Int
        switch condition {
        case .day(let value): day = value
        case .place(let name):
            // One join, on the store, rather than a substring match written
            // out again here: an unanchored one lets "Ha Long" claim
            // "Ha Long Bay".
            guard let segment = store.segment(namingCity: name) else { return nil }
            day = segment.startDay
        default: return nil
        }
        guard day > 0, day <= store.dayCount else { return nil }
        let weeks = max((day - 1) / 7, 0)
        let country = store.legs.first { $0.contains(day: day) }?.country ?? "somewhere"
        let position = store.legs.firstIndex { $0.contains(day: day) }.map { $0 + 1 } ?? 1
        let ordinal = ["first", "second", "third", "fourth"][min(position - 1, 3)]
        return "Day \(day). \(weeks) week\(weeks == 1 ? "" : "s") in, \(ordinal) country — \(country), by the itinerary as it stands tonight."
    }

    // MARK: - Editing

    private func load() {
        guard let letter else { return }
        title = letter.title
        body_ = letter.paragraphs.joined(separator: "\n\n")
        signature = letter.signature
        condition = letter.condition
    }

    private var paragraphs: [String] {
        body_.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func persist() {
        store.updateDraft(letterID, title: title, paragraphs: paragraphs,
                          condition: condition, signature: signature)
    }

    private func saveAndClose() {
        persist()
        dismiss()
    }

    private var hasWords: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !paragraphs.isEmpty
    }

    private func askToDiscard() {
        if hasWords { confirmingDiscard = true } else { discard() }
    }

    private func discard() {
        discarded = true
        store.discardDraft(letterID)
        dismiss()
    }

    private func seal() {
        persist()
        store.seal(letterID)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withGentleAnimation(.easeInOut(duration: 0.3)) { sealed = true }
        // Sealing is local and already true, so the animation runs now and the
        // post resolves behind it. `SealedConfirmationView` reads the outcome
        // off the store's `@Published` state rather than being handed it, so the
        // sentence corrects itself when the post lands or fails — which is what
        // the old fire-and-forget `Task` had no way to do.
        Task { await store.postLetters() }
    }
}

// MARK: - J3 · one picker, three kinds of condition

/// A place, a day, or a stamp — and, once they have left, "the next time
/// they're online", which is the only one guaranteed to fire.
///
/// Conditions that have already happened are shown and disabled rather than
/// hidden. The observer should be able to see that Hà Giang is no longer available and
/// why, instead of wondering where it went.
struct ConditionPickerView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    let number: Int
    @State var selected: LetterCondition
    var onChoose: (LetterCondition) -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case place, day, stamp
        var id: String { rawValue }
        var label: String {
            switch self {
            case .place: "A place"
            case .day: "A day"
            case .stamp: "A stamp"
            }
        }
    }

    @State private var kind: Kind = .day

    var body: some View {
        // Built once for the whole screen.
        //
        // `letterMoment` walks every waypoint and every stop and allocates five
        // sets. It was read once per chip — there is one per city and one per
        // stamp code — plus once more for the button below, so opening the
        // picker on an eleven-stop trip rebuilt it two dozen times.
        let moment = store.letterMoment

        return VStack(spacing: 0) {
            SheetHeader(title: "Opens when", trailing: "Back") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("Letter No. \(String(format: "%02d", number))", size: 10.5)

                    Display(text: "When should it\nopen itself?", size: 34)
                        .padding(.top, 8)
                        .padding(.bottom, Space.s3)

                    HStack(spacing: 6) {
                        ForEach(Kind.allCases) { option in
                            SegmentTile(text: option.label, selected: kind == option, serif: false) {
                                kind = option
                            }
                        }
                    }
                    .padding(.bottom, Space.s3)

                    Panel(border: Palette.accent) {
                        Mono("It will open", size: 9.5, color: Palette.a700)
                        Text(selected.summary)
                            .font(Typeface.heading(25))
                            .foregroundStyle(Palette.text)
                            .padding(.top, 6)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = detail(for: selected) {
                            Aside(text: detail, size: 12)
                                .padding(.top, 5)
                        }
                    }

                    if store.phase == .during {
                        Button {
                            selected = .nextOnline
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("The next time they're online")
                                        .font(Typeface.heading(16, .semibold))
                                        .foregroundStyle(Palette.text)
                                    Aside(text: "the only one that can't miss, now they're out there", size: 11.5)
                                }
                                Spacer()
                                Tag(text: isSelected(.nextOnline) ? "chosen" : "pick",
                                    active: isSelected(.nextOnline))
                            }
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Space.s3)
                    }

                    SectionRule()

                    switch kind {
                    case .day: dayOptions(moment)
                    case .place: placeOptions(moment)
                    case .stamp: stampOptions(moment)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            OutlineButton(title: "Use this condition", minHeight: 48) {
                onChoose(selected)
                dismiss()
            }
            .disabled(!selected.canStillFire(moment))
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .onAppear {
            switch selected {
            case .place: kind = .place
            case .stamp, .finalStamp: kind = .stamp
            default: kind = .day
            }
        }
    }

    // MARK: Options

    private func dayOptions(_ moment: LetterMoment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Day of the trip", size: 10).padding(.bottom, 9)
            FlowRow(spacing: Space.s2) {
                ForEach(dayCandidates, id: \.self) { day in
                    chip(label: dayLabel(day), condition: .day(day), in: moment)
                }
            }
        }
    }

    private var dayCandidates: [Int] {
        var days = [store.dayCount / 2, store.dayCount]
        days += stride(from: 7, through: store.dayCount, by: 7).map { $0 }
        // Whatever is currently chosen is always offered, so the panel above
        // and the chips below can never disagree about what's selected.
        if case .day(let chosen) = selected { days.append(chosen) }
        return Array(Set(days.filter { $0 >= 1 })).sorted()
    }

    private func dayLabel(_ day: Int) -> String {
        if day == store.dayCount { return "\(day) · last day" }
        if day == store.dayCount / 2 { return "\(day) · halfway" }
        return "\(day)"
    }

    private func placeOptions(_ moment: LetterMoment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("One of their cities", size: 10).padding(.bottom, 9)
            FlowRow(spacing: Space.s2) {
                ForEach(store.orderedStamps) { stamp in
                    chip(label: stamp.city, condition: .place(stamp.city), in: moment)
                }
            }
            Aside(text: "A place fires on the stamp, which only lands when the phone agrees they're standing in it.",
                  size: 11.5)
                .padding(.top, Space.s3)
        }
    }

    private func stampOptions(_ moment: LetterMoment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("A stamp", size: 10).padding(.bottom, 9)
            FlowRow(spacing: Space.s2) {
                chip(label: "the last one", condition: .finalStamp, in: moment)
                ForEach(store.orderedStamps) { stamp in
                    chip(label: stamp.code, condition: .stamp(stamp.code), in: moment)
                }
            }
        }
    }

    private func chip(label: String, condition: LetterCondition, in moment: LetterMoment) -> some View {
        let dead = condition.deadReason(moment)
        return Button {
            guard dead == nil else { return }
            selected = condition
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Mono(dead == nil ? label : "\(label) · \(dead!)",
                 size: 10.5, trackingRatio: 0.06,
                 color: dead != nil ? Palette.n500 : (isSelected(condition) ? Palette.a800 : Palette.n700))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected(condition) && dead == nil ? Palette.a100 : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(dead != nil ? Palette.n400 : (isSelected(condition) ? Palette.accent : Palette.divider),
                                      style: StrokeStyle(lineWidth: 1, dash: dead != nil ? [3, 3] : []))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(dead != nil)
        .accessibilityLabel(dead == nil ? label : "\(label), unavailable, \(dead!)")
    }

    private func isSelected(_ condition: LetterCondition) -> Bool { selected == condition }

    private func detail(for condition: LetterCondition) -> String? {
        switch condition {
        case .day(let day):
            guard day >= 1, day <= store.dayCount else { return nil }
            let where_ = store.city(forDay: day)
            return "\(store.date(forDay: day).dayMonth) by the itinerary — around \(where_)."
        case .place(let name):
            guard let segment = store.segment(namingCity: name)
            else { return "Not on the itinerary as it stands. It'll fire if they go anyway." }
            return "About day \(segment.startDay), \(store.date(forDay: segment.startDay).dayMonth) — if they keep to the plan."
        case .stamp(let code):
            return store.orderedStamps.first { $0.code == code }.map { "The \($0.city) stamp." }
        case .finalStamp:
            return "Only once every stamp is earned. If they skip a city, this one never opens."
        case .nextOnline:
            return "The next time their phone finds signal, wherever they are."
        case .hidden:
            return nil
        }
    }
}

// MARK: - J4 · sealed

/// The confirmation, and the honest paragraph underneath it.
struct SealedConfirmationView: View {
    @EnvironmentObject private var store: TripStore
    let letterID: UUID
    var onDone: () -> Void

    private var letter: Letter? { store.letters.first { $0.id == letterID } }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Mono(sealedLine, size: 10, trackingRatio: 0.16, color: Palette.a700)

                Text(letter?.numberLabel ?? "—")
                    .font(Typeface.heading(44))
                    .monospacedDigit()
                    .foregroundStyle(Palette.a700)
                    .frame(width: 132, height: 132)
                    .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 1))
                    .padding(.vertical, Space.s6)

                // "It's out of your hands" is the whole feeling this screen is
                // for, and it is a claim about where the letter now is. With no
                // postal service it is in exactly one pair of hands, and the
                // headline was the largest false sentence on the screen.
                Display(text: store.lettersAreStuck
                        ? "Sealed, and\nwaiting to go"
                        : "It's out of\nyour hands", size: 32)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Text(promise)
                    .font(Typeface.body(13.5).italic())
                    .foregroundStyle(Palette.n700)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 270)
                    .padding(.top, Space.s3)
                    .padding(.bottom, Space.s6)

                Panel {
                    Mono("What you'll never know", size: 9.5)
                    Text("Whether it was opened that day or two weeks later. Whether it was read twice. Whether it landed at all. The app has no way to tell you.")
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Mono(tally, size: 9.5, trackingRatio: 0.12)
                    .padding(.top, Space.s4)
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 0)

            OutlineButton(title: "Done", minHeight: 48) { onDone() }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .transition(.opacity)
    }

    private var sealedLine: String {
        guard let letter, let at = letter.sealedAt else { return "Sealed" }
        return "Letter No. \(letter.numberLabel) · sealed \(at.text("HH:mm"))"
    }

    private var promise: String {
        guard let letter else { return "" }
        let when: String
        switch letter.condition {
        case .day(let day): when = "On day \(day)"
        case .place(let name): when = "When they reach \(name)"
        case .stamp(let code): when = "When the \(code) stamp lands"
        case .finalStamp: when = "When the last stamp lands"
        case .nextOnline: when = "The next time they're online"
        case .hidden: when = "When its moment comes"
        }
        // A promise about the *other* phone, which needs this one to have
        // posted first. When nothing is leaving, the sentence has to say so
        // rather than assert a delivery.
        guard !store.lettersAreStuck else {
            let why = (store.letterPostProblem ?? "").prefix(1).lowercased()
                + (store.letterPostProblem ?? "").dropFirst()
            return "\(when) their phone would open it — but \(why)"
        }
        return "\(when) their phone will open it, whether or not it has signal, whether or not you're awake."
    }

    private var tally: String {
        store.lettersAreStuck
            ? "\(store.deliveredCount) due · \(store.stillSealedCount) not yet"
            : "\(store.deliveredCount) delivered · \(store.stillSealedCount) sealed"
    }
}
