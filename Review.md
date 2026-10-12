# Review

Two halves, deliberately kept apart.

**Part 1** is an adversarial read of what is built: flaws, shortcuts and debt.
It is written to be uncharitable, because the charitable version already exists
in `README.md`, `architecture.md` and `expansion.md` and those three documents
are unusually good at explaining why things are the way they are. The job here
is to find the places where the explanation is better than the code.

**Part 2** is what is missing: features that would deepen this app rather than
widen it, each one weighed against the bar the project set for itself.

The overall verdict, so it isn't buried: **this is a genuinely well-made
codebase with an unusually principled model layer and an unusually large gap
between what its screens claim and what its code does.** The privacy
architecture is real and structural. The money maths is real. The itinerary
reflow is real. But a significant amount of the *chrome* — signal bars, offline
map sizes, kilometre counts, emergency numbers, "shows on both lock screens" —
is transcribed from the prototype and was never converted into something
computed, which is precisely the failure mode `CLAUDE.md` says the project
learned to avoid. The lesson was learned about numbers that could be
contradicted by other numbers on screen, and not learned about numbers that can
only be contradicted by reality.

---

# Part 1 — Adversarial code review

## 1. Claims the code cannot keep

This is the largest and most damaging category, and it is the one the project's
own stated standard is harshest about:

> *"When a design's numbers disagree, that's a spec bug — surface it and pick
> the source of truth."* — `CLAUDE.md`

That rule was applied to internal contradictions. It was not applied to
contradictions between the app and the world.

### 1.1 The emergency screen shows the wrong emergency numbers — with the right country name on it

`DiThoi/Features/Papers/SeparatedView.swift:76-79`

```swift
Mono("Emergency · \(store.currentCountry)", size: 9, …)
Text(SampleTrip.emergencyLine)     // "191 police · 1669 medical"
```

`emergencyLine` is a `static let` (`DiThoi/Model/SampleTrip.swift:577`). Those
are Thailand's numbers. The label above them is computed from the current leg.
So on day 30 the screen reads:

> **Emergency · Vietnam**
> 191 police · 1669 medical

Vietnam is 113 / 115. Korea is 112 / 119. This is the 2am screen, in the dark,
on a dying battery, and it presents wrong safety information with an
authoritative dynamic label that makes it look verified. Of everything in this
review this is the only item I would call a defect rather than debt.

The same screen hard-codes a Thai SIM number and a Chiang Mai guesthouse number
into `CallTile`s (`SeparatedView.swift:71-72`), labelled with the *live* renamed
person (`store.otherName`), so a trip between two renamed people in Portugal
offers to phone "Sofie" on a Thai mobile.

`DiThoi/Features/Papers/PapersView.swift:24` does it again in the light:
`"\(store.otherName)'s SIM \(SampleTrip.phoneNumber)"`.

### 1.2 Separated is single-player, and says it isn't

The file's own doc comment (`SeparatedView.swift:3-4`) calls it *"the only place
the app ever shares a live position"*. The screen tells the user
(`SeparatedView.swift:88`):

> "Turning this on also texts home your city — not your street. Nobody can watch
> you walk home."

and (`SeparatedView.swift:141`):

> "\(otherName)'s phone shares hers only while this is on, too."

None of that happens. `separatedSince` is declared in the **"This phone only"**
block (`DiThoi/Model/TripStore.swift:51`) and never appears in `SyncPayload`
(`DiThoi/Model/Syncing.swift:11-26`). `LocationService.current` never leaves the
device. There is no messaging integration anywhere in the project. The other
phone cannot learn that you are separated, where you are, or that you pressed
the button.

What the screen actually computes is *this* phone's distance to the meeting
point — useful, honest, and a fifth of what the copy promises. The design's most
emotionally loaded feature is a local distance readout wearing a two-person
label.

### 1.3 "Shows on both lock screens without unlocking"

`PapersView.swift:24` and `TodayView.swift:323`. There is no widget target, no
`WidgetKit` import, no Live Activity. `expansion.md:80` records the lock-screen
widget as *"Deferred indefinitely"* — so this is a known-untrue line that
survived into shipped copy on two screens.

### 1.4 Fabricated device and asset state

| Where | String | Reality |
|---|---|---|
| `SeparatedView.swift:13` | `"1 bar · no data"` | Never reads the radio |
| `TodayView.swift:16`, `MoneyView.swift:12`, `PapersView.swift:11` | `context: "offline"` | Never checks reachability |
| `ArrivalFlow.swift:141` | `"BKK gate D4"` | Literal |
| `ArrivalFlow.swift:349` | `context: "airplane mode"` | Literal |
| `ArrivalFlow.swift:168` | `"Made at home · April 2027"` | Literal; today is 2026 |
| `ArrivalFlow.swift:356` | `"\(SampleTrip.offlineMapSize) already on the phone"` = 1.4 GB | No offline maps exist |
| `ArrivalFlow.swift:439` | `"Offline maps · 9 cities"` | As above |
| `ArrivalFlow.swift:450` | `"Show-this cards · TH · VN · KR"` | Hard-coded |
| `TrailView.swift:21` | `"1,840 km\nand counting"` | Constant; never counts |
| `TrailView.swift:31` | `"38 pins dropped"` | Constant |
| `MoneyView.swift:13` | `"Ledger · ฿ ₫ ₩"` | Hard-coded symbols; `store.tripCurrencies` exists and is right there |

`TrailView`'s *"and counting"* is the sharpest one — it is a constant that
explicitly claims to be a counter, on the screen whose entire subject is
accumulated distance. `MoneyView`'s currency strip is the ironic one, given
`CLAUDE.md`'s insistence that *"no exchange rate is baked into logic"*: the
rates aren't, but the currencies are.

### 1.5 Onboarding promises an undo it does not implement

`ArrivalFlow.swift:218`:

> "This build serves all three, and picking wrong is a tap to undo."

`ArrivalFlow` holds `index` and only ever calls `advance()`
(`ArrivalFlow.swift:102-104`). There is no back affordance on any step. Worse,
`commitNames()` calls `store.adopt(mine)` (`ArrivalFlow.swift:123`), which is
documented as *"the only thing that may delete letters, and it must"*
(`TripStore.swift:232`). So the sequence "tap traveller two → Next → realise I'm
traveller one" **destroys the twelve packed letters with no way back and no
warning**. The commit-on-continue design was built specifically to stop this
happening per-keystroke; it stops it happening per-tap, and then the missing
back button reintroduces it per-step.

### 1.6 "PDF/X-3 · CMYK"

`BookSpec.standard` (`DiThoi/Model/Book.swift:12`) is displayed on the print
screen. `BookPDF.write` (`DiThoi/Features/Book/BookPDF.swift`) rasterises each
spread through `ImageRenderer` and draws the bitmap into a
`UIGraphicsPDFRenderer` context. The result is an sRGB raster PDF with no
PDF/X-3 conformance, no output intent, no CMYK conversion, and no vector type.
Blurb and Lulu will either reject it or silently convert it, and the type will
be resampled rather than typeset. The label is a spec sheet for a file the code
does not produce.

### 1.7 Attribution the model cannot support

`TodayView.swift:203`: `"\(store.otherName) added this."` — `DayPlan`
(`Models.swift:525`) has no author field, and `dayPlans` is a fixed
`SampleTrip` constant. The app asserts who wrote a plan item it cannot know
anything about.

---

## 2. Correctness and structural defects

### 2.1 Every photo in the book prints soft, always

`BookSpec.fullBleedPixels` = (8 + 2×0.125) × 300 = **2,475 px**
(`Book.swift:15`).

`PhotoStore.save` downscales to a long edge of **2,048 px**
(`DiThoi/Model/PhotoStore.swift:87`).

