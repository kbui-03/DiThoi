# Expansion

Where this goes next, and why. For whoever decides what gets built.

Every idea below is scored on the same two axes — **effort** (dev-weeks, one
person) and **payoff** — and, more importantly, judged against a single
question:

> Does it survive week five?

That's the bar the prototype set for itself. On day three everything is
delightful; on day thirty-five they're tired, the novelty is gone, and the app
gets used at 11pm in a hostel bunk or not at all. Features that only work when
someone is enthusiastic are features that quietly stop being used. This document
is biased hard toward things that hold up when nobody can be bothered.

---

## Where things stand

Phases 1, 2 and 2.5 are built — everything listed under **Built** in
[CHANGELOG.md](CHANGELOG.md), which is also where the known issues are. How
those phases were scoped, what each one changed about the plan, and the order
they were done in are kept in [archive/expansion-shipped.md](archive/expansion-shipped.md).

Two things remain before anything new: making sync real (§2.0), which needs a
paid Apple Developer membership, and fixing what the October review found
(§2.6), which needs nothing.

---

## Next

### 2.0 Make sync real — 1 week · blocking

Attach a developer team, create the container, flip the flag — then spend the
week on everything the loopback transport cannot simulate: partial failure, the
user signing out of iCloud mid-trip, a first-run race where both phones push an
empty trip at once, and whether `CKShare` acceptance behaves the way the invite
flow assumes.

**This item was scoped wrong twice, and both corrections are now in the code.**

- *"`CKShare` so pairing is real"* read as a nice-to-have. It isn't: the
  transport wrote to `privateCloudDatabase`, which is scoped to one iCloud
  account, so flipping the flag would have given one person sync across their
  own devices and **nothing at all between two people**. Sharing needs a custom
  zone, a share on a root record, and reads through `sharedCloudDatabase`. That
  is now written, keyed off `tripID` the way `SyncPayload` always claimed, with
  `.ifServerRecordUnchanged` and a coordinator that re-merges on conflict —
  which also closes the pull→merge→push lost-update window that was never
  anybody's item.
- **The letters had no transport at all, and that was not on this list.**
  `LetterDropTransport` had one conformer, file-backed, same device. Home mode —
  all of §2.4 — could not deliver a letter to another phone, and 2.0 as
  originally written would not have changed that. `CloudKitLetterDropTransport`
  now exists, keyed on `(tripID, recipient)` with the address in the record
  name, so a phone cannot request a box it isn't on.

Both are inert and neither has executed. What pins them is
`TransportConformance` — one written-down set of semantics that the loopback
implementations are run against on every `./Tools/run-checks.sh`, and that the
CloudKit ones are waiting to be run against. That is weaker than testing them
and it is not pretending otherwise; what it buys is that the two can't quietly
come to mean different things, which is precisely how the old transport ended up
meaning "the trip" where every caller meant "this trip".

*Why first:* Phase 1 delivered the hard, testable half. This is the untestable
half, and until it's done every sharing claim in the UI is still aspirational.

### 2.6 Fix what the October review found — ~2 weeks · before anything new

