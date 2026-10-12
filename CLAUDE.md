# CLAUDE.md

Traps, and the reasons behind them. Everything here is the residue of a real bug.

## What this is

A native SwiftUI iPhone app built from `Đi Thôi - Classical Prototype.dc.html`
and `Đi Thôi - Phase 2.dc.html`: a travel companion for two people on a long
trip, with sealed letters from home that open when they arrive somewhere.

**The app ships with no trip inside it.** A first launch is a blank trip, and
onboarding asks who is holding the phone — either traveller, or the observer who
stays home and writes — along with what they are called, and then for the dates,
the budget, the currency and the itinerary. Everything else is computed. The two
traveller slots are `.one` and `.two`; what they are called is trip data, in
`TripNames`.

The trail is not fixed. Waypoints are made on the itinerary stop they belong to,
and **moments** record what the itinerary never planned for.

Phase 2 is built too: the evening ritual, the printable book, home mode,
multi-trip, the money refinements. Pairing is built as well — one phone invites,
the other follows the link and *joins the same trip*, which until now nothing
did: two phones each minted their own `tripID` and synced quietly past each
other. Only running CloudKit for real is outstanding, and it needs a **paid**
Apple Developer membership; a free personal team cannot hold the iCloud
capability at all.

- **[README.md](README.md)** — run it, screen map, decisions
- **[architecture.md](architecture.md)** — how it's built and why
- **[expansion.md](expansion.md)** — what to build next

## Layout

```
DiThoi/Model/      TripStore, Models, SampleTrip (commented out), TripShape,
                   TrailReplay,
                   Syncing,
                   SyncTransports, SyncCoordinator, TransportConformance,
                   Rates, CountryFacts, LocationService, PhotoStore, PhotoCrop,
                   DocumentStore, ScanVault, DocumentCrypto, Storage,
                   WidgetBridge, Book, SetupSteps,
                   Ritual, LetterDelivery, TripLibrary,
                   DayFacts, LinePrompts, BookScrub, Postcard
DiThoi/Design/     Components, AppLock, ReadOnly
DiThoi/Features/   41 screens grouped by tab, incl. Arrival/, Home/ and Trips/
DiThoi/Root/       RootView, MainTabs, HomeTabs, ClassicalTabBar, DebugScreens,
                   AppShortcuts
Shared/            both targets: Theme, TripMark, TripMarkView, WidgetSnapshot,
                   DayWidgetView, QuickAction, MarkMomentIntent
DiThoiWidget/      WidgetBundle, DayWidget (timeline), MarkMomentControl (iOS 18)
Tools/             run-checks.sh, CheckTrip.swift, VerifyTrip.swift,
                   render-icons.sh, RenderIcons
Screenshots/       107 files — every screen, 3 text sizes
```

~25k lines of Swift, no third-party dependencies.

## Before you change anything

```bash
./Tools/run-checks.sh          # 1,304 model assertions, macOS, no simulator
./Tools/render-icons.sh        # regenerates the icon set and re-tests actool
```

Run the checks after touching `Model/` or `Shared/`. They cover money maths, date
shifting, itinerary reflow, settlement, letter gating and addressing, the day-plan
and card merges, the country table, the shelf, the mark's geometry, the vault's
key handling, the letter seal, the rate plausibility band and the move of the trip
off `UserDefaults` — and run two stores against one loopback box to prove they
converge, which is how sync is verified with no Developer account.

To reach a screen without walking a flow (`#if DEBUG`, out of Release):

```bash
xcrun simctl launch <device> com.lovedones.dithoi -resetTrip -screen money
```

71 routes. `savedpostcard` is the saved page on a night the book reaches a
multiple of seven (`-seedItinerary -seedJournal -day 14`); `postcard -week n` is
the postcard sheet; `exportpostcard -week n` writes the PNG and prints where.
`bookpreview -scrubDay n` draws the page bar's bubble held, `entry -promptIndex n`
picks the blank line's question, and `-seedSpending` puts money on every day so
far — nothing else seeds an expense, so the facts line had none. `-day N` moves the trip to that day and may be zero or negative
(`-day -5` is six days before departure). `-screen widget` draws all four widget
families; `dayplan`, `showcards`, `showcard`, `country` reach the newer screens.
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

## Non-obvious things that will bite you

### Privacy, made structural

**The trip is a protected file, not a `UserDefaults` key.** It used to be JSON in
the app's preferences plist — journal, every letter in full, moments, the ledger,
and via `TripLibrary` every archived trip as well. That plist is in every backup,
is plaintext, and is readable whenever the phone has been unlocked once since
boot, while the passport scans got AES-GCM *and* a backup exclusion.
`PhotoStore.init`'s comment names the asymmetry and only fixed the photographs;
`Review.md` §2.3 is the other half. Both halves now go through
`Storage.writeProtected/readProtected` into `Store/` with
`.completeFileProtection`. **`Storage.forget(_:)` clears both addresses**, so a
key moving between them never stales the reset.

