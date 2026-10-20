import SwiftUI

/// The trail drawing itself, day by day.
///
/// Drawn the way the book draws it — `BookTrail`, hairlines on paper — so the
/// trip has one picture of itself: the ending screen, the shelf, the openers
/// and the cover are the same drawing. It used to be an Apple map here and
/// hairlines in the book, two pictures of one route.
///
/// Fitted once to the finished trail, so the frame never moves: the whole
/// route is there from the first frame, faint, and darkens as each place is
/// stood in, the way an opener draws its own country over the rest. About twelve
/// seconds whatever the trip's length — a weekend and two months take the same
/// time to watch, because what is being watched is the shape, not the days.
///
/// With Reduce Motion it does not play itself: it opens on the last frame, with
/// the scrubber, and anybody can drag back through it at their own pace.
struct TrailReplayView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Inline on the last-day screen; full height from the shelf.
    var height: CGFloat? = nil
    /// Where to stop and hold, for a debug route that has to photograph a
    /// frame without racing the timer.
    var holdAtDay: Int? = nil
    /// Off on the last-day screen, whose figures already say "Kilometres" —
    /// the same number twice on one screen, a few centimetres apart.
    var showsKilometres = true

    @State private var day = 0
    @State private var playing = false
    @State private var player: Task<Void, Never>?

    private var replay: TrailReplay { store.trailReplay }

    var body: some View {
        let replay = self.replay
        let frame = replay.frame(atDay: day)
        VStack(alignment: .leading, spacing: 0) {
            if replay.isEmpty {
                Aside(text: "Nothing on this trail had a position to replay.", size: 12.5)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Mono(dayLine(frame), size: 10.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: toggle) {
                        Mono(verb(replay), size: 10.5, trackingRatio: 0.1, color: Palette.a700)
                            .padding(.leading, Space.s4)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if showsKilometres {
                    Display(text: "\(Formatting.decimal(Double(frame.kilometres), places: 0)) km", size: 38)
                        .monospacedDigit()
                        .padding(.bottom, Space.s2)
                }

                TrailPicture(map: BookMap.fit(replay.last.stamps,
                                              highlighting: Set(frame.stamps.map(\.id)),
                                              moments: frame.moments, allowsSinglePlace: true),
                             height: height ?? 360, faintRest: true)
                    .accessibilityLabel("The trail on \(dayLine(frame)), \(Formatting.spelledCount(frame.stamps.count, "stamp", spellingUpTo: 0)), \(Formatting.spelledCount(frame.kilometres, "kilometre", spellingUpTo: 0))")

                Slider(value: Binding(get: { Double(day) },
                                      set: { stop(); day = Int($0.rounded()) }),
                       in: Double(replay.days.lowerBound)...Double(max(replay.days.upperBound, replay.days.lowerBound + 1)),
                       step: 1)
                    .tint(Palette.accent)
                    .padding(.top, Space.s2)
                    .accessibilityLabel("Day")
                    .accessibilityValue(dayLine(frame))
            }
        }
        .onAppear(perform: begin)
        .onDisappear(perform: stop)
    }

    private func dayLine(_ frame: TrailReplay.Frame) -> String {
        if frame.day < 1 { return "Before you left" }
        let city = store.city(forDay: frame.day)
        return city == TripStore.unknownPlace ? "Day \(frame.day)" : "Day \(frame.day) · \(city)"
    }

    private func verb(_ replay: TrailReplay) -> String {
        if playing { return "pause" }
        return day >= replay.days.upperBound ? "again" : "play"
    }

    private func begin() {
        let replay = self.replay
        if let holdAtDay {
            day = holdAtDay
        } else if reduceMotion {
            day = replay.days.upperBound
        } else {
            day = replay.days.lowerBound
            play()
        }
    }

    private func toggle() {
        if playing { stop(); return }
        if day >= replay.days.upperBound { day = replay.days.lowerBound }
        play()
    }

    private func play() {
        let replay = self.replay
        guard !replay.isEmpty else { return }
        let steps = max(replay.days.count, 1)
        let perDay = max(0.08, 12.0 / Double(steps))
        playing = true
        player?.cancel()
        // `@MainActor`, explicitly: a bare `Task` from a view's method runs on
        // the global executor and would move `@State` from a background thread.
        player = Task { @MainActor in
            while day < replay.days.upperBound {
                try? await Task.sleep(for: .seconds(perDay))
                guard !Task.isCancelled else { return }
                day += 1
            }
            playing = false
        }
    }

    private func stop() {
        player?.cancel()
        player = nil
        playing = false
    }
}
