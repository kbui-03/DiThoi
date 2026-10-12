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

## The honest state of things

**Phase 1 is built.** Sync, an editable itinerary, real photos, real maps and
encrypted document scans all shipped, plus CoreLocation in Separated. The
lock-screen widget was deferred by decision, then built anyway — from the icon
set rather than from D4, once the mark gave it something to draw.

What's real today: the ledger, the budget maths, the letter gating, the journal
with actual photographs, the trip dates, live rates, an itinerary you can
rearrange, a map of where they've been, passport scans encrypted on the phone,
a real distance to the meeting point, and a merge that two phones converge
through — including a settlement neither can clear alone.

**The trail is the travellers' now.** Waypoints are made and edited on the
itinerary stop they belong to — so a trip nobody packed can have a trail at all,
which it never could — and moments record what nobody planned: one photo, one
line, the phone's own position, kept on the phone and printed at the back of the
book. Still open: renaming a stop (`ItineraryDocument` has no `setTitle`), and
the screenshot matrix for the book's moment spreads.

**And it is quick to use.** Making a moment is a verb at the top of the trail
rather than a button under every stamp and moment so far, and Siri, Spotlight,
the Action button and an iOS 18 control open the composer from outside the app.
The map opens full-screen with a card for every mark; the trail knows where you
are, if you already said it could, and how far the next stop is; deleting a
moment can be undone; the full list is grouped by stop. A moment kept at the
airport is filed before departure. Unverified on a device: the App Shortcut and
the control.

**Phase 2 is built too, except its first item.** The evening prompt, the book as
a real printable object, home mode, multi-trip and the money refinements all
shipped. The trip now has a beginning, a middle that asks for one line a night,
and an ending.

What is still not real:

- **CloudKit has never executed.** The merge is tested against a file-backed
  second phone; the pipe to Apple's service is written and unrun. Until someone
  attaches a developer team, "shared with the other phone" is still a claim. This is now
  the *only* thing in either phase that hasn't run — but it is a bigger thing
  than this list said it was for two rounds running, because until recently the
  transport was shaped so that running it would not have worked either. See §2.0.
- **Letters are now genuinely addressed.** Either traveller can be the one
  written to, the box is keyed on `(tripID, recipient)`, and the other phone
  collects nothing rather than collecting and declining to draw it. What is
  still missing is any feedback when the observer addresses one wrongly — and
  that stays missing on purpose, because the only thing that could report it is
  a delivery receipt.
- **There is no pairing.** Who is holding the phone is now the *first* question
  onboarding asks — traveller or observer — and the slots carry names each phone
  sets for itself, merged per slot so neither can clobber the other. The merge,
  the handshake and the one-way letter channel are real; identity still isn't.
  Nothing stops two phones claiming the same slot, and that is what CloudKit
  sharing (`CKShare`) would fix.
- **A blank trip is reachable but not shipped.** `TripStore(seed:)` and the
  `origin == .blank` branch of onboarding are built and driven by the checks;
  the app still defaults to `.packed`, because this build is one packed trip.
  A wider release flips one default and gets a real setup flow for free.
- **Nothing has been printed.** The PDF is generated at spec and has been
  inspected on a phone; no physical proof has come back from Blurb or Lulu, and
  the handoff stops at a confirmation screen rather than their API.
- **The trail on the book's country openers is still a placeholder.** Every
  other hatched panel from Phase 1 got a real asset behind it; this one didn't.

Phase 1 was "make the two-person premise true". Phase 2 was "make it worth
opening on day thirty-five, and give it an ending". Phase 3 is a list of things
worth trying, and none of them should be started before 2.0.

---

## Phase 1 — Make it real ✅ *shipped*

| | Shipped | Notes |
|---|---|---|
| 1.1 | Sync engine, merge, two-phase settlement | CloudKit transport written but **inert** — no developer team |
| 1.2 | Editable itinerary | Add/remove/reorder/resize, days re-flow, overrun surfaced |
| 1.3 | Real photos | `PHPicker`, own downscaled copy + thumbnail, never synced |
| 1.4 | Real maps | MapKit route and pins, framed on the travelled portion |
| 1.5 | Document scans | VisionKit + photo fallback, AES-GCM at rest, Keychain key |
| — | CoreLocation in Separated | When-in-use only, real distance and bearing |
| 1.6 | Lock-screen widget | Built later, from `Đi Thôi - Icon Set.dc.html` — four families, one App Group key |

### What Phase 1 changed about the plan

Three things are now obvious that weren't before.

