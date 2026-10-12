import SwiftUI
import UIKit

/// Turns the book into files a printer will accept.
///
/// The pages are drawn by `BookSpreadView` — the same view the preview draws —
/// split down the gutter into single pages, because that is what a print
/// service expects and because a preview drawn by different code from the
/// print file is a preview that can lie.
///
/// **Drawn, not photographed.** This used to take an `ImageRenderer` *image* of
/// each spread at 300 dpi and paste it in. Every letter was pixels while the
/// print screen said "fonts: embedded, subset"; every page carried the whole
/// spread's bitmap, so each photograph was in the file twice; and nothing set
/// a trim box. `ImageRenderer.render` draws the view straight into the PDF
/// context instead, so type is type, a photograph is embedded once on the page
/// it prints on, and each page says where the guillotine goes.
enum BookPDF {

    /// - Parameter progress: called on the main actor after each spread, with a
    ///   fraction across every volume.
    /// - Returns: per volume, its interior and — when Lulu's table has a
    ///   spine for its page count — its cover. Nil if the book has no pages,
    ///   the caller cancelled, or a file could not be written.
    @MainActor
    static func write(plan: BookPlan, store: TripStore, baseName: String,
                      progress: @MainActor (Double) -> Void = { _ in }) async -> [URL]? {
        guard !plan.spreads.isEmpty else { return nil }

        // Not `temporaryDirectory`. This file is the whole journal — every
        // page and every photograph — and it used to be written there at the
        // ordinary protection class with nothing anywhere deleting it.
        //
        // Cleared first: the previous build is somebody's book too, and leaving
        // it behind is the same leak one export older.
        Storage.clearExports()

        let volumes = plan.volumeSpreads
        let total = max(volumes.reduce(0) { $0 + $1.count }, 1)
        var done = 0
        var urls: [URL] = []

        for (number, spreads) in volumes.enumerated() {
            let stem = volumes.count == 1
                ? baseName
                : "\(baseName) — volume \(number + 1) of \(volumes.count)"
            let url = Storage.exportDirectory.appendingPathComponent("\(stem) — interior.pdf")
            // Its own contents, numbered to its own pages: the writer numbers
            // each file from page 1.
            let sections = plan.volumeSections.indices.contains(number) ? plan.volumeSections[number] : plan.sections
            let written = await writeVolume(spreads, sections: sections, spec: plan.spec, store: store, to: url) {
                done += 1
                progress(Double(done) / Double(total))
            }
            guard written else {
                // Cancelled or failed: nothing half-made is left behind, and
                // an earlier volume on its own is not the book either.
                Storage.clearExports()
                return nil
            }
            urls.append(url)

            // Its cover, sized to its own page count. A volume at a page
            // count Lulu's table has no trustworthy spine for gets none,
            // rather than one sized by guesswork; the print screen says so.
            if let spec = CoverSpec(pages: BookPlan.pageCount(spreads)) {
                let coverURL = Storage.exportDirectory.appendingPathComponent("\(stem) — cover.pdf")
                guard writeCover(spec, store: store, to: coverURL,
                                 volume: volumes.count > 1 ? (number + 1, volumes.count) : nil)
                else {
                    Storage.clearExports()
                    return nil
                }
                urls.append(coverURL)
            }
            await Task.yield()
        }
        return urls
    }

    /// One flat case-wrap cover. Every box is the whole sheet, as on Lulu's
    /// own template: the wrap is part of the artwork, not bleed to be trimmed.
    @MainActor
    static func writeCover(_ spec: CoverSpec, store: TripStore, to url: URL,
                           volume: (Int, Int)? = nil, style: CoverStyle = .paper) -> Bool {
        var media = CGRect(x: 0, y: 0, width: spec.totalWidth * 72, height: spec.totalHeight * 72)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: store.tripName,
            kCGPDFContextCreator: "Đi Thôi"
        ]
        guard let pdf = CGContext(url as CFURL, mediaBox: &media, info as CFDictionary) else { return false }
        let boxes: [CFString: Any] = [
            kCGPDFContextMediaBox: boxData(media),
            kCGPDFContextBleedBox: boxData(media),
            kCGPDFContextTrimBox: boxData(media)
        ]
        let view = BookCoverView(spec: spec, width: media.width,
                                 volume: volume.map { (number: $0.0, of: $0.1) }, style: style)
            .environmentObject(store)
            .frame(width: media.width, height: media.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: media.width, height: media.height)
        renderer.render(rasterizationScale: 300.0 / 72) { _, draw in
            pdf.beginPDFPage(boxes as CFDictionary)
            draw(pdf)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return true
    }

