# CLAUDE.md

The rules, one line each, for whoever edits this code. Every rule is the residue
of a real bug. The bug, and the reasoning, are in
[docs/architecture.md](docs/architecture.md) at the § given. **Read the section
before changing anything it covers**, and when a rule changes, change it in both
places.

## What this is

A native SwiftUI iPhone app built from `Đi Thôi - Classical Prototype.dc.html`
and `Đi Thôi - Phase 2.dc.html`: a travel companion for two people on a long
trip, with sealed letters from someone at home that open when they arrive
somewhere. **It ships with no trip inside it**: onboarding asks who is holding
the phone (either traveller, or the observer at home), then the dates, budget,
currency and itinerary, and everything else is computed. Phase 2 (the nightly
page, the book, home mode, many trips) and pairing are built. CloudKit is
written and has never run, because it needs a **paid** Apple Developer
membership.

- [docs/README.md](docs/README.md): running it, the screen map, decisions
- [docs/architecture.md](docs/architecture.md): how it's built, and every trap in full
- [docs/expansion.md](docs/expansion.md): what to build next
- [docs/CHANGELOG.md](docs/CHANGELOG.md): what's built, and the known issues
- [docs/archive/](docs/archive): historical

## Layout

```
DiThoi/Model/      TripStore, Models, SampleTrip (commented out), TripShape,
                   TrailReplay, Syncing, SyncTransports, SyncCoordinator,
                   TransportConformance, Rates, CountryFacts, LocationService,
                   PhotoStore, PhotoCrop, DocumentStore, ScanVault,
                   DocumentCrypto, Storage, WidgetBridge, Book, SetupSteps,
                   Ritual, LetterDelivery, TripLibrary, DayFacts, LinePrompts,
                   BookScrub, Postcard
DiThoi/Design/     Components, AppLock, ReadOnly
DiThoi/Features/   41 screens grouped by tab, incl. Arrival/, Home/ and Trips/
DiThoi/Root/       RootView, MainTabs, HomeTabs, ClassicalTabBar, DebugScreens,
                   AppShortcuts
Shared/            both targets: Theme, TripMark, TripMarkView, WidgetSnapshot,
                   DayWidgetView, QuickAction, MarkMomentIntent
DiThoiWidget/      WidgetBundle, DayWidget (timeline), MarkMomentControl (iOS 18)
docs/              README, architecture, expansion, CHANGELOG; archive/
Tools/             run-checks.sh, CheckTrip.swift, VerifyTrip.swift,
                   render-icons.sh, RenderIcons
Screenshots/       107 files: every screen, 3 text sizes
```

About 33k lines of Swift, no third-party dependencies. Not every model rule is in a
check: `Features/` and `Root/` aren't compiled by the checks.

## Before you change anything

```bash
./Tools/run-checks.sh          # 1,505 model assertions, macOS, no simulator
./Tools/render-icons.sh        # regenerates the icon set and re-tests actool
```

- Run the checks after touching `Model/` or `Shared/`. They also run two stores
  against one loopback box, which is how sync is verified with no account. (§6.1)
- Reach any screen with `xcrun simctl launch <device> com.lovedones.dithoi
  -resetTrip -screen <route>`. There are 71 routes, plus `-day N` (zero or
  negative allowed), `-seedItinerary`, `-seedJournal`, `-seedSpending` and
  `-planned`. The empty states are half of what there is to look at, which is
  why seeding is a flag, not a route. (§6.2)
- **Take the screenshots.** Eleven rounds of fully green checks have sat over a
  screen that was wrong. (§6.3)

## Rules

The general lessons behind them are §11; the debt kept on purpose is §7.

### Privacy, made structural
- The trip is a protected file in `Store/`, never a `UserDefaults` key.
  `Storage.forget(_:)` clears both addresses. (§3.2)
- A protected write can fail (the phone is locked). `TripWriter.write` returns
  whether it landed, and the next foreground retries. (§3.2)
- The migration writes, reads back, and only then removes. Never remove on
  faith. (§3.2)
- Journals, letters, moments and documents are not fields on `SyncPayload`.
  Don't tidy them in. A reflection check pins the field list. (§3.5)
- `letterKeys` on the payload holds public keys only. The private half is in the
  Keychain, in neither the payload nor the snapshot. (§3.5)
