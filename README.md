# Đi Thôi — iPhone app

A native SwiftUI implementation of `Đi Thôi - Classical Prototype.dc.html`, the
Classical-direction prototype for a two-person trip through Thailand, Vietnam
and South Korea. The travellers set their own dates and budget; the money is
euros, converted at rates the phone fetches when it can.

```bash
open DiThoi.xcodeproj
```

Requires Xcode 16+; the app targets iOS 17 and iPhone only (portrait). Built and
run on an iPhone 16 Pro simulator (iOS 18.3).

## Where the prototype's screens went

| Prototype | In the app |
|---|---|
| A1 First open, A2 What's inside | `Features/Arrival/ArrivalFlow.swift` — shown once, then never again |
| — Who's holding this phone, and what you're called | `Features/Arrival/ArrivalFlow.swift`, `ParticipantPicker.swift` — added; one screen, asked before anything else |
| A3 Trip setup | `Features/Arrival/TripSetupView.swift` — a real setup on a blank trip, a confirm on one that arrived filled in, and settings for the rest of the trip |
| B1 Today, G1 the other traveller's today | `Features/Today/TodayView.swift` — one screen, two roles |
| B2 Itinerary, B3 One day | `Features/Today/ItineraryView.swift`, `DayDetailView.swift` — B3 has a day strip, so every day of a stop is reachable, not only the first |
| B4 Add expense | `Features/Money/AddExpenseView.swift` — sheet from Money |
| C1 Letter box, C2 Reading one | `Features/Letters/LettersView.swift`, `LetterReaderView.swift` |
| C3 A stamp unlocks | `Features/Letters/StampEarnedView.swift` — full-screen, from Trail |
| D1 The trail | `Features/Trail/TrailView.swift` — "+ mark a moment" at the top, the newest three moments, and the map as a door |
| *(new)* The whole trail | `Features/Trail/TrailMapView.swift` — the map full-screen, pannable, with a card for whichever mark is tapped |
| *(new)* Every moment | `Features/Trail/MomentsView.swift` — grouped by where each run was kept, newest first |
| Marking a moment | `Features/Trail/MomentComposerView.swift` — from the Trail, or from outside the app (below) |
| *(new)* "Mark a moment" from Siri, Spotlight, the Action button and Control Centre | `Shared/MarkMomentIntent.swift`, `Root/AppShortcuts.swift`, `DiThoiWidget/MarkMomentControl.swift` (iOS 18) |
| A stop's stamp | `WaypointEditorView` in `Features/Today/ItineraryEditorView.swift` |
| D2 Money, D3 Settle up | `Features/Money/MoneyView.swift`, `SettleUpView.swift` |
| E1 Tonight's entry, E2 Looking back | `Features/Book/TonightEntryView.swift`, `BookView.swift` |
| F1 Vault, F2 One document | `Features/Papers/PapersView.swift`, `DocumentDetailView.swift` |
| F3 Show this | `Features/Papers/ShowThisView.swift` — swipeable, screen at full brightness; the card face is its own view so the editor previews the real thing |
| F4 Separated | `Features/Papers/SeparatedView.swift` — full-screen cover |
| G2 What the other traveller can see | `SharingSettingsView` in `Features/Papers/PapersView.swift` |
| TabBar component | `ClassicalTabBar` in `Root/RootView.swift` |
| D4 Lock screen widget | `DiThoiWidget/` — built from the icon set instead; `accessoryRectangular` and `accessoryCircular` |
| *(new)* Itinerary editor | `Features/Today/ItineraryEditorView.swift` |
| *(new)* Day editor | `Features/Today/DayPlanEditorView.swift` — the sentence, the hours and the lodging for one day |
| *(new)* Show-this cards | `Features/Papers/ShowCardEditorView.swift` — the list and the editor; both languages, typed, never translated |
| *(new)* Document editor | `Features/Papers/DocumentEditorView.swift` — behind the same lock as the scans, because a passport number is one whether it's being read or typed |

### Phase 2 — `Đi Thôi - Phase 2.dc.html`

