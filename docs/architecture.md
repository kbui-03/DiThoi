# Architecture

How Đi Thôi is put together, and why — including every trap that has bitten it,
with the reasoning in full. For whoever maintains or extends it.

Read [README.md](README.md) first if you just want to run it.
[CHANGELOG.md](CHANGELOG.md) lists what is built and the known issues.
[`CLAUDE.md`](../CLAUDE.md) at the repository root is the short form of this
document: one line per rule, each pointing at the section here that explains it.
**When a rule changes, change it in both places.**

Many paragraphs below open with what the code used to do. That is deliberate:
the history is the argument for the rule, and the obvious "tidy-up" is usually
the bug being described.

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

**The app ships with no trip inside it.** A first launch is a blank trip, and
onboarding asks who is holding the phone — either traveller, or the observer who
stays home and writes — along with what they are called, and then for the dates,
the budget, the currency and the itinerary. Everything else is computed. The two
traveller slots are `.one` and `.two`; what they are called is trip data, in
`TripNames`.

**Everything on screen is derived or deleted.** The fake signal bar, "texts home
your city", 1.4 GB of offline maps, "38 pins dropped" and `Made at home · April
2027` are gone. If you add a sentence with a number in it, something has to
compute the number.

---

## 2. Layers

```
┌──────────────────────────────────────────────────────────────┐
│  Features/          41 screens, grouped by tab                 │
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

`TripStore` is now ~3,500 lines, most of it computed properties, and that is
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

**`Currency`** — a curated enum of about forty currencies, every country in
`CountryFacts` plus the common travel ones. Raw values are lowercase ISO codes
and are persisted, so cases are added and never renamed. Symbol, name and
decimal places come from one `faces` table. No case has three decimals (the
keypad is whole units), and no symbol but the US dollar's is a bare "$". It was
six cases, which left Japan, Laos, Cambodia and most of Europe outside the euro
with nothing to record spending in. It deliberately does *not* carry an
exchange rate; see §3.3.

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

**A model mutation is validated whole, then applied whole.** `updateWaypoint`
used to check and write a field at a time, so a good code with an empty city
changed the code, re-keyed the drafts that named it, returned `false` — and never
reached the `updatedAt` at the bottom, which is the only thing that makes an edit
visible to the merge. The other phone would hand the old code straight back, over
a letter now pointing somewhere else. `canSave` in the editor happens to prevent
it; a guarantee that lives in a view isn't one.

### 3.2 `TripStore` and persistence

A handful of persisted inputs — `start`, `dayCount`, `budget`, `homeCurrency`,
`role`, `participant`, `names`, `origin`, `hasOpened` — plus the mutable
collections (`expenses`, `journal`, `letters`, `stamps`, `dayPlans`, `showCards`,
`documents`, `meetingPoint`, `settlements`, `separatedSince`, `ritualClock`,
`moments`, `meetingPlaces`). Everything else is computed.

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

Nothing else sits in the container root. The loopback boxes used to:
`loopback-shared.json` (the ledger, itinerary and meeting point) and
`letters-*.json` (every sealed letter in full, unsealed), at the default
protection class and in every backup, one folder up from the store this table
was built to protect. The app no longer writes either: sync and letters both
choose an inert transport when CloudKit is off. The loopbacks, reached by
injection from the checks and debug screens, write to `Loopback/` through
`Storage.writeLoopback`, protected and excluded from backup. Every launch runs
`Storage.sweepStrayLoopbackFiles()`, which deletes what an older build left.
That delete has no read-back, unlike the migration: neither file was ever the
only copy of anything (the payload is this phone's own trip, and the letters
are `TripStore.letters` in the protected snapshot).

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

**`TripSnapshot` decodes field by field with defaults.** All thirty are
`decodeIfPresent` and a check strips each key in turn; adding a stored property
without a fallback loses somebody's trip. Relatedly, **what a trip came with is
stored per trip** — `dayPlans`, `documents`, `showCards` and `sharingRules` are
fields on the snapshot, not constants, so a new trip opens with its own papers
rather than another trip's.

`Storage` is the single seam for both `UserDefaults` and the container, which the
checks point at a scratch suite and a temporary directory. `Storage.shared` —
the App Group suite the widget reads — returns `nil` rather than
falling back, because `UserDefaults(suiteName:)` hands back a working object with
or without the entitlement, and a fallback would write widget data into the app's
own plist where nothing reads it and nothing complains.

**A check that reads its own write uses `flushAndWait()`.** "a store with a key
writes itself" did `flush()` and slept 120 ms, and failed the first time an
Xcode build was running beside it. The rule was already written above; the
check was the one place still guessing.

**`-resetTrip` clears the letters file and the shelf too.** Letters left in the
drop are collected back onto the empty trip on the next wake, so a reset that
spared them wouldn't be a first launch.

**Everything the app persists is named once, in `Storage.appKeys`.**
`DebugScreen.reset()` used to write out four fresh string literals while every
one of them already had a constant. Bump `TripStore.storeKey` to v4 and that
reset goes on faithfully clearing v3 — and every screenshot taken after it
carries the previous run's trip, which is a failure this project has already had.
The list lives in `Model/` rather than `Root/` for a second reason: `Root/` isn't
compiled by `run-checks.sh`, so a list kept there could only be checked against a
copy of itself. Same argument as `CloudKitZone.isEnabled`.

**`resetTrip()` deletes no photo directly; it prunes.** It used to walk the
journal and the moments and delete what they pointed at, justified as "reset
overwrites rather than archives, so nothing is left pointing at these". True of a
live trip and false of a closed one: `closeTrip()` freezes a snapshot and leaves
the live journal where it is, so the store still names exactly the files that
book is made of until `beginNextTrip` clears it. The same rule holds for
`beginNextTrip(discarding:)`: it prunes rather than deletes. `pruneOrphanedPhotos()` is
the only thing that knows the whole answer. It no-ops on a keyless store, which is
correct and is why a check for this has to build a store *with* a key.

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

Any new dated collection must be added to `setStart` (through `TripShift`, in
`Syncing.swift`) or the trip loses its shape.

**The shift reaches the other phone by conversion, not by re-stamping.** The
shifted records keep their `updatedAt`, and that is now on purpose. The
invariant: every dated record in a payload is measured from that payload's own
`settings.start`. When two payloads disagree about the start, `SyncMerge.merge`
moves the dates of the side whose settings lose into the winner's frame
(`SyncPayload.shiftDates(by:)`) before the union, and per-record LWW then
decides edits and deletes as it always did. On the receiving phone, `apply`
calls the same `shiftDates(by:)` the store's `setStart` uses before taking the
new start, which moves what never travels: the journal, the moments, the
letters and `separatedSince`.

It used to keep the shifted records' timestamps *and* do nothing else, so the
other phone took the new start, kept its unshifted copies on the tie, and every
expense sat N days off on one phone for good. Re-stamping each shifted record
was the obvious fix and the wrong one: one date move would have overridden the
other phone's unsynced edits and brought its deleted lines back. Two phones on
mixed builds would still diverge, but CloudKit has never run, so there is no
older peer to meet.

### 3.3 Rates and number formatting

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
         make(from:updatedAt:previous:)
         — rejects a payload wrong about USD or GBP;
           a bad minor currency holds its last rate
                    ▼
        @Published snapshot  →  UserDefaults "dithoi.rates.v1"
