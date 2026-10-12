import SwiftUI

/// The next trip, sketched ahead: its name, its dates, its money and where it
/// goes. It waits on the shelf as a dashed spine until the trip in front of it
/// is shelved, and then the shelf offers to start it.
///
/// The store in here is **keyless** (`TripStore.makePlan` / `openPlan`), the
/// shelf reader's arrangement: nothing it does can reach the live trip's file,
/// the widget, or a prune. It saves itself to the library as the plan on every
/// change, and it never syncs — the other phone meets this trip when it goes
/// live and the invite step pairs them.
struct PlanTripView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var plan: TripStore

    /// Takes a store `makePlan()` or `openPlan()` built. `@StateObject` holds
    /// on to the first one it is handed, so a redraw of the shelf can't swap
    /// the store out from under somebody typing.
    init(plan: TripStore) {
        _plan = StateObject(wrappedValue: plan)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "The next trip", trailing: "Done") { dismiss() }
            TripSetupView(mode: .plan, onRemovePlan: {
                plan.library.clearPlan()
                dismiss()
            })
        }
        .background(Palette.bg)
        .environmentObject(plan)
        // After the change, not as it is announced: `objectWillChange` fires
        // before the value moves, so the save waits a turn of the run loop.
        .onReceive(plan.objectWillChange) { _ in
            Task { @MainActor in save() }
        }
        .onDisappear {
            // Opened and closed with nothing in it: not a plan, and a dashed
            // spine reading "this trip" would be a book nobody sketched.
            if plan.tripName.trimmingCharacters(in: .whitespaces).isEmpty, plan.legs.isEmpty {
                plan.library.clearPlan()
            } else {
                save()
            }
        }
    }

    /// Only while the plan still exists. "Forget this plan" clears it and
    /// then dismisses, and the save on the way out would otherwise write it
    /// straight back.
    private func save() {
        guard plan.library.plan != nil else { return }
        plan.savePlan()
    }
}
