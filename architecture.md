# Architecture

How Đi Thôi is put together, and why. For whoever maintains or extends it.

Read [README.md](README.md) first if you just want to run it. This document
assumes you have.

---

## 1. Context

The app is a native SwiftUI implementation of two web prototypes —
`Đi Thôi - Classical Prototype.dc.html` and `Đi Thôi - Phase 2.dc.html`,
design-canvas documents for a two-person trip through Thailand, Vietnam and South
Korea. Both are static HTML: absolutely-positioned phone frames with hard-coded
copy and numbers. That last word is most of what this document is about — turning
transcribed numbers into computed ones, and deleting the sentences that could not
be computed.

The goals that shaped every decision below:

1. **Fidelity to a typeset design.** The prototype is editorial, not styled —
   it specifies exact points, tracking and sub-1.0 line-heights. The
   implementation reproduces that rather than mapping onto UIKit defaults.
2. **Real behaviour, not a click-through.** Numbers are computed from a live
   model, not transcribed. Adding an expense genuinely moves the budget.
3. **Offline-first.** The prototype's premise is "nothing here needs wifi".
   Exactly one thing reaches the network (exchange rates) and the app is fully
   usable if it never succeeds.
4. **The trip belongs to the travellers.** Dates, budget and home currency are
   inputs; everything else is derived.

### Constraints

| Constraint | Consequence |
|---|---|
| iOS 17+, iPhone only, portrait | No size-class branching, no iPad layouts |
| No third-party dependencies | Everything is Foundation, SwiftUI, UIKit |
| No backend, no accounts | Protected files for the trip and the shelf, plain files for photos, encrypted ones for scans, `UserDefaults` for rates and a sync timestamp |
| Only a free personal team on this machine | A personal team cannot hold the iCloud capability, so CloudKit is written but cannot run; a file-backed transport stands in |
| Design fonts aren't on iOS | System serif/mono substitution, isolated to 3 functions |

---

## 2. Layers

```
┌──────────────────────────────────────────────────────────────┐
│  Features/          39 screens, grouped by tab                 │
│  Arrival · Today · Letters · Trail · Money · Book · Papers     │
│  Home (the observer's three) · Trips (the shelf)               │
└───────────────────────────┬──────────────────────────────────┘
                            │ @EnvironmentObject
┌───────────────────────────▼──────────────────────────────────┐
│  Root/              RootView, MainTabs, HomeTabs              │
│                     ClassicalTabBar, DebugScreens (#if DEBUG) │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  Model/                                                       │
│    TripStore        — the one observable object                │
│    RatesService     ─┐                                         │
│    SyncCoordinator  ─┼─ owned by the store, re-published       │
│    LocationService  ─┘                                         │
│    Syncing          — payload, merge, transport protocol       │
│    SyncTransports   — CloudKitZone · Loopback · CloudKit       │
│    LetterDelivery   — the one-way channel, both transports     │
│    TransportConformance — semantics both sides must satisfy    │
│    TripShape · TripLibrary — origin, features, the shelf,      │
│                      and "a year ago today"                    │
│    TrailReplay      — the trail, day by day                    │
│    Book · Ritual    — the print plan, the evening clock        │
│    CountryFacts     — what is still true in five years         │
│    PhotoStore       — the book's photographs, backed up        │
│    ScanVault        — the scans: names, order, prune, delete   │
│    DocumentStore    — UIImage ↔ JPEG, and nothing else         │
│    DocumentCrypto   — AES-GCM and the Keychain                 │
│    Storage          — the one seam for defaults and container  │
│    WidgetBridge     — the one key the extension may read       │
│    Models           — value types, all Codable                 │
│    SampleTrip       — commented out; the app ships with no trip │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  Design/            Components (Rule, Mono, Panel, …)         │
│                     AppLock · ReadOnly                        │
└──────────────────────────────────────────────────────────────┘

     both targets ────────────────────────────────────────────┐
┌──────────────────────────────────────────────────────────────┐
│  Shared/            Theme        — tokens, type scale         │
│                     TripMark     — the mark, as arithmetic    │
│                     TripMarkView — the mark, in SwiftUI       │
│                     WidgetSnapshot — the one thing published  │
│                     DayWidgetView  — the four lockups         │
│                     QuickAction · MarkMomentIntent            │
│                                  — "mark a moment", no data   │
└───────────────────────────┬──────────────────────────────────┘
                            │ group.com.lovedones.dithoi
                            │ one key: dithoi.widget.v1
┌───────────────────────────▼──────────────────────────────────┐
│  DiThoiWidget/      WidgetBundle · DayWidget (timeline)       │
│                     MarkMomentControl (iOS 18)                │
│                     no model layer, and that is the point     │
└──────────────────────────────────────────────────────────────┘
```

`Shared/` is in both targets. `DiThoiWidget/` is in one, and it contains no
model type at all — the extension has no way to reach a `Leg`, a `Letter` or a
`JournalEntry` even by accident, because those types are not compiled into it.
That is the same trick `SyncPayload` plays with the journal, one process over.