```

Design points:

- **Two keyless public endpoints, in order.** Both are unauthenticated and
  return a public list of numbers. Nothing about the trip is transmitted.
- **All-or-nothing about the majors, per currency below them.** `make` returns
  `nil` when USD or GBP is missing or implausible, which still catches an
  inverted table or one that lost its thousands. A missing or implausible minor
  currency keeps its last rate (or the built-in one) while the rest move. This
  was all-or-nothing over every currency, which was right at six and wrong at
  forty: one odd kyat would have frozen every rate on the phone.
- **Drifting currencies are judged against their last rate.** `RatesService.drifting`
  (ARS, TRY, LAK, EGP, MMK) can outrun ×4 in a few years, so they are compared
  with the last rate that got through rather than the built-in one. Still ×4 per
  step, so a decimal in the wrong place is refused all the same.
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

**A fetched rate is checked against the one the app shipped with, and the
endpoint cannot be pinned.** `rate > 0` was the whole validation, so a rate out
by a thousand drove the budget forecast, the per-country lines and the
`amountHome` written into a settlement — a real transfer between two people. The
obvious fix doesn't work: the jsdelivr fallback is a CalVer npm package
republished *daily*, so there is no major to pin (`@1` is a 404, which silently
drops the endpoint) and pinning a date freezes the rates. So the control is
`RatesService.isPlausible`, a ×4 band against `RateSnapshot.builtIn`, which holds
whoever published the numbers. Check the URL still returns before changing it.

**Number formatting goes through `Formatting.decimal`.** A raw `NumberFormatter`
takes the device region, rendering `38.348 THB` as `"38,348"` on a Dutch phone.
It and `Date.text(_:)` hold their formatters in a `FormatterBox` rather than
building one per call — these are read once per row of every dated or priced
list, and `DateFormatter` is not cheap.

### 3.4 Money

The ledger is `expenses`; everything on the Money tab and the money half of Today
is derived from it at the freshest rates the phone has. `Expense.balanceFactor`
(§3.1) is the whole balance calculation.

**"Spent today" counts every expense, converted into the money in hand — and
says so when it had to convert.** It was `spentTodayLocal`, which filtered on
`currency == localCurrency`. Survivable while the figure was inert; not once it
became the control that *adds* an expense, because a euro card payment in
Thailand left the 30pt number somebody had just tapped sitting exactly where it
was. "No error is not it worked", on a button. `spentTodayInLocal` sums
everything through `inLocal`, which is identity when the currencies match, so a
baht day stays exact. `spentTodayText` puts a "≈" in front **only when
`spentTodayIsConverted`** — marking an exact day approximate is the same lie in
the other direction — and rounds when it does, because the cents of an estimate
are noise and "≈€26.43" argues with itself. The two formats agree on baht, dong
and won, so that branch only shows on a leg whose currency is the home one.
Local rather than home because this is the figure read at a counter; the budget
question belongs to the pace line, which stays in home.

**And it needs `lineLimit(1)` and a `minimumScaleFactor`, like the keypad's own
amount.** It lives in a half-width column, and at an accessibility size
"≈฿19,379" broke across two lines with the final digit alone on the second —
"SONGKRA / N" on a number, on the screen where misreading one matters. Counting
every currency makes the figure bigger and the "≈" adds a glyph, so the change
that made it honest is the change that made it wrap. Only the screenshot showed
it; both suites were green.

**The pace line needs a budget to judge against.** Nought is allowed, and
`paceNote` used to say "≈ €0 · under pace" on an empty day and "over pace" for
anything spent against a day worth nothing. It is the store's now: with no
budget it is only the home figure, and only when a rate was used or the money
in hand isn't the home money; otherwise `nil` and nothing is drawn. Its "≈"
follows `spentTodayText`'s rule.

**A record is stamped with `countryNow`, never `currentCountry`.** The em-dash
in `currentCountry` is what a *label* says when the trip has nowhere in it, and
it leaked into stored data: `AddExpenseView.save()` and `proposeSettlement`
both took it, so the ordinary first-run path — `init` always seeds a blank trip,
and the ledger is meant to work with nowhere in the plan — filed real money
under a country that does not exist. Every reader keys off `legs`, so the line
fell out of "by country" and the per-day lines in silence, and stayed out after
Thailand was typed in. `countryNow` answers `""`; `TripStore.unknownPlace` names
the label once so the two cannot drift.

**And `country(of:)` resolves an unstamped line rather than guessing at write
time.** Empty — or the legacy em-dash, which it still recognises — means nobody
had said yet, so it asks the itinerary as it stands: the money was spent in
Thailand whether or not Thailand had been typed in. **A stamped line is never
re-resolved**, which is the opposite of `DayDetailView.cityName` and
deliberately so: a day *plan* joins on `dayNumber` and `reflow()` renumbers
days, so there the stored city goes stale, while an expense is a record of a
dated event and where they were does not change because somebody dragged a stop.
The stamped case short-circuits before any calendar arithmetic, so the readers
pay nothing on an ordinary trip.

**Deleting an expense writes `deletedAt`; it never removes the record.** That's
what lets a delete beat a concurrent edit — `merged(with:)` keeps whichever side
was written last. Undo is the same mechanism backwards. Draw from `expenses.live`.

**Settlement is a `.transfer` expense, never a mutated balance.** `.transfer` lines
are excluded from `spending`, so they move the balance and provably leave the
budget alone. An earlier version used mirrored ±expenses and left half the balance
behind.

**`Expense.isEditable` is why the edit sheet refuses some lines.** A `.transfer`
borrows its proposal's id and amount, and the keypad is whole units, so a
fractional amount can't be typed back in.

### 3.5 Syncing (`Syncing.swift`, `SyncTransports.swift`, `SyncCoordinator.swift`)

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

**`letterKeys` is on the payload, deliberately, and it is public keys only.** The
pinned field list was edited in the open to add it — that is the check working.
The private half lives in the Keychain via `LetterKeyStore`, so it is in neither
`SyncPayload` nor `TripSnapshot`, which means neither iCloud nor a backup.

**What the sharing screen lists is derived, and pinned to `SyncPayload`.** It used
to be `sharingRules`, six sentences typed into `SampleTrip` and stored per trip —
and `SampleTrip` is commented out, so the array was **empty on every trip made
through onboarding**. The screen whose whole job is saying what the other phone
can see listed nothing at all, on every real trip, and only looked right because
the one trip anybody opened came packed. `TripStore.whatTravels` computes it from
`features`, and every line names the payload fields it describes so a check can
assert that nothing claiming "shared" is absent from the payload and nothing
claiming private is on it. The stored property stays for decoding and nothing
reads it.

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

**`modifyRecords` does not throw when the record failed to save.** It returns
per-record results, and `post` treated a non-nil return as delivery while `push`
had always inspected them. Same class as the `.changedKeys` it also used: a write
built on a stale read silently winning instead of being refused.

#### Switching it on

The three steps are in [README.md](README.md#turning-on-sync). What makes them
fragile is below.

**CloudKit is written but does not run.** `isAvailable` reads a bundle flag
that's `NO`. The flag lives in one place — `CloudKitZone.isEnabled` — because it
was two copies of a string literal, and a build where they disagreed is very
nearly what shipped.

**The flag it reads was unreachable for longer than that.** It was set as
`INFOPLIST_KEY_DiThoiCloudKitEnabled`, and Xcode only injects Info.plist keys it
already knows about — so the key was absent from every build ever made, and
`isEnabled` was answering `?? false` off something that could not exist. Turning
the setting to `YES` changed nothing, silently, with the build green. It is a
physical `DiThoi-Info.plist` now, merged into rather than replacing the
generated one, which is the arrangement the widget target already had.

**And the flag cannot see the entitlement it stands for.** They are two
independent switches, so a build with the flag on and the container missing asks
`CKContainer` for something it was not signed for. On a device that build fails
at signing; on the simulator it succeeds, because entitlements are simulated.
Ordering the steps so the entitlement is real first is the whole of the
protection — the flag asserts, it does not verify.

**`CKSharingSupported` is on whatever `DiThoiCloudKitEnabled` says.** Without it
iOS hands the link to the browser and the invitation dead-ends. The flag decides
whether this build can *act* on one; a build that can't should still be able to
say so, because silently not opening looks like a broken link at the sender's end.

**`application(_:userDidAcceptCloudKitShareWith:)`, and no scene delegate.** The
documented callback for an app with scenes is the *scene* delegate's, and it
cannot be used: naming a `delegateClass` replaces the scene delegate SwiftUI
installs, which is what creates the window. The app then launches to a blank white
screen — every screen — with nothing logged and no crash. Both spellings were
tried, a fresh `UISceneConfiguration` and the session's own. Both blank.

#### Pairing

Joining is the one way a `tripID` moves between phones.

**Two phones only meet if one of them *joined* the other.** Every phone mints its
own `tripID` in `TripStore.init`, `pull(tripID:)` fetches the record named after
it, and `SyncMerge` refuses a mismatch — so two people who each walked onboarding
are two trips that will never touch, however well the merge works. The failure was
silent, which is what made it worth a feature: the second phone's pull found no
record, which is *indistinguishable from being first*, so it pushed its own blank
trip and reported success. Both phones said synced; neither carried a word the
other wrote. `TripStore.joinTrip(_:as:)` is the only thing that moves an id
between phones, and `CloudKitZone.tripID(fromRecordName:)` is the only way one is
read off an invitation — which is why `tripRecordID` has to stay reversible.

**The invitation carries the slot, on the share and not the root record.**
Whoever invites is one of the two, so the invitee is `role.other` — decided at the
sending end, because both phones defaulting to `.one` is per-slot name stamping
with nothing to tell the two apart. It rides on the `CKShare` because
`CKShare.Metadata` carries the share itself: the joining phone can say *who they
would become* before accepting anything. On the root record it would need the
zone already in their shared database, which is the very thing being confirmed.
An invitation that doesn't say asks, and never guesses.

**Joining is split by reversibility, like onboarding's commit.** `details(of:)`
reads, `accept` joins the share, `joinTrip` takes on the trip — and the last one
runs only after iCloud has agreed. The other order shelves somebody's trip, empties
the phone, and *then* finds out there is no network.

**Joining shelves a trip and deletes letters, and the screen no longer says so.**
It did: a panel counted both from `joiningDiscards(becoming:)`, naming them apart
because one is a shelf and one is a deletion. It was removed on request. The
function is still there and still checked, and `joinTrip` still does both — so
this is the only place the second one is written down. Deleting letters addressed
to whoever the phone used to be is the one irreversible act in the app outside
closing a trip.

#### In this build

`SyncCoordinator` always chooses `CloudKitSyncTransport` unless a check injects
a box. With the flag off it is the switched-off transport the conformance check
describes: unavailable, with a reason, refusing every call. So `state` is
`.unavailable`, the sync line reads "on this phone", Settings names the reason
and drops "Sync now", and `lastSyncedAt` is never stamped (a stale one from an
older build is cleared on init).

It used to fall back to `LoopbackSyncTransport`, which is available and
succeeds, so every screen said "synced just now" about a round that wrote a file
on this phone and read it back. The loopback is a test fixture, and it is reached
only by injection: `init(transport:)` and `useForTesting`. Turning sync on stays
what it was, the flag and nothing else, and then the line is true by itself.

### 3.6 Files on disk

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

**The exported book is the whole journal in one file, and it is deleted.** It
went to `temporaryDirectory` under a name built from the trip's title and nothing
ever removed it; `tmp/` is emptied under storage pressure and on no schedule an
app may rely on. It is `Storage.exportDirectory` now
(`.completeUnlessOpen`, because the share sheet hands it to another process),
cleared before each build, on share-sheet completion, and on `.background`. The
PDF metadata carries the trip's title and **not** the traveller's name — metadata
travels with the file.

**A moment's photograph must be walked by `referencedPhotoIDs` in both halves** —
the live trip *and* every shelved snapshot. `pruneOrphanedPhotos()` runs on
every wake, so doing only the live half deletes them on the first launch after
the trip closes, which is when the book is being printed.

**A read must never mint a key, and a write must never delete one on spec.**
`loadKey()` returned nil for any non-success status, so an unreachable Keychain
read as "first run" — and the next line did `SecItemDelete` before `SecItemAdd`,
so the real key was gone before anything proved a replacement could be stored.
Every scan on the phone becomes noise, permanently, in silence. The likeliest
trigger is a step this file documents as supported: setting `DEVELOPMENT_TEAM`
re-signs the app and changes the keychain access group. `existingKey()` now tells
`errSecItemNotFound` from everything else, and `store` adds first.

**A failed decrypt is an answer, not a spinner.** `image(_:)` returned nil for
"no such page" and "cannot open this page" alike, so `ScanPage` drew "decrypting"
for good, under a row still saying "3 pages · encrypted on this phone". It is
`DocumentStore.Page` — missing / decrypted / unreadable — and `add` reports a
short batch instead of `continue`-ing past it.

### 3.7 `LocationService`

When-in-use only, and asked for by the act that needs a position: Separated
switching on (tracked, and stopped when they find each other), keeping a moment,
and dropping a pin (one fix each, `requestOnce()`). Never at launch. No
background mode and no always-on authorisation. A moment's coordinate stays on
the phone. A pin's doesn't: `arrive(at:)` fills a blank waypoint from the fix,
and waypoints sync. The copy said "only while Separated is on" on the sharing
screen and "only this screen reads where you are" on Separated long after both
stopped being true. Both name every reader now, and a check holds the sharing
line to it.

The trail uses `requestOnceIfAllowed()`, which does nothing until somebody has
already said yes. The trail is opened on any afternoon and is never the moment
to ask. What it draws from the fix — the "you are here" mark and "180 km from
here" under the next stop — appears only on a traveller's live trip, from a fix
under fifteen minutes old, and the distance only when the next waypoint has a
position. On the observer's phone it would put their kitchen on somebody else's
trail. Distance is `Geo.kilometres`, the one great-circle formula, which
`Stamp.kilometres(to:)` also calls.

It provides a distance and a spoken-word bearing for Separated, which falls back
to the written directions with no fix. **Two known issues:** nothing gives a
typed meeting point a position, so the distance never appears; and the bearing
is *to* the meeting point while the sentence reads "770 m south-west *of* the
meeting point", which is backwards. See
[CHANGELOG.md](CHANGELOG.md#known-issues).

### 3.8 The itinerary

Day offsets and `reflow()` are §3.1. The rest is how a stop is named, found and
made.

**`city(forDay:)` falls through to the last segment on the way home.**
`contains(day:)` is half-open because `endDay` is the day they *leave*, so the
final day is in no segment; without `lastKnownSegment(forDay:)` `TripEndingView`
said "— → home".

**`todaySegment` is the lenient lookup, and `currentSegment` is not.**
`contains(day:)` is half-open, so the strict one answers nil on the last morning
of the trip — the morning somebody opens the day to check the flight.
`currentCity` already went through `lastKnownSegment` for exactly that reason;
the two deliberately disagree. Nil still means an empty trip or an unplanned
gap, and the panel draws the itinerary rather than pushing to a day with no stop
behind it.

**A stop's title splits through `Segment.places`, and nowhere else.** Nine sites
wrote out `components(separatedBy: " · ")` and exactly one of them trimmed — the
same shape as the seven copies of the waypoint join that `segment(for:)` exists to
end, except that only the *join* was ever consolidated. A title typed
`"Ayutthaya ·  Pai "` therefore resolved in the app and not in the book. `places`
trims and drops blanks, `primaryPlace` is the headline one, `names(city:)` is the
whole-name match. Dropping blanks is load-bearing twice over: it is what makes
`DayDetailView.cityName`'s `?? plan?.city` fallback reachable at all, since the
raw split answered `[""]` and never nil. `Segment.places(in:)` is the static half,
for the stop still being typed in `AddStopView` — the same splitter, not a second
one, which is the entire point of the property.

**Both sheets that make a stop return it, and both offer the stamp.**
`AddCountryView` makes a country's *first* stop and had no stamp section, behind
a comment saying the sheet already asked four questions — while `addLeg` returned
`Void`, so a caller who wanted to stamp it had no handle anyway. On a blank trip
`legs` is empty, so "+ add a stop in X" does not exist and that sheet is the only
way in: the first stop of every country, and the first stop of every trip, was
the one stop whose stamp had to be added afterwards from a different sheet.
`addLeg` now returns the `Segment?` the way `addSegment` does — read back after
`touched(now)`, so the days are post-reflow — and `StampSection` is one view used
by both sheets, for the reason `StampFields` and `Segment.places` are shared.
`AddCountryView.isComplete` gained the refusal rule too: a code that is filled in
and refused disables "Add it" rather than making the leg and dropping the stamp.

**A stop and its stamp are made in one sheet.** They are the same answer asked
twice — where are we going, and what does getting there mean — and asking
separately is what put the city on screen twice. `addSegment` therefore *returns*
the stop it made, read back after `touched(now)` reflows, so the days on it aren't
the ones it had before the renumber. The stamp is optional: a blank code makes a
stop and no waypoint. A code that is filled in and *refused* disables "Add it"
rather than making the stop and dropping the stamp — "no error" is not "it
worked", one screen further down.

**Removing a stop takes its stamps, and asks first.** `ItineraryDocument.removeSegment`
only ever removed the segment. Its unearned waypoints stayed live with a
`segmentID` pointing at nothing: still in `orderedStamps`, still `nextStamp`,
sorted last by `planPosition`, reachable from no editor because
`waypoints(forSegment:)` never returned them — and holding
`allStampsEarned` false, so every `.finalStamp` letter could never open. The
AYU bug again, one operation over. `removeSegment` and `removeLeg` now go
through `removalSummary(ofSegments:)`, one derived answer for a stop and a
country: the unearned stamps that go, the sealed letters that will never open
(worded as `removalCost(ofWaypoint:)` words them, secret conditions kept
secret), the day plans filed under those stops, and a refusal — the group half
of `removalRefusal(ofWaypoint:)`, because removing the last unearned stamps
completes the trail and opens the last-stamp letter on the spot. It is
validated whole, then applied whole. Earned stamps stay: they are a record.
`ItineraryDocument.removeSegment` on its own is now only what a merge does, and
`orphanedWaypoints` is how the editor catches that (§3.9).

**Renaming keeps what hangs off the name.** A stamp joined only by name —
packed before the join existed, or one of two on "Ayutthaya · Pai", which the
backfill won't guess at — would lose its stop with the old title, so
`renameSegment` gives it the id first, as an edit. `Stamp.city` is never
rewritten: a `.place` letter is sealed to it, and `StampFields.options`
already offers the drifted city. A country's name is on every expense spent
there and is never re-resolved (§3.4), so `renameLeg` re-stamps the lines that
carry the old name *and* fall in that visit — a country entered twice keeps the
other visit's. `setCurrency` changes what new lines default to and nothing
already spent.

**A country can be entered twice, and `legs` is not the list of them.** Thailand →
Laos → Thailand is an ordinary route. Anything keyed off "*the* leg for this
country" answers with the first; anything that iterates `legs` to talk about
countries says the same one twice. Both shipped: `spent(inCountry:)` did the first
and `perDayByCountry` did the second, so Money drew two "Thailand" rows each
showing every baht spent in Thailand under two different day counts — and
`perDayLine` then found Thailand both cheapest and dearest and silently suppressed
itself. Go through `countries`, `legs(inCountry:)` and `daysSpent(inCountry:)`.

### 3.9 Waypoints

A waypoint is a stamp somebody can earn by standing in a stop. They are made on
the stop they belong to, in the itinerary editor, and they are what a letter
from home is most often sealed to — so most of what follows is about never
letting a letter point at the wrong place.

**A waypoint belongs to a stop by `segmentID`, and `nil` is permanent.** The link
was `segment.title.contains(stamp.city)` in seven places, three of them written
differently and one of them unanchored — "Ha Long" matched "Ha Long Bay". They
all go through `segment(for:)` now, which prefers the id and falls back to the
name. `backfillWaypointJoins()` attaches ids only where the match is unique in
*both* directions, so a trip saved before the field existed keeps working and
nothing is ever guessed.

**A stop can hold more than one waypoint, and `waypoints(forSegment:)` is
plural.** "Ayutthaya · Pai" is one stop naming two places and holding two stamps.
**And the editor offers to add one whether or not the stop already has one.**
Making the *read* plural was only half of it: `ItineraryEditorView` drew
"+ a stamp for this stop" behind `waypoints(forSegment:).isEmpty`, so the state
the plural fix exists for could only be reached on a trip that arrived packed. A
trip typed from scratch could never make the second stamp — on the screen whose
own copy says "A stop can name two places". The gate is `appendCost().refused`,
which is about the last stamp's letter and nothing to do with how many are here.

A `first` here made AYU unreachable from every screen in the app — it could not
be opened, corrected or removed — while every assertion stayed green, because
both still resolved to a stop and both still sorted. Only the screenshot showed
it.

**`index` is derived by `reflowWaypoints()`, which re-stamps `updatedAt`.** Same
relationship `reflow()` has to `startDay`/`endDay`: order is the authority, the
number is output, so a gap or a duplicate is unrepresentable. Renumbering is an
*edit* to every waypoint that moved — the `moveShowCards` lesson — or the other
phone merges the new order straight back out.

**Waypoints stayed a tombstoned collection rather than moving inside `Segment`.**
The itinerary merges whole-document LWW; stamps merge per-record. Nesting would
put `earnedOn` under LWW, so one phone earning Jeju while the other reorders a
leg loses the arrival — with the letter it opened still open. It would also force
a destructive migration through the ambiguous `" · "` matcher, and dropping
either of AYU/PAI changes `orderedStamps.count`, which re-fires every
`.finalStamp` letter including ones already read.

**An earned waypoint is immutable; a letter-referenced one is confirmed, not
refused.** Removing one names the letters that will never open. That only holds
up because `canStillFire` now knows `knownStampCodes` and `knownPlaces`: without
them "not reached yet" and "will never exist" are the same sentence, and an
orphaned condition reads "live" forever.

**Earned stamps come first, in the order they were earned.** `reflowWaypoints()`
sorted every live stamp by plan position, so an earned stamp whose stop was
removed went to `Int.max` — the end of the trail, behind places nobody has
reached — and dragging a stop behind an earned one reordered history. The trail
is where they have been and then where they are going: earned by `earnedOn`,
the rest by plan.

**A stamp whose stop is gone is listed, not left.** Removing a stop takes its
stamps, but a merge can still strand one: the other phone removes the stop
while this one stamps it. `orphanedWaypoints` (live, unearned, `segment(for:)`
nil) is drawn at the top of the plan editor, and `attachWaypoint` puts one on a
stop as an edit; the stamp editor's own remove, with its guards, lets it go.

**A typed waypoint finds its position in a list that ships with the app.**
Nothing gave a typed waypoint a coordinate until somebody stood in it, so the
nudge, the distance to the next stop and the map ahead never happened on a
trip nobody packed. `CityPositions` reads `Resources/cities.tsv` (GeoNames,
cities over 15,000, every Latin-script spelling, made by
`Tools/build-cities.sh`) — never the network, which the app promises not to
need. It searches only inside the stop's own country, largest first: a city
looked up anywhere puts Springfield on the wrong continent and fires the nudge
there, and an unknown country answers nil, the country card's rule (§8.5).
`addWaypoint` fills the position; changing an unearned stamp's city refills it
or clears it; `backfillWaypointPositions()` fills blanks at launch, after a merge
and after every itinerary edit, without touching `updatedAt`, because both
phones read the same list. The list is a closure on the store (`cityList`), so
2.8 MB is read the first time it is wanted and the checks hand in a fixture.
GeoNames is CC BY 4.0: the credit at the bottom of Settings *is* the licence.

**`kilometresTravelled` skips waypoints with no position; it used to zero them.**
`Stamp.kilometres(to:)` answers 0 when *either* end is unlocated, so one
positionless waypoint killed the legs on both sides of it — and a trip whose
waypoints were typed rather than packed has nothing but those. The headline
stopped growing under the words "and counting".

**`arrive(at:)` can only fill a coordinate if something asked for one.** It had
the mechanism and no source: `location.current` is nil unless Separated happens
to be running, so a typed waypoint never got a position. `TrailView` now calls
`requestOnce()` when the confirmation opens, which gives the fix the length of
the dialog to arrive.

**Removing the last unearned waypoint is refused, not confirmed.** `appendCost`
refused an append that would take a `.finalStamp` letter *back*; removal does the
opposite and only one guard existed. Taking away the last stop nobody has stood
in completes the trail, and every letter sealed to the last stamp opens on the
spot with `openedOn` and `openedPlace` written for good.

**A removed code must not come free.** `codeIsAvailable` reads `stamps.live`,
which cannot see a tombstone — so a code a sealed `.stamp(_:)` letter still names
could be handed to a different stop, and the letter would open in Busan at a
stamp the writer never chose. Cities get no such rule on purpose: a place *is*
the place, so a new waypoint for Hội An firing the letter sealed to Hội An is
right. A code is an arbitrary label.

**A city visited twice is offered a code, not a refusal — and the rule stays.**
Bangkok out and Bangkok home is an ordinary route, so the second stop can't have
`BKK`, and that is correct rather than unfortunate: the code is the letter's
address, the writing screen's chips are labelled by it, `earnedStampCodes` and
`knownStampCodes` are `Set<String>` (duplicates collapse, so a letter sealed to
the second visit opens on the first), and `place(satisfying:)` and `dayForStamp`
both resolve it with `.first` — the AYU bug one key over. What was wrong was
being refused *after* typing the obvious answer. `suggestedCode(forCity:)` seeds
`BKK2` off the **first stamp's own code**, not off the city, so it still reads as
Bangkok on the writing screen weeks later, and the note names whose second it is.
Two letters minimum before it suggests anything: the seed is recomputed on every
keystroke of a new stop's title, and a one-letter base numbering itself flashes
`H2` on the way into "Hue".

**The stamp's city is a choice among the stop's own places, and the escape hatch
is for editing only.** On the ordinary stop there is no control at all — the stop
*is* the city, and a text field prefilled with a copy of the title asks a question
already answered. `StampFields.options` adds the stamp's current city when it has
drifted from its stop, so a renamed stop can keep the answer somebody chose rather
than have it silently rewritten under a `.place` letter. Offering that same hatch
to a stamp being *made* is a loop: the city is in the list by virtue of being in
it, so typing "Bangkok" one letter at a time left `Ban` selected against
`Bangkok` — and the repeat-visit note then never fired, because the city it asked
about was `Ban`. Both checks were green; the screenshot is what showed it.

### 3.10 Moments and the trail

`Moment` is a record of standing somewhere, kept on this phone only — no
`updatedAt`, so it can never be merged into `SyncPayload`. What is not
obvious about it:

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

**`Moment` has no `author`, and that is correct.** `JournalEntry` needs one
because a trip can arrive with pages for *both* slots and the book filters to
yours. Nothing ever seeds a moment, so every moment on a phone was made by
whoever is holding it — including after `adopt(_:)` changes which slot that is.
Don't add the field for symmetry.

**The way to make a moment is at the top of the trail, and the list stops at
three.** "Mark this one" was the last thing on the screen, under every stamp
and every moment so far — so the further the trip went, the further away it
got, for the one thing only worth doing in the next ten seconds. It is
`MarkMomentLabel` now, the `spentLabel` corner verb, stacking above the
accessibility threshold; the big button survives only in the empty state. The
list shows the newest `TrailView.momentsShown` and an "All N" row pushes
`MomentsView`. The gate is `!isReadOnly && isLive && !isObserver` — `isLive`
because closing a trip injects no flag.

**The trail's map is a door; the full-screen one is the map.** `TrailMap` stays
`allowsHitTesting(false)` inline and is wrapped in a button with "open the map"
written on it, since a tappable frame looks exactly like a dead one.
`TrailMapView` passes `interactive: true`, which turns each mark into a padded
button — a 6pt diamond is not a target. Its cards never mention letters: the
same screen is on the observer's tab and in the shelf. `TrailView` pushes through
one `navigationDestination(item:)` over `TrailDestination`.

**"Keep a moment here" presents from the cover's `onDismiss`.** The stamp
screen is a full-screen cover; a sheet started while it is still animating out
is the `PhotoIntake` race, so the stamp is held in `keepingAt` and handed to
the sheet once the cover is gone. The moment is filed under the *stamp's* city
through `addMoment(city:)` — they can arrive a day before the itinerary says.

**`photoIntake` asks camera or library, and clears `isPresented` on sight.**
Left set while the source dialog was dismissed by a tap outside, the next tap
would set `true` over `true` and open nothing. The camera ends in the same crop
as the picker. A shot is also written to Photos with **add-only** access, so the
app still cannot read the library; refused, the app's copy is kept and the
composer says the other half didn't happen. No camera (the simulator) means no
dialog with one answer in it. The three usage strings were rewritten to match —
the location one still said "only while Separated is on".

**The replay's last frame is the trail's headline, by construction.**
`TrailReplay` measures along earned stamps with the same function
`kilometresTravelled` now calls (`TrailReplay.kilometres(along:)`), and a check
holds the two equal — a replay ending on a different number would be a second
answer to the trail's one question. It frames on the *finished* trail from day
one: left to follow the earned stamps, day 8 was a close-up of Bangkok. Twelve
seconds whatever the length; with Reduce Motion it opens on the last frame and
never plays itself.

**The trail has one picture, and it is the book's.** The replay on the ending
screen and the shelf was an Apple map while the book drew hairlines — two
pictures of one route. It is `TrailPicture` now, `BookTrail` on the book's paper:
fitted once to the finished trail (`allowsSinglePlace`, since the first frame may
be the only place), with the route not yet walked faint and the walked part in
the accent, the way an opener draws its own country over the rest. A shelved
trip's page carries the same drawing of the whole trail. Moments are hollow
diamonds on every one of them — the replay, the shelf, the book's maps and the
cover — projected like the stamps but never framed, joined or named, and drawn
*under* the dots, since one kept at a stamp sits exactly on it. Because they are
never framed, a far one lands outside the square: `TrailPicture`, the map page
and the cover each clip. The live Trail tab and its full-screen map stay on
Apple Maps; they are interactive and say "you are here".

**Tonight's page borrows a moment's photograph as a copy.** `PhotoStore.duplicate`
under a fresh id, never the moment's own file — `updateMoment` and
`save(entry:)` each delete the file they swap out, so a shared id is a book
missing a picture the first time either changes. The words go in only over an
empty line. The first fills the main photograph and the next fill the extras, up
to the page's three; it used to replace the main one every time, so the extras
could only come from the library. Tapping a moment already on the page takes its
copy back off, by "swap"'s rule — the first extra moves up. Which copy each moment
made is `borrowed`, and "on the page" is asked of the page, not the map, so a copy
removed with the cross isn't drawn as still there. A missed night's composer
offers that night's moments (`moments(onDay:)`, by the day the moment recorded),
not today's. **Borrowing never focuses the line.** It used to, and the keyboard
scrolled the sheet to the field, moving the strip out from under the finger: the
second tap meant for a moment landed on the main photo and opened the library.

**"A year ago today" is memoised per calendar day in `TripLibrary`.** It
decodes every shelved snapshot, which is not something to do on each pass of
`TodayView.body`; the cache clears when the shelf changes. Only this phone's
own pages (`author == snapshot.role`), never an observer's shelf, never an
unfinished moment, and 29 February only on 29 February. `Memory.id` is the
source record's. Nothing seeds a dated record on the shelf, so `seedShelf` now
puts one exactly a year back, and `-screen memory` is Today with it.

**A memory opens the book at its page (`MemoryBookView`).** It opened the
archived trip's page — figures, then a tap and a swipe through every spread —
from a panel showing one night's words. It is that night's spread now, found by
`BookPlan.spreadIndex(containing:)` off the reader store's cached plan, with "the
whole trip" one tap away. Something the book doesn't print — a trip with no
book, a page since removed — opens the trip as before. The reader store is built
the way `ArchivedTripView` builds it, keyless and silent, for its reasons.

**Photographs on the map are still diamonds.** Below `TrailMap.thumbnailSpan`
(0.35° of latitude, about a city) the full-screen map draws a moment's photo
rotated 45° inside its border — the shape is what says "moment" on a map where
filled means earned and dashed means ahead. Zoomed out, and always on the
trail's own map, it stays the hollow diamond.

**A moment's mark on the map is neither stamp mark, and is excluded from the
framing.** Filled accent is earned, dashed n500 is ahead; a moment is a hollow
rotated square in n600, off the polyline. One recorded at a layover airport would
otherwise reframe the whole trail.

**Arriving is suggested, never awarded.** `nearNextStop(latitude:longitude:)`
answers the next waypoint inside `TripStore.arrivalRadiusKm` and refuses
everything `arrive(at:)` would, plus before departure. Today and Trail ask it of
a fix under fifteen minutes old that the app already had permission for; both
lead to Trail's existing confirmation (`ArrivalRequest`, §5).

### 3.11 The meeting point

Tonight's place to meet if the phones die — one value, last writer wins and
always announced (§3.5) — and the history of every place already agreed.

**A blank trip has one, and it is not an answer.** `init`'s blank branch seeds
`MeetingPoint(place: "", detail: "", localScript: "", setAt: .distantPast)` — a
real value nobody chose. Ask `MeetingPoint.isSet`, which keys on `placeKey` so
whitespace doesn't count. `TodayView` was asking correctly and keeping the answer
to itself as a private `hasMeetingPoint`, so Papers printed `". Agreed at 00:53."`
— a bare full stop where the place goes, and `.distantPast` put through a time
formatter — and Separated, the 2am screen, said "Go to the" over an empty card
captioned "show this to a driver". One question on the model, not three views'
worth of guesses.

**Today's sentence is the store's (`meetingLine`), and the possessive belongs
to the detail.** One interpolation read "set at The bridge's  if you lose each
other" with "Which bit of it" left empty; the figures column drew a blank second
line for the same reason.

**Its fallback was unreachable, like `DayDetailView.cityName`'s.** The headline
was `detail.components(separatedBy: ",").first ?? "meeting point"`, and splitting
`""` answers `[""]`, never nil. A `??` behind a split only fires if the split can
produce nothing.

**Replacement copy for an empty state has to compute its own promises too.** The
first version of Separated's said "the distance below is still yours, and the
emergency numbers are still here" — on a trip with no location fix and no country,
both were false. That is the bug being fixed, one card along.

**Tonight's point is one value; `meetingPlaces` is the list, and both are on
`SyncPayload`.** The picker offered "anywhere this trip has already used" and
could name exactly one place — setting tomorrow's was the end of yesterday's, so
a gate they had walked to and could describe was gone the moment it was
replaced. It syncs for the same reason the point does: either of them can be the
one who typed it. Losing the LWW round is not the same as never having been
there, so the merge unions the *history* and last-writer-wins the *point*.

**And the book prints the list: "Where we said we'd meet".** A spread after the
stamps, paged by the stamps' own arithmetic (`pagedRange`), four places a page,
oldest first through `BookPlan.meetingPlacesInOrder` — which the plan and the page
both read. Each place keeps only the last time it was agreed, so that is all the
page claims ("agreed 04 OCT", "in the order you last agreed them"), and the
local script prints as typed. `meetingPlaces` is a book input now.

**A `MeetingPoint` has no id, and must not grow one.** The thing identified is a
gate somebody can walk to: two phones that both typed "the bridge" mean the same
bridge, and unioning by id would list it twice — a per-decode id would list it
twice every launch. `placeKey` (trimmed, folded) is the identity, and
`setMeetingPoint` trims the place because of it.

**The local script belongs to the place, not to the screen.** It is a typed
field on the `MeetingPoint`, and changing "Where" re-derives it from what the
trip knows about *that* place — one gate's script left under another gate's name
is how somebody is driven to the wrong side of a city. Like the show-this card
editor, it says out loud that the app doesn't translate.

### 3.12 Day plans and show-this cards

**Day plans and show-this cards are editable, and therefore on `SyncPayload`.**
They were constants while the sharing screen said "money, **plans**, the trail and
the meeting point are shared both ways". Both are `SyncableRecord` now.

**`ShowCard` carries an `index`, like `Stamp`.** The merge unions into a dictionary
and returns `Array(byID.values)`, so append order doesn't survive a sync. Read
`orderedShowCards`, never `showCards`. Day plans order by `dayNumber`, but
`plan(forDay:)` must read `dayPlans.live` — clearing a day tombstones it.

**A day plan is filed under its stop, not its day number.** Plans joined on
`dayNumber` while `reflow()` renumbers every day on any itinerary edit, so
dragging Chiang Rai ahead of Chiang Mai left Songkran under Chiang Rai with no
warning. `planKey(forDay:)` is the one resolver: the stop covering the day and
how far into it, the last stop's `nights` for the morning they fly home, and
the day number only where no stop covers it. `plan(forDay:)` and `editPlan`
both go through it. A plan past a shortened stop's nights is *set aside* —
`setAsidePlans(forSegment:)`, named under the stop in the editor — and comes
back when the nights do; nothing is written either way. Removing a stop
tombstones its plans. `backfillPlanKeys()` files a plan from the older build,
or a gap-day plan a stop has since come to cover, without an edit, on the
`backfillWaypointJoins()` reasoning. The newest of two answers wins: two phones
writing one day before a round mint two records, and `.first` over a merge's
dictionary order picked one at random. `dayNumber` is still written, for the
older build. `TripShift` leaves plans alone; they were never dated.

**The hours sort by their time.** `orderedItems` parses what people type
("07:30", "7am", "19.15", "12:30 pm") and puts the hours with no clock time
("after dark") after them in the order written. Derived, so the stored order
and the merge are never touched, and the drag handles are gone: the clock is
the order. Read `orderedItems`, never `items`.

**A day plan's `city` is what it was written *about*.** `DayDetailView.cityName`
prefers the segment covering the day.

**`DayPlanEditorView` loads with `.task(id: day)`, not `onAppear`.** `@State`
survives the view being rebuilt with a different `day`, so a one-shot load showed
one day's fields under another day's header. And **editor placeholders must not be
the seeded trip's own words** — the day editor prompted day 12's actual content
under "Day 20 · Chiang Rai", which reads as this day's plan until you notice the
grey.

**The Papers row opens the cards, not the list that manages them.** Making the
cards editable briefly put `ShowCardsView` in front of `ShowThisView`, so handing
the phone to somebody cost a tap, a scroll past every card and a 10pt label at the
bottom — on the one tab that deliberately has no lock in front of it, for exactly
the reason its contents are wanted in a hurry. Showing is the row; `edit` in the
section header manages. Same shape as `ItineraryView`, and worth keeping that way.

**Hold to edit or delete, and the delete is not the same delete twice.** The
ledger's `.contextMenu` — `Edit` / `Delete`, and the hint "hold it to edit or
delete" — is now on the document rows and the show-this card rows, with that
second clause word for word. What differs underneath is the safety net, and it
has to: a card is tombstoned, so it deletes straight through with the ten-second
`UndoBanner` behind it, and `restoreShowCard` is `restore(_:)` one collection
over, fresh `updatedAt` and all. A document is *really* removed and takes its
scans with it — `TravelDocument` must never gain a `deletedAt` — so it keeps the
confirmation in front of it, printing the editor's own sentence through
`DocumentEditorView.deletionMessage(for:in:)` so the two counts can't disagree.
`UndoBanner` moved into `Components.swift` for the same reason.

**A `Section`'s `footer` draws its own white band and ignores `listRowBackground`.**
The cards' hint was a footer and sat on a white strip where the paper stopped. It
is an ordinary row inside the section now, with `.listRowBackground(Palette.bg)`
like the "+ write a card" button above it. And `.contextMenu` *does* fire on a
row in a list with `editMode` active — worth knowing, since that list keeps its
drag handles on permanently.

**A small control directly above a large one needs a padded hit area.** That `edit`
is a 10pt word a few points above a 44pt row opening a full-screen cover at maximum
brightness. The padding goes on the label *before* `.contentShape`, so a near-miss
opens the list rather than the deck.

### 3.13 `SampleTrip` — commented out

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

**`TripStore.init` always seeds a blank trip.** `.packed` is still a real
`TripOrigin`, but the only way to reach it now is a snapshot that carries it —
the shelf, or `Tools/CheckTrip.swift`.

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

### 4.4 SwiftUI traps

Each of these shipped once.

**Absolute offsets must scale with the type factor.** The board's timeline
multiplies every offset by `k` (capped at 1.7) and grows its frame; `DayDetailView`
does the same for the hours column. Without it "12 quiet days" lands on "day 1" and
"07:30" stacks as "07 / :3 / 0".

**`Mono` defaults to n700, not n600, and no `Palette` token changed.** The label
voice renders at 9.5–10.5pt, under the 18pt where WCAG relaxes, and n600 is 3.85:1
against the 4.5:1 small text needs. The ramp is intact; what moved is which rung
small text stands on.

**`TypeScale.factor(for:)` is memoised, and has to be.** It builds a
`UITraitCollection` and calls `UIFontMetrics`, and `ScaledFont` runs it for every
piece of type on screen on every layout pass — while `TripStore` invalidates every
view on every mutation. That put two allocations on the critical path of a bound
`TextField`, once per keystroke per visible label. There are twelve settings and
the answer never changes, so the table is built once.

**`@Published` fires on every set, not on every change — and a set inside an
`onReceive` for that same publisher is a loop.** `InvitationInbox.take()` cleared
`arrived` in a `defer`, so taking nothing still published nil-over-nil, which
re-fired the `onReceive` that had just called it. The loop ran *inside* SwiftUI's
layout pass, so the first render never finished: blank white on every screen, no
crash, nothing in the log. A stack sample was the only thing that showed it — the
same tool that found the checks blocked in `SecItemCopyMatching`. Guard before
you clear.

**A `Task { }` in a view struct is not on the main actor.** Only `body` inherits
isolation from `View`; an ordinary method of the struct is nonisolated, so a bare
`Task` runs on the global executor — and `MoneyView`'s undo timer was clearing
`@State` from a background thread. Swift 5 mode diagnoses none of it. Write
`Task { @MainActor in }`.

**A map that takes no gestures needs `position:`, not `initialPosition:`.**
`TrailMap` sets `allowsHitTesting(false)`, so the initial camera was the only
camera it would ever have: dropping a pin in Huế while the frame was still around
Bangkok left the new mark off the edge for the rest of the visit to the tab — on
the one screen whose whole subject is that it grew.

**Animations go through `gentleAnimation` / `withGentleAnimation`.** Reduce Motion
was ignored everywhere.

**Light appearance is locked on purpose.** The dark screens (stamp, separated,
lock) are deliberate moments in one warm-paper palette, not a dark mode.

---

## 5. Navigation, roles and onboarding

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
every screen launches blank (§3.5). `MarkMomentIntent` (`openAppWhenRun`) sets
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

### 5.1 Today and the way into the plan

**Today's panels are the way into the plan, and both used to be dead.** "First
stop" and "Today together" are the two large bordered cards on the app's first
screen, and neither was tappable: the only route to the itinerary was the 10.5pt
`Day 12 of 61` in the header, and the only route to a day was through the
itinerary and a stop row — so editing today's plan was five taps behind two
10.5pt words. The panel now opens what it is *showing* — the first stop opens
the itinerary, "Today together" opens the day — and the named row under it
(`planRow`, the shape the letters' "All 12 · 3 open" row already had) keeps the
list one tap away. A tappable `Panel` is pixel-identical to a dead one, so each
carries a written affordance line; the before-departure one draws it only when
the trip is empty, because with a stop in it the row directly below says the
same words.

**The "Spent today" figure adds an expense, and the `RateStamp` under it stays
outside the button.** Same complaint, one section down: the figure a reader is
looking at when they think *I should put that in* was inert, while the
meeting-point column beside it in the same `HStack` was a door. It opens
`AddExpenseView` — the sheet the Money tab opens, unchanged, because it is
already self-contained: it dates a new line to `store.now` and takes the local
currency and who is holding the phone on appear. One way to record money,
reached from two places.

**But `RateStamp` is itself a `Button`** — it kicks `store.rates.refresh()` —
so it is a sibling *below* the wrapped column, not inside it. A button inside a
button happens to work and is one refactor from swallowing the tap. That is
also why the meeting-point column gets away with wrapping everything: it holds
no control of its own. The verb rides on the label line through an `AnyLayout`
that stacks above the accessibility threshold, the `CallTileRow` trick — `Mono`
is uncapped there and "SPENT TODAY" already wraps on its own at AX5, so a verb
beside it on one line is "POLIC / E" waiting to happen.

**"Today together" is on every phone, and the letters never take its place.**
It used to be swapped out for the letter card whenever `lettersVisible`, and
the card — the "All 12 · 3 open" row with it — drew only once
`newestOpenLetter` existed. So a phone holding three sealed letters and none
opened had no day panel, no meeting line, and no way into its own letters. The
card now sits *above* the panel when a letter has opened, the "All N" row
(`letterTally`, "3 sealed" with no nought clause) is drawn whenever there are
letters, and the extra "The whole day" row went with the swap: the panel is
always the door to the day. The panel also names tonight's lodging, title only.

**`TodayView` pushes through one `navigationDestination(item:)`, not two
`isPresented:`.** Two of those stacked on one view is the arrangement where the
later swallows the earlier and the push silently does nothing — a dead control,
which is the failure this screen was being fixed for.

**`ItineraryView` had no empty state at all.** With `legs` empty it drew the date
range, the spelled day count, and the aside "Drag a city and the days re-flow"
over nothing to drag — on every trip made through onboarding, which is every
trip. It is a panel plus "Plan the trip" now, the aside moved inside the
non-empty branch, and the corner `edit` is not drawn over an empty trip because
it asks a reader to edit what.

**And the "First stop" panel printed `"—"` over `"12 Jan · "`.** A dangling
separator standing where the country goes — the meeting point's
`". Agreed at 00:53."` exactly, one screen over. The separator belongs to the
country, not to the line.

**No composer drops work on a swipe.** Swiping down, or tapping Close, used to
throw away tonight's page and its photographs, a letter from home, a day plan's
occasion and lodging, and every other sheet with fields in it, with no word
said; `interactiveDismissDisabled` appeared once in the app. Each sheet now
does what fits its kind:

- **New work** (tonight's page, a moment, an expense, an hour, a card, a
  document, the meeting point, a new stop, country or stamp) uses
  `guardsUnsavedWork(isDirty:isAsking:whatGoes:onDiscard:)`. While dirty the
  swipe is held, and both the swipe and Close ask "Throw it away?". The swipe
  is heard through `DismissAttemptObserver`, which joins the presentation
  controller as its delegate and forwards everything else to SwiftUI's, so a
  held swipe asks instead of bouncing.
- **An edit to something that exists** (the day plan's fields) commits on
  `onDisappear`, the setup screens' rule (§5.4).
- **A letter keeps itself.** Leaving any way but Discard saves the draft, a
  draft with no words goes (`discardDraftIfEmpty`), and Discard asks when there
  is something to lose.

Dirty is "differs from what was loaded", so an untouched sheet closes without a
question. The meeting point's "Done" keeps what was typed instead of being a
bare `dismiss()`. A composer's photographs are written to disk at pick time, so
they are held (`PhotoStore.hold`) until the sheet knows what was kept: the
prune runs on every return to the foreground, and an app switch mid-compose
used to delete the photo a page was about to point at.

### 5.2 What the lock is in front of, and why it is a rule

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

**Re-locking on `scenePhase` is the state; `privacyCovered()` is the paint.**
SwiftUI gives no guarantee the re-render lands before iOS writes the app-switcher
snapshot, and that snapshot goes to disk at the ordinary protection class — so a
decrypted passport at full brightness could sit in `Library/SplashBoard/`
underneath the lock meant to prevent exactly that. The cover is driven by
`willResignActive`, which is posted *before* the snapshot, and `ScanViewer` needs
its own because a `fullScreenCover` is presented above the view that spawned it.

### 5.3 One build, three roles

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

**The observer cannot drop a pin; the guard is in the store.** `arrive(at:)` and
`setMeetingPoint(_:)` open with `guard !isObserver`. Home mode draws the
travellers' own `TrailView`, and a pin from a kitchen in Utrecht earned the stamp,
opened the letter sealed to that city, moved `kilometresTravelled` and synced all
three. `HomeTabs` injects `\.isReadOnly` on **that tab only**. Flag = courtesy,
guard = guarantee.

**Per-slot name stamping is not paranoia — there is a third phone.** `DiThoiApp`
calls `syncNow()` *before* the `isObserver` branch, and in home mode `role` is the
traveller written to, so "the remote slot is `role.other`" is unsafe. An unrenamed
slot carries `.distantPast` and can never win one somebody has.

**Names are data; `Traveller` has no `name`.** Slots live in `TripNames`, read only
through `name(for:)` / `myName` / `otherName` / `label(for:)`. The enums'
`name`/`label` were deleted rather than left as fallbacks so the compiler
enumerates every site. `name(of:)` is the `Participant` overload — one shared label
makes every leading-dot call site ambiguous.

**A rename must never ride in `TripSettings`.** Settings merge as one blob on one
timestamp, so a name inside them would win the dates, budget and currency too.
`names` is its own field, merged per slot, and doesn't `touchSettings()`.

**Nor does a feature switch.** `features` never leaves the phone, but its
`didSet` used to stamp the settings blob anyway, so turning the letters off on
one phone would carry that phone's old budget over the other phone's newer one.
Only the dates, budget and currency stamp it now, and a check runs two stores
against one loopback box to prove a later toggle loses to an earlier budget.

**The observer sets no trip parameters.** On a trip somebody filled in they
don't own those answers; on a blank one their settings blob would race the
travellers'.

**`Participant.writer` keeps its raw value.** `decodeIfPresent` *throws* on an
unknown raw value, `TripSnapshot` swallows it with `try?`, and the store re-seeds
over somebody's two months. Renaming a persisted case doesn't lose a field, it
wipes the trip. Same for `Traveller.one` / `.two`.

### 5.4 Onboarding

`ArrivalFlow` is the only setup flow — the first trip and every next one go
through it.

**`TripOrigin` is stored, never inferred.** `!legs.isEmpty` looks like the same
question, but the blank branch hands off to the itinerary editor — so counting
what's inside changes the answer *during the flow it gates*.

**The trip's name is asked on the setup step, in both flows, and the fallback
lives in two places because a frozen summary can't reach a store.** `tripName`
has always existed and the shelf's old new-trip flow always asked for it, but
`ArrivalFlow` never did, so every *first* trip carried `""`, and the spine drew " · 2026", the
live row drew an empty `Text` and the exported book was " — Alex.pdf". The field
is now in `TripSetupView` in all three modes: onboarding asks (and gates Next on
it), adjust corrects what was packed, settings is the
rename — there was no way to rename a trip at all before. `TripSummary.displayName`
mirrors `TripStore.displayName` and `spine` reads it, because an archived row
reads the frozen struct and never holds a store. **The PDF's metadata keeps the
raw title on purpose**; every other site a reader sees goes through a fallback,
including `WidgetBridge`, which substitutes on the way out since `WidgetSnapshot`
is scalars only.

**Its three fields commit on focus loss *and* on `onDisappear`.** Settings has no
Next button, so focus loss was the only commit — type a name, swipe back with the
keyboard still up, and it was gone. All three writers are idempotent, so running
them again on the way out costs nothing.

**The role and the names are one step.** `WhosePhoneView` draws the picker and
the name fields together, so a slot labelled wrong can be corrected where it is
picked. There is no `-screen names` route any more.

**The setup steps are a registry, and it lives in `Model/SetupSteps.swift`.**
`SetupStep.allCases` is in order, and each case answers `isIncluded(_:)`, so
the steps can't be walked by `rawValue ± 1` and a new step is a case plus a
predicate. It moved out of `ArrivalFlow` once the rules branched on four
things, because `Features/` isn't compiled by the checks. The flow holds an
index into the list, so a context change may only add or remove steps *after*
the one on screen:
- `returning` and `returningTraveller` are captured once on appear, because
  the `who` step writes the names and the role that decide them;
- `changingWho` only ever inserts `who` directly after `destination`;
- becoming the observer on `who` moves only steps after it.

A check asserts that last point.

**A returning traveller is asked where next, first.** `destination`
(`NextTripDestinationView`) leads, with who is holding the phone as one line
with "change" on it. The first launch still asks who first, because that
answer decides the whole app. The observer sets no trip parameters, so a
returning observer gets no destination step.
- **Country and first stop are both or neither**, `AddCountryView`'s rule.
  With a leg already in, the fields give way to rows, so a second "Next" can't
  add the country twice.
- **The currency chip is preselected from `Currency.likely(forCountry:)`.**
  It is a guess drawn on a chip and never applied silently. Nil means no chip
  is preselected. `CurrencyChips` shows the likely and home currencies, with the
  rest by name behind "another…", because forty chips are a wall.
- **"Coming along" is applied from a snapshot.** `CarriedOver` is captured
  once, and `applyCarry` runs from it on every continue. Going back and
  ticking a row again gives it back. Each write is skipped when it would
  change nothing, because the settings blob stamps itself on every set, and a
  stamp that changed nothing still wins the merge. A declined card is
  tombstoned, not removed.

**The suggested name is a button beside the field, never its placeholder.**
Grey text in a field reads as an answer somebody gave.
`TripStore.suggestedTripName` counts distinct countries and is checked. It is
not a `Chip`, because `Chip` sets its label in capitals and this label is the
name exactly as tapping will set it.

**The setup step draws the trip's book while it is named.** The next trip's
spine is drawn among the last three shelved ones: the draft name on it, and
its height following the dates. It is the shelf's own `SpineView`, scaled as a
whole. While unnamed, the spine carries the year alone: the fallback "this
trip" is words for a sentence, and on a book it read as a title.

**Every trip is set up here, the first and every one after.** There used to be
a second flow on the shelf, `NewTripFlow`: five linear steps (template, dates,
money, travellers, features). It duplicated `TripSetupView`, had no itinerary
or invite step, and reset whoever held the phone to `.one`. It is deleted.
`beginNextTrip` clears `hasOpened`, and `RootView` hands the phone to
`ArrivalFlow` with the carried answers already in it. Templates are no longer
asked, and the switches moved to settings (`featuresBlock`), which is the only
place they can change now.

**Onboarding ends by offering to pair the phones, and that is where the silent
divergence is actually prevented.** `joinTrip` is the cure; this is what stops
somebody needing it, because it asks at the one moment both people are together
and neither has typed anything worth losing. The step is appended only when
`!isObserver && sync.canInvite` — the share is between the two travellers, and a
step whose only control can't work wastes the first two minutes with the app.

**It runs *after* `commitSlot()`, and `hasOpened` stays false until it is done
with.** The invitation names `role.other`, and `role` isn't final until the slot
is taken — offering it earlier would put a name on the link that the next tap
could still change. `hasOpened` is what ends the flow, so `applySlot()` advances
to the invite step instead of setting it when there is one. Every entry point is
skippable and repeatable: Papers, and the "other phone" block in settings.

**Onboarding splits its commit by reversibility.** `commitNames()` runs on every
continue; `commitSlot()` — `adopt(_:)`, which deletes letters — runs once at the
end behind a confirmation naming what is lost. `TripSetupView` called `adopt`
straight off a picker tap and now shares the fix.

---

## 6. Verification

There is no simulator in CI and no XCTest target. Verification is two things:

### 6.1 `./Tools/run-checks.sh`

Compiles everything in `DiThoi/Model/` and `Shared/` plus `Tools/VerifyTrip.swift`
for **macOS** and runs 1,594 assertions — no simulator; the compile takes a
few minutes, the run a few seconds. It
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
`ScanVault`, which is most of §3.6.
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

### 6.2 `Root/DebugScreens.swift`

To reach a screen without walking a flow (`#if DEBUG`, out of Release):

