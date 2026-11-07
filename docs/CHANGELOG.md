# Changelog

What the app does, and what is known to be wrong with it. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The project went into git on 12 October 2026 with everything below already
built. Nothing before that was versioned, so the first entry describes the
current state as a whole rather than a list of commits.

**v1** is the first iteration: the 1.0 build that went into git, plus every
fix from the October review, closed on 7 November 2026. **v1.1** is the to-do
list from the November review that followed it. When an item lands, tick it
and move its line into Added / Changed / Fixed under a v1.1 release heading.

## [v1.1] — unreleased

### Fixed

- **A switched-off feature showed on Today.** With the shared ledger off the
  spent column is gone and the meeting point takes the row; with nightly pages
  off there is no page row.
- **Old positions were written down for good.** The moment composer and
  `arrive(at:)` take only a fix under 15 minutes old
  (`LocationService.freshFix(at:)`), like every other reader.
- **The meeting point never went stale.** From an earlier night it reads
  "set yesterday · still right?" with a one-tap "still here"; from another
  stop it is not offered on Today, Papers or Separated, and Separated measures
  nothing to it.
- **Pre-trip spending ruined the pace.** Bookings count against the budget but
  not the pace (`pacePerDay`); before departure Money says "Not yet · N days to
  go" and judges nothing, and the forecast waits until something is spent on
  the trip.
- **A page written after midnight was filed under the next day.** Before 05:00
  tonight's page is last night's (`nightDay`), and the composer fixes its night
  when it opens.
- **Papers' "never uploaded" line covered too much.** It sits under Documents
  now, the only part of Papers it is true of.

## [v1.1] — to-do

From a page-by-page review on 7 November 2026, read against the code rather
than the screenshots (several screenshots are months older than the code).
**Must** means it breaks something a screen promises or files something in
the wrong place; **should** means it is wrong or rough, but nothing is lost;
**nice** is a missing feature or a missing link between two parts of the app,
judged against "does it survive week five?" and against the privacy posture.
Items carried over from the v1 known issues say so.

### Everywhere

- [ ] **Must · CloudKit has never run, so the letters from home cannot reach
  the travellers.** The observer's half of the product, and the pairing that
  makes two phones one trip, work only on one phone. Everything else on this
  list is smaller than this. (expansion §2.0; needs the paid membership.)
- [ ] **Should · Switching tabs throws each tab away.** `MainTabs` swaps views
  in a `switch`, so a pushed screen (the ledger, the itinerary, a document),
  the scroll position, Money's undo banner and Today's "not yet" on the
  arrival nudge are all lost on every tab change. The nudge comes back every
  time Today is opened. Keep the five tabs alive (an `opacity`/`hidden` stack,
  or `TabView` with the custom bar) and move "not yet" into the store as an
  event for the day.
- [ ] **Should · Nothing happens at midnight or on resume.** The ending cover
  and Separated are only checked in `MainTabs.onAppear`, so a phone resumed
  (not relaunched) on the last day never shows the ending until a cold launch.
  Nothing republishes the store when the date turns, so a screen left open
  across midnight keeps yesterday. Re-check both, and nudge
  `objectWillChange`, on `.active` and on `significantTimeChangeNotification`.
- [ ] **Should · Location errors are swallowed.** `didFailWithError` is empty,
  so "Finding where you are…" on the meeting point picker waits for ever when
  no fix comes. Give `LocationService` a failed state and the picker a timeout,
  the way Separated's "Finding you…" was fixed.
- [ ] **Should · Helper copy that never goes away.** "Tap a line to edit it;
  hold it to delete" (Money), "Tap one to open it; hold it to edit or delete"
  (Trail, Papers) are permanent lines on screens used fifty times. Show each
  until it has been used once, then drop it. The Trail's version is also
  wrong: tapping a moment *edits* it, there is no separate "open".
