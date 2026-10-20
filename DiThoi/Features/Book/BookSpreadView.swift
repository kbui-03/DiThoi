import SwiftUI

/// One spread of the book, drawn at whatever size it is given.
///
/// The same view draws the on-screen preview and the pages that go into the
/// PDF. That is deliberate: a preview rendered by different code from the print
/// file is a preview that can lie, and this book only gets printed once.
///
/// Everything inside scales off `width`, so the 17 × 8.5 inch spread has one
/// layout rather than a phone layout and a print layout that drift apart.
struct BookSpreadView: View {
    @EnvironmentObject private var store: TripStore
    let spread: BookSpread
    /// Full spread width in points; each page is half of it.
    let width: CGFloat
    /// Page number of the left-hand page — always even, because facing pages
    /// are an even page and the odd one after it. See `BookSpread`.
    var leftPageNumber: Int
    /// Print rendering draws photographs at full size; the preview draws
    /// screen-sized copies, because it keeps several spreads ready at once.
    var forPrint: Bool = false
    /// The sections the printed contents lists, numbered to the file this
    /// spread is in. Nil reads the whole book's, which is what the preview
    /// shows; the writer passes each volume's own.
    var sections: [BookSection]? = nil
    /// What a tap on a page changes, in the reader on a live trip. Nil
    /// everywhere else — the PDF, the preview, the shelf — and then no page
    /// takes a tap at all, so the printed file and every other screen are
    /// exactly as they were.
    var onEdit: ((BookEdit) -> Void)? = nil

    private var pageWidth: CGFloat { width / 2 }
    /// The page is square: exactly as tall as it is wide.
    private var height: CGFloat { pageWidth }
    /// One unit of the spread's own scale, so 46pt of margin on a 762pt spread
    /// stays 46pt of margin on a 1224pt one.
    private func s(_ points: CGFloat) -> CGFloat { points * (pageWidth / 381) }

    var body: some View {
        HStack(spacing: 0) {
            switch spread {
            case .opening:
                insideCover
                gutter
                halfTitlePage
            case .title:
                titlePage
                gutter
                routePage
            case .contents(let page):
                contentsPage(page, half: 0)
                gutter
                contentsPage(page, half: 1)
            case .countryOpener(let legID, let country, let nights, let stamps,
                                let fromDay, let toDay, let ordinal, let visit, let carried):
                countryPage(country, nights: nights, stamps: stamps, fromDay: fromDay, toDay: toDay,
                            label: BookPlan.openerLabel(ordinal: ordinal, visit: visit), carried: carried)
                gutter
                if let map = store.bookMap(highlightingLeg: legID) {
                    // A country of one or two places is a dot and a line; its
                    // stops go under a smaller map rather than leaving that
                    // to be the page.
                    let own = Set(map.marks.filter(\.highlighted).map { "\($0.point.x),\($0.point.y)" }).count
                    mapPage(map, heading: "On the trail", labelsAll: false,
                            stopsOf: BookPlan.openerListsStops(locatedPlaces: own) ? legID : nil)
                } else {
                    stopsPage(legID)
                }
            case .day(let entryID):
                HStack(spacing: 0) {
                    photoPage(entryID)
                    gutter
                    textPage(entryID)
                }
                .editable(store.entry(entryID).map { .night(day: $0.dayNumber) }, onEdit)
            case .stamps(let page):
                stampsHalf(page, half: 0)
                gutter
                stampsHalf(page, half: 1)
            case .meetingPlaces(let page):
                meetingHalf(page, half: 0)
                gutter
                meetingHalf(page, half: 1)
            case .moments(_, let heading, let page, let left, let right):
                momentsPage(left, heading: page == 0 ? heading : "\(heading) · continued",
                            pageNumber: leftPageNumber)
                gutter
                if right.isEmpty {
                    notesPage(leftPageNumber + 1)
                } else {
                    momentsPage(right, heading: "\(heading) · continued", pageNumber: leftPageNumber + 1)
                }
            case .wholeTrip:
                wholeTripPage
                gutter
                if let map = store.bookMap() {
                    mapPage(map, heading: "The trail", labelsAll: true)
                } else {
                    routeLinePage
                }
            case .notes:
                notesPage(leftPageNumber)
                gutter
                notesPage(leftPageNumber + 1)
            case .closing:
                colophonPage
                gutter
                insideCover
            }
        }
        .frame(width: width, height: height)
        .background(Palette.n100)
        // A page is a picture of a printed page. Its type follows the page's
        // size, never the reader's text-size setting: at an accessibility
        // size every heading here grew by up to 2.4× while the page stayed
        // the same size, so the preview stopped being the book and its text
        // ran off the page the proof above says it fits.
        .environment(\.dynamicTypeSize, .large)
    }

    private var gutter: some View { Divider().overlay(Palette.divider) }

    private func photo(_ id: String?, maxPixels: Int = 1_000) -> UIImage? {
        guard let id else { return nil }
        return forPrint ? PhotoStore.shared.image(id) : PhotoStore.shared.preview(id, maxPixels: maxPixels)
    }

    // MARK: - The covers