The October 2026 review went screen by screen; its must-haves are listed in
[CHANGELOG.md](CHANGELOG.md#known-issues). The ones that decide whether the app
survives week five:

- **Money that can't be written down.** Six currencies, no decimal key, every
  expense dated "now", and only the newest six lines reachable to edit or
  delete. Each was a reason to keep the real ledger somewhere else; all four
  are fixed (see the changelog), along with settling up on one phone.
- **Writing that can be lost.** Tonight's page and a letter from home are
  discarded by a swipe down, with no warning. The journal is the payload of the
  whole product.
- **Moments that don't happen.** Arriving doesn't open the letters home sealed
  to that stamp — they open on the next wake, off screen. Typed stops have no
  position, so the arrival nudge never fires; typed meeting points have none
  either, so Separated can't say how far.
- **Claims the build can't keep.** "Synced just now" with nothing synced, and
  plaintext loopback copies of the ledger and the letters outside the protected
  store.

*Why before Phase 3:* every item is something already promised on a screen.

---

## Phase 3 — Things worth trying (unscheduled)

Ideas with real upside and real risk of being gimmicks. Prototype before
committing.

**Offline peer sync over Multipeer Connectivity — 1.5 weeks.** Two phones in the
same room reconciling the ledger with no signal at all. Deeply on-brand for an
offline-first app and genuinely useful on a night bus. Risk: a second sync path
to keep correct, for a case CloudKit mostly covers on the next café wifi.

**Voice notes as journal entries — 0.5 weeks.** Some nights nobody wants to
type. Thirty seconds of audio, transcribed on-device, transcript editable. Risk:
audio doesn't print, so it needs a clear story about what reaches the book.

**"What did we do on day 12?" — 1 week.** On-device search across journal,
ledger and trail. Cheap and quietly valuable a year later.

**Postcards in the post — 1 week.** A week of pages already saves as a postcard
image to Photos (built, never sent). Printing and mailing one through a service
would send the trip *outward*, which nothing currently does — and would be the
first thing that leaves the phone with the journal in it, so it needs the same
care the book's export got.

**Widgets beyond the day — 0.5 weeks.** Day and next-stop ship in all four
families. What's missing is spend-today, which is the one figure somebody would
plausibly want without unlocking — and the one that would need a second number
in the App Group. Low effort, modest payoff, and it costs a little of the
promise that the group holds a day, a place and a distance and nothing else.

**Per-trip hue on the shelf — 0.5 weeks.** The icon set rotates archived trips'
hue at the same lightness and chroma so spines are distinguishable without a
second design. It needs an exact `oklch → sRGB` conversion in Swift — eyeballed
hexes would drift off the ramp — and it is the one part of the set that isn't
about the icon or the widget, which is why it was left.

**Apple Watch companion — 3 weeks.** Tempting and probably wrong. The two
plausible cases — logging cash spend at a stall, and Separated mode on a wrist —
are real but narrow, and a Watch app is a permanent maintenance tax. Revisit
only if usage data shows people reaching for the phone specifically for those.

### Explicitly not doing

- **Social features, sharing, feeds.** The app's whole posture is that this is
  private between two people and one person at home. A "share your trip" button
  would contradict every privacy line in the design.
- **Gamification of the journal.** Streaks, badges, completion percentages. See
  §2.1 — the design deliberately forgives missed nights and it's right to.
- **Ads or analytics SDKs.** "Never uploaded, never in anyone's cloud —
  including his" is on the Papers screen. Believe it.
- **Android/web ports.** Not until there's evidence anyone but these two want
  it.

---

## Roadmap at a glance

| Phase | Weeks | Ships | Unlocks |
|---|---|---|---|
| **1 · Make it real** | ~8 | ✅ Sync engine, editable itinerary, photos, maps, encrypted scans, location | Two people *could* take it on a trip — once 2.0 lands |
| **2 · Worth opening** | ~9 | ✅ The evening ritual, the book, multi-trip, the writing side, smarter money, pairing (unrun) · ⛔ real CloudKit | It survives week five and ends properly — for one phone |
| **2.6 · Review fixes** | ~2 | ⛔ The known issues in the changelog | The ledger and the journal can be trusted on a real trip |
| **2.5 · The travellers' trail** | — | ✅ Editable waypoints, moments, the book's last section · ✅ marking from anywhere, the explorable map, "you are here", undo, grouping | A blank trip can have a trail; spontaneous things get kept, in seconds |
| **3 · Worth trying** | — | Peer sync, voice, search, postcards | Prototype first |

**Critical path:** 2.0 Real CloudKit and 2.6 the review fixes. 2.6 needs no
paid membership and can start today; 2.0 cannot start until there is one.

### What to measure

Vanity metrics will lie here — a two-month trip has a tiny, committed user base.
The only numbers that answer "does it survive week five?":

- **Journal completion by trip week.** If week 5 is much below week 1, §2.1
  didn't work.
- **Expenses logged within an hour of being spent.** Delay is the leading
  indicator of the ledger being abandoned.
- **Meeting point set per day.** The design's one daily shared ritual.
- **Books actually exported at the end.** The app can't see an order, so the
  export is the nearest honest proxy for whether any of this mattered.

And one Phase 1 added:

- **Sync rounds that merge something.** If two phones are genuinely both in use,
  a meaningful fraction of rounds should be pulling in the other person's
  changes. If nearly none do, only one of them is actually using the app — which
  is a product problem wearing a technical disguise.
