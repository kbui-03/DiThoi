import Foundation
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

/// Photos for the book, kept in the app's own container.
///
/// A `PHAsset` identifier would be cheaper, but the book has to survive
/// somebody tidying their camera roll six weeks later. So the app takes a copy,
/// downscaled to something a printer can still use, plus a thumbnail for the
/// timeline.
///
/// Nothing here is ever synced — the journals stay private until they print.
/// They are, however, backed up; see `init`.
final class PhotoStore {

    static let shared = PhotoStore()

    /// What `pixelShortEdge` found, by id. A photograph's id names one file
    /// for good — every save, crop and borrowed copy mints a fresh one — so
    /// the answer never goes stale, and the Book tab can ask about every page
    /// without reading every file's header on every visit. `NSCache` because
    /// the measuring runs off the main thread.
    let pixelEdges = NSCache<NSString, NSNumber>()

    /// How big a saved photo is kept, in pixels on its long edge.
    ///
    /// Taken from the book rather than chosen, because these two numbers are
    /// the same physical quantity and holding them separately is what went
    /// wrong: this was 2048 while `BookSpec` wanted 2,475, so every photo the
    /// app could produce measured 248 dpi and `PrintReadiness` warned that
    /// *every* page would print soft. A warning that is always true carries no
    /// information. Now the only way for the two to disagree is to change the
    /// book's trim or dpi, at which case this follows.
    static var printLongEdge: Int { BookSpec().fullBleedPixels }

    /// Small enough to decode in a scrolling list.
    static let thumbnailLongEdge = 320

    private let directory: URL
    #if canImport(UIKit)
    private var thumbnails = NSCache<NSString, UIImage>()
    /// Full-size pages, cached because the book preview asks for them inside
    /// `body`.
    ///
    /// `image(_:)` decodes a 2,475px JPEG off disk every time it is called, and
    /// `JournalPhoto` calls it during layout — so turning a spread re-decoded
    /// the same photograph on every pass, on the main thread. Small limit: these
    /// are ~7 MB decoded each, and the point is to survive a layout pass, not to
    /// hold the whole book in memory.
    private var pages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 6
        return cache
    }()
    /// Screen-sized copies for the book preview, keyed by id and size.
    private var previews: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()
    #endif

    init(directoryName: String = "Photos") {
        let base = Storage.directory(directoryName)
        // These used to be excluded from the backup, justified as privacy. It
        // wasn't privacy, it was data loss: the photographs are the artefact
        // this app exists to produce, and excluding them meant losing the phone
        // lost the pictures while the journal text and every letter — which the
        // app describes as the private half — carried on sitting in the backed-up
        // preferences plist. The protection was inverted.
        //
        // Set to false rather than left unset: an install that already ran the
        // old build has the flag on its directory, and only writing over it
        // clears it. Passport scans in `DocumentStore` keep both the exclusion
        // and their encryption, which is the one place the reasoning held.
        try? (base as NSURL).setResourceValue(false, forKey: .isExcludedFromBackupKey)
        directory = base
    }

    // MARK: - Writing

    func delete(_ id: String) {
        pixelEdges.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: url(for: id))
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
        #if canImport(UIKit)
        thumbnails.removeObject(forKey: id as NSString)
        pages.removeObject(forKey: id as NSString)
        #endif
    }

    /// A second file under a fresh id — for a page borrowing a moment's
    /// photograph. Never a shared id: `updateMoment` and `save(entry:)` both
    /// delete the file they swap out, so a page and a moment pointing at one
    /// file is a book missing a picture the first time either changes.
    func duplicate(_ id: String) -> String? {
        let copy = UUID().uuidString
        do {
            try FileManager.default.copyItem(at: url(for: id), to: url(for: copy))
        } catch {
            return nil
        }
        // The thumbnail is a convenience; without it the full file still reads.
        try? FileManager.default.copyItem(at: thumbnailURL(for: id), to: thumbnailURL(for: copy))
        return copy
    }

    func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    #if canImport(UIKit)
    fileprivate func cachedThumbnail(_ id: String) -> UIImage? {
        thumbnails.object(forKey: id as NSString)
    }

    fileprivate func cache(_ image: UIImage, as id: String) {
        thumbnails.setObject(image, forKey: id as NSString)
    }
    #endif

    var count: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter { !$0.hasSuffix("-thumb.jpg") }.count ?? 0
    }

    /// Deletes every photo no page points at any more.
    ///
    /// Nothing did this. Starting a new trip cleared the journal without deleting
    /// what it referenced and closing a trip kept its pages, so the folder only
    /// ever grew — invisible, unbounded, and full of pictures nothing could
    /// display.
    ///
    /// - Parameter keeping: **every** live id, which means the archived trips
    ///   too. The shelf reopens closed books and draws their photographs; a
    ///   prune that only consulted the live trip would silently gut every book
    ///   on the shelf, which would be far worse than the leak it fixes.
    /// - Returns: how many files it removed.
    @discardableResult
    func prune(keeping ids: Set<String>) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return 0
        }
        var removed = 0
        for name in names {
            // "<uuid>.jpg" and "<uuid>-thumb.jpg" both belong to one id.
            let id = name
                .replacingOccurrences(of: "-thumb.jpg", with: "")
                .replacingOccurrences(of: ".jpg", with: "")
            guard !ids.contains(id) else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            removed += 1
        }
        return removed
    }

    /// Everything in the folder right now, whether anything points at it.
    var storedIDs: Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".jpg") && !$0.hasSuffix("-thumb.jpg") }
            .map { $0.replacingOccurrences(of: ".jpg", with: "") })
    }

    /// Removes the folder's contents entirely. For `-resetTrip`, which is what
    /// first launch is tested through — and which used to leave every photo
    /// behind, so a reset trip was never quite a first launch.
    func eraseAll() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        #if canImport(UIKit)
        thumbnails.removeAllObjects()
        pages.removeAllObjects()
        #endif
    }

    // MARK: - Paths

    private func url(for id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg")
    }

    fileprivate func thumbnailURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id)-thumb.jpg")
    }

    fileprivate func fullURL(for id: String) -> URL { url(for: id) }
}