    /// The inside of a cover. It is never printed — the writer skips it — and
    /// the preview draws it as board so nobody reads it as a blank page.
    private var insideCover: some View {
        Rectangle()
            .fill(Palette.n300)
            .frame(width: pageWidth, height: height)
            .accessibilityHidden(true)
    }

    /// Page 1, on its own on the right: the name, small, the way a book opens.
    private var halfTitlePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(store.displayName)
                .font(Typeface.heading(s(22)))
                .tracking(s(22) * -0.01)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            Rectangle().fill(Palette.accent)
                .frame(width: s(36), height: 1)
                .padding(.top, s(16))
            Spacer(minLength: 0)
        }
        .padding(s(54))
        .frame(width: pageWidth, height: height)
    }

    private var colophonPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Rectangle().fill(Palette.accent)
                .frame(width: s(36), height: 1)
                .padding(.bottom, s(18))
            Text(colophon)
                .font(Typeface.body(s(12)).italic())
                .foregroundStyle(Palette.n700)
                .lineSpacing(s(4))
                .fixedSize(horizontal: false, vertical: true)
            Mono("Đi thôi — let's go", size: s(8.5), trackingRatio: 0.14, color: Palette.n500)
                .padding(.top, s(18))
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    /// Every clause computed, and one that has nothing to say drops.
    private var colophon: String {
        let nights = store.bookPlan.dayCountInBook
        var lines = ["\(store.displayName), kept by \(store.myName), \(store.start.shortDayMonth) – \(store.end.shortDate)."]
        if nights > 0 {
            lines.append("\(Formatting.spelledCount(nights, "night")) written down, one line at a time, wherever the day ended.")
        }
        lines.append("Made on the road with Đi Thôi.")
        return lines.joined(separator: " ")
    }

    // MARK: - Title & route

    private var titlePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Whose copy, and nothing more. It said "one of two", which was a
            // promise about a second book this phone can't know exists.
            Mono("\(store.myName)'s copy", size: s(10), trackingRatio: 0.18, color: Palette.a700)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                // The fallback, not the raw name: a trip that was never named
                // printed a blank `Display` here and bound it into a book. Only
                // the PDF's metadata keeps the raw title.
                //
                // A word to a line, and each word shrinks rather than breaking.
                // The name is typed by whoever made the trip, so a word wider
                // than the page is ordinary — "Somewhere warm" set itself as
                // "Somewh / ere / warm" at 76pt, permanently, in a bound book.
                Display(text: store.displayName.replacingOccurrences(of: " ", with: "\n"),
                        size: s(76), tracking: -0.03)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                Rectangle().fill(Palette.accent)
                    .frame(width: s(56), height: 1)
                    .padding(.vertical, s(22))
                Text(BookPlan.subtitle(days: store.dayCount, countries: store.countries.count))
                    .font(Typeface.body(s(16)).italic())
                    .foregroundStyle(Palette.n700)
            }
            Spacer(minLength: s(18))
            Mono("\(store.start.shortDayMonth) – \(store.end.shortDate)", size: s(11), trackingRatio: 0.14)
        }
        .padding(s(42))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    private var routePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("The route", size: s(10), trackingRatio: 0.18)
                .padding(.bottom, s(18))

            // One line per leg rather than per stop. Ten segments on a
            // half-page is a list; five is a route. Per leg, not per country:
            // Thailand on the way back is a second line, because it is.
            ForEach(Array(store.legs.enumerated()), id: \.element.id) { index, leg in
                HStack(alignment: .firstTextBaseline) {
                    Text(stops(in: leg))
                        .font(Typeface.heading(s(17)))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: s(8))
                    Mono(store.date(forDay: leg.startDay).text("MMM"), size: s(11), trackingRatio: 0.06)
                }
                .padding(.vertical, s(7))
                if index < store.legs.count - 1 { Rule() }
            }

            Text(routeFootnote)
                .font(Typeface.body(s(13)).italic())
                .foregroundStyle(Palette.n700)
                .lineSpacing(s(4))
                .padding(.top, s(26))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(s(42))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    /// "Bangkok · Ayutthaya · Chiang Mai" — the first stop of each leg, capped
    /// so a country with seven stops doesn't take the whole page.
    private func stops(in leg: Leg) -> String {
        leg.segments.map(\.primaryPlace).prefix(3).joined(separator: " · ")
    }

    private var routeFootnote: String {
        let plan = store.bookPlan
        let nights = plan.dayCountInBook
        guard nights > 0 else {
            return "Nothing written yet. Every night you write something down becomes a spread in here."
        }
        // The page count and the night count stopped being the same number the
        // moment anything but a night could take a spread, so the sentence
        // stopped claiming they were. It says what each number is instead.
        let moments = plan.momentSpreadCount > 0
            ? ", and what you stopped for along the way"
            : ""
        return "\(plan.pageCount) pages — a spread for \(nights == 1 ? "the one night" : "each of the \(nights) nights") you wrote something down\(moments)."
    }

    // MARK: - Contents

    /// One page of the printed contents: a section to a row, its first page
    /// at the right. A page with no rows left on it is ruled for notes, so
    /// the second page of the spread is only ever contents when the list
    /// needs it.
    @ViewBuilder
    private func contentsPage(_ page: Int, half: Int) -> some View {
        let all = sections ?? store.bookPlan.sections
        let rows = BookPlan.contentsRows(all, page: page, half: half)
        if rows.isEmpty && (page > 0 || half > 0) {
            notesPage(leftPageNumber + half)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Mono(page == 0 && half == 0 ? "Contents" : "Contents · continued",
                     size: s(10), trackingRatio: 0.18, color: Palette.a700)
                    .padding(.bottom, s(14))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, section in
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.title)
                            .font(Typeface.heading(s(13)))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: s(8))
                        Mono("\(section.firstPage)", size: s(10), trackingRatio: 0.06, color: Palette.n700)
                    }
                    .padding(.vertical, s(4))
                    if index < rows.count - 1 { Rule() }
                }
                Spacer(minLength: 0)
                Mono("\(leftPageNumber + half)", size: s(9.5), trackingRatio: 0.14, color: Palette.n500)
            }
            .padding(s(46))
            .frame(width: pageWidth, height: height, alignment: .topLeading)
        }
    }

    // MARK: - A country

    private func countryPage(_ country: String, nights: Int, stamps: Int,
                             fromDay: Int, toDay: Int, label: String, carried: [UUID]) -> some View {
        let carrying = !carried.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Mono(label, size: s(10.5), trackingRatio: 0.18, color: Palette.a700)
            Display(text: country.replacingOccurrences(of: " ", with: "\n"),
                    size: s(carrying ? OpenerMoments.countrySize : 58), tracking: -0.03)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.top, s(carrying ? 10 : 14))
            Rectangle().fill(Palette.accent)
                .frame(width: s(44), height: 1)
                .padding(.vertical, s(carrying ? 14 : 20))
            Text("\(store.date(forDay: fromDay).shortDayMonth) – \(store.date(forDay: toDay - 1).shortDayMonth)")
                .font(Typeface.body(s(15)).italic())
                .foregroundStyle(Palette.n700)
            Spacer(minLength: 0)
            if carrying {
                openerMoments(carried)
                    .frame(height: s(OpenerMoments.band), alignment: .bottomLeading)
                    .padding(.bottom, s(12))
            }
            HStack(spacing: s(30)) {
                figure("Nights", "\(nights)")
                figure("Written", "\(nightsWritten(fromDay: fromDay, toDay: toDay))")
                if store.features.stamps { figure("Stamps", "\(stamps)") }
            }
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    /// A short group of moments, carried by the opener instead of a spread of
    /// their own — sized by `OpenerMoments`, which a check proves they fit.
    /// The shrink underneath is a floor nothing `openerCarries` allows should
    /// reach.
    private func openerMoments(_ ids: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: s(OpenerMoments.tileGap)) {
            ForEach(ids.compactMap { store.moment($0) }) { moment in
                HStack(alignment: .top, spacing: s(OpenerMoments.thumbGap)) {
                    if let image = photo(moment.photoID, maxPixels: 400) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: s(OpenerMoments.thumb), height: s(OpenerMoments.thumb))
                            .clipped()
                    }
                    VStack(alignment: .leading, spacing: s(2)) {
                        if !moment.note.isEmpty {
                            Text(moment.note)
                                .font(Typeface.heading(s(OpenerMoments.note)))
                                .foregroundStyle(Palette.text)
                                .lineSpacing(s(OpenerMoments.noteSpacing))
                                .minimumScaleFactor(0.7)
                        }
                        Mono("\(moment.caption) · \(moment.capturedAt.stampDate)", size: s(7), trackingRatio: 0.1)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .editable(.moment(moment.id), onEdit)
            }
        }
    }

    /// Nights with a page in this leg. It was "Pages", counted two per entry,
    /// which left out the opener it was printed on.
    private func nightsWritten(fromDay: Int, toDay: Int) -> Int {
        let isLast = store.legs.last?.startDay == fromDay
        return store.myEntries.filter { $0.dayNumber >= fromDay && (isLast || $0.dayNumber < toDay) }.count
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Mono(label, size: s(9), trackingRatio: 0.14)
            Text(value)
                .font(Typeface.heading(s(26)))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
        }
    }

    /// The leg's stops, set as type. This page used to print a hatched panel
    /// captioned "the trail, drawn from every stamp you earned · hairline, no
    /// basemap" — a note from the design file, bound into the book.
    private func stopsPage(_ legID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Where you stayed", size: s(10), trackingRatio: 0.18)
                .padding(.bottom, s(14))
            stopRows(legID, limit: 9, size: 16)
            Spacer(minLength: 0)
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .topLeading)
    }

    /// A leg's stops, one to a row with its nights — on the stops page, and
    /// under a small map.
    private func stopRows(_ legID: UUID, limit: Int, size: CGFloat) -> some View {
        let segments = store.legs.first { $0.id == legID }?.segments ?? []
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.prefix(limit).enumerated()), id: \.element.id) { index, segment in
                HStack(alignment: .firstTextBaseline) {
                    Text(segment.title)
                        .font(Typeface.heading(s(size)))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: s(8))
                    Mono(Formatting.spelledCount(segment.nights, "night", spellingUpTo: 0),
                         size: s(9.5), trackingRatio: 0.08)
                }
                .padding(.vertical, s(6))
                if index < min(segments.count, limit) - 1 { Rule() }
            }
            if segments.count > limit {
                Mono("and \(segments.count - limit) more", size: s(9.5), trackingRatio: 0.08, color: Palette.n600)
                    .padding(.top, s(8))
            }
        }
    }

    // MARK: - A day

    /// The left page, laid out by `DaySpreadLayout`: one photograph full
    /// bleed, two or three as a contact sheet, none as the day set in type.
    @ViewBuilder
    private func photoPage(_ entryID: UUID) -> some View {
        let entry = store.entry(entryID)
        let layout = entry.map(DaySpreadLayout.init) ?? DaySpreadLayout(photoCount: 0, hasNote: false)
        switch layout.photos {
        case .contact:
            contactSheet(entry)
        case .single:
            if let image = photo(entry?.photoID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: pageWidth, height: height)
                    .clipped()
            } else {
                quietDayPage(entry)
            }
        case .quiet:
            quietDayPage(entry)
        }
    }

    /// Two or three photographs: the first large, the others stacked beside
    /// it, the day underneath. A third of the page is the smallest any of
    /// them prints, and the print check measures them at that size.
    private func contactSheet(_ entry: JournalEntry?) -> some View {
        let margin = s(34)
        let gap = s(8)
        let small = (pageWidth - margin * 2 - gap) / 3
        let hero = small * 2
        let ids = entry?.allPhotoIDs ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: gap) {
                contactPhoto(ids.first, side: hero)
                VStack(spacing: gap) {
                    ForEach(Array(ids.dropFirst().prefix(2)), id: \.self) { id in
                        contactPhoto(id, side: small)
                    }
                }
            }
            // No date here: the right-hand page's heading says which day this
            // is, and saying it on both pages printed it twice.
            Spacer(minLength: 0)
        }
        .padding(margin)
        .frame(width: pageWidth, height: height, alignment: .topLeading)
    }

    @ViewBuilder
    private func contactPhoto(_ id: String?, side: CGFloat) -> some View {
        if let image = photo(id, maxPixels: 800) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipped()
        } else {
            Rectangle().fill(Palette.n200).frame(width: side, height: side)
        }
    }

    /// A night written without a photograph gets a page set in type: the
    /// day's number, large. It used to be a hatched box labelled "no photo ·
    /// the page still prints" — true, and printed. The date and the place are
    /// the facing page's heading, and only there.
    private func quietDayPage(_ entry: JournalEntry?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("\(entry?.dayNumber ?? 0)")
                .font(Typeface.heading(s(120)))
                .tracking(s(120) * -0.04)
                .monospacedDigit()
                .foregroundStyle(Palette.a300)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .leading)
        .background(Palette.n100)
    }

    /// The right-hand page of a day, laid out by `DayTextPage` — the numbers a
    /// check measures the worst text the store accepts against.
    ///
    /// The text gets a box of a fixed height, and the sizes are tried largest
    /// first. It used to get "whatever was left" and three sizes, which could
    /// not be checked from outside the view, and let one long word run off the
    /// page. The shrink underneath the last size is a floor nothing the store
    /// saves can reach; it exists so that if a typeface ever disagrees with the
    /// proof, the page shrinks rather than overprinting the tags.
    private func textPage(_ entryID: UUID) -> some View {
        let entry = store.entry(entryID)
        let line = entry?.line ?? ""
        let note = entry?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasNote = !note.isEmpty
        // What the day was, when somebody said: "Market day", written on the
        // day's plan. It was on the day screen and nowhere in the book.
        let occasion = entry.flatMap { store.plan(forDay: $0.dayNumber)?.occasion }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasOccasion = !occasion.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Mono(dayHeading(entry), size: s(10.5), trackingRatio: 0.18, color: Palette.a700)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: s(DayTextPage.headingLine), alignment: .leading)
            if hasOccasion {
                Mono(occasion, size: s(9.5), trackingRatio: 0.16, color: Palette.a700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: s(DayTextPage.occasionLine), alignment: .leading)
            }
            // The trip mark, where an accent rule used to be: how far through
            // the trip this night was. Turning the pages, the dot walks.
            TripMarkView(day: entry?.dayNumber ?? 1, of: store.dayCount,
                         ahead: Palette.n300, walked: Palette.accent,
                         height: s(DayTextPage.mark))
                .padding(.top, s(hasNote ? DayTextPage.ruleAboveWithNote : DayTextPage.ruleAbovePlain))
                .padding(.bottom, s(hasNote ? DayTextPage.ruleBelowWithNote : DayTextPage.ruleBelowPlain))

            ViewThatFits(in: .vertical) {
                ForEach(DayTextPage.scales(forLine: line, hasNote: hasNote), id: \.self) { scale in
                    dayText(line, note, scale: CGFloat(scale))
                }
                dayText(line, note, scale: CGFloat(DayTextPage.scales.last ?? 1))
                    .minimumScaleFactor(0.5)
            }
            .frame(height: s(DayTextPage.textHeight(hasNote: hasNote, hasOccasion: hasOccasion)), alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: s(DayTextPage.footerGap))
            // The tags, and opposite them on the same line what the app already
            // knows about the day. Sharing the line is what leaves the text
            // box, and so every proof of it, exactly where it was.
            //
            // The tags are what somebody chose, so they keep their room and
            // the facts take what is left: the longest of `lines` that fits,
            // a clause shorter at a time, or nothing at all.
            let tags = entry?.tags ?? []
            let facts = entry.map { store.dayFacts(forDay: $0.dayNumber).lines } ?? []
            if !tags.isEmpty || !facts.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if !tags.isEmpty {
                        Mono(tags.joined(separator: " · "), size: s(9.5), trackingRatio: 0.14)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .layoutPriority(1)
                    }
                    Spacer(minLength: s(8))
                    ViewThatFits(in: .horizontal) {
                        ForEach(facts, id: \.self) { line in
                            // A touch tighter than the tags beside it (0.14):
                            // at 0.14 an ordinary day only just fitted beside
                            // two tags on the printed page. The checks hold it.
                            Mono(line, size: s(9.5), trackingRatio: DayFacts.tracking, color: Palette.n500)
                                .fixedSize()
                        }
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
            }
            // The page number, and on the right — on the same line, so the
            // page's proven geometry doesn't move — the nights before this one
            // that have no page. The book used to close over them silently.
            HStack(alignment: .firstTextBaseline) {
                Mono("\(leftPageNumber + 1)", size: s(9.5), trackingRatio: 0.14, color: Palette.n500)
                Spacer(minLength: s(8))
                if let missed = store.bookPlan.missedBefore[entryID] {
                    Mono(BookPlan.missedLine(missed), size: s(9.5), trackingRatio: 0.14, color: Palette.n500)
                        .lineLimit(1)
                }
            }
            .padding(.top, s(8))
        }
        .padding(s(DayTextPage.margin))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    /// The line alone, or the line and a few more lines, at one of
    /// `DayTextPage.scales`.
    @ViewBuilder
    private func dayText(_ line: String, _ note: String, scale: CGFloat) -> some View {
        if note.isEmpty {
            Text(line)
                .font(Typeface.heading(s(DayTextPage.lineAlone * scale)))
                .tracking(s(DayTextPage.lineAlone * scale) * -0.02)
                .foregroundStyle(Palette.text)
                .lineSpacing(s(DayTextPage.lineAloneSpacing * scale))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: s(DayTextPage.lineToNote * scale)) {
                Text(line)
                    .font(Typeface.heading(s(DayTextPage.lineWithNote * scale)))
                    .tracking(s(DayTextPage.lineWithNote * scale) * -0.015)
                    .foregroundStyle(Palette.text)
                    .lineSpacing(s(DayTextPage.lineWithNoteSpacing * scale))
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .font(Typeface.body(s(DayTextPage.note * scale)))
                    .foregroundStyle(Palette.n700)
                    .lineSpacing(s(DayTextPage.noteSpacing * scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayHeading(_ entry: JournalEntry?) -> String {
        guard let entry else { return "" }
        let place = entry.city.isEmpty ? "" : " · \(entry.city)"
        return "Day \(entry.dayNumber) · \(entry.date.dayMonth)\(place)"
    }

    // MARK: - The stamps

    @ViewBuilder
    private func stampsHalf(_ page: Int, half: Int) -> some View {
        let earned = store.earnedStamps
        if let range = BookPlan.stampRange(spread: page, half: half, earned: earned.count) {
            stampsGrid(Array(earned[range]), pageNumber: leftPageNumber + half)
        } else {
            stampsTextPage
        }
    }

    private var stampsTextPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Mono(stampCountLine, size: s(10.5), trackingRatio: 0.18, color: Palette.a700)
            Display(text: "Everywhere\nyou stood", size: s(44), tracking: -0.03)
                .padding(.top, s(16))
            Rectangle().fill(Palette.accent)
                .frame(width: s(44), height: 1)
                .padding(.vertical, s(20))
            Text("Each one only appeared when the phone agreed you were really there.")
                .font(Typeface.body(s(14)))
                .foregroundStyle(Palette.n700)
                .lineSpacing(s(6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    private var stampCountLine: String {
        let earned = store.earnedStamps.count
        let total = store.orderedStamps.count
        let words = ["none", "one", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "eleven", "twelve"]
        guard earned < words.count, total < words.count else { return "\(earned) of \(total)" }
        return "\(words[earned].capitalized) of \(words[total])"
    }

    /// The seals, four to a row and three rows deep, each with its city under
    /// it, in plain stacks. `LazyVGrid` is a container built for scrolling,
    /// and this view is also drawn by `ImageRenderer` into the PDF, where
    /// nothing scrolls and nothing is promised about lazy content.
    private func stampsGrid(_ stamps: [Stamp], pageNumber: Int) -> some View {
        let columns = 4
        let rows = stride(from: 0, to: stamps.count, by: columns).map {
            Array(stamps[$0..<min($0 + columns, stamps.count)])
        }
        let side = (pageWidth - s(80) - s(14) * CGFloat(columns - 1)) / CGFloat(columns)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: s(16)) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: s(14)) {
                        ForEach(row) { stamp in
                            VStack(spacing: s(5)) {
                                StampSeal(code: stamp.code, date: stamp.earnedOn, side: side,
                                          dateSize: s(5.6))
                                Mono(stamp.city, size: s(7), trackingRatio: 0.08, color: Palette.n700)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(width: side)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Mono("\(pageNumber)", size: s(9.5), trackingRatio: 0.14, color: Palette.n500)
        }
        .padding(.horizontal, s(40))
        .padding(.top, s(40))
        .padding(.bottom, s(34))
        .frame(width: pageWidth, height: height, alignment: .topLeading)
    }

    // MARK: - Where we said we'd meet

    /// The places they agreed to meet, oldest first. The picker kept every
    /// one of them and the book printed none: the gate somebody walked to at
    /// two in the morning is as much the trip as the stamp.
    @ViewBuilder
    private func meetingHalf(_ page: Int, half: Int) -> some View {
        let places = store.bookMeetingPlaces
        if let range = BookPlan.pagedRange(spread: page, half: half, count: places.count,
                                           perPage: BookPlan.meetingPlacesPerPage) {
            if range.isEmpty {
                notesPage(leftPageNumber + half)
            } else {
                meetingList(Array(places[range]), pageNumber: leftPageNumber + half)
            }
        } else {
            meetingHeadingPage(count: places.count)
        }
    }

    private func meetingHeadingPage(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Mono(Formatting.spelledCount(count, "place"), size: s(10.5), trackingRatio: 0.18,
                 color: Palette.a700)
            Display(text: "Where we said\nwe'd meet", size: s(40), tracking: -0.03)
                .padding(.top, s(16))
            Rectangle().fill(Palette.accent)
                .frame(width: s(44), height: 1)
                .padding(.vertical, s(20))
            // Only what the record holds: each place keeps the last time it
            // was agreed, not the first.
            Text(count == 1 ? "As you last agreed it." : "In the order you last agreed them.")
                .font(Typeface.body(s(14)))
                .foregroundStyle(Palette.n700)
                .lineSpacing(s(6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    private func meetingList(_ places: [MeetingPoint], pageNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.placeKey) { index, place in
                VStack(alignment: .leading, spacing: s(3)) {
                    HStack(alignment: .firstTextBaseline) {
                        // Wraps at one size rather than shrinking: shrunk,
                        // a long name set its row smaller than the next one's.
                        Text(place.place)
                            .font(Typeface.heading(s(15)))
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: s(8))
                        Mono("agreed \(place.setAt.stampDate)", size: s(8), trackingRatio: 0.1)
                            .fixedSize()
                    }
                    if !place.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(place.detail)
                            .font(Typeface.body(s(11)).italic())
                            .foregroundStyle(Palette.n700)
                            .lineLimit(2)
                    }
                    // As typed: the app doesn't translate, and says so where
                    // it is written.
                    if !place.localScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(place.localScript)
                            .font(Typeface.body(s(12)))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(.vertical, s(7))
                if index < places.count - 1 { Rule() }
            }
            Spacer(minLength: 0)
            Mono("\(pageNumber)", size: s(9.5), trackingRatio: 0.14, color: Palette.n500)
        }
        .padding(.horizontal, s(46))
        .padding(.top, s(40))
        .padding(.bottom, s(34))
        .frame(width: pageWidth, height: height, alignment: .topLeading)
    }

    // MARK: - Along the way

    /// One page of a country's moments, cut by `BookPlan.momentPages` — three
    /// in words, two photographs, or one of each — and carried on the spread,
    /// so this page draws exactly what the plan counted.
    ///
    /// They print at the end of the country they happened in, not at the back
    /// of the book, which put a day's moment a hundred pages from its day.
    ///
    /// No verification blurb here, unlike the stamps page. A moment is kept
    /// because somebody said so, with whatever position the phone happened to
    /// have, and the book shouldn't claim more than that.
    private func momentsPage(_ ids: [UUID], heading: String, pageNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: s(16)) {
            Mono(heading, size: s(10), trackingRatio: 0.18, color: Palette.a700)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.bottom, s(2))

            ForEach(ids.compactMap { store.moment($0) }) { moment in
                momentTile(moment)
            }

            Spacer(minLength: 0)
            Mono("\(pageNumber)", size: s(9.5), trackingRatio: 0.14, color: Palette.n500)
        }
        .padding(s(34))
        .frame(width: pageWidth, height: height, alignment: .topLeading)
    }

    /// A moment without a photograph is its words. In the reader, a tap on it
    /// opens it. It used to sit beside a
    /// hatched square standing in for the picture it never had. One with a
    /// photograph gets it at a size worth printing — it was a 74-point
    /// thumbnail, three to a page, whatever it held.
    private func momentTile(_ moment: Moment) -> some View {
        HStack(alignment: .top, spacing: s(14)) {
            if let image = photo(moment.photoID, maxPixels: 700) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: s(120), height: s(120))
                    .clipped()
            }

            VStack(alignment: .leading, spacing: s(5)) {
                if !moment.note.isEmpty {
                    Text(moment.note)
                        .font(Typeface.heading(s(15)))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(s(3))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Under "Before we left" the caption would say it again; the
                // date is what's left to tell them apart.
                Mono(moment.isBeforeDeparture ? moment.capturedAt.stampDate
                                              : "\(moment.caption) · \(moment.capturedAt.stampDate)",
                     size: s(8), trackingRatio: 0.1)
            }
            Spacer(minLength: 0)
        }
        .editable(.moment(moment.id), onEdit)
    }

    // MARK: - The trail, drawn

    /// The trail as hairlines, no basemap: every place they stood, joined in
    /// order. On an opener this country's stops are in the accent and named;
    /// on the whole-trip page every stop carries its code.
    /// - Parameter stopsOf: a leg whose stops are set under a half-size map,
    ///   when the map alone would be a dot or two.
    private func mapPage(_ map: BookMap, heading: String, labelsAll: Bool, stopsOf: UUID? = nil) -> some View {
        let side = pageWidth - s(46) * 2
        return VStack(alignment: .leading, spacing: 0) {
            Mono(heading, size: s(10), trackingRatio: 0.18)
            if let stopsOf {
                trail(map, side: side * 0.5, labelsAll: labelsAll)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, s(12))
                stopRows(stopsOf, limit: 4, size: 14)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                trail(map, side: side - s(24), labelsAll: labelsAll)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .topLeading)
        // An opener's map projects the rest of the trip past its square; the
        // route runs faintly off the page, not over the facing one.
        .clipped()
    }

    private func trail(_ map: BookMap, side: CGFloat, labelsAll: Bool) -> some View {
        BookTrail(map: map, side: side, labelsAll: labelsAll, unit: s(1), faintRest: map.hasHighlight)
    }

    // MARK: - The whole trip

    /// What it all added up to. Every figure is one the trip already knows,
    /// and a figure with nothing in it is left out rather than printed as 0.
    private var wholeTripPage: some View {
        let plan = store.bookPlan
        var figures: [(String, String)] = [("Days", "\(store.dayCount)"),
                                           ("Nights written", "\(plan.dayCountInBook)")]
        if !store.countries.isEmpty { figures.append(("Countries", "\(store.countries.count)")) }
        if store.kilometresTravelled > 0 {
            figures.append(("Kilometres", Formatting.decimal(Double(store.kilometresTravelled), places: 0)))
        }
        if store.features.stamps, !store.earnedStamps.isEmpty {
            figures.append(("Stamps", "\(store.earnedStamps.count) of \(store.orderedStamps.count)"))
        }
        if !store.printedMoments.isEmpty { figures.append(("Moments", "\(store.printedMoments.count)")) }
        let rows = stride(from: 0, to: figures.count, by: 2).map { Array(figures[$0..<min($0 + 2, figures.count)]) }

        return VStack(alignment: .leading, spacing: 0) {
            Mono("The whole trip", size: s(10.5), trackingRatio: 0.18, color: Palette.a700)
            Display(text: "All of it", size: s(44), tracking: -0.03)
                .padding(.top, s(12))
            Rectangle().fill(Palette.accent)
                .frame(width: s(44), height: 1)
                .padding(.vertical, s(16))
            Text("\(store.start.shortDayMonth) – \(store.end.shortDate)")
                .font(Typeface.body(s(15)).italic())
                .foregroundStyle(Palette.n700)
            // Six figures in three rows fill the page; the minimum keeps the
            // dates off the first label, which they printed through.
            Spacer(minLength: s(22))
            VStack(alignment: .leading, spacing: s(16)) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(row, id: \.0) { label, value in
                            figure(label, value)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if row.count == 1 { Spacer(minLength: 0).frame(maxWidth: .infinity) }
                    }
                }
            }
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    /// The route in words, for a trip with no places to draw between.
    private var routeLinePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("The route", size: s(10), trackingRatio: 0.18)
            Spacer(minLength: 0)
            Text(store.legs.map(\.country).joined(separator: " → "))
                .font(Typeface.heading(s(24)))
                .foregroundStyle(Palette.text)
                .lineSpacing(s(6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .leading)
    }

    // MARK: - Notes

    /// The pages a short book is padded with to reach the fewest a printer
    /// binds. Ruled, so they read as room for a ticket stub or a pencil rather
    /// than as a mistake.
    private func notesPage(_ number: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("Notes", size: s(10), trackingRatio: 0.18, color: Palette.n600)
                .padding(.bottom, s(24))
            ForEach(0..<9, id: \.self) { _ in
                Rectangle().fill(Palette.n200).frame(height: 1)
                    .padding(.bottom, s(26))
            }
            Spacer(minLength: 0)
            Mono("\(number)", size: s(9.5), trackingRatio: 0.14, color: Palette.n500)
        }
        .padding(s(46))
        .frame(width: pageWidth, height: height, alignment: .topLeading)
    }
}

/// The trail as hairlines, no basemap — on a country opener, on the
/// whole-trip page, and on the back of the cover. One drawing, so the three
/// can't disagree about where a place is.
struct BookTrail: View {
    let map: BookMap
    let side: CGFloat
    let labelsAll: Bool
    /// One point of the page's own scale.
    let unit: CGFloat
    var line: Color = Palette.n400
    var dot: Color = Palette.n500
    var highlight: Color = Palette.accent
    var label: Color = Palette.n600
    var highlightLabel: Color = Palette.a700
    var moment: Color = Palette.n600
    /// Draw everything that isn't highlighted as context: an opener's other
    /// countries, or the replay's route not walked yet.
    var faintRest = false

    private func s(_ points: CGFloat) -> CGFloat { points * unit }

    private func point(_ mark: BookMap.Mark) -> CGPoint {
        CGPoint(x: mark.point.x * side, y: mark.point.y * side)
    }

    var body: some View {
        // Never more than 40% of the square: at a fixed 96 units a name had no
        // room either side on a half-size map, and was dropped — Huế, unnamed,
        // on the one map that was about Huế.
        let labelWidth = min(s(96), side * 0.4)
        // Clear of a moment's diamond, which a name used to touch: half the
        // diamond and two points more, or the usual 2% where that is wider.
        let gap = max(side * 0.02, s(3.25 + 2))
        let labels = map.labels(all: labelsAll, width: Double(labelWidth / side),
                                height: Double(s(11) / side), gap: Double(gap / side))
        // On an opener the rest of the route is context, drawn fainter than
        // the whole-trip page draws it, so the country's own line reads first.
        let faint = faintRest
        return ZStack(alignment: .topLeading) {
            // Moments: hollow diamonds, the trail's own mark — filled is a
            // stamp, a diamond is somewhere they stopped. Under everything
            // else and a little larger than a dot, because a moment kept at
            // a stamp sits exactly on it: drawn over, the two made one blob;
            // drawn under, the dot sits inside its diamond.
            ForEach(map.moments) { kept in
                Rectangle()
                    .strokeBorder(moment, lineWidth: s(0.7))
                    .frame(width: s(6.5), height: s(6.5))
                    .rotationEffect(.degrees(45))
                    .offset(x: kept.point.x * side - s(3.25), y: kept.point.y * side - s(3.25))
            }

            Path { path in
                for (index, mark) in map.marks.enumerated() {
                    index == 0 ? path.move(to: point(mark)) : path.addLine(to: point(mark))
                }
            }
            .stroke(faint ? Palette.n300 : line,
                    style: StrokeStyle(lineWidth: s(0.8), lineCap: .round, lineJoin: .round))

            // This country's legs of the line, over the rest.
            Path { path in
                for (from, to) in zip(map.marks, map.marks.dropFirst()) where from.highlighted && to.highlighted {
                    path.move(to: point(from))
                    path.addLine(to: point(to))
                }
            }
            .stroke(highlight, style: StrokeStyle(lineWidth: s(1.4), lineCap: .round))

            ForEach(map.marks) { mark in
                Circle()
                    .fill(mark.highlighted ? highlight : (faint ? Palette.n400 : dot))
                    .frame(width: s(mark.highlighted ? 6 : 4), height: s(mark.highlighted ? 6 : 4))
                    .offset(x: point(mark).x - s(mark.highlighted ? 3 : 2),
                            y: point(mark).y - s(mark.highlighted ? 3 : 2))
            }

            // Placed by `BookMap.labels`, so no two names print over each other.
            ForEach(labels) { placed in
                let x = placed.point.x * side, y = placed.point.y * side
                Mono(placed.text, size: s(8), trackingRatio: 0.1,
                     color: labelsAll ? label : highlightLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: labelWidth, height: s(11), alignment: placed.onLeft ? .trailing : .leading)
                    .offset(x: placed.onLeft ? x - gap - labelWidth : x + gap, y: y - s(5.5))
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}

/// The trail as a picture in the app: `BookTrail` on the book's paper, in a
/// square as tall as it is given. The replay draws its frames in it and a
/// shelved trip's page draws the whole route — the same drawing the book
/// prints, so a trip has one picture of itself wherever it is shown.
struct TrailPicture: View {
    let map: BookMap?
    var height: CGFloat = 220
    var labelsAll = false
    var faintRest = false

    var body: some View {
        GeometryReader { geometry in
            if let map {
                BookTrail(map: map, side: min(geometry.size.width, geometry.size.height),
                          labelsAll: labelsAll, unit: 1.25, faintRest: faintRest)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(height: height)
        // Moments are never counted toward the frame, so one kept far from
        // every stamp lands outside it; it stays inside the paper.
        .clipped()
        .padding(Space.s3)
        .background(Palette.n100)
        .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
        // A picture of type, like the book's pages: the labels follow the
        // drawing's size, not the reader's text-size setting.
        .environment(\.dynamicTypeSize, .large)
    }
}

/// What a tap on a page in the reader opens.
enum BookEdit: Equatable {
    /// That night's composer.
    case night(day: Int)
    /// The moment's own composer.
    case moment(UUID)
}

private extension View {
    /// A tap target only when there is somewhere for the tap to go. A gesture
    /// attached for nothing would still take the tap, and the preview's "read
    /// it full size" tap would land on a page that swallowed it.
    @ViewBuilder
    func editable(_ target: BookEdit?, _ onEdit: ((BookEdit) -> Void)?) -> some View {
        if let target, let onEdit {
            self.contentShape(Rectangle())
                .onTapGesture { onEdit(target) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens it to change")
        } else {
            self
        }
    }
}