- The exported book is the whole journal in one file. It goes to
  `Storage.exportDirectory` and is cleared before each build, on share
  completion and on background. PDF metadata carries the title, never a name.
  (§3.6)
- `Moment`, `TravelDocument` and `SealedLetter` must never gain `updatedAt`,
  `deletedAt` or a read-shaped field. Their absence is the guarantee, and
  checks reflect over each type. (§3.5, §8.3)
- A moment's photograph is walked by `referencedPhotoIDs` in both the live trip
  and every shelved snapshot. (§3.6)
- The widget gets one scalar-only key, `dithoi.widget.v1`, and never the trip.
  `Storage.defaults` stays `.standard`. (§8.8)
- The imported PDF is opened in place and never copied. (§3.6)

### Files, scans and photos
- `ScanVault.prune` keeps the live trip alone; `PhotoStore.prune` walks the shelf
  too. Read both before "fixing" either. Both guard on `persists`. (§3.6)
- `ScanVault.nextIndex` is one past the highest, not the count. Pages sort on
  the parsed index, not the filename. (§3.6)
- Picker results go into slots, never appended as they load. (§3.6)
- A Keychain read never mints a key, and a write never deletes one first.
  `errSecItemNotFound` is the only "no key yet". (§3.6)
- A failed decrypt is an answer (missing / decrypted / unreadable), not a
  spinner. (§3.6)
- Photos are backed up (set `false` actively); scans are encrypted and are not.
  (§3.6)
- `resetTrip()` and `beginNextTrip(discarding:)` prune; they never delete photos
  directly. (§3.2)
- Closing a trip is the one act that deletes while keeping the trip. Scans go
  and values are cleared before the snapshot is frozen. Labels survive. (§3.6)

### Persistence
- `storeKey: nil` means never touch disk. That is how the shelf, plans and
  readers open a trip. Never pour a snapshot into the live store. (§3.2)
- Writes are coalesced. `flush()` dispatches and returns; anything that reads
  its own write uses `flushAndWait()`. A second store needs an explicit
  `snapshot:`. (§3.2)
- "Nothing saved" and "saved but unreadable" are different. `storageFault`
  makes `save()` refuse. (§3.2)
- Every `TripSnapshot` field is `decodeIfPresent` with a default, and a check
  strips each key. Adding one without a default loses somebody's trip. (§3.2)
- `Storage` is the one seam. `Storage.shared` returns `nil`, never a fallback.
  Every persisted key is named once, in `Storage.appKeys`. (§3.2)
- `-resetTrip` clears the letters file and the shelf too. (§3.2)
- Nothing sits in the container root. The loopback boxes live in `Loopback/`,
  protected and out of backups, and every launch sweeps strays an older build
  left (`Storage.sweepStrayLoopbackFiles`). (§3.2)
- Persisted enums keep their raw values (`Participant.writer`, `Traveller.one`
  and `.two`). An unknown raw value throws and wipes the trip. (§5.3)

### Roles
- The observer cannot drop a pin, keep a moment or set a meeting point. The
  guard is in the store; `\.isReadOnly` on their trail tab is the courtesy.
  (§5.3)
- Names are data in `TripNames`. `Traveller` has no `name`. Read through
  `name(for:)`, `myName`, `otherName`, `label(for:)`; `name(of:)` is the
  `Participant` overload. (§5.3)
- Names merge per slot and never ride in `TripSettings`. An unrenamed slot
  carries `.distantPast`. (§5.3)
- The observer sets no trip parameters. (§5.3)
- `role` is the letter box's address on both sides; never sync a
  `letterRecipient`. `lettersVisible` asks what is on the phone, not who holds
  it. (§8.3)
- `adopt(_:)` and `becomeObserver()` delete letters, and compare against
  `lettersBelongTo`, never `role` or `participant`. Dialogs ask
  `adoptionDiscardsLetters(becoming:)`. (§8.3)
- `isReadOnly` is not "closed". Gate edits on `!isReadOnly && store.isLive`.
  (§5.2)

### Onboarding
- `TripOrigin` is stored, never inferred. `TripStore.init` always seeds a blank
  trip. (§5.4, §3.13)
- The setup steps are a registry in `Model/SetupSteps.swift`. A context change
  may only add or remove steps after the one on screen. (§5.4)
- The trip's name is asked in every mode. Readers go through `displayName`;
  only the PDF metadata keeps the raw title. (§5.4)