| Prototype | In the app |
|---|---|
| H1 The one notification | `Model/Ritual.swift` — a learned hour, a local notification, no badge |
| H2 Composer, pre-loaded | `Features/Book/TonightEntryView.swift` — line first, a question about the day greyed in it, tags pre-lit |
| H3 Saved | `SavedPageView` in the same file |
| H4 Backfill offer | `BackfillOffer` in `Features/Book/BookView.swift` — once, about last night only |
| I1 Page-turn preview | `Features/Book/BookPreviewView.swift` |
| I1 Full-size reader | `Features/Book/BookReaderView.swift` — tap the preview; the one landscape screen, pinch to zoom, tap a page to change it |
| I2 The four spreads | `Features/Book/BookSpreadView.swift` — one view, screen *and* print |
| I3 Print file | `Features/Book/PrintFileView.swift`, PDF in `BookPDF.swift` |
| I4 Print handoff | `Features/Book/PrintHandoffView.swift` |
| I5 The last stamp | `StampEarnedView` — the ending branch of the existing screen |
| I6 The last letter | `LetterReaderView` — likewise |
| I7 Day 61 | `Features/Book/TripEndingView.swift` |
| J1 His home screen | `Features/Home/HomeView.swift` |
| J2 Compose, J6 Writing session, J9 Mid-trip | `Features/Home/ComposeLetterView.swift` |
| J3 Condition picker | `ConditionPickerView` in the same file |
| J4 Sealed | `SealedConfirmationView` in the same file |
| J5 The board | `Features/Home/LetterBoardView.swift` |
| J7 The handover | `HandoverView` in `Features/Home/HomeView.swift` |
| J8 The two things he's told | the *never sent* block on J1, plus what `LetterDrop` structurally cannot carry |
| J10 The one that never opened | `UndeliveredView` in `Features/Home/HomeView.swift` |
| K1 The shelf (and between trips), K8 Archived | `Features/Trips/ShelfView.swift` |
| K7 Finishing a trip — shelve or throw away | `Features/Trips/FinishTripView.swift` |
| K2–K6 The next trip | `ArrivalFlow`, via `TripStore.beginNextTrip`; switches in `TripSetupView` settings |
| *(2.5, no design)* Categories, per-day rates, repeats | `Model/Models.swift` (`SpendCategory`), `MoneyView`, `AddExpenseView` |

### Icon set — `Đi Thôi - Icon Set.dc.html`

One pin on a line: a rule bleeding off both edges at the vertical centre, celadon
behind the dot and grey ahead of it, the dot fixed at 62% along. The same diagram
is the app icon, the widget, and the progress bar on Today — which is the design's
own argument for the geometry.

| Prototype | In the app |
|---|---|
| M Master · construction, two grounds | `Shared/TripMark.swift` — the cut table, the dot position, the progress maths |
| M Three optical sizes | `TripMarkCut.forIcon(pixels:)`; rendered by `Tools/RenderIcons.swift` |
| M Tinted · iOS 18 monochrome | `MarkGround.tinted` — two values, no hue; iOS supplies the tint |
| M Notification badge | `IconRole.notification` — flat white on grey, a second axis from size |
| M The dot walks · widget only | `DiThoiWidget/DayWidget.swift` — one timeline entry per trip day |
| M Widget lockup | `Shared/DayWidgetView.swift` — small, medium, and both Lock Screen families |
| M The same rule, unwrapped | `Features/Today/TodayView.swift` — above the day header |
| M Per-trip hue on the shelf | *not built* — see **Not done** |

Everything in the set is generated, never hand-drawn:

```bash
./Tools/render-icons.sh
```

## Design tokens

`Shared/Theme.swift` holds the prototype's CSS custom properties: the palette
(the `oklch` accent ramp converted to sRGB), the `--space-*` scale, and the
radii. It sits in `Shared/` rather than `Design/` because the widget extension
needs it too. `Design/Components.swift` holds the recurring pieces — rules,
monospace labels, outlined buttons, bordered panels, the hatched placeholder.

The six colours the mark stands on live in `TripMarkInk` and `Palette` reads
*them*, so the icon generator — which runs on macOS and cannot see SwiftUI — and
the app cannot drift apart on what green means.

Two substitutions were forced by the platform:

- **Type.** Cormorant Garamond, Lora and IBM Plex Mono don't ship with iOS, so
  `Typeface` maps them onto New York (both serif roles, separated by weight and
  tracking instead of by family) and SF Mono. Drop the real TTFs into the bundle
  and only those three functions change.
- **Status bar.** The prototype draws its own time and context ("offline",
  "airplane mode"). The system draws the real time, so only the context word is
  rendered, right-aligned under it.

## The trip is the travellers'