#if canImport(UIKit)

extension PhotoStore {

    /// Returns the id to store on the journal entry, or nil if it couldn't be
    /// written — in which case the caller should leave the page photo-less
    /// rather than pointing at nothing.
    ///
    /// Kept at the size the book asks for. `downscaled(toLongEdge:)` never
    /// scales *up*, so a genuinely small source — a screenshot, something sent
    /// over a messaging app — still lands small and still gets reported soft by
    /// the print screen. That warning is now about the photograph rather than
    /// about this function.
    @discardableResult
    func save(_ image: UIImage) -> String? {
        let id = UUID().uuidString
        guard let full = image.downscaled(toLongEdge: CGFloat(Self.printLongEdge))
                              .jpegData(compressionQuality: 0.85),
              let thumb = image.downscaled(toLongEdge: CGFloat(Self.thumbnailLongEdge))
                               .jpegData(compressionQuality: 0.8)
        else { return nil }
        do {
            try full.write(to: fullURL(for: id), options: .atomic)
            try thumb.write(to: thumbnailURL(for: id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    func image(_ id: String) -> UIImage? {
        if let cached = pages.object(forKey: id as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: fullURL(for: id).path) else { return nil }
        pages.setObject(image, forKey: id as NSString)
        return image
    }

    /// A copy no larger than `maxPixels` on its long edge, decoded straight to
    /// that size by ImageIO rather than decoding the whole photograph first.
    ///
    /// For the book preview. A spread on a phone is a few hundred points wide,
    /// and the preview used to ask `image(_:)` for every page the `TabView`
    /// kept ready — a 2,600px decode each, on the main thread, under a
    /// `forPrint` flag documented as preventing exactly that and read nowhere.
    func preview(_ id: String, maxPixels: Int = 1_000) -> UIImage? {
        let key = "\(id)@\(maxPixels)" as NSString
        if let cached = previews.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let source = CGImageSourceCreateWithURL(fullURL(for: id) as CFURL, nil),
              let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = UIImage(cgImage: scaled)
        previews.setObject(image, forKey: key)
        return image
    }

    func thumbnail(_ id: String) -> UIImage? {
        if let cached = cachedThumbnail(id) { return cached }
        guard let image = UIImage(contentsOfFile: thumbnailURL(for: id).path) else { return nil }
        cache(image, as: id)
        return image
    }

    /// **Short** edge in pixels, read from the file's header rather than by
    /// decoding it — the print screen asks this about every page in the book at
    /// once.
    ///
    /// This is the number the 300 dpi check is made of, so it has to be the
    /// pixels actually on disk and not what the camera claimed — and it has to
    /// be the edge the page actually stretches. The page is square and fills,
    /// so a photograph is cropped to its shorter edge and *that* is what gets
    /// scaled to 8.25 inches. Reading the long edge said a 2475 × 1856
    /// landscape was clean at 300 dpi while it printed at about 225: a check
    /// that answered about an axis the book throws away.
    ///
    /// Photographs cropped through `PhotoCrop` are square, so the two agree.
    /// The difference is what makes the warning honest about the ones already
    /// on disk, which are not.
    func pixelShortEdge(_ id: String) -> Int? {
        if let known = pixelEdges.object(forKey: id as NSString) { return known.intValue }
        guard let edge = measureShortEdge(id) else { return nil }
        pixelEdges.setObject(NSNumber(value: edge), forKey: id as NSString)
        return edge
    }

    private func measureShortEdge(_ id: String) -> Int? {
        guard let source = CGImageSourceCreateWithURL(fullURL(for: id) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return min(width, height)
    }
}

extension UIImage {
    /// Aspect-correct resize that never scales *up* — a small photo stays small
    /// rather than being interpolated into a big blurry one.
    func downscaled(toLongEdge edge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > edge, longest > 0 else { return self }
        let scale = edge / longest
        let target = CGSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

#endif