Therefore `PhotoMeasurement.dpi(on:)` for every photo the app has ever saved is
2048 / 8.25 = **248 dpi**, and `isSoft(on:)` (`Book.swift:185`) is
unconditionally `true`. `PrintReadiness.softSummary` will name **every single
day in the book** and tell the user their photos "came off something smaller
than the page needs".

The model checks do not catch this because they measure two synthetic values —
2,600 px and 1,560 px (`Tools/VerifyTrip.swift:485-486`) — neither of which is a
number the app can actually produce. The test asserts the arithmetic, not the
system.

Fix is one constant (`2048` → `2475`, or better, `BookSpec().fullBleedPixels`),
but the class of bug matters more than the instance: **two subsystems each held
a magic number for the same physical quantity and nothing tied them together.**

### 2.2 Archived trips are not browsable, and the docs say they are

`TripLibrary.swift:78-79` (`TripStatus.archived`): *"Read-only, on the shelf,
still completely browsable."*
`architecture.md:790`: *"An archived trip is the app it was, not a report about
it."*

`ArchivedTripView` (`DiThoi/Features/Trips/ShelfView.swift:287-374`) renders
eight `factRow`s off `TripSummary` and a `HatchPanel` placeholder. It never
touches `trip.snapshot`. `TripStore.adopt(_ snapshot:)`
(`TripStore.swift:1161-1188`) — the 27-line function that would make the claim
true — **is called from nowhere in the app.** It is dead code.

Consequences:

- Once a trip is closed, its journal, its letters, its ledger and its photos are
  permanently unreachable through the UI. For an app whose stated purpose is
  producing a keepsake, the keepsake becomes write-only the moment the trip ends.
- The `snapshot: Data` blob on every `ShelvedTrip` is stored, synced to nothing,
  and read by nothing.
- `architecture.md:790-791` contains a self-refuting sentence: *"…not a report
  about it, so `ArchivedTripView` reads the frozen summary"*. Reading the frozen
  summary is exactly what makes it a report about it.

### 2.3 The photos that matter are excluded from backup; the text that is "private" is not

`PhotoStore.init` (`PhotoStore.swift:31`):

```swift
try? (base as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
```

The comment justifies it as privacy. The effect is that **the book's
photographs — the artefact the whole app exists to produce — are not in the
iCloud backup.** Lose the phone on day 40 and the pages survive; the pictures
don't.

Meanwhile `TripStore.save()` (`TripStore.swift:1140-1143`) writes the entire
`TripSnapshot` — journal text, all twelve letters with full paragraphs, the
ledger — to `UserDefaults.standard`, which *is* in the backup, in plaintext, in
the app's preferences plist.

So the protection is inverted: the irreplaceable binary data is unbacked, and
the "never leaves this phone" prose is the part that leaves in a backup. Only
`DocumentStore` (passport scans) gets both encryption and backup exclusion,
which is the one place the reasoning is coherent.

### 2.4 Persistence is a whole-trip JSON encode on every property write

Every `@Published` on `TripStore` carries `didSet { save() }` — 27 of them.
`save()` encodes the entire `TripSnapshot` and writes it to `UserDefaults`.

- `setStart(_:)` (`TripStore.swift:255-277`) mutates six collections and
  `start`, so a single date change triggers **seven** full-trip serialisations.
- Any `TextField` bound through the store re-encodes the whole trip per
  keystroke.
- `startNewTrip` (`TripStore.swift:1046-1088`) assigns ~20 properties in
  sequence: twenty encodes, each of a partially-updated trip.
- `UserDefaults` is a preferences store. A 120-day trip with 120 journal entries
  and a full ledger is a few hundred kilobytes of synchronous main-thread JSON
  per mutation.

There is no debounce, no dirty flag, no incremental write, and no file-based
store. This works at the current scale and is a straightforward performance
cliff at the scale `TripTemplate.longHaul` (120 days) advertises.

### 2.5 The calendar is not anchored to a timezone, in a travel app

`Calendar.trip` (`Models.swift:837-841`) is a plain Gregorian calendar using the
device's zone, with a comment saying *"the dates are the user's"*.

`start` is stored as `Calendar.trip.startOfDay(for:)` **in whatever zone the
phone was in when it was set**. `dayNumber`, `date(forDay:)`, `phase`,
`dayNumber(for:)` and every seeded record are all computed against the *current*
zone.

Amsterdam → Bangkok is +5/+6 hours. A trip whose `start` was normalised to
00:00 CEST is, in ICT, 05:00 or 06:00 — still the same day, so `startOfDay`
arithmetic mostly survives. But:

- `RitualClock.observe` (`Ritual.swift:28`) records wall-clock minutes in the
  *current* zone, so flying east shifts the whole learned habit by the offset and
  the median silently drags across the timezone boundary.
- `RitualClock.fireDate` schedules against `Calendar.trip` at the moment of
  scheduling; the notification is a `UNCalendarNotificationTrigger` with absolute
  components (`Ritual.swift:180-181`), so a flight after scheduling fires it at
  the wrong local hour.
- A page written at 23:30 in Seoul and a page written at 23:30 in Hanoi are two
  hours apart in `observations`, and the clock treats them as identical.
- `date(forDay:)` returning a `Date` that is then formatted with `en_GB` and no
  explicit zone (`Models.swift:849-855`) can render the day before or after
  across a DST boundary at home while abroad.

None of this is caught, because `store.now` is `Date()` (`TripStore.swift:251`)
and there is no injectable clock, so no check can place the store in another
timezone.

### 2.6 CloudKit, as written, cannot sync two people

`CloudKitSyncTransport` (`DiThoi/Model/SyncTransports.swift:69-125`):

```swift
private var database: CKDatabase { container.privateCloudDatabase }
private let recordName = "trip"
```

The **private** database is scoped to one iCloud account. Two travellers have
different Apple IDs. Flipping `DiThoiCloudKitEnabled` to `YES` gives you
device-to-device sync for *one* person, and nothing between two people. Real
two-party sharing needs `CKShare` and the shared database, or a public/custom
zone with an invitation.

`expansion.md:88-91` frames 2.0 as *"a team ID, a container and a plist flag"*
plus a week of error hardening, and mentions `CKShare` only as the fix for
pairing identity. That understates it: without `CKShare` the transport does not
do the thing the app's copy says it does, at all.

Secondly, `SyncPayload`'s own doc comment (`Syncing.swift:16-18`) says the
`tripID` *"is what lets the transport key its record off the trip"*. The
transport uses a fixed `recordName = "trip"`. The comment describes a design the
code doesn't implement.

### 2.7 The letter channel has no real transport at all

`LetterDropTransport` has exactly one conformer: `LoopbackLetterDropTransport`
(`DiThoi/Model/LetterDelivery.swift:117`), which writes to
`Application Support/DiThoi/letters-<slot>.json` **on the same device**.

There is no CloudKit sibling, no remote implementation, no stub. Home mode — the
entire second half of Phase 2, the feature `expansion.md:203-207` calls the
reason anyone would choose this over Splitwise-plus-Notes — **cannot deliver a
letter to another device, and will not be able to after 2.0 lands.** This is a
larger hole than the one the roadmap identifies as its critical path, and it
isn't on the roadmap.

### 2.8 Sync has a lost-update window and no delivery outside the foreground

`SyncCoordinator.sync` (`SyncCoordinator.swift:41-65`) is pull → merge → push
with no version token, etag or `CKRecord.recordChangeTag` check. If phone B
pushes between A's pull and A's push, A's push overwrites B's record with a
payload that predates it. Convergence is recovered only when B syncs again — B
still holds its own records locally and re-pushes them. So it converges
*eventually*, provided both phones keep syncing, and silently loses the shared
box's copy in the meantime.