**Turning CloudKit on is a config change, not a project.** Because merge was
kept out of the transport, the remaining work is a team ID, a container and a
plist flag. What is genuinely untested is everything CloudKit does when it goes
wrong — retries, partial failures, quota, the user switching iCloud account.
That is a week of hardening, and it is now *the* thing standing between this and
two people actually relying on it.

**Sync being whole-payload is fine, until it isn't.** Every round ships the
entire shared trip. For two people and sixty days that is tens of kilobytes and
completely reasonable. It becomes wrong the moment there are many trips or a
much longer one — and multi-trip is a Phase 2 item, so the two collide.

**"No conflict UI beyond a notice" is a real gap.** The loser of a
last-writer-wins merge is announced but unrecoverable. It has not bitten yet
because the app has never run on two real devices.

---

## Phase 2 — Make it worth opening (~9 weeks)

Phase 1 made it *work*. Phase 2 is what makes someone open it on day thirty-five
without being asked, and what gives the whole thing an ending.

It opens with the item Phase 1 created rather than closed.

| | State | Notes |
|---|---|---|
| 2.0 | **Still blocking** | Needs a developer team; nothing about it is code |
| 2.1 | ✅ shipped | Learned hour, pre-loaded composer, one backfill offer |
| 2.2 | ✅ shipped | Page-turn preview, PDF at print spec, handoff, the ending |
| 2.3 | ✅ shipped, then reworked | Shelf, finish (shelve or discard), between trips, next trip through onboarding |
| 2.4 | ✅ shipped | Home mode, compose/condition/seal, the board, J9 and J10 |
| 2.5 | ✅ shipped | Categories, spend-by-category, per-country day rates, repeats |

### What Phase 2 changed about the plan

**2.0 got smaller, and more clearly the only thing left.** Multi-trip was
supposed to force the sync round to become per-trip. It didn't, because the
design's own rule — one live trip, archived ones are cold storage — turns it
into one payload with a `tripID` on it and a merge that refuses a mismatch.
Half a week of the 2.3 estimate evaporated. What remains in 2.0 is exactly what
it always was: everything CloudKit does when it goes wrong.

**The privacy promises got harder to break, not easier.** Adding the writing
side meant letters finally had to travel, which is the moment a promise like
"he can't see when you read it" usually dies. Putting them on their own one-way
channel, with a type that has nowhere to put a read receipt, cost about a day
and made the promise structural instead of a rule somebody has to remember.

**One design instruction was not followed.** H2 has the app pick the night's
photo "from 84 today", which needs read access to the whole camera roll — and
the Papers screen promises the app holds nothing it doesn't need. The composer
pre-loads the line and the tags and leaves the photo one tap. That was the only
place the design and the built app disagreed, and the app won, as instructed.

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

### 2.1 The evening ritual — ✅ shipped

The journal composer is good. What's missing is anything that *brings them to
it*. A single notification, at a time the app learns rather than one they set:

> *Day 34. Hội An. One photo, one line.*

With the day's best photo already picked and the tag chips pre-lit from where
they were. Three taps to done, exactly as the design promises.

