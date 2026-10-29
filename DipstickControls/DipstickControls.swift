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
        CarFillUpControl()
        FillUpWidget()
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

/// The car a "Log Fill-Up for a car" button is for, chosen when adding it.
struct CarFillUpConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Car"

    @Parameter(title: "Car")
    var car: CarEntity?
}

/// A Control Center button for one car: straight to the pump scanner for it,
/// no question. Add one per car.
struct CarFillUpControl: ControlWidget {
    static let kind = "com.colinfriedel.Dipstick.LogFillUpForCar"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: CarFillUpConfiguration.self) { configuration in
            ControlWidgetButton(action: LogFillUpForCarIntent(car: configuration.car)) {
                Label(configuration.car?.name ?? "Choose Car", systemImage: "fuelpump.fill")
            }
        }
        .displayName("Log Fill-Up for a Car")
        .description("Opens Dipstick's pump scanner for one car. Add one for each car.")
        .promptsForUserConfiguration()
    }
}