Onboarding asks **who is holding the phone** first, because the answer changes
the whole app: a traveller gets the plan, the ledger, a journal and whatever has
been sealed for them; an observer gets their trail and the letters they write,
and no dates of their own to set.

After that it stops asking for answers somebody already gave. This trip arrives
*packed* — an itinerary, twelve sealed letters, downloaded maps — so setup is a
manifest with an **adjust** row on it rather than a form. A trip nobody packed
(`TripOrigin.blank`) runs the real setup instead and hands off to the itinerary
editor for countries. Which of the two it is comes from `origin`, stored at
creation, never inferred from what happens to be inside.

The three answers below drive everything else, and are editable forever after
from Papers → The trip:

- **Leaving** and **home again**. The length is computed from them and shown
  back, never typed. Moving the departure date shifts everything already
  written down — expenses, journal pages, opened letters, earned stamps — by
  the same number of days, so the trip keeps its shape instead of scattering
  across the calendar. The itinerary is stored as *day offsets* rather than
  dates for the same reason; if it ends up longer than the trip, setup and the
  itinerary screen both say so by how many days.
- **The budget**, in the home currency. Every derived figure comes off it: the
  daily allowance, the pace verdict on Today, the progress bar, the "is this
  cheap?" comparison on a new expense, and the final-country forecast. Nothing
  is measured against a hard-coded amount — a €2,000 trip and a €9,000 trip get
  genuinely different advice.
- **Home currency**, defaulting to **EUR** for two Dutch passports. GBP and USD
  are there too. Changing it converts nothing; it re-reads the same spending in
  a different currency.

Before the departure date, Today shows a countdown and the first stop rather
than pretending to be day one.

## Exchange rates

`Model/Rates.swift`. No rate is baked into the app's logic.

- Fetched when the app opens and whenever it returns to the foreground, from
  `open.er-api.com`, falling back to the jsDelivr currency API. Both are free,
  keyless and public; the request is unauthenticated and sends nothing about
  the trip.
- Throttled to once an hour, and it never blocks the UI. A failed fetch is not
  an error the user has to dismiss — it just means the date under the numbers
  doesn't move.
- Cached to `UserDefaults`, so the last rates that reached the phone keep
  working with no signal. A phone that has never been online falls back to a
  table shipped with the app, and says so in as many words.
- A payload missing any of the app's currencies is rejected outright rather
  than half-updating the table.
- **Every converted figure carries its age.** `RateStamp` sits under the totals
  on Today, Money, Settle up, a day's detail and the new-expense screen, reading
  "rates updated just now", "rates cached 9 hours ago", or "built-in rates ·
  never updated". Tapping it forces a check. Trip setup shows the full picture:
  each currency's current rate, the exact timestamp, and a manual refresh.

This is the one place the app touches the network, which is a deliberate
departure from the prototype's "nothing here needs wifi" — so it is opportunistic
and silent, and the app is still fully usable having never once succeeded.

## Two phones

The shared half of the trip merges with the other traveller's copy:
`Model/Syncing.swift` holds the payload and the merge, `SyncCoordinator` runs a
round, and `SyncTransports.swift` has the pipes.

- **Shared:** money, the itinerary, the trail, the meeting point, settlements.
- **Never shared:** journals, letters and moments. They are not merely filtered
  out of the UI — they never enter the payload type at all. `Moment` has no
  `updatedAt`, so it cannot even conform to the protocol the merge needs.
- **Merging:** expenses, stamps and settlements are append-only and union by id
  (last writer wins on a real clash). The settings and the itinerary are single
  documents, last-writer-wins, with the loser surfaced as a notice. The meeting
  point is last-writer-wins and *always* announced — a silently replaced meeting
  point is how two people end up in different parts of a city.
- **Settling is a genuine two-phase commit.** One proposes, the other confirms,
  and only then does each phone write the `.transfer`. The expense borrows the
  proposal's id, so both phones applying it converge on one line.

### CloudKit is written but inert

`CloudKitSyncTransport` compiles and is complete, but `isAvailable` returns
false without an iCloud entitlement, so it never runs. Until then the app uses
`LoopbackSyncTransport`, a file-backed stand-in. To switch it on: set
`DEVELOPMENT_TEAM` **to a paid team** — a free personal one cannot hold the
iCloud capability at all — add that capability with a container named
`iCloud.com.lovedones.dithoi`, and flip `DiThoiCloudKitEnabled` to `<true/>` in
`DiThoi-Info.plist`. No code changes. It is a physical plist, not
`INFOPLIST_KEY_DiThoiCloudKitEnabled`: Xcode drops custom keys from that
mechanism, so the flag never reached the built app and the setting did nothing.

