import SwiftUI

/// D3 · Settle up. Every currency netted to one number, and — where there are
/// two phones — genuinely no way to clear the tab on your own.
///
/// Where there aren't (a build with no sync, which is every build until the
/// paid membership), "the other phone agrees" is a promise nothing can keep,
/// so the tab is cleared here with both of them in the room, behind a
/// question that says so.
struct SettleUpView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var method: Method = .cash
    @State private var askingTogether = false

    private enum Method: String, CaseIterable, Identifiable {
        case cash, roll, forget
        var id: String { rawValue }

        var title: String {
            switch self {
            case .cash: "Cash tonight"
            case .roll: "Roll it into the next country"
            case .forget: "Just forget it"
            }
        }
    }

    private var pending: SettlementProposal? { store.pendingSettlement }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Settle up", trailing: "Close") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Mono("Since \(store.start.shortDayMonth)", size: 10.5)

                    Display(text: headline, size: 36)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // Counted — it said "three currencies" on every trip.
                    Aside(text: store.settleCurrencyLine, size: 12.5)
                        .padding(.bottom, Space.s3)

                    Rule()

                    // The itinerary's currencies and any other a shared line
                    // was paid in, so the rows add up to the net beneath them.
                    ForEach(store.settleCurrencies) { currency in
                        DetailRow(title: currencyName(currency),
                                  subtitle: itemsCaption(currency)) {
                            Text(store.sharedItemCount(currency: currency) == 0
                                 ? "—"
                                 : currency.format(abs(store.balance(in: currency))))
                                .font(Typeface.mono(13.5))
                                .monospacedDigit()
                                .foregroundStyle(store.sharedItemCount(currency: currency) == 0 ? Palette.n500 : Palette.text)
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Net, in \(store.homeCurrency.name.lowercased())s")
                            .font(Typeface.heading(18, .semibold))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(store.homeText(store.balanceAmountHome))
                            .font(Typeface.mono(16))
                            .monospacedDigit()
                            .foregroundStyle(Palette.a700)
                    }
                    .padding(.vertical, 11)

                    Rule(color: Palette.text)

                    RateStamp(size: 11.5, prefix: "netted at today's rates")
                        .padding(.top, Space.s2)

                    if let pending {
                        proposalBlock(pending)
                    } else {
                        methodChooser
                    }

                    Aside(text: store.settlesOnOnePhone
                          ? "This build can't reach \(store.otherName)'s phone, so you agree here, together."
                          : "Both phones agree before it clears — no one can settle a tab alone.",
                          size: 12)
                        .padding(.top, Space.s3)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s4)
            }

            footer
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.gutter)
        }
        .background(Palette.bg)
        .confirmationDialog("Is \(store.otherName) with you?", isPresented: $askingTogether,
                            titleVisibility: .visible) {
            Button("Yes, clear it") { settleTogether() }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("\(togetherSummary) This clears the tab and can't be taken back.")
        }
    }

    // MARK: - Choosing how

    @ViewBuilder
    private var methodChooser: some View {
        Mono("How", size: 10)
            .padding(.top, Space.s4)
            .padding(.bottom, 8)

        ForEach(Method.allCases) { option in
            Button {
                method = option
            } label: {
                Panel(border: method == option ? Palette.accent : Palette.divider,
                      padding: EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)) {
                    Text(option.title)
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(method == option ? Palette.a800 : Palette.text)
                    Aside(text: detail(for: option), size: 12)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Space.s2)
        }
    }

    // MARK: - Waiting on the other phone

    @ViewBuilder
    private func proposalBlock(_ proposal: SettlementProposal) -> some View {
        Panel(border: Palette.accent, fill: Palette.a100) {
            Mono(proposal.awaiting == store.role ? "Waiting on you" : "Waiting on \(store.name(for: proposal.awaiting))",
                 size: 9.5, color: Palette.a700)
            Text("\(store.name(for: proposal.debtor)) pays \(proposal.paidIn.format(proposal.amountPaid))")
                .font(Typeface.heading(19, .semibold))
                .foregroundStyle(Palette.text)
                .padding(.top, 5)
            Text(proposalDetail(proposal))
                .font(Typeface.body(12.5))
                .foregroundStyle(Palette.n700)
                .lineSpacing(4)
                .padding(.top, 5)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                store.cancelSettlement(proposal.id)
            } label: {
                Mono("Call it off", size: 10, trackingRatio: 0.1, color: Palette.n700)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: Space.s2) {
            if store.sync.isSyncing {
                Mono("syncing…", size: 10, trackingRatio: 0.1, color: Palette.a700)
            }

            if store.settlesOnOnePhone, pending != nil || method != .roll {
                OutlineButton(title: pending == nil ? "We're both here · clear it" : "We're both here · agree") {
                    askingTogether = true
                }
                .disabled(pending == nil && store.balanceAmountHome < 0.01)
                .opacity(pending == nil && store.balanceAmountHome < 0.01 ? 0.4 : 1)
            } else if let pending {
                if pending.awaiting == store.role {
                    OutlineButton(title: "Agree · clear it") {
                        store.confirmSettlement(pending.id)
                        Task { await store.syncNow() }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                } else {
                    // Named for what it does. It was "Nudge", and sent the
                    // other phone nothing: all it has ever done is look again.
                    OutlineButton(title: "Check for \(store.name(for: pending.awaiting))'s answer",
                                  border: Palette.divider, foreground: Palette.n700) {
                        Task { await store.syncNow() }
                    }
                    if let checked = store.sync.lastSyncedAt, !store.sync.isSyncing {
                        Aside(text: "last checked \(checked.text("HH:mm")) · nothing yet", size: 11.5)
                    }
                }
            } else {
                OutlineButton(title: settleTitle) { propose() }
                    .disabled(store.balanceAmountHome < 0.01)
                    .opacity(store.balanceAmountHome < 0.01 ? 0.4 : 1)
            }
        }
    }

    /// One step, both of them here: a new settlement proposed and agreed at
    /// once, or the pending one agreed on the spot.
    private func settleTogether() {
        if let pending {
            store.confirmSettlement(pending.id, inPerson: true)
        } else {
            switch method {
            case .roll: return
            case .cash: store.settleTogether(note: "Settled in cash", in: store.localCurrency)
            case .forget: store.settleTogether(note: "Written off")
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    /// What the question under "Is … with you?" says is about to happen.
    private var togetherSummary: String {
        let debtor = store.name(for: store.debtor)
        let creditor = store.name(for: store.creditor)
        if let pending {
            return "\(store.name(for: pending.debtor)) pays \(store.name(for: pending.debtor.other)) \(pending.paidIn.format(pending.amountPaid))."
        }
        switch method {
        case .cash:
            let local = store.localCurrency
            return "\(debtor) pays \(creditor) \(local.format(store.fromHome(store.balanceAmountHome, to: local).rounded())) in cash."
        case .forget, .roll:
            return "\(store.homeText(store.balanceAmountHome)) is written off."
        }
    }

    private func proposalDetail(_ proposal: SettlementProposal) -> String {
        let at = proposal.proposedAt.text("HH:mm")
        if store.settlesOnOnePhone {
            return "Proposed at \(at). With \(store.name(for: proposal.awaiting)) beside you, agree to it here."
        }
        return proposal.awaiting == store.role
            ? "\(store.name(for: proposal.proposedBy)) proposed this at \(at). Agreeing clears the tab on both phones."
            : "Proposed at \(at). Nothing clears until \(store.name(for: proposal.awaiting)) agrees on the other phone."
    }

    private var settleTitle: String {
        guard store.balanceAmountHome >= 0.01 else { return "Nothing to settle" }
        if method == .roll { return "Leave it running" }
        // Whoever isn't holding this phone is the one who has to agree.
        return "Ask \(store.otherName) to confirm"
    }

    private func propose() {
        switch method {
        case .roll:
            dismiss()
        case .cash:
            store.proposeSettlement(note: "Settled in cash", in: store.localCurrency)
            Task { await store.syncNow() }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .forget:
            store.proposeSettlement(note: "Written off")
            Task { await store.syncNow() }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    // MARK: - Copy

    private var headline: String {
        guard store.balanceAmountHome >= 0.01 else { return "Nothing\nbetween you" }
        return "\(store.name(for: store.debtor)) owes\n\(store.name(for: store.creditor)) \(store.homeText(store.balanceAmountHome))"
    }

    private func currencyName(_ currency: Currency) -> String { currency.name }

    private func itemsCaption(_ currency: Currency) -> String {
        let count = store.sharedItemCount(currency: currency)
        return count == 0 ? "nothing yet" : "\(count) shared \(count == 1 ? "item" : "items")"
    }

    private func detail(for option: Method) -> String {
        switch option {
        case .cash:
            let local = store.localCurrency
            return "\(local.format(store.fromHome(store.balanceAmountHome, to: local).rounded())) · in cash, tonight"
        case .roll:
            return "keep the tab running, settle at the airport"
        case .forget:
            return "writes it off and clears the ledger to zero"
        }
    }
}