- Setup fields commit on focus loss and on `onDisappear`. (§5.4)
- A returning traveller is asked "where next" first. Country and first stop
  are both or neither. The currency chip is a guess, never applied silently.
  "Coming along" applies from a snapshot. (§5.4)
- A suggested name is a button beside the field, never a placeholder. Grey
  text reads as an answer. (§5.4)
- There is one setup flow, `ArrivalFlow`, for the first trip and every next one.
  (§5.4)
- The invite step runs after `commitSlot()`, only when
  `!isObserver && sync.canInvite`. `hasOpened` stays false until it's done.
  (§5.4)
- Commits split by reversibility: `commitNames()` on every continue, and
  `commitSlot()` once, behind a confirmation. (§5.4)

### The trip's shape
- The itinerary is day offsets; dates come from `date(forDay:)`. (§3.1)
- `setStart(_:)` shifts every dated record through `TripShift`. A new dated
  collection joins both. Never re-stamp a shift: `SyncMerge` moves the losing
  payload's dates into the winning start's frame, and `apply` moves this
  phone's own. (§3.2)
- Itinerary edits are a mutation plus `reflow()`. Order and nights are the
  authority. (§3.1)
- `city(forDay:)` and `todaySegment` fall through to the last stop on the way
  home; `currentSegment` deliberately doesn't. (§3.8)
- A stop's title splits only through `Segment.places` and
  `Segment.places(in:)`. (§3.8)
- `addSegment` and `addLeg` return the stop they made, read after reflow. Both
  sheets offer the stamp through `StampSection`, and a refused code disables
  "Add it". (§3.8)
- A country can be entered twice. Use `countries`, `legs(inCountry:)` and
  `daysSpent(inCountry:)`, never `legs` as a country list. (§3.8)
- A model mutation is validated whole, then applied whole. (§3.1)

### Waypoints
- A waypoint joins its stop through `segment(for:)` only: `segmentID` first,
  name second. `backfillWaypointJoins()` attaches only unique matches. (§3.9)
- `waypoints(forSegment:)` is plural, and the editor offers another stamp
  whenever `appendCost()` allows. Never use `.first`. (§3.9)
- `index` is derived by `reflowWaypoints()`, which re-stamps `updatedAt`.
  Renumbering is an edit. (§3.9)
- Waypoints stay a tombstoned collection, never nested in `Segment`. (§3.9)
- An earned waypoint is immutable. Removing one a letter names is confirmed,
  with the letter named. Removing the last unearned one is refused. (§3.9)
- A removed code doesn't come free while a sealed letter names it; cities have
  no such rule. (§3.9)
- A city visited twice is offered `BKK2`, seeded off the first stamp's code,
  and only from two letters up. (§3.9)
- The stamp's city is a choice among the stop's places. The drift escape hatch
  is for editing only. (§3.9)
- `kilometresTravelled` skips positionless waypoints. `arrive(at:)` fills a
  position only if something asked for one. (§3.9)

### Moments and the trail
- `Moment` has no `author`, and none is needed. (§3.10)
- A moment before departure is filed before departure: `trueDayNumber`, an
  empty city, and `caption`/`place` for every reader. (§3.10)
- "Mark a moment" is at the top of the trail. Outside the app it's App
  Intents, never the icon's quick-action menu. `RootView` reads the inbox and
  drops what it can't act on. (§3.10, §5)
- Deleting a moment leaves the photo to the prune, which is what makes undo
  work. `MomentUndo` withdraws on background. (§3.10)
- The inline map is a door (`allowsHitTesting(false)`); `TrailMapView` is the
  map. Its cards never mention letters. (§3.10)
- "You are here" never asks for permission: `requestOnceIfAllowed`, a fix under
  15 minutes old, live traveller trips only. (§3.7)
- Arrival is suggested, never awarded. The nudge goes to Trail's own
  confirmation. (§3.10)
- "Keep a moment here" presents from the cover's `onDismiss`. (§3.10)
- An unfinished moment is derived, never stored. (§3.10)
- `photoIntake` clears `isPresented` on sight. (§3.10)
- The replay's last frame is the headline by construction, and the trail has
  one picture, `TrailPicture`. (§3.10)
- Tonight's page borrows a moment's photo as a copy (`PhotoStore.duplicate`).
  Borrowing never focuses the line. (§3.10)
- "A year ago today" is memoised per day and opens the book at its page.
  (§3.10)