```bash
xcrun simctl launch <device> com.lovedones.dithoi -resetTrip -screen money
```

76 routes. `savedpostcard` is the saved page on a night the book reaches a
multiple of seven (`-seedItinerary -seedJournal -day 14`); `postcard -week n` is
the postcard sheet; `exportpostcard -week n` writes the PNG and prints where.
`bookpreview -scrubDay n` draws the page bar's bubble held, `entry -promptIndex n`
picks the blank line's question, and `-seedSpending` puts money on every day so
far — nothing else seeds an expense, so the facts line had none. `-day N` moves the trip to that day and may be zero or negative
(`-day -5` is six days before departure). `-screen widget` draws all four widget
families; `dayplan`, `showcards`, `showcard`, `country` reach the newer screens.
`countryedit`, `renamestop`, `addstop` (typed "Chiang Rai", so the "on the map"
line shows) and `placestamp` reach the itinerary sheets; `editororphan` takes
Huế out of the document behind the store's back, the way a merge would, so
"Stamps with no stop" has something in it. Both need `-seedItinerary`.
`book` is the journal list and `shelf` now seeds two archived trips, because
neither could otherwise be reached with anything on it. `finish` is the
finishing sheet, seeded with documents so its papers line is drawn. `between`
opens and closes the trip, then shows the shelf that `RootView` puts in place of
the tabs, with the trip landing on it. With `-seedItinerary` it also seeds
located waypoints and moments, so every clause of the "put away today" line is
drawn. `-settled` consumes the landing first. `nexttrip` is `ArrivalFlow` as "Start the next trip" opens it, after a trip
with a budget and two show-this cards, so "Coming along" has rows.
`nexttripdates` opens the same flow at the name-and-dates step with a country
in, which draws the growing spine and the suggested name. `plan` is the plan
sheet over a live trip. `-planned` seeds a plan (Vietnam and Laos, a
fortnight) on `shelf`, `between`, `nexttrip` and `nexttripdates`, so every
place a plan shows can be photographed. After
`-screen between`, a launch with no flags lands on the real between-trips
root.
`-seedItinerary` fills the trip in — three countries, ten stops, a budget, and
hours on whatever day `-day n` picked. Nothing else does: `TripStore.init` always seeds a
*blank* trip, so `today`, `itinerary`, `day` and `dayplan` had only ever run
against a trip with nowhere in it, and `-screen day` still carries a fallback to
the editor for that reason. It is a flag rather than a property of those routes
because the **empty** states are half of what there is to look at, and have to
stay photographable.
`-seedJournal` writes pages up to the day the trip is on, drawn photographs and
all. Day 4 is a contact sheet with a note; day 9 has no photo; day 10 is the
longest line under the longest note; day 17 is a photograph too small to print
sharp. It also earns every seeded waypoint whose stop has begun, so the map has a
trail. `bookpreview` takes `-spread n`. `exportbook` runs the PDF writer and
prints where the file went. `handoff` is gone with ordering. Like `-seedItinerary`,
it is a flag because the empty book is half of what there is to look at. Seeding
runs in the host's `onAppear`, after the child's, so `-screen entry` needs one
seeded launch before it draws a saved page. `-screen entry -entryDay n` writes
night `n` instead of tonight and keeps two photographed moments on it, so the
strip that fills the extra photographs has something to fill them from; with
`-seedJournal`, `-entryDay 13` is a missed night. `-seedJournal` also seeds three
meeting places, for the book's "Where we said we'd meet", and one moment in the
second country, so its opener carries it. `memorybook` is what tapping "a year
ago today" opens. `reader -spread n` is the full-size book in landscape, since a
full-screen cover is a tap `simctl` can't make — and `simctl io` captures in the
device's own portrait frame, so its screenshots come out sideways (`sips -r 270`).
`invite` is onboarding's last step; `join` and `joinasking` are the invitation's
two branches — the second is the one where the share doesn't name a slot, so the
picker is drawn. All three need
`DiThoiCloudKitEnabled` on to photograph the invite side, and turning it on means
adding the entitlement too: the flag asserts a container rather than checking for
one, so flag-on-entitlement-off traps in `CKContainer.__allocating_init` the
moment a sync round starts. On the simulator that builds and installs happily.

