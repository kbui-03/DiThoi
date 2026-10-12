import SwiftUI
import UIKit

/// Choosing the square the book gets.
///
/// The page is square and the photograph is whatever shape the phone was held
/// in, so something has to decide what is lost. It used to be decided twice, by
/// nobody: `BookSpreadView` centre-cropped at print time and `JournalPhoto`
/// centre-cropped into a different shape on screen.
///
/// The arithmetic is `PhotoCrop`, in `Model/`, where the checks can reach it.
/// What is here is the aperture, two gestures and one rasterise.
///
/// Dark ground, like the stamp and separated screens: the subject is the
/// photograph, and a cream page around it is a second thing to look at.
struct PhotoCropView: View {
    let source: UIImage
    /// The chosen square. The caller saves it — this screen touches no store,
    /// so cancelling costs nothing and leaves whatever is already attached.
    var onUse: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var crop: PhotoCrop
    /// The crop as it was when the current gesture started. Deltas are applied
    /// to this rather than accumulated onto `crop`, which would compound the
    /// clamping — a drag held against an edge would otherwise keep eating
    /// translation and the photo would lurch when it came back.
    @State private var dragBase: PhotoCrop?
    @State private var zoomBase: PhotoCrop?

    init(source: UIImage, onUse: @escaping (UIImage) -> Void) {
        self.source = source
        self.onUse = onUse
        _crop = State(initialValue: PhotoCrop(sourceWidth: Double(source.size.width),
                                              sourceHeight: Double(source.size.height)).clamped())
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                aperture(side: side)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, Space.gutter)

            Spacer(minLength: 0)

            footer
        }
        .background(Palette.n900.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - The aperture

    private func aperture(side: CGFloat) -> some View {
        // Source points per screen point. The whole layout is one number: the
        // chosen square is drawn `side` wide, so everything else follows.
        let k = side / max(CGFloat(crop.side), 0.0001)
        return Image(uiImage: source)
            .resizable()
            .frame(width: CGFloat(crop.sourceWidth) * k,
                   height: CGFloat(crop.sourceHeight) * k)
            .offset(x: -CGFloat(crop.originX) * k, y: -CGFloat(crop.originY) * k)
            .frame(width: side, height: side, alignment: .topLeading)
            .clipped()
            .overlay(Rectangle().strokeBorder(Palette.n100.opacity(0.7), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(drag(scale: k))
            .simultaneousGesture(magnify)
            .accessibilityLabel("The square the book will print. Drag to move it, pinch to zoom.")
    }

    private func drag(scale k: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = dragBase ?? crop
                if dragBase == nil { dragBase = base }
                var next = base
                // Dragging the photograph right moves the window left.
                next.offsetX = base.offsetX - Double(value.translation.width / k)
                next.offsetY = base.offsetY - Double(value.translation.height / k)
                crop = next.clamped()
            }
            .onEnded { _ in dragBase = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = zoomBase ?? crop
                if zoomBase == nil { zoomBase = base }
                var next = base
                next.zoom = base.zoom * Double(value.magnification)
                crop = next.clamped()
            }
            .onEnded { _ in zoomBase = nil }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { dismiss() } label: {
                Mono("Cancel", size: 10.5, trackingRatio: 0.1, color: Palette.n400)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Mono("The page is square", size: 10.5, trackingRatio: 0.1, color: Palette.n500)
        }
        .padding(.horizontal, Space.gutter)
    }

    private var footer: some View {
        VStack(spacing: Space.s2) {
            // The instruction stays put. It used to be replaced by the warning
            // below, which took the words "pinch to zoom" off the screen at
            // exactly the moment somebody needed to pinch back out.
            Text("Drag to move it, pinch to zoom. This is what the book prints.")
                .font(Typeface.body(11).italic())
                .foregroundStyle(Palette.n500)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let softLine {
                Text(softLine)
                    .font(Typeface.body(11).italic())
                    .foregroundStyle(Palette.n400)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if let cropped = rendered() { onUse(cropped) }
                dismiss()
            } label: {
                Text("Use this square")
                    .font(Typeface.heading(17, .semibold))
                    .foregroundStyle(Palette.a200)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Rectangle().strokeBorder(Palette.a600, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s4)
    }

    /// Why this square will print soft, or nil because it won't.
    ///
    /// Two different facts, and one sentence for both is wrong half the time. A
    /// photograph small enough to print soft *uncropped* — a screenshot,
    /// something sent over a messaging app — is nothing anybody can fix by
    /// pinching out, and "this close in" said to somebody who has not zoomed at
    /// all sends them looking for a control that will not help. It said exactly
    /// that on the first run, on an untouched crop of a 2,005-pixel photograph.
    ///
    /// The number is `BookSpec`'s, which is the same arithmetic the print
    /// screen reads, so the warning here and the warning there cannot disagree.
    private var softLine: String? {
        let chosen = crop.clamped()
        let scale = Double(source.scale)
        guard chosen.isSoft(scale: scale) else { return nil }
        let dpi = BookSpec().printedDPI(forSquare: chosen.pixelSide(scale: scale))
        return chosen.zoom > 1.01
            ? "This close in it prints soft — about \(dpi) dpi against 300."
            : "This photograph is small — even uncropped it prints at about \(dpi) dpi against 300."
    }

    // MARK: - The one rasterise

    /// Drawn with `UIImage.draw(at:)`, **not** `CGImage.cropping(to:)`.
    ///
    /// The picker hands back a `UIImage` whose `imageOrientation` may not be
    /// `.up`, and `cgImage` is the raw un-rotated buffer — cropping there takes
    /// the wrong quarter of a photograph held sideways, silently, and only for
    /// the people whose phone was rotated. `draw(at:)` works in the oriented
    /// point space `PhotoCrop` was built from.
    ///
    /// The result goes to `PhotoStore.save`, which caps the long edge at
    /// `fullBleedPixels` as it always did. A square in is a square out.
    private func rendered() -> UIImage? {
        let c = crop.clamped()
        guard c.side > 0 else { return nil }
        // A square source nobody moved is already the answer. Re-encoding it
        // through the renderer would cost a generation of JPEG for nothing.
        if c.isUntouched { return source }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = source.scale
        format.opaque = true
        let size = CGSize(width: c.side, height: c.side)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(at: CGPoint(x: -c.originX, y: -c.originY))
        }
    }
}