The loopback transport is not just a placeholder — the model checks point two
stores at one box and assert they converge, so the merge logic is verified
without an account or a second device.

## The phone's own hardware

- **Photos** (`PhotoStore`, `PhotoPicker`) — `PHPickerViewController`, which
  needs no library permission. The app keeps its own downscaled copy plus a
  thumbnail, because the book has to survive them tidying their camera roll.
- **Maps** (`TrailMap` in `TrailView`) — MapKit route and stamps, framed on where
  they have actually been rather than the whole trip. Moments draw as a third,
  quieter mark and are left out of the framing, as is a fourth — "you are here".
  On the trail the map takes no touches and is a door; tapped, it opens
  `TrailMapView`, where it pans and zooms and every mark answers with a card.
- **Document scans** (`ScanVault`, `DocumentStore`, `ScannerView`) — a choice of
  three sources rather than a fallback: the VisionKit scanner, several photos at
  once in the order you pick them, or a PDF. AES-GCM at rest with a Keychain key;
  never synced, never backed up, and deleted outright when the trip closes.
- **Location** (`LocationService`) — when-in-use, and asked for by the act that
  needs it: switching Separated on, keeping a moment, dropping a pin. Never at
  launch, and the trail never asks at all — it uses a fix only if one was
  already allowed (`requestOnceIfAllowed`), to draw "you are here" and "180 km
  from here" under the next stop. No background mode, no always-on. Separated
  shows a real distance and bearing, and falls back to the written directions
  when there's no fix.

## Dynamic Type

Screens ask for exact points, because the design is typeset rather than styled.
`Typeface.heading(38)` returns a `TypeSpec` rather than a `Font`, and a
`View.font(_:)` overload resolves it against `@Environment(\.dynamicTypeSize)` —
so every label in the app scales, and SwiftUI redraws when the setting changes,
without a single screen having to know about it.

Growth is capped by size, in `TypeSpec.growthCeiling`. Body copy takes the
reader's setting in full; display type does not, because a 78pt masthead at the
largest accessibility size would be 240pt and nothing would fit beside it.
Shrinking is never capped. Type in a fixed slot — the five tab-bar labels — can
cap itself harder still via `.capped(at:)`.

Verified by screenshot at xSmall, Large and accessibility-XXXL on an iPhone 16
Pro. Tap targets are ≥44pt and VoiceOver labels are in place throughout.

## What actually works

Not a click-through. The model layer is real, and it persists to a **protected
file** — `Application Support/DiThoi/Store/dithoi.trip.v3`, written with
`.completeFileProtection` so it is unreadable while the phone is locked. It was a
`UserDefaults` key until the privacy pass: a preferences plist is in every
backup, is plaintext, and is readable after one unlock since boot, and what was
in it was the journal, every letter in full, the ledger and every archived trip.
The shelf moved with it. Only the exchange-rate table and one sync timestamp are
still preferences.

- Adding an expense recomputes the burn, the per-country totals, the daily
  allowance, the final-country forecast and the balance between them — all in
  the home currency, at the freshest rates the phone has.
- The itinerary is editable: add, remove, reorder and resize stops and
  countries, and the days re-flow. Segments hold order and nights; every edit is
  a mutation plus a reflow, so the plan can never end up with a gap or an
  overlap.
- Splits are real, including **Custom** — a slider sets the non-payer's share.
- Settling writes a `.transfer`, which moves the balance and deliberately does
  *not* touch the budget. Both phones have to agree first.
- Arriving somewhere on the Trail earns the stamp and opens whatever letter was
  sealed to that place. Nothing else can open a letter — a moment never does.
- Waypoints are made and edited on the itinerary stop they belong to, so a trip
  that arrived empty can have a trail. Earned ones are immutable; removing one a
  sealed letter names says which letter it strands.
- Moments record what the itinerary didn't plan for — one photo, one line, the
  phone's own position. They stay on the phone and print in the book, beside the days they happened.
  Making one is never more than a tap away: "+ mark a moment" sits above the
  map, and Siri, Spotlight, the Action button or an iOS 18 control open the
  composer straight from outside the app. One kept at the airport is filed
  "before we left", not on day 1 in a city nobody has reached. Deleting one
  offers ten seconds to take it back, and the full list groups them by stop.
