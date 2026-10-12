import SwiftUI
import CoreLocation

/// Something worth keeping that the itinerary never planned for.
///
/// Built on `TonightEntryView`'s shape — one photo, one line, one button —
/// because it is the same act at a different hour, and a second composer that
/// behaved differently would be a second thing to learn. What it does not carry
/// is tags, a prompt, or a page number: a moment is not a page, and it is not
/// part of the ritual that asks for one every night.
///
/// The position is whatever the phone has when the sheet opens. There is no map
/// to tap and no field to type a place into: a moment records standing
/// somewhere, and the phone's own fix is the only source for that. With no fix
/// the moment is still kept — it says so, and doesn't draw on the map.
struct MomentComposerView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    /// Set when an existing moment is being changed rather than made.
    var editing: Moment?
    /// Handed the moment that was just deleted, so the screen underneath can
    /// offer it back. The composer is gone by then; the offer can't live here.
    var onDelete: ((Moment) -> Void)?
    /// Opened from the stamp screen: the moment is filed under the stamp's
    /// city, which knows better than the itinerary where they are standing.
    var arrivedAt: Stamp?

    @State private var note = ""
    @State private var photoID: String?
    @State private var pickingPhoto = false
    @State private var loaded = false
    /// A photograph taken here that the library refused. The app's copy is
    /// kept either way; this is only whether to say the other half didn't.
    @State private var libraryRefused = false
    /// "Just keep the spot", waiting a moment for a fix before it gives up.
    @State private var keepingSpot = false
    @FocusState private var noteFocused: Bool

    private let limit = 120

    private var isNew: Bool { editing == nil }

    private var canKeep: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "Here, now" : "That moment",
                        trailing: "Close") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Mono(dayLabel, size: 10.5)
                        Spacer()
                        Mono("Private", size: 10.5, color: Palette.a700)
                    }

                    Display(text: heading, size: 32)
                        .padding(.top, 8)
                        .padding(.bottom, Space.s2)

                    // Never blank. A missing sentence where a status line
                    // belongs reads as a bug, and this one is the only thing
                    // that says whether the map will show it.
                    Aside(text: positionLine, size: 12.5)
                        .padding(.bottom, Space.s3)

                    Button {
                        pickingPhoto = true
                    } label: {
                        JournalPhoto(photoID: photoID,
                                     caption: photoID == nil
                                     ? "one tap · a photo\n·\nor keep it without one" : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photoID == nil
                                        ? "No photo. Tap to choose one."
                                        : "Photo attached. Tap to replace it.")

                    if photoID != nil {
                        HStack(alignment: .firstTextBaseline) {
                            Aside(text: libraryRefused
                                  ? "Kept in the app. Not saved to Photos — that's off in Settings."
                                  : "Kept in the app, not a link to your camera roll.", size: 11)
                            Spacer(minLength: 8)
                            Button {
                                remove(photoID)
                                photoID = nil
                            } label: {
                                Mono("swap", size: 9.5, trackingRatio: 0.1, color: Palette.a700)
                                    .frame(minHeight: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, Space.s1)
                    }

                    SectionRule(top: Space.s4)

                    Mono("What happened", size: 10)
                        .padding(.bottom, 8)

                    TextField("", text: $note, prompt: Text("the noodle stall with no name")
                        .font(Typeface.heading(23).resolved(for: typeSize))
                        .foregroundStyle(Palette.n500), axis: .vertical)
                        .font(Typeface.heading(23))
                        .tracking(-0.23)
                        .lineSpacing(6)
                        .foregroundStyle(Palette.text)
                        .focused($noteFocused)
                        .textInputAutocapitalization(.sentences)
                        .frame(minHeight: 58, alignment: .top)
                        .onChange(of: note) { _, newValue in
                            if newValue.count > limit { note = String(newValue.prefix(limit)) }
                            if newValue.contains("\n") {
                                note = newValue.replacingOccurrences(of: "\n", with: " ")
                            }
                        }

                    Rectangle().fill(Palette.accent).frame(height: 1)

                    HStack(alignment: .firstTextBaseline) {
                        Mono("it doesn't have to be a sentence", size: 9.5, trackingRatio: 0.08)
                        Spacer(minLength: 8)
                        Mono("\(note.count) of \(limit)", size: 9.5, trackingRatio: 0.08)
                    }
                    .padding(.top, Space.s1)

                    Aside(text: "Moments stay on this phone and print in your book, beside the days they happened. They earn no stamp and open no letter.",
                          size: 11.5, color: Palette.n600)
                        .padding(.top, Space.s4)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 10) {
                if !isNew {
                    Button(role: .destructive) {
                        if let editing {
                            store.deleteMoment(editing.id)
                            onDelete?(editing)
                        }
                        dismiss()
                    } label: {
                        Mono("delete", size: 10, trackingRatio: 0.08, color: Palette.n600)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // The one-tap version, for a bus with no hand free: the time
                // and the place, kept now, written up later. Only on a new
                // moment with nothing in it yet — once there is a word or a
                // photograph, "Keep it" is the button.
                if isNew && !canKeep {
                    Button { keepSpot() } label: {
                        Mono(keepingSpot ? "finding you…" : "just keep the spot",
                             size: 10, trackingRatio: 0.08, color: Palette.a700)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(keepingSpot)
                }
                Spacer(minLength: 8)
                OutlineButton(title: "Keep it", minHeight: 48, size: 15,
                              fillsWidth: false, horizontalPadding: 22) {
                    keep()
                }
                .disabled(!canKeep)
                .opacity(canKeep ? 1 : 0.45)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.s3)
            .background(Palette.bg)
        }
        .background(Palette.bg)
        // `.task(id:)` rather than `onAppear`: `@State` survives the view being
        // rebuilt with a different moment, and a one-shot load would show one
        // moment's words under another one's heading.
        .task(id: editing?.id) { load() }
        .photoIntake(isPresented: $pickingPhoto,
                     onSavedToLibrary: { libraryRefused = !$0 }) { square in
            let previous = photoID
            if let saved = PhotoStore.shared.save(square) {
                photoID = saved
                remove(previous)
            }
        }
    }

    // MARK: - Where it will be filed

    /// Computed from the same facts `addMoment` stamps with, so the heading is
    /// a preview of the record rather than a guess beside it.
    private var dayLabel: String {
        if let editing {
            return editing.isBeforeDeparture ? "Before we left" : "Day \(editing.dayNumber)"
        }
        return store.isBeforeDeparture ? "Before we left" : "Day \(store.dayNumber)"
    }

    /// The city, or — before departure, or on a trip with nowhere in it — a
    /// word that is true rather than an em-dash at 32pt, or the first stop's
    /// name over a gate at the airport.
    private var heading: String {
        if let editing { return editing.place ?? (editing.isBeforeDeparture ? "On the way" : "Here") }
        if let arrivedAt, !store.isBeforeDeparture { return arrivedAt.city }
        if store.isBeforeDeparture { return "On the way" }
        return store.cityNow.isEmpty ? "Here" : store.cityNow
    }

    // MARK: - What the phone knows

    private var fix: CLLocationCoordinate2D? {
        store.location.current?.coordinate
    }

    private var positionLine: String {
        if let editing {
            return editing.hasLocation
                ? "Kept where you were standing."
                : "Kept without a position, so it isn't on the map."
        }
        if fix != nil { return "The phone has your position. This one lands on the trail." }
        if store.location.isDenied {
            return "No position — location is off, so this one won't be on the map. It's kept either way."
        }
        return "Looking for your position. It's kept either way, with or without one."
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            note = editing.note
            photoID = editing.photoID
        } else {
            // Asked for here, at the moment it is needed — never at launch.
            store.location.requestOnce()
        }
    }

    private func keep() {
        if var moment = editing {
            moment.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            moment.photoID = photoID
            store.updateMoment(moment)
        } else {
            store.addMoment(note: note, photoID: photoID,
                            latitude: fix?.latitude ?? 0, longitude: fix?.longitude ?? 0,
                            city: arrivedAt?.city)
        }
        dismiss()
    }

    /// Keeps the spot with nothing written. Waits up to three seconds for a
    /// fix when one is on the way — the position is most of what a spot is —
    /// and keeps it without one after that, because the time is still worth
    /// having. With location off there is nothing to wait for.
    private func keepSpot() {
        keepingSpot = true
        Task { @MainActor in
            var waited = 0
            while fix == nil, !store.location.isDenied, waited < 12 {
                try? await Task.sleep(for: .milliseconds(250))
                waited += 1
            }
            store.addMoment(note: "", latitude: fix?.latitude ?? 0, longitude: fix?.longitude ?? 0,
                            city: arrivedAt?.city)
            dismiss()
        }
    }

    /// Only ever removes a file this composer put there — never the one the
    /// saved moment is still pointing at.
    private func remove(_ id: String?) {
        guard let id, id != editing?.photoID else { return }
        PhotoStore.shared.delete(id)
    }
}
