import SwiftUI

/// Ten seconds to take a deleted moment back.
///
/// The ledger's undo, one collection over, with one difference underneath: an
/// expense is a tombstone, so its undo is `restore(id)`; a moment is removed
/// outright, so the banner holds the value itself and `restoreMoment` puts
/// that back. The photograph survives the window because `deleteMoment` leaves
/// the file to the prune, and the prune runs on the next wake — which is why
/// the offer is withdrawn the moment the app leaves the foreground.
struct MomentUndo: ViewModifier {
    @Binding var deleted: Moment?
    @EnvironmentObject private var store: TripStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let deleted {
                    UndoBanner(text: "Deleted · \(deleted.note.isEmpty ? "a photograph" : deleted.note)") {
                        store.restoreMoment(deleted)
                        withdraw()
                    }
                }
            }
            .gentleAnimation(.easeInOut(duration: 0.2), value: deleted?.id)
            .onChange(of: deleted?.id) { _, id in
                timer?.cancel()
                guard id != nil else { return }
                // `@MainActor`, explicitly: a bare `Task` from a view's method
                // runs on the global executor and would clear `@State` from a
                // background thread, with nothing in Swift 5 mode to say so.
                timer = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    deleted = nil
                }
            }
            // Leaving the screen, or the app. The second is load-bearing: the
            // wake that follows prunes the file, and an offer that outlived it
            // would restore a moment pointing at a photograph that is gone.
            .onDisappear { withdraw() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { withdraw() }
            }
    }

    private func withdraw() {
        timer?.cancel()
        timer = nil
        deleted = nil
    }
}

/// "Kept · 14:05, Chiang Mai — undo", after a spot kept in one tap with no
/// sheet. The same ten seconds and the same banner as a delete, run the other
/// way: undo takes the spot back out.
struct SpotKept: ViewModifier {
    @Binding var kept: Moment?
    @EnvironmentObject private var store: TripStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let kept {
                    UndoBanner(text: "Kept · \(kept.capturedAt.text("HH:mm"))\(kept.place.map { ", \($0)" } ?? "")") {
                        store.deleteMoment(kept.id)
                        withdraw()
                    }
                }
            }
            .gentleAnimation(.easeInOut(duration: 0.2), value: kept?.id)
            .onChange(of: kept?.id) { _, id in
                timer?.cancel()
                guard id != nil else { return }
                timer = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    kept = nil
                }
            }
            .onDisappear { withdraw() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { withdraw() }
            }
    }

    private func withdraw() {
        timer?.cancel()
        timer = nil
        kept = nil
    }
}

extension View {
    func momentUndo(_ deleted: Binding<Moment?>) -> some View {
        modifier(MomentUndo(deleted: deleted))
    }

    func spotKept(_ kept: Binding<Moment?>) -> some View {
        modifier(SpotKept(kept: kept))
    }
}

/// Edit / Delete on a held moment row, the same two words the ledger and the
/// show-this cards use.
struct MomentRowMenu: ViewModifier {
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            if canEdit {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}