- [ ] **Should · Rule drift in `Features/`, where the checks can't see it.**
  "The whole ledger · N lines" is a hand-written ternary (`spelledCount`);
  `budgetComparison` uses `String(format: "%.1f")` (`Formatting.decimal`);
  Money's forecast verdict is computed in the view, so its clauses are
  unchecked (move it to the store beside `burnLine`); `ComposeLetterView`
  reads `Date()` instead of `store.now`.
- [ ] **Should · The screenshots have gaps.** The sample-trip era shots (Lynn
  and Emmie, the phase-1 set, the print order and handoff) were deleted on
  7 November 2026, and `10-trail.png` re-shot; Today is the `v11-` set. Nothing
  current shows onboarding (who, names, writing to, first stop, the trip),
  the print file, the book reader at AX size or the ending at AX size, and the
  October shots still read "synced just now". Re-shoot every route
  (CLAUDE.md, §6.3).
- [ ] **Should · The docs have drifted.** CLAUDE.md lists `MainTabs`,
  `HomeTabs` and `ClassicalTabBar` as files in `Root/` (they live in
  `RootView.swift`); README's decisions still say six currencies; this file's
  1.0 entry says 1,304 assertions where README says 1,745.
- [ ] **Should · An uncommitted Xcode edit stripped `DiThoi-Info.plist`.** The
  working tree drops every comment explaining `DiThoiCloudKitEnabled`,
  `CKSharingSupported` and the URL scheme (the file says "edit it by hand"),
  and sets `UIStatusBarStyle` to an empty string. Restore the comments, keep
  the new `LSApplicationCategoryType`, and decide the status bar on purpose.

### Today

- [ ] **Should · "Today together" shows the first hour, not the next.** At
  6pm it still names the 8am item. Show the next timed item, or the evening's
  last one once the day is over.
- [ ] **Should · The letter card never leaves.** "A letter opened itself here"
  shows the newest opened letter on every day after it opened, pushing
  "Today together" down for weeks. Show it on the day it opened (or until it
  has been read), then only in the letters row.
- [ ] **Should · The header names the holder instead of the place** on a phone
  with no letters (`lettersVisible ? currentCity : myName`). Both travellers
  are in the same city; both headers should say it.
- [ ] **Should · The meeting point opens for editing on a read-only trip**
  (the button isn't gated on `canAdd`), and saves with a success haptic into a
  store that persists nothing.
- [ ] **Nice · A real countdown.** Before departure Today has the first stop
  and the itinerary. Add what is actually useful in the last week, each line a
  link: documents in Papers (and whether the passport has a scan), show-this
  cards written, the money set up, and the second phone paired. Each line is
  computed, none is a checklist to tick.
- [ ] **Nice · "Same place as last night?"** In the picker, offer yesterday's
  point as one tap when the city hasn't changed, and the city's previous
  points first. `meetingPlaces` grows for the whole trip and is never filtered
  by city or trimmed; a remembered place can't be forgotten.

### Trail

- [ ] **Should · A skipped stop blocks the rest of the trail.** `nextStamp` is
  strictly the first unearned one, so a stop they decided not to go to stops
  every later stamp (and every letter sealed to one) until somebody opens the
  itinerary editor and removes it. Offer "We didn't go" beside "I'm standing
  in it": it leaves the stamp unearned and moves on, and the book can say so.
- [ ] **Should · An archived trip's trail hides its moments.** `momentsSection`
  is behind `!isReadOnly`, so the shelf's "Open it again · The trail" shows no
  moments at all. Read-only should mean "no editing", not "nothing listed".
- [ ] **Should · (carried over)** A typed stop the city list doesn't know (a
  camp, a village under 15,000 people) still has no position until somebody
  stands in it.
- [ ] **Nice · A moment you can read.** Tapping a moment opens the editor.
  Open a read view (the photo large, the line, the day and place, a small map)
  with "edit" in its corner; hold still edits or deletes.

### Money

