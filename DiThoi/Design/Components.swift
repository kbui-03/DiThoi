import SwiftUI

// MARK: - Rules and labels

/// The hairline used everywhere as a section divider.
struct Rule: View {
    var color: Color = Palette.divider
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// Uppercase monospace label — the app's "small caps" voice.
///
/// Defaults to n700, not n600. The label voice renders at 9.5–10.5pt, under the
/// 18pt where WCAG relaxes, and n600 is 3.85:1 against the page — below the
/// 4.5:1 small text needs. n700 is 5.8:1. The `Palette` ramp is unchanged; this
/// only picks which rung small text stands on.
struct Mono: View {
    let text: String
    var size: CGFloat = 10
    var trackingRatio: CGFloat = 0.14
    var color: Color = Palette.n700
    var weight: Font.Weight = .regular
    /// See `TypeSpec.ceilingOverride`.
    var growthCap: CGFloat?

    private var spec: TypeSpec {
        let base = Typeface.mono(size, weight)
        return growthCap.map { base.capped(at: $0) } ?? base
    }

    var body: some View {
        Text(text.uppercased())
            .font(spec)
            .tracking(size * trackingRatio)
            .foregroundStyle(color)
    }
}

/// Screen title in the display serif.
///
/// Display type sits at a line-height below 1 — the lines nearly touch, which
/// is most of what makes it read as a masthead rather than a paragraph.
/// SwiftUI's `lineSpacing` can only add, so multi-line titles are stacked and
/// pulled together instead.
struct Display: View {
    let text: String
    var size: CGFloat = 38
    var color: Color = Palette.text
    /// In em, like CSS `letter-spacing`.
    var tracking: CGFloat = -0.02
    @Environment(\.dynamicTypeSize) private var typeSize

    private var spec: TypeSpec { Typeface.heading(size) }

    private var points: CGFloat {
        TypeScale.points(size, ceiling: spec.growthCeiling, for: typeSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: -(points * 0.17)) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(spec)
                    .tracking(points * tracking)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Italic serif aside — the prototype's recurring explanatory line.
struct Aside: View {
    let text: String
    var size: CGFloat = 12.5
    var color: Color = Palette.n700

    var body: some View {
        Text(text)
            .font(Typeface.body(size).italic())
            .foregroundStyle(color)
            .lineSpacing(size * 0.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Screen scaffolding

/// The status row. On device the system status bar already shows the time, so
/// only the right-hand context word is drawn.
///
/// Screens that pass `.syncState` get something the app can actually check —
/// how long ago the shared half of the trip last moved, or why it can't —
/// rather than a fixed word about the network.
struct ScreenContext: View {
    var tag: ScreenTag
    var color: Color = Palette.n700
    @EnvironmentObject private var store: TripStore
    @Environment(\.isReadOnly) private var isReadOnly

    var body: some View {
        if let text = tag.text(store, isReadOnly: isReadOnly) {
            HStack {
                Spacer()
                Mono(text, size: 10.5, trackingRatio: 0.1, color: color)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 4)
        }
    }
}

/// What the context row says.
///
/// A string literal is fine where the screen is saying something about the
/// flow rather than the network — "before you go" is true whatever the radio is
/// doing. `.syncState` is for the rest.
enum ScreenTag: ExpressibleByStringLiteral, Equatable {
    case hidden
    /// How long ago the shared half of the trip last moved, or why it can't.
    case syncState
    case text(String)

    init(stringLiteral value: String) { self = .text(value) }

    /// - Parameter isReadOnly: set when the shelf has reopened a closed trip.
    ///   That store has no persistence key and has never synced, so
    ///   `sync.summary` answers "not synced yet" — a true statement about a
    ///   throwaway object and a false one about the trip, which synced for two
    ///   months and then closed. The shelf prints the real "last synced" off
    ///   the frozen summary; here the honest output is nothing.
    @MainActor
    func text(_ store: TripStore, isReadOnly: Bool = false) -> String? {
        switch self {
        case .hidden: nil
        case .syncState: isReadOnly ? nil : store.sync.summary
        case .text(let value): value
        }
    }
}

extension Mono {
    init(_ text: String, size: CGFloat = 10, trackingRatio: CGFloat = 0.14,
         color: Color = Palette.n700, weight: Font.Weight = .regular, growthCap: CGFloat? = nil) {
        self.init(text: text, size: size, trackingRatio: trackingRatio,
                  color: color, weight: weight, growthCap: growthCap)
    }
}

/// Standard light screen: context row, then scrolling gutter-padded content.
struct Screen<Content: View>: View {
    var context: ScreenTag = .hidden
    var contextColor: Color = Palette.n700
    var background: Color = Palette.bg
    var gutter: CGFloat = Space.gutter
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if context != .hidden {
                ScreenContext(tag: context, color: contextColor)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, gutter)
                .padding(.top, 14)
                .padding(.bottom, Space.s6)
            }
        }
        .background(background)
    }
}

// MARK: - Buttons

/// Outlined action button — accent border, transparent fill.
struct OutlineButton: View {
    let title: String
    var minHeight: CGFloat = 48
    var size: CGFloat = 15
    var border: Color = Palette.accent
    var foreground: Color = Palette.accent
    var fillsWidth: Bool = true
    var horizontalPadding: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.heading(size, .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, fillsWidth ? 0 : horizontalPadding)
                .frame(minHeight: minHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableOutline(border: border))
    }
}

private struct PressableOutline: ButtonStyle {
    let border: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(configuration.isPressed ? Palette.a100 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

/// Bordered container for callout cards.
struct Panel<Content: View>: View {
    var border: Color = Palette.divider
    var fill: Color = .clear
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(border, lineWidth: 1))
    }
}

/// Small pill — the "sealed / shared / private" markers.
struct Tag: View {
    let text: String
    var active: Bool = false
    var body: some View {
        Mono(text, size: 10, trackingRatio: 0.08, color: active ? Palette.a700 : Palette.n700)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(active ? Palette.accent : Palette.divider, lineWidth: 1)
            )
    }
}

/// A number somebody can actually dial, with what it reaches above it.
///
/// Drawn twice on two grounds: the Separated screen is dark and the country
/// card in Papers is not, so the three colours are parameters and the defaults
/// are the light ones. It was private to `SeparatedView` and hard-coded to the
/// dark palette, which would have meant a second copy the first time anything
/// else needed to show a phone number.
///
/// The `tel://` fallback is `112` rather than nothing, because a tile that
/// silently does nothing when tapped is worse than one that dials the number
/// most of Europe answers.
struct CallNumber: Identifiable {
    let label: String
    let number: String
    var id: String { number }
}

/// The row of them, which is the part that has to survive Dynamic Type.
///
/// Three tiles side by side is fine at every normal size and breaks badly at
/// the accessibility ones: Vietnam's "police · medical · fire" rendered as
/// "POLIC / E" and "MEDIC / AL" over three tiles of three different heights —
/// the same failure as "SONGKRA / N", on the screen where a misread number
/// matters most. Above the accessibility threshold they stack, each one full
/// width, and nothing wraps.
struct CallTileRow: View {
    let numbers: [CallNumber]
    var labelColor: Color = Palette.n700
    var numberColor: Color = Palette.text
    var border: Color = Palette.divider

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.s2))

        layout {
            ForEach(numbers) { number in
                CallTile(label: number.label, number: number.number,
                         labelColor: labelColor, numberColor: numberColor, border: border)
            }
        }
    }
}

