import Foundation
import CryptoKit

/// What any transport has to do, whichever one it is.
///
/// The CloudKit transports can't run on a machine with no developer team, so
/// the semantics both implementations share are written down here, run against
/// the one that does execute, and left pointed at the other — ready the day
/// somebody attaches a team.
///
/// A weaker guarantee than running both. What it buys is that the two can't
/// quietly mean different things by the same call.
///
/// Results come back as values rather than being asserted here, so the caller
/// reports them in its own voice.
enum TransportConformance {

    struct Result {
        var label: String
        var passed: Bool
        var detail: String = ""
    }

    // MARK: - Sync

    /// - Parameter fresh: hands back an *empty* box each time it's called, so
    ///   the suite can start from nothing without knowing how to erase one.
    static func sync(_ transport: SyncTransport, tripID: UUID) async -> [Result] {
        var results: [Result] = []
        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            results.append(Result(label: label, passed: passed, detail: detail))
        }

        let mine = UUID()
        let theirs = UUID()

        var payload = SyncPayload.empty(tripID: mine)
        payload.expenses = [Expense(date: Date(), amount: 120, currency: .thb, payer: .one,
                                    split: .evenly, note: "Conformance", country: "Thailand")]

        do {
            check("an empty box pulls nothing", try await transport.pull(tripID: mine) == nil)

            try await transport.push(payload)
            let back = try await transport.pull(tripID: mine)
            check("what goes in comes back", back?.expenses.first?.note == "Conformance")
            check("and comes back for the right trip", back?.tripID == mine)

            // The whole point of `pull(tripID:)`. A box holding one trip must
            // not answer for another, or two trips merge into one book.
            check("a different trip finds nothing",
                  try await transport.pull(tripID: theirs) == nil,
                  "the box answered for a trip it isn't holding")

            // Whole-payload writes, so the newest push is the state — there is
            // no partial application anywhere in this design.
            var later = payload
            later.expenses = []
            later.settings.budget = 4_321
            try await transport.push(later)
            let replaced = try await transport.pull(tripID: mine)
            check("a push replaces rather than merges",
                  replaced?.expenses.isEmpty == true && replaced?.settings.budget == 4_321,
                  "merging is the coordinator's job, not the pipe's")
        } catch {
            check("the box is reachable", false, "\(error)")
        }
        return results
    }

    // MARK: - Letters

    static func letters(_ transport: LetterDropTransport, tripID: UUID) async -> [Result] {
        var results: [Result] = []
        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            results.append(Result(label: label, passed: passed, detail: detail))
        }

        let addressee = Traveller.one
        let other = Traveller.two

        // The conformance suite has to seal the way the app does, or it proves
        // the transports work in a mode nothing uses. One key pair stands in for
        // the addressee's phone; the "other traveller" checks below are then
        // about the *address*, which is what stops the wrong phone learning a
        // box exists — the seal is what stops it reading one.
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPublic = recipientKey.publicKey.rawRepresentation

        let sealed = SealedLetter(
            Letter(number: 1, title: "Conformance", writtenOn: Date(),
                   condition: .nextOnline, hint: "soon", paragraphs: ["Hello."],
                   signature: "— me", sealedAt: Date()),
            sealedAt: Date())

        do {
            check("an unwritten box holds nothing",
                  try await transport.collect(tripID: tripID, for: addressee, opening: recipientKey) == nil)

            let drop = LetterDrop(tripID: tripID, recipient: addressee,
                                  letters: [sealed], updatedAt: Date())
            try await transport.post(drop, to: addressee, sealingTo: recipientPublic)

            let collected = try await transport.collect(tripID: tripID, for: addressee, opening: recipientKey)
            check("post reaches the address it was sent to",
                  collected?.letters.count == 1)

            // The design's promise is that the other phone has no notion of the
            // letters *including that they exist*. A phone that could fetch a
            // box and then decline to draw it has already learned the box is
            // there, so the address has to be part of what is asked for.
            check("and the other traveller finds nothing at all",
                  try await transport.collect(tripID: tripID, for: other, opening: recipientKey) == nil,
                  "a non-recipient could see that a box exists")
            check("and neither does another trip",
                  try await transport.collect(tripID: UUID(), for: addressee, opening: recipientKey) == nil)

            // Whole-set, so a drop can never half-arrive.
            let replaced = LetterDrop(tripID: tripID, recipient: addressee,
                                      letters: [], updatedAt: Date())
            try await transport.post(replaced, to: addressee, sealingTo: recipientPublic)
            check("a second post replaces the set",
                  try await transport.collect(tripID: tripID, for: addressee, opening: recipientKey)?.letters.isEmpty == true)
        } catch {
            check("the box is reachable", false, "\(error)")
        }

        // Type-level, and true of every transport because it is true of the
        // type they all carry: there is nowhere to put a read receipt.
        let fields = Mirror(reflecting: sealed).children.compactMap(\.label)
        check("nothing it carries can say whether a letter was read",
              !fields.contains("openedOn") && !fields.contains("openedPlace")
                  && !fields.contains("receivedAt"),
              "\(fields)")

        return results
    }

    // MARK: - Switched off

    /// What a transport has to do when it *can't* work.
    ///
    /// The only state the CloudKit pair is ever in on a machine with no
    /// developer team. `isAvailable == false` isn't enough on its own: the
    /// callers above branch on the *shape* of the failure, so the shape is what
    /// gets pinned.
    ///
    /// Three rules:
    ///
    /// - **A write throws, and throws `.unavailable`.** `SyncCoordinator` reads
    ///   `isFatal` to decide whether to retry, and `TripStore.postLetters`
    ///   records the sentence. A write that returned quietly would report a
    ///   delivery it never made.
    /// - **A read returns `nil`, not an empty drop.** An empty `LetterDrop`
    ///   says "there is a box here and it is empty", which a non-recipient must
    ///   not be able to learn.
    /// - **There is a reason, in words**, so home mode has something to print
    ///   instead of a delivery promise.
    static func inert(_ transport: LetterDropTransport, tripID: UUID) async -> [Result] {
        var results: [Result] = []
        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            results.append(Result(label: label, passed: passed, detail: detail))
        }

        check("a transport that isn't available says so", !transport.isAvailable)
        check("and says why in a sentence somebody could act on",
              transport.unavailableReason?.isEmpty == false)

        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPublic = recipientKey.publicKey.rawRepresentation
        let drop = LetterDrop(tripID: tripID, recipient: .one, letters: [], updatedAt: Date())
        do {
            try await transport.post(drop, to: .one, sealingTo: recipientPublic)
            check("posting into an unusable box throws", false,
                  "it returned as though the letter had gone")
        } catch let error as SyncError {
            check("posting into an unusable box throws", true)
            check("and the throw is one a caller can act on", error.isFatal,
                  "\(error)")
        } catch {
            check("posting into an unusable box throws", true)
            check("and the throw is one a caller can act on", false, "\(error)")
        }

        let collected = try? await transport.collect(tripID: tripID, for: .one, opening: recipientKey)
        check("and an unusable box holds nothing rather than an empty drop",
              collected == nil,
              "an empty drop would say a box exists")

        return results
    }
}