- Capturing is quick. The stamp screen offers "Keep a moment here", filed
  under that stamp's city. Holding "+ mark a moment" or tapping "just keep the
  spot" in the composer keeps the time and place in one tap, to write up later;
  those show as "N to finish" on the trail, today's are offered on tonight's
  page, and the book leaves them out until they're finished. The photo box asks
  camera or library each time, and camera shots go to Photos too (add-only).
- The trail can be watched again: on the last day it draws itself, stamps
  landing and the kilometres counting up, and every shelved trip has "Replay
  the trail", drawn in the book's own hairlines so the trip has one picture.
  Tonight's page offers the night's moments to start from — the first tap
  copies the photo and the words, later taps fill the extra photos, and a missed
  night offers that night's. On the full map, zoomed in, a moment shows its
  photograph. And when a shelved trip has something from this date in an
  earlier year, Today and the shelf say "A year ago today", and tapping it opens
  that trip's book at the page.
- While the app is open near the next stop, Today says "Looks like you're in
  Chiang Mai" and the trail says "you look close". Both lead to the same
  confirmation as before — the app suggests an arrival, it never awards one.
- Sealed letters expose only their condition. Nothing records when one is read.
- Journal entries save, edit, and skip; the book counts missed nights honestly.
- Switching to the other traveller removes the letters *and every reference to
  them*, per the prototype's note.

And since Phase 2:

- **The evening prompt learns its hour** from the times pages actually get written —
  median, so one 3am airport entry doesn't move it — and jitters a few minutes
  either side so it never arrives at the same time twice. There is no screen
  that sets it and none that explains it. No badge, no streak, no count.
- **The book is a real object.** Spreads you can turn, a contents list that
  jumps, and a PDF at print spec — 8 × 8 in, 0.125 in bleed, 300 dpi, rendered
  from the same view the preview draws. Photos below 300 dpi at that trim are
  named by day before anything is sent.
- **Home mode is the other half of the product.** Pick "Him" in trip setup and
  the whole app changes: their pins and the letters you have sealed, and nothing else.
  He writes, sets a condition, seals — and after that neither he nor the app can
  change it or find out whether it was read.
- **Letters travel one way.** A separate `LetterDrop` channel, not a field on
  the sync payload, and the type it carries has no field that could hold a read
  receipt.
- **Many trips, one live.** Finish a trip from one sheet: put it on the shelf,
  or throw it away. The app then waits between trips on the shelf of spines,
  and the next trip is set up through the same onboarding as the first. That
  onboarding opens on "Where next?", suggests a name from the country, and
  draws the new book's spine while it is named. What came over from last time
  (the money, the switches, each show-this card) can be declined row by
  row. The next trip can also be sketched ahead, even mid-trip. It waits on
  the shelf as a dashed spine with a countdown, stays on this phone, and is
  offered the moment the current trip is shelved. A closed trip reopens read-only. Only the live trip syncs,
  notifies or drops pins.
- **Money knows what it went on**: categories inferred from the note and
  corrected by tapping a line, spend by category, per-country daily rates, and a
  four-nights-in-one-guesthouse shortcut that writes four dated lines.
- **The papers are yours to fill in.** Write a document, type what's on it, and
  add pages from the scanner, from the camera roll or out of a PDF — the vault
  and the lock were built two phases ago and had nothing to hold. The numbers
  never reach the sync payload, by not being a field on it. Closing a trip
  deletes the scans and clears the numbers before it goes on the shelf, and says
  how many of each it is about to take.

Run the model checks without a simulator — 980 assertions covering the trip
maths, the date shifting, budget derivation, rate conversion, settlement, the
letter gating, the learned hour, the book's page arithmetic, the one-way letter
channel, the country table and the shelf:

```bash
./Tools/run-checks.sh
```

### Driving the simulator

`Root/DebugScreens.swift` is a `#if DEBUG` screen router — it exists so every
screen can be opened and photographed without synthetic taps, and it compiles
out of Release entirely:

```bash
xcrun simctl launch <device> com.lovedones.dithoi -resetTrip -screen money
```

## Decisions worth arguing about

- **61 days is the default length, not a fixed one.** The prototype's dates
  don't reconcile: 4 Apr – 14 Jun is 72 days, and its per-country nights sum to
  71, against a "61 days" headline repeated on six screens. 61 became the
  default the setup screen opens on, and every night count and date range in the
  UI is computed from the itinerary and the travellers' dates rather than
  written into the page, so nothing can contradict anything else.
