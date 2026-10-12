import SwiftUI
import WidgetKit
import AppIntents

/// A control for the Lock Screen, Control Centre and the Action button.
///
/// It runs `MarkMomentIntent`, which opens the app on the composer. No trip
/// data is read to draw it: the label is a constant, so the extension still
/// reaches `dithoi.widget.v1` and nothing else.
@available(iOS 18.0, *)
struct MarkMomentControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lovedones.dithoi.mark-moment") {
            ControlWidgetButton(action: MarkMomentIntent()) {
                Label("Mark a moment", systemImage: "sparkle")
            }
        }
        .displayName("Mark a moment")
        .description("Opens Đi Thôi on a new moment.")
    }
}