There is no view-model layer. Screens read the store directly and hold only their
own transient UI state (`@State`: which sheet is open, what's typed so far).

`TripStore` is now ~1,800 lines, most of it computed properties, and that is
recorded as accepted debt rather than defended: every mutation invalidates every
view, and the seams visible in the `// MARK:` comments are clean. What blocks
splitting them out is that they all mutate one persisted blob. The cost is
redraws and reading time, not correctness.

### Why one store

Every screen shows a different projection of the same trip. A `MoneyView` model
and a `TodayView` model would both need the ledger, the dates and the rates, and
would have to be kept consistent. One `@MainActor` observable object with
computed properties gives consistency for free: there is no cached derived state
to invalidate.

`TripStore` is `@MainActor` because it is only ever touched from view bodies and
user actions, and because `RatesService` mutates `@Published` state from an
async context.

---

## 3. The model layer

### 3.1 Value types (`Model/Models.swift`)

`SyncableRecord` (`id` + `updatedAt` + `deletedAt`) is the contract for anything
that merges; `Array.merged(with:)` implements union-by-id-last-writer-wins once
for every conforming type.


Everything is a `Codable` struct or enum. Notable shapes:

**`Currency`** — an enum of the six currencies the app knows (`eur usd gbp thb
vnd krw`) carrying symbol, display name and decimal places. It deliberately does
*not* carry an exchange rate; see §3.3.

**`Expense`** — one line of the ledger. The interesting part is that it exposes
two rate-free properties and lets the store do the conversion half:

```swift
var shareOwedByOther: Double   // 0, 0.5, or a custom fraction
var balanceFactor: Double      // multiply by the home-currency value
```

`balanceFactor` folds together who paid, how it was split, and whether the line
is a purchase or a payment between the two travellers:

| kind | payer | balanceFactor |
|---|---|---|
| `.spend` | slot one | `+shareOwedByOther` |
| `.spend` | slot two | `−shareOwedByOther` |
| `.spend` | Both | `0` |
| `.transfer` | slot one | `+1` |
| `.transfer` | slot two | `−1` |

Positive means slot two ends up owing slot one. The store multiplies this by the line's
value in the home currency and sums — that single expression is the whole
balance calculation.

`Expense` has a hand-written `init(from:)` so ledgers saved before `kind` and
`customShare` existed still decode.

**`Segment` / `Leg` / `ItineraryDocument`** — the itinerary is stored as
**trip-day offsets, not dates**:

```swift
struct Segment { var title: String; var startDay: Int; var endDay: Int }
```

This is load-bearing. Because the travellers own the departure date, an
itinerary in absolute dates would need rewriting every time they moved it. Day
offsets mean the itinerary is invariant and the dates are computed
(`store.date(forDay:)`).

Now that it is editable, the *authority* is a segment's order and its length in
nights; `startDay`/`endDay` are derived. `ItineraryDocument.reflow()` rewrites
them all from day 1 after every mutation, so add, remove, reorder and resize are
each one mutation plus a reflow and the plan can never acquire a gap or an
overlap. The checks assert that invariant after all four operations.

**`TripPhase`** — `.before(daysUntil:)` / `.during` / `.after(daysSince:)`. Once
dates are user-set, "the trip hasn't started yet" is a real state the UI has to
handle rather than an impossible one.

### 3.2 `TripStore`

A handful of persisted inputs — `start`, `dayCount`, `budget`, `homeCurrency`,
`role`, `participant`, `names`, `origin`, `hasOpened` — plus the mutable
collections (`expenses`, `journal`, `letters`, `stamps`, `dayPlans`, `showCards`,
`documents`, `meetingPoint`, `settlements`, `separatedSince`, `ritualClock`,
`bookOrder`). Everything else is computed.

```swift
var dayNumber: Int          // clamped into 1...dayCount, so screens always draw
var phase: TripPhase
var spentHome: Double       // spending.reduce(0) { $0 + inHome($1) }
var budgetPerDay: Double    // budget / dayCount
var paceDaysAhead: Int
var netBalanceHome: Double  // Σ inHome(e) * e.balanceFactor
```

#### Persistence

One `TripSnapshot` struct encoded to a **protected file**,
`Store/dithoi.trip.v3`, written from a `didSet` on every `@Published` property.

**It used to be a `UserDefaults` key, and moving it is the single most
consequential change in this section.** A preferences plist is in every iCloud
and Finder backup, is plaintext, and carries only the default protection class —
readable whenever the phone has been unlocked once since boot. What was in there
was the journal, every letter in full, the moments, the ledger, and via
`TripLibrary` every archived trip as well. Meanwhile the passport scans had
AES-GCM *and* a backup exclusion. `PhotoStore.init`'s comment named that
asymmetry and fixed only the photographs. A file can carry a protection class;
a preferences key cannot, and that is the whole argument.

So `Storage.writeProtected`/`readProtected` put it in `Store/` with
`.completeFileProtection`. Two of the four things the app persists moved and two
did not:

| key | where | why |
|---|---|---|
| `dithoi.trip.v3` | `Store/`, protected | the journal, the letters, the ledger |
| `dithoi.library.v1` | `Store/`, protected | the shelf — every archived trip, entire |
| `dithoi.rates.v1` | `UserDefaults` | a public table of numbers |
| `dithoi.sync.lastSyncedAt` | `UserDefaults` | a timestamp |

`Storage.forget(_:)` clears **both** addresses unconditionally rather than
knowing which is which, so a key moving between them can never stale the reset.

Five things about it are load-bearing:

- **A protected write can fail, and a `UserDefaults` write could not.** It is
  refused while the phone is locked, which is reachable by backgrounding and
  locking a second later. So `TripWriter.write` *returns* whether it landed,
  `writeFailed` records it, the next foreground retries, and `DiThoiApp` holds a
  background-task assertion across `flushAndWait()` rather than sleeping a
  guessed two seconds. The widget snapshot goes out either way — it carries no
  private field and its container is unprotected on purpose, so there is no
  reason to hold the Home Screen back behind the trip's write.
- **The migration writes, reads back, and only then removes.**
  `migrateFromDefaultsIfNeeded` will not delete the old key until it has
  confirmed the new file reads. A remove on faith loses the trip whenever the
  write failed — and the write can now fail. Leaving the old copy for one more
  launch costs nothing.
- **Writes are coalesced.** Each `didSet` schedules rather than encodes; a burst
  costs one encode ~400 ms later, off the main actor. `DiThoiApp` calls
  `flush()` on the way to background, so that is not optional. It also changed
  what a *second* store sees — one built immediately after a mutation no longer
  finds it on disk, so any check wanting "the same trip on another phone" has to
  pass `snapshot:` explicitly rather than letting it re-read. A check that reads
  the file it just wrote must use `flushAndWait()`; `flush()` dispatches and
  returns.
- **The store key may be `nil`, meaning "never touch disk."** That is what lets
  the shelf open a closed trip: `init(storeKey: nil, snapshot:)` builds a second
  store that cannot write. An earlier `adopt(_ snapshot:)` that poured an archive
  into the *running* store would have fired thirty `didSet` handlers over the
  live trip; it was deleted rather than wired up.
- **"Nothing saved" and "saved but unreadable" are different answers.**
  `TripSnapshot.stored(key:)` returns `.none` / `.trip` / `.unreadable`. Both
  used to answer `nil`, and `init` seeded the sample over the top of a trip it
  had merely failed to decode. An unreadable one now sets `storageFault`, which
  makes `save()` refuse. On a protected file this stopped being hypothetical:
  "the device is locked" is exactly the case that reads as unreadable.

All thirty fields decode with `decodeIfPresent` and a fallback, and a check
strips each key in turn: adding a stored property without a default loses
somebody's two months. The memberwise init is synthesised, so `init(from:)`
lives in an extension rather than repeating the field list a fourth time.

`Storage` is the single seam for both `UserDefaults` and the container, which the
checks point at a scratch suite and a temporary directory. `Storage.shared` —
the App Group suite the widget reads — returns `nil` rather than
falling back, because `UserDefaults(suiteName:)` hands back a working object with
or without the entitlement, and a fallback would write widget data into the app's
own plist where nothing reads it and nothing complains.

#### Date shifting

The one genuinely subtle operation. `setStart(_:)` computes the day delta and
shifts *every dated record* by it — expenses, journal entries, letter
`writtenOn`/`openedOn`, stamp `earnedOn`, the meeting point and every place in
its history, the separated timestamp:

```swift
func setStart(_ newStart: Date) {
    let shift = Calendar.trip.days(from: start, to: normalised)
    guard shift != 0 else { return }
    expenses = expenses.map { var c = $0; c.date = moved($0.date); return c }
    // … same for every other dated collection
    start = normalised
}
```

Without this, moving the departure date leaves twelve days of spending
scattered around the calendar relative to a trip that now starts elsewhere. The
trip has to keep its *shape*.

`setEnd(_:)` only derives `dayCount`; it does not touch records. If the new
length is shorter than the itinerary, `itineraryOverrun` reports by how many
days and both the setup and itinerary screens say so — the app declines to
silently truncate the plan.

#### Settlement

Settling writes a `.transfer` expense rather than mutating a balance field:

```swift
func settle(note: String, in currency: Currency? = nil) {
    let balance = netBalanceHome
    guard abs(balance) > 0.005 else { return }
    expenses.append(Expense(…, payer: balance > 0 ? .two : .one,
                            kind: .transfer))
}
```

Because `.transfer` lines are excluded from `spending`, this moves the balance
to zero and provably leaves the budget untouched. That invariant is asserted in
the checks. `forgiveBalance()` is the same call with a different note — a
write-off and a payment differ only in whether money moved, and the ledger only
cares that the balance is gone.

> **History worth knowing.** The first implementation faked this with a
> mirrored pair of positive/negative expenses and left half the balance behind.
> The `.transfer` kind exists because that was wrong.

### 3.3 `RatesService`

No exchange rate is baked into the app's logic. `Currency` knows nothing about
value; `RateSnapshot` holds `[String: Double]` of units per euro, plus
`updatedAt` and a `source` of `.builtIn` or `.live`.

```
launch / foreground
        │
        ▼
 refreshIfNeeded()  ── fresher than 1h? ──► return, silently
        │ stale
        ▼
   open.er-api.com ──fail──► cdn.jsdelivr.net/…/eur.json ──fail──► keep cache,
        │ ok                        │ ok                            set
        ▼                           ▼                          lastAttemptFailed
   decodeERAPI                decodeCurrencyAPI
        └───────────┬───────────────┘
                    ▼
              make(from:updatedAt:)
              — rejects a payload missing ANY known currency
                    ▼
        @Published snapshot  →  UserDefaults "dithoi.rates.v1"
```

Design points:

- **Two keyless public endpoints, in order.** Both are unauthenticated and
  return a public list of numbers. Nothing about the trip is transmitted.
- **All-or-nothing decoding.** `make(from:)` returns `nil` if any currency is
  missing, rather than half-updating the table and leaving one currency on a
  stale rate while the others move.
- **Failure is not an error state.** A failed fetch sets `lastAttemptFailed` and
  changes nothing else. There is no alert. The only visible consequence is that
  the date under the numbers doesn't move.
- **Three-tier fallback:** live → last cached → table compiled into the binary.
  A phone that has never been online still converts, and says
  `"built-in rates · never updated"`.

`RatesService` is owned by `TripStore`, which re-publishes its changes:

```swift
ratesObserver = rates.objectWillChange.sink { [weak self] _ in
    self?.objectWillChange.send()
}
```

Views observe only the store, so a rate arriving mid-session redraws every
converted figure without any screen subscribing to a second object.

#### The disclaimer is a component

`RateStamp` renders `store.rates.disclaimer` — "rates updated just now",
"rates cached 9 hours ago", "built-in rates · never updated" — and forces a
refresh when tapped. It sits under every converted total (Today, Money, Settle
up, day detail, new expense). Trip setup shows the long form: each currency's
rate, the exact timestamp, and a manual refresh.

The reason this is a component rather than a string: a converted figure without
its age is a number pretending to be more current than it is.

### 3.4 Syncing (`Syncing.swift`, `SyncTransports.swift`, `SyncCoordinator.swift`)

The design is built around two people sharing one trip. Making that true meant
answering three questions, in order of how much they matter.

#### What crosses, and what never does

`SyncPayload` carries the `tripID`, the settings, the names, the itinerary, the
expenses, the stamps, the meeting point, the places this trip has met before,
the settlement proposals, the day plans and the show-this cards.
The last two joined when they became things either traveller can write — the
sharing screen says "money, **plans**, the trail and the meeting point are
shared both ways", and two people editing the same day on two phones with no
merge would make that false. It does **not** carry journals,
letters, moments or documents — and not by filtering them at the edge, but by
their not being fields on the type at all. `Moment` and `TravelDocument` go one
better: with no `updatedAt` neither can conform to `SyncableRecord`, so neither
can be `merged(with:)` and there is no way to union one into a payload even
deliberately. A reflection check pins
the payload's field list to a written-down array, so anything joining it is an
edit somebody made on purpose. The design promises the journals stay private until the
books print and that the letters exist on one phone only. Sync is exactly where
a promise like that gets broken by an absent-minded `+ journal`, so the type
system is doing the remembering.

`TravelDocument` is the newest of those and the argument is the same one twice
over. Its `fields` hold passport and policy numbers, so the missing `updatedAt`
keeps it off the wire — and the *also* missing `deletedAt` keeps it off the
disk. A tombstone exists so a delete can beat a concurrent edit across two
phones; there is no second phone for a document, and a tombstoned row is a
passport number still stored under the word "deleted". `deleteDocument` really
removes, and takes the scans with it. Two reflection checks hold both halves.

#### How two copies merge

Merging is pure and lives in `SyncMerge.merge(local:remote:as:)` — no network, no
I/O, fully testable.

| Data | Rule | Why |
|---|---|---|
| expenses, stamps, settlements, day plans, show-this cards | union by id, later `updatedAt` wins | append-only in practice, so a union never loses a line; `deletedAt` is a tombstone so a delete can beat a concurrent edit |
| settings | whole-document LWW | dates/budget/currency are set together on one screen; a half-and-half result is a trip neither chose |
| itinerary | whole-document LWW, loser announced | per-segment merge of an ordered list with day offsets produces nonsense |
| meeting point | LWW, **always** announced | a silently replaced meeting point is how two people end up in different parts of a city |
| meeting-point history | union by folded `place`, later `setAt` wins | there is one place they are standing tonight, but a gate either of them walked to is worth offering back on day 40; losing the LWW round is not the same as never having been there. No id: two phones that both typed "the bridge" mean the same bridge |

Every overwrite that a person would want to know about becomes a `SyncNotice`,
shown as a dismissible banner over the tab bar.

#### Settling, which needs both of them

The one operation neither traveller may do alone, so it is a real two-phase
commit rather than a button that looks like one:

```
Slot one                      shared                      Slot two
──────────────────────────────────────────────────────────────────
proposeSettlement()  ──►  SettlementProposal
                          (pending, awaiting: slot two)  ──►  sees it
                                                            │
                            confirmSettlement()  ◄───────────┘
                                    │
             both apply ◄───────────┴──────────► both apply
             Expense(id: proposal.id, kind: .transfer)
```

The transfer borrows the **proposal's id**, so both phones applying the same
settlement converge on one ledger line instead of two. `applyConfirmedSettlements()`
is idempotent and asserted to be.

`SettlementProposal.debtor` is stored rather than inferred from `proposedBy` —
either traveller can raise a settlement regardless of which way the balance runs.

#### Transport

`SyncTransport` is a dumb pipe: `push(payload)`, `pull() -> payload?`. Keeping
merge out of the transport is what makes the interesting half testable. Conflict
is reported (`SyncError.conflict`), never resolved — `SyncCoordinator` re-runs
the round. Resolving inside the transport would put the one pure function behind
a network call.

- **`LoopbackSyncTransport`** — a second phone that lives in a file. The model
  checks point two `TripStore`s at one box and assert convergence: two expenses
  added offline both survive, the later meeting point wins and is announced, an
  itinerary edit crosses over, and a journal entry does not.
- **`CloudKitSyncTransport`** — complete, compiles, and **never runs**.
  `isAvailable` reads a bundle flag that is `NO`, and every call checks it,
  because touching `CKContainer` without the entitlement traps.

**Sharing needs a custom zone and a `CKShare`, not the private database.** This
used to write one fixed record named `trip` to `privateCloudDatabase`, which is
scoped to a single iCloud account — one person's devices syncing with each other
and nothing at all between two people, while every screen said "shared with
the other phone". Three things the old shape could not provide: a custom zone,
default-zone records cannot be shared; a `CKShare` on a root record, which is
what produces an invitation; and reading through `sharedCloudDatabase` when this
phone is the participant rather than the owner. The record is keyed off
`tripID` — one record per trip holding the whole payload as JSON, so the merge
stays ours and one write is atomic with no partially-applied trip.

**`CloudKitZone` answers "where does this trip live", once.** Both CloudKit
transports need it and they used to answer it differently: the sync side located
by looking for the trip *record*, and the letter side enumerated every zone
looking for one named `DiThoi` — which meant a letter could only be posted if the
sync transport had already run and created it. The zone name tells you where to
look; the trip record tells you the trip is actually there. It also owns the
availability flag and the `CKError` → `SyncError` translation, both of which
existed twice.

Only the trip may pass `creatingIfNeeded: true`. The letter poster is the
observer, who is a *participant*: minting a zone for them would create one in
their own private database and post into it, a write that reports success into a
box no traveller can ever read.

#### The switched-off contract

`TransportConformance` writes down the semantics both implementations of each
protocol must share, runs them against the ones that execute, and leaves them
pointed at the ones that don't. Three suites — `sync`, `letters`, and `inert`.

`inert` is the one worth explaining. On a machine with no developer team the
CloudKit pair is only ever in one state, and the only thing previously checked
about it was that `isAvailable` was false. But callers branch on the *shape* of
the failure, not the flag: a write must throw, and throw `.unavailable`, because
`SyncCoordinator` reads `isFatal` and `postLetters` records the sentence; a read
must return `nil` rather than an empty `LetterDrop`, because an empty drop says
"there is a box here and it is empty", which is the one thing a non-recipient
must never learn.

> **Not verified.** Without a developer team neither CloudKit transport has ever
> executed. The merge they feed is verified and their semantics are pinned; the
> pipes are not. That is weaker than running them and this document is not
> pretending otherwise.

### 3.5 Files on disk

Everything the app keeps is a file except a rates table and one timestamp
(§3.2). The trip and the shelf are covered there; what follows is the two stores
that sit outside the snapshot entirely — and they answer "who else can read
this" in opposite directions. The photographs are backed up on purpose; the
scans are encrypted and excluded on purpose. Neither is ever synced.

**`PhotoStore`** keeps a downscaled copy plus a 320px thumbnail in Application
Support. A `PHAsset` identifier would have been cheaper, but the book is the
artefact the whole app builds toward and it has to survive them tidying their
camera roll six weeks later. The file-handling half is Foundation-only and the
`UIImage` half is behind `#if canImport(UIKit)` — that is what keeps the model
layer buildable for macOS, which is what lets `run-checks.sh` exist.

The long edge is `BookSpec().fullBleedPixels`, not a number. It used to be 2048
against a book that wanted 2,475, so every photo the app could produce measured
248 dpi and `PrintReadiness` warned that *every* page would print soft — a
warning that is always true and therefore says nothing.

These are **backed up**, unlike the scans below. Excluding them was never
privacy: the photographs are irreplaceable, and the journal text and all twelve
letters were sitting in the backed-up preferences plist the whole time, so the
protection was pointing the wrong way. The flag is set to `false` explicitly
rather than left off, because an install that ran the old build still carries it.

**The scans** are passport and visa pages encrypted with AES-GCM, key in the
Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), excluded from
backup, never synced. The Papers screen promises "never uploaded, never in
anyone's cloud — including the one at home", and scans of a passport are the one
thing here that would genuinely hurt to leak.

