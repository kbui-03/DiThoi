import SwiftUI

/// F2 · One document.
///
/// Behind the app lock, with `DocumentEditorView`. Papers as a whole isn't: it
/// holds the meeting point, "we got separated" and the show-this cards, which
/// exist to be handed to a driver or a hotel desk, and a lock in front of those
/// would hurt the person it is meant to protect. This screen decrypts a passport
/// and puts it on the glass, so this is one of the two that ask.
struct DocumentDetailView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    /// The id, not the document.
    ///
    /// It used to be the value, which is fine for a thing nothing can change
    /// and wrong the moment there is an editor: the row would be saved, the
    /// sheet would close, and this screen would go on drawing the copy it was
    /// pushed with. Read it back out of the store on every pass instead.
    let documentID: UUID
    let index: Int

    @State private var fullScreen = false
    @State private var capturing = false
    @State private var editing = false
    @State private var pages: [String] = []
    /// Said out loud when fewer pages were kept than were photographed.
    @State private var captureProblem: String?

    var body: some View {
        Locked(reason: "Passport and visa scans. The phone gets handed over often enough on a trip like this that the vault shouldn't open with it.") {
            if let document = store.document(documentID) {
                content(document)
            } else {
                // Deleted from the editor that sits on top of this. Nothing to
                // draw and nothing alarming to say about it.
                Screen { Aside(text: "That document is gone.", size: 13) }
            }
        }
    }

    private func content(_ document: TravelDocument) -> some View {
        Screen(context: .syncState) {
            HStack(alignment: .firstTextBaseline) {
                Mono(ownerLine(document), size: 10.5)
                Spacer(minLength: Space.s2)
                if canEdit {
                    Button { editing = true } label: {
                        Mono("edit", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                            .padding(.vertical, 10)
                            .padding(.leading, Space.s3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Display(text: document.title.components(separatedBy: " · ").first ?? document.title, size: 34)
                .padding(.top, 8)
                .padding(.bottom, Space.s3)

            if let first = pages.first {
                Button { fullScreen = true } label: {
                    ScanPage(pageID: first, height: 216)
                        .frame(height: 216)
                        .clipped()
                        .padding(6)
                        .background(Palette.surface)
                        .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)

                HStack {
                    Mono("\(Formatting.spelledCount(pages.count, "page", spellingUpTo: 0)) · encrypted on this phone", size: 9.5, trackingRatio: 0.08)
                    Spacer()
                    if canEdit {
                        Button { capturing = true } label: {
                            Mono("add another", size: 9.5, trackingRatio: 0.08, color: Palette.a700)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 40)
            } else if !canEdit {
                // A closed trip. `closeTrip()` deleted the scans on its way to
                // the shelf, so this is not the same absence as "not scanned
                // yet" and must not borrow its words — and it is emphatically
                // not "this scan isn't on this phone", which says it is
                // somewhere else.
                HatchPanel(height: 216, caption: "emptied when this trip closed")
            } else {
                Button { capturing = true } label: {
                    HatchPanel(height: 216,
                               caption: DocumentScanner.isAvailable
                               ? "no scan yet\n·\ntap to add one"
                               : "no scan yet\n·\ntap to import one")
                }
                .buttonStyle(.plain)

                Aside(text: "Scans are encrypted on this phone and never leave it — not to iCloud, not to whoever's at home.", size: 11.5, color: Palette.n600)
                    .padding(.top, 4)
            }

            if let captureProblem {
                Aside(text: captureProblem, size: 12, color: Palette.a800)
                    .padding(.top, Space.s2)
            }

            SectionRule(top: Space.s4, bottom: Space.s2)

            ForEach(Array(document.fields.enumerated()), id: \.element.id) { fieldIndex, field in
                VStack(spacing: 0) {
                    fieldRow(field)
                        .padding(.vertical, 8)
                    if fieldIndex < document.fields.count - 1 { Rule() }
                }
            }

            if let title = document.footnoteTitle, let body = document.footnoteBody {
                Panel {
                    Mono(title, size: 9.5)
                    Text(body)
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s4)
            }

            // Only when there is something to show full screen. It was
            // unconditional, so a document with no scans offered a 48pt button
            // that opened a black screen at maximum brightness onto a hatched
            // panel — and on a closed trip that panel said "nothing scanned
            // yet" about pages that had been deliberately deleted. A control
            // that leads nowhere is worse than one that isn't there.
            if !pages.isEmpty {
                OutlineButton(title: "Full screen", size: 14) { fullScreen = true }
                    .padding(.top, Space.s4)
            }

            // There was a "Send to <them>" button here. It set a flag, changed
            // its own label to "Sent", and did nothing else — under a line
            // saying "Sending copies both ways means one lost bag isn't a
            // crisis". So the screen told somebody a copy of their passport was
            // on the other phone, and the moment they'd find out otherwise is
            // the moment the feature existed for.
            //
            // Implementing it was never the fix: it would contradict the
            // sentence this same view draws when there is no scan yet — "never
            // leave it, not to iCloud, not to whoever's at home". A second copy
            // is something to make deliberately, outside the app.
            Aside(text: "This is the only copy on this phone. A second one is worth making somewhere else — it won't be made here.", size: 12)
                .padding(.top, Space.s3)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: documentID) { pages = DocumentStore.shared.pageIDs(for: documentID) }
        .fullScreenCover(isPresented: $capturing) {
            DocumentCapture { images in
                // The result is read. It used to be discarded, so a page that
                // failed to encrypt was dropped in silence — scanner dismissed,
                // success haptic, one page fewer than were photographed.
                let result = DocumentStore.shared.add(images, to: documentID)
                pages = DocumentStore.shared.pageIDs(for: documentID)
                capturing = false
                if result.isComplete {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    captureProblem = nil
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    captureProblem = shortfall(result)
                }
            } onCancel: {
                capturing = false
            }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            ScanViewer(title: document.title, pages: pages) { fullScreen = false }
        }
        .sheet(isPresented: $editing) {
            DocumentEditorView(editing: store.document(documentID))
        }
    }

    /// Label and value, side by side until they can't be.
    ///
    /// "Nationality" beside "NX4419 882" is comfortably wider than a phone at an
    /// accessibility size, and the failure is the one the country card already
    /// had: a passport number broken mid-word on the screen where being misread
    /// costs the most. Same `AnyLayout` switch as `CallTileRow`, so both grounds
    /// draw through one decision.
    @ViewBuilder
    private func fieldRow(_ field: DocumentField) -> some View {
        let stacks = typeSize.isAccessibilitySize
        let layout = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Mono(field.label, size: 10, trackingRatio: 0.12)
            if !stacks { Spacer(minLength: Space.s2) }
            if field.value.isEmpty {
                // Cleared by `closeTrip()`. The label is still the question; a
                // blank where the answer was is the honest picture of that, and
                // it is why the strip keeps the labels at all.
                Mono("emptied", size: 10, trackingRatio: 0.08, color: Palette.n600)
            } else {
                Text(field.value)
                    .font(Typeface.mono(13))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: stacks ? .infinity : nil,
                           alignment: stacks ? .leading : .trailing)
            }
        }
    }

    /// Whether this screen may offer to change anything.
    ///
    /// Not `isReadOnly` alone. That flag is injected by the shelf's reader and
    /// by home mode, and a trip closed *in place* sets neither — `closeTrip()`
    /// does not send the app anywhere, so a trip shelved a minute ago is still
    /// on screen. Which meant the emptied document went on offering "tap to
    /// import one" and an `edit`, on a trip whose papers had just been deleted
    /// on purpose: a control that would write into a closed trip, next to three
    /// fields reading "emptied".
    ///
    /// `isLive` is the state; `isReadOnly` is the courtesy. Both have to say
    /// yes.
    private var canEdit: Bool { !isReadOnly && store.isLive }

    private func ownerLine(_ document: TravelDocument) -> String {
        let who = document.owner.map { store.name(for: $0) } ?? "Both of you"
        return "\(who) · document \(index + 1) of \(total)"
    }

    /// Says what was lost, and why, when a batch didn't all land.
    private func shortfall(_ result: DocumentStore.AddResult) -> String {
        let missed = result.attempted - result.written
        let pages = "\(missed) of the \(Formatting.spelledCount(result.attempted, "page", spellingUpTo: 0))"
        guard let failure = result.failure else {
            return "\(pages) couldn't be saved. Nothing was written for \(missed == 1 ? "it" : "them")."
        }
        switch failure {
        case .keyUnavailable, .keyNotStored:
            return "\(pages) couldn't be encrypted, so \(missed == 1 ? "it wasn't" : "they weren't") kept. Unlock the phone properly and photograph \(missed == 1 ? "it" : "them") again."
        case .undecryptable:
            return "\(pages) couldn't be encrypted, so \(missed == 1 ? "it wasn't" : "they weren't") kept."
        }
    }

    /// Never smaller than the document being drawn.
    ///
    /// The count came straight off `store.documents`, which is right for every
    /// document that is in there and reads "document 1 of 0" for one that isn't
    /// — which is what a `-screen document` route handing over its own passport
    /// produced. A total that can come out lower than the index is a derived
    /// number that doesn't handle its own degenerate case.
    private var total: Int { max(store.documents.count, index + 1) }
}

/// Brightness goes up, chrome goes away — the phone is being held out to
/// someone else.
struct ScanViewer: View {
    let title: String
    var pages: [String] = []
    var onClose: () -> Void

    @State private var previousBrightness: CGFloat = UIScreen.main.brightness

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Mono("brightness max", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                Spacer()
                Button(action: onClose) {
                    Mono("close", size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, Space.gutter)

            if pages.isEmpty {
                HatchPanel(height: 460, caption: "\(title)\n·\nnothing scanned yet")
                    .padding(.horizontal, Space.gutter)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: Space.s3) {
                        ForEach(pages, id: \.self) { page in
                            ScanPage(pageID: page)
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.s6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.n100.ignoresSafeArea())
        // Its own cover rather than inheriting `Locked`'s: a `fullScreenCover`
        // is presented above the view that spawned it, so an overlay on the
        // locked content does not sit over this. And this is the screen that
        // actually has a passport on it, at maximum brightness.
        .privacyCovered()
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
        }
        .onDisappear { UIScreen.main.brightness = previousBrightness }
    }
}