struct CallTile: View {
    let label: String
    let number: String
    var labelColor: Color = Palette.n700
    var numberColor: Color = Palette.text
    var border: Color = Palette.divider

    var body: some View {
        Link(destination: URL(string: "tel://\(number.replacingOccurrences(of: " ", with: ""))") ?? URL(string: "tel://112")!) {
            VStack(alignment: .leading, spacing: 3) {
                Mono(label, size: 9, trackingRatio: 0.12, color: labelColor)
                Text(number)
                    .font(Typeface.mono(13))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Call \(label)")
    }
}

/// Selectable chip used for tags, currencies and the "three taps" row.
struct Chip: View {
    let text: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Mono(text, size: 10, trackingRatio: 0.08,
                 color: selected ? Palette.a800 : Palette.n700)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(RoundedRectangle(cornerRadius: Radius.sm).fill(selected ? Palette.a100 : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(selected ? Palette.accent : Palette.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A currency choice that fits on a phone.
///
/// It was every case as a chip, which was fine at six and is a wall at forty.
/// Now the few that are likely right are chips, and the rest are one menu
/// away, by name, because nobody remembers that the Lao kip is LAK.
struct CurrencyChips: View {
    let selected: Currency?
    /// Offered as chips, in this order. Nils and repeats are dropped, and the
    /// selection is always among them.
    let suggested: [Currency?]
    let onPick: (Currency) -> Void

    private var shown: [Currency] {
        var seen: [Currency] = []
        for case let option? in suggested + [selected] where !seen.contains(option) {
            seen.append(option)
        }
        return seen
    }

    var body: some View {
        FlowRow(spacing: Space.s2) {
            ForEach(shown) { option in
                Chip(text: option.chipLabel, selected: selected == option) {
                    onPick(option)
                }
            }
            Menu {
                ForEach(Currency.byName) { option in
                    Button("\(option.name) · \(option.code)") { onPick(option) }
                }
            } label: {
                Mono("another…", size: 10, trackingRatio: 0.08, color: Palette.a700)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(Palette.divider, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Another currency")
        }
    }
}

/// Larger segmented choice — "who paid", "split".
struct SegmentTile: View {
    let text: String
    let selected: Bool
    var serif: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if serif {
                    Text(text)
                        .font(Typeface.heading(17, .semibold))
                        .foregroundStyle(selected ? Palette.a800 : Palette.text)
                } else {
                    Mono(text, size: 11, trackingRatio: 0.06,
                         color: selected ? Palette.a800 : Palette.n700)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(selected ? Palette.a100 : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(selected ? Palette.accent : Palette.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rows

/// Label on the left, monospace value on the right, hairline underneath.
struct DetailRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var titleSize: CGFloat = 16
    var showsRule: Bool = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typeface.heading(titleSize, .semibold))
                        .foregroundStyle(Palette.text)
                    if let subtitle {
                        Aside(text: subtitle, size: 11.5, color: Palette.n600)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 10)
            if showsRule { Rule() }
        }
    }
}

extension DetailRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, titleSize: CGFloat = 16, showsRule: Bool = true) {
        self.init(title: title, subtitle: subtitle, titleSize: titleSize, showsRule: showsRule) { EmptyView() }
    }
}

// MARK: - Placeholders

/// The hatched "no asset yet" panel: 45° repeating stripes inside a thick
/// surface frame.
struct HatchPanel: View {
    var height: CGFloat
    var caption: String?

    var body: some View {
        Hatching()
            .frame(height: height)
            .overlay { HatchCaption(caption) }
            .photoMount()
    }
}

/// The words on a hatched stand-in.
///
/// Pulled out of `HatchPanel` when `JournalPhoto` stopped being able to use it:
/// a page's stand-in is square and a panel's is a given height, but they are
/// the same stand-in and had started being two.
struct HatchCaption: View {
    let caption: String?

    init(_ caption: String?) { self.caption = caption }

    var body: some View {
        if let caption {
            Text(caption.uppercased())
                .font(Typeface.mono(10))
                .tracking(1)
                .foregroundStyle(Palette.n600)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
        }
    }
}

extension View {
    /// The 6pt mat, the paper behind it and the hairline round it — what makes
    /// a photograph on any of these screens read as mounted rather than pasted.
    ///
    /// One place, because `HatchPanel` and `JournalPhoto` both drew it and only
    /// one of them would have been corrected.
    func photoMount() -> some View {
        padding(6)
            .background(Palette.surface)
            .overlay(Rectangle().strokeBorder(Palette.divider, lineWidth: 1))
    }
}

struct Hatching: View {
    var period: CGFloat = 14
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.n100))
            let stride = period * 1.41421
            var x = -size.height
            while x < size.width + stride {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(Palette.n200), lineWidth: period / 2)
                x += stride
            }
        }
        .clipped()
    }
}

// MARK: - Layout helpers

extension View {
    func sectionGap(_ amount: CGFloat = Space.s3) -> some View {
        padding(.top, amount)
    }
}

/// One typed answer on an accent rule — the trip's name, a person's name.
///
/// The `prompt:` carries a resolved `Font` rather than a `TypeSpec`, because a
/// prompt doesn't go through the `font(_:)` overload that scales everything
/// else and would otherwise sit at one size while the field grew around it.
struct WrittenField: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var note: String?
    var size: CGFloat = 26
    /// What the answer is written in. Green for a phrase in the local script,
    /// which is how every screen that *shows* one already draws it — a field
    /// that types in one colour and reads back in another is two things.
    var ink: Color = Palette.text
    /// Off for anything that isn't English. `.words` is a rule about Latin
    /// script: it does nothing to Thai or Hangul and is simply wrong in
    /// Vietnamese, where it capitalises every syllable of a place name.
    var capitalisation: TextInputAutocapitalization = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono(label, size: 10).padding(.bottom, 8)

