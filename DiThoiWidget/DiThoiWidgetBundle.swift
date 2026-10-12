import SwiftUI
import WidgetKit

/// The whole extension. One widget, four families — and on iOS 18 one control,
/// which opens the app and reads nothing.
///
/// It can reach exactly one thing: `dithoi.widget.v1` in the shared group. The
/// trip, the journal and the twelve letters are in the app's own container,
/// which this process has no entitlement for and no type to decode with. See
/// the note at the top of Shared/WidgetSnapshot.swift.
@main
struct DiThoiWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayWidget()
        if #available(iOS 18.0, *) {
            MarkMomentControl()
        }
    }
}
