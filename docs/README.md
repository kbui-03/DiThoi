# Đi Thôi — iPhone app

A native SwiftUI implementation of `Đi Thôi - Classical Prototype.dc.html` and
`Đi Thôi - Phase 2.dc.html`: a travel companion for two people on a long trip,
with sealed letters from somebody at home that open when they arrive somewhere.
The prototype drew one trip through Thailand, Vietnam and South Korea; the app
ships with **no trip inside it**. Onboarding asks who is holding the phone, then
the dates, the budget, the currency and the itinerary, and everything else is
computed. Money defaults to euros and is converted at rates the phone fetches
when it can.

From the repository root:

```bash
open DiThoi.xcodeproj
```

Requires Xcode 16+; the app targets iOS 17 and iPhone only (portrait, except the
book reader). Built and run on an iPhone 16 Pro simulator (iOS 18.3).

## The documents

| File | What it is |
|---|---|
| [README.md](README.md) | This file — running it, where each designed screen went, decisions |
| [architecture.md](architecture.md) | How it is built and why |
| [expansion.md](expansion.md) | What to build next, and what not to |
| [CHANGELOG.md](CHANGELOG.md) | What the app does today, and the known issues |
| [archive/](archive) | Historical: the August 2026 review, and how the shipped phases were planned |
| [`../CLAUDE.md`](../CLAUDE.md) | The traps, for whoever edits the code next. It stays at the repository root, which is where Claude Code reads it |

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
| I4 Print handoff | *removed* — the app exports the print files and does not order prints; see "Decisions" |
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
| M Per-trip hue on the shelf | *not built* — see [CHANGELOG.md](CHANGELOG.md) |

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

Every trip starts blank (`TripOrigin.blank`): onboarding runs the real setup —
the trip's name, the dates, the money — and hands off to the itinerary editor
for countries. A trip that arrives filled in (`.packed`), which today means one
joined from the other phone or reopened from a shelved snapshot, gets a manifest
with an **adjust** row instead of a form. Which of the two it is comes from
`origin`, stored at creation, never inferred from what happens to be inside.
`SampleTrip.swift`, the prototype's packed trip, is kept but commented out.

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

## How it works, briefly

Each of these has a full section in [architecture.md](architecture.md).

- **Rates** (§3.3, `Model/Rates.swift`). Fetched opportunistically from two
  free, keyless endpoints, cached, and checked for plausibility against a table
  shipped with the app. Every converted figure carries its age in a `RateStamp`.
  This is the one place the app touches the network, and it works having never
  once succeeded.
- **Two phones** (§3.4). Money, the plan, the trail, the meeting point, the
  show-this cards and the names merge between the travellers' phones. Journals,
  moments, letters and documents never enter the sync payload at all. Settling
  up is propose-then-confirm. Pairing is a link offered at the end of onboarding.
- **Files on disk** (§3.5). The trip is a protected file, not a preferences
  key. Photos are the app's own copies and are backed up; scans are encrypted
  and are not.
- **The phone's hardware** (§3.6, §8.6). The photo picker needs no library
  permission. Location is when-in-use, asked for only by the act that needs it,
  and never in the background. Documents come from the scanner, the photo
  library or a PDF.
- **Type** (§4.2). `Typeface.heading(38)` returns a `TypeSpec` that resolves
  against the reader's text size, so every label scales. Display type is
  capped, body copy isn't.

### Turning on sync

CloudKit is written, complete, and has never run. Until it does, the app's
sync and letter transports are CloudKit's, switched off: **nothing leaves the
phone, and every screen says so** ("on this phone"; Settings gives the reason).
The model checks prove two stores converge through `LoopbackSyncTransport`, a
file box they inject; the app never falls back to it.

To switch CloudKit on, which needs a **paid** Apple Developer membership (a free
personal team cannot hold the iCloud capability):
1. Set `DEVELOPMENT_TEAM` to the paid team.
2. Add the iCloud capability with the container `iCloud.com.lovedones.dithoi`.
3. Set `DiThoiCloudKitEnabled` to `<true/>` in `DiThoi-Info.plist`.

No code changes, and it switches the letters on as well as the trip. Check the
built app rather than the setting:
`plutil -extract DiThoiCloudKitEnabled raw …/DiThoi.app/Info.plist`.

## Checking it

What is built, what has never run and what is known to be wrong are in
[CHANGELOG.md](CHANGELOG.md). From the repository root, the model checks run
without a simulator — 1,530 assertions over the trip maths, the date shifting,
rates, settlement, letter gating and sealing, the book's arithmetic and type
fitting, the shelf, the vault's key handling, and two stores converging through
one loopback box:

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

The full list of routes and seeding flags is in [`CLAUDE.md`](../CLAUDE.md).

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
- **Money defaults to euros.** The prototype is dollar-denominated; two Dutch
  passports are not. A trip can be held in EUR, GBP or USD and spent in those
  plus THB, VND and KRW — the six the app can get a rate for. That list is a
  known limitation (see [CHANGELOG.md](CHANGELOG.md)). The budget starts at
  nothing and is asked for in onboarding.
- **"Now" is the real device date**, not a pinned day. A new trip departs today
  until the travellers say otherwise.
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
  couldn't open itself, so the prototype's four hidden letters could never have
  fired.
- **The app does not order prints.** The design's I4 handed the book to a
  printer and reported "Both books are ordered". It could never have ordered
  both — the other book's pages are only on the other phone — and it reached no
  printer. It now exports the interior and cover PDFs through the share sheet,
  sized for Lulu, and says so.
