import UIKit
import PDFKit

/// A PDF picked out of Files, turned into the page images the vault stores.
///
/// The case `ScannerView`'s own comment already named — "importing a visa PDF
/// screenshot someone emailed" — except that a screenshot was the only version
/// of it that worked, because the photo picker takes images and an emailed visa
/// is a PDF. This is the rest of it.
///
/// **The file itself is never copied anywhere.** It is opened in place under a
/// security-scoped URL, rasterised, and let go. Writing it to
/// `temporaryDirectory` on the way past would put an unencrypted passport in a
/// folder emptied on no schedule an app may rely on, which is the bug the
/// exported book already had once.
enum DocumentImport {

    /// Twenty is enough for a passport, a visa and the insurance schedule; a
    /// travel policy runs to forty pages of terms nobody wants sealed one page
    /// at a time. Said out loud when it bites rather than silently truncated.
    static let pageLimit = 20

    struct Result {
        var images: [UIImage]
        /// How many pages the file actually had, so the caller can say when it
        /// took only some of them.
        var pageCount: Int

        var wasTruncated: Bool { pageCount > images.count }
    }

    /// - Returns: nil when the file could not be opened or held no pages at all.
    ///
    /// Off the main actor — rasterising twenty pages at 2400px is not something
    /// to do on the way through `body`.
    static func pages(from url: URL) async -> Result? {
        await Task.detached(priority: .userInitiated) {
            // A URL out of `.fileImporter` is security-scoped: without this the
            // read fails, and without the matching stop the app leaks the grant
            // for as long as it runs.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { return nil }

            var images: [UIImage] = []
            for index in 0..<min(pdf.pageCount, pageLimit) {
                guard let page = pdf.page(at: index) else { continue }
                images.append(render(page))
            }
            guard !images.isEmpty else { return nil }
            return Result(images: images, pageCount: pdf.pageCount)
        }.value
    }

    /// One page at the size `DocumentStore.add` is going to keep it at.
    ///
    /// Rendering smaller than that and letting the downscale be a no-op would
    /// make the scan softer than a photographed one for no reason; rendering
    /// larger just to have it thrown away costs memory per page.
    private static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let longEdge = max(bounds.width, bounds.height)
        // A PDF point is 1/72 inch and the vault keeps a 2400px long edge, so
        // this is the scale that lands on it. Guarded, because a malformed page
        // can report a zero box.
        let scale = longEdge > 0 ? 2400 / longEdge : 1
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Paper, not the app's cream — a scan is a picture of a document and
            // tinting it would be inventing something about the original.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}
