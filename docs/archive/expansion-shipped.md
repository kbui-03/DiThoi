# Expansion — the shipped phases

> **Archived.** These are the parts of [expansion.md](../expansion.md) about
> work that is now built: how Phases 1 and 2 were scoped, what each changed
> about the plan, the order they were done in, and the honest-state summary as
> it stood before the October 2026 review. What is built today and what is
> wrong with it is in [CHANGELOG.md](../CHANGELOG.md); what comes next is in
> [expansion.md](../expansion.md).

---

## The honest state of things

**Phase 1 is built.** Sync, an editable itinerary, real photos, real maps and
encrypted document scans all shipped, plus CoreLocation in Separated. The
lock-screen widget was deferred by decision, then built anyway — from the icon
set rather than from D4, once the mark gave it something to draw.

What's real today: the ledger, the budget maths, the letter gating, the journal
with actual photographs, the trip dates, live rates, an itinerary you can
rearrange, a map of where they've been, passport scans encrypted on the phone,
and a merge that two phones converge through — including a settlement neither
can clear alone. (Separated's distance to the meeting point is built but has
nothing to measure to: a typed meeting point has no position. See the known
issues in [CHANGELOG.md](../CHANGELOG.md#known-issues).)

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
- **Pairing is built and has never run.** Onboarding ends by offering a
  `CKShare` link that carries the trip and the other traveller's slot, and
  `TripStore.joinTrip` is the one thing that moves a `tripID` between phones.
  Everything on this side of the wire is checked; minting the share, accepting
  it and reading the owner's zone need two iCloud accounts and a paid team.
- **The app ships blank.** Every trip, the first included, starts empty and is
  set up through onboarding; `SampleTrip` is commented out.
- **Nothing has been printed.** The interior and cover PDFs are generated to
  Lulu's own templates and inspected on a phone; no physical proof has come
  back. The app exports the files and deliberately does not order prints.
- **Until 2.0 lands, this is a one-phone app that says "synced".** The loopback
  transport reports success, so the sync line reads "synced just now" while
  nothing leaves the phone, and settling up and home mode cannot complete. That
  wording is the first known issue to fix, and the cheapest.

Phase 1 was "make the two-person premise true". Phase 2 was "make it worth
opening on day thirty-five, and give it an ending". A review in October 2026
found a set of bugs in what is built — they are §2.6 below, and they come
before anything new. Phase 3 is a list of things worth trying, and none of them
should be started before 2.0 and 2.6.

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
| 2.2 | ✅ shipped, then reworked | Page-turn preview, reader, PDF and cover to Lulu's spec, the ending · the print handoff was removed |
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

*Reworked since.* The handoff is gone. It set an order flag on this phone,
reached no printer, and announced both books ordered when the other book's
pages are only on the other phone. The app exports an interior and a cover per
volume, sized to Lulu's templates, through the share sheet.

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

Since built: planning the next trip while the current one is still live, as a
dashed "planned" spine that becomes the next trip when this one is shelved.

Left for later:
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

## How it was sequenced

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
