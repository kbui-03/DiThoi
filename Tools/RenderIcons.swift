import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the app icon set from `Shared/TripMark.swift` and rewrites
/// `Contents.json` from the same slot table. See Tools/render-icons.sh.
///
/// The catalogue and the files on disk are two lists that can disagree, so one
/// of them has to be derived from the other. Both are derived from
/// `IconSlot.all` here, which means a slot that isn't rendered can't be
/// declared and a file that isn't declared can't be left behind.
@main
struct RenderIcons {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: rendericons <path to AppIcon.appiconset>\n".utf8))
            exit(2)
        }
        let set = URL(fileURLWithPath: arguments[1], isDirectory: true)

        // Which appearances the catalogue is allowed to carry. Settled by the
        // actool experiment in Tools/render-icons.sh, not by assumption.
        let appearances: [IconAppearance] = [.any, .dark, .tinted]
        let slots = appearances.flatMap { IconSlot.iPhone($0) }

        do {
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
            try removeStalePNGs(in: set, keeping: Set(slots.map(\.filename)))
            for slot in slots {
                try write(slot, into: set)
            }
            try writeContents(slots, into: set)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }

        print("— \(slots.count) icons —")
        for appearance in appearances {
            let cuts = IconSlot.iPhone(appearance)
                .map { "\($0.pixels)·\($0.cut.rawValue)" }
                .joined(separator: "  ")
            print("\(appearance.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)) \(cuts)")
        }
    }

    // MARK: - Drawing

    /// One tile.
    ///
    /// Full-bleed, opaque, square, and *unrounded*: the catalogue masks the
    /// squircle itself, and actool rejects alpha in the default app icon.
    static func write(_ slot: IconSlot, into set: URL) throws {
        let pixels = slot.pixels
        let geometry = TripMarkGeometry(cut: slot.cut, progress: TripMarkGeometry.iconProgress)
        guard let context = CGContext(
            data: nil,
            width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure("could not make a \(pixels)px context") }

        // Core Graphics puts the origin bottom-left. The rule sits on the
        // vertical centre so it happens to be flip-invariant today; flip anyway,
        // so moving it off-centre later can't silently mirror the whole mark.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: 1, y: -1)

        let scale = CGFloat(pixels) / CGFloat(geometry.width)
        context.setFillColor(cg(slot.ground.background))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
        context.scaleBy(x: scale, y: scale)

        draw(geometry, in: context, ground: slot.ground)

        guard let image = context.makeImage() else { throw Failure("no image for \(slot.filename)") }
        let url = set.appendingPathComponent(slot.filename)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw Failure("could not write \(slot.filename)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure("could not finalise \(slot.filename)")
        }
    }

    /// The three fills, in the order `Shared/TripMarkView.swift` uses them:
    /// the whole road, then the part walked, then the pin.
    ///
    /// Filled rectangles rather than a stroked path — a stroked 2.58px line on a
    /// 40px grid renders softer than a rect on the same pixels, and softness is
    /// the exact failure the three optical cuts exist to avoid.
    static func draw(_ g: TripMarkGeometry, in context: CGContext, ground: MarkGround) {
        let top = CGFloat(g.y - g.strokeWidth / 2)
        context.setFillColor(cg(ground.ahead))
        context.fill(CGRect(x: 0, y: top, width: CGFloat(g.width), height: CGFloat(g.strokeWidth)))

        context.setFillColor(cg(ground.walked))
        context.fill(CGRect(x: 0, y: top, width: CGFloat(g.dotX), height: CGFloat(g.strokeWidth)))

        if g.showsDot {
            context.fillEllipse(in: CGRect(
                x: CGFloat(g.dotX - g.dotRadius), y: CGFloat(g.y - g.dotRadius),
                width: CGFloat(g.dotRadius * 2), height: CGFloat(g.dotRadius * 2)))
        }
    }

    static func cg(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    // MARK: - The catalogue

    static func writeContents(_ slots: [IconSlot], into set: URL) throws {
        let images = slots.map { slot -> String in
            var fields = [
                "\"filename\":\"\(slot.filename)\"",
                "\"idiom\":\"\(slot.idiom)\""
            ]
            if let luminosity = slot.appearance.luminosity {
                fields.append("\"appearances\":[{\"appearance\":\"luminosity\",\"value\":\"\(luminosity)\"}]")
            }
            if slot.idiom == "universal" {
                // The iOS 18 single-size form. Without the platform key the
                // entry is cross-platform and the compiler won't match it.
                fields.append("\"platform\":\"ios\"")
            } else {
                fields.append("\"scale\":\"\(slot.scaleString)\"")
            }
            fields.append("\"size\":\"\(slot.sizeString)\"")
            return "{" + fields.sorted().joined(separator: ",") + "}"
        }
        // Minified, matching the three Contents.json files already in the
        // catalogue rather than introducing a second house style.
        let json = "{\"images\":[\(images.joined(separator: ","))],\"info\":{\"author\":\"xcode\",\"version\":1}}"
        try Data(json.utf8).write(to: set.appendingPathComponent("Contents.json"))
    }

    /// A renamed slot leaves its old PNG behind, where actool ignores it and
    /// git keeps it forever. The set is generated, so it is also swept.
    static func removeStalePNGs(in set: URL, keeping wanted: Set<String>) throws {
        let existing = try FileManager.default.contentsOfDirectory(atPath: set.path)
        for name in existing where name.hasSuffix(".png") && !wanted.contains(name) {
            try FileManager.default.removeItem(at: set.appendingPathComponent(name))
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
