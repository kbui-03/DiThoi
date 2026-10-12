import SwiftUI

/// K7 · finishing a trip. Shelve it or throw it away, and then the next one.
///
/// This used to be two screens in two places. "Close this trip" was on the
/// shelf, promising "Deletes nothing" over a close that deletes the scans.
/// "Empty this trip" was at the bottom of settings, and it shelved nothing
/// and never mentioned the shelf existed. They are the same question, so they
/// are one sheet with two answers, reached from the shelf, from settings, from
/// the last day and from Today once the trip is over.
///
/// Neither answer starts the next trip on the spot. Shelving leaves the phone
/// *between trips*, which `RootView` draws as the shelf in place of the tabs,
/// for as long as somebody wants to stay there. Throwing away goes straight
/// to `ArrivalFlow`, because there is nothing left on the phone to look at.
struct FinishTripView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    private enum Answer { case shelve, discard }
    @State private var confirming: Answer?
    /// What was confirmed, done once the sheet has gone. Either answer swaps
    /// the view that presented this sheet for another one, and pulling the
    /// presenter out from under a sheet that is still up is how a
    /// presentation goes wrong without an error. So it waits for
    /// `onDisappear`.
    @State private var decided: Answer?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Finish this trip", trailing: "Not now") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono(sinceLine, size: 10.5, trackingRatio: 0.16, color: Palette.a700)

                    // A question, so the fallback name ("this trip") reads as
                    // a sentence too. Alone, it was a lowercase fragment.
                    Display(text: "Finish \(store.displayName)?", size: 40, tracking: -0.025)
                        .padding(.top, 12)

                    Rectangle().fill(Palette.accent)
                        .frame(width: 52, height: 1)
                        .padding(.vertical, Space.s4)

                    Text(preamble)
                        .font(Typeface.body(13.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(6)
                        .padding(.bottom, Space.s4)
                        .fixedSize(horizontal: false, vertical: true)

                    Panel(border: Palette.accent) {
                        Mono("Put it on the shelf", size: 9.5, color: Palette.a700)
                            .padding(.bottom, 6)
                        lines(shelveLines)
                    }
                    .padding(.bottom, Space.s2)

                    Panel {
                        Mono("Or throw it away", size: 9.5).padding(.bottom, 6)
                        lines(["Nothing goes on the shelf",
                               "The ledger, the letters, the trail and the book's pages go, for good"])
                    }

                    Text(carriesLine)
                        .font(Typeface.body(12.5))
                        .foregroundStyle(Palette.n700)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.s4)

                    if !store.isObserver {
                        Mono("\(store.otherName) finishes theirs separately.",
                             size: 9.5, trackingRatio: 0.1)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Space.s4)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, Space.s6)
            }

            VStack(spacing: Space.s2) {
                OutlineButton(title: "Put it on the shelf", minHeight: 48, size: 15) {
                    confirming = .shelve
                }
                OutlineButton(title: "Throw it away", minHeight: 44, size: 14,
                              border: Palette.divider, foreground: Palette.text) {
                    confirming = .discard
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .confirmationDialog("Put \(store.displayName) on the shelf?",
                            isPresented: isConfirming(.shelve), titleVisibility: .visible) {
            Button("Put it on the shelf") { decide(.shelve) }
            Button("Leave it open", role: .cancel) {}
        } message: {
            Text(shelvingMessage)
        }
        .confirmationDialog("Throw \(store.displayName) away?",
                            isPresented: isConfirming(.discard), titleVisibility: .visible) {
            Button("Throw it away", role: .destructive) { decide(.discard) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It won't go on the shelf. The ledger, the letters, the trail and the book's pages are deleted, and nothing can bring them back.")
        }
        .onDisappear {
            switch decided {
            case .shelve: withGentleAnimation(.easeInOut(duration: 0.3)) { store.closeTrip() }
            case .discard: withGentleAnimation(.easeInOut(duration: 0.3)) { store.beginNextTrip(discarding: true) }
            case nil: break
            }
        }
    }

    private func isConfirming(_ answer: Answer) -> Binding<Bool> {
        Binding(get: { confirming == answer },
                set: { if !$0, confirming == answer { confirming = nil } })
    }

    private func decide(_ answer: Answer) {
        decided = answer
        dismiss()
    }

    /// The papers line is computed, and only appears when there are papers.
    ///
    /// Everything else here is true of every trip. This one is true of the
    /// trip in front of you or not at all, and a fixed sentence about deleting
    /// passport scans on a trip that has none is the kind of promise that gets
    /// ignored on the trip where it matters.
    private var shelveLines: [String] {
        var lines = ["Read-only, and every screen of it opens again",
                     "Stops syncing, and the nightly page stops for good"]
        if let lost = store.papersLostOnClose {
            lines.append(papersLine(lost))
        }
        return lines
    }

    private func papersLine(_ lost: TripStore.PapersLoss) -> String {
        let scans = lost.scans == 0
            ? ""
            : " and \(lost.scans) scan\(lost.scans == 1 ? "" : "s")"
        return "Empties \(lost.documents) document\(lost.documents == 1 ? "" : "s")\(scans) — passport numbers don't go on the shelf"
    }

    /// Asked of the store, so this and the deletion cannot drift apart — the
    /// mistake `adoptionDiscardsLetters(becoming:)` exists to prevent.
    private var shelvingMessage: String {
        let base = "It goes on the shelf, read-only, and every screen of it opens again."
        guard let lost = store.papersLostOnClose else { return base }
        let scans = lost.scans == 0
            ? ""
            : ", and \(lost.scans) scan\(lost.scans == 1 ? "" : "s") come off the phone"
        return "\(base) The numbers on \(lost.documents) document\(lost.documents == 1 ? "" : "s") are cleared\(scans). That part can't be undone."
    }

    /// What the next trip starts with, whichever answer is picked. Computed
    /// from what there is, so a trip with no cards doesn't promise any.
    private var carriesLine: String {
        guard !store.isObserver else {
            return "Either way, the next one starts with your names already filled in."
        }
        var carried = ["your names", "the money"]
        if !store.orderedShowCards.isEmpty { carried.append("the show-this cards") }
        let list = carried.dropLast().joined(separator: ", ") + " and " + carried.last!
        // A plan is what comes next either way, so it is named: throwing this
        // trip away starts it straight off, and shelving offers it.
        if let plan = store.library.plan {
            return "Either way, \(plan.summary.displayName) is next, with \(list) already in."
        }
        return "Either way, the next trip starts with \(list) already filled in."
    }

    private var sinceLine: String {
        switch store.phase {
        case .after(let days):
            return days == 0 ? "You landed today" : "\(days) day\(days == 1 ? "" : "s") after you landed"
        case .during: return "The trip is still running"
        case .before: return "You haven't left yet"
        }
    }

    private var preamble: String {
        let base = "It can stay open as long as you like"
        if store.phase == .during {
            return "\(base). Finishing it now stops the ledger, the pins and the nightly page."
        }
        return "\(base)."
    }

    private func lines(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(Typeface.body(12.5))
                    .foregroundStyle(Palette.n700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
