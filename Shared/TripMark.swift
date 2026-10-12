import Foundation

// The mark: one pin on a line.
//
// A rule that bleeds off both edges at the vertical centre, the walked part in
// celadon and the road ahead in grey, with a filled dot at 62% along. The same
// diagram is the app icon, the widget, and the progress bar on Today.
//
// One view can't draw all three: the third caller is a macOS command-line
// rasteriser and the design layer imports UIKit. So this file holds the part
// that can disagree — the cut table, the pixel→cut mapping, the dot position
// and the progress arithmetic — and the two rasterisers
// (`Shared/TripMarkView.swift` for SwiftUI, `Tools/RenderIcons.swift` for Core
// Graphics) stay thin enough that only a fill order can drift.
//
// No `import CoreGraphics`: `Double` throughout, so `Tools/run-checks.sh` can
// keep proving this half is arithmetic.

// MARK: - Optical cuts

/// Three cuts, because one file scaled down goes thin: at 29px the large cut
/// renders the rule under a single physical pixel and the mark reads as a
/// floating dot.
enum TripMarkCut: String, CaseIterable {
    case large, medium, small
    /// A circular crop needs the dot pulled in so it doesn't collide with the curve.
    case circular
    /// iOS 18 monochrome. The mark is already two values, so tinting needs no
    /// special art.
    case tinted
    /// The rule unwrapped from its tile — the widget's progress bar, and Today's.
    case lockup

    /// Grid the numbers below are expressed on.
    var gridWidth: Double { self == .lockup ? 1024 : 1024 }
    var gridHeight: Double { self == .lockup ? 40 : 1024 }

    var strokeWidth: Double {
        switch self {
        case .large: 30
        case .medium: 44
        case .small: 66
        case .circular: 56
        case .tinted: 34
        case .lockup: 14
        }
    }

    var dotRadius: Double {
        switch self {
        case .large: 110
        case .medium: 130
        case .small: 164
        case .circular: 150
        case .tinted: 116
        case .lockup: 19
        }
    }

    /// Whether the rule runs off the edge of whatever holds it.
    ///
    /// On the last day the dot's centre lands exactly on the frame edge. In a
    /// tile the rule already bleeds off both sides, so half the dot leaving is
    /// the intended asymmetry. In a lockup the rule is *inset*, so there is no
    /// edge to leave through and the same half-dot gets cut by the canvas —
    /// which reads as an arrowhead welded onto the end of a bar.
    var bleeds: Bool { self != .lockup }

    /// Which cut a given rendered pixel size gets.
    ///
    /// Two thresholds covering the three lists: large 1024 · 180 · 167 · 152,
    /// medium 120 · 87 · 80 · 76, small 60 · 58 · 40 · 29. All twelve are
    /// checked.
    static func forIcon(pixels: Int) -> TripMarkCut {
        if pixels >= 152 { return .large }
        if pixels >= 76 { return .medium }
        return .small
    }
}

// MARK: - Ink

/// The six grounds, as numbers.
///
/// `Palette` reads these rather than carrying its own copies. Holding the same
/// physical quantity in two places is what put `PhotoStore` at 2048 while the
/// book wanted 2,475 — same lesson, applied to colour.
enum TripMarkInk {
    static let ink: UInt32 = 0x201F1D          // Palette.text
    static let cream: UInt32 = 0xF3F2F2        // Palette.bg
    static let roadDark: UInt32 = 0x605D5D     // Palette.n700
    static let roadLight: UInt32 = 0xBAB6B6    // Palette.n400
    static let accentDark: UInt32 = 0xA3BE9F   // Palette.a400
    static let accentLight: UInt32 = 0x688465  // Palette.a600

    /// The notification badge. "No green survives at that scale on a grey chip."
    static let badgeGround: UInt32 = 0x3B3B3B
    static let badgeRoad: UInt32 = 0x8A8A8A
    static let badgeMark: UInt32 = 0xFFFFFF

    /// Where hue is unavailable — the tinted icon, and the Lock Screen's vibrant
    /// rendering — the rule ahead drops to this fraction of the mark instead of
    /// changing colour. The design's one number, used in both places.
    static let aheadFraction = 0.35

    static func white(_ fraction: Double) -> UInt32 {
        let v = UInt32((max(0, min(1, fraction)) * 255).rounded())
        return v << 16 | v << 8 | v
    }
}

/// One tile's three colours.
struct MarkGround: Equatable {
    var background: UInt32
    var ahead: UInt32
    var walked: UInt32

    static let dark = MarkGround(background: TripMarkInk.ink,
                                 ahead: TripMarkInk.roadDark,
                                 walked: TripMarkInk.accentDark)

    static let light = MarkGround(background: TripMarkInk.cream,
                                  ahead: TripMarkInk.roadLight,
                                  walked: TripMarkInk.accentLight)

    static let badge = MarkGround(background: TripMarkInk.badgeGround,
                                  ahead: TripMarkInk.badgeRoad,
                                  walked: TripMarkInk.badgeMark)

    /// Greyscale. iOS supplies the tint, so the art is luminance only: black
    /// ground, white mark, and the road ahead at `aheadFraction` of it.
    static let tinted = MarkGround(background: 0x000000,
                                   ahead: TripMarkInk.white(TripMarkInk.aheadFraction),
                                   walked: 0xFFFFFF)
}

// MARK: - Geometry

/// Where the rule and the dot sit, on the cut's own grid.
struct TripMarkGeometry: Equatable {
    var cut: TripMarkCut
    var progress: Double
    /// The dot is a claim that something has been walked. Before departure
    /// nothing has, so it is withheld rather than parked at the left edge.
    var showsDot: Bool