            TextField("", text: $text, prompt: Text(placeholder)
                .font(Typeface.heading(size).resolved(for: typeSize))
                // n400 was 1.80:1 on the page — a placeholder nobody could read
                // in daylight, in an app used outdoors in April in Thailand.
                .foregroundStyle(Palette.n600))
                .font(Typeface.heading(size))
                .foregroundStyle(ink)
                .textInputAutocapitalization(capitalisation)
                .autocorrectionDisabled()
                .accessibilityLabel(label)
                .padding(.bottom, 8)

            Rectangle().fill(Palette.accent).frame(height: 1)

            if let note {
                Aside(text: note, size: 11.5).padding(.top, Space.s1)
            }
        }
    }
}

/// How far through a flow this step is. One bar, two callers.
struct StepProgress: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Rectangle()
                    .fill(index <= current ? Palette.accent : Palette.n300)
                    .frame(height: 2)
            }
        }
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// A hairline with breathing room above and below, as used between blocks.
struct SectionRule: View {
    var top: CGFloat = Space.s3
    var bottom: CGFloat = Space.s3
    var body: some View {
        Rule()
            .padding(.top, top)
            .padding(.bottom, bottom)
    }
}

// MARK: - Rates

/// The disclaimer that rides along with every converted figure: how old the
/// rate behind it is. Tapping it asks for a fresh one.
struct RateStamp: View {
    @EnvironmentObject private var store: TripStore
    var size: CGFloat = 12.5
    var color: Color = Palette.n700
    var prefix: String?

