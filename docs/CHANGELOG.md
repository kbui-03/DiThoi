# Changelog

What the app does, and what is known to be wrong with it. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The project went into git on 12 October 2026 with everything below already
built. Nothing before that was versioned, so the first entry describes the
current state as a whole rather than a list of commits. From here on, each
change gets its own line under **Unreleased**.

## [Unreleased]

### Fixed
- The location copy on the sharing screen and Separated said only Separated
  reads where you are. It now names moments, pins and the trail, and says a
  pin's spot is the one that leaves the phone.
- Turning a feature on or off no longer re-stamps the shared settings, so it
  can't carry this phone's budget over the other phone's newer one.
- "1 nights", "1 days", "1 places" and the like: every count that can reach one
  goes through `Formatting.spelledCount`, including the hand-written
  `== 1 ? "" : "s"` ternaries in `Features/`. The widget, which can't see
  `Formatting`, keeps a ternary.
- The sync line no longer says "synced just now" when nothing has left the
  phone. With CloudKit off, sync and letters use CloudKit's switched-off
  transports instead of the loopback, so screens read "on this phone",
  Settings gives the reason, and "Sync now" is gone until there is something
  to sync with.
- No plaintext copies outside the protected store. The app stopped writing
  `loopback-shared.json` and `letters-*.json`; every launch deletes copies an
  older build left in the container root. The loopbacks the checks use now
  write to `Loopback/`, protected and excluded from backups.
- Moving the start date reaches the other phone. The merge moves the losing
  side's dates into the winning start's frame instead of leaving one ledger
  N days off, and the receiving phone moves its own journal, moments and
  letters. Concurrent edits and deletes keep their usual last-writer-wins.
- About forty currencies instead of six: every country the country card knows
  (Japan, Laos, Cambodia, most of Europe outside the euro, and more), each
  with a built-in rate. Pickers show the likely and home currencies, with the
  rest by name behind "another…"; the home currency can be any of them. A
  fetched table missing one minor currency still updates the rest.
- A new country suggests its likely currency instead of baht.
- No composer throws work away on a swipe or Close. New work asks "Throw it
  away?" first; the day plan keeps its occasion and lodging; a letter saves
  itself as a draft, and an empty one leaves nothing behind. The meeting
  point's "Done" keeps what was typed.
- A photograph picked into tonight's page or a moment survives an app switch
  before saving. The foreground prune used to delete it.
- A document being edited no longer reverts to the saved one after the vault
  re-locks and unlocks.

## [1.0 (build 1)] — 2026-10-12 — first commit

The version Xcode carries (`MARKETING_VERSION 1.0`, build 1). Never submitted
to the App Store; run on the simulator and on a device through a free personal
team.

### Built

**Setting out**
- Onboarding that asks who is holding the phone first — either traveller, or the
  observer who stays home and writes — and what everyone is called, then the
  trip's name, dates, budget, currency and itinerary. The app ships with no trip
  inside it.
- A returning traveller is asked "where next" first, with a suggested trip name
  and what came along from last time (money, switches, show-this cards), each
  of which can be declined.
- Onboarding ends by offering to pair the second phone with a link that carries
  the trip and the other traveller's slot.

**Today**
- The day, the trip mark as a progress rule, the day's plan, tonight's meeting
  point, what was spent today (tap to add), and tonight's page with the book's
  spine beside it.
- A countdown before departure, "home again" with a way to finish the trip
  after it, a nudge when a country has just ended, "a year ago today" from the
  shelf, and an arrival nudge near the next stop.

**The plan**
- An itinerary of countries and stops stored as day offsets, so moving the
  dates never scatters it. Add, remove, reorder and resize; the days re-flow
  with no gaps or overlaps.
- Per-day plans: a sentence, an occasion, hours and lodging.
- Waypoints (stamps) made on the stop they belong to, with suggested codes and
  repeat-visit handling.

**The trail**
- Earning a stamp, with the stamp screen and any letter it opens.
- Moments: a photo, a line and the phone's position, marked from the trail,
  from Siri, Spotlight, the Action button or an iOS 18 control; "just keep the
  spot" for later; undo on delete; a full list grouped by stop.
- An inline map that opens a full-screen explorable one, "you are here", and a
  replay of the trail drawn in the book's own style.

**Money**
- A shared ledger in six currencies with live rates (and their age on every
  converted figure), splits including custom, categories inferred from the
  note, spend by category, per-country daily rates, a final-country forecast
  and a multi-night shortcut.
- Settling up as propose-then-confirm, written as a transfer that never touches
  the budget.

**The book**
- One photo and one line a night, a few more lines if wanted, up to three
  photos, tags, a question about the day in the empty line, and moments to
  borrow from.
- An evening prompt at an hour learned from when pages get written. No badge,
  no streak.
- A preview with a page bar that scrubs by day, a landscape full-size reader in
  which a page can be changed, a weekly postcard saved to Photos, and the
  interior and cover PDFs at Lulu's 8.5 × 8.5 in hardcover spec, in volumes for
  a long trip.

**Papers**
- Documents with typed fields and scans from the scanner, the photo library or
  a PDF, AES-GCM encrypted, behind Face ID or the passcode, excluded from backup.
- Show-this cards at full brightness, a country card with emergency numbers,
  sockets and two phrases, and a Separated screen for when the two of you lose
  each other.

**Home mode (the observer)**
- Writing letters, sealing them to a place, a day, a stamp or "next time
  they're online", a board of when each should land, and the one that never
  did.

**Many trips**
- Finishing a trip from one sheet — shelve it or throw it away — and a shelf of
  spines between trips. Shelved trips reopen read-only. The next trip can be
  sketched ahead as a plan.

