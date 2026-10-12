import SwiftUI
import UIKit

// Tokens transcribed from the Classical design system in
// "Đi Thôi - Classical Prototype.dc.html". The oklch accent ramp was
// converted to sRGB; hex values below are the converted results.
//
// The six rungs the mark stands on are *not* written out again here — they are
// read from `TripMarkInk` in Shared/TripMark.swift, because the icon generator
// needs them and cannot see this file. The same physical quantity held in two
// places is what put `PhotoStore` at 2048 while the book wanted 2,475.

enum Palette {
    static let bg        = Color(hex: TripMarkInk.cream)
    static let surface   = Color(hex: 0xEAE9E9)
    static let text      = Color(hex: TripMarkInk.ink)
    static let divider   = Color(hex: TripMarkInk.ink).opacity(0.16)

    static let n100 = Color(hex: 0xF8F4F4)
    static let n200 = Color(hex: 0xEAE7E7)
    static let n300 = Color(hex: 0xD7D3D3)
    static let n400 = Color(hex: TripMarkInk.roadLight)
    static let n500 = Color(hex: 0x9B9797)
    static let n600 = Color(hex: 0x7D7979)
    static let n700 = Color(hex: TripMarkInk.roadDark)
    static let n800 = Color(hex: 0x444141)
    static let n900 = Color(hex: 0x2D2B2B)

    /// oklch(0.60 0.056 142)
    static let accent = Color(hex: 0x6D896A)
    static let a100 = Color(hex: 0xECF6EA)
    static let a200 = Color(hex: 0xD6E8D3)
    static let a300 = Color(hex: 0xBED7BB)
    static let a400 = Color(hex: TripMarkInk.accentDark)
    static let a500 = Color(hex: 0x86A282)
    static let a600 = Color(hex: TripMarkInk.accentLight)
    static let a700 = Color(hex: 0x4D664B)
    static let a800 = Color(hex: 0x354933)
    static let a900 = Color(hex: 0x243222)

    /// Divider colour for the dark screens (stamp, lock, separated).
    static let darkDivider = Color(hex: TripMarkInk.roadDark)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Three roles: display serif, text serif, monospace label. They map onto the
/// system families — New York for both serifs, separated by weight and tracking
/// rather than by family, and SF Mono for the labels. Drop TTFs into the bundle
/// and change these three functions to use exact faces instead.
enum Typeface {
    static func heading(_ size: CGFloat, _ weight: Font.Weight = .regular) -> TypeSpec {
        TypeSpec(role: .heading, size: size, weight: weight)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> TypeSpec {
        TypeSpec(role: .body, size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> TypeSpec {
        TypeSpec(role: .mono, size: size, weight: weight)
    }
}

/// A font before it knows how big the reader wants it.
///
/// The screens ask for exact points. Resolving that against the reader's
/// text-size setting happens here, in one place, so no screen has to.
struct TypeSpec: Equatable {
    enum Role { case heading, body, mono }

    var role: Role
    var size: CGFloat
    var weight: Font.Weight = .regular
    var isItalic: Bool = false
    /// Tighter than the size would normally allow. For type in a fixed slot —
    /// five tab labels across one bar — where growing freely would collide
    /// with the neighbours rather than just take more room.
    var ceilingOverride: CGFloat?

    func italic() -> TypeSpec {
        var copy = self
        copy.isItalic = true
        return copy
    }

    func capped(at ceiling: CGFloat) -> TypeSpec {
        var copy = self
        copy.ceilingOverride = ceiling
        return copy
    }

    var design: Font.Design {
        switch role {
        case .heading, .body: .serif
        case .mono: .monospaced
        }
    }

    /// How far this size is allowed to grow.
    ///
    /// Body copy takes the reader's setting in full. Display type does not:
    /// a 78pt masthead at the largest accessibility size would be 240pt and
    /// nothing else would fit on the screen beside it. Larger type therefore
    /// gets a smaller ceiling — the standard editorial compromise, and the
    /// reason the layout still holds at accessibility sizes. Shrinking is
    /// never capped.
    var growthCeiling: CGFloat {
        if let ceilingOverride { return ceilingOverride }
        return switch size {
        case ..<14: 2.4
        case ..<19: 2.0
        case ..<29: 1.6
        case ..<47: 1.35
        default: 1.2
        }
    }

    func resolved(for typeSize: DynamicTypeSize) -> Font {
        .system(size: TypeScale.points(size, ceiling: growthCeiling, for: typeSize),
                weight: weight, design: design)
            .italic(isItalic)
    }
}

private extension Font {
    func italic(_ on: Bool) -> Font { on ? self.italic() : self }
}

/// Turns the reader's text-size setting into a multiplier.
enum TypeScale {
    static func points(_ size: CGFloat, ceiling: CGFloat, for typeSize: DynamicTypeSize) -> CGFloat {
        let scale = factor(for: typeSize)
        return (size * min(scale, ceiling)).rounded()
    }

    /// UIKit's own scaling for body text, which is what the reader has actually
    /// asked for, expressed as a plain multiplier.
    ///
    /// Worked out once per setting, not once per label. `ScaledFont` reads this
    /// for every piece of type on screen on every layout pass, and `TripStore`
    /// invalidates every view on every mutation — so a `UITraitCollection`
    /// allocation and a `UIFontMetrics` call sat on the critical path of a bound
    /// `TextField`, once per keystroke per visible label.
    ///
    /// There are twelve settings and the answer for each never changes while
    /// the process is running, so the whole table is built on first use.
    static func factor(for typeSize: DynamicTypeSize) -> CGFloat {
        table[typeSize] ?? measure(typeSize)
    }

    private static let table: [DynamicTypeSize: CGFloat] = {
        var built: [DynamicTypeSize: CGFloat] = [:]
        for size in DynamicTypeSize.allCases { built[size] = measure(size) }
        return built
    }()

    private static func measure(_ typeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: typeSize.contentSizeCategory)
        let reference: CGFloat = 17
        return UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: reference, compatibleWith: traits) / reference
    }
}

extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

/// Applies a `TypeSpec` at the reader's current text size. Reading the
/// environment here is what makes every label in the app re-draw when they
/// change the setting.
private struct ScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let spec: TypeSpec

    func body(content: Content) -> some View {
        content.font(spec.resolved(for: typeSize))
    }
}

extension View {
    /// Shadows `View.font(_:)` for specs, so screens keep asking for points and
    /// get the reader's size for free.
    func font(_ spec: TypeSpec) -> some View {
        modifier(ScaledFont(spec: spec))
    }
}

/// The spacing scale, in points.
enum Space {
    static let s1: CGFloat = 4.6
    static let s2: CGFloat = 9.2
    static let s3: CGFloat = 13.8
    static let s4: CGFloat = 18.4
    static let s6: CGFloat = 27.6
    static let s8: CGFloat = 36.8

    /// Horizontal screen gutter, used by every screen.
    static let gutter: CGFloat = 26
}

enum Radius {
    static let sm: CGFloat = 2
    static let md: CGFloat = 4
    static let lg: CGFloat = 7
}