**Nothing seeds a moment, so a debug route has to make some.** `-resetTrip`
leaves zero, which puts the list, the map marks and the book's moments pages out
of reach. `-screen moments` seeds six, spread over days, stops and one before
departure, through `restoreMoment` — the one mutation taking a whole value.
`momentslist` and `trailmap` use the same six, and with `-seedItinerary` all
three also get `seedWaypoints`: five located stamps, two earned, since nothing
else makes a stamp and every map so far had drawn moments over no trail. **They are seeded in the host's `onAppear`, after `-day` and
`-seedItinerary`** — a child's `onAppear` fires first, so seeding there filed
every moment on a blank trip's day 1 whatever the flags said.

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

107 screenshots — every screen, plus accessibility variants — are in
[Screenshots/](../Screenshots), at the repository root.

**A Simulator window can stop repainting while the device is fine.** After a
reboot of the device under a running Simulator.app, the window drew black, then
blank white over an app whose main thread was idle and whose `simctl io
screenshot` was correct. Taps still land. Trust the direct capture, not the
window — and sample the process before calling it a layout loop.

### 6.3 What screenshots caught that assertions couldn't

Eleven rounds, every suite fully green over a screen that was wrong. Every one is
about what a *reader* concludes, which is what an assertion cannot hold. Take the
screenshots.

