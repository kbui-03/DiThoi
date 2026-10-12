import UIKit

/// Passport and visa scans, as images.
///
/// The Papers screen says these stay on the phone: never uploaded, never in
/// anyone's cloud. They get AES-GCM at rest, with a key that lives in the
/// Keychain and never leaves it.
///
/// Never synced. Never backed up.
///
/// Almost nothing is left here. The crypto is in `DocumentCrypto` and the files,
/// their names, their order and the prune are in `ScanVault` — both
/// Foundation-only, and therefore both checked. What genuinely needs UIKit is
/// images to JPEG and back, which is all this is, and which is why it is still
/// the one exclusion in `Tools/run-checks.sh`. Keep it that way: anything that
/// can be written without `UIImage` belongs next door where a check can reach
/// it.
final class DocumentStore {

    static let shared = DocumentStore()

    private let vault: ScanVault

    init(vault: ScanVault = .shared) {
        self.vault = vault
    }

    // MARK: - Pages

    /// Forwarders, so the three screens that only want a count don't have to
    /// know which of the two objects to ask.
    func pageIDs(for documentID: UUID) -> [String] { vault.pageIDs(for: documentID) }

    func pageCount(for documentID: UUID) -> Int { vault.pageCount(for: documentID) }

    /// What happened to a batch of scans.
    ///
    /// `add` returned a bare count and every caller ignored it, so a page that
    /// failed to encrypt was skipped in silence — the scanner dismissed, the
    /// haptic fired, and one of the three pages simply wasn't there.
    struct AddResult {
        var written: Int
        var attempted: Int
        var failure: DocumentCrypto.Failure?

        var isComplete: Bool { written == attempted }
    }

    @discardableResult
    func add(_ images: [UIImage], to documentID: UUID) -> AddResult {
        var result = AddResult(written: 0, attempted: images.count, failure: nil)
        var index = vault.nextIndex(for: documentID)
        for image in images {
            guard let data = image.downscaled(toLongEdge: 2400).jpegData(compressionQuality: 0.85)
            else { continue }
            do {
                try vault.write(data, for: documentID, at: index)
                result.written += 1
                index += 1
            } catch let failure as DocumentCrypto.Failure {
                // The Keychain is the same for every page in the batch, so the
                // first crypto failure is the answer for all of them. Stop
                // rather than produce the same error three times.
                result.failure = failure
                break
            } catch {
                // A write that was refused rather than a seal that failed —
                // reachable, because the file protection class means the write
                // is refused while the phone is locked. `failure` stays nil and
                // the shortfall says so in its own words.
                continue
            }
        }
        return result
    }

    /// One page, or why not.
    ///
    /// Three answers rather than an optional. "There is no such page" and "there
    /// is a page and this phone cannot open it" are different things to say, and
    /// collapsing them is what let a lost key present as a spinner.
    enum Page {
        case missing
        case decrypted(UIImage)
        case unreadable(DocumentCrypto.Failure)
    }

    func page(_ pageID: String) -> Page {
        switch vault.decrypted(pageID) {
        case .missing:
            return .missing
        case .unreadable(let failure):
            return .unreadable(failure)
        case .data(let data):
            // Bytes that opened but are not an image are as unreadable to the
            // reader as bytes that would not open.
            guard let image = UIImage(data: data) else { return .unreadable(.undecryptable) }
            return .decrypted(image)
        }
    }

    @discardableResult
    func deleteAll(for documentID: UUID) -> Int { vault.deleteAll(for: documentID) }
}

extension DocumentCrypto.Failure {
    /// What the screen says. Never "decrypting".
    var readerText: String {
        switch self {
        case .keyUnavailable:
            "this phone can't reach the key right now"
        case .undecryptable, .keyNotStored:
            "this phone can no longer open this scan"
        }
    }
}