- [ ] **Should · The forecast's copy compares against the wrong thing.**
  "€283/day — above the trip average" compares with `budgetPerDay`, which is
  what the budget allows, not what the trip has averaged. Say "more than the
  budget's €131 a day".
- [ ] **Should · No way to log a currency the itinerary doesn't have.** The
  expense sheet offers the legs' currencies and home only, with no
  "another…" (which the setup pickers have). A layover in Singapore, or
  dollars in Cambodia, can't be written down. The chips are also an `HStack`
  that squeezes past five currencies; use `FlowRow`.
- [ ] **Should · Empty Money says nothing.** With no lines, "Recent" is a
  bare heading over "Tap a line to edit it", and "By country" is empty on a
  trip with no legs. Each needs its own sentence.
- [ ] **Should · "How many nights" sits on every expense.** "×7" on a coffee
  means nothing. Show it for lodging (or call it "repeat").
- [ ] **Should · (carried over)** The rates are today's, so the CSV's home
  column and every converted figure move with the rate instead of recording
  what a line cost the day it was spent. Store the rate on the line at save.
- [ ] **Should · (carried over)** With sync on, nothing tells the other phone
  a settlement is waiting; "Check for X's answer" only looks again.
- [ ] **Nice · From Today's "Spent today" to the day's lines.** The figure
  only adds; holding it (or a "see today" under it) could open the ledger
  filtered to today.

### Book

- [ ] **Should · Tonight's page has no draft.** Every other composer keeps its
  work on a swipe, and a letter saves itself as a draft, but a page lives only
  in view state: an evicted app, a dead battery or an incoming call that
  kills it loses the evening's line. Keep a local draft per night until it is
  saved or thrown away. The journal is the payload of the product.
- [ ] **Should · The copy argues with the book.** "Nobody minds; the book skips
  them" (Book), "the book closes the gap" (backfill offer) — but a missed
  night leaves a line in the book, on purpose (§8.2). Say that.
- [ ] **Should · "Your pages · Nobody reads them until the books are printed"**
  on the sharing screen implies the two books meet. Each book stays on its
  own phone and the app doesn't print. Say "Yours alone. Each of you has your
  own book."
- [ ] **Nice · After the trip, "61 days in"** is still the headline. Say "The
  whole trip · 61 days" and lead with the export.

### Papers and Separated

- [ ] **Should · The separated panel looks tappable and isn't.** It is an
  accent-bordered `Panel` whose only way to change the place is "on Today".
  Add "change" opening the same `MeetingPointPicker`.
- [ ] **Should · "We got separated" works on a closed trip.** The buttons
  aren't gated on `store.isLive`.
- [ ] **Should · (carried over)** A meeting point whose "Which bit of it"
  starts with a capital reads "Go to the Second floor" on Separated.
- [ ] **Nice · The next country's card before the border.** Papers only knows
  `currentCountry`. In the last two days of a country, show the next one's
  card too (emergency numbers, plugs, two sentences), and link it from Today's
  "Vietnam is done" panel.

### Home mode (the observer)

- [ ] **Should · "They're in Hanoi" is sometimes the plan, not a pin.**
  `whereabouts` falls back to `currentCity` from the itinerary under a line
  promising "Pins only". Say "They're in X" only from a pin, with its age
  ("since Tuesday"), and "Due in X" from the plan.
- [ ] **Should · "Their phone last reached wifi…"** reads `sync.lastSyncedAt`,
  which is *this* phone's last round, as the code's own comment says. Say what
  it is, or carry their last contact on the payload.

### Onboarding and the shelf

- [ ] **Nice · Pairing at the end of onboarding can't happen in this build,**
  so the invite step is skipped silently. Say once, on the Trip screen, that
  the second phone is not connected and what that means for letters.

### Score