- **One build, three roles.** The prototype shows two phones. Who is holding this
  one — either traveller, or the observer at home — is the *first* question
  onboarding asks, which is what makes home mode reachable at all.
- **Money is euros.** The prototype is dollar-denominated; two Dutch passports
  are not. The default budget is €5,500, roughly the prototype's $6,000. The
  headline spend is summed from the seeded ledger rather than transcribed, so it
  reads about €1,630 of €5,500 at today's rates. The Thailand total (฿62,400) is
  exactly the design's, and the balance (~€40 against a designed $42.10) lands
  where the design put it.
- **"Now" is the real device date**, not a pinned day. The default departure is
  eleven days ago, so the app still opens on day 12 as the prototype shows —
  but it's a real date the travellers can move.
- **Light appearance only.** The dark screens (stamp, separated, lock) are
  deliberate moments in a single warm-paper palette, not a dark mode.
- **The composer does not pick tonight's photo.** H2 says "chosen from 84
  today · the one with both your faces", which means holding read access to the
  whole camera roll. The Papers screen promises this app never leaves the phone
  and holds nothing it doesn't need, and `PHPickerViewController` needs no
  permission at all. The other two thirds of "pre-loaded" — something greyed
  in the line to type over (a question about the day now, where the design had
  yesterday's line), tags lit from where they've been — are implemented; the
  photo stays one tap rather than none. **This is the one place the design was
  not followed, and it was followed everywhere else.**
- **A spread is two pages, and the page count is derived.** The design says
  both "118 pages, one for each night" and "the spread that repeats 118 times",
  which can't both be true; its own contents list (Vietnam, 30 days, pp 45–98)
  implies roughly two pages a night. Each written night is therefore a spread,
  and every page number on every screen is computed from that.
- **The notification permission is asked for after the first saved page**, not
  at launch. An app that opens with a system alert has spent something it hasn't
  earned.
- **A hidden letter has a real condition.** `secretCondition` withholds the
  *when* from the reader while the letter still knows it — the old `.hidden` case
  couldn't open itself, so those four letters could never have fired.

## Not done

- **The camera has never been used.** The simulator has none, so the source
  dialog, the capture, the crop from a camera shot and the save to Photos are
  built and unexercised; on the simulator the photo box goes straight to the
  picker, which is correct there. A device build is enough to try it.
- **"Mark a moment" has never run from outside the app.** The App Shortcut and
  the iOS 18 control build, and `-screen markmoment` drives the same route
  inside the app — the inbox, the check for who is holding the phone, the
  composer — but Siri, Spotlight and Control Centre need a device. No
  paid membership is involved; a free-team device build is enough to try it.
  The Home Screen icon's long-press menu is deliberately not a route at all:
  it needs a scene delegate, and naming one blanks every screen.
- **The widget has never been dragged onto a real Home Screen.** It builds,
  embeds, reads the shared container, and `-screen widget` draws all four
  families with the shipping view — but adding one needs simulator input this
  machine's tooling couldn't be granted. Same for the Dark and Tinted icon
  appearances: the renditions are confirmed in the compiled `Assets.car`, the
  *Customize* sheet has not been opened.
- **Per-trip hue on the shelf.** The icon set rotates archived trips' hue at the
  same lightness and chroma so spines are distinguishable without a second
  design. Not built — it needs an exact `oklch → sRGB` conversion in Swift, and
  it is the one part of the set that isn't about the icon or the widget.
- **CloudKit has never run.** The transport is written and compiles; without a
  developer team it cannot be executed, so it is untested against the real
  service. The merge it feeds is tested. The App Group is a different case — it
  does run, on the simulator, through the simulated entitlements.
- **PDF import has no automated coverage.** Rasterising a page is `UIImage` work,
  so `DocumentImport` sits in `Features/` where `run-checks.sh` — which builds
  for macOS — cannot reach it. What it hands the vault is checked end to end;
  what it makes of a given PDF has only been looked at.
- **Nothing verifies that a protected file is unreadable while the phone is
  locked** — not the trip, not the shelf, not the scans. Protection classes are a
  no-op on the simulator and compile out for macOS. That the trip is a file, that
  the preferences hold only the rates and a timestamp, that a migration lands
  before the old copy goes, and that a refused write is reported and retried are
  all checked; the class itself needs a locked device.