    /// One volume, one file.
    ///
    /// The context is a plain `CGContext` held open across `await`s. The old
    /// writer ran inside `UIGraphicsPDFRenderer.writePDF`, whose closure is
    /// synchronous — so the "yield between spreads" its comment promised never
    /// happened, the progress label never redrew, and the tap that was meant
    /// to stop it could not be delivered until it had finished.
    @MainActor
    private static func writeVolume(_ spreads: [BookSpread], sections: [BookSection],
                                    spec: BookSpec, store: TripStore,
                                    to url: URL, onSpread: @MainActor () -> Void) async -> Bool {
        var media = CGRect(x: 0, y: 0, width: spec.mediaPoints, height: spec.mediaPoints)
        let trim = media.insetBy(dx: spec.bleedPoints, dy: spec.bleedPoints)

        // The trip's own title, and not the traveller's name. Metadata travels
        // with the file wherever it is sent; the title page inside the book
        // says whose copy it is.
        let info: [CFString: Any] = [
            kCGPDFContextTitle: store.tripName,
            kCGPDFContextCreator: "Đi Thôi"
        ]
        guard let pdf = CGContext(url as CFURL, mediaBox: &media, info as CFDictionary) else {
            return false
        }
        let pageBoxes: [CFString: Any] = [
            kCGPDFContextMediaBox: boxData(media),
            kCGPDFContextBleedBox: boxData(media),
            kCGPDFContextTrimBox: boxData(trim)
        ]

        let trimPoints = CGFloat(spec.trimPoints)
        let spreadWidth = trimPoints * 2
        // One uniform scale for both axes: the trim artwork is enlarged by
        // exactly `media / trim` so it overflows the cut line by the bleed on
        // every side, in proportion. Two different ratios made every page 1.5%
        // taller than wide.
        let scale = CGFloat(spec.bleedScale)

        for (position, spread) in spreads.enumerated() {
            if Task.isCancelled {
                pdf.closePDF()
                try? FileManager.default.removeItem(at: url)
                return false
            }

            let view = BookSpreadView(spread: spread, width: spreadWidth,
                                      leftPageNumber: BookPlan.leftPage(ofSpreadAt: position),
                                      forPrint: true, sections: sections)
                .environmentObject(store)
                .frame(width: spreadWidth, height: trimPoints)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: spreadWidth, height: trimPoints)

            // The insides of the covers are half-spreads that never print.
            var halves: [Int] = []
            if spread.printsLeft { halves.append(0) }
            if spread.printsRight { halves.append(1) }

            renderer.render(rasterizationScale: CGFloat(spec.dpi) / 72) { _, draw in
                for half in halves {
                    pdf.beginPDFPage(pageBoxes as CFDictionary)
                    pdf.saveGState()
                    pdf.clip(to: media)
                    // Slide the spread so this half sits over the page, then
                    // enlarge it into the bleed.
                    pdf.translateBy(x: -CGFloat(half) * trimPoints * scale, y: 0)
                    pdf.scaleBy(x: scale, y: scale)
                    draw(pdf)
                    pdf.restoreGState()
                    pdf.endPDFPage()
                }
            }

            onSpread()
            // The render occupies the main thread — `ImageRenderer` is bound to
            // it — so this is what lets the progress draw and a stop tap land.
            await Task.yield()
        }

        pdf.closePDF()
        return true
    }

    private static func boxData(_ rect: CGRect) -> CFData {
        var box = rect
        return Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
    }
}

/// The system share sheet, for "Save PDF".
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Run once the sheet is finished with the file, whether it was sent or
    /// cancelled.
    ///
    /// Nothing used to run. The exported book — the whole journal — was left on
    /// disk for good, and the only reason it was ever tolerable is that nobody
    /// looked in `tmp/`. Cleanup belongs here rather than on dismissal, because
    /// the activity that received the file is still reading it until this fires.
    var onFinished: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items,
                                                  applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinished() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
