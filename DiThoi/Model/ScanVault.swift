import Foundation

/// The passport and visa scans on disk: sealed bytes, their names, their order,
/// and what happens to the ones nothing points at any more.
///
/// Split out of `DocumentStore` for the reason `DocumentCrypto` was, one layer
/// up. That file imports UIKit — it turns `UIImage`s into JPEGs — so it is the
/// single entry in `EXCLUDED` at the top of `Tools/run-checks.sh` and nothing in
/// it is compiled by the checks. Leaving the bookkeeping there would have put
/// `prune(keeping:)` in the unchecked file, and a prune with the wrong set
/// deletes somebody's passport silently. `Data` in, `Data` out: no UIKit, so the
/// glob picks this up and it is checked with the rest of `Model/`.
///
/// Never synced. Never backed up.
final class ScanVault {

    static let shared = ScanVault()

    private let directory: URL
    private let crypto: DocumentCrypto

    /// - Parameters:
    ///   - directoryName: injectable so the checks get their own folder inside
    ///     `Storage`'s scratch container and never see the app's real scans.
    ///   - crypto: likewise for the Keychain account.
    init(directoryName: String = "Documents", crypto: DocumentCrypto = DocumentCrypto()) {
        let base = Storage.directory(directoryName)
        // Actively excluded, and the inverse of `PhotoStore`, which actively
        // sets this to `false`. The photographs are the artefact the trip
        // exists to produce and losing them to a restored backup is data loss;
        // a passport scan is the one thing here with a reason not to travel.
        try? (base as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        directory = base
        self.crypto = crypto
    }

    // MARK: - Names

    private static let suffix = ".scan"

    /// `<document uuid>-<zero-padded index>.scan`.
    ///
    /// The padding is what makes a lexicographic listing come back in page
    /// order, and the parse below is what stops that being load-bearing past
    /// page 999.
    private func name(for documentID: UUID, at index: Int) -> String {
        "\(documentID.uuidString)-\(String(format: "%03d", index))"
    }

    /// The document and page a filename belongs to, or nil if it isn't one of
    /// ours.
    ///
    /// Nothing else writes into this folder, so an unparseable name is a partial
    /// write or somebody else's file — either way not a scan, and not something
    /// `prune` is entitled to delete on a guess.
    private func parse(_ pageID: String) -> (document: UUID, index: Int)? {
        guard let separator = pageID.lastIndex(of: "-") else { return nil }
        let id = String(pageID[pageID.startIndex..<separator])
        let tail = String(pageID[pageID.index(after: separator)...])
        guard let document = UUID(uuidString: id), let index = Int(tail) else { return nil }
        return (document, index)
    }

    private func url(for pageID: String) -> URL {
        directory.appendingPathComponent("\(pageID)\(Self.suffix)")
    }

    private var storedPageIDs: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(Self.suffix) }
            .map { String($0.dropLast(Self.suffix.count)) }
    }

    // MARK: - Pages

    /// The scans belonging to one document, in page order.
    ///
    /// Sorted on the parsed index rather than on the string, so the zero padding
    /// is a convenience for anybody reading the folder and not a limit on how
    /// many pages a document may have.
    func pageIDs(for documentID: UUID) -> [String] {
        storedPageIDs
            .compactMap { pageID -> (String, Int)? in
                guard let parsed = parse(pageID), parsed.document == documentID else { return nil }
                return (pageID, parsed.index)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    func pageCount(for documentID: UUID) -> Int { pageIDs(for: documentID).count }

    /// One past the highest page this document has.
    ///
    /// Not `pageCount`, which was what `add` used: the two agree only while no
    /// page has ever been removed from the middle, and a count that collides
    /// with a name that already exists overwrites the page it collided with.
    func nextIndex(for documentID: UUID) -> Int {
        let highest = pageIDs(for: documentID).compactMap { parse($0)?.index }.max()
        return (highest ?? -1) + 1
    }

    /// Seals `data` and writes it as the next page of `documentID`.
    ///
    /// - Returns: the id of the page that was written.
    /// - Throws: `DocumentCrypto.Failure` when it could not be sealed, and
    ///   whatever `Data.write` throws when it could not be written — which on a
    ///   locked phone it can, because of the protection class below.
    @discardableResult
    func write(_ data: Data, for documentID: UUID, at index: Int) throws -> String {
        let sealed = try crypto.seal(data)
        let pageID = name(for: documentID, at: index)
        // The same split `Storage.writeProtected` makes, and for the same
        // reason: the checks build this file for macOS, where the protection
        // classes do not exist.
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try sealed.write(to: url(for: pageID), options: options)
        return pageID
    }

    /// One page's plaintext bytes, or why not.
    ///
    /// Three answers rather than an optional, which is the distinction
    /// `DocumentStore.Page` is built on top of: "there is no such page" and
    /// "there is a page and this phone cannot open it" are different things to
    /// put on a screen, and collapsing them is what let a lost key present as a
    /// spinner.
    enum Sealed {
        case missing
        case data(Data)
        case unreadable(DocumentCrypto.Failure)
    }

    func decrypted(_ pageID: String) -> Sealed {
        guard let sealed = try? Data(contentsOf: url(for: pageID)) else { return .missing }
        do {
            return .data(try crypto.open(sealed))
        } catch let failure as DocumentCrypto.Failure {
            return .unreadable(failure)
        } catch {
            return .unreadable(.undecryptable)
        }
    }

    // MARK: - Removing

    @discardableResult
    func deleteAll(for documentID: UUID) -> Int {
        var removed = 0
        for pageID in pageIDs(for: documentID) {
            try? FileManager.default.removeItem(at: url(for: pageID))
            removed += 1
        }
        return removed
    }

    /// Drops every scan belonging to a document that is no longer in the trip.
    ///
    /// - Parameter keeping: the ids of the **live** trip's documents, and
    ///   nothing else.
    ///
    ///   This is deliberately not the shape `PhotoStore.prune(keeping:)` has,
    ///   whose doc comment insists on walking the shelf as well — so read that
    ///   one and then this one before changing either. A closed trip's
    ///   photographs are what its book is made of, so they have to survive it.
    ///   A closed trip's scans are deleted *by* `closeTrip()`, before the
    ///   snapshot is frozen, which means no archived snapshot can ever name a
    ///   scan that is still on disk. Adding the shelf to this set would keep
    ///   files that the close was supposed to destroy.
    /// - Returns: how many files it removed.
    @discardableResult
    func prune(keeping ids: Set<UUID>) -> Int {
        var removed = 0
        for pageID in storedPageIDs {
            guard let parsed = parse(pageID), !ids.contains(parsed.document) else { continue }
            try? FileManager.default.removeItem(at: url(for: pageID))
            removed += 1
        }
        return removed
    }

    /// Empties the folder. For `-resetTrip`, which is how first launch is
    /// tested — `DebugScreen.reset()` wrote this out as a path literal, in a
    /// file `run-checks.sh` does not compile, which is the same argument
    /// `Storage.appKeys` exists for.
    func eraseAll() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