    var body: some View {
        Button {
            Task { await store.rates.refresh() }
        } label: {
            HStack(spacing: 5) {
                Aside(text: [prefix, store.rates.disclaimer].compactMap { $0 }.joined(separator: " · "),
                      size: size, color: color)
                if store.rates.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exchange rates: \(store.rates.disclaimer). Tap to check for new ones.")
    }
}

// MARK: - Undo

/// The strip that says something was deleted, and offers it back.
///
/// One component because it is the same offer in more than one place, and the
/// wording is the thing that has to match: a ledger line and a show-this card
/// are both tombstoned, both restorable, and both deleted with no confirmation
/// in front of them — the banner *is* the safety net, so two copies of it
/// drifting is two different promises.
///
/// It draws `Palette.bg` behind itself because it sits between a `Screen` and
/// whatever is under it, and neither of their backgrounds reaches the strip
/// either side.
struct UndoBanner: View {
    /// What went, in a few words. One line — it is a receipt, not a summary.
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            Text(text)
                .font(Typeface.body(12.5))
                .foregroundStyle(Palette.n700)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onUndo) {
                Mono("undo", size: 10, trackingRatio: 0.1, color: Palette.a700)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.a100))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.accent, lineWidth: 1))
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.s2)
        .background(Palette.bg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Unsaved work

/// What a composer does when somebody leaves it with something typed.
///
/// A swipe down used to throw away tonight's page, its photographs and a
/// letter in progress with no word said, and `interactiveDismissDisabled` was
/// used exactly once in the app. This is for *new* work, the kind with nowhere
/// to go but the thing being composed. An edit to something that already
/// exists commits on `onDisappear` instead (the day plan, the setup fields),
/// and a letter keeps itself as a draft; see §5.1.
///
/// While `isDirty`, the swipe is held and raises the same question Close does.
/// The sheet's own Close should call `askOrDismiss` from the view, so both
/// ways out ask the one question in the one wording.
struct UnsavedWorkGuard: ViewModifier {
    let isDirty: Bool
    @Binding var isAsking: Bool
    /// What goes. A few words: "The line and the photos." Nil asks plainly.
    var whatGoes: String?
    /// Runs before the sheet closes, for anything the composer wrote to disk
    /// ahead of saving.
    let onDiscard: () -> Void

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isDirty)
            .background(DismissAttemptObserver { if isDirty { isAsking = true } })
            .confirmationDialog("Throw it away?", isPresented: $isAsking,
                                titleVisibility: .visible) {
                Button("Throw it away", role: .destructive) { onDiscard() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text(whatGoes.map { "\($0) Nothing here has been saved." }
                     ?? "Nothing here has been saved.")
            }
    }
}

extension View {
    /// See `UnsavedWorkGuard`. `onDiscard` must dismiss the sheet itself.
    func guardsUnsavedWork(isDirty: Bool, isAsking: Binding<Bool>,
                           whatGoes: String? = nil,
                           onDiscard: @escaping () -> Void) -> some View {
        modifier(UnsavedWorkGuard(isDirty: isDirty, isAsking: isAsking,
                                  whatGoes: whatGoes, onDiscard: onDiscard))
    }
}

/// Hears a swipe that `interactiveDismissDisabled` held back.
///
/// SwiftUI has no hook for it, so this joins the sheet's presentation
/// controller as its delegate and forwards everything else to the delegate
/// SwiftUI put there, which is what keeps `isPresented` and
/// `interactiveDismissDisabled` working. Without it a held swipe just bounces,
/// which reads as the app being stuck.
private struct DismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Observer { Observer() }

    func updateUIViewController(_ controller: Observer, context: Context) {
        controller.onAttempt = onAttempt
        controller.attach()
    }

    final class Observer: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttempt: (() -> Void)?
        private weak var forwarded: UIAdaptivePresentationControllerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        /// The sheet's presentation controller, found from the top of this
        /// controller's parent chain.
        func attach() {
            var top: UIViewController = self
            while let parent = top.parent { top = parent }
            guard let presentation = top.presentationController,
                  presentation.delegate !== self else { return }
            forwarded = presentation.delegate
            presentation.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt?()
            forwarded?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (forwarded?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if let forwarded, forwarded.responds(to: selector) { return forwarded }
            return super.forwardingTarget(for: selector)
        }
    }
}