**6.5 / 10** on 7 November 2026. As a one-phone travel journal, ledger and
papers wallet it is close to an 8: the model layer is unusually careful (1,745
checks, privacy enforced by types rather than by promises), the copy is honest
about almost everything, and the October review's fixes are real. It loses the
rest because the thing that makes it *this* app — two phones as one trip, and
letters from home that open when they arrive — has never run, and because the
two nightly rituals it is built around (the page and the meeting point) both
break on the clock: the page after midnight, the meeting point after the first
day.

## [v1] — 2026-11-07 — the first iteration

Everything in **[v1 · base]** below, plus the October review's fixes.

### Added
- Tapping the day widget during the trip opens tonight's page, or tonight's
  written page to edit. Before departure, after the trip, on the observer's
  phone or with pages switched off, it opens the app as before. The link,
  `dithoi://tonight`, carries no trip data.
- The whole ledger. "The whole ledger · N lines" under Money's recent lines
  opens every line, grouped by day with each day's total, filterable by
  country and settlements. Older lines can be edited and deleted from there.
- A decimal key. Currencies with cents get "." where "000" was, so €3.50 can
  be typed; baht, đồng and won keep "000". Lines with cents can be edited.
- "When" on the expense sheet: today, yesterday, any earlier day of the trip,
  or before you left. A backdated line is filed under where you were that
  day.
- Settling up on one phone. While the build has no sync, "We're both here ·
  clear it" proposes and agrees in one step, after asking whether the other
  traveller is there. The settlement is marked as agreed together.
- "Export as a spreadsheet" at the bottom of the ledger: a CSV of every line,
  home money at today's rates, shared and then deleted from the phone like
  the book.
- Renaming a stop and editing a country. "rename" on each stop row keeps the
  stamps on it and the cities their letters are sealed to. "edit" on each
  country opens one sheet for its name, its currency and removing the whole
  country. Renaming a country re-stamps the lines spent on that visit, and a
  new currency leaves every line already spent in its own.
- Typed stops get a position from a city list bundled with the app (GeoNames,
  cities over 15,000 people, CC BY 4.0, credited in Settings). The list is
  searched only inside the stop's own country. The arrival nudge, the distance
  to the next stop and the map ahead now work on a trip nobody packed. The
  stop sheets say whether a stop is on the map.
- "Pin where I'm standing" in the meeting point picker. The pin goes with the
  place to both phones, and Separated measures to it: "700 m north-east of
  you". A remembered place keeps its own pin.
- "We got separated" on Papers with no meeting point, wherever the app knows
  the country's emergency numbers. Separated then shows those numbers and the
  two phrases.
- The day screen links to that night's page and that day's moments.
- "Stamps with no stop" at the top of the plan editor, for a stamp whose stop
  was removed on the other phone. Each one can be put on a stop or let go.

### Changed
- The observer's home screen draws the travellers' trail, the same drawing
  as the shelf and the book, once there are two pins. It used to show a
  hatched placeholder. "Pins only · never a live position" stays under it.
- New letters are signed with the observer's name, or left unsigned if no
  name was given. A draft still signed "— me, obviously" takes the name when
  it's opened; sealed letters keep what they say.
- The ending's last line says how long the trip was ("ten days", "three
  weeks", "two months") instead of always "two months".
- Papers has one "Trip" row where setup, sharing and the shelf were three. It
  opens a Trip screen holding the three.
- Separated only follows the phone while the meeting point is pinned. An
  unpinned point says to use the written directions.
- Tapping a ledger line opens it to edit, with "Counts as" chips for its
  category; holding it deletes. Tapping used to cycle the category in place.
  New expenses show the chips too, with the guess from the note selected.
- "Nudge" on Settle up is "Check for X's answer", with when it last checked.
  It only ever re-ran sync.
- Today says where the next sealed letter opens, under the letters row.
- The trail's closing line ("X is the last one, and it's just a stamp") is
  gone.
