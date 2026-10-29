import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: TripStore
    /// Where a tapped invitation link lands. Observed here rather than deeper
    /// in the app because joining changes which trip this phone is, so it can
    /// arrive over onboarding, over the tabs, or over home mode — there is no
    /// screen it belongs *under*.
    @ObservedObject private var inbox = InvitationInbox.shared
    /// "Mark a moment" from Siri, Spotlight or a control. Read here rather
    /// than in `MainTabs` so the one place that decides whether it can be
    /// acted on also *drops* it when it can't — left in the inbox, a tap made
    /// during onboarding would pop the composer the moment onboarding ended.
    @ObservedObject private var quickActions = QuickActionInbox.shared
    /// A quick action this phone can act on, handed to the tabs to present.
    @State private var outside: QuickAction?

    var body: some View {
        Group {
            #if DEBUG
            if DebugScreen.requested == "tonightlink" {
                // The widget's link, end to end, without a widget: the URL
                // goes through the same `onOpenURL` a tap on the Home Screen
                // does, so the parsing is on the route too.
                openTrip
                    .onAppear {
                        DebugScreen.applyDay(to: store)
                        DebugScreen.seedTripIfAsked(into: store)
                        store.hasOpened = true
                        if let action = QuickAction(url: QuickAction.tonightURL) {
                            QuickActionInbox.shared.pending = action
                        }
                    }
            } else if DebugScreen.requested == "markmoment" {
                // The intent's own route, end to end, without Siri: a finished
                // onboarding and a request waiting in the inbox, read by the
                // same `readQuickAction()` a real launch goes through.
                openTrip
                    .onAppear {
                        DebugScreen.applyDay(to: store)
                        DebugScreen.seedTripIfAsked(into: store)
                        store.hasOpened = true
                        QuickActionInbox.shared.pending = .markMoment
                    }
            } else if let id = DebugScreen.requested {
                DebugScreenHost(id: id)
            } else {
                openTrip
            }
            #else
            openTrip
            #endif
        }
        .gentleAnimation(.easeInOut(duration: 0.35), value: store.hasOpened)
        // `onReceive` rather than `onChange`: `CKShare.Metadata` is not
        // `Equatable`, and the launch case has already published before this
        // view exists — so the value has to be collected on arrival *and* on
        // appearance, and collecting twice is free because `take()` empties it.
        .onReceive(inbox.$arrived) { _ in readInvitation() }
        .task { readInvitation() }
        .onReceive(quickActions.$pending) { _ in readQuickAction() }
        .task { readQuickAction() }
        // The widget's tap. Into the same inbox as Siri's, so a cold launch
        // and a warm one are read by the same code.
        .onOpenURL { url in
            guard let action = QuickAction(url: url) else { return }
            quickActions.pending = action
        }
        .sheet(item: $store.pendingInvitation) { invitation in
            JoinTripView(invitation: invitation)
                .environmentObject(store)
        }
    }

    /// Take whatever the delegate left, and let the store decide whether it is
    /// a question worth asking. The reading is split from the answering so the
    /// metadata never has to sit around waiting for a view to exist.
    private func readInvitation() {
        guard let metadata = inbox.take() else { return }
        store.offerInvitation(store.sync.hold(metadata))
    }

    /// Only a traveller on a live trip they have finished setting up keeps a
    /// moment. Everyone else is simply brought to the app: the observer's
    /// phone holds no moments, and a screen explaining why would be a
    /// reference to a channel that isn't theirs. `addMoment` guards the same
    /// three things, so this is the courtesy and that is the guarantee.
    private func readQuickAction() {
        guard let action = quickActions.take() else { return }
        switch action {
        case .markMoment:
            guard store.hasOpened, !store.isObserver, store.isLive else { return }
            outside = .markMoment
        case .writeTonight:
            // A widget entry can be tapped on a phone with no tonight to
            // write: before departure, after the trip, with pages switched
            // off. Then the tap has done its job by opening the app.
            guard store.hasOpened, !store.isObserver, store.isLive,
                  store.phase == .during, store.features.nightlyPage,
                  store.canWritePage(forDay: store.dayNumber) else { return }
            outside = .writeTonight
        }
    }

    /// The same build serves both sides. Which one it is depends on who said
    /// they were holding the phone, and it changes the whole app rather than
    /// hiding a few rows.
    @ViewBuilder
    private var openTrip: some View {
        if !store.hasOpened {
            ArrivalFlow()
                .transition(.opacity)
        } else if !store.isLive {
            // Between trips. The one that was open is on the shelf, and the
            // shelf is the whole app until the next one is started — the tabs
            // of a trip that has finished would be a trip drawn as if it were
            // still running, which is what they were.
            NavigationStack { ShelfView() }
                .transition(.opacity)
        } else if store.isObserver {
            HomeTabs()
        } else {
            // On the tabs rather than on the root, which already presents the
            // invitation: one sheet modifier per view is the arrangement that
            // is certain to present.
            MainTabs(outside: $outside)
        }
    }
}

// MARK: - Tabs

enum Tab: String, CaseIterable, Identifiable {
    case today, trail, money, book, papers
    var id: String { rawValue }
    var title: String { rawValue }
}

struct MainTabs: View {
    @EnvironmentObject private var store: TripStore
    var initialTab: Tab = .today
    /// Siri's moment or the widget's page, already vetted by `RootView`. One
    /// `sheet(item:)` for both: two sheet modifiers on one view is the
    /// arrangement where the later one silently never presents.
    @Binding var outside: QuickAction?