    var width: Double { cut.gridWidth }
    var height: Double { cut.gridHeight }
    var y: Double { height / 2 }
    var strokeWidth: Double { cut.strokeWidth }
    var dotRadius: Double { cut.dotRadius }
    var dotX: Double { progress * width }

    init(cut: TripMarkCut, progress: Double, showsDot: Bool = true) {
        self.cut = cut
        self.progress = min(max(progress, 0), 1)
        self.showsDot = showsDot
    }

    /// 62%, fixed, so the App Store asset never changes shape. Not 50%:
    /// centred, the mark stops reading as a journey underway.
    static let iconProgress = 635.0 / 1024.0

    static func icon(pixels: Int) -> TripMarkGeometry {
        TripMarkGeometry(cut: .forIcon(pixels: pixels), progress: iconProgress)
    }

    /// Day 1 sits at 0 and the last day at 1 — where the rule is solid and the
    /// dot's centre is exactly on the frame edge, so the widget's half-out-of-
    /// frame final state is what the arithmetic asks for rather than a rounding
    /// artefact.
    static func progress(day: Int, of dayCount: Int) -> Double {
        guard dayCount > 1 else { return 1 }
        return min(max(Double(day - 1) / Double(dayCount - 1), 0), 1)
    }
}

// MARK: - The icon catalogue

enum IconAppearance: String, CaseIterable {
    case any, dark, tinted

    /// The value the asset catalogue's `appearances` entry carries. `any` has
    /// no entry at all — it is the default slot, which is also what the App
    /// Store and light mode use.
    var luminosity: String? { self == .any ? nil : rawValue }
}

/// What a slot is *for*, which is a second axis from how big it is.
///
/// The design says the 20pt badge is "flat white on grey — no green survives at
/// that scale". A generator keyed on pixels alone would ship a green
/// notification icon and nothing but a real banner would show it.
enum IconRole: String {
    case notification, settings, spotlight, home, marketing
}

struct IconSlot: Equatable {
    var idiom: String
    var pointSize: Double
    var scale: Int
    var role: IconRole
    var appearance: IconAppearance

    var pixels: Int { Int((pointSize * Double(scale)).rounded()) }

    /// The default appearance gets the cut its own pixel size asks for. The
    /// appearance slots can't: they are one 1024 file that iOS scales across
    /// the whole ramp, so a `.large` cut there would render the rule at 1.17px
    /// on a notification — the failure the three cuts exist to prevent,
    /// reintroduced by the catalogue.
    ///
    /// So they take the middle cut: the same rule (weight for the size it will
    /// be seen at) applied to a slot that has only one file. `.tinted`'s own
    /// numbers stay in the table above, ready for the day `actool` accepts a
    /// per-size tinted set; `Tools/render-icons.sh` re-tests that every run.
    var cut: TripMarkCut { appearance == .any ? .forIcon(pixels: pixels) : .medium }

    var ground: MarkGround {
        switch appearance {
        case .tinted: .tinted
        case .any: role == .notification ? .badge : .light
        case .dark: role == .notification ? .badge : .dark
        }
    }

    /// `"20x20"`, the way the catalogue writes it.
    var sizeString: String {
        let s = pointSize == pointSize.rounded() ? String(Int(pointSize)) : String(pointSize)
        return "\(s)x\(s)"
    }

    var scaleString: String { "\(scale)x" }

    var filename: String {
        let stem = pointSize >= 1024
            ? "icon-1024"
            : "icon-\(Int(pointSize))@\(scale)x"
        return appearance == .any ? "\(stem).png" : "\(stem)-\(appearance.rawValue).png"
    }

    /// Every slot the catalogue can actually carry.
    ///
    /// **The default appearance gets the three optical cuts; dark and tinted get
    /// one 1024 each.** That asymmetry is not a preference — `actool` silently
    /// drops per-size children that carry an `appearances` key ("the app icon
    /// set has 16 unassigned children", no error, exit 0). Tools/render-icons.sh
    /// re-runs the experiment on every render so the day it stops being true is
    /// the day the build says so.
    ///
    /// The cost: on a dark home screen the 40px badge is a scaled-down large
    /// cut rather than the small one. The default slot — which is also the App
    /// Store's — keeps all three.
    ///
    /// The iPad sizes (167, 152, 76) are absent because this app is
    /// iPhone-only. They stay in the cut table above and are still checked, so
    /// the table is complete where it happens to be unused.
    static func iPhone(_ appearance: IconAppearance) -> [IconSlot] {
        guard appearance == .any else {
            return [IconSlot(idiom: "universal", pointSize: 1024, scale: 1,
                             role: .home, appearance: appearance)]
        }
        return [
            IconSlot(idiom: "iphone", pointSize: 20, scale: 2, role: .notification, appearance: .any),
            IconSlot(idiom: "iphone", pointSize: 20, scale: 3, role: .notification, appearance: .any),
            IconSlot(idiom: "iphone", pointSize: 29, scale: 2, role: .settings, appearance: .any),
            IconSlot(idiom: "iphone", pointSize: 29, scale: 3, role: .settings, appearance: .any),
            IconSlot(idiom: "iphone", pointSize: 40, scale: 2, role: .spotlight, appearance: .any),
            IconSlot(idiom: "iphone", pointSize: 40, scale: 3, role: .spotlight, appearance: .any),
            IconSlot(idiom: "iphone", pointSize: 60, scale: 2, role: .home, appearance: .any),
            IconSlot(idiom: "iphone", pointSize: 60, scale: 3, role: .home, appearance: .any),
            IconSlot(idiom: "ios-marketing", pointSize: 1024, scale: 1, role: .marketing, appearance: .any)
        ]
    }

    static var all: [IconSlot] {
        IconAppearance.allCases.flatMap { iPhone($0) }
    }
}