**Outside the app**
- A widget in four families, built from the icon set, and app icons rendered
  from the same arithmetic.

### Privacy, made structural
- The trip is a protected file (`.completeFileProtection`), not a
  `UserDefaults` key.
- Journals, moments, letters and documents are not fields on the sync payload.
- Letters travel on their own one-way channel whose type cannot carry a read
  receipt, sealed to the recipient's key.
- The widget gets one scalar-only value, not the trip.
- Closing a trip deletes its scans and clears its document numbers before it is
  shelved.

### Removed
- **The print handoff.** It reported both books ordered without reaching a
  printer. The app now exports the files and says it doesn't order prints.
- **`NewTripFlow`.** It was a second setup flow, duplicating onboarding. Every
  trip is now set up the same way.
- **The prototype's packed trip.** `SampleTrip.swift` is commented out.
- **Chrome transcribed from the prototype**, such as the signal bar, map sizes
  and pin counts. Every number on screen is computed.

### Not yet run
- **CloudKit sync, pairing and letter delivery** are written and compile, but
  have never executed. They need a paid Apple Developer membership. The merge
  they feed is checked; the App Group does run on the simulator.
- **The camera, the App Shortcut and the iOS 18 control** have never run on a
  device. The simulator has no camera, and `-screen markmoment` drives the same
  route inside the app. A free-team device build is enough to try all three.
- **The widget** has never been added to a real Home Screen, and the Dark and
  Tinted icons have never been seen in the *Customize* sheet. Their renditions
  are confirmed in the compiled `Assets.car`.
- **Nothing has been physically printed.**
- **File protection classes** have not been verified on a locked device. They
  are a no-op on the simulator. That the trip is a file, that a migration lands
  before the old copy goes, and that a refused write is retried are all checked.
- **PDF import has no automated coverage.** Rasterising is `UIImage` work,
  which the macOS checks can't build. What it hands the vault is checked.

### Not built from the designs
- **Per-trip hue on the shelf.** The icon set rotates each archived trip's hue
  at the same lightness and chroma. It needs an exact `oklch → sRGB` conversion
  in Swift.
- **The icon's long-press menu.** It needs a scene delegate, and naming one
  blanks every screen. "Mark a moment" goes through App Intents instead.

### Checks
- `./Tools/run-checks.sh`: 1,304 model assertions, all passing on macOS without
  a simulator.

## Known issues

From a screen-by-screen review on 12 October 2026. **Must** means it breaks
something the app promises; **should** means it is wrong or rough, but nothing
is lost.

### Everywhere
- **Should:** location copy still says it is only read in Separated. Moments,
  pins, the trail and the arrival nudge read it too.
- **Should:** toggling a feature re-stamps the shared settings, so a local
  switch can override the other phone's budget change.
- **Should:** "1 nights", "1 days" and "1 places" in a few places.

### Today
- **Must:** a phone holding sealed letters but none opened has no way into
  them, and loses the "Today together" panel.
- **Should:** the meeting line reads "set at The bridge's  if you lose each
  other" when there is no detail.
- **Should:** "under pace" and "over pace" are shown with no budget set.

### Itinerary and day
- **Must:** removing a stop orphans its unearned stamps. They stay "next" on the
  trail, can't be edited, and block letters sealed to the last stamp.
- **Should:** before departure, the first stop says "you're here".
- **Should:** there is no way to rename a stop or country, change a country's
  currency, or remove a whole country.
- **Should:** day plans are keyed by day number, so dragging a stop leaves its
  plans behind.

### Trail
- **Must:** arriving doesn't open letters sealed from home to that stamp or
  place. They open on the next wake, off screen.
- **Should:** typed stops have no position, so the arrival nudge and the
  distance to the next stop never appear.
- **Should:** the map defaults to Bangkok, and the last stamp can say "0 km".

### Letters
- **Should:** the dashed rule between sealed letters strokes both edges of a
  one-point box, which draws a zigzag.

### Money
- **Must:** only the newest six expenses can be reached to edit or delete.
- **Must:** no decimal key, so €3.50 can't be entered.
- **Must:** every expense is dated now, so yesterday's can't be recorded.
- **Must:** settling up can't complete without the other phone.
- **Should:** a trip with no budget reads "€120 of €0", "exactly on the burn",
  and shows an empty "Is this cheap?" panel.
- **Should:** "Across three currencies" is fixed text, "Nudge" only re-syncs,
  and tapping a line cycles its category.

### Book
- **Should:** a page written on a trip with nowhere planned stores "—" as its
  city.
- **Should:** before departure, the Book tab offers day 1.
- **Should:** the backfill offer promises photos "sorted by hour", which the app
  doesn't do.

### Papers and Separated
- **Must:** nothing gives a meeting point a position, so Separated's distance
  never appears.
- **Must:** once the distance does appear, its direction is reversed. It says
  "north-east *of* the meeting point" when the meeting point is north-east of
  you.
- **Should:** the screen can sleep while a show-this card is held out.
- **Should:** an emergency number that fails to parse falls back to dialling
  112.

### Home mode
- **Should:** the home screen reads "They're in —" on a blank trip, and shows a
  hatched placeholder where the trail should be.
- **Should:** letters are signed "— me, obviously" by default.

### Finishing
- **Must:** the ending screen reappears on every launch from the last day until
  the trip is closed.
- **Should:** "It stops asking for a page today" isn't kept, because the prompt
  is re-armed when the app goes to the background.
- **Should:** the ending screen says "two months" whatever the trip's length.

### Settings
- **Should:** feature descriptions still say "8 × 8 in" (it is 8.5 × 8.5) and
  "GPS only" for stamps (they are confirmed, not GPS-verified).