Separately, `syncNow()` runs only from `DiThoiApp.catchUp()`
(`DiThoiApp.swift:62`) on `.task` and `scenePhase == .active`. There is no
background refresh, no CloudKit subscription, no push. The meeting point — the
one time-critical shared value, the one `SyncMerge` surfaces a notice for
because *"a silently replaced meeting point is how two people end up in
different parts of a city"* (`Syncing.swift:142-143`) — only arrives when the
recipient happens to open the app.

### 2.9 The tombstone system is entirely unexercised

`SyncableRecord.deletedAt` exists on `Expense`, `Stamp` and
`SettlementProposal`; `Array.live` filters on it; `merged(with:)` is designed so
a delete can beat a concurrent edit (`Models.swift:184-208`).

**Nothing in the app or the checks ever assigns `deletedAt`.** A grep for writes
returns only the declaration and the decoder. There is no UI to edit or delete
an expense anywhere in the project.

So:

- A mistyped amount — ฿8,000 for ฿800 — is permanent. It distorts `spentHome`,
  `budgetFraction`, the forecast panel, `netBalanceHome` and any settlement
  proposed afterwards, for the rest of the trip.
- The most-used destructive path in every expense app is missing.
- The merge semantics that exist to handle deletion have never handled one, in
  production or in a check.
- `MoneyView.recentExpenses` (`MoneyView.swift:277-282`) iterates
  `store.expenses`, not `store.expenses.live` — so the moment deletion *is*
  implemented, tombstoned rows will appear in the Recent list.

### 2.10 The passport vault has no lock

`DocumentStore` does AES-GCM at rest with a Keychain key
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) — good, careful work. There
is no `LocalAuthentication` import anywhere in the project.

In the same tab, "Show-this cards" instructs the user to **hand the phone over**
(`PapersView.swift:69`). An unlocked phone handed to a driver, a hotel clerk or
an official is two taps from decrypted passport scans. The encryption defends
against offline file extraction, which iOS Data Protection largely already
covers; it does not defend against the threat model the feature *itself*
creates.

### 2.11 A blank trip inherits the packed trip's content

`TripStore` (`TripStore.swift:72-75`):

```swift
let dayPlans = SampleTrip.dayPlans
let documents = SampleTrip.documents
let showCards = SampleTrip.showCards
let sharingRules = SampleTrip.sharingRules
```