    init(initialTab: Tab = .today, outside: Binding<QuickAction?> = .constant(nil)) {
        self.initialTab = initialTab
        _outside = outside
    }
    @State private var selection: Tab = .today
    @State private var showingSeparated = false
    @State private var showingEnding = false
    /// Today's "drop the pin?", on its way to the trail's confirmation.
    @State private var arrivalAsked: Stamp?

    /// A feature that's off is off everywhere — no empty tab, no greyed-out
    /// button, no reminder that it exists.
    private var tabs: [Tab] {
        Tab.allCases.filter { tab in
            switch tab {
            case .money: store.features.sharedLedger
            case .book: store.features.nightlyPage || store.features.printedBooks
            case .trail: store.features.stamps
            default: true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch selection {
                case .today: TodayView()
                case .trail: TrailView()
                case .money: MoneyView()
                case .book: BookView()
                case .papers: PapersView(showingSeparated: $showingSeparated)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ClassicalTabBar(selection: $selection, tabs: tabs)
        }
        .environment(\.arrivalRequest, ArrivalRequest(
            asked: arrivalAsked,
            ask: { stamp in
                guard tabs.contains(.trail) else { return }
                arrivalAsked = stamp
                selection = .trail
            },
            answered: { arrivalAsked = nil }))
        .overlay(alignment: .top) { SyncNotices() }
        .background(Palette.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showingSeparated) {
            SeparatedView()
        }
        .fullScreenCover(isPresented: $showingEnding) {
            TripEndingView()
        }
        .sheet(item: $outside) { action in
            switch action {
            case .markMoment: MomentComposerView().environmentObject(store)
            case .writeTonight: TonightEntryView().environmentObject(store)
            }
        }
        // Tonight's page opens over the Book tab, so closing it lands where
        // the page now is.
        .onChange(of: outside) { showBookIfWriting() }
        .onAppear {
            selection = tabs.contains(initialTab) ? initialTab : (tabs.first ?? .today)
            showBookIfWriting()
            if store.isSeparated { showingSeparated = true }
            // I7 · day 61. Shown once, and only because the trip actually got
            // there — never as a preview of an ending that hasn't happened.
            if store.isFinalDay { showingEnding = true }
        }
    }

    private func showBookIfWriting() {
        if outside == .writeTonight, tabs.contains(.book) { selection = .book }
    }
}

/// J1 · home mode. Three destinations, because there are only three things the
/// observer is ever shown.
struct HomeTabs: View {
    @EnvironmentObject private var store: TripStore
    @State private var selection: Tab = .today

    /// The trail is the observer's window onto where the travellers are, and it
    /// goes when the stamps do — the same rule `MainTabs` applies, so a trip
    /// with stamps switched off doesn't hand this side an empty tab.
    private var tabs: [Tab] {
        [.today, .book, .trail].filter { $0 != .trail || store.features.stamps }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch selection {
                case .book: LetterBoardView()
                // The observer reads the trail; they do not write it. The
                // guarantee is in `TripStore` — `arrive` refuses an observer
                // outright — and this is what stops the app *offering* the tap.
                //
                // On this tab only: the other two are the letters, which are
                // what this phone is for and are not part of the trip the flag
                // speaks about.
                case .trail: TrailView().environment(\.isReadOnly, true)
                default: HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ClassicalTabBar(selection: $selection, tabs: tabs,
                            labels: [.today: "home", .book: "letters", .trail: "their trail"])
        }
        // The observer's phone syncs like any other, so it can be told the
        // itinerary moved.
        .overlay(alignment: .top) { SyncNotices() }
        .background(Palette.bg.ignoresSafeArea())
        .onAppear {
            if !tabs.contains(selection) { selection = tabs.first ?? .today }
        }
    }
}

/// A dot and a word per destination.
struct ClassicalTabBar: View {
    @Binding var selection: Tab
    var tabs: [Tab] = Tab.allCases
    var labels: [Tab: String] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    guard selection != tab else { return }
                    selection = tab
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    VStack(spacing: 7) {
                        Circle()
                            .fill(selection == tab ? Palette.accent : Palette.n400)
                            .frame(width: 5, height: 5)
                        // Five labels share one bar, so this one grows less
                        // than body text does — enough to stay legible, not
                        // enough to run into its neighbours.
                        Mono(labels[tab] ?? tab.title, size: 9.5, trackingRatio: 0.06,
                             color: selection == tab ? Palette.a700 : Palette.n700,
                             growthCap: 1.35)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .frame(minHeight: 50, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((labels[tab] ?? tab.title).capitalized)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(Palette.bg)
        .overlay(alignment: .top) { Rule() }
    }
}


/// What the last merge decided, said once and then dismissed. A meeting point
/// replaced in silence is how two people end up in different parts of a city.
struct SyncNotices: View {
    @EnvironmentObject private var store: TripStore

    var body: some View {
        VStack(spacing: Space.s2) {
            ForEach(store.sync.notices) { notice in
                Button {
                    store.sync.dismiss(notice)
                } label: {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6).padding(.top, 6)
                        Text(notice.text)
                            .font(Typeface.body(12.5))
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Mono("ok", size: 9.5, trackingRatio: 0.1, color: Palette.a700)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.a100))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.accent, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Space.gutter)
        .gentleAnimation(.easeInOut(duration: 0.25), value: store.sync.notices)
    }
}