**A protected file can fail to write, and `UserDefaults` could not.** It is
refused while the phone is locked, which is reachable by backgrounding and
locking a second later. So `TripWriter.write` *returns* whether it landed,
`writeFailed` records it, the next foreground retries, and `DiThoiApp` holds a
background-task assertion across `flushAndWait()` rather than sleeping a guessed
two seconds. A check that reads the file it just wrote must use `flushAndWait()`
— `flush()` dispatches and returns.

**The migration writes, reads back, and only then removes.** A remove on faith
loses the trip whenever the write failed, and the write can now fail. Leaving the
old copy for one more launch costs nothing.

**Journals and letters are not fields on `SyncPayload`** — never in the type, not
filtered at the boundary. Don't tidy them in.

**`letterKeys` is on the payload, deliberately, and it is public keys only.** The
pinned field list was edited in the open to add it — that is the check working.
The private half lives in the Keychain via `LetterKeyStore`, so it is in neither
`SyncPayload` nor `TripSnapshot`, which means neither iCloud nor a backup.

**The exported book is the whole journal in one file, and it is deleted.** It
went to `temporaryDirectory` under a name built from the trip's title and nothing
ever removed it; `tmp/` is emptied under storage pressure and on no schedule an
app may rely on. It is `Storage.exportDirectory` now
(`.completeUnlessOpen`, because the share sheet hands it to another process),
cleared before each build, on share-sheet completion, and on `.background`. The
PDF metadata carries the trip's title and **not** the traveller's name — metadata
travels with the file.

**Moments are not on `SyncPayload` either, and `Moment` has no `updatedAt`.**
Without it the type cannot conform to `SyncableRecord`, so it cannot be
`merged(with:)` and cannot be unioned into a payload by somebody tidying — the
same trick as the sealed letter's missing read receipt, one collection over. A
reflection check now pins the payload's field list to a written-down array, so
adding anything to it is a deliberate edit in the open.

**A moment's photograph must be walked by `referencedPhotoIDs` in both halves** —
the live trip *and* every shelved snapshot. `pruneOrphanedPhotos()` runs on
every wake, so doing only the live half deletes them on the first launch after
the trip closes, which is when the book is being printed.

**Letters travel on `LetterDrop`, a one-way channel.** Its `SealedLetter` has no
`openedOn`, `openedPlace` or `receivedAt`; a check reflects over the type and
fails if a read-shaped field appears. Don't unify the transports.

**`role` is the letter box's address on both sides** — the traveller's own slot,
or in home mode the traveller written *to*. A *synced* `letterRecipient` is the
obvious fix and the wrong one: it would tell the other phone a channel exists and
who is on it.

**`lettersVisible` asks what is on the phone, not who holds it**
(`features.letters && !letters.isEmpty`). An empty letterbox is itself a reference
to a channel that may not exist — same reason no screen says "no letters on this
phone", which belongs on the sharing screen.

**`collectLetters` is silent on failure, and `postLetters` is not.** Telling a
traveller a fetch failed tells them a box exists. The asymmetry is the design.

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

**`TravelDocument` has no `updatedAt` and no `deletedAt`, and must gain neither.**
`fields` holds passport numbers. Without `updatedAt` it cannot conform to
`SyncableRecord`, so it cannot be `merged(with:)`, so it cannot be unioned into a
`SyncPayload` by somebody tidying — the `Moment` trick, one collection over, and
a check reflects over the type to hold it. The missing `deletedAt` is the second
half: a tombstone is how a delete beats a concurrent edit across two phones,
there is no second phone for a document, and a tombstoned row is a passport
number still on disk under the word "deleted". `deleteDocument` really removes,
and takes the scans with it.

**Closing a trip is the one thing that deletes.** `closeTrip()`'s doc used to say
"nothing is deleted, so it can be reopened and read", and three screens repeated
it. The papers are now stripped — scans deleted, values cleared — *before* the
snapshot is frozen, so no shelved trip carries a passport number. The labels
survive, so the row reads "emptied" rather than vanishing and breaking the
shelf's promise quietly. The one other deleting act is *throwing a trip away*
(`beginNextTrip(discarding: true)`), which is the other answer on the same
finishing sheet and says so in its own confirmation.

**`ScanVault.prune(keeping:)` is the live trip alone, and `PhotoStore.prune`'s
doc argues the opposite.** Read both. A closed trip's photographs are what its
book is printed from, so that set walks the shelf; a closed trip's scans were
deleted by the close, so no archived snapshot can name one, and adding the shelf
here would preserve exactly what the close destroyed. Both keep
`guard persists` — without it the shelf's reader store, holding a *different*
trip's document ids, takes the live trip's scans with it.

**Nothing pruned the scans at all before this.** `resetTrip` cleared `documents`
and pruned the *photographs*; `ScanVault.deleteAll(for:)` had no callers
anywhere. Invisible only because no document could be made by hand.