These are `let`s on the store, not per-trip data, and `startNewTrip` does not
touch them (it can't). So a fresh two-week Lisbon trip created through
`NewTripFlow` opens with:

- Chiang Mai's day-12 Songkran plan,
- two other people's passport and visa rows in Papers,
- Thai/Vietnamese/Korean show-this cards,
- a sharing-rules screen describing the packed trip.

Combined with §1.4's hard-coded strings, the "trip nobody packed" branch that
`VerifyTrip` carefully exercises at the model layer produces a visibly wrong app
at the view layer. The checks assert `fresh.legs.isEmpty` and stop there.

### 2.12 The meeting-point picker is a dead-ish control

`MeetingPointPicker` (`TodayView.swift:286-332`) offers exactly four options,
all in Chiang Mai, all `static let` in `SampleTrip`
(`SampleTrip.swift:562-571`). There is no free-text entry and no map pick. On
day 25 in Hanoi the app's one daily shared ritual offers you Wat Phra Singh.

By the project's own rule — *"Dead controls are worse than missing ones"*
(`CLAUDE.md`) — this is the same class of bug as the unwired Custom split that
was already fixed once.

### 2.13 The PDF geometry is anamorphic

`BookPDF.swift:48-55`. The spread is rendered at `spreadWidth × trimPoints` =
1152 × 576 pt (aspect 2.000). Each half-page is then drawn into:

```
width  = spreadWidth + bleed*2 = 1152 + 18 = 1170
height = trimPoints  + bleed*2 =  576 + 18 =  594
```

aspect 1.970. `UIImage.draw(in:)` stretches to fill, so horizontal scale is
1.0156× and vertical is 1.0313× — the printed page is **~1.5% taller than it is
wide relative to the design**, and the type is proportionally stretched. Small,
permanent, and exactly the kind of thing that is invisible on screen and obvious
in a bound book.

Correct behaviour is to render at `(2·trim + 2·bleed) × (trim + 2·bleed)` and
slice, or to render each page separately.

### 2.14 PDF generation blocks the main thread; the mitigation is cosmetic

`PrintFileView.swift:136-145`:

```swift
building = true
// Rendering 118 pages at 300 dpi is not a tap-and-wait job, so the
// button says what it is doing rather than freezing under the finger.
Task { @MainActor in
    exported = BookPDF.write(plan: plan, store: store, filename: name)
```

`BookPDF.write` is `@MainActor` and synchronous; wrapping it in
`Task { @MainActor in … }` yields once and then runs the entire render on the
main thread. The button label changes and *then* the app freezes. The comment
describes an intention the code does not implement.

Each spread allocates a 4800 × 2400 px bitmap (~46 MB) plus the PDF page buffer,
sequentially, for up to ~60 spreads. There is no progress reporting, no
cancellation, and on an older device a real memory-pressure risk.

`ImageRenderer` is `@MainActor`-bound, so this needs restructuring (render to
data off-thread per page, or chunk with explicit yields), not just a `Task
.detached`.

### 2.15 Journal photos are decoded synchronously inside `body`

`JournalPhoto.loaded` (`DiThoi/Features/Book/PhotoPicker.swift:66-68`) calls
`PhotoStore.shared.image(id)` → `UIImage(contentsOfFile:)`. Only thumbnails are
cached (`PhotoStore.swift:103-108`); full images are not. Every `body`
evaluation that isn't `usesThumbnail` does a disk read and a full JPEG decode of
a 2048 px image on the main thread. In `BookPreviewView` / `BookSpreadView`,
which are scrollable and re-evaluated on every layout pass, this is a per-frame
cost.

### 2.16 Photo files are never garbage-collected

`PhotoStore.delete` is called from exactly two places: replacing a page's photo
(`TripStore.swift:807`) and `resetToPacked()` (`TripStore.swift:1203`).

`startNewTrip` clears `journal = []` without deleting the photos it referenced.
`closeTrip` archives a snapshot whose `photoID`s point at files that no screen
can ever display again (§2.2). Nothing enumerates the directory and reconciles
it against live references. Photos accumulate in `Application Support`
indefinitely, invisible to the user, unbacked-up, and unreachable.

### 2.17 Smaller model issues

- **`arrive(at:)` bypasses every letter guard.** `TripStore.swift:747-755` calls
  `open(letterNumber:place:)` directly, which checks only *"exists and isn't
  already open"* (`TripStore.swift:574-578`). It does not check `isSealed`,
  `features.letters`, `isObserver`, or the letter's own `condition`. A stamp
  whose `unlocksLetter` points at an unsealed draft will "open" the draft. On the
  observer's phone (who also gets `TrailView`, `RootView.swift:104`), tapping
  "I'm standing in it" marks the writer's own letter as opened. Nothing leaks
  outward — `SealedLetter` has no read fields — but the state is wrong.
- **`openedPlace` may record the wrong city.** `openDueLetters`
  (`TripStore.swift:705`) sets `openedPlace = currentCity`, derived from the
  itinerary segment for today. A `.place(name)` condition satisfied via
  `earnedStampCities` (`LetterDelivery.swift:183`) can fire on a day when
  `currentCity` is somewhere else, so the book records the wrong place for the
  letter's most meaningful fact.
- **`recentExpenses` shows transfers as tappable dead rows.**
  `MoneyView.swift:84`: `guard expense.kind == .spend else { return }`. A
  settlement row is a button that does nothing, with no visual indication.
- **`resetToPacked()` doesn't restore `tripID`.** Everything else is put back to
  the handover state, but the trip keeps whatever id it had, which will not match
  a second phone reset the same way.
- **`applyConfirmedSettlements` stamps the transfer with `currentCountry`**
  (`TripStore.swift:536`), computed independently on each phone. Two phones
  applying the same settlement on different days write the same expense `id`
  with different `country` values, and the merge resolves it by `updatedAt`.
  Harmless today; a latent divergence.

---

## 3. Testing and process debt

### 3.1 There is no test target

`DiThoi.xcodeproj` contains exactly one `PBXNativeTarget`. `ENABLE_TESTABILITY
= YES` is set with nothing to test. Everything the project calls "194 model
assertions" is a single 802-line `@main` struct
(`Tools/VerifyTrip.swift`) with a hand-rolled `check(_:_:_:)` closure.

Consequences beyond the obvious:

- **No isolation.** One `TripStore` is mutated through the whole run. An early
  failure corrupts every later check. `store.role = debtor.other` at line 144
  and `store.role = .one` at line 161 are manual state restoration; miss one and
  a check 400 lines later fails for an unrelated reason.
- **No per-check reporting.** The output is a printed log and an exit code. No
  CI integration, no per-suite timing, no failure diffs.
- **Order dependence is load-bearing.** `store.setStart` /
  `store.setStart(SampleTrip.defaultStart)` at lines 90–96 must both run or every
  subsequent date check is wrong.

### 3.2 Some assertions are tautologies

`VerifyTrip.swift:751`:

```swift
check("a closed trip never pushes",
      phone.sync.lastSyncedAt == nil || phone.payload.expenses.count == payloadBefore + 1)
```

`payload` is computed from local state, and an expense was just added, so the
right-hand side is unconditionally true. **This check passes whether or not
`syncNow()` is a no-op on a closed trip.** It tests nothing. The correct
assertion is against the transport's contents.

`VerifyTrip.swift:67`:

```swift
check("spend excludes transfers", store.spending.count == store.expenses.count)
```

At that point the seeded ledger contains no transfers, so this asserts
`n == n`. The genuine exclusion is tested 90 lines later ("settling doesn't
change the burn"), which is the check that matters — this one is noise that
inflates the count.

### 3.3 Timing-dependent checks

`VerifyTrip.swift:296` and `:325`:

```swift
try? await Task.sleep(for: .milliseconds(20))
```

Used to force `updatedAt` ordering between two stores. This is a real-clock
race — on a loaded machine, or with a coarser clock, the ordering can invert and
the meeting-point and rename checks fail intermittently. The fix is the same one
that fixes §2.5: an injectable clock.

### 3.4 `store.now` is `Date()`, so nothing time-dependent is testable

`TripStore.swift:251`. Everything downstream — `phase`, `dayNumber`,
`isFinalDay`, `backfillCandidate`, `undeliveredLetters`, `RitualClock` — can only
be tested by mutating `start` to move the trip *around* today. There is no way
to test:

- the day the trip ends (`isFinalDay` fires once, `TripEndingView` is presented
  from `onAppear`),
- midnight rollover,
- a DST transition,
- crossing a timezone (§2.5),
- the `.after` phase with real elapsed time.

`VerifyTrip` works around this by rewinding `setStart`, which exercises the date
shifting but never the clock.

### 3.5 The check build is a hand-maintained file list

`Tools/run-checks.sh` lists 14 source files explicitly. A new file in
`DiThoi/Model/` is picked up automatically by the Xcode project (via
`PBXFileSystemSynchronizedRootGroup`) and **silently not compiled by the
checks**. Nothing fails; coverage just quietly drops.

The list also reveals that the invariant `CLAUDE.md` states as —

> *"The model layer imports no SwiftUI and no UIKit. That's what lets the checks
> build for macOS."*

— is not an invariant. `DiThoi/Model/DocumentStore.swift:1` is `import UIKit`,
and the rule is maintained by omitting that one file from the script. The
consequence is that **the AES-GCM encryption and Keychain handling for passport
scans have zero test coverage**, which is the one subsystem where a silent
failure (`storeKey` returning false → `encrypt` returning nil → `add` skipping
the page) is unrecoverable and invisible.

### 3.6 Language mode and concurrency

`SWIFT_VERSION = 5.0`, no `SWIFT_STRICT_CONCURRENCY`. Both sync transports are
`@unchecked Sendable` (`SyncTransports.swift:13`, `:69`) — the loopback one
guards a `DispatchQueue` correctly, the CloudKit one is stateless, so both are
defensible; but the annotation is doing the work a compiler check would.
`LoopbackLetterDropTransport` (`LetterDelivery.swift:117`) is not `Sendable` at
all and is captured across an `await` from `@MainActor`. Under Swift 6 that is a
diagnostic; under 5.0 it is silent.

`LocationService` uses `@preconcurrency CLLocationManagerDelegate` with `Task {
@MainActor in }` hops in each callback — workable, but delegate callbacks
already arrive on the queue the manager was created on, so this is defensive
noise rather than a fix.

### 3.7 Checks pollute the real user environment

`VerifyTrip` writes to `UserDefaults.standard` and to
`~/Library/Application Support/DiThoi/` on the developer's Mac
(`SyncTransports.swift:27-30`, `LetterDelivery.swift:125-128`). It cleans up
some keys and some boxes, not all — `dithoi.library.checks-blank`,
`checks-addr-*` boxes and the `Photos` directory persist. Running the checks
mutates state outside the build directory, which is the reason a test suite
should take its container as a parameter.

### 3.8 Screenshots are the only UI verification, and they are manual

`CLAUDE.md` is emphatic and correct that screenshots caught what compilation and
assertions did not. There is no script
that regenerates them, no snapshot-diff harness, and no failure mode other than
a human looking. Every item in §1 (hard-coded strings) and §2.11 (blank trip
inherits packed content) is visible in a screenshot and none of them were caught
— because the 66 files in `Screenshots/` are all of the *packed* trip, where all
of it looks right.

---

## 4. Architecture and maintainability

### 4.1 `TripStore` is a 1,333-line god object

It owns: identity, names, dates, the itinerary, money, settlement, letters (both
sides), the trail, the meeting point, the journal, the ritual, Separated, the
book, print readiness, ordering, the shelf, sync, and persistence. It has 27
`@Published` properties and roughly 90 members.

Every view takes it as an `@EnvironmentObject`, so **any mutation anywhere
invalidates every view in the app.** `objectWillChange` is additionally
force-forwarded from four child objects (`TripStore.swift:175-180`), so a rate
refresh redraws the letters screen.

The natural seams are visible in the `// MARK:` comments and are already
clean — `Money`, `Letters`, `Journal`, `The book`, `Syncing` — but extracting
them is blocked by the fact that they all mutate the same persisted blob.

### 4.2 The 27-field list is written out four times

`init` from snapshot (`:110-135`), `snapshot` (`:1148-1158`), `adopt(_:)`
(`:1162-1187`), plus `TripSnapshot`'s memberwise `init` (`:1263-1298`) and its
`init(from:)` (`:1300-1331`). Adding a stored property means five edits, and
**the compiler catches only two of them.** Omit it from `adopt` and archived
trips silently lose it; omit it from `init(from:)`'s `decodeIfPresent` and
somebody loses their trip — a risk `CLAUDE.md` names explicitly and then
mitigates only by documentation.

A single `Codable` value type that the store *holds* rather than *unpacks* would
collapse all five into one.

### 4.3 `role` is a public mutable test seam

`@Published var role: Traveller` (`TripStore.swift:33`). `VerifyTrip` assigns it
directly six times to impersonate the other traveller. `adopt(_:)` exists as the
guarded path and is bypassed. Any future code that assigns `role` outside
`adopt`/`writeTo` will skip the letter-deletion invariant that
`CLAUDE.md` describes as load-bearing.

### 4.4 Three overlapping identity enums

`Participant` (lynn/emmie/writer), `Traveller` (lynn/emmie), `Payer`
(lynn/emmie/both). The distinctions are justified and the justifications are
good. The cost is `name(for:)` / `name(of:)` / `label(for:)` — three
name-lookup functions differing only in argument type, with a comment explaining
that they can't share a name because leading-dot syntax would be ambiguous. That
comment is a smell pointing at a missing protocol.

### 4.5 Views reach directly into `SampleTrip`

Eleven call sites across `Features/` and `Root/` (§1.4). The model layer is
carefully injected and parameterised; the view layer skips it and reads
fixtures. This is the mechanical cause of most of Part 1 §1.

### 4.6 Zero localisation, in an app about crossing borders

`grep` for `LocalizedString` / `String(localized:)` returns **0 results** across
14,745 lines. Every string is an English literal.
`SWIFT_EMIT_LOC_STRINGS = YES` is set and nothing consumes it.

Separately, `Formatting.decimal` and `Date.text` both hard-pin
`Locale(identifier: "en_GB")` (`Models.swift:139`, `:852`). For numbers this is
the documented fix for the `38.348 THB → "38,348"` bug and is right. For **dates
and weekday names** it means Dutch users get English weekdays with no way to
change it, which is a different decision that inherited the same line of code.

### 4.7 Accessibility

The Dynamic Type work is genuinely excellent — `TypeSpec`, the per-size growth
ceiling, and `font(_:)` shadowing are a better solution than most shipping apps
have, and the timeline `k`-factor fix is exactly right.

Colour contrast is not:

| Token | Hex | On `bg` #F3F2F2 | Used for | WCAG AA (needs 4.5:1) |
|---|---|---|---|---|
| `n600` | #7D7979 | **3.85:1** | every `Mono` label, unselected tab labels, `RateStamp` | ❌ fail |
| `n500` | #9B9797 | **2.63:1** | "not yet" country rows in Money | ❌ fail |
| `n400` | #BAB6B6 | **1.80:1** | every `TextField` placeholder | ❌ fail badly |

`Mono` is the app's entire label voice, rendered at 9.5–10.5 pt — well below the
18 pt large-text exemption. `WrittenField`'s placeholder at 1.8:1 is effectively
invisible in daylight, on a screen used outdoors, in Thailand, in April.

Also missing: any use of `accessibilityReduceMotion` (there are `withAnimation`
blocks in `RootView`, `ArrivalFlow`, `SyncNotices` and the tab bar); only 15
`accessibilityLabel`s and one `accessibilityHint` across ~40 screens; the
`ClassicalTabBar` dot-plus-word design conveys selection by colour alone plus a
correctly-set `.isSelected` trait, which saves it for VoiceOver but not for
low-vision sighted use.

### 4.8 Portrait-only, iPhone-only

`INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait`.
Defensible for the design. Worth noting that the book preview — the one screen
that is inherently landscape, since a spread is 2:1 — is drawn in portrait.

### 4.9 Errors are swallowed everywhere

`try?` appears throughout: `save()` discards encode failures
(`TripStore.swift:1141`), `TripSnapshot.load()` discards decode failures
(`:1256`), `postLetters` discards post failures (`:667`), `DocumentStore.add`
`continue`s past an encryption failure (`DocumentStore.swift:57`),
`LoopbackLetterDropTransport.collect` returns nil on any error.

Only `SyncCoordinator` surfaces failure, via `SyncState.failed`. Everywhere
else, a full disk, a Keychain denial or a corrupt snapshot presents as *nothing
happened*. For an app holding two months of irreplaceable writing, silent
persistence failure is the worst available behaviour.

---

## 5. What is genuinely good

Stated plainly, because an adversarial review that omits it is a misleading one.

- **The privacy architecture is real.** Keeping journals and letters off
  `SyncPayload` by *absence from the type*, and `SealedLetter` having nowhere to
  put a read receipt, are structural guarantees rather than rules. The
  reflection-based check (`VerifyTrip.swift:543-548`) that fails if a read-shaped
  field appears is a genuinely clever piece of test design.
- **Addressed letter delivery.** Routing the privacy promise instead of
  rendering it — a non-recipient finds nothing at their own address and learns
  nothing about whether other addresses exist — is the correct solution and the
  reasoning in `CLAUDE.md` for rejecting a synced `letterRecipient` field is
  exactly right.
- **`ItineraryDocument.reflow()`.** Making gaps and overlaps unrepresentable by
  deriving day offsets from order-and-nights is the right shape, and the
  `isContiguous` invariant check after every edit type is the right test.
- **Settlement as propose→confirm with the transfer borrowing the proposal's
  id.** Idempotent by construction, converges under concurrent application, and
  provably leaves the budget alone.
- **Per-slot name stamping**, and the check that builds a third phone and asserts
  the observer can't claim a traveller's name.
- **`TypeSpec` and the growth ceiling.** The correct answer to a typeset design
  under Dynamic Type, and roughly 150 call sites got it for free.
- **The documentation.** `CLAUDE.md` in particular is the best example I have
  seen of a file that records *why* rather than *what*, and several entries are
  clearly the residue of real bugs. The failure is that it is trusted as
  enforcement (§3.5, §4.2) in places where only a compiler or a test can enforce.

---

## 6. Priority

**Everything in this table has since been addressed except localisation**, which
was ruled out of scope. The status column says how. §2.8's lost-update window
fell out of the item 6 work for free. The architectural findings that were
*decided* rather than fixed — §4.1's god object, §4.4's overlapping enums,
§4.8's portrait-only — are recorded as accepted debt in `CLAUDE.md`.

| # | Item | § | Severity | Status |
|---|---|---|---|---|
| 1 | Wrong emergency numbers under the right country label | 1.1 | **Critical** | ✅ `CountryFacts`; unknown country draws nothing |
| 2 | Every photo prints soft (2048 vs 2475 px) | 2.1 | **High** | ✅ save size derives from `BookSpec` |
| 3 | No expense edit/delete; tombstones never written | 2.9 | **High** | ✅ edit/delete/undo; delete-beats-edit checked |
| 4 | Archived trips unreachable; `adopt(_:)` dead | 2.2 | **High** | ✅ book, letters, ledger reopen read-only |
| 5 | Book photos excluded from backup | 2.3 | **High** | ✅ exclusion cleared; scans keep theirs |
| 6 | CloudKit private DB cannot sync two people | 2.6 | **High** | ✅ zone + `CKShare`, keyed on `tripID` — still inert |
| 7 | Letter channel has no remote transport | 2.7 | **High** | ✅ `CloudKitLetterDropTransport` — still inert |
| 8 | Onboarding "undo" destroys letters with no back button | 1.5 | **High** | ✅ back button; adoption deferred + confirmed |
| — | Lost-update window in pull→merge→push | 2.8 | Medium | ✅ fell out of item 6 |
| 9 | Separated / lock-screen / offline-map claims are false | 1.2–1.4 | Medium-High | ✅ deleted or derived |
| 10 | No app lock on the passport vault | 2.10 | Medium-High | ✅ Face ID on the scans only |
| 11 | Timezone-naive calendar | 2.5 | Medium | ✅ ritual clock anchored |
| 12 | Blank trip inherits packed content | 2.11 | Medium | ✅ per-trip, empty states |
| 13 | Contrast failures on the primary label colour | 4.7 | Medium | ✅ labels moved down the ramp |
| 14 | Whole-trip encode on every property write | 2.4 | Medium | ✅ coalesced + flush |
| 15 | Main-thread PDF render; anamorphic bleed | 2.13–2.14 | Medium | ✅ uniform scale, progress, cancel |
| 16 | Tautological assertions; no test target; no clock seam | 3.1–3.5 | Medium | ✅ clock + scratch storage; no XCTest by decision |
| 17 | Meeting-point picker is four Chiang Mai constants | 2.12 | Medium | ✅ free text + recents |
| 18 | Photo files never garbage-collected | 2.16 | Low-Medium | ✅ prune incl. the shelf |
| 19 | Zero localisation | 4.6 | Low (scope decision) | — out of scope |

---

---

# Part 2 — What is missing

## The bar

`expansion.md` set the right test and I am keeping it:

> **Does it survive week five?**

I am adding a second, because this app is not a productivity tool:

> **Does it deepen the artefact or the relationship — or does it just add a
> screen?**

The core of this product is four things, and nothing below is allowed to dilute
them:

1. Two people, one trip, one shared ledger that stays fair without arguments.
2. Sealed letters from home that open themselves, and never report back.
3. One page a night, asked for once, forgiven when missed.
4. Two printed books that arrive on the same day.

Everything else is scaffolding. **Fourteen features follow, in four groups.**
Nine of them I would build. Five are listed with reservations. At the end is
what I would refuse, which matters as much as the list.

---

## Group A — The trip while it is happening

*The middle of the trip is where the app is used most and where it currently has
the largest gap between promise and function.*

### A1. A country card that knows which country it is in ★ build first

**What.** Per-`Leg` reference data, shipped with the itinerary: emergency
numbers, the nearest consulate for the travellers' own nationality, "I need a
doctor / I've lost my passport" in the local script, plug type, and the rough
cost of a taxi from the airport. Appears in Papers, and on the Separated screen
in place of `SampleTrip.emergencyLine`.

**Why.** It fixes the one actual defect in the app (§1.1) by turning a constant
into data, which is what this project does everywhere else. It is also the most
useful thing you can put on a 2am dark screen. And it costs almost nothing: a
static table keyed on country, ~40 rows, no network.

**Effort.** 0.5 weeks, most of it collecting the data carefully.

**Guardrail.** It is a card, not a travel guide. No opening hours, no
recommendations, no content that goes stale. Everything on it must be true for
five years.

> **Built**, minus two of the five columns. `CountryFacts` already existed with
> emergency numbers and a language label; what was added is sockets and mains,
> two phrases in the local script, and `CountryCardView` in Papers — plus the
> phrases on the dark Separated screen, which is what they are for.
>
> **The consulate and the taxi fare were refused, on this item's own guardrail.**
> Fares are wrong within a year and "the airport" is not one place; consulate
> addresses and duty numbers move, and it would need a nationality the app has
> never asked anybody for. A wrong number at 2am is the §1.1 defect returning
> with a different label on it. The reasons are written into `CountryFacts` so
> the next person meets the decision rather than the gap.
>
> Phrases ship only where somebody could check the script — a whitelist, with
> fourteen languages named as waiting. The check enforces `phrases ⇒ language`.

### A2. Edit, delete, and undo on the ledger ★ build first

**What.** Swipe to delete (writes `deletedAt`, which already exists and already
merges correctly), tap to edit amount/currency/payer/split/note, and a 10-second
undo toast. Extend to the journal: a page should be editable the next morning.

**Why.** Not a feature so much as a missing floor. A ฿8,000 typo currently
poisons the budget, the forecast, the balance and every settlement for the rest
of the trip, and the only recovery is a compensating fake expense. It also
finally exercises the tombstone machinery the sync layer was built around.

**Effort.** 0.5 weeks. The model is done; this is UI plus one `SyncMerge` check.

**Guardrail.** No edit history, no audit log, no "who changed this". Two people
who trust each other enough to share a ledger do not need forensics.

> **Already built** — see Part 1's item 3. `update`/`delete`/`restore` write
> tombstones, the context menu edits and deletes, the ten-second undo banner
> restores, and the journal has been re-editable for any past day through
> `TonightEntryView(day:)` all along.
>
> Two residues closed since: nothing asserted `save(entry:)`'s *replace* branch
> — only the append one — so a page edited twice could have printed twice
> without a check noticing; and `MoneyView`'s undo `Task` outlived its view.
>
> Swipe-to-delete was **not** added. The rows are a hand-rolled `VStack`, not a
> `List`, and the shipped long-press menu says so in the footer copy.

### A3. Cash on hand ★ build

**What.** A `.withdrawal` case on `ExpenseKind`. Logging an ATM withdrawal
creates a cash pot in that currency; cash expenses draw it down. The Money
screen gains one line: *"You have about ฿4,200 left of the ฿20,000 you took
out."*

**Why.** This is the question a shared travel ledger is genuinely asked and
currently cannot answer. In cash economies — Thailand and Vietnam are two of
them — the ledger and the wallet diverge within a week, and the divergence is
what makes people stop logging. The leading indicator `expansion.md` says it
wants to measure ("expenses logged within an hour") collapses precisely when the
ledger stops matching the wallet.

It also slots into an existing seam: `ExpenseKind` already distinguishes money
that leaves the trip from money that moves between them; a withdrawal is money
that changes *form* and neither of the existing cases fits.

**Effort.** 1 week, including the reconciliation prompt ("you have ฿3,000 more
in your pocket than the ledger thinks — a missed noodle stall?").

**Guardrail.** Never a budgeting tool. One line, one number, one gentle nudge.
No cash-flow chart.

### A4. A receipt photo on a ledger line ★ build

**What.** One optional photo per expense, stored via the existing `PhotoStore`,
never synced (same promise as journal photos), shown in the expense detail.

**Why.** Cheap, obvious, and it removes the last reason to keep a parallel
paper trail. Also the thing you want six weeks later when a guesthouse charges
you twice.

**Effort.** 0.3 weeks. Everything needed already exists.

**Guardrail.** No OCR, no auto-amount-extraction. That is a different product
and it fails in three alphabets.

### A5. Separated, made mutual ★ build

**What.** Make the screen do what its own copy says. A `SeparatedSignal` on
`SyncPayload`:

```swift
struct SeparatedSignal: Codable {
    var traveller: Traveller
    var coarseLatitude: Double     // rounded to ~500 m
    var coarseLongitude: Double
    var startedAt: Date
    var expiresAt: Date            // startedAt + 4h, hard cap
}
```

Present only while Separated is on, auto-expiring, coarse by construction. The
other phone shows *"they are about 900 m north-east of the meeting point, as of
four minutes ago"* — and, critically, a Separated signal from the other phone is
the one thing in this app permitted to raise a notification without being asked.

**Why.** Because the current screen is a solo distance readout with two-person
copy on it, and because "we lost each other in a market with no data" is the
scenario the whole Papers tab is built around. Making it mutual is what turns a
comfort object into a tool.

The coarseness is not a compromise, it is the design: *"texts him your city —
not your street"* was already the stated rule, and rounding to 500 m is that
rule made structural in the same way `SealedLetter` is.

**Effort.** 1 week, and it must wait for real sync (§2.6) and a real push
channel (§2.8) — a beacon that arrives when the other person next opens the app
is worse than no beacon.

**Guardrail.** Never continuous. Never background. Never retained after
expiry — the signal must be *deleted*, not tombstoned, and there must be no
history of where anyone was. If it can answer "where was she on Tuesday", it has
become surveillance and the feature is wrong.

### A6. A meeting point you can actually set ⚠ needed, but small

Free-text plus an optional map pin, replacing the four Chiang Mai constants
(§2.12). Recently-used list. Not really a feature — a control that is currently
dead. 0.3 weeks.

---

## Group B — The book

*This is the artefact. It is also the part of the app with the largest
unfinished promise.*

### B1. Both journals, exchanged once, at the end ★ the single biggest missing feature

**What.** On the last day, both phones offer: *"Trade books?"* Both must accept.
Exactly once. When both have accepted, the journals — and only the journals —
cross, and each person's printed book contains both voices: her page on the
left, his on the right, for every night both wrote.

Until that moment nothing crosses. If either declines, nothing crosses, ever,
and the other person is told only "not this trip" — never "she said no at
11:04".

**Why.** The app's own closing line is that two books *"arrive on the same day
and that's when the reading starts."* Right now they can't: each book contains
one voice, and `draftOrder` (`TripStore.swift:933-945`) counts the other
person's pages from local data that never existed. The ending the product is
built toward is currently a page count.

More importantly: **this is the correct place for the privacy promise to end.**
The journals are private *until the books print* — that is what
`Syncing.swift:8-10` actually says. The current implementation keeps them
private forever, which is not the promise, it is the promise plus an unfinished
feature. Building the exchange is what makes the existing restraint mean
something: it is private because you chose to keep it private, right up to the
one moment you both chose otherwise.

**Effort.** 1.5 weeks. Needs a second one-way-until-mutual channel (the
symmetric `SyncPayload` must not carry it), a two-sided consent handshake
modelled on `SettlementProposal`, and a book layout that handles one voice, two
voices, and one-of-each-per-night.

**Guardrail.** Once, at the end, both consenting, all-or-nothing. No preview. No
partial exchange. No "share just this page". The moment it becomes a toggle in
settings it has destroyed the thing it exists to protect.

### B2. Letters in the book ★ build

**What.** A letter that opened on day 34 in Hội An gets its own spread in her
book, in place, with where and when *she* opened it.

**Why.** The letters are the emotional centre of the product and they currently
do not print. The book is a travel journal; it should be the record of the whole
trip, and a letter arriving in a strange city was part of the trip.

And the privacy structure holds perfectly: the letter is already on her phone,
`openedOn`/`openedPlace` are already hers alone, nothing travels back, and the
observer's copy of the book — if he gets one at all — has the letters he wrote
without a single fact about their reading. `SealedLetter` still has nowhere to
put a receipt.

**Effort.** 0.5 weeks — a new `BookSpread` case plus layout.

**Guardrail.** The observer never sees which letters made it into her book.

### B3. A print file that meets its own spec ★ build

**What.** Replace the raster pipeline (§1.6, §2.13, §2.14): vector text, correct
per-page bleed geometry, embedded fonts, CMYK with an output intent, PDF/X-1a
(more widely accepted than X-3 by print-on-demand services), off-main-thread
rendering with progress and cancellation. Then a physical proof from Blurb or
Lulu, because nothing has ever been printed.

**Why.** The book is the deliverable. A 1.5% anamorphic stretch and resampled
type are permanent in a physical object. And the app currently *labels* the file
with a standard it does not meet.

**Effort.** 1.5 weeks plus a two-week proof turnaround.

### B4. A colophon and an index of places ★ build (trivial)

A dedication spread the traveller writes on the last night, and a back-matter
index of every place with the pages it appears on — derived from the itinerary,
which already has all of it. 0.3 weeks. It is the difference between a printout
and a book.

### B5. Order the book from inside the app ⚠ build after a proof

Blurb and Lulu both have APIs. Currently `PrintHandoffView` ends at a
confirmation screen. Worth doing, but only after B3 has produced a file a
printer has actually accepted — the API is the easy half.

---

## Group C — The writing side

*Home mode is the feature that makes this product repeatable for anyone but
these two people, and it is half-built.*

### C1. Letters that can actually reach another phone ★ blocking, and not on the roadmap

**What.** A real `LetterDropTransport`. The protocol is already correct and
already addressed by `(tripID, recipient)`; what does not exist is any
implementation that crosses a device boundary (§2.7).

**Why.** Without it, home mode cannot do the one thing it is for. This is more
blocking than `expansion.md`'s 2.0, and `expansion.md` does not list it — it
describes the addressing as done (correctly) and moves on. Addressing without a
postal service is a well-designed envelope.

**Effort.** 1 week, alongside 2.0, since it shares the CloudKit setup.

**Guardrail.** The record name must carry the recipient, for the same reason the
filename does. A phone must not be able to *request* a box it isn't on, not just
decline to read it.

> **Built, minus the Developer account.** The transport already existed — Part 1's
> item 7 — and the guardrail was already met: `Letters-<tripID>-<recipient>`, so
> the wrong phone constructs a name nothing answers to. What C1 turned out to be
> was smaller and worse than "write a transport".
>
> **Nothing selected it.** `TripStore` built a `LoopbackLetterDropTransport`
> unconditionally while `SyncCoordinator` probed and chose, so
> `CloudKitLetterDropTransport` was constructed nowhere in the app. The three
> steps that switch iCloud on would have moved the *trip* to iCloud and left the
> letters writing to a file on the observer's own phone — home mode still with no
> postal service, which is the exact thing the class was written to end. That is
> one line, and it is now `chooseLetterTransport(cloudAvailable:)` with both
> branches checked.
>
> Four real bugs went with it: it could not create or find its own zone without
> the sync transport having run first; `modifyRecords` returns per-record results
> and does not throw, so a refused write read as a delivered letter; it used
> `.changedKeys` where `push` uses `.ifServerRecordUnchanged`; and it never called
> `translate`, so every `CKError` came out as nothing.
>
> **And the screens were claiming delivery.** `postLetters` was `try?`, so a post
> that never left the phone was indistinguishable from one that did — same haptic,
> same animation. Home mode printed "4 delivered", promised "her phone will open
> it", and headlined the seal confirmation **"It's out of your hands"** when the
> letter was in exactly one pair of hands. All of it now branches on whether the
> channel can actually deliver.
>
> Not done, and out of reach here: `DEVELOPMENT_TEAM`, the iCloud entitlement and
> the plist flag. Those three remain the only step, and they now switch the
> letters on as well as the trip.

### C2. A second person at home ★ build

**What.** More than one observer. Each has their own addressed box; none can see
another's letters or even that another exists.

**Why.** A trip has a mother, a best friend, a sibling. The model already
supports this — the box is keyed on `(tripID, recipient)` and nothing assumes
one writer — so what is missing is the fan-out and a way for a traveller's phone
to hold letters from more than one source without revealing the set of sources
to anyone.

This is also the honest answer to "who else would use this": the observer is a
lower-commitment role than the traveller, and it is the one that scales.

**Effort.** 1 week.

**Guardrail.** Observers never see each other. The traveller sees who a letter
is from when it opens, and nowhere else — the sealed list stays a list of
conditions, not a list of people.

### C3. The writer's own evening ritual ★ build

**What.** `LetterSchedule` already computes silences (`LetterDelivery.swift:238`
onward) — the stretches of the trip where nothing lands. Turn that diagnostic
into the thing that actually gets letters written: *"Nineteen quiet days after
Hà Giang. Want to put something in the middle of them?"* — once, gently, with
the condition pre-filled to the right day.

**Why.** §2.1 of `expansion.md` correctly identifies the evening prompt as the
highest-value item in the whole document, on the grounds that the journal is the
payload and something has to bring people to it. **The letters are the payload
of the other half of the product and nothing brings anyone to them.** The
observer's app currently shows him a board with a hole in it and no way to
respond.

Same discipline as the traveller's ritual: one prompt, no streaks, no counts, no
guilt. The board's own arithmetic decides when.

**Effort.** 0.5 weeks — the computation exists.

**Guardrail.** Never "she hasn't had a letter in 12 days", which makes the
traveller the subject of a metric. Always about the shape of the trip.

### C4. A letter that opens on something that happened ⚠ interesting, risky

**What.** Extend `LetterCondition` with conditions the writer cannot compute in
advance: *the first night you're both over budget*, *the first time you're
separated*, *the day after a night with no page*.

**Why.** The current conditions are all schedule-derived — a place, a day, a
stamp — so every letter is essentially timed. A letter that arrives *because
something happened* is a different and better object.

**Risk.** This is the first feature in this document that could turn tender into
creepy. "A letter that opens when you don't write" reads as surveillance the
instant it lands on a bad night, and the writer learning that the condition
fired is a read receipt through the back door.

**Verdict.** Prototype exactly one — *"the first night you're separated"* — and
show it to a real traveller before committing to any others. If it lands badly,
the whole branch is wrong.

---

## Group D — After the trip

*Currently a cliff. Day 61 shows an ending screen and then the app becomes a
list of eight numbers.*

### D1. Open the shelf ★ build first, cheapest high-value item in this document

**What.** Load `ShelvedTrip.snapshot` into a read-only `TripStore` and let every
existing screen render it. `TripStore.adopt(_ snapshot:)` already exists and is
already dead code (§2.2); this is mostly a read-only flag and a navigation
change.

**Why.** Because the docs already claim it works, because a keepsake app whose
keepsake cannot be reopened is not a keepsake app, and because the effort is
close to zero.

**Effort.** 0.5 weeks.

**Guardrail.** Genuinely read-only. No syncing, no notifications, no location.
`isLive` already gates all three.

> **Already built** — see Part 1's item 4. `ArchivedTripView` opens the frozen
> snapshot into a second `TripStore(storeKey: nil, snapshot:)` and pushes the
> book, the letters and the ledger under `\.isReadOnly`. `adopt(_ snapshot:)`
> wasn't wired up; it was deleted, and the tombstone comment says why — poured
> into the live store it would have fired 27 `didSet { save() }` handlers over
> the running trip.
>
> Three things were still wrong and are fixed:
>
> - A `HatchPanel` captioned *"the trail as it was · maps deleted, route kept"*
>   stood in for a trail that could not be opened, while `CloseTripView`
>   promised every screen would reopen. The trail now opens read-only — it was
>   already `isReadOnly`-aware — and `TripStatus.archived`'s doc moved with it.
> - Every reopened screen read **"not synced yet"**, which is true of a
>   throwaway store and false of a trip that synced for two months.
> - The reopened book still offered *"Send it to the printer"*, whose confirm
>   calls `place(_:)` on a keyless store: the screen said the order was placed,
>   nothing persisted, and the shelf row read "never printed" for ever. Export
>   stays — it mutates nothing and is the reason to reopen a finished book.

### D2. "A year ago today" ★ build

**What.** One notification a year after a page was written, with the page.
Nothing else — no summary, no "your year in travel", no share card.

**Why.** It is the thing that makes someone keep the app installed, and the
thing that makes them start a second trip. It is a query over the shelf plus one
notification. It costs almost nothing and it is the only feature here that acts
on its own after the trip ends.

**Effort.** 0.3 weeks.

**Guardrail.** Once a year per page, silenceable in one tap, never a digest,
never a montage.

### D3. Export and handover ★ build

**What.** One file — snapshot, photos, generated PDFs, plain-text journal — that
the traveller can put wherever they keep things. Plus the reverse: import it on a
new phone.

**Why.** Three reasons, in ascending order of seriousness. It is the disaster
recovery for §2.3 (photos are not in the backup). It is the migration path,
which currently does not exist — a new phone starts a new trip. And it is the
correct posture for an app that promises nothing goes to anyone's cloud: if you
hold the only copy, the user must be able to take it.

**Effort.** 0.7 weeks.

**Guardrail.** Plain formats. JSON and JPEGs in a folder, not a proprietary
blob. If the app dies, the trip should still be readable.

### D4. Search ⚠ build after D1

*"What did we do on day 12?"* — already in `expansion.md`'s Phase 3 and rated
correctly. It is worth much more once the shelf is browsable (D1), and close to
worthless before, since there is only ever one trip to search.

---

## Group E — The floor under all of it

These are not features and I am listing them anyway, because three of the items
above cannot ship without them and the roadmap treats one as smaller than it is.

- **Real pairing.** `CKShare`, or a QR invite carrying `tripID` plus a shared
  key. Two phones can currently both claim the same slot. A5, B1, C1 and C2 all
  depend on identity being real. `expansion.md` names this; it is under-scoped
  at "add `CKShare`" (§2.6).
- **A push channel.** Meeting points, Separated signals and letters that arrive
  only when the recipient opens the app are, for their purposes, undelivered.
- **An app lock.** Face ID on Papers, because the same tab tells you to hand the
  phone to a stranger (§2.10).
- **Conflict recovery.** The loser of a last-writer-wins merge is announced and
  unrecoverable. Keep the losing version for 24 hours and let the notice say
  *"put it back"*. `expansion.md:98-101` calls this a real gap and it is; it is
  also two days of work.

---

## Sequencing

**Step 1 is done.** It cost far less than 1.5 weeks, because A2 and D1 were
already built and A1 was half built — Part 2 was written against an older tree
than the one Part 1's priority table describes. What the step actually bought was
the country card, and four bugs the existing screens were carrying: three call
tiles breaking to "POLIC / E" at an accessibility size, a hatched drawing of an
unopenable trail, "not synced yet" on a two-month trip, and a print order that
reported success and changed nothing.

| | Ship | Why here |
|---|---|---|
| **1** | ✅ A1 country card · A2 edit/delete · D1 open the shelf | Three floors, ~1.5 weeks total, one of them fixes the only real defect |
| **2** | 2.0 real CloudKit + `CKShare` + ✅ **C1 letter transport** | The blocking half. C1 must ride along or home mode stays fictional |
| **3** | B3 print file + a physical proof | Longest lead time; start the proof turnaround early |
| **4** | B1 journal exchange · B2 letters in the book · B4 colophon | The ending, made true. B1 needs the pairing from step 2 |
| **5** | A3 cash · A4 receipts · C3 writer's ritual | Retention, once the foundations hold |
| **6** | A5 mutual Separated · D2 a year ago · D3 export | Needs push (step 2) |
| **7** | C4 event-conditioned letters · D4 search · B5 print API | Prototype first, all three |

**Roughly 11 dev-weeks to the end of step 4**, which is the point at which every
sentence currently printed in the app is true and the product has a real ending.

---

## What I would refuse

`expansion.md`'s existing refusals are right and I would keep all four — no
social features, no gamification of the journal, no analytics SDKs, no ports.
Four more:

- **Any AI trip suggestion, summary or "highlights of your trip".** The app's
  entire position is that the trip is the two people's, written in their own
  words. A generated summary of a journal is the exact opposite of a printed
  book.
- **Location sharing outside Separated.** A5 is deliberately coarse,
  time-boxed, mutual and non-retained. Any always-on version, any "see where
  they are" map, any history — that is a different app and a worse one.
- **Third-party expense splitting.** The moment the ledger has three or more
  people it needs a settlement graph, group invitations and permissions, and it
  becomes Splitwise with a nicer font. Two people is the product.
- **In-app messaging.** They have a phone. Adding chat would make the letters —
  which are slow, sealed and one-way *on purpose* — look like a worse version of
  the messaging tab sitting next to them.

---

## The one-sentence version

Part 1: the model layer is principled and well tested and the view layer is
full of prototype fixtures presented as facts, and the gap is widest on the
screens where being wrong matters most.

Part 2: finish the book — both voices in it, letters in it, a file a printer
will accept — make the shelf openable, give the letters a postal service, and
resist everything else.