- **Phase 2** — an invisible "sealed" dot (`Palette.a100`), four overlapping
  timeline labels, a `Rule().frame(width: 1)` that drew a dot, "About 1 MB… so this
  wants real wifi" on a book with no photographs.
- **The mark** — a green stub painted before departure, the final day's dot as an
  arrowhead welded to a bar, a Lock Screen headline truncated to "…until Se…".
- **The editors** — "SONGKRA / N" broken across a word, "07:30" stacked as
  "07 / :3 / 0", a placeholder reproducing day 12's plan under "Day 20 · Chiang
  Rai", a Thai prompt on a card written in Busan.
- **The card and the shelf** — "POLIC / E" over three mismatched tiles, a hatched
  drawing of a trail nothing could open, "not synced yet" on a two-month trip, a
  print order that reported success and changed nothing, "It's out of your hands"
  over a letter that had gone nowhere.
- **The waypoints** — AYU missing from the editor entirely, because both it and
  PAI belong to "Ayutthaya · Pai" and the lookup returned `.first`: one record
  unreachable from every screen in the app, with both checks green because both
  still resolved and both still sorted. Also "Earned on 26 Jul. A stamp can't be
  undone." wrapping to three lines under *every* earned waypoint at an
  accessibility size — six on the two-stamp row, for a rule the arrival dialog
  already states.
- **The security pass** — "Send to Emmie" on the passport screen, a button that
  set a flag, said "Sent", and did nothing, under a line promising a copy on the
  other phone. It had been photographed as a working control since Phase 1. The
  same pass found `-screen document` silently falling back to Papers on a blank
  trip, which is *why* nobody had looked at it since — and then, once the route
  reached the screen, "DOCUMENT 1 OF 0".
- **The stamp fields** — a place picker offering `BANGKOK` and `BAN` as if they
  were two places, with the half-typed one selected, because the drift escape
  hatch fired on every keystroke. The repeat-visit note it hid was the feature
  being built, and the seeded `BAN2` was right by coincidence of the truncation,
  not by recognising the second visit. Every model check passed: the store's
  answers were correct, and the view never asked it the question.
- **The documents** — four in one pass, over a green suite that proved the strip
  worked. "Close ?", a bare question mark where a blank trip's name goes, which
  is the meeting point's ". Agreed at 00:53." exactly. "Delete a single page,
  photo or letter" directly under "Empties 3 documents and 3 scans", where
  "page" had quietly started meaning a scan. "Blank p…" truncated *in an
  editable field*, because the label was capped at an absolute 130pt that
  doesn't grow with the type factor. And a closed trip still offering "tap to
  import one" and `edit` over three fields reading "emptied", because the gate
  was `isReadOnly` — which the shelf injects and closing a trip does not.

- **The book's additions** — two, over a green suite. The postcard's dashed
  rule was a `Rectangle` stroked with a dash, which strokes *both* edges of a
  one-point box and drew a zigzag. And the first prompt cap of 44 dropped every
  seeded moment, so the composer asked "What did you eat?" on a day with a dog
  in it. Neither was wrong to any assertion.

- **The trip's name** — two, both on the screens the name had only just started
  reaching. The cards' hint sat on a white band, because a `Section` footer draws
  its own background and takes no `listRowBackground`. And the book's title page
  set "Somewhere warm" as "Somewh / ere / warm" at 76pt: the name is typed by
  whoever made the trip, so a word wider than the page is ordinary, and the page
  had never had a word on it before — the check that the fallback resolves was
  green, and would have stayed green through the binding.

- **The book** — four, in one pass, over a green suite.
  - Every day's photograph and its line were on the two sides of one leaf.
  - The last night was filed under "Elsewhere".
  - The design file's caption for the map was printed on every country opener.
  - The whole-trip page set its dates through the first figure's label.

  None of it was reachable before `-seedJournal`, because every book route had
  only ever drawn an empty journal.

- **Finishing a trip** — two. The finishing sheet's headline was the trip's
  name alone, so an unnamed trip was headed by a lowercase fragment,
  "this trip". It is a question now, "Finish this trip?", which reads either
  way. And the nudge on Today never appeared under `-screen today -day 63`,
  because `isOverButOpen` also asked `hasOpened`. Today is only ever drawn once
  that is true, so the extra condition guarded nothing, and it hid the panel
  from the only route that could photograph it.

From the rounds before the screenshot matrix:

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

