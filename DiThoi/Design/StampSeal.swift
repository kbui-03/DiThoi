import SwiftUI

/// The stamp, as the app draws it the moment it is earned: the code, a short
/// rule, and the date, inside one ring.
///
/// One drawing for the arrival screen and the book. The book's stamps page was
/// a grid of plain circles with the code in them while the screen that hands
/// the stamp out drew this seal — so the printed record of every place they
/// stood looked like a different, lesser thing than the moment it recorded.
///
/// Everything is proportioned off `side`, from the arrival screen's 186-point
/// seal, so the two are the same object at two sizes.
struct StampSeal: View {
    let code: String
    let date: Date?
    let side: CGFloat
    var ring: Color = Palette.accent
    var ink: Color = Palette.a700
    var rule: Color = Palette.accent
    var lineWidth: CGFloat = 1
    /// The date's size, when the seal is too small for its proportional one
    /// to be read. On the book's stamps page it would print at about five
    /// points; the date is the half of the stamp that says when.
    var dateSize: CGFloat? = nil

    /// One point of the arrival screen's seal, at this size.
    private func u(_ points: CGFloat) -> CGFloat { points * side / 186 }

    var body: some View {
        VStack(spacing: 0) {
            Text(code)
                .font(Typeface.heading(u(44)))
                .tracking(u(-0.44))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rectangle().fill(rule)
                .frame(width: u(44), height: lineWidth)
                .padding(.vertical, u(12))
            if let date {
                Text(date.text("dd MMM yyyy").uppercased())
                    .font(Typeface.mono(dateSize ?? u(10)))
                    .tracking((dateSize ?? u(10)) * 0.14)
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        // Keep the type inside the ring where the ring is narrowest.
        .padding(.horizontal, u(24))
        .frame(width: side, height: side)
        .overlay(Circle().strokeBorder(ring, lineWidth: lineWidth))
    }
}