- Day plans are filed by stop and day-of-stop, not by day number, so dragging
  a stop takes its plans with it. A stop shortened past a written day sets the
  plan aside, and lengthening the stop brings it back. If two phones write the
  same day, the newest is shown.
- Hours sort by their time, with untimed ones last. The drag handles are gone.
- The trail lists earned stamps first, in the order they were earned, then
  the rest in plan order.

### Fixed
- The ending screen came back on every launch from the last day until the
  trip was closed. It now comes up once, and once more only if the dates
  change and the trip has a new last day.
- "It stops asking for a page today" is kept. Leaving the app used to
  re-arm the evening prompt the ending had just cancelled.
- On a blank trip the observer's home screen read "They're in —". It now
  reads "They're away".
- Setup's feature list said books were "8 × 8 in" and stamps "GPS only". It
  now says "8.5 × 8.5 in" and "confirmed on arrival".
- Spending with "orapin", "khao" or "soi" in it was filed by the sample
  trip's guesthouse and dinner, and Money shortened "South Korea" to "Korea".
  Both are gone.
- A page written on a trip with nowhere planned stored "—" as its city, and
  the book printed "Day 3 · 4 Aug · —". Pages now store nothing, and a page
  with no city, including one an older build stamped "—", takes the city
  from the itinerary once a stop covers that day.
- Before departure the Book tab said "One day in" and let you write day 1. It
  now says "No pages yet" and when the first one is written, and the store
  refuses a page for any night that hasn't begun.
- The "Yesterday has no page" offer promised the photos "sorted by hour",
  which the app can't do: its access to Photos is add-only.
- Separated's direction read backwards: "north-east of the meeting point"
  when the meeting point was north-east of you.
- Separated said "Finding you…" for ever, because no meeting point had a
  position to measure to.
- Show-this cards keep the screen awake while they're held out.
- An emergency number that doesn't parse is printed and dials nothing. It
  used to dial 112.
- The sharing screen's headline said "Invite" when the build can't invite.
- A trip with no budget reads "€810 spent" and "€67 a day so far" instead of
  "€810 of €0" and "exactly on the burn". The bar, the forecast and the empty
  "Is this cheap?" panel are gone, and Money offers to set a budget for the
  first three visits.
- "By country" counts card payments made in the home currency, converted and
  marked "≈", with a line saying why. Settle up lists every currency a shared
  line was paid in, so its rows add up to the net, and counts them instead of
  saying "three currencies". "1 shared items" is "1 shared item".
- Arriving opens the letters written from home. Letters sealed to a stamp, a
  place or the last stamp opened on the next wake, off screen; the stamp
  screen now shows every letter that opened, one row each. "Arriving here
  opens a letter" asks the letters, and never counts one whose condition was
  withheld.
- The empty trail map frames the itinerary instead of Bangkok, and with no
  stop it can place it shows a frame saying what fills it.
- The last stamp no longer says "0 km" when no stamp has a position.
- The dashed rule between sealed letters is a line, not a zigzag.
- Removing a stop takes its unearned stamps with it. They used to stay "next"
  on the trail, reachable from no editor, and blocked every letter sealed to
  the last stamp. The confirmation names the stamps, the sealed letters and
  the day plans that go. A removal that would complete the trail is refused,
  as removing the last stamp is.
- Before departure the first stop no longer says "you're here"; it says when
  it starts.
- The "clear this day" note sits on the paper, not on a white band.
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

## [v1 · base: 1.0 (build 1)] — 2026-10-12 — first commit

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
- "Today together" is on every phone, with tonight's lodging in it. A phone
  holding letters gets the newest open one above it and an "All 3 · 3 sealed"
  row into the letters whether or not one has opened.
- The meeting sentence drops the possessive when there is no detail, and the
  pace line gives no verdict on a trip with no budget. Its "≈" shows only when
  a rate was used.

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

Moved into **[v1.1] — to-do** at the top of this file. The October review's
three open items are there, marked "carried over"; the rest of that review was
fixed in v1.