- Moments are hollow diamonds, excluded from map framing. (§3.10)

### Today and the screens
- Every panel that looks tappable is tappable and says so in words. A tappable
  `Panel` is pixel-identical to a dead one. (§5.1)
- `RateStamp` is a `Button`; never nest it inside another. (§5.1)
- Push through one `navigationDestination(item:)`, never two stacked
  `isPresented:`. (§5.1)
- Empty states compute their own promises. Separators belong to the clause,
  not the line ("12 Jan · "). (§5.1, §3.11)
- Every editable sheet keeps its work. New work uses `guardsUnsavedWork`; an
  edit to something that exists commits on `onDisappear`; a letter saves as a
  draft, and an empty one goes. (§5.1)
- A composer holds what it writes to disk (`PhotoStore.hold`) until it knows
  what was kept, or the foreground prune takes it. (§5.1)

### The meeting point
- Ask `MeetingPoint.isSet`. A blank trip's meeting point exists and is not an
  answer. (§3.11)
- A `??` behind a split never fires. (§3.11)
- There is one tonight's point and a `meetingPlaces` history, both synced. The
  merge unions the history and LWWs the point. (§3.11)
- `MeetingPoint` has no id; `placeKey` is the identity. (§3.11)
- The local script belongs to the place, not to the screen. (§3.11)
- Known issue: nothing sets a meeting point's position. (§3.7)

### Day plans and show-this cards
- Both are editable and therefore on `SyncPayload`. (§3.12)
- Read `orderedShowCards`, never `showCards`. `plan(forDay:)` reads
  `dayPlans.live`. (§3.12)
- A day plan's `city` is what it was written about; screens prefer the segment.
  (§3.12)
- Editors keyed on a value load with `.task(id:)`. Placeholders are never real
  content. (§3.12)
- The Papers row shows the cards; `edit` manages them. (§3.12)
- Hold to edit or delete. Cards delete with undo; documents delete behind a
  confirmation. (§3.12)
- A `Section` footer draws a white band. Use a row with
  `listRowBackground`. (§3.12)
- A small control above a large one gets padding before `.contentShape`.
  (§3.12)

### The country card
- An unknown country draws nothing. Never print one country's numbers under
  another's name. (§8.5)
- Only what stays true lives in `CountryFacts`. Taxi fares and consulates were
  refused. (§8.5)
- `phrases` is `nil` wherever `language` is, and phrases hang off the country.
  `language` is a label, not a translation. (§8.5)
- Call tiles go through `CallTileRow`, which stacks at accessibility sizes.
  (§8.5)

### Money
- "Spent today" counts every expense in local money. It puts "≈" in front only
  when it converted, and uses `lineLimit(1)` with a scale factor. (§3.4)
- Records are stamped with `countryNow`, never `currentCountry`.
  `country(of:)` resolves unstamped lines; stamped ones are never re-resolved.
  (§3.4)
- Deleting writes `deletedAt`. Draw from `expenses.live`. (§3.4)
- Settlement is a `.transfer` that borrows the proposal's id. It is
  propose-then-confirm, and `debtor` is stored. (§3.4, §3.5)
- `Expense.isEditable` refuses fractional transfers. (§3.4)
- No rate is baked into logic. Every converted figure gets a `RateStamp`.
  (§3.3)
- A fetched rate must sit within ×4 of `RateSnapshot.builtIn`, or of the last
  rate for a `drifting` currency. A bad minor currency holds its last rate; a
  bad major refuses the table. The jsDelivr endpoint can't be pinned. (§3.3)
- `Currency` is a curated enum: a new case needs a `faces` row and a built-in
  rate, and no case has three decimals. No symbol but USD's is a bare "$".
  (§3.1, §3.3)
- Numbers go through `Formatting.decimal`; formatters live in `FormatterBox`.
  (§3.3)

### Sync, pairing and the letter channel
- Only the live trip syncs, and `SyncMerge` refuses another `tripID`. (§8.4)
- The CloudKit flag is `CloudKitZone.isEnabled`, read from the physical
  `DiThoi-Info.plist`, never `INFOPLIST_KEY_`. It asserts the entitlement;
  it can't check it. (§3.5)
- Two phones meet only if one joined the other. `joinTrip` is the only thing
  that moves a `tripID`, and `tripRecordID` stays reversible. (§3.5)
- The invitation carries the slot on the `CKShare`. If it doesn't, the app asks
  and never guesses. (§3.5)