Weighed against the [August review](archive/Review-2026-08.md) and left on
purpose, so the next person meets them deliberately. The bugs found since are in
[CHANGELOG.md](CHANGELOG.md#known-issues).

- **`TripStore` is ~3,500 lines and every mutation invalidates every view.** The
  seams are clean; what blocks splitting is that they all mutate one persisted
  blob. Cost is redraws and reading time, not correctness.
- **`Participant` / `Traveller` / `Payer` overlap**, as do `name(for:)`,
  `name(of:)` and `label(for:)` — a comment standing where a protocol should.
- **Portrait-only, iPhone-only** — except the book reader, the one screen a 2:1
  spread needs. See §8.2.
- **No localisation**, in an app for Dutch travellers in three countries. Out of
  scope by decision.
- **Show-this cards ask for a language the app can't check.** The editor says so;
  the alternative is a translation service it has no way to be honest about.
- **`VerifyTrip`'s main narrative is one store's life.** Independent suites build
  their own.
- **`DocumentStore`'s image handling has no test coverage**, being the one model
  file that can't build for macOS. It is now only `UIImage` ↔ JPEG: the crypto
  and the Keychain are in `DocumentCrypto`, and the files, their names, their
  order and the prune are in `ScanVault`. Both are checked.
- **`PhotoCropView`'s rasterising has no check**, for the same reason PDF
  import has none: it is `UIImage` work. What it is handed and what it computes
  are both checked — `PhotoCrop`'s clamping is swept over every zoom and offset
  — but what it *draws* is not.
- **PDF import has no check either**, for the same reason — PDFKit rasterising
  is `UIImage` work, so `DocumentImport` lives in `Features/`. What it hands to
  the vault is checked; what it makes is not.
- **The letters' sealing has never run against real CloudKit.** The crypto is
  checked end to end through the loopback; `parent`, `encryptedValues` and the
  share hierarchy are written to the shape CloudKit documents and nothing more.
- **Neither has the pairing, and it is the half that needs two accounts.** What
  is checked is everything on this side of the wire: that two phones start on
  different trips, that a record name reads back as the trip it names, that
  `joinTrip` takes on the id and the slot, that an open trip is shelved rather
  than lost, and that a second tap on the same link asks nothing. What has never
  run is `CKShare` itself — minting the invitation, `container.accept`, and a
  participant reading the owner's zone through `sharedCloudDatabase`. The one
  thing that *has* executed is the container and `locate`, against a simulator
  with no iCloud account: private database first, then the shared zones, then
  `NoAccountExists` on the screen as "Sign in to iCloud on this phone…".
- **`UICloudSharingController` is not used, so there is no participant list.**
  The invitation is a URL out of `invitation(to:named:inviting:)` handed to the
  share sheet, which is enough for two people and reuses the sheet the book
  already exports through. What it doesn't give is seeing who has joined, or
  removing them. If the trip ever holds more than two, that is the seam.
- **File protection classes are a no-op on the simulator.** That the trip is a
  file and the preferences are empty is verifiable there; that it is unreadable
  while locked is not.
- **The dark and tinted app icons lose the optical cuts**, because of the `actool`
  limitation. The default appearance keeps all three.
- **The widget has no configuration and is unverified on a real Home Screen.** The
  timeline, group container and `Assets.car` renditions are checked; nothing has
  dragged it onto a springboard.
- **Page 800 gets no cover.** Lulu's spine table lists 800 twice, at 2.0625 and
  2.125 in, and no template has settled it. `CoverSpec` answers nil there rather
  than pick one, and the print screen says "none at this page count".
- **Spine type below half an inch is the app's call, not Lulu's.** A quarter-inch
  case-wrap spine (24–84 pages) carries no type, and the 1/16 in inset either
  side of the spine's type is ours too.
- **The PDF is sRGB, not PDF/X, and embeds the system fonts.** Lulu accepts sRGB.
  New York and SF Mono are embedded as subsets, which is what makes the type real.
  Whether Apple's font licence covers handing them to a printer is unchecked.
- **Nothing measures a real photograph's file size.** The print screen estimates
  2.5 MB a photograph. The seeded ones are drawn and compress to a fraction of
  that.

And, from before:

- **Sync is whole-payload, pull-merge-push.** Fine for two people and a
  two-month ledger; wrong for a long trip or many devices. There is no change
  token, no delta, and no push notification — a round only happens on launch, on
  foreground, or when someone taps. For letters that is acceptable, since the
  channel's whole premise is slowness; for a meeting point it is the known gap.
- **Prose that arrives with a trip carries whatever names it was written with.**
  A document titled by hand keeps its title when a slot is renamed, so a renamed
  traveller can get "Kim · document 1 of 6" over "Passport · Alex".
- **No conflict UI beyond a notice.** The loser of a last-writer-wins merge is
  announced but not recoverable — there is no "restore what I had".
- **Map tiles need the network.** MapKit degrades to grey offline; the route and
  pins still draw. Genuinely offline tiles would mean bundling them.
- **`Screen`'s `ScrollView` still has no lazy stack.**

---

## 8. Features, one at a time

Each of these turned out to be mostly one decision.

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

**`RitualClock` stores the zone it learned in.** Observations are wall-clock
minutes, so without it Amsterdam → Bangkok dragged a learned 22:40 to 04:40. The
notification is scheduled from an interval, not calendar components, which resolve
against the device's zone *when they fire*. It never touches
`UNUserNotificationCenter` before permission is held, and asks after the first
saved page, not at launch.

**`save(entry:)` replaces on `(dayNumber, author)`.** Re-opening last night's page
must not append a second one, or a page edited twice prints twice. Swapping the
photo deletes the file it replaced.

### 8.2 The book (`Model/Book.swift`, `Features/Book/`)

`BookPlan` is derived, never stored — the same reasoning as every other number
in the app. A written night is a **spread** (photo page, text page), page
numbers come from the spread's index, and the contents sections are computed
ranges. The checks assert that the sections tile the book exactly and never
overlap.

**`BookSpreadView` draws the preview *and* the PDF.** A preview rendered by
different code from the print file is a preview that can lie. `ShowCardFace` is
the same idea for the cards. `SavedPageView` draws it too, for the same reason.
**A spread is two pages** and page numbers derive from the spread index. Nothing
stores one.

**Facing pages are an even page and the odd one after it.** Spreads were numbered
(1, 2), (3, 4), which is how a PDF viewer shows them and not how paper folds. Every
day's photograph printed on a right-hand page and its line on the *back of the
same leaf*. Every assertion was green, because each one checked the arithmetic
against itself. `.opening` and `.closing` are half-spreads: the inside of each
cover is the other half and never prints, so page 1 is the half-title alone.
`BookPlan.leftPage(ofSpreadAt:)` is the one formula, and a check holds every day
spread to an even page.

**The last night of the trip is in the last country.** `endDay` is the day they
leave, so `build` sent the night before the flight home to "Elsewhere", after
every country. The last leg keeps every day from its start, which is
`lastKnownSegment`'s rule.

- **A page written off the itinerary is still in the book.** If a city is
  dropped, its pages would otherwise vanish from the plan — the worst bug this
  thing could have. `BookPlan.build` sweeps up anything unplaced into an
  "Elsewhere" section, and the checks cover it.

**The PDF is drawn, not photographed.** It was an `ImageRenderer` *bitmap* per
spread, which meant:
- all the type was pixels, under a spec row saying "fonts: embedded";
- each page held the whole spread, so every photograph was in the file twice;
- there was no trim box.

`ImageRenderer.render` now draws straight into a `CGContext` PDF. That gives real
type with subset fonts, one JPEG per photograph (passed through, not re-encoded),
and MediaBox, BleedBox and TrimBox on every page. The context stays open across
`await`s. `UIGraphicsPDFRenderer.writePDF` has a synchronous closure, so its
"yield between spreads" never happened: the progress label never drew, and the
stop tap could not land. **Check the file, not the screen.** `-screen exportbook`
writes it without the share sheet, and `-cancelAt 0.3` stops it partway.

**The trim is 8.5 × 8.5, Lulu's square, with a 24-page floor.** It was 8 × 8 under
a comment saying Blurb and Lulu both stocked it; neither does. `.notes` spreads pad
up to `minimumPages`. They are counted like every other kind.

**Volumes are real spreads (`volumeSpreads`), one file each.** `pagesPerVolume`
used to be arithmetic, while the writer wrote one file whatever the count. Each
volume opens and closes like a book. An opener travels with its first day, a
country's moments stay in the volume of the night before them, and the stamps
and the whole trip go in the last volume. `split` used to send a non-day spread by
the count of days already *passed*, which after a country's last night is the
next volume's share — its moments would have opened the next book.

**Every volume prints its own contents, numbered to its own pages.** The preview
listed sections for as long as there was a preview, and the bound book had no
contents at all. `.contents(page:)` follows the title spread in every volume
(page 4, with page 5 ruled for notes unless the list turns onto it), and reads
`volumeSections`, not `sections`: the writer numbers each file from page 1, so
the whole book's numbers are wrong in every volume after the first. Sections
are paged in `assemble` from where each spread actually landed, keyed on the run
of spreads they belong to, so two Thai legs of the same length are two rows.

**The app does not order prints, and must not pretend to.** "Send it to the
printer" set `bookOrder` on this phone and reached no printer, then said "Both
books are ordered · two boxes at the door". It could never have ordered both: the
other book's pages are only on the other phone. `PrintHandoffView`, `BookOrder`,
`PrintService`, `place` and `draftOrder` are gone. An old file's `bookOrder` key is
passed over by the keyed decoder, and `TripSummary.printedOn` stays optional and is
no longer written or drawn. Export works from the shelf too: it mutates nothing.

#### Printing sharp

**The Book tab says what will print soft while it can still be fixed.** One
sentence, `PrintReadiness.earlyLine` — "Before it prints: a photo on day 17 is
small for its page, and one moment has nothing in it yet." — with "fix the first"
opening that night's composer or the moment. Only on a live trip printing a book:
after it, the photograph can't be taken again. It measures in a `.task` off the
main thread, and `PhotoStore.pixelShortEdge` is memoised per id, which is safe
because an id names one file for good — every save, crop and borrowed copy mints a
fresh one. The print screen used to be the first place either was said.

**`softBelowDPI` (250) is not `dpi` (300).** 300 is what a photograph is *saved*
at. Squares cropped for the old 8 × 8 trim are 283 dpi on this page and print
fine; warning on them would be the always-true warning again. A photograph is
measured at the fraction of the page it prints at (`PhotoMeasurement.printedFraction`):
full bleed, a contact sheet's two-thirds or one-third, or a moment's third.

**The 300 dpi check measures the *short* edge.** `pixelLongEdge` returned
`max(width, height)`, so a 2475 × 1856 landscape reported clean at 300 and
printed at about 225 — the page is square and fills, so the shorter edge is the
one stretched to 8.25 inches. `pixelShortEdge` is what makes the warning honest
about photographs already on disk; cropped ones are square, so the two agree.
The arithmetic is `BookSpec.printedDPI(forSquare:)`, asked by the crop screen
and by `PhotoMeasurement` alike, so the warning on the way in and the warning on
the print screen cannot disagree about the same square.

**And the crop screen's warning branches, because one sentence is wrong half the
time.** A photograph small enough to print soft *uncropped* is nothing anybody
can fix by pinching out, and "this close in" said to somebody who has not zoomed
sends them looking for a control that will not help. It said exactly that on the
first run. The instruction line also stays put rather than being *replaced* by
the warning, which took the words "pinch to zoom" off the screen at the one
moment somebody needed to pinch back out.

**`BookSpec.bleedScale` is one number for both axes.** Scaling them separately —
1.0156 against 1.0313 — made every printed page 1.5% taller than wide, type
included. Invisible on screen, permanent in a bound book.

#### The pages

**A day's layout is `DaySpreadLayout`, from what the page holds.** One photograph
is full bleed; two or three are a contact sheet; none is the day set in type.
The no-photo layout used to be a hatched box captioned "no photo · the page still
prints", and it went to print. The store, not the composer, holds the limits:
`lineLimit` 120, `noteLimit` 240, `extraPhotoLimit` 2. `save(entry:)` clamps and
promotes, and the note steps its type down through `ViewThatFits` rather than run
off the page. The date and place are the right-hand page's heading and nowhere
else: the contact sheet and the quiet page both captioned them too, so they
printed twice. `extraPhotoIDs` and `note` are `decodeIfPresent`; everything else
in `JournalEntry` is `decode`, and a throw there re-seeds the trip. **Walk
`allPhotoIDs`, never `photoID`, in anything that keeps or deletes a file**:
`referencedPhotoIDs`, both halves.

**The composer deletes nothing until it knows what the page kept.** "swap"
deleted the *saved* page's file on the spot, so swap-then-Close left the page
pointing at nothing. `madeHere` is what this sheet wrote: at save, whatever the
page didn't keep goes; on an unsaved close, all of it goes. The page's previous
file is `save(entry:)`'s to let go.

**The composer is line first, and nothing grows above the picture row.** It used
to open on the city at 32pt, an aside, a "finish it" row, the moments strip with
its own aside and a full-width photo square — so on any night with a moment the
line was below the fold — and six sentences on it described the screen rather
than the day. Now the header is one line ("Day 12 · Chiang Mai · p. 10"), the
line opens focused, and under it is **one row** of everything that can put a
picture on the page: the "+", the night's moments, and tonight's unfinished
spots as dashed tiles that open the moment instead of copying it, because they
do something different and so must look different. The chosen photograph and
its extras appear full width **below** the row, so the row never moves between
two taps — the same failure as focusing the line, by another route. Tiles are
the mounted size (a photograph is drawn at `tile - 12` because `photoMount` adds
6 a side), or a photograph stands taller than the "+" beside it. Two rules held
from before: borrowing never focuses, and a missed night shows that day's
moments. Focus on open is skipped at accessibility sizes, where the keyboard
would cover the row, and on a page that already has a line. "A night you
missed" is its own line under the header: appended to it, it ran into "Close".

**Moments are packed by what they hold (`momentPages`).** In words a moment weighs
two, with a photograph three, against a page of six. The cut happens once, in
`build`, and the `.moments` spread *carries the ids* each page draws — so what
the plan counted and what the page prints cannot disagree. `moments(onPage:)`,
which re-cut the list from the view, is gone.

**A missed night leaves a line, not a gap.** `BookPlan.missedBefore` is the run of
unwritten days before each page, and the text page prints "Days 13–14 · no page"
on the page number's own line, so `DayTextPage`'s proven geometry doesn't move.
`skippedDays` is derived from it. Only gaps *between* pages: the days after the
last one are the future on a live trip, not something missed.

**The line's size follows its length (`DayTextPage.maxScale`).** Every line used
to be tried at the same largest size, so four words and a paragraph that both
fitted were set identically. A short line now caps at 1.45×, a medium one at
1.2×, and `ViewThatFits` falls back through `scales` as before. The worst-case
proof is untouched, because the smallest scale is the same; a second check sets
an ordinary line at each threshold and proves it fits at its cap, so the ladder
never quietly relies on the fallback.

**The stamps page draws the arrival screen's seal (`StampSeal`).** It was a grid
of bare circles while the screen that hands the stamp out drew code, rule and
date in a ring — the printed record of where they stood looked lesser than the
moment. One view for both, proportioned off the 186-point seal; the book passes a
`dateSize`, since a proportional date on a 65-unit seal prints at about five
points. The city goes under each seal, which took the fourth row:
`stampsPerPage` is 12.

**The day page's text is proven to fit, not hoped.** `DayTextPage` holds the
page's geometry: a fixed text box, the rules and footer around it, and the type
sizes. `scales` is the list of sizes tried, largest first. The checks set the
worst text the store accepts in New York, the face `.serif` resolves to, via
CoreText:
- inputs: the longest line and note in W's, as one unbroken word, as wide
  words, and as emoji;
- page sizes: print, and two phone preview widths;
- the assertion: each fits the box at the smallest scale.

The phone sizes are the ones that bite. SwiftUI rounds fonts to whole points, so
a small page's type is proportionally bigger, and the first run failed there
until two smaller steps were added. The `minimumScaleFactor` under the last
step is a floor nothing saved can reach. `-seedWorstPages` writes days 11 and
12 as those worst cases, to photograph.

**A day's occasion is its own line under the heading (`occasionLine`).**
"Market day" was written on the day's plan and printed nowhere. The heading
already fills its line at "Chiang Rai", so the occasion takes a line of its own,
as on the day screen, and `textHeight(hasNote:hasOccasion:)` takes that line out of
the box. Every proof runs with it too: the worst text, the ladder, and the
arithmetic that the box and everything around it fill the page.

**The day page's footer carries what the app already knows: "฿1,240 · 14 km ·
3 moments" (`DayFacts`).** Every figure is computed; a temperature was asked for
and refused, because the app holds no weather. Three rules:
- **The money is that day's leg's currency, not `localCurrency`**, which is
  today's — a night in Hội An reads in dong after they've flown on. The "≈"
  follows `spentTodayText`: only when a rate was needed.
- **The kilometres are the trail's, shared out by day.** `kilometresWalked`
  credits each leg to the day its arriving stamp was earned and hands out the
  whole kilometres by largest remainder, so the days sum to
  `kilometresTravelled` *exactly* — a check holds them equal. Rounding each day
  on its own gives three 0.5 km days a total of 3 under a headline of 2.
- **It is not cached, on purpose.** Expenses are not book inputs. Memoise it and
  `expenses` has to join `bookInputsChanged()` first, or the money on a page
  freezes the first time it is drawn.

It shares the tags' line, so the text box and every proof of it are untouched,
and **the tags win**: they are somebody's words. The facts take what is left,
the longest of `lines` that fits, a clause shorter at a time, money last. An
ordinary day prints whole beside two tags on paper; a phone preview rounds its
type up to whole points and may drop the last clause, the way the text box's
own scales can differ. Both are checked in CoreText. Its tracking is 0.1, not
the tags' 0.14 — at 0.14 an ordinary day fitted on paper by five units.

**The heading's accent rule is the trip mark now.** `DayTextPage.mark` (4 units)
replaced `rule` (1), and the extra 3 came out of the gaps either side, so
`textHeight` is the value it was; a check pins all four heights to their old
numbers. `.lockup` doesn't bleed, so the last night's dot is clamped inside.
Day pages only — openers and the rest keep their own rules.

**The blank line asks a question about that day (`LinePrompts`), and every
prompt must end in "?".** Grey text in a field reads as an answer somebody gave;
a question can't. It replaced yesterday's line, and `previousLine` is gone.
Questions come from the day's arrival, plan items and moments, else a generic
five — only *that* day's, so a missed night gets its own. Titles lead
("Wat Phra Singh: how was it?") because lowercasing one mid-sentence is guessing
which words are names. The cap is 60: at 44 every seeded moment was too long
and the day asked what they ate. Chosen once on appear, never on a timer.

**Book and cover type never follow the reader's text size.** `BookSpreadView`
and `BookCoverView` pin `dynamicTypeSize` to `.large`: they are pictures of
printed pages. Unpinned, an accessibility size grew every heading by up to 2.4×
inside a page that stayed the same size, so the preview stopped being the book.

**"Page" means a page of the book.** The Book tab's corner said "12 pages" (entries)
over a row saying "34 pages", and the composer's "page 12" meant the twelfth entry.
`nightsWritten` is the count; `bookPage(forDay:)` is where a night lands.

**`BookPlan.pagesPerVolume` counts the spread kinds; it used to subtract.**
"Everything that isn't a day, the title or the stamps must be a country opener"
was true while there were four kinds and silently wrong at five — the new kind
lands in volume one and every total still adds up. The check is the accounting
identity: the counters have to account for every spread there is.

**`PrintReadiness.softSummary` lists days, so it dedupes.** A page and a moment
on one day are two soft photographs and one day to go and look at; it read
"day 22, day 22 and day 31". The count stays per photograph.

#### Maps, moments and the cover

**The map is arithmetic (`BookMap`), and so is where its names go.** It is
equirectangular, unwrapped across the antimeridian, and the aspect is kept.
`labels(all:)` places each name right of its dot, else left, else drops it.
Bangkok and Ayutthaya printed their names through each other. Nil under two
distinct places: the opener then sets the leg's stops as type, never a hatched
box.

**An opener's map frames its own country (`framing:`).** Fitted to the whole
trip, Vietnam's opener was one green dot beside the jump to Seoul. Every place is
still projected, so the rest of the route lands outside the square and runs
faintly off the *page* — the clip is on the page, not the square, or the line
stops in mid-air. `minimumSpan` (1.5°) keeps a one-stop country a dot in a
city-sized frame rather than an infinite zoom, and a label is never placed for a
mark off the square. A country with no located earned stamp of its own gets its
stops as type: it used to get the whole trip with nothing highlighted. The
whole-trip page and the cover pass no framing and are unchanged. Below
`mapAloneFrom` (three) of its own located places the map is half size with the
stops under it, since a dot and a line is not a page. A name's box is at most 40%
of the square and its gap clears a moment's diamond: at a fixed 96 units a name
had no room either side of a half-size map and was dropped — Huế, unnamed, on the
map that was about Huế.

**Moments print with their country, after its last night.** They were one
section at the back, so "the dog that followed us the whole way up" printed a
hundred pages after day 12. Each leg's moments are cut into spreads under "Along
the way · Vietnam", inside that leg's section, so the contents range covers them.
Day 1 or later goes by the entries' own rule (the last leg keeps every day after
its start); before departure is a "Before we left" section ahead of the first
country; on no itinerary at all, "Elsewhere". A country with moments and no
written night still gets its opener. An odd last page faces the ruled notes
page, never a heading over nothing. The layout is the same on every page, which
is still how the seventh record keeps printing; and the pages still make no
verification claim, since "only appeared when the phone agreed you were really
there" is true of a stamp and false of a moment. Under "Before we left" a
moment's caption is its date alone — the heading already says the rest.

**A short group rides on its opener (`openerCarries`).** Up to two moments in
words, or one with a photograph, each within `OpenerMoments.noteLimit`, print on
the opener's left page between the dates and the figures, with the country's name
set smaller to make the room. One moment used to cost a spread: one tile facing a
ruled page. The opener carries their ids (`countryOpener(…, moments:)`), and
`spreadIndex(containing:)` and every walk of the moments look there too. A
CoreText check proves the largest allowed group fits the band at print and both
phone sizes. The price, and it is a real one: those moments print a few pages
*before* their days.

**A volume that opens partway through a country lists it as "Thailand,
continued".** `Placed.country` is what lets `assemble` tell; a check holds that
the word appears exactly when a volume's section begins mid-country.

**The cover is `CoverSpec`, and every number in it came off Lulu's own
templates.** They are in `Tools/LuluTemplates/`: the 8.5 × 8.5 case-wrap photo
book (`CoverSpec.product`) at 24, 84, 140, 300 and 500 pages, fetched from the
service behind the pricing calculator's "Custom Cover Template" button
(`api.lulu.com/cover/api/v1/template/?binding_type=CW&…&num_pages=N`). A check
rebuilds each template's total size.
- **The geometry:** boards are 8.75 × 9 in, larger than the pages. A 0.625 in
  wrap folds round every edge, and the safety margin is another 0.625 in from
  the wrap edge, the spine side included. The barcode box is 3.622 × 1.26 in,
  bottom of the back, against the spine-side safety line, and the back's
  artwork stays above it.