*Why this is the highest-value item in Phase 2:* the journal is the payload of
the entire product. Everything else is scaffolding around getting two books
printed at the end. Streaks and stats would be the obvious move and they're the
wrong one — a broken streak on a hard day is a punishment, and the design
already takes the opposite line ("You've missed two nights. Nobody minds; the
book skips them"). Keep that. One gentle prompt, no scores.

### 2.2 The book itself — ✅ shipped

The app is explicitly building toward two printed books that "arrive on the same
day and that's when the reading starts". That artefact doesn't exist.

Ship: a proper page-turn preview, PDF export at print spec, and a print-service
handoff (Blurb or Lulu have APIs). Then the closing moment the prototype's own
"try next" list asks for — day 61, both books ordered, the last letter opening.

*Why:* it's the ending. Without it the app just stops on day 61.

### 2.3 A second trip — ✅ shipped (reworked)

Right now there is one trip, seeded from `SampleTrip`. Generalise to many:
create, archive, browse past ones. `TripStore` is already parameterised by
dates/budget/currency, so the app half is mostly a container and a picker.

*Now larger than first estimated,* because it collides with sync: one payload
per trip means the whole-payload round has to become per-trip, and the CloudKit
record name has to key off the trip. Doing multi-trip without touching sync
would mean pushing every trip on every round. Half a week of that estimate is
sync, and it should be done in the same change rather than discovered later.

*Reworked since.* The first version had a separate five-step setup (template,
dates, money, travellers, features) and three unrelated exits: close, "empty
this trip", and join. The separate setup duplicated onboarding's screens, had
no itinerary or invite step, and reset whoever held the phone. It is gone:
- A trip is finished from one sheet: shelve it or throw it away.
- A closed trip leaves the tabs, and the app waits on the shelf.
- "Start the next trip" runs `ArrivalFlow` again, with names, role, money and
  cards carried over.
- Templates are not asked any more, and the feature switches live in settings.

Left for later:
- Planning the next trip while the current one is still live, as a "planned"
  spine that becomes live on close.
- Re-pairing the phones in one tap. The new `tripID` means the invite step
  asks again.

*Why:* it's the difference between a keepsake for one trip and something they
open again next year. Also the honest precondition for anybody but the two people it was written for
using it.

### 2.4 Letters, from the other side — ✅ shipped

There's a whole half of this product that doesn't exist: **the app he uses at
home to write the letters.** Compose, set a condition (a place, a day, a stamp),
seal. Plus the promise the design makes — he can't see when they're read.

*Why:* the prototype's own "try next" list names it first. It's also what makes
the app repeatable: anyone with someone leaving for two months is the customer,
and the letters are the reason they'd choose this over Splitwise plus a notes
app.

### 2.5 Smarter money — ✅ shipped

Categories (inferred from note text, correctable), spend-by-category, "you spend
€40/day in Thailand and €95 in Korea", and a recurring-expense shortcut for the
guesthouse you're in for four nights.

*Why medium:* the money screen already does the two things that matter (are we
okay, who owes whom). This is refinement, not a gap.

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

**Postcards — 1 week.** Turn a journal page into a physical postcard, printed
and mailed from a service. Sends the trip *outward*, which nothing currently
does.

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
| **2 · Worth opening** | ~9 | ✅ The evening ritual, the book, multi-trip, the writing side, smarter money · ⛔ real CloudKit + pairing | It survives week five and ends properly — for one phone |
| **2.5 · The travellers' trail** | — | ✅ Editable waypoints, moments, the book's last section · ✅ marking from anywhere, the explorable map, "you are here", undo, grouping | A blank trip can have a trail; spontaneous things get kept, in seconds |
| **3 · Worth trying** | — | Peer sync, voice, search, postcards | Prototype first |

**Critical path:** 2.0 Real CloudKit is now the whole of it. Everything else in
Phase 2 is built, and every sharing claim in the UI is still the one thing that
has never executed.

### Sequencing logic

1. **Real CloudKit before anything else.** Phase 1 built the testable half of
   sync deliberately, which means what remains is precisely the part that can
   only be learned by running it. Every week it stays inert, more of the app is
   built on a sharing claim that has never been true. It is also the cheapest
   remaining item.
2. **The evening ritual next** because it is one week for the highest retention
   payoff in the document, and it depends on nothing.
3. **The book before the writing side.** The book completes the experience for
   the two people who already have the app; the writing side grows the cast.
   Ship the ending first.
4. **Multi-trip after the book**, and treat it as a sync change as much as a UI
   one — see 2.3. Doing it earlier would mean rewriting the sync round twice.
5. **Everything in Phase 3 gets a prototype and a week of real use before a
   commitment.** The Watch app remains the standing example of an idea that
   reads well and might not survive contact with a real trip.

### What Phase 1 suggests about how to work

Two things that paid off and are worth repeating.

**Separating the decidable half from the untestable half.** Merge went in one
pure function with no I/O, and the transport became a two-method protocol. That
is why sync could be verified — two stores, one file, real convergence — with no
account, no second device and no network. When something can't be tested for
environmental reasons, look for the seam that lets most of it be tested anyway.

**Screenshots as a test, not a demo.** Compiling and 76 passing assertions did
not catch a debug flag that silently reused stale state, an off-by-one in the
overrun warning, or a map framed on the wrong region. All three were obvious in
a picture. Budget time to *look* at every screen after a change of this size.

### What to measure

Vanity metrics will lie here — a two-month trip has a tiny, committed user base.
The only numbers that answer "does it survive week five?":

- **Journal completion by trip week.** If week 5 is much below week 1, §2.1
  didn't work.
- **Expenses logged within an hour of being spent.** Delay is the leading
  indicator of the ledger being abandoned.
- **Meeting point set per day.** The design's one daily shared ritual.
- **Books actually ordered at the end.** The single number that says whether any
  of this mattered.

And one Phase 1 added:

- **Sync rounds that merge something.** If two phones are genuinely both in use,
  a meaningful fraction of rounds should be pulling in the other person's
  changes. If nearly none do, only one of them is actually using the app — which
  is a product problem wearing a technical disguise.