- Joining is split by reversibility: `details`, then `accept`, then `joinTrip`.
  (§3.5)
- The sharing screen's list is derived (`whatTravels`) and pinned to the
  payload. (§3.5)
- Share acceptance lands on the app delegate. **Never name a scene delegate:**
  it blanks every screen. (§3.5)
- `CKSharingSupported` follows the flag. (§3.5)
- Sharing uses a custom zone and a `CKShare`, keyed off `tripID`. Only the trip
  may pass `creatingIfNeeded: true`. (§3.5)
- `modifyRecords` returns per-record results; inspect them. (§3.5)
- Letters choose their transport through `chooseLetterTransport(cloudAvailable:)`.
  Don't unify the transports. (§8.3)
- The letter address is routing, not a lock. `LetterSeal` seals to the
  recipient's key; no key means refuse, never send in clear. (§8.3)
- A `LetterDrop` record needs `parent`. The body rides in `encryptedValues`.
  The loopback doesn't seal. (§8.3)
- `collectLetters` is silent on failure and `postLetters` is not. The
  vocabulary splits on `lettersAreStuck`. (§8.3)
- A switched-off transport fails in the shape `TransportConformance.inert`
  pins. Conflict is the coordinator's to retry. (§3.5)
- The default sync transport is CloudKit, inert when the flag is off; with no
  container the line says "on this phone". The loopbacks are reached only by
  injection, never as a fallback. (§3.5)
- With no CloudKit, letters get `ClosedLetterDropTransport`, and
  `postLetters` skips a transport that isn't available. (§8.3)

### The book, the ritual, the letters
- `BookSpreadView` draws the preview *and* the PDF. A spread is two pages, and
  page numbers are derived. (§8.2)
- Facing pages are even then odd; `BookPlan.leftPage(ofSpreadAt:)` is the one
  formula. (§8.2)
- The last night belongs to the last country. (§8.2)
- The PDF is drawn into a `CGContext`, never rasterised. Check the file, not the
  screen. (§8.2)
- The trim is Lulu's 8.5 × 8.5 with a 24-page floor. Volumes are real spreads,
  each with its own contents. (§8.2)
- `softBelowDPI` (250) is not `dpi` (300). The check measures the short edge,
  through `BookSpec.printedDPI`. (§8.2)
- `BookSpec.bleedScale` is one number for both axes. (§8.2)
- A day's layout is `DaySpreadLayout`. The store clamps the limits. Walk
  `allPhotoIDs`, never `photoID`. (§8.2)
- The composer deletes nothing until it knows what the page kept. It's line
  first, and nothing grows above the picture row. (§8.2)
- Moments are packed by weight in `build`, and spreads carry their ids. They
  print with their country, short groups riding on the opener. (§8.2)
- A missed night leaves a line, not a gap. (§8.2)
- The day page's text is proven to fit in CoreText at every size. The occasion
  and footer facts are inside that proof. (§8.2)
- `DayFacts` is not cached, and the tags win the shared line. (§8.2)
- Blank-line prompts are questions ending in "?". (§8.2)
- Book and cover type are pinned to `.large`. (§8.2)
- "Page" means a page of the book. `pagesPerVolume` counts spread kinds and
  never subtracts. (§8.2)
- The cover is `CoverSpec`, off Lulu's own templates; its cream is not the
  app's. (§8.2)
- The book is cached; a new input joins `bookInputsChanged()`. (§8.2)
- Photos are cropped square on the way in: `UIImage.draw(at:)`, never
  `CGImage.cropping`. The crop cover is `item:`, not `isPresented:`. (§8.2)
- The reader alone turns the phone (`OrientationLock`), and Close is permanent.
  (§8.2)
- The postcard saves and never sends. One add-only path to Photos. (§8.2)
- Never mint an id inside a derived value; read derived values once per
  `body`. (§8.2)
- The app does not order prints. (§8.2)
- The book's maps are arithmetic (`BookMap`), and an opener frames its own
  country. The stamps page draws the arrival screen's `StampSeal`. (§8.2)
- Soft photos and unfinished moments are named on the Book tab while they can
  still be fixed. (§8.2)
- `RitualClock` stores its zone and schedules by interval. It never touches
  `UNUserNotificationCenter` without permission. (§8.1)