- **The spine table** is Lulu's published one. It overlaps itself at 84 and
  140, and the templates settle both: 84 is 0.25 in and 140 is 0.5 in.
- **Every PDF box is the whole sheet**, as on the template, because the wrap is
  artwork, not bleed to trim.
- **One cover per volume, each sized to that volume's own page count.**
- **To check one by eye**, draw the template over the exported cover at 35%:
  the boards, spine and safe areas have to line up.

**The cover is paper, drawn in the app's grammar, and its cream is not the app's.**
`BookCoverView` sets the front like a screen header: tracked label, serif title,
the trip mark as the rule, then an italic aside. The mark is one walked line from
the back's safety edge, across the spine (drawn in the ground colour there, so it
reads through the green), ending in its dot under the title. The spine is the
shelf's green stripe made physical, and it runs 1/16 in past each fold so a
binding a millimetre off still shows green. The ground is `CoverStyle.cream`
(#EDE3D3, the colour of a well-loved book's paper). `Palette.bg` is near-white
and would print as plain board. `.ink` exists and is not the default.

#### Photographs in

**The page is square, so the photograph is cropped on the way *in*.** It used
to be cropped on the way out, twice, by nobody: `BookSpreadView` centre-cropped
to 1:1 at print time and `JournalPhoto` centre-cropped into a *third* shape on
screen — a fixed height at full width. Three apertures, none of them chosen by
the person who took the photograph, and a landscape shot cramped on screen into
neither of the shapes it would print in. `PhotoCropView` now asks, and
`PhotoStore.save` stores the square that comes back. The arithmetic is
`PhotoCrop` in `Model/` — Foundation only, `Double` throughout, the `TripMark`
arrangement — because the failure is a rectangle walking off the edge of the
source, which is invisible in a screenshot of a photograph big enough to hide
it. Every mutation goes through `clamped()`, so there is no state where the
square hangs over an edge, which is why the view has no empty gap to render.

**Crop with `UIImage.draw(at:)`, never `CGImage.cropping(to:)`.** The picker
hands back a `UIImage` whose `imageOrientation` may not be `.up`, and `cgImage`
is the raw un-rotated buffer — cropping there takes the wrong quarter of a
photograph held sideways, silently, and only for the people whose phone was
rotated.

**`JournalPhoto` takes a side, not a height.** `TrailView` used to wrap it in a
second square frame with a comment explaining that asking for a height alone
gave every moment *without* a photograph a taller box than the ones with. The
shape was the caller's problem when it should never have been anyone's. A
photograph saved before the crop existed is not square and is centre-cropped
here — which is exactly what the book already does to it, and is the point: the
app stops disagreeing with the print file without a migration.

**The picker and the crop are two presentations, and neither end of the picker
is reliably last.** `PHPickerViewController` dismisses *itself*, synchronously,
inside `didFinishPicking`, and only hands the image over once `loadObject`
finishes — a runloop turn or more later. Driving the crop off `onDismiss` opens
it with nothing to crop; driving it off `onPicked` can start a presentation
while the sheet is still animating out. `PhotoIntake` calls `open()` from both
and lets whichever is last win. **And the cover is `item:`, not
`isPresented:`** — a separate flag and payload can disagree, and did: the cover
opened with the photograph still nil and drew an empty white screen over the
composer, with the main thread *idle* and nothing in the log. Not the layout
loop that white screen usually means; a stack sample is still what tells the two
apart.

#### Reading it, and the derived values behind it

**The book is cached, and seven `didSet`s are what keep the cache honest.**
`bookPlan` was rebuilt on every read. Today rebuilt it on every pass of its body
to ask `countryJustFinished`, and the composer rebuilt it on every keystroke for a
page number. Now `bookPlan`, `printedMoments`, `bookMap(highlightingLeg:)` and
`bookPage(forDay:)` are memoised. `bookInputsChanged()` drops them all from the
`didSet` of `journal`, `itinerary`, `stamps`, `moments`, `meetingPlaces`,
`features` and `role`,
which is the whole of what `BookPlan.build` reads. **A new input to the book
joins that list or the book goes stale.** A check rebuilds the plan through
`freshBookPlan()` after every kind of edit and compares. Removing the journal's
reset makes it fail; it was tried. `bookPlanBuilds` counts real builds, so a
second check can tell a cache from a recomputation.

**The reader turns the phone, and nothing else can (`OrientationLock`).** A
spread is two square pages side by side, and across a portrait phone its contents
page set at about six points. `BookReaderView`, opened by tapping the preview,
allows landscape while it is open: the app delegate's
`supportedInterfaceOrientationsFor` answers `OrientationLock.mask`, which
overrides the Info.plist's portrait, and the window is asked to turn. The lock
is static and starts portrait, so a reader killed while open leaves nothing
behind. It pages with a `TabView`, not a paging `ScrollView`, which kept its
*offset* across the turn and showed half of one spread and half of the next.
Pinch or double-tap zooms, and paging stops while zoomed. **Close is a permanent
button**, not part of the fading chrome: on a live trip every tap on a night's
spread edits it, so a tap on Close a moment after it faded opened the composer
instead. The chrome comes back on every page turn.

**Pages can be changed from where they are read (`onEdit`).** In the reader on a
live trip, a tap on a night's spread opens its composer, and a tap on a moment —
on a moments page or an opener — opens the moment. The phone turns back to
portrait for the composer and round again when it closes, and the reader finds
its spread again by id. `onEdit` is nil everywhere else, and then no page takes a
tap at all — a gesture attached for nothing would still swallow the preview's
"read it full size" tap — so the PDF and every other screen are as they were.

**The preview's page bar is a timeline of the trip (`BookScrub`), not of the
pages.** Drag it and the x position is a day, on the trip mark's axis; the book
lands on that night, else the next written one, else the last — never on a map
or the title. The bubble says "no page" for a missed night. Checks hold the
mapping monotone and every written night to its own spread.

**Today's spine is the shelf's `SpineView`, scaled whole** — the setup step's
`growingSpine` arrangement — so it is the same book that lands on the shelf. It
keeps the shelf's thickness arithmetic, which means it grows over a week, not
overnight. The reward is the object; there is no count of evenings.

**The postcard saves; it never sends (`Postcard`, `PostcardView`).** It was
drafted as "Send one home" and the app sends nothing — the journal is not a
field on anything that leaves the phone, and a picture of the journal is the
journal. "Save to Photos" is the act; "Share…" is a text link for sending on the
spot, through the export directory and cleared like the book.
- **The offer is derived, never stored.** `postcardOffer(after:)` fires when
  tonight's page makes `nightsWritten` a multiple of seven, on a live
  traveller's trip. No "already offered" flag, nothing on `TripSnapshot`, no
  migration. A missed night written late is catching up, not an occasion.
- **There is one add-only path into Photos, `PhotoLibrary`.** The camera's
  full-frame save moved onto it. It reports `performChanges`' answer, not the
  absence of an error, and a refusal says nothing was saved.
- **`pngData()` writes an `eXIf` chunk.** Read off a real export, it is
  orientation, resolution, colour space and pixel size — no location, date or
  device. The first comment said "no EXIF"; check the file, not the API.
- **The image is `BookSpreadView`**, so the postcard cannot disagree with the
  book, on the cover's cream, pinned to `.large`.

**`BookSection.id` is its page and its title, for exactly the same reason** — and
it was a stored UUID for longer, because `BookPlan` is derived too and nothing
noticed. `BookPreviewView`'s contents list keyed its `ForEach` on it, so the whole
list had new identity every pass: no diffing, no animation, and `isCurrent(_:)`
comparing against a section that no longer existed. **Anything minted inside a
`build`, `plan` or other derived value has this bug by default.** A check now
builds one book twice and asserts the ids match.

**A derived value read from `body` is built once and handed down.** `bookPlan`,
`printReadiness` and `letterMoment` were computed properties read three, five and
two dozen times per pass. `printReadiness` is the one that mattered — it opens
the file header of every photograph in the book, `CGImageSourceCreateWithURL` per
page, on the main thread — so laying out the print screen re-read every photo on
disk five times over.

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

**`adopt(_:)` is the only thing that may delete letters, and it must.** A phone
only holds post addressed to the slot it used to be; declining to *draw* somebody
else's letters still leaves them on disk. Not the observer's path —
`writeTo(_:)` is, since their copy is the archive of what they wrote.

**What it compares against is `lettersBelongTo`, and neither `role` nor
`participant` can stand in.** `role` is the addressee on a traveller's phone and
the *recipient* on the observer's, so `traveller != role` answered "nothing
changed" for an observer adopting the slot they were writing to — the phone
became that traveller still holding every letter they had written, drafts
included, and letters for the *other* traveller if `writeTo` had been flipped.
With no dialog: `TripSetupView` asked its own copy of the same wrong question, so
the confirmation was skipped too. And `participant` is no good either, because
`ArrivalFlow.commitNames()` writes it on every continue, reversibly, so by the
time the irreversible half runs it already reads as the new person. Hence a field
that moves only when the letterbox is re-established. `becomeObserver()` is the
mirror, and it had to exist: the picker set `participant` straight through its
binding, so a traveller's received post became the observer's outgoing set and
`postLetters()` re-posted it as if written here.

**`adoptionDiscardsLetters(becoming:)` is asked of the store**, so the dialog and
the deletion cannot drift apart — which is exactly how they drifted.
`papersLostOnClose` is the same shape, one screen over: `closeTrip()` destroys
something, so what it destroys is counted once and both the panel and the
confirmation read that.

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

**`LetterSchedule.Silence.id` is its span, not a UUID.** `letterSchedule` is
computed, so a fresh UUID per rebuild means nothing can be compared against it.

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
already learned the box is there.

**But the address is routing, not a lock, and the comment used to claim
otherwise.** Both travellers are participants in the same shared zone and both
know `tripID` — it is on the payload — so the record name is fully derivable; and
the zone's *owner* reads every record in their own zone regardless of any share.
So `LetterSeal` seals the drop to a Curve25519 key only the addressed traveller
holds, before it leaves the writing phone, with the trip and the slot bound into
the derivation so a drop cannot be replayed into another trip or read as the
other slot's post. Ephemeral key per seal, so identical post is not identical
bytes. **A drop with no recipient key is refused, not sent in clear** — the
traveller hasn't synced yet, and `lettersAreStuck` already has the vocabulary.

**The `LetterDrop` record needs `parent`, or a participant cannot write it.** It
had none. The observer is always a participant — only the trip may pass
`creatingIfNeeded: true` — and a participant may only save records hanging off
the shared root, so `post` would have failed on the first real run. The parent is
the trip record, the same anchor `CloudKitZone` uses.

**The body rides in `encryptedValues`, and that could only be decided now.**
CloudKit will not let a field change between encrypted and not once the schema
exists. Nothing here has ever run, so it was free exactly once.

**The loopback does not seal, and that is correct.** It writes a file in this
app's own container on this one phone; sealing it would encrypt against a key
held by the same process. The seal exists because a *shared zone* is readable by
people who are not the recipient.

**With CloudKit off, the letterbox is closed.** `chooseLetterTransport(cloudAvailable: false)`
used to return the loopback, which wrote every sealed letter in clear into the
container root. It returns `ClosedLetterDropTransport` now, which passes
`TransportConformance.inert`: unavailable, a reason, `post` throws `.unavailable`,
`collect` returns nil. `postLetters` skips a transport that isn't available, so
`letterPostProblem` is the plain reason rather than a refusal dressed as a
failure. The Home vocabulary didn't change, because `lettersAreStuck` already
read `unavailableReason`.

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

- `TripSnapshot` decodes field by field with defaults, so a trip written by an
  earlier version still opens. The alternative is a phone that loses two months
  of pages because a flag was added.

**Finishing a trip is one sheet with two answers, and a closed trip leaves the
tabs.** `FinishTripView` offers "Put it on the shelf" (`closeTrip()`) and
"Throw it away" (`beginNextTrip(discarding: true)`). It is reached from the
shelf, from settings, from `TripEndingView`, from Today once `isOverButOpen`,
and from the observer's `HomeView`, which had no way out of a trip at all. It
used to be two unrelated screens. "Close this trip" said "Deletes nothing" over
a close that deletes scans. "Empty this trip" shelved nothing and never
mentioned the shelf. After a close, the closed trip stayed in `MainTabs` drawn
as live, and the shelf showed it twice. Now `RootView` shows `ShelfView` in
place of the tabs whenever `hasOpened && !isLive`: the phone is **between
trips**, and the only action is "Start the next trip". The confirmed action
runs in the sheet's `onDisappear`, because both answers remove the view that
presented it.

**The shelved trip lands on the shelf, once.** `closeTrip()` sets
`justShelved` last, and `ShelfView` takes it on appear with `takeJustShelved()`.
The spine then drops into its slot, a soft haptic fires, VoiceOver gets an
announcement, and "Put away today" fades in with `TripSummary.shelvedLine`.
- **It is an event, not state.** It is not persisted and not on `TripSnapshot`,
  the way `pendingInvitation` isn't, because a landing that survived a relaunch
  would replay a moment that already happened.
- **Only `closeTrip()` sets it, and `joinTrip` clears it.** Joining shows no
  shelf, and a leftover signal would land the wrong book the next time the
  shelf did appear.
- **`take` checks before it clears**, the `InvitationInbox` rule.
- **The landing modifiers sit outside `spine(_:isLive:)`.** Its frame, rotation
  and clip order is the fix for long names, and an offset is a render
  transform, so the slot keeps its space and the neighbouring spines never
  move. The row is `.clipped()`, so the spine enters from the top of the shelf
  and doesn't fall across the panel above.
- **"A year ago today" drops below the line while landing.** Above it, at an
  accessibility size, the whole moment happened under the fold. The panel
  checks the store's pending signal too, so it is already in place on the
  first frame.

**`TripSummary.kilometres` and `.moments` are optional, and must stay so.**
They are the first fields added since shelves were written, and `TripSummary`
decodes synthetically. A missing non-optional key throws, and it takes every
finished trip with it. `shelvedLine` drops a clause that is nil or zero, and
counts **distinct** countries: `countries` has one entry per leg.

**`beginNextTrip` refuses a live trip unless it is discarding.** Closing is its
own confirmed act, and making the next trip must never imply it. It carries the
names, who holds the phone, currency, budget, length, switches and the
show-this cards. The cards get **fresh ids**: the new trip has a new `tripID`,
and a reused id is a card resurrecting against a tombstone on the other phone.
`tripName` is blanked so onboarding asks. Nothing re-pairs the phones: the new
`tripID` means the invite step appears again when `canInvite`.

**A spine's label is sized before it is rotated, and clipped after.**
`rotationEffect` is a render-time transform and does not change layout size, so
the old `.fixedSize()` *after* the rotation read the label's **unrotated** ideal
width — the whole string, one line, full point size, uncompressible — and
nothing clipped it. A three-day trip with a long name painted over its
neighbours, through the baseline rule and up into the masthead. The
`.frame(width: spineHeight - 16)` *before* the rotation is what gives
`minimumScaleFactor` and the ellipsis a box to work in. The name fits the book
and never the other way round: height is trip length and thickness is page
count, and the caption under that row says so out loud. The font is
`.capped(at: 1.3)` for the reason `Mono.growthCap` exists — uncapped, a 13pt
spine reaches 31pt at AX5 and its *line height* then exceeds the 26pt width of a
thin book, so it bleeds sideways as well as endways against a `spineHeight` that
is a plain constant. Nothing is lost to a reader who needs the size: the
accessibility label reads the whole name and year however small it draws.

**A planned trip is a keyless store and a file of its own, and it never
syncs.** `makePlan()` / `openPlan()` hand `PlanTripView` a
`TripStore(storeKey: nil)`, the shelf reader's arrangement, which shares the
live store's `library`. Keyless is the point. `persists` is false, so the
prunes, the widget and every save are no-ops. A second store *with* a key
would prune the scans against its own document ids (none) and delete the live
trip's passport. A check writes a real scan and proves it survives.
- **It is built from `init`'s blank branch, not a copy of the live trip.**
  Nothing private can ride in because somebody forgot to clear it. What is
  copied is named in `makePlan`: the names and role, the money, the switches
  and the length. It starts the day after this trip ends.
- **`TripLibrary.plan` is the shelf's own shape in its own file**
  (`planKey`, in `Storage.appKeys`). The shelf's `[ShelvedTrip]` format is
  untouched, and `erase()` takes the plan with it.
- **`savePlan()` skips a write that changes nothing, and that is
  load-bearing.** The plan store forwards its library's changes as its own,
  and the sheet saves on every change it sees. An unconditional write
  announces a change that asks for another write, every turn of the run loop.
  The encoding uses sorted keys, so the byte comparison means something.
- **An untouched plan is forgotten on dismiss.** A dashed spine reading
  "this trip" would be a book nobody sketched.
- **`beginNextTrip(usingPlan:)` adopts the plan's name, dates, money,
  itinerary and unearned stamps.** It keeps the new `tripID` and leaves
  `origin` at `.blank`, so onboarding still walks where-next, dates and
  itinerary with the plan filled in. "Start something else instead" passes
  `false` and keeps the plan. Throwing the live trip away uses the plan,
  because the plan is what was next. `FinishTripView` names it, and the
  checklist header lost "from last time", because those rows may now hold the
  plan's money.
- **The observer can't plan.** `makePlan` refuses them, and the shelf draws no
  plan row for them.

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

**`CountryFacts.language` is a label, not a translation.** It names the show-card
editor's first field. Belgium, Switzerland, Canada, India and South Africa answer
`nil`: "Hindi" in Chennai is the same mistake as Thai numbers under "Vietnam".

**Three call tiles don't fit at an accessibility size.** Vietnam's police ·
medical · fire rendered as "POLIC / E" and "MEDIC / AL" — "SONGKRA / N" again, on
the screen where a misread number matters most. `CallTileRow` stacks above the
threshold and both grounds draw through it, so neither can regress alone.

### 8.6 The papers (`Model/ScanVault.swift`, `Features/Papers/`)

Everything under the vault had been built and hardened for two phases — the
crypto, the three-state page read, the short-batch reporting, the lock, the
backup exclusion. What was missing was the top half. `TripStore.documents` was
`private(set)` with no mutator anywhere, so in a shipped build it was permanently
empty and the Papers screen said so out loud: *"what's missing is a way to add a
document of your own, which this build doesn't have yet."*

The whole risk in adding it was that the top half would quietly undo the bottom
half, and most of §3.6 and §5.2 is the record of keeping that from happening. Three
things are worth pulling out here.

**Scope was a decision, not a default.** Documents go *onto* the phone and
nowhere else — no sending to the other traveller, no encrypted cloud backup. Both
were considered and both would have reversed a promise the app makes in three
places, including a fake "Send to <them>" button that was deleted in Phase 2 for
saying exactly that. The feature is the missing local half and nothing more.

**Adding a way to create documents made a dormant leak live.** Nothing pruned
`.scan` files and `deleteAll(for:)` had no callers, so every page ever written
would have survived a reset forever. That was invisible while no document could
exist and would have shipped the moment one could. The fix is in §3.6; the
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

### 8.7 The mark and the icons (`Shared/TripMark.swift`, `Tools/RenderIcons.swift`)

**The mark is arithmetic plus two thin rasterisers.** Its third caller is a macOS
command-line rasteriser, so `Shared/TripMark.swift` holds the cut table,
pixel→cut mapping, dot position and progress maths with **no
`import CoreGraphics`** — `Double` throughout, so `run-checks.sh` keeps proving it
is arithmetic. `Palette` reads its six mark rungs from `TripMarkInk`.

**The mark's overhang belongs to the cut, not the caller.** In a tile the rule
bleeds off both sides and half the dot leaving is the design's one deliberate
asymmetry; in the lockup the rule is *inset*, so the same half-dot is cut by the
canvas and reads as an arrowhead welded to a bar. `TripMarkCut.bleeds` decides it —
first built as an app-versus-widget switch, the wrong axis. And **clamping the dot
inside must not clamp the rule with it**: doing both painted a green stub at the
left edge before departure, claiming a day had been walked before the trip started.

**`actool` drops per-size icon children carrying an `appearances` key.** It says
"16 unassigned children", which reads like a stray-file notice, and exits 0. So the
default appearance carries the three optical cuts as a legacy per-size list, and
dark and tinted are one 1024 each taking the *middle* cut.

**The 20pt icon slots are a second axis from size.** The notification badge is
"flat white on grey", so the decision is `(pixels → cut, role → ground)`. Keyed on
pixels alone it ships a green notification icon, and nothing but a real banner
shows it.

### 8.8 The widget (`DiThoiWidget/`, `Shared/WidgetSnapshot.swift`)

**The widget gets one purpose-built value, not the trip.** `dithoi.trip.v3` in the
App Group would put the journal and letters in a container the extension is
entitled to. So `Storage.defaults` stays `.standard` and the group holds one key,
`dithoi.widget.v1` → `[WidgetSnapshot]`. Three checks: no private-looking field
name, **every field a scalar** (nothing holding a collection can carry a journal,
whatever it's later called), and that one key alone. It also means **no
migration**, so `TripStore.init` can never take its seeding branch there.

**`WidgetCenter` reloads are budgeted, so `publishWidget` compares first.** An
evening of journalling would spend the day's budget, after which the widget stops
updating at midnight and nothing says so. The other guard is `persists`: without
it, the shelf opening a finished trip would repaint the Home Screen with it.

**Timeline days are added with `Calendar.trip`, never `+ 86_400`.** A DST boundary
would shift every later entry an hour and the day would tick over at 23:00 for the
rest of the trip.

**`DayWidgetView` is in both targets so `-screen widget` can photograph it.** The
two likeliest failures are invisible to the compiler: the Lock Screen renders
*vibrant*, flattening a green rule and a grey one into one bar, and the mark can
vanish at an accessibility size.

**The design's widget says "11 days until Seoul" on day 38; the answer is 9.** Same
class as the "61 days" the prototype printed across a 72-day range: compute it.
The check's label carries the design's 11 so the discrepancy shows in the output.

---

## 9. Where to change what

| You want to… | Go to |
|---|---|
| Change a colour, space or radius | `Shared/Theme.swift` — the mark's six live in `TripMarkInk` |
| Swap in the real Cormorant/Lora/Plex fonts | `TypeSpec.design`, `Shared/Theme.swift` |
| Adjust how type scales for accessibility | `TypeSpec.growthCeiling` |
| Add a currency | a case in `Currency`, a `faces` row, and a `RateSnapshot.builtIn` rate; the checks refuse a case missing either |
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
| Add an onboarding step | A case in `SetupStep` (`Model/SetupSteps.swift`), in order, and its line in `isIncluded` — the first trip and every next one get it |
| Change what carries to the next trip | `TripStore.beginNextTrip` — and the carried-over line on `FinishTripView`, which says it out loud |
| Add a way to finish a trip | Present `FinishTripView`; never call `closeTrip()` or `beginNextTrip` from a new control |
| Turn a feature off for a trip | `TripFeatures`, then the `tabs` filter in `MainTabs` |

---

## 10. Build and environment

How the project is put together on disk, and what the machine it was built on
needed. The model layer's import rule is §6.1.

**`Shared/` is explicit file references, not a synchronised folder** — a
`PBXFileSystemSynchronizedRootGroup` can't cleanly donate files to a second target.
A new file there is *not* picked up automatically; `run-checks.sh` globs
`Shared/*.swift` so it is at least compiled on the way to somebody noticing.

**The widget extension needs a physical `Info.plist`.** `INFOPLIST_KEY_*` produces
top-level scalars only and `NSExtension → NSExtensionPointIdentifier` is nested.
Both `.entitlements` live at the repo root so the synchronised folder can't claim
them as resources.

**App Groups work on the simulator with no `DEVELOPMENT_TEAM`, via the *simulated*
entitlements.** `codesign -d --entitlements` shows an empty dict, which looks like
failure and isn't. The proof is `simctl get_app_container …` returning a path.

### Environment notes

- Xcode 16.2, iOS 18.3 simulator runtime.
- **There is a signing identity now, and it is a *free* personal team** —
  `DEVELOPMENT_TEAM = 6U6Y487HT5`, cert OU matching, device builds working. It
  is still why CloudKit is inert, for a reason no code change reaches: a
  personal team cannot hold the iCloud capability. `xcodebuild
  -allowProvisioningUpdates` refuses it in as many words — "Personal
  development teams, including "Khang Bui", do not support the iCloud
  capability." **CloudKit needs the paid Apple Developer Program.** The tell,
  without building anything, is the profile's expiry: free profiles last 7
  days, paid ones a year.
- To turn CloudKit on, once the membership is paid: the iCloud capability with
  container `iCloud.com.lovedones.dithoi` in `DiThoi.entitlements`, then
  `DiThoiCloudKitEnabled` to `<true/>` in `DiThoi-Info.plist`. No code changes,
  and those switch the **letters** on as well as the trip. **It is not
  `INFOPLIST_KEY_DiThoiCloudKitEnabled`**, which is what three files used to
  say: that mechanism only injects keys Xcode already knows, so the custom one
  never reached the built Info.plist and the flag `isEnabled` reads could not
  exist. Every known key beside it landed, and the build reported success —
  `actool`'s sixteen dropped renditions, one build phase over. Check the
  built app, not the setting:
  `plutil -extract DiThoiCloudKitEnabled raw …/DiThoi.app/Info.plist`.
- The App Group runs anyway, through the simulated entitlements — check
  `simctl get_app_container … group.com.lovedones.dithoi`, not the signature.
  So does iCloud on the simulator: with the flag on, the app resolves
  `iCloud.com.lovedones.dithoi`, TCC approves it, and `CloudKitZone.locate`
  runs its real order — private database first, then enumerating shared zones —
  before both fail `NoAccountExists` and the screen says "Sign in to iCloud on
  this phone…". That is the error translation verified end to end, and it is
  the **only** part of CloudKit that has ever executed. No record has been
  written, no zone created, no `CKShare` made, no letter sealed over the wire.
- The group's plist is written lazily, so read it after `simctl terminate`, not
  right after launch, or the key looks missing and the widget looks broken:
  ```bash
  G=$(xcrun simctl get_app_container <dev> com.lovedones.dithoi group.com.lovedones.dithoi)
  python3 -c "import json,plistlib,sys;d=plistlib.load(open(sys.argv[1]+'/Library/Preferences/group.com.lovedones.dithoi.plist','rb'));print(json.dumps(json.loads(d['dithoi.widget.v1'])[:2],indent=2,ensure_ascii=False))" "$G"
  ```
- **The persisted trip is ground truth when the screen is ambiguous** — and it is
  a file now, not a preferences key, so it is plain JSON:
  ```bash
  C=$(xcrun simctl get_app_container <dev> com.lovedones.dithoi data)
  python3 -c "import json,sys;print(json.load(open(sys.argv[1]+'/Library/Application Support/DiThoi/Store/dithoi.trip.v3'))['dayPlans'][0])" "$C"
  ```
  The preferences plist should hold only `dithoi.rates.v1` and
  `dithoi.sync.lastSyncedAt`; anything else there is a regression. Reading it
  right after a launch can still show a stale `dithoi.trip.v3` — `cfprefsd`
  writes lazily, so the migration's removal lands late. Read after
  `simctl terminate`, the same caveat the group plist has.
- Screenshots need location granted and set, or Separated has nothing to say:
  `xcrun simctl privacy <dev> grant location-always com.lovedones.dithoi` then
  `xcrun simctl location <dev> set 18.7920,98.9880`.
- The `.xcodeproj` is hand-written, `objectVersion = 77`, with two
  `PBXFileSystemSynchronizedRootGroup`s — new files in `DiThoi/` and
  `DiThoiWidget/` are picked up automatically, **`Shared/` are not**. Object ids
  are hand-allocated; `D1000001000000000000A036` is next.
- **The MCP simulator integration works**, so screens can be *driven*, not just
  photographed. If it regresses to "Xcode is installed but not selected", the fix
  needs the user's password (`sudo xcode-select -s …`) — say so rather than falling
  back to `xcrun simctl` silently.
- **Simulator input is in device points** (402×874 on an iPhone 16 Pro), not
  screenshot pixels. A swipe at x=450 silently does nothing.
- **Anything on a timer can't be hand-driven.** The ledger's ten-second undo window
  expires between a screenshot and the next tap; fire dependent taps back to back
  with no screenshot between, then check the result.
- Two `xcodebuild` runs against the same DerivedData fail with `database is locked`.

---

## 11. Key learnings

The general lessons, each of which more than one section above is an instance of.

**When a design's numbers disagree, that's a spec bug — compute.** The prototype
said "61 days" on six screens, spanned 72, and summed to 71 nights. **And derived
copy has to handle its own degenerate cases:** the forecast advised cooking twice a
week once the projection ran the budget dry, and the book's headline read "One
days in" on the first day of every trip — a *spelled-out* number leaves nothing
in the sentence to make the noun agree with it, so both screens that spell one
out had simply written the plural in. `Formatting.spelledCount` is where that
agreement lives now, along with the numeral fallback past a hundred that
`ItineraryView` had and `BookView` did not: one sentence written twice,
disagreeing in two different places.

The countdown's aside was the third of these and had all three faults at once.
Written as one interpolation it read **"61 days, 0 countries, €0 between you.
It's all already on the phone."** on every trip typed from scratch — which is
every trip, since `init` always seeds a blank one: two counts of nothing stated
as though nought were an answer, a plural nothing forced to agree so a
one-country trip said "1 countries", and a promise about a phone with nothing on
it. `TripStore.packedSummary` assembles it clause by clause now, each one
dropping when it has no content, and the promise holds only while something has
been named. It is **on the store rather than in the view** because `Features/`
isn't compiled by `run-checks.sh` — a sentence with a branch in it wants a
check, the way `whatTravels` and `papersLostOnClose` do. The counts go through
`spelledCount` at `spellingUpTo: 0`, the numeral branch, which still pluralises:
this is a 13pt aside under a numeral headline, not the 38pt one the spelling is
for.

**Dead controls are worse than missing ones.** The "Custom" split had no way to set
it and silently recorded zero debt. The passport screen's "Send to <them>" was the
same shape with a safety cost: it told somebody a copy of their passport was on
the other phone, and the moment they'd find out otherwise is the moment the
feature existed for. Implementing it was never the fix — the same screen promises
the scans never leave.

**The first question was the one the flow never asked.** Onboarding hid the
traveller/observer choice in settings, so a fresh install could only be a
traveller. Asking identity first cost one screen and made home mode reachable.

**The two features that were about restraint were both load-bearing.** Sealed
letters expose only their condition and never record when they're read; the other
side hides the letters *and every reference to them*. Exactly what an
implementation quietly drops.

**A promise the compiler keeps beats one a reviewer has to notice.** The journal
stayed off `SyncPayload` and the read receipt off `SealedLetter` by not being
fields; `WidgetSnapshot` goes further, asserting every field is a *scalar*. Look
for the shape that makes breaking the promise not compile — failing that, one that
fails a check nobody has to remember.

**Where a design asks for a permission the app promised not to hold, the promise
wins.** H2 picks the night's photo "from 84 today", meaning the whole camera roll;
`PHPickerViewController` needs none. The only place Phase 2 departed from the
design, documented in three files because a silent departure is the thing to avoid.

**"No error" is not "it worked".** `actool` dropped sixteen of twenty-five icon
renditions with exit code 0; `modifyRecords` returns non-nil over a failed save.
The API's success is not the outcome's. **And "no answer" is not "nothing there":**
`SecItemCopyMatching` returning non-success meant "no key yet", so the next line
deleted the real one — the difference between `errSecItemNotFound` and every other
status was the whole of somebody's passport scans.

**A guarantee that lives in a view isn't one, and a guarantee keyed off the wrong
field isn't either.** `adopt(_:)` compared against `role`, which means two
different things depending on who is holding the phone, and the call site asked
its own copy of the same wrong question — so the guard and the confirmation failed
together, in the same direction, for the same reason. Ask the store.