**`isReadOnly` is not "this trip is closed".** It is injected by the shelf's
reader and by home mode, and `closeTrip()` sets neither. The root does move to
the between-trips shelf once `isLive` goes false, but a sheet or cover over the
tabs can still be on screen for a moment, and any view reachable from the shelf
reads the same store. Gating on the
flag alone left "tap to import one" and `edit` on an emptied document.
`canEdit` is `!isReadOnly && store.isLive`; the flag is the courtesy and
`isLive` is the state.

**A picker's results are not in the order they were picked.** `loadObject`
completions arrive whenever each finishes, so appending as they land shuffles a
passport's pages — nothing missing, nothing crashing, silently wrong.
`PhotoPicker` writes each result to its own slot and hands the batch over once
every slot has reported.

**`ScanVault.nextIndex(for:)` is one past the highest, not the count**, and pages
sort on the parsed index, not the filename. The two agree inside the zero
padding, which is why a check at twelve pages proves nothing: past it "1000"
sorts before "999".

**The imported PDF is never copied anywhere.** Opened in place under a
security-scoped URL, rasterised, let go. A copy in `temporaryDirectory` is an
unencrypted passport in a folder emptied on no schedule — the bug the exported
book already had once.

**The widget gets one purpose-built value, not the trip.** `dithoi.trip.v3` in the
App Group would put the journal and letters in a container the extension is
entitled to. So `Storage.defaults` stays `.standard` and the group holds one key,
`dithoi.widget.v1` → `[WidgetSnapshot]`. Three checks: no private-looking field
name, **every field a scalar** (nothing holding a collection can carry a journal,
whatever it's later called), and that one key alone. It also means **no
migration**, so `TripStore.init` can never take its seeding branch there.

### Roles

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

**The observer sets no trip parameters.** On a trip somebody filled in they
don't own those answers; on a blank one their settings blob would race the
travellers'.

**`Participant.writer` keeps its raw value.** `decodeIfPresent` *throws* on an
unknown raw value, `TripSnapshot` swallows it with `try?`, and the store re-seeds
over somebody's two months. Renaming a persisted case doesn't lose a field, it
wipes the trip. Same for `Traveller.one` / `.two`.

### Onboarding

**`TripOrigin` is stored, never inferred.** `!legs.isEmpty` looks like the same
question, but the blank branch hands off to the itinerary editor — so counting
what's inside changes the answer *during the flow it gates*.

**`TripStore.init` always seeds a blank trip.** `.packed` is still a real
`TripOrigin`, but the only way to reach it now is a snapshot that carries it —
the shelf, or `Tools/CheckTrip.swift`.

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
  It is a guess drawn on a chip and never applied silently. Nil is the
  ordinary answer (Japan has no rate in this app), and it means no chip is
  preselected.
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

### The trip's shape

**The itinerary is day offsets, not dates.** The travellers own the departure
date, so the itinerary must be invariant under it; dates come from
`date(forDay:)`.

**Changing the start date shifts every dated record.** `setStart(_:)` moves
expenses, journal, letters, stamps, the meeting point and every place in
`meetingPlaces`. Any new dated collection must be added there or the trip loses
its shape.

**Itinerary edits are a mutation plus `reflow()`.** Order and nights are the
authority, `startDay`/`endDay` derived — which makes gaps and overlaps
unrepresentable. `lastDay` compares against `dayCount` directly, no off-by-one.

**`city(forDay:)` falls through to the last segment on the way home.**
`contains(day:)` is half-open because `endDay` is the day they *leave*, so the
final day is in no segment; without `lastKnownSegment(forDay:)` `TripEndingView`
said "— → home".

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

**A country can be entered twice, and `legs` is not the list of them.** Thailand →
Laos → Thailand is an ordinary route. Anything keyed off "*the* leg for this
country" answers with the first; anything that iterates `legs` to talk about
countries says the same one twice. Both shipped: `spent(inCountry:)` did the first
and `perDayByCountry` did the second, so Money drew two "Thailand" rows each
showing every baht spent in Thailand under two different day counts — and
`perDayLine` then found Thailand both cheapest and dearest and silently suppressed
itself. Go through `countries`, `legs(inCountry:)` and `daysSpent(inCountry:)`.

### Waypoints and moments

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

**`Moment` has no `author`, and that is correct.** `JournalEntry` needs one
because a trip can arrive with pages for *both* slots and the book filters to
yours. Nothing ever seeds a moment, so every moment on a phone was made by
whoever is holding it — including after `adopt(_:)` changes which slot that is.
Don't add the field for symmetry.

**Nothing seeds a moment, so a debug route has to make some.** `-resetTrip`
leaves zero, which puts the list, the map marks and the book's moments pages out
of reach. `-screen moments` seeds six, spread over days, stops and one before
departure, through `restoreMoment` — the one mutation taking a whole value.
`momentslist` and `trailmap` use the same six, and with `-seedItinerary` all
three also get `seedWaypoints`: five located stamps, two earned, since nothing
else makes a stamp and every map so far had drawn moments over no trail. **They are seeded in the host's `onAppear`, after `-day` and
`-seedItinerary`** — a child's `onAppear` fires first, so seeding there filed
every moment on a blank trip's day 1 whatever the flags said.

**The way to make a moment is at the top of the trail, and the list stops at
three.** "Mark this one" was the last thing on the screen, under every stamp
and every moment so far — so the further the trip went, the further away it
got, for the one thing only worth doing in the next ten seconds. It is
`MarkMomentLabel` now, the `spentLabel` corner verb, stacking above the
accessibility threshold; the big button survives only in the empty state. The
list shows the newest `TrailView.momentsShown` and an "All N" row pushes
`MomentsView`. The gate is `!isReadOnly && isLive && !isObserver` — `isLive`
because closing a trip injects no flag.

**Outside the app it is App Intents, and never the icon's quick-action menu.**
`UIApplicationShortcutItem` reaches a scene-based app only through a scene
delegate, which is the blank-white-screen trap under *Sync*. `MarkMomentIntent`
(`openAppWhenRun`) sets `QuickActionInbox.pending` and nothing else; Siri and
Spotlight reach it through `DiThoiShortcuts`, iOS 18's Lock Screen, Control
Centre and Action button through `MarkMomentControl`. **`RootView` reads the
inbox, not `MainTabs`**, so it can *drop* a request it can't act on — left
waiting, a tap made during onboarding popped the composer the moment onboarding
ended. `take()` guards before it clears: `InvitationInbox`'s loop, one inbox
over. `-screen markmoment` drives the real route without Siri. Nothing here has
run on a device: the control cannot be added from `simctl`.

**Deleting a moment leaves the photograph to the prune, and that is what makes
undo possible.** `deleteMoment` used to delete the file on the spot, so the only
safety net it could have was a confirmation. It removes the record now and
`pruneOrphanedPhotos()` — which runs on every wake and knows every live and
shelved reference — takes the file later; `restoreMoment` puts the same value
back. `MomentUndo` withdraws the offer when the app leaves the foreground,
because the wake that follows is the prune, and an offer that outlived it would
restore a moment pointing at nothing. `PhotoStore.prune` counts *files*, and a
photograph is two.

**The trail's map is a door; the full-screen one is the map.** `TrailMap` stays
`allowsHitTesting(false)` inline and is wrapped in a button with "open the map"
written on it, since a tappable frame looks exactly like a dead one.
`TrailMapView` passes `interactive: true`, which turns each mark into a padded
button — a 6pt diamond is not a target. Its cards never mention letters: the
same screen is on the observer's tab and in the shelf. `TrailView` pushes through
one `navigationDestination(item:)` over `TrailDestination`.

**"You are here" never asks.** `LocationService.requestOnceIfAllowed()` does
nothing until somebody has already said yes, from a moment, a pin or Separated,
because the prompt belongs to the act that needs a position and the trail is
opened on any afternoon. The dot and "180 km from here" are drawn only on a
traveller's live trip, from a fix under fifteen minutes old, and the distance
only when the next waypoint has a position — every typed one has none, and
"— km" is the dangling separator again. The dot is excluded from the framing,
like moments. `Geo.kilometres` is the one formula; `Stamp.kilometres` calls it.

**The full list groups consecutive runs, by what the moment recorded.**
`Moment.groupedByStop` keys on `(isBeforeDeparture, place)` in capture order,
so Bangkok out and Bangkok home are two groups, and it never consults the
itinerary — a moment is a record, like an expense. `MomentGroup.id` is borrowed
from its first moment, never minted: the `BookSection.id` bug. Under a heading
a row drops the place, and before departure it prints the date, since
"BEFORE WE LEFT" under "Before we left" was the first screenshot.

**The arrival nudge suggests; it never awards.** `nearNextStop` answers the
next waypoint inside `arrivalRadiusKm` (10 km) from a fix the app already had
permission for — `requestOnceIfAllowed`, never a prompt, and never in the
background, which is the promise the location string makes. Today's "Drop the
pin" switches to Trail through `ArrivalRequest` in the environment and opens
Trail's *existing* confirmation, re-checked against `nextStamp` on arrival,
because a stamp cannot be undone and it opens letters. It refuses the observer,
a closed trip and before departure, exactly as `arrive(at:)` would.

**"Keep a moment here" presents from the cover's `onDismiss`.** The stamp
screen is a full-screen cover; a sheet started while it is still animating out
is the `PhotoIntake` race, so the stamp is held in `keepingAt` and handed to
the sheet once the cover is gone. The moment is filed under the *stamp's* city
through `addMoment(city:)` — they can arrive a day before the itinerary says.

**An unfinished moment is derived, never stored.** `Moment.isUnfinished` is an
empty note and no photograph — what "just keep the spot" makes. No field, so no
migration and nothing new on `TripSnapshot`. `printedMoments` leaves them out,
and since everything that paginates reads it, the spread count agrees by
construction; `PrintReadiness.unfinishedMoments` names them on the print
screen. Tonight's page offers **today's** only, so the evening prompt never
turns into a backlog.

**`photoIntake` asks camera or library, and clears `isPresented` on sight.**
Left set while the source dialog was dismissed by a tap outside, the next tap
would set `true` over `true` and open nothing. The camera ends in the same crop
as the picker. A shot is also written to Photos with **add-only** access, so the
app still cannot read the library; refused, the app's copy is kept and the
composer says the other half didn't happen. No camera (the simulator) means no
dialog with one answer in it. The three usage strings were rewritten to match —
the location one still said "only while Separated is on".

**A check that reads its own write uses `flushAndWait()`.** "a store with a key
writes itself" did `flush()` and slept 120 ms, and failed the first time an
Xcode build was running beside it. The rule was already written above; the
check was the one place still guessing.

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

**A Simulator window can stop repainting while the device is fine.** After a
reboot of the device under a running Simulator.app, the window drew black, then
blank white over an app whose main thread was idle and whose `simctl io
screenshot` was correct. Taps still land. Trust the direct capture, not the
window — and sample the process before calling it a layout loop.

**A moment made before departure is filed before departure.** `dayNumber`
clamps to 1, so a moment at Schiphol was stored as "day 1 · Bangkok" and
printed that way. `addMoment` stamps `trueDayNumber` (zero or below) and an
empty city, and `cityNow` — `countryNow`'s twin — never writes the em-dash.
Every reader goes through `Moment.caption` / `place`, which draw "before we
left" and drop the separator when there is no place. `addMoment`,
`updateMoment` and `deleteMoment` refuse a closed trip: the shelved snapshot
names those photographs.

**A moment's mark on the map is neither stamp mark, and is excluded from the
framing.** Filled accent is earned, dashed n500 is ahead; a moment is a hollow
rotated square in n600, off the polyline. One recorded at a layover airport would
otherwise reframe the whole trail.

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

**`TodayView` pushes through one `navigationDestination(item:)`, not two
`isPresented:`.** Two of those stacked on one view is the arrangement where the
later swallows the earlier and the push silently does nothing — a dead control,
which is the failure this screen was being fixed for.

**`todaySegment` is the lenient lookup, and `currentSegment` is not.**
`contains(day:)` is half-open, so the strict one answers nil on the last morning
of the trip — the morning somebody opens the day to check the flight.
`currentCity` already went through `lastKnownSegment` for exactly that reason;
the two deliberately disagree. Nil still means an empty trip or an unplanned
gap, and the panel draws the itinerary rather than pushing to a day with no stop
behind it.

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

### The meeting point

**A blank trip has one, and it is not an answer.** `init`'s blank branch seeds
`MeetingPoint(place: "", detail: "", localScript: "", setAt: .distantPast)` — a
real value nobody chose. Ask `MeetingPoint.isSet`, which keys on `placeKey` so
whitespace doesn't count. `TodayView` was asking correctly and keeping the answer
to itself as a private `hasMeetingPoint`, so Papers printed `". Agreed at 00:53."`
— a bare full stop where the place goes, and `.distantPast` put through a time
formatter — and Separated, the 2am screen, said "Go to the" over an empty card
captioned "show this to a driver". One question on the model, not three views'
worth of guesses.

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

### Editing days and cards

**Day plans and show-this cards are editable, and therefore on `SyncPayload`.**
They were constants while the sharing screen said "money, **plans**, the trail and
the meeting point are shared both ways". Both are `SyncableRecord` now.

**`ShowCard` carries an `index`, like `Stamp`.** The merge unions into a dictionary
and returns `Array(byID.values)`, so append order doesn't survive a sync. Read
`orderedShowCards`, never `showCards`. Day plans order by `dayNumber`, but
`plan(forDay:)` must read `dayPlans.live` — clearing a day tombstones it.

**A day plan's `city` is what it was written *about*.** Plans join on `dayNumber`
while `reflow()` renumbers days, so `DayDetailView.cityName` prefers the segment
covering the day.

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

### The country card

**Emergency numbers come from `CountryFacts`; an unknown country draws nothing.**
A fixed set under a label computed from the current leg prints one country's
numbers under another country's name. `Leg.country` is free text, so silence is
correct: a missing number sends somebody to a hotel desk, a wrong one sends them
nowhere.

**Rule 2 is about staleness, not rendering.** It used to say "only what is
rendered lives here — no plug types", which would have refused the card. Sockets,
mains voltage and a fixed sentence don't move, so they are in. **Airport taxi
fares and consulates were asked for and refused** — fares are wrong within a year,
and a consulate needs a nationality the app has never asked for plus an address
that moves. Both refusals are written into the file.

**`phrases` is `nil` wherever `language` is, and a check enforces it.** A phrase is
written in one script, so a country that won't name a language can't have one.
Also `nil` for English-speaking countries, and — the list to grow — for scripts
nobody has checked with a reader. A whitelist, not an oversight. And **phrases hang
off the country, not the language**: China and Taiwan both label theirs "Mandarin"
and are written in different characters.

**`CountryFacts.language` is a label, not a translation.** It names the show-card
editor's first field. Belgium, Switzerland, Canada, India and South Africa answer
`nil`: "Hindi" in Chennai is the same mistake as Thai numbers under "Vietnam".

**Three call tiles don't fit at an accessibility size.** Vietnam's police ·
medical · fire rendered as "POLIC / E" and "MEDIC / AL" — "SONGKRA / N" again, on
the screen where a misread number matters most. `CallTileRow` stacks above the
threshold and both grounds draw through it, so neither can regress alone.

### Money

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

**Settling is propose → confirm, and the transfer borrows the proposal's id**,
which makes both phones converge on one ledger line and
`applyConfirmedSettlements()` idempotent. `debtor` is stored, not inferred.

**`Expense.isEditable` is why the edit sheet refuses some lines.** A `.transfer`
borrows its proposal's id and amount, and the keypad is whole units, so a
fractional amount can't be typed back in.

**No exchange rate is baked into logic.** `Currency` carries no value; conversion
goes through `inHome(_:from:)`. **Every converted figure needs a `RateStamp`** — a
number without its age pretends to be current.

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

**A model mutation is validated whole, then applied whole.** `updateWaypoint`
used to check and write a field at a time, so a good code with an empty city
changed the code, re-keyed the drafts that named it, returned `false` — and never
reached the `updatedAt` at the bottom, which is the only thing that makes an edit
visible to the merge. The other phone would hand the old code straight back, over
a letter now pointing somewhere else. `canSave` in the editor happens to prevent
it; a guarantee that lives in a view isn't one.

### Persistence

**`TripStore` has a persistence key, and `nil` means "never touch disk"** — which
is what lets the shelf open a closed trip. `init(storeKey: nil, snapshot:)` is the
only way in; a former `adopt(_ snapshot:)` would have fired thirty
`didSet { save() }` handlers over the live trip.

**Writes are coalesced, and `flush()` is not optional.** A burst costs one encode
400 ms later, off the main actor; `DiThoiApp` flushes on the way to background.
**This changed what a second store sees** — one built right after a mutation no
longer finds it on disk, so any check wanting "the same trip on another phone"
must pass `snapshot:` explicitly, or it re-seeds, mints fresh ids, and the merge
unions them into three of everything.

**"Nothing saved" and "saved but unreadable" are different answers.**
`TripSnapshot.stored(key:)` returns `.none` / `.trip` / `.unreadable`; an
unreadable one sets `storageFault`, which makes `save()` refuse. Collapsing them
to `nil` lets `init` start a fresh trip over the top of somebody's two months.

**`TripSnapshot` decodes field by field with defaults.** All thirty are
`decodeIfPresent` and a check strips each key in turn; adding a stored property
without a fallback loses somebody's trip. Relatedly, **what a trip came with is
stored per trip** — `dayPlans`, `documents`, `showCards` and `sharingRules` are
fields on the snapshot, not constants, so a new trip opens with its own papers
rather than another trip's.

**`Storage` is the one seam for `UserDefaults` and the container**, pointed at a
scratch suite by the checks; `discardScratch()` is called explicitly before `exit`,
which doesn't unwind, so a `defer` would never run. **`Storage.shared` returns
`nil` rather than falling back** — `UserDefaults(suiteName:)` hands back a working
object with or without the entitlement, so a fallback would write widget data into
the app's own plist where nothing reads it and nothing complains.

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

**Photos are backed up; passport scans are not.** `PhotoStore` sets
`isExcludedFromBackupKey` to `false` *actively*, since an install on the old build
has it set: excluding them was never privacy, it was data loss. **Pruning them must
consult the shelf** — `referencedPhotoIDs` walks every archived snapshot's journal,
because reading only the live one would gut every finished book.

**`resetTrip()` deletes no photo directly; it prunes.** It used to walk the
journal and the moments and delete what they pointed at, justified as "reset
overwrites rather than archives, so nothing is left pointing at these". True of a
live trip and false of a closed one: `closeTrip()` freezes a snapshot and leaves
the live journal where it is, so the store still names exactly the files that
book is made of until `beginNextTrip` clears it. The same rule holds for
`beginNextTrip(discarding:)`: it prunes rather than deletes. `pruneOrphanedPhotos()` is
the only thing that knows the whole answer. It no-ops on a keyless store, which is
correct and is why a check for this has to build a store *with* a key.

### The shelf

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

**`beginNextTrip` refuses a live trip unless it is discarding.** Closing is its
own confirmed act, and making the next trip must never imply it. It carries the
names, who holds the phone, currency, budget, length, switches and the
show-this cards. The cards get **fresh ids**: the new trip has a new `tripID`,
and a reused id is a card resurrecting against a tombstone on the other phone.
`tripName` is blanked so onboarding asks. Nothing re-pairs the phones: the new
`tripID` means the invite step appears again when `canInvite`.

**It reopens the trail, and `TripStatus.archived`'s doc says so.** The trail used
to be listed among the screens that stay closed while a `HatchPanel` captioned
"the trail as it was" stood in for it — a picture of a screen nothing could open,
under a promise that every screen reopens. Like `MoneyView`, `TrailView` takes
`embedsNavigation: false` when pushed.

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

**A reopened trip draws no sync tag.** The shelf's store has never synced, so
`ScreenTag.syncState` said "not synced yet" about a trip that synced for two
months. True of the throwaway object, false of the trip.

**The app does not order prints, and must not pretend to.** "Send it to the
printer" set `bookOrder` on this phone and reached no printer, then said "Both
books are ordered · two boxes at the door". It could never have ordered both: the
other book's pages are only on the other phone. `PrintHandoffView`, `BookOrder`,
`PrintService`, `place` and `draftOrder` are gone. An old file's `bookOrder` key is
passed over by the keyed decoder, and `TripSummary.printedOn` stays optional and is
no longer written or drawn. Export works from the shelf too: it mutates nothing.

### Sync and the letter channel

**Only the live trip syncs.** `syncNow()` is a no-op once `closedOn` is set, and
`SyncMerge` refuses a payload whose `tripID` doesn't match.

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

**`application(_:userDidAcceptCloudKitShareWith:)`, and no scene delegate.** The
documented callback for an app with scenes is the *scene* delegate's, and it
cannot be used: naming a `delegateClass` replaces the scene delegate SwiftUI
installs, which is what creates the window. The app then launches to a blank white
screen — every screen — with nothing logged and no crash. Both spellings were
tried, a fresh `UISceneConfiguration` and the session's own. Both blank.

**`CKSharingSupported` is on whatever `DiThoiCloudKitEnabled` says.** Without it
iOS hands the link to the browser and the invitation dead-ends. The flag decides
whether this build can *act* on one; a build that can't should still be able to
say so, because silently not opening looks like a broken link at the sender's end.

**Sharing needs a custom zone and a `CKShare`, not the private database**, which is
scoped to one iCloud account — the old fixed `recordName = "trip"` gave one person
device sync and nothing between two people. Default-zone records can't be shared
at all; the record is keyed off `tripID`.

**Letters pick their transport the way sync does, and for a long time they
didn't.** `TripStore.init` said `letterPost ?? LoopbackLetterDropTransport()`,
unconditional, while `SyncCoordinator` probed and chose — so the three steps that
switch iCloud on would have moved the *trip* and left the letters writing to a
file on the observer's own phone. It is now
`chooseLetterTransport(cloudAvailable:)`, taking the flag as an argument rather
than reading the bundle, because that is the only way a check can exercise the
branch this build never takes.

**`CloudKitZone` exists because two transports answered "where does this trip
live" differently** — the letter box enumerated zones looking for one named
`DiThoi`, so a letter could only be posted if the sync transport had already
created it. The anchor is the trip *record*, not the zone name. **Only the trip may
pass `creatingIfNeeded: true`:** the poster is the observer, a participant, so
creating a zone would mint one in their own private database and post into it — a
write that reports success into a box no traveller can ever read.

**`modifyRecords` does not throw when the record failed to save.** It returns
per-record results, and `post` treated a non-nil return as delivery while `push`
had always inspected them. Same class as the `.changedKeys` it also used: a write
built on a stale read silently winning instead of being refused.

**`CloudKitLetterDropTransport` keys on `(tripID, recipient)`**, for the reason the
loopback puts the address in the filename: a phone that could fetch a box and then
decline to draw it has already learned the box exists.

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

**`TransportConformance.inert` pins how a switched-off transport must fail**, not
just that it is off. Callers branch on the shape: a write must throw
`.unavailable`, a read must return `nil` rather than an empty `LetterDrop` — an
empty drop says "there is a box here and it is empty".

**Conflict is not failure, and it is the coordinator's to handle.** The transport
reports `SyncError.conflict`; `SyncCoordinator` re-runs the round. Letters have no
coordinator, so their one retry lives inside `post`.

**Home mode says out loud that the letters haven't gone anywhere.** Every screen on
the writing side described a delivery — "4 delivered", "her phone will open it",
"It's out of your hands" — while the loopback wrote to a file on that same phone.
`deliveredCount` was never the problem: it is condition arithmetic over synced
state, a real prediction. What it never knew is whether the drop *left*, and
"delivered" asserts both. The vocabulary now splits on `lettersAreStuck`.

### The book, the ritual, the letters

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

**`BookSpec.bleedScale` is one number for both axes.** Scaling them separately —
1.0156 against 1.0313 — made every printed page 1.5% taller than wide, type
included. Invisible on screen, permanent in a bound book.

**Photos save at `BookSpec().fullBleedPixels`, not at a number.** Held separately,
`PhotoStore` saved 2048 while the book wanted 2,475, so every photo measured 248
dpi and the print screen warned that *every* page would print soft — a warning that
is always true carries no information.

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

**`RitualClock` stores the zone it learned in.** Observations are wall-clock
minutes, so without it Amsterdam → Bangkok dragged a learned 22:40 to 04:40. The
notification is scheduled from an interval, not calendar components, which resolve
against the device's zone *when they fire*. It never touches
`UNUserNotificationCenter` before permission is held, and asks after the first
saved page, not at launch.

**`save(entry:)` replaces on `(dayNumber, author)`.** Re-opening last night's page
must not append a second one, or a page edited twice prints twice. Swapping the
photo deletes the file it replaced.

**`Letter.sealedAt == nil` means draft, and the initialiser must not default it.**
Defaulting to `writtenOn` sealed every letter on creation and made the writing
side inert; the defaulting belongs in `init(from decoder:)` only.

**`secretCondition`, not `.hidden`, withholds a condition.** A letter whose only
condition is "hidden" can never open itself.

**`LetterSchedule.Silence.id` is its span, not a UUID.** `letterSchedule` is
computed, so a fresh UUID per rebuild means nothing can be compared against it.

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

### The mark and the icons

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

### The widget

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

### Design layer

**`Typeface.heading(38)` returns a `TypeSpec`, not a `Font`.** A `font(_:)`
overload resolves it against `@Environment(\.dynamicTypeSize)`, which is what makes
~150 call sites scale unedited *and* redraw on a text-size change. Don't
"simplify" it back.

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

**The app lock is on `DocumentDetailView` only.** Papers holds the meeting point
and the show-this cards, which exist to be handed to a stranger. `AppLock` opens
rather than seals when the device can't ask at all — a lock nobody can satisfy is a
way of losing your passport at a border.

**Re-locking on `scenePhase` is the state; `privacyCovered()` is the paint.**
SwiftUI gives no guarantee the re-render lands before iOS writes the app-switcher
snapshot, and that snapshot goes to disk at the ordinary protection class — so a
decrypted passport at full brightness could sit in `Library/SplashBoard/`
underneath the lock meant to prevent exactly that. The cover is driven by
`willResignActive`, which is posted *before* the snapshot, and `ScanViewer` needs
its own because a `fullScreenCover` is presented above the view that spawned it.

**Everything on screen is derived or deleted.** The fake signal bar, "texts home
your city", 1.4 GB of offline maps, "38 pins dropped" and `Made at home · April
2027` are gone. If you add a sentence with a number in it, something has to compute
the number.

### Build

**The model layer imports no SwiftUI and no UIKit, with one written-down
exception** — which is what lets the checks build for macOS. `DocumentStore` is it,
listed in `EXCLUDED` at the top of `run-checks.sh`, which compiles everything else
in `Model/` **by glob**. That list used to be by hand, so a new model file was
picked up by Xcode and silently not checked.

**The crypto is not in there any more, and must not go back.** AES-GCM and the
Keychain's `OSStatus` branching are in `DocumentCrypto.swift`, Foundation-only and
therefore checked — the exclusion previously meant the one subsystem whose silent
failure is *unrecoverable* was also the one with no coverage. `DocumentStore` keeps
only `UIImage` ↔ `Data`.

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

**`TripStore.now` is a clock you can hand it**, and `Date()` appears nowhere else
in the class. Without it, midnight, the last day, a DST boundary and a flight into
another zone are untestable by construction.

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

## Known debt, accepted on purpose

Weighed against `Review.md` and left, so the next person meets them deliberately.

- **`TripStore` is ~1,800 lines and every mutation invalidates every view.** The
  seams are clean; what blocks splitting is that they all mutate one persisted
  blob. Cost is redraws and reading time, not correctness.
- **`Participant` / `Traveller` / `Payer` overlap**, as do `name(for:)`,
  `name(of:)` and `label(for:)` — a comment standing where a protocol should.
- **Portrait-only, iPhone-only** — except the book reader, the one screen a 2:1
  spread needs. See "The reader turns the phone".
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

## Key learnings

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

**A screen nothing can reach is a screen nothing checks — and a route that reaches
it can still be in the wrong state.** Today's `notYet` branch had never been
photographed because `-day` refused values below 1. Every home-mode route drew its
view without setting `participant = .writer`, so for the whole of Phase 2 they
photographed the observer's screens with a *traveller's* store behind them —
invisible until the letters learned to say whether they had been posted.

**`@StateObject` is built before `init()` runs.** A debug reset flag in `init()`
cleared state the store had already read, and every screenshot silently carried the
previous run's data.

### Screenshots caught what the assertions couldn't — eleven times

Eleven rounds, every suite fully green over a screen that was wrong:

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

Every one is about what a *reader* concludes, which is what an assertion cannot
hold. Take the screenshots.

## Environment notes

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