- `save(entry:)` replaces on `(dayNumber, author)`. (§8.1)
- `sealedAt == nil` means draft, and only the decoder defaults it.
  `secretCondition` withholds; `.hidden` can't fire. `Silence.id` is its span.
  (§8.3)

### The shelf
- Finishing is one sheet with two answers, acting in `onDisappear`. A closed
  trip leaves the tabs for the shelf. (§8.4)
- `justShelved` is an event, never persisted. Only `closeTrip()` sets it, and
  `take` checks before it clears. (§8.4)
- `TripSummary`'s new fields are optional and must stay so. (§8.4)
- A planned trip is a keyless store in its own file, never synced, built from
  the blank branch. `savePlan()` skips no-op writes; that's load-bearing.
  (§8.4)
- `beginNextTrip` refuses a live trip unless it's discarding, and re-mints the
  card ids. (§8.4)
- A spine's label is sized before rotation and clipped after. Font capped at
  1.3. (§8.4)

### The mark, icons and widget
- The mark is arithmetic in `Shared/TripMark.swift`, with no CoreGraphics.
  (§8.7)
- The overhang belongs to the cut (`TripMarkCut.bleeds`). Clamp the dot, never
  the rule. (§8.7)
- `actool` drops per-size children with `appearances` and exits 0. The 20pt
  slots are a second axis. (§8.7)
- `publishWidget` compares before reloading, and only when `persists`. (§8.8)
- Timeline days use `Calendar.trip`, never `+ 86_400`. (§8.8)
- `DayWidgetView` is in both targets so `-screen widget` can photograph it.
  Compute countdowns; the design's "11 days until Seoul" is wrong. (§8.8)

### Design layer and SwiftUI
- `Typeface.heading(38)` returns a `TypeSpec`; don't simplify it to a `Font`.
  (§4.2)
- Absolute offsets scale with the type factor. (§4.4)
- `Mono` defaults to n700. (§4.4)
- `TypeScale.factor(for:)` is memoised. (§4.4)
- `@Published` fires on every set. Guard before clearing an inbox. (§4.4)
- A `Task {}` in a view method isn't on the main actor; write
  `Task { @MainActor in }`. (§4.4)
- A map without gestures needs `position:`. (§4.4)
- Animations go through `gentleAnimation`. Light appearance is locked on
  purpose. (§4.4)
- The lock is on document screens only. `privacyCovered()` paints over the
  app-switcher snapshot. (§5.2)
- Everything on screen is derived or deleted. (§1)

### Build
- `Model/` imports no SwiftUI or UIKit, except `DocumentStore`. The crypto stays
  out of it. `run-checks.sh` globs. (§6.1)
- `TripStore.now` is the clock; `Date()` appears nowhere else in it. (§6.1)
- `Shared/` is explicit file references, not picked up automatically. The
  widget needs a physical `Info.plist`. (§10)

## Environment

Details in §10.

- Xcode 16.2, iOS 18.3 simulator. Free personal team `6U6Y487HT5`: device builds
  work, the iCloud capability doesn't.
- Turning CloudKit on: paid team, iCloud capability with container
  `iCloud.com.lovedones.dithoi`, then `DiThoiCloudKitEnabled` → `<true/>` in
  `DiThoi-Info.plist`. Verify with `plutil -extract DiThoiCloudKitEnabled raw
  …/DiThoi.app/Info.plist`.
- The persisted trip is plain JSON at
  `Library/Application Support/DiThoi/Store/dithoi.trip.v3` in the data
  container. The preferences should hold only `dithoi.rates.v1` and
  `dithoi.sync.lastSyncedAt`. Read plists after `simctl terminate`.
- Location for screenshots: `xcrun simctl privacy <dev> grant location-always
  com.lovedones.dithoi`, then `xcrun simctl location <dev> set 18.7920,98.9880`.
- The `.xcodeproj` is hand-written; next object id is
  `D1000001000000000000A036`.
- Simulator input is in device points (402×874), and timers expire between a
  screenshot and a tap. Trust `simctl io screenshot` over a frozen window.
- If the MCP simulator integration says Xcode isn't selected, the fix needs the
  user's password. Say so rather than silently falling back.
- Two `xcodebuild` runs on one DerivedData fail with `database is locked`.
- App Groups work on the simulator through simulated entitlements. An empty
  `codesign -d --entitlements` is normal; `simctl get_app_container … group.com.lovedones.dithoi`
  returning a path is the proof.