They are handled by **three** types, and the split is entirely about what
`run-checks.sh` can compile. That script builds `Model/` for macOS, so anything
importing UIKit has to be excluded — and for a long time the exclusion was
`DocumentStore`, which meant the one subsystem in the app whose silent failure is
*unrecoverable* was also the only one with no coverage. The fix has now been
applied twice, in the same direction:

| | imports | checked | holds |
|---|---|---|---|
| `DocumentCrypto` | Foundation, CryptoKit, Security | yes | seal/open, the Keychain, the `errSecItemNotFound` distinction |
| `ScanVault` | Foundation | yes | the directory, file names, page order, `prune`, `deleteAll` |
| `DocumentStore` | UIKit | **no** | `UIImage` ↔ JPEG, and nothing else |

Only the last genuinely needs UIKit, and it is now small enough to read in one
sitting. The rule to keep: anything expressible without `UIImage` belongs next
door where a check can reach it.

**Page order is parsed, not lexicographic.** A page is
`<document uuid>-<index>.scan`, zero-padded to three digits, and `pageIDs`
sorts on the *parsed* index. Inside the padding the two agree, which is exactly
why a check at twelve pages proves nothing — past it, `"1000"` sorts before
`"999"`. `nextIndex(for:)` is one past the highest rather than the count, for the
same class of reason: the two agree only until something is removed from the
middle, after which a count collides with a name that already exists and
overwrites the page it collided with.

**Nothing pruned these before.** `resetTrip` cleared `documents` and pruned the
*photographs*; `ScanVault.deleteAll(for:)` had no callers anywhere in the app. So
every encrypted page ever written stayed on the phone, referenced by nothing, for
good — invisible only because until now no document could be made by hand.
`TripStore.pruneOrphanedScans()` runs on every wake beside
`pruneOrphanedPhotos()`, and both guard on `persists` so the shelf's keyless
reader — holding a *different* trip's ids — cannot take the live trip's files
with it.

**The two prunes take deliberately opposite sets, and each doc comment says so.**
`referencedPhotoIDs` walks the shelf as well as the live trip, because a closed
trip's book is printed from those photographs. `referencedDocumentIDs` is the
live trip alone, because closing a trip *deletes* its scans before the snapshot
is frozen — so no archived snapshot can name one, and adding the shelf there
would preserve exactly what the close destroyed. Read both before changing
either; the next person to see them side by side will otherwise "fix" one to
match the other.

**Closing a trip is the one operation in the app that destroys something
while keeping the trip.** Throwing one away, the other answer on the same
finishing sheet, destroys all of it.
`closeTrip()`'s doc used to open "Nothing is deleted, so it can be reopened and
read", and three screens repeated the promise. It now deletes the scans and
clears every typed value before `library.archive`, so a shelved trip carries no
passport number and no encrypted page. The field *labels* survive, so a reopened
document still reads "Passport · Number · Expires" with "emptied" where the
answers were — a row that simply vanished would break the shelf's "every screen
reopens" promise quietly, which is worse than breaking it out loud.

What it costs is counted once, on the store:

```swift
struct PapersLoss: Equatable { var documents: Int; var scans: Int }
var papersLostOnClose: PapersLoss?     // nil when there is nothing to lose
```

Both the finishing sheet's panel and its confirmation read that. The shelf's
old new-trip flow, since deleted, had been promising "nothing deleted" all
along. This is the
`adoptionDiscardsLetters(becoming:)` shape, and for the same reason: when a
dialog computes its own version of what a guard is about, the two drift, and they
drift in the same direction so nothing catches it.

**Getting a page in.** Three sources, offered as a choice rather than a fallback
— `DocumentCapture` used to be "the scanner if there's a camera, the photo picker
if there isn't", which is the wrong shape once a visa arrives as a PDF and a
boarding pass is already in the camera roll.

- `VNDocumentCameraViewController`, for photographing one.
- `PHPickerViewController` with `selectionLimit: 0`. **Results are gathered into
  fixed slots, not appended.** `loadObject` completions arrive whenever each
  finishes, so appending as they land shuffles a passport's pages: nothing
  missing, nothing crashing, silently wrong — the same class as a waypoint lookup
  answering `.first`.
- `.fileImporter` → PDFKit, in `Features/Papers/DocumentImport.swift`. The source
  file is opened in place under a security-scoped URL, rasterised at the vault's
  own 2400px long edge, and let go. **It is never copied anywhere.** A copy in
  `temporaryDirectory` would be an unencrypted passport in a folder emptied on no
  schedule an app may rely on — the bug the exported book already had once.

Every route out reports, including cancellation. The picker branch used to drop
`onCancel` entirely and `PHPickerViewController` dismisses itself, so cancelling
left the caller's `isPresented` set over an empty screen — on the only path a
simulator can take, and therefore the path every screenshot of this flow takes.

### 3.6 `LocationService`

When-in-use only, and asked for by the act that needs a position: Separated
switching on (tracked, and stopped when they find each other), keeping a moment,
and dropping a pin (one fix each, `requestOnce()`). Never at launch. No
background mode and no always-on authorisation — by design, matching Separated's
promise that position is *shared* "only while Separated is on"; a moment's
coordinate stays on the phone.

