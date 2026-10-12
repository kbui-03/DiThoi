import SwiftUI

/// D3 · Settle up. Three currencies netted to one number, and — now that there
/// are two phones — genuinely no way to clear the tab on your own.
struct SettleUpView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var method: Method = .cash

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

                    Aside(text: "Across three currencies, netted down to one number.", size: 12.5)
                        .padding(.bottom, Space.s3)

                    Rule()

                    ForEach(store.tripCurrencies) { currency in
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

                    Aside(text: "Both phones agree before it clears — no one can settle a tab alone.", size: 12)
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
            Text(proposal.awaiting == store.role
                 ? "\(store.name(for: proposal.proposedBy)) proposed this at \(proposal.proposedAt.text("HH:mm")). Agreeing clears the tab on both phones."
                 : "Proposed at \(proposal.proposedAt.text("HH:mm")). Nothing clears until \(store.name(for: proposal.awaiting)) agrees on the other phone.")
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

            if let pending {
                if pending.awaiting == store.role {
                    OutlineButton(title: "Agree · clear it") {
                        store.confirmSettlement(pending.id)
                        Task { await store.syncNow() }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                } else {
                    OutlineButton(title: "Nudge \(store.name(for: pending.awaiting))",
                                  border: Palette.divider, foreground: Palette.n700) {
                        Task { await store.syncNow() }
                    }
                }
            } else {
                OutlineButton(title: settleTitle) { propose() }
                    .disabled(store.balanceAmountHome < 0.01)
                    .opacity(store.balanceAmountHome < 0.01 ? 0.4 : 1)
            }
        }
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
        return count == 0 ? "nothing yet" : "\(count) shared items"
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
