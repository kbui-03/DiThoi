import SwiftUI

/// I3 · the print file. Built on the phone, checked before it goes anywhere.
///
/// There is no ordering here any more. "Send it to the printer" set a flag on
/// this phone, said "Both books are ordered", and reached no printer — and it
/// could never have ordered both, because the other book's pages are only on
/// the other phone. What is left is the half that is real: a file a printer
/// will take, and the share sheet to send it wherever you like.
struct PrintFileView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var exported: [URL] = []
    @State private var sharing = false
    @State private var building = false
    /// How far the render has got, 0…1. Real: the writer yields between
    /// spreads, so this draws while it runs and a second tap can stop it.
    @State private var built: Double = 0
    @State private var job: Task<Void, Never>?

    var body: some View {
        // Both built once per pass and handed down.
        //
        // `readiness` is the one that mattered: it rebuilds the whole book plan
        // *and* opens the file header of every photograph in it —
        // `CGImageSourceCreateWithURL`, once per page, on the main thread. It
        // was a computed property read five times in this body, so laying the
        // screen out re-read every photo on disk five times over.
        let plan = store.bookPlan
        let readiness = store.printReadiness { PhotoStore.shared.pixelShortEdge($0) }

        return VStack(spacing: 0) {
            SheetHeader(title: "The print file", trailing: "Close") {
                job?.cancel()
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono(fileCountLabel(plan), size: 10.5)

                    Display(text: "The print file", size: 36)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    Aside(text: readiness.sizeLine, size: 12.5)
                        .padding(.bottom, Space.s3)

                    Rule()

                    specRow("Trim", plan.spec.trimLabel)
                    specRow("Bleed", plan.spec.bleedLabel)
                    specRow("Pages", pagesLabel(plan))
                    specRow("Format", plan.spec.format)
                    specRow("Images", "\(plan.spec.dpi) dpi when saved")
                    specRow("Type", "real text, fonts embedded")
                    specRow("Cover", coverLabel(plan), last: true)

                    if let cover = CoverSpec(pages: plan.pagesPerVolume.first ?? plan.pageCount) {
                        // Drawn by the view that draws the cover PDF.
                        Mono("The cover, flat · back, spine, front", size: 10)
                            .padding(.top, Space.s4)
                            .padding(.bottom, 8)
                        GeometryReader { geometry in
                            BookCoverView(spec: cover, width: geometry.size.width,
                                          volume: plan.volumes > 1 ? (1, plan.volumes) : nil)
                        }
                        .aspectRatio(CGFloat(cover.totalWidth / cover.totalHeight), contentMode: .fit)
                        .accessibilityLabel("The cover: \(store.displayName) on the front, the trail on the back")
                        Aside(text: "Hardcover, case wrap. The outer edge folds round the boards, so the colour runs right to it.",
                              size: 11.5, color: Palette.n600)
                            .padding(.top, Space.s2)
                    }

                    if let warning = readiness.softSummary {
                        Panel(border: Palette.a300, fill: Palette.a100) {
                            Mono(softTitle(readiness), size: 9.5, color: Palette.a700)
                            Text(warning)
                                .font(Typeface.body(12.5))
                                .foregroundStyle(Palette.a800)
                                .lineSpacing(4)
                                .padding(.top, 5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Space.s3)
                    } else if plan.pageCount > 0 {
                        Panel {
                            Mono("Every photo is big enough", size: 9.5, color: Palette.a700)
                            Text("Nothing in the book will print soft.")
                                .font(Typeface.body(12.5))
                                .foregroundStyle(Palette.n700)
                                .padding(.top, 5)
                        }
                        .padding(.top, Space.s3)
                    }

                    if readiness.missingPhotos > 0 {
                        Aside(text: "\(Formatting.spelledCount(readiness.missingPhotos, "night")) with no photo. Each gets a page set in type instead.",
                              size: 12)
                            .padding(.top, Space.s3)
                    }

                    if let unfinished = readiness.unfinishedLine {
                        Aside(text: unfinished, size: 12)
                            .padding(.top, Space.s3)
                    }

                    if plan.notesSpreadCount > 0 {
                        Aside(text: "Printers bind \(plan.spec.minimumPages) pages or more, so the book ends on ruled notes pages until it reaches that.",
                              size: 12)
                            .padding(.top, Space.s3)
                    }

                    SectionRule()

                    Aside(text: "An interior and a cover\(plan.volumes > 1 ? " for each volume" : ""), sized for Lulu's 8.5 × 8.5 hardcover photo book. They go to the phone's own share sheet — save them, mail them to yourself, or upload them at Lulu. Nothing passes through anything of ours, and the app doesn't order prints.",
                          size: 12)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            OutlineButton(title: building
                          ? "Building \(Int(built * 100))% · tap to stop"
                          : "Save the print files",
                          minHeight: 48) {
                build(plan)
            }
            .disabled(plan.spreads.isEmpty)
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .sheet(isPresented: $sharing) {
            ShareSheet(items: exported) {
                // The book has gone wherever it was going. What is left on
                // this phone is a second copy of the whole journal, so the
                // file goes, and the screen forgets it rather than offering a
                // share of nothing.
                Storage.clearExports()
                exported = []
            }
        }
        .onDisappear { job?.cancel() }
    }

    /// "N · M days" was true while every spread was a day. Moments take spreads
    /// too, so the second half names them rather than folding them into a day
    /// count that would then be wrong.
    private func pagesLabel(_ plan: BookPlan) -> String {
        if plan.volumes > 1 {
            return plan.pagesPerVolume.map(String.init).joined(separator: " + ") + " · \(plan.volumes) volumes"
        }
        let nights = Formatting.spelledCount(plan.dayCountInBook, "night", spellingUpTo: 0)
        guard plan.momentSpreadCount > 0 else { return "\(plan.pageCount) · \(nights)" }
        let moments = Formatting.spelledCount(store.printedMoments.count, "moment", spellingUpTo: 0)
        return "\(plan.pageCount) · \(nights), \(moments)"
    }

    /// What "Save" will hand over: an interior per volume, and a cover for
    /// each one Lulu's table has a spine for.
    private func fileCountLabel(_ plan: BookPlan) -> String {
        let covers = plan.pagesPerVolume.compactMap(CoverSpec.init(pages:)).count
        let files = plan.volumes + covers
        let what = covers == 0 ? "interior" : "interior and cover"
        return plan.volumes > 1
            ? "\(Formatting.spelledCount(files, "file")) · \(what), per volume"
            : "\(Formatting.spelledCount(files, "file")) · \(what)"
    }

    /// The cover's size from Lulu's template, or why there isn't one.
    private func coverLabel(_ plan: BookPlan) -> String {
        let covers = plan.pagesPerVolume.map(CoverSpec.init(pages:))
        guard !covers.isEmpty, covers.allSatisfy({ $0 != nil }) else {
            return "none at this page count"
        }
        if covers.count > 1 { return "one per volume" }
        return covers[0]?.sizeLabel ?? "none"
    }

    private func softTitle(_ readiness: PrintReadiness) -> String {
        let count = readiness.softPhotos.count
        return count == 1 ? "One photo needs attention" : "\(count) photos need attention"
    }

    private func specRow(_ label: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Mono(label, size: 10, trackingRatio: 0.12)
                Spacer()
                Text(value)
                    .font(Typeface.mono(12.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 8)
            if !last { Rule() }
        }
    }

    private func build(_ plan: BookPlan) {
        guard !building else {
            // Second tap stops it. The writer checks between spreads.
            job?.cancel()
            return
        }
        building = true
        built = 0
        job = Task { @MainActor in
            // The trip's name and nothing else. It carried the traveller's
            // name too, while the metadata deliberately left it out because it
            // "travels with the file" — and so does the file's name.
            let name = store.displayName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let urls = await BookPDF.write(plan: plan, store: store, baseName: name) { fraction in
                built = fraction
            }
            building = false
            exported = urls ?? []
            sharing = !exported.isEmpty
        }
    }
}