The trail uses `requestOnceIfAllowed()`, which does nothing until somebody has
already said yes. The trail is opened on any afternoon and is never the moment
to ask. What it draws from the fix — the "you are here" mark and "180 km from
here" under the next stop — appears only on a traveller's live trip, from a fix
under fifteen minutes old, and the distance only when the next waypoint has a
position. On the observer's phone it would put their kitchen on somebody else's
trail. Distance is `Geo.kilometres`, the one great-circle formula, which
`Stamp.kilometres(to:)` also calls.

Provides distance and a spoken-word bearing ("770 m south-west of the meeting
point"); with no fix, Separated falls back to the written directions it had
before location existed.

### 3.6a Moments

`Moment` is a record of standing somewhere, kept on this phone only — no
`updatedAt`, so it can never be merged into `SyncPayload`. Three things about
it are not obvious:

- **The day is the true one.** `TripStore.dayNumber` clamps to 1, so a moment
  kept before departure used to be filed as day 1 in the first stop's city.
  `addMoment` stamps `trueDayNumber` (zero or below) and an empty city, and
  `cityNow` never writes the em-dash a label uses. Readers go through
  `Moment.caption` and `place`, which say "before we left" and drop the
  separator when there is nowhere to name.
- **Deleting removes the record, not the photograph.** The file is left to
  `pruneOrphanedPhotos()`, which runs on every wake and knows every live and
  shelved reference. That is what makes the ten-second undo possible:
  `restoreMoment` puts the same value back. The offer is withdrawn when the app
  leaves the foreground, because the next wake is the prune.
- **The full list groups by consecutive runs** (`Moment.groupedByStop`), keyed
  on what each moment recorded rather than on the itinerary — Bangkok out and
  Bangkok home are two groups. A group's id is borrowed from its first moment,
  never minted in the build.

- **An unfinished moment is derived** (`isUnfinished`: no words, no photo) —
  what one-tap "just keep the spot" makes. `printedMoments` leaves them out, so
  the book's pagination agrees by construction, and `PrintReadiness` names them.
- **A moment can be filed under a stamp's city** (`addMoment(city:)`), which is
  how "Keep a moment here" on the stamp screen files it.

`addMoment`, `updateMoment`, `deleteMoment` and `restoreMoment` all refuse the
observer and a closed trip; the shelved snapshot names those photographs.

**The replay and the memories are derived, and checked.** `TrailReplay`
(`Model/TrailReplay.swift`) turns earned stamps and moments into a frame per
day; its last frame's kilometres are `kilometresTravelled`'s by construction,
since both call `TrailReplay.kilometres(along:)`. `TripLibrary.memories(on:)`
walks the shelf for records on this date in earlier years, memoised per day.
Tonight's page borrows from `momentsToday` through `PhotoStore.duplicate`, a
copy under a fresh id, because two records sharing one photo file lose it the
first time either swaps.

**Arriving is suggested, never awarded.** `nearNextStop(latitude:longitude:)`
answers the next waypoint inside `TripStore.arrivalRadiusKm` and refuses
everything `arrive(at:)` would, plus before departure. Today and Trail ask it of
a fix under fifteen minutes old that the app already had permission for; both
lead to Trail's existing confirmation (`ArrivalRequest`, §5).

### 3.7 `SampleTrip` — commented out

The app ships with no trip inside it. `DiThoi/Model/SampleTrip.swift` keeps the
old seed content as a comment block: nothing in it is compiled, referenced or
reachable, and `TripStore.init` seeds a blank trip when there is nothing saved.

The checks build their trip from `Tools/CheckTrip.swift` instead, which lives
outside the app target and so can never ship. **Nothing there holds a calendar
date** either — every record is a day offset materialised against the departure
date:

```swift
static func expenses(start: Date) -> [Expense]
static func letters(start: Date) -> [Letter]
static func stamps(start: Date) -> [Stamp]
static func snapshot(now: Date) -> TripSnapshot
```

`CheckTrip.defaultStart` is *today minus 11 days*, so the fixture opens on day
12 — far enough in to have a ledger and earned stamps, far enough from the end
to still have unearned ones ahead.

---

## 4. The design layer

### 4.1 Tokens (`Shared/Theme.swift`)

A direct transcription of the prototype's CSS custom properties: the neutral and
accent ramps, `--space-1…8` (the odd 4.6/9.2/13.8 values are the original's), and
the three radii. The accent ramp was `oklch()` in CSS and was converted to sRGB
offline; the hex values are the conversion results, not eyeballed.

### 4.2 Type, and Dynamic Type

The problem: the design specifies exact points (78pt masthead, 62pt amount,
9.5pt labels), and iOS users expect text to obey their text-size setting. Fixed
sizes and Dynamic Type appear to be in conflict.

The resolution — `Typeface.heading(38)` returns a **`TypeSpec`**, not a `Font`:

```swift
struct TypeSpec {
    var role: Role           // .heading | .body | .mono
    var size: CGFloat
    var weight: Font.Weight
    var isItalic: Bool
    var ceilingOverride: CGFloat?
}

extension View {
    func font(_ spec: TypeSpec) -> some View { modifier(ScaledFont(spec: spec)) }
}
```

`ScaledFont` reads `@Environment(\.dynamicTypeSize)` and resolves the spec.
Because the environment read happens inside a `ViewModifier`, SwiftUI invalidates
and redraws on a text-size change — the guarantee you don't get from computing a
`Font` once. And because the overload is on `font(_:)`, **every existing call
site scaled without being edited**.

Growth is capped by size (`TypeSpec.growthCeiling`):

| size | ceiling | reasoning |
|---|---|---|
| < 14pt | 2.4× | labels; take the setting in full |
| < 19pt | 2.0× | body copy |
| < 29pt | 1.6× | subheads |
| < 47pt | 1.35× | headings |
| ≥ 47pt | 1.2× | display; 78pt × 3.1 would be 240pt |

Shrinking is never capped. `.capped(at:)` tightens further for type in a fixed
slot — the five tab-bar labels use 1.35× because at 2.4× they collide rather
than merely taking more room.

The three `Text`-typed placeholder `prompt:` arguments can't take a
`ViewModifier`, so they call `spec.resolved(for: typeSize)` against the same
environment value by hand. They are the only exceptions in the codebase.

**Font substitution.** Cormorant Garamond, Lora and IBM Plex Mono don't ship
with iOS. `TypeSpec.design` maps the two serif roles onto New York (separated by
weight and tracking where the original separates them by family) and the label
role onto SF Mono. Bundling the real faces means changing `design` and nothing
else.

### 4.3 Components

`Design/Components.swift` holds the recurring pieces: `Rule`, `Mono`, `Display`,
`Aside`, `Screen`, `OutlineButton`, `Panel`, `Tag`, `Chip`, `SegmentTile`,
`DetailRow`, `HatchPanel`, `RateStamp`.

`Display` is worth a note. The prototype sets display type at a line-height
below 1.0 — the lines nearly touch, which is most of what makes it read as a
masthead. SwiftUI's `lineSpacing` can only *add*, so `Display` splits on `\n`
and stacks the lines in a `VStack` with negative spacing proportional to the
resolved point size.

`Screen` is the standard scaffold: an optional context word top-right (the
system draws the real time, so the prototype's fake clock is dropped), then a
gutter-padded `ScrollView`.

---

## 5. Navigation

A custom bar, and no `TabView`:

```
RootView
├─ hasOpened == false → ArrivalFlow   (SetupStep.steps(for:), Model/SetupSteps.swift)
│                        first launch → hello → who → …
│                        next trip    → destination (who? on "change") → dates → …
│                        packed  → inside (manifest + adjust) → done
│                        blank   → dates → itinerary → invite? → done
│                        observer→ writingTo → inside (their three rows) → done
├─ hasOpened, !isLive → ShelfView, between trips
│                        └─ "Start the next trip" → beginNextTrip() → ArrivalFlow
├─ hasOpened, isObserver → HomeTabs
│                        └─ home · letters · their trail (read-only)
└─ hasOpened            → MainTabs
                        ├─ NavigationStack per tab
                        │   Today · Trail · Money · Book · Papers
                        ├─ tabs filtered by TripFeatures
                        ├─ ClassicalTabBar (dot + uppercase label)
                        ├─ fullScreenCover: SeparatedView
                        └─ sheet: MomentComposerView, when QuickActionInbox
                           says "mark a moment" (read by RootView, which drops
                           it for the observer, onboarding or a closed trip)
```

**"Mark a moment" from outside the app goes through App Intents, not the icon's
quick-action menu.** `UIApplicationShortcutItem` reaches a scene-based app only
through a scene delegate, and naming one replaces the one SwiftUI installs —
every screen launches blank (§3.4). `MarkMomentIntent` (`openAppWhenRun`) sets
`QuickActionInbox.pending` and nothing else, so no trip data reaches the widget
extension it is also compiled into. `RootView` reads the inbox, not `MainTabs`,
so that a request it cannot act on is *dropped* rather than left waiting — a tap
made during onboarding would otherwise pop the composer when onboarding ended.
`take()` guards before it clears, the `InvitationInbox` lesson.

Today's arrival nudge crosses tabs through `ArrivalRequest`, an environment
value `MainTabs` owns: "Drop the pin" sets the stamp and selects the trail, and
`TrailView` turns it into the confirmation it already has — re-checked against
`nextStamp`, since a sync round can reorder the trail between the two taps.

The Trail tab pushes through one `navigationDestination(item:)` over
`TrailDestination` (the whole map, every moment), never two stacked
`isPresented:` destinations, which is how `TodayView` once had a dead push.

The tab bar is hand-built because it *is* the design — a 5pt dot over a 9.5pt
uppercase mono word. `UITabBar` cannot be styled into that shape. Each tab owns
a `NavigationStack`, so per-tab back stacks work as expected.

Presentation follows the weight of the moment:

| Pattern | Used for |
|---|---|
| `NavigationLink` | Itinerary, day detail, documents, letters, sharing, setup, the whole trail, every moment |
| `.sheet` | Add expense, settle, letter reader, journal entry, meeting point, document editor, a moment |
| `.fullScreenCover` | Stamp earned, Separated, Show-this cards, scan viewer, adding a page |

The full-screen covers are the three screens that take over the phone — a stamp
being earned, the 2am "we lost each other" screen, and holding the phone out to
a stranger. Two of them are dark, deliberately, in an otherwise single-palette
light app.

### What the lock is in front of, and why it is a rule

`AppLock` gates two screens, not the tab they live on. Papers itself is
deliberately open: it holds the meeting point and the show-this cards, which
exist to be *handed over*, and a lock in front of those hurts the person it is
meant to protect.

The rule is one sentence with no flag in it: **anything that shows or accepts a
document's field values wraps its own `body` in `Locked`.** That is
`DocumentDetailView` and `DocumentEditorView`. A "type your passport number"
screen reachable from an unlocked tab would put the vault's contents on the wrong
side of the gate — including everything already in it, the moment somebody
tapped `edit`.

`Locked` brings `privacyCovered()` with it, which the editor needs on its own
account: a sheet is presented *above* the view that spawned it, so the cover over
the screen underneath does not sit over this one. `ScanViewer` learned that first
and carries its own for the same reason.

Two screens under one gate meant `AppLock.unlock()` needed a re-entrancy guard.
It already returned early when `isOpen`, but a `Locked` sheet over `Locked`
content is two `.task` blocks that can both start while the lock is still shut,
and `LAContext` will put up two prompts one behind the other.

**`isReadOnly` is not "this trip is closed", and using it as such is a live
trap.** That flag is injected by the shelf's reader and by home mode.
`closeTrip()` sets neither. The root moves to the between-trips shelf, but a
sheet over the tabs can outlive the close by a moment. Gating the papers on the flag alone left "tap to
import one" and `edit` on a document whose values had just been deliberately
erased. The gate is `!isReadOnly && store.isLive`: the flag is the courtesy,
`isLive` is the state.

### One build, three roles

The prototype shows two physical phones. Here the answer is `participant` —
either traveller, or the observer who stays home and writes — asked as the *first*
question in onboarding rather than hidden in settings, which is what made home
mode reachable at all.

`lettersVisible` is deliberately **not** an identity test. It is
`features.letters && !letters.isEmpty` — a question about what is on this phone,
not about who is holding it. The letters and *every reference to them* disappear
from the other side, and an empty letterbox would itself be a reference to a
channel that may not exist. For the same reason no screen anywhere says "no
letters on this phone"; what each side can see belongs on the sharing screen,
which is the screen that is about that.

The three tab sets are filtered from `TripFeatures`, so a feature that is off is
off *everywhere* — the tab disappears rather than showing an empty screen that
reminds you what this trip isn't doing.

---

## 6. Verification

There is no simulator in CI and no XCTest target. Verification is two things:

### `./Tools/run-checks.sh`

Compiles everything in `DiThoi/Model/` and `Shared/` plus `Tools/VerifyTrip.swift`
for **macOS** and runs 980 assertions — no simulator, about five seconds. It
covers trip shape, rate conversion and round-tripping, budget derivation, the
date-shift invariants, itinerary reflow after all four edit operations, the
settlement handshake, split maths, expense edit/delete/undo, letter gating and
addressing, journal bookkeeping, the book plan, the ritual clock, the country
table, the shelf, the mark's geometry, the vault's key handling, moments — the
true day before departure, delete and undo against the prune, grouping by stop,
the one distance formula — the move of the
trip off `UserDefaults` — that a plist written by the old build migrates intact
and the old copy survives until the new one reads back — and the papers: that
they cannot reach the payload, that closing a trip clears them, that the dialog's
count matches what the close removes, and that a prune keeps what the live trip
names and nothing else.

It also runs **two stores against one loopback box** — a second phone — and
asserts they converge: two expenses added offline both survive, the ledgers
match by id, a delete beats a concurrent edit, the later meeting point wins *and
is announced*, an itinerary edit crosses over, and a journal entry does not.

The file list is a **glob minus a written-down exclusion list**, not a hand-kept
enumeration. It used to be by hand, which meant a new file in `Model/` was picked
up automatically by Xcode and silently *not* checked — coverage dropping with
nothing failing. The default is now to be checked, and every exception is argued
for at the top of the script.

This is possible only because the model layer imports nothing but `Foundation`,
`Combine`, `CoreLocation`, `CloudKit` and `CryptoKit` — no SwiftUI, no UIKit,
with one written-down exception (`DocumentStore`, because turning a scan into
JPEG bytes means `UIImage`). That exception used to cover the encryption and the
file bookkeeping too; both have since moved out to `DocumentCrypto` and
`ScanVault`, which is most of §3.5.
Keeping it that way is worth some effort: it is why `ItineraryDocument` has its
own `moveElements(fromOffsets:toOffset:)` instead of SwiftUI's `move`, why
`PhotoStore` splits its file handling from its image handling, and why
`Shared/TripMark.swift` does the mark's geometry in `Double` with no
`import CoreGraphics`.

Two seams make the untestable testable: `RatesService.applyForTesting(_:)` swaps
in a known snapshot so the money maths runs without the network, and
`TripStore.now` is a clock you can hand it — `Date()` appears nowhere else in the
class, without which midnight, the last day, a DST boundary and a flight into
another zone are untestable by construction.

### `Root/DebugScreens.swift`

A `#if DEBUG` launch-argument router:

```bash
xcrun simctl launch <device> com.lovedones.dithoi -resetTrip -screen money
```

67 routes. `-day N` moves the trip to that day and may be zero or negative.
`moments`, `momentslist` and `trailmap` seed six moments across days and stops
and, with `-seedItinerary`, five located waypoints with two earned — nothing else
makes a stamp, so no map had ever been photographed with a trail on it.
`markmoment` is the only route not in `DebugScreenHost`: it goes through
`RootView` so the quick action's real path is the one photographed.
Verified absent from Release: the Release build succeeds and `strings` on the
binary finds no trace of the flag.

The MCP simulator integration now works, so screens can be *driven* rather than
only photographed — which is how context menus, confirmation dialogs and the undo
banner were first exercised, all having shipped untouched.

Three traps in the routes themselves, all learned the hard way:

- **A screen nothing can reach is a screen nothing checks.** Today's `notYet`
  branch had never been photographed because `-day` refused values below 1. One
  line to fix, and it immediately showed a bug.
- **A route that reaches the screen can still be in the wrong state.** Every
  home-mode route drew its view without setting `participant = .writer`, so for
  the whole of Phase 2 they photographed the observer's screens with a
  *traveller's* store behind them. Nothing on those screens branched on
  `isObserver`, so it was invisible — until the letters learned to say whether
  they had been posted. Home mode is a store state, not a view.
- **A route that reaches the screen can still miss the branch worth looking at.**
  `-screen finish` (formerly `closetrip`) launches with `-resetTrip`, and the papers warning on that
  screen only exists when there are papers to lose — so the route photographed
  the screen with the sentence absent, every time. It seeds documents now. The
  same argument applies to any conditional warning: a route that can only reach
  the quiet branch signs the screen off having never shown the loud one.

86 screenshots — every screen, plus accessibility variants — are in
[Screenshots/](Screenshots).

### What running it actually caught

The pattern across every round is the same: **assertions catch arithmetic,
screenshots catch what a reader concludes.** Eight times now a suite has gone
fully green over a screen that was wrong — 149 assertions past an invisible
"sealed" dot and four overlapping labels; every mark-geometry assertion past a
green stub painted before departure; 45 editor assertions past "SONGKRA / N"
broken across a word; and most recently 757 past four separate defects on the
papers screens.

From the papers round, which is the clearest illustration of the split — every
one of these sat over checks that correctly proved the strip, the prune and the
ordering all worked:

- **"Close ?"** — a bare question mark where a blank trip's name goes, which is
  the meeting point's `". Agreed at 00:53."` exactly, four years of copy later.
  `store.displayName` is the one answer now.
- **"Delete a single page, photo or letter"** directly beneath "Empties 3
  documents and 3 scans". It always meant a journal page; it stopped reading that
  way the moment the panel above it learned the word "scans".
- **"Blank p…"** — a field label truncated *in an editable field*, because it was
  capped at an absolute 130pt that doesn't grow with the type factor. Visible
  only at an accessibility size, and the truncation hides what the person typed
  rather than merely abbreviating a heading.
- **A closed trip still offering "tap to import one" and `edit`** over three
  fields reading "emptied" — the `isReadOnly`-is-not-`isLive` trap in §5.

From the round before that:

- **"POLIC / E" and "MEDIC / AL"** — Vietnam's three emergency call tiles broke
  mid-word at an accessibility size, over three tiles of three different heights,
  on the screen where a misread number matters most. `CallTileRow` stacks above
  the threshold and both the country card and the dark Separated screen draw
  through it, so neither can regress alone.
- **A hatched drawing of a trail that could not be opened** sat on the archived
  trip screen while the close screen promised "you can open every screen of it
  whenever you like".
- **"Not synced yet" on a two-month trip** — true of the shelf's throwaway store,
  false of the trip. `ScreenContext` now reads `\.isReadOnly` and draws nothing.
- **A print order that reported success and changed nothing**, because
  `place(_:)` on a keyless store sets `bookOrder` in memory and the shelf row
  went on reading "never printed".
- **"It's out of your hands"** headlining the seal confirmation for a letter that
  was in exactly one pair of hands.

From earlier rounds:

- **`@StateObject` is constructed before `init()` runs**, so the debug
  `-resetTrip` flag was clearing state the store had already read — every
  screenshot silently carried the previous run's state. Building the store
  inside `init()` fixed it. Worth knowing generally: a stored property's default
  value is evaluated during initialisation, not after it.
- **The itinerary-overrun arithmetic was off by one.** `lastDay` is the day they
  leave the final stop — the last day of the trip — so it compares against
  `dayCount` directly.
- **The map framed the whole trip** on a screen titled "the trail so far",
  putting six weeks of empty ocean on screen. It now frames the earned stamps
  plus the next one.

From the previous round:

Worth recording, because none of it was reachable by the type-checker:

- **Locale-formatted numbers.** Three sites built their own `NumberFormatter`
  without pinning separators, so on a Dutch-region phone `38.348 THB` rendered
  as `"38,348"` — a 1000× misread inside English copy. Now all numbers go
  through `Formatting.decimal`.
- **Collapsed stamp badges.** They sized themselves from their own text; the
  circles shrank and codes truncated to `"B…"`. Fixed by taking the square from
  the grid cell (`Color.clear.aspectRatio(1, .fit)`) and drawing into it.
- **Self-contradicting forecast copy** when the projection ran the budget dry:
  "€0 for 14 days — fine if you cook twice a week".
- **A floating button covering ledger rows.**
- **Loose display line-height** — the fix in §4.3.

---

## 7. Decisions and trade-offs

| Decision | Alternative | Why |
|---|---|---|
| One `TripStore` | Per-screen view models | Every screen projects the same trip; computed properties can't drift |
| Itinerary as day offsets | Absolute dates | Travellers own the departure date; offsets make it invariant |
| Shift all records on date change | Leave dates alone | Otherwise the trip loses its shape relative to its own start |
| Settlement as a `.transfer` line | A mutable balance field | Keeps one source of truth; makes "doesn't touch the budget" provable |
| One coalesced snapshot | SwiftData / Core Data | No relational queries, no migrations needed for one trip; the debounce removed the only real cost |
| The trip as a protected file | A `UserDefaults` key | A plist is in every backup, is plaintext, and is readable after one unlock; a file can carry a protection class. The journal and every letter were in there while the passport scans got AES-GCM |
| `TripWriter.write` returns a `Bool` | `try?` and move on | A protected file cannot be written while the phone is locked, so the failure is real and the caller has to be able to retry |
| Migration writes, reads back, *then* removes | Remove once the write returns | The write can fail now; a remove on faith loses the trip. One extra launch holding both copies costs nothing |
| `storeKey: nil` for archived trips | `adopt(_ snapshot:)` on the live store | Pouring an archive into a running store fires thirty `didSet` handlers over the live trip |
| `CloudKitZone` shared by both transports | A copy each | They were answering "where does this trip live" differently, and the letters lost |
| `chooseLetterTransport(cloudAvailable:)` | Reading the flag inline | A free function taking the flag is the only way a check can exercise the branch this build never takes |
| `TransportConformance` | Trusting two implementations to agree | Weaker than running them, and it stops them coming to mean different things |
| Custom tab bar | `TabView` | The bar is the design; `UITabBar` can't be styled into it |
| `TypeSpec` + `font(_:)` overload | Editing ~150 call sites | Zero-churn Dynamic Type with guaranteed invalidation |
| Light appearance only | Follow system | The dark screens are deliberate moments, not a dark mode |
| Model checks on macOS | XCTest + simulator | Runs in seconds, no runtime needed, catches the maths |
| Merge separate from transport | CloudKit-native record merging | The half that can be wrong is testable without an account or a second device |
| One CloudKit record holding JSON | A record per expense | The merge is ours; one record means one atomic write and no partially-applied trip |
| Journals excluded from the payload *type* | Filtered at the boundary | A promise the compiler enforces beats one a reviewer has to notice |
| Settlement as propose/confirm | A synced boolean | "Both phones agree" is either a protocol or it's theatre |
| Photos copied, not referenced | `PHAsset` identifier | The book must survive a tidied camera roll |
| Scans encrypted at rest | Plain files in the container | It's a passport |
| `ScanVault` split out of `DocumentStore` | Leaving the bookkeeping in the excluded file | A prune with the wrong `keeping` set silently deletes somebody's passport; it can't live in the one file no check compiles |
| `TravelDocument` has no `updatedAt` | Filtering documents at the sync boundary | With no `updatedAt` it can't conform to `SyncableRecord`, so it can't be merged into a payload even deliberately |
| …and no `deletedAt` either | Tombstoning like every other record | A tombstone beats a concurrent edit across two phones; there is no second phone here, and a tombstoned row is a passport number still on disk under the word "deleted" |
| Closing a trip strips the papers | Archiving them with the rest | A finished trip is a book worth keeping; the passport that got you through it is not, and a shelf quietly holding every number ever typed is the opposite of what the vault is for |
| `papersLostOnClose` asked of the store | Each dialog counting for itself | Same as `adoptionDiscardsLetters`: a dialog that computes its own version of a guard drifts, and drifts the same way, so nothing catches it |
| Scan prune is the live trip alone | Matching `PhotoStore`'s shelf-walking prune | Closing deletes the scans, so no archived snapshot can name one; including the shelf would preserve what the close destroyed |
| Both editors behind `Locked` | Locking the Papers tab | The meeting point and the show-this cards exist to be handed over; a lock in front of those hurts the person it protects |
| PDF rasterised in place, never copied | Copying to `temporaryDirectory` first | An unencrypted passport in a folder emptied on no schedule — the exported book's bug, already had once |
| Picker results gathered into slots | Appending as they load | `loadObject` completions are unordered, so a passport's pages come back shuffled: nothing missing, nothing crashing, silently wrong |
| Itinerary nights authoritative, days derived | Editing dates directly | Reflow makes gaps and overlaps unrepresentable |
| 61 days as a *default* | A fixed constant | The prototype's own numbers didn't reconcile; see README |

### Known limitations

- **Neither CloudKit transport has ever executed.** Without a developer team they
  cannot run, so they are untested against the real service — retries, partial
  failures, account-changed, quota. The merge they feed is tested and their
  semantics are pinned; the pipes are not. Everything else needed to switch them
  on needs no code changes: a **paid** `DEVELOPMENT_TEAM` (a free personal team
  cannot hold the iCloud capability), that capability with container
  `iCloud.com.lovedones.dithoi`, and `DiThoiCloudKitEnabled` set to `<true/>` in
  `DiThoi-Info.plist` — and those now switch the **letters** on as well as the
  trip, which for a long time they would not have. The flag moved out of
  `INFOPLIST_KEY_DiThoiCloudKitEnabled`, which Xcode was dropping as a key it
  did not recognise, so it never reached a built app.
- **Sync is whole-payload, pull-merge-push.** Fine for two people and a
  two-month ledger; wrong for a long trip or many devices. There is no change
  token, no delta, and no push notification — a round only happens on launch, on
  foreground, or when someone taps. For letters that is acceptable, since the
  channel's whole premise is slowness; for a meeting point it is the known gap.
- **`role` is still a switch, not two paired accounts.** The merge and the
  handshake are real; identity is not — the slots now carry names, but nothing
  stops two phones claiming the same one. Pairing is where `CKShare` would go.
- **Prose that arrives with a trip carries whatever names it was written with.**
  A document titled by hand keeps its title when a slot is renamed, so a renamed
  traveller can get "Kim · document 1 of 6" over "Passport · Alex". Now that
  every document is typed by hand this is the common case rather than an artefact
  of seeded content.
- **PDF import has no automated coverage.** Rasterising is `UIImage` work, so
  `DocumentImport` sits in `Features/` where `run-checks.sh` cannot reach it.
  What it hands the vault is checked end to end; what it produces from a given
  PDF is verified by eye only.
- **Nothing verifies that a protected file is actually unreadable while the
  phone is locked** — not the trip, not the shelf, not the scans. File protection
  classes are a no-op on the simulator and `writeProtected` compiles the option
  out entirely for macOS, which is where the checks run. What *is* verifiable
  there, and is: that the trip is a file rather than a preferences key, that the
  preferences hold only the rates and the sync stamp, that a migration lands
  before the old copy goes, that a refused write is reported and retried, and
  that the scans are encrypted, ordered, pruned and excluded from backup. The
  class itself needs a locked device.
- **One screen still prints `tripName` without a fallback, and means to.** The
  PDF's metadata keeps the raw title: it travels with the file, and "this trip"
  as a document title is a sentence pretending to be a name. Everything a reader
  sees goes through a fallback now — `store.displayName` for the book's title
  page and the export filename, `TripSummary.displayName` for the shelf, since a
  frozen summary can never reach a store, and `WidgetBridge` substitutes on the
  way out because `WidgetSnapshot` holds only scalars and has no room for a
  computed one.
- **No conflict UI beyond a notice.** The loser of a last-writer-wins merge is
  announced but not recoverable — there is no "restore what I had".
- **Map tiles need the network.** MapKit degrades to grey offline; the route and
  pins still draw. Genuinely offline tiles would mean bundling them.
- **The widget is unverified on a real Home Screen.** The timeline, the group
  container and the compiled `Assets.car` renditions are all checked; nothing has
  dragged the widget onto a springboard.
- **Zero localisation**, in an app about crossing borders — out of scope by
  decision, and the one item from the review deliberately not addressed.
- **`Screen`'s `ScrollView` still has no lazy stack.**

---

## 8. Phase 2 and after

Six features, each of which turned out to be mostly one decision.

### 8.1 The evening ritual (`Model/Ritual.swift`)

The design's position is that the app notices when the walking stops and never
says so — no settings screen, no "we noticed you write around ten". That makes
the interesting part a pure function over past behaviour, so `RitualClock` is a
`Codable` struct of minute-of-day observations with no dependency on a
notification centre, and the checks exercise it directly:

- **median, not mean**, so one 3am airport entry doesn't drag the habit to
  breakfast;
- **entries before 05:00 count as the previous evening** (`raw + 24 * 60`),
  because a page written at 00:20 is last night's;
- **a fortnight's window**, long enough to be a habit and short enough to follow
  one that changes;
- **jitter derived from the day number**, so "never at the same hour twice" is
  true and the same day always produces the same answer — a notification that
  moves when the phone is woken twice is a notification that fires twice.

Posting it is behind `RitualScheduler`, a three-method protocol with a
`SilentRitualScheduler` for the checks. Only *tonight's* page teaches the clock;
backfilling day 35 at lunchtime says nothing about when she writes, and there's
an assertion for that.

Two things it deliberately doesn't do. It never sets a badge — a number on the
icon is a count, and the design counts nothing about her. And it never touches
`UNUserNotificationCenter` before permission is actually held, which is what
keeps a system alert off the screen of somebody who has only opened a tab.

### 8.2 The book (`Model/Book.swift`, `Features/Book/`)

`BookPlan` is derived, never stored — the same reasoning as every other number
in the app. A written night is a **spread** (photo page, text page), page
numbers come from the spread's index, and the contents sections are computed
ranges. The checks assert that the sections tile the book exactly and never
overlap.

The load-bearing detail is that `BookSpreadView` draws both the on-screen
preview and the pages that go into the PDF. `BookPDF` renders it with
`ImageRenderer` at `scale = 300/72`, splits each spread down the gutter, and
draws each half oversize so the bleed is real image rather than white paper the
guillotine would expose. A preview rendered by different code from the print
file is a preview that can lie, and this book gets printed once.

Two smaller things worth keeping:

- **A page written off the itinerary is still in the book.** If a city is
  dropped, its pages would otherwise vanish from the plan — the worst bug this
  thing could have. `BookPlan.build` sweeps up anything unplaced into an
  "Elsewhere" section, and the checks cover it.
- **The dpi check is arithmetic, not a library call.** `PhotoMeasurement` takes
  a pixel count and the spec; `PhotoStore.pixelLongEdge` reads it from the
  file's header. That split is what lets the print maths run on macOS.

### 8.3 Home mode and the letter channel (`Model/LetterDelivery.swift`)

The design's promise is that he can never learn whether a letter was read. Phase
1 kept half of it by leaving letters off `SyncPayload`. Phase 2 needs them to
travel, so the other half had to be made structural too.

Letters therefore move on **their own one-way channel**, not as a sixth field on
the payload:

```swift
struct SealedLetter { id, number, title, writtenOn, sealedAt,
                      condition, hint, paragraphs, signature, secretCondition }
```

There is no `openedOn`, no `openedPlace`, no `receivedAt` — not filtered out at
the boundary, simply absent, so a future field can't leak one. Sync is
symmetric and this must not be, which is the other reason it isn't a payload
field. A check reflects over the type and fails if a read-shaped field ever
appears on it.

**The box is addressed, and that is what carries the recipient.** `LetterDrop`
is keyed on `(tripID, recipient)`, not on the trip alone. `role` already meant
the right thing on both sides — the traveller's own slot on their phone, the
traveller being written *to* on the observer's — so `postLetters()` posts to
`role`, `collectLetters()` collects at `role`, and no field describes the
recipient anywhere else.

It was tempting to sync a `letterRecipient` instead. That is the wrong shape: the
promise is that the other side hides the letters *and every reference to them*,
and a synced recipient **is** a reference to them — it would tell the other phone
that a channel exists and who is on it. Routing carries the answer, so a
non-recipient looks at their own address, finds nothing, and cannot tell whether
any other address exists. `lettersVisible` follows from that rather than from
identity: `features.letters && !letters.isEmpty`.

The corollary is that `adopt(_:)` — a phone taking a traveller slot — **deletes**
any letters it holds, because they were addressed to the slot it used to be.
Declining to *draw* somebody else's letters still leaves them on this disk, which
is the thing the addressed channel exists to stop. The observer's path is
`writeTo(_:)` and deletes nothing: their copy is the archive of what they wrote.

Three more things fell out of taking the design seriously:

- **A draft never travels.** `sealedAt == nil` means draft, and `postLetters`
  builds the drop from `sealedByWriter`. Getting this right required *removing*
  a convenience: `Letter.init` used to default `sealedAt` to `writtenOn` for
  back-compatibility, which quietly sealed every letter the moment it was
  started. The defaulting now happens only in the decoder, where it belongs.
- **A hidden letter has a real condition.** `LetterCondition.hidden` could never
  fire, so `secretCondition` withholds the *when* from her while the letter
  still knows it. Four seeded letters were sealed with no way to open.
- **Nothing says "no letters on this phone".** `TodayView` used to, on the phone
  that is supposed to have neither the letters nor any mention of them. It read
  as a demonstration written for a reader of the prototype. What each side can
  see belongs on the sharing screen, which is the screen that is about that.

#### What the observer can and cannot be told

Nothing reports delivery back, and nothing may: a delivery receipt is precisely
what the design forbids. So `deliveredCount` is *inferred* — condition arithmetic
over the observer's own copy of the synced trip (day, city, stamps). That is a
real prediction, not a fixture, and it is exactly why the no-read-receipts
promise holds at all.

But it conflates two facts the phone knows separately: **the condition has
fired**, from synced state, and **the sealed set left this phone**, from the
transport. "Delivered" asserts both, and for the whole of Phase 2 the second was
false for every letter always, because the loopback wrote to a file on that same
device. Home mode said "4 delivered", promised "her phone will open it", and
headlined the seal confirmation "It's out of your hands".

The vocabulary now splits on `lettersAreStuck` — due/not-yet when nothing is
leaving, delivered/sealed when it is — and a panel says which of the two it is.
`postLetters` records `lastPostFailure` and `lastPostedAt` on the store instead of
swallowing with `try?`.

**The reading side stays silent on failure, deliberately.** `collectLetters`
returns `[]` whether the fetch failed or the box was empty, and records nothing.
Telling the traveller "a fetch failed" tells her a letter box exists, which is
the one thing the addressing is built to withhold. The asymmetry is the design,
not an oversight.

#### The transport, and the line that nearly wasn't there

`LetterDropTransport` has two implementations, `LoopbackLetterDropTransport` and
`CloudKitLetterDropTransport`, and the CloudKit one keys its record on
`Letters-<tripID>-<recipient>` for the same reason the loopback puts the address
in the filename: a phone that could fetch a box and *then* decline to draw it has
already learned the box is there. The wrong phone constructs a name nothing
answers to.

The transport existed and compiled for a long time before anything selected it.
`TripStore.init` read `letterPost ?? LoopbackLetterDropTransport()` —
unconditional — while `SyncCoordinator` probed and chose, so the three steps that
switch iCloud on would have moved the *trip* to iCloud and left the letters
writing to a file on the observer's own phone: home mode with a well-designed
envelope and no postal service. The choice is now
`chooseLetterTransport(cloudAvailable:)`, and both of its branches are checked.

`LetterCondition.canStillFire(_:)` is J9's whole argument in one function: a
letter written mid-trip only lands the next time her phone is online, so a place
she has already passed is a condition that will never come true. The picker
greys those out and says why, rather than letting him set a letter that silently
never opens — and `.nextOnline` exists because it is the one condition that
cannot miss.

### 8.4 More than one trip (`Model/TripLibrary.swift`)

The design's own note is the architecture: *only one trip is ever live*. That
turns what would have been a per-trip sync fan-out into one record for the live
trip plus cold storage.

- `SyncPayload` gained a `tripID`, and `SyncMerge` refuses a payload whose id
  doesn't match — with a notice, because silently doing nothing is worse.
- `TripStore.syncNow()` is a no-op once `closedOn` is set.
- Closing freezes the whole `TripSnapshot` into the shelf, and `ArchivedTripView`
  opens it: a second `TripStore` built with **no persistence key**, so the book,
  the letters and the ledger are the real screens reading real data and nothing
  they do can reach disk. The summary rows above them stay frozen rather than
  recomputed, because a closed trip's figures shouldn't move.
  This sentence used to say the archive was "the app it was, not a report about
  it, so `ArchivedTripView` reads the frozen summary" — which refutes itself, and
  described what the screen actually did: eight facts and no way in.
- Opening it is deliberately not *all* the screens. Today and the papers were
  about running a trip on a particular day; the trail, the book, the letters and
  the ledger are the things worth going back for. The trail was on the wrong side
  of that line for a while, standing in as a hatched placeholder captioned "the
  trail as it was" — a drawing of a screen nothing could open. Where they went is
  the record, not a control, and the one part that *was* a control (handing out a
  stamp) was already behind `\.isReadOnly`.
- A reopened trip draws **no sync tag**: the shelf's store has never synced, so
  `ScreenTag.syncState` answered "not synced yet" about a trip that synced for two
  months and then closed. True of the object, false of the trip.
- It exports its book but cannot **order** one. `place(_:)` on a keyless store
  sets `bookOrder` in memory, so the screen said the order was placed, nothing
  reached disk, and the shelf row read "never printed" for good. Export stays: it
  mutates nothing and is the actual reason to reopen a finished book.
- `TripSnapshot` decodes field by field with defaults, so a trip written by an
  earlier version still opens. The alternative is a phone that loses two months
  of pages because a flag was added.

**Finishing, between trips, and the next one.** One sheet, `FinishTripView`,
offers the only two ways out of a live trip:
- *Put it on the shelf:* `closeTrip()`.
- *Throw it away:* `beginNextTrip(discarding: true)`.

The sheet is reached from the shelf, settings, the ending screen, Today (once
`isOverButOpen`) and the observer's home screen. The confirmed action runs in
the sheet's `onDisappear`, because both answers remove the view that presented
it.

Once a trip is closed, `RootView` draws `ShelfView` in place of the tabs, and
the trip that was just closed *lands*. `closeTrip()` sets `justShelved`, a
signal that is read once and never persisted. The shelf takes it, drops the
spine into its slot, fires one soft haptic, and fades in
`TripSummary.shelvedLine` ("61 days · 3 countries · 67 km · 6 pages ·
7 moments"). The line is built clause by clause and each clause drops out when
empty. With Reduce Motion it is simply there. The summary's new `kilometres`
and `moments` fields are optional, so shelves written before them still
decode. The
old arrangement left a closed trip in `MainTabs` drawn as live, listed twice on
the shelf. The shelf's one action is then "Start the next trip":
- `beginNextTrip()` refuses a live trip, so closing is never implied.
- It mints a new `tripID`, blanks the name and clears `hasOpened`, which hands
  the phone back to `ArrivalFlow`.
- It carries the names, the role, the money, the length, the switches, and the
  show-this cards. The cards are re-minted under fresh ids so no tombstone on
  the other phone can take them.

`ArrivalFlow` is the only setup flow. Its steps are a registry in
`Model/SetupSteps.swift`, where the checks can reach them. `returning` and
`returningTraveller` are captured once on appear, so the flow can't reshuffle
under its own index. A returning traveller opens on `destination`:
- where next, as a country and a first stop;
- who is holding the phone, as one line;
- what came over, as rows that can be declined through `applyCarry`, applied
  from a snapshot so it is reversible.

The name step then offers `suggestedTripName` and draws the book's spine
growing with the dates.

**Planned trips.** One next trip can be sketched ahead, whether a trip is
live or not. It holds a name, dates, the money and an itinerary.
- **Storage:** `TripLibrary.plan`, in its own protected file, status
  `.planned`.
- **Editing:** a keyless `TripStore` from `makePlan()` / `openPlan()` that
  shares the live store's library. So it can't write the live trip, publish
  the widget, or prune anything.
- **Never synced.** The other phone meets it when it goes live and the
  invite step pairs them.
- **On the shelf:** a dashed spine and a "planned · starts in N days" row.
  Between trips, it becomes "Start ⟨name⟩".
- **Going live:** `beginNextTrip(usingPlan:)` adopts it and clears it, under
  a fresh `tripID`.

| Decision | Alternative | Why |
|---|---|---|
| Next trip through `ArrivalFlow` | A second setup flow | Two flows for one set of questions drifted: the second had no itinerary or invite step and reset the role |
| Between trips as a root state | Leaving the closed trip in the tabs | A finished trip drawn with live chrome, listed twice on the shelf |
| Shelve and discard on one sheet | Close on the shelf, empty in settings | They are the same question; apart, one lied about deleting and the other never mentioned the shelf |
| Templates not asked | A template step presetting the switches | The switches are now changeable in settings, which they never were; a preset for something editable is a question with no stakes |

`TripFeatures` is the other half: a feature that's off is off *everywhere* — the
tab disappears, rather than showing an empty screen that reminds you of what
this trip isn't doing. They change in settings (`featuresBlock`), and a next
trip carries the last one's.

### 8.5 The country card (`Model/CountryFacts.swift`)

A static table keyed on a normalised country name, and the app's clearest example
of the difference between a constant and a fact. The Separated screen used to
print Thailand's emergency numbers under a label computed from the current leg,
so on day 30 it read **"Emergency · Vietnam"** above `191 police · 1669 medical`.
That was the only item in the review classed as a defect rather than debt.

Two rules hold the file together, and both are about restraint:

1. **An unknown country returns `nil`, and `nil` draws nothing.** `Leg.country` is
   free text, so most countries somebody types will not be in the table, and
   silence is the honest output — a missing number sends somebody to a hotel
   desk, a wrong one sends them nowhere. The rule runs per *column* as well: a
   country can be known and still decline to name a language, its sockets or its
   phrases.
2. **Only what stays true lives here.** The test is staleness, not usefulness.
   Emergency numbers, socket standards and mains voltage do not move; two fixed
   sentences in a fixed script do not move. Airport taxi fares and consulate
   addresses were asked for and **refused** — fares are wrong within a year, and
   a consulate needs a nationality the app has never asked anybody for plus an
   address that moves. Both refusals are written into the file so the next person
   meets the decision rather than the gap.

`phrases` is bound to `language` by a checked invariant: a phrase is written in
one script, so a country that won't name a language can't have one. It is a
whitelist — the file names the fourteen languages waiting on somebody who reads
them — and it is not the translation service the show-card editor refuses, which
is asked to carry arbitrary text nobody can read back. Phrases hang off the
*country*, not the language: China and Taiwan both label theirs "Mandarin" and
are written in different characters.

### 8.6 The papers (`Model/ScanVault.swift`, `Features/Papers/`)

Everything under the vault had been built and hardened for two phases — the
crypto, the three-state page read, the short-batch reporting, the lock, the
backup exclusion. What was missing was the top half. `TripStore.documents` was
`private(set)` with no mutator anywhere, so in a shipped build it was permanently
empty and the Papers screen said so out loud: *"what's missing is a way to add a
document of your own, which this build doesn't have yet."*

The whole risk in adding it was that the top half would quietly undo the bottom
half, and most of §3.5 and §5 is the record of keeping that from happening. Three
things are worth pulling out here.

**Scope was a decision, not a default.** Documents go *onto* the phone and
nowhere else — no sending to the other traveller, no encrypted cloud backup. Both
were considered and both would have reversed a promise the app makes in three
places, including a fake "Send to <them>" button that was deleted in Phase 2 for
saying exactly that. The feature is the missing local half and nothing more.

**Adding a way to create documents made a dormant leak live.** Nothing pruned
`.scan` files and `deleteAll(for:)` had no callers, so every page ever written
would have survived a reset forever. That was invisible while no document could
exist and would have shipped the moment one could. The fix is in §3.5; the
general shape is that a feature which makes an unreachable state reachable
inherits every bug in that state.

**The editor is `ShowCardEditorView`'s shape, with one deliberate difference.**
Same sheet for new and edit, same whole-value `update`, same
`.confirmationDialog` naming what is lost. What it does *not* do is end with
`Task { await store.syncNow() }` — every other editor in the app does, so the
absence is commented rather than left to look like an oversight. Papers do not
travel.

Two smaller shapes that follow the house style:

- **`badge` is a `String`, not a `DocumentKind` enum.** The editor offers chips
  that fill it, which is the ergonomics of an enum without the hazard:
  `decodeIfPresent` *throws* on an unknown raw value, `TripSnapshot` swallows
  that with `try?`, and the store re-seeds over somebody's trip. The same trap
  `Participant.writer`'s raw value is kept for.
- **`hasScan` was deleted rather than maintained.** It was written and never
  read; `PapersView` already computed the real answer from `pageCount`. Once
  documents are typed by hand, a second source of truth for "does this have a
  scan" is one the editor would have had to keep in step. `badgeIsAccent` went
  the same way and is now derived from the count.

`TravelDocument` also gained a tolerant `init(from:)`, field by field with
defaults, which it had never needed while nothing could create one. The
synthesized decode requires every key, and one missing key throws out of
`TripSnapshot`'s `decodeIfPresent([TravelDocument])` — which `TripSnapshot.decode`
catches with `try?`, so the whole trip reads as unreadable and the store starts a
fresh one over the top. A dropped field must cost a field, never the trip.

## 9. Where to change what

| You want to… | Go to |
|---|---|
| Change a colour, space or radius | `Shared/Theme.swift` — the mark's six live in `TripMarkInk` |
| Swap in the real Cormorant/Lora/Plex fonts | `TypeSpec.design`, `Shared/Theme.swift` |
| Adjust how type scales for accessibility | `TypeSpec.growthCeiling` |
| Add a currency | `Currency` in `Models.swift` — rates follow automatically |
| Add or change a rate provider | `RatesService.Endpoint` + a `decode…` function |
| Change what the checks run against | `Tools/CheckTrip.swift` |
| Persist something new | `Storage.appKeys` **and** a line in the reset check — never a string literal in `DebugScreen` |
| Change where the trip is written | `Storage.writeProtected` / `readProtected` — and keep `forget(_:)` clearing both addresses |
| Add a field to the trip | `TripSnapshot` + `init(from:)` with a default, or the strip-each-key check fails and somebody loses two months |
| Add a derived money figure | `TripStore`, then assert it in `Tools/VerifyTrip.swift` |
| Add a screen | `Features/<Tab>/`, then a case in `DebugScreens` so it's shootable |
| Add something Siri or a control can start | A `QuickAction` case, an `AppIntent` in `Shared/` that only posts it, and a branch in `RootView.readQuickAction()` — which decides, and drops, before anything is presented |
| Change what the trail's map draws | `TrailMap` — inline it is a door, `interactive: true` is `TrailMapView`; keep every mark a different shape, and keep moments and "you" out of the framing |
| Change how moments are grouped or captioned | `Moment.groupedByStop`, `Moment.caption` / `place` — then the grouping checks |
| Change the icon's geometry | `TripMarkCut` / `TripMarkGeometry`, then `./Tools/render-icons.sh` |
| Add an icon slot | `IconSlot.iPhone` — the PNGs *and* `Contents.json` come from it |
| Change what the widget says | `WidgetSnapshot.kicker` / `.place` / `.nextLine`, then assert it |
| Change what the widget is *told* | `WidgetSnapshot` — and read its three privacy checks first |
| Change the widget's layout | `Shared/DayWidgetView.swift`, then `-screen widget` |
| Turn CloudKit on | A **paid** `DEVELOPMENT_TEAM`, iCloud capability, `DiThoiCloudKitEnabled` → `<true/>` in `DiThoi-Info.plist` — no code; switches the letters on too |
| Change what syncs | `SyncPayload` + `SyncMerge`, then assert it in the two-phone checks |
| Change how a clash resolves | `SyncMerge.merge` — one function, no I/O |
| Add a transport | Conform, then point `TransportConformance` at it — building it is not checking it |
| Change where a record lives in iCloud | `CloudKitZone` — both transports read it |
| Add a country, socket or phrase | `CountryFacts.all`, then the `phrases ⇒ language` check |
| Add an itinerary edit | `ItineraryDocument`, then assert contiguity in the checks — and call `reflowWaypoints()` |
| Join a waypoint to a stop | `TripStore.segment(for:)` — one join; never write the string match again |
| Add a kind of spread | `BookSpread` + `BookSpreadView` + `pagesPerVolume`'s counters |
| Change when the evening prompt fires | `RitualClock` — pure, and checked on macOS |
| Change what the book looks like | `BookSpreadView` — it draws the preview *and* the PDF |
| Change the print spec | `BookSpec`, then re-assert `fullBleedPixels` in the checks |
| Add a letter condition | `LetterCondition` + `isMet` + `canStillFire`, then the picker |
| Change what reaches the writer | `SealedLetter` — and think hard before adding a field |
| Change where scans live, or how they're named | `ScanVault` — and nothing in `DocumentStore` |
| Add a field to a document | `TravelDocument` + its `init(from:)` — never `updatedAt` or `deletedAt` |
| Add a way to get a page in | `DocumentCapture`'s source sheet; every route out must report, including cancel |
| Change what closing a trip destroys | `closeTrip()` **and** `papersLostOnClose` — one is what happens, the other is what the dialogs say |
| Show or accept a passport number on a new screen | Wrap its `body` in `Locked`, and gate edits on `!isReadOnly && store.isLive` |
| Add an onboarding step | A case in `ArrivalFlow.Step`, in order, and its line in `isIncluded` — the first trip and every next one get it |
| Change what carries to the next trip | `TripStore.beginNextTrip` — and the carried-over line on `FinishTripView`, which says it out loud |
| Add a way to finish a trip | Present `FinishTripView`; never call `closeTrip()` or `beginNextTrip` from a new control |
| Turn a feature off for a trip | `TripFeatures`, then the `tabs` filter in `MainTabs` |
