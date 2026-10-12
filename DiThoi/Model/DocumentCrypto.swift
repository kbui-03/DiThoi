import Foundation
import CryptoKit
import Security

/// The lock on the passport scans: AES-GCM, with a key that lives in the
/// Keychain and never leaves it.
///
/// Split out of `DocumentStore` so it can be checked. That file imports UIKit —
/// it turns `UIImage`s into JPEGs — which is why it is the single entry in
/// `EXCLUDED` at the top of `Tools/run-checks.sh`, and therefore why the one
/// subsystem in the app whose silent failure is *unrecoverable* had no coverage
/// at all. `Data` in, `Data` out: no UIKit, so the glob picks this up and the
/// checks compile it for macOS along with everything else in `Model/`.
struct DocumentCrypto {

    /// What happened, when it didn't work.
    ///
    /// Three cases rather than an optional, because the difference between them
    /// is the difference between "you haven't scanned anything" and "your
    /// passport is on this phone and this build can't read it". `image(_:)`
    /// used to answer `nil` to all of it, and the screen drew "decrypting"
    /// forever underneath a row that still said "3 pages · encrypted on this
    /// phone".
    enum Failure: Error, Equatable {
        /// The Keychain could not be reached, or refused. Nothing was changed.
        case keyUnavailable(OSStatus)
        /// There is a key and the bytes would not open with it.
        case undecryptable
        /// A fresh key could not be stored, so nothing was written.
        case keyNotStored(OSStatus)
    }

    /// Where the key lives. Injectable so the checks can use their own account
    /// and never touch the one the app's scans are sealed with.
    private let service: String
    private let account: String

    init(service: String = "com.lovedones.dithoi.documentKey",
         account: String = "documents") {
        self.service = service
        self.account = account
    }

    // MARK: - Sealing

    func seal(_ data: Data) throws -> Data {
        let key = try existingOrFreshKey()
        guard let sealed = try? AES.GCM.seal(data, using: key).combined else {
            throw Failure.undecryptable
        }
        return sealed
    }

    /// Opens what `seal` wrote.
    ///
    /// Never mints a key. Sealing is the only operation with a reason to create
    /// one, and a *read* that quietly creates a key is how the old code lost
    /// people's scans: any Keychain hiccup looked like "no key yet", a fresh one
    /// was minted over the real one, and every file on the phone became noise.
    func open(_ sealed: Data) throws -> Data {
        guard let key = try existingKey() else { throw Failure.undecryptable }
        guard let box = try? AES.GCM.SealedBox(combined: sealed),
              let opened = try? AES.GCM.open(box, using: key) else {
            throw Failure.undecryptable
        }
        return opened
    }

    // MARK: - The key

    /// The key that is already there, or nil if there genuinely isn't one.
    ///
    /// - Throws: `keyUnavailable` for every status that is *not*
    ///   `errSecItemNotFound`. That distinction is the whole point. The old
    ///   `loadKey()` returned nil for any non-success status, so a Keychain that
    ///   was merely unreachable — locked before first unlock, or an access group
    ///   that changed because the app was re-signed with a `DEVELOPMENT_TEAM`,
    ///   which is a step this project documents as supported — read as "no key
    ///   yet" and the next line deleted the real one.
    func existingKey() throws -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw Failure.keyUnavailable(status) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keyUnavailable(status)
        }
    }

    private func existingOrFreshKey() throws -> SymmetricKey {
        if let existing = try existingKey() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        try store(fresh)
        return fresh
    }

    /// Adds the key. Never deletes speculatively.
    ///
    /// This used to be `SecItemDelete` then `SecItemAdd`, which meant the real
    /// key was gone before anything had proved a replacement could be written —
    /// and `SecItemAdd`'s failure was reported by a `Bool` nobody could act on,
    /// since by then there was nothing to go back to. Add first; the only reason
    /// to delete is a duplicate, and then the retry is deliberate.
    fileprivate func storeFresh(_ key: SymmetricKey) throws { try store(key) }

    private func store(_ key: SymmetricKey) throws {
        var query = baseQuery()
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        // Available once the phone has been unlocked, never migrated to another
        // device, and never in a backup. Matches the directory's own exclusion:
        // a scan that survived to a new phone with no key to open it would be
        // worse than not surviving.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Something is there that `existingKey()` could not read back. It
            // cannot open anything, so replacing it loses nothing — and unlike
            // the old unconditional delete, we only get here having actually
            // asked.
            SecItemDelete(baseQuery() as CFDictionary)
            let retry = SecItemAdd(query as CFDictionary, nil)
            guard retry == errSecSuccess else { throw Failure.keyNotStored(retry) }
        default:
            throw Failure.keyNotStored(status)
        }
    }

    /// Forgets the key. For the checks, and for nothing in the app: there is no
    /// screen that discards the vault's key, because the files it opens would
    /// still be sitting there.
    func discardKey() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: - The key a letter is sealed to

/// This phone's half of the letter channel.
///
/// The private key never leaves the Keychain — not into `TripSnapshot`, so it is
/// not in a backup, and not into `SyncPayload`, so it is not in iCloud. Only the
/// public half travels, and a public key travelling is what it is for.
///
/// Built on `DocumentCrypto`'s Keychain handling rather than beside it, because
/// the failure that matters is the same one: a read that silently mints a
/// replacement is a phone that can no longer open its own post.
struct LetterKeyStore {

    private let crypto: DocumentCrypto

    init(account: String = "letters") {
        crypto = DocumentCrypto(service: "com.lovedones.dithoi.letterKey",
                                account: account)
    }

    /// This phone's private key, minting one the first time and only then.
    func privateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try crypto.existingKey() {
            let raw = existing.withUnsafeBytes { Data($0) }
            if let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
                return key
            }
        }
        let fresh = Curve25519.KeyAgreement.PrivateKey()
        try crypto.replaceKey(with: SymmetricKey(data: fresh.rawRepresentation))
        return fresh
    }

    /// What goes in the payload. Nil when the Keychain can't be reached, which
    /// the caller reports rather than papering over — publishing no key is
    /// recoverable, publishing a key whose private half was just thrown away is
    /// not.
    var publicKey: Data? {
        (try? privateKey())?.publicKey.rawRepresentation
    }

    func discard() { crypto.discardKey() }
}

extension DocumentCrypto {
    /// Replaces whatever is stored. Only for a key that is being *created* —
    /// `store(_:)` is private because minting over an existing key is the bug
    /// this file exists to prevent, and this is the one caller that has already
    /// established there is nothing to lose.
    func replaceKey(with key: SymmetricKey) throws {
        discardKey()
        try storeFresh(key)
    }
}
