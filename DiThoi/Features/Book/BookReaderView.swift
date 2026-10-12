import SwiftUI

/// The book, full size, the right way round.
///
/// A spread is two square pages side by side — a 2:1 object — and the preview
/// draws it across a portrait phone, where the contents page set at about six
/// points and a stamp's date at five pixels. This is the one screen the app
/// turns for: `OrientationLock` allows landscape while it is open and puts
/// portrait back when it closes.
///
/// Drawn by `BookSpreadView`, like the preview and the PDF, so reading it here
/// is reading the print file. Swipe to turn, pinch or double-tap to look
/// closer, and — on a live trip — tap a page to change it.
struct BookReaderView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The spread to open on, and where the preview lands afterwards. By id,
    /// because saving a page can renumber the book under it.
    @Binding var spreadID: String?

    @State private var position: String?
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero
    @State private var chromeVisible = true
    @State private var hider: Task<Void, Never>?
    @State private var night: Night?
    @State private var moment: Moment?

    /// A night to write, as a sheet's item.
    private struct Night: Identifiable {
        let day: Int
        var id: Int { day }
    }

    /// Changing a page needs a live trip somebody can write in. A shelved
    /// trip reads; home mode never reaches the book.
    private var canEdit: Bool { !isReadOnly && store.isLive && !store.isObserver }

    var body: some View {
        let plan = store.bookPlan
        GeometryReader { geometry in
            // As wide as the screen allows at the spread's own 2:1.
            let width = min(geometry.size.width, geometry.size.height * 2)
            // A paging `TabView`, as the preview uses: it keeps its selection
            // as the phone turns. A paging `ScrollView` kept its *offset*, so
            // opened in portrait and turned it showed half of one spread and
            // half of the next.
            TabView(selection: $position) {
                ForEach(Array(plan.spreads.enumerated()), id: \.element.id) { index, spread in
                    let current = spread.id == position
                    BookSpreadView(spread: spread, width: width,
                                   leftPageNumber: BookPlan.leftPage(ofSpreadAt: index),
                                   onEdit: canEdit ? open : nil)
                        .scaleEffect(current ? zoom : 1)
                        .offset(current ? pan : .zero)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .tag(Optional(spread.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Turning a page while looking closely would throw the reader off
            // the page they were reading.
            .scrollDisabled(zoom > 1)
            .simultaneousGesture(magnify(in: geometry.size))
            .simultaneousGesture(drag(in: geometry.size), including: zoom > 1 ? .all : .subviews)
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture { showChrome() }
        }
        .background(Palette.n900.ignoresSafeArea())
        .overlay(alignment: .top) { chrome(plan) }
        .overlay(alignment: .topTrailing) { closeButton }
        .statusBarHidden()
        .onAppear {
            position = spreadID ?? plan.spreads.first?.id
            OrientationLock.landscape()
            showChrome()
        }
        .onDisappear {
            spreadID = position
            hider?.cancel()
            OrientationLock.portrait()
        }
        // A turned page brings the chrome back. On a live trip every tap on a
        // night's spread opens it to change, so a tap on "nothing" could not
        // be relied on to find "Close" again once it had faded.
        .onChange(of: position) { _, _ in
            resetZoom(animated: false)
            showChrome()
        }
        // The composers are portrait screens, so the phone turns back for
        // them and round again when they close.
        .sheet(item: $night, onDismiss: OrientationLock.landscape) { night in
            TonightEntryView(day: night.day)
                .environmentObject(store)
        }
        .sheet(item: $moment, onDismiss: OrientationLock.landscape) { moment in
            MomentComposerView(editing: moment)
                .environmentObject(store)
        }
    }

    // MARK: - Chrome

    private func chrome(_ plan: BookPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if canEdit {
                Mono("tap a page to change it", size: 9.5, trackingRatio: 0.1, color: Palette.n400)
                Spacer()
            }
            Mono(pagesLabel(plan), size: 10.5, trackingRatio: 0.1, color: Palette.n300)
            // Room for the close button, which never fades.
            Spacer().frame(width: 44)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Space.gutter)
        // On the page's dark surround, not on the paper: the spread runs to
        // the top of the screen, and light type over it couldn't be read.
        .background(Palette.n900.opacity(0.88).ignoresSafeArea(edges: .top))
        .opacity(chromeVisible ? 1 : 0)
        .allowsHitTesting(chromeVisible)
    }

    /// Always there, and never over nothing: the chrome fades, and when it
    /// carried "Close" a tap meant for it a moment too late landed on the page
    /// under it and opened that night's composer instead.
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.n100)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Palette.n900.opacity(0.85)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close the book")
        .padding(.trailing, 4)
    }

    private func pagesLabel(_ plan: BookPlan) -> String {
        guard let position, let index = plan.spreads.firstIndex(where: { $0.id == position }) else { return "" }
        if index == 0 { return "page 1" }
        let left = BookPlan.leftPage(ofSpreadAt: index)
        return index == plan.spreads.count - 1 ? "page \(left)" : "pages \(left)–\(left + 1)"
    }

    /// Shown on opening and on any tap that changes nothing, then out of the
    /// way of the page.
    private func showChrome() {
        withGentleAnimation(.easeOut(duration: 0.2)) { chromeVisible = true }
        hider?.cancel()
        hider = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withGentleAnimation(.easeIn(duration: 0.4)) { chromeVisible = false }
        }
    }

    // MARK: - Looking closer

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(settledZoom * value.magnification, 1), 4)
                pan = clamped(settledPan, zoom: zoom, in: size)
            }
            .onEnded { _ in
                settledZoom = zoom
                if zoom <= 1.01 { resetZoom(animated: true) }
            }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                pan = clamped(CGSize(width: settledPan.width + value.translation.width,
                                     height: settledPan.height + value.translation.height),
                              zoom: zoom, in: size)
            }
            .onEnded { _ in settledPan = pan }
    }

    /// The page never slides off far enough to show what's behind it.
    private func clamped(_ offset: CGSize, zoom: CGFloat, in size: CGSize) -> CGSize {
        let maxX = (zoom - 1) * size.width / 2
        let maxY = (zoom - 1) * size.height / 2
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    private func toggleZoom() {
        if zoom > 1 {
            resetZoom(animated: true)
        } else {
            withGentleAnimation(.easeInOut(duration: 0.25)) { zoom = 2.5 }
            settledZoom = 2.5
        }
    }

    private func resetZoom(animated: Bool) {
        let reset = {
            zoom = 1
            pan = .zero
        }
        if animated && !reduceMotion { withAnimation(.easeInOut(duration: 0.25), reset) } else { reset() }
        settledZoom = 1
        settledPan = .zero
    }

    // MARK: - Changing a page

    private func open(_ edit: BookEdit) {
        switch edit {
        case .night(let day):
            OrientationLock.portrait()
            night = Night(day: day)
        case .moment(let id):
            guard let found = store.moment(id) else { return }
            OrientationLock.portrait()
            moment = found
        }
    }
}
