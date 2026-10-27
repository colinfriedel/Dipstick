//
//  DipstickControls.swift
//  DipstickControls
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct DipstickControlsBundle: WidgetBundle {
    var body: some Widget {
        LogFillUpControl()
    }
}

/// A Control Center (and Lock Screen) button that opens Dipstick at the
/// pump scanner.
struct LogFillUpControl: ControlWidget {
    static let kind = "com.colinfriedel.Dipstick.LogFillUp"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogFillUpIntent()) {
                Label("Log Fill-Up", systemImage: "fuelpump.fill")
            }
        }
        .displayName("Log Fill-Up")
        .description("Opens Dipstick's pump scanner to log a fill-up.")
    }
}
