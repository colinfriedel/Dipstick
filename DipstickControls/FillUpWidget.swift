//
//  FillUpWidget.swift
//  DipstickControls
//

import AppIntents
import SwiftUI
import WidgetKit

/// The car a Lock Screen fill-up widget is for; none means ask each time.
struct FillUpWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Log Fill-Up"
    static let description = IntentDescription("Opens Dipstick's pump scanner.")

    @Parameter(title: "Car", description: "Leave empty to choose the car each time")
    var car: CarEntity?
}

struct FillUpEntry: TimelineEntry {
    let date: Date
    /// nil: ask which car.
    let car: CarDirectory.Car?
    /// A car was chosen but has since been deleted.
    let carMissing: Bool
}

struct FillUpProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FillUpEntry {
        FillUpEntry(date: .now, car: .init(id: "", name: "My Car", lastMPG: 28.4), carMissing: false)
    }

    func snapshot(for configuration: FillUpWidgetConfiguration, in context: Context) async -> FillUpEntry {
        entry(for: configuration)
    }

    /// The app reloads the widget when a car's name or last MPG changes.
    func timeline(for configuration: FillUpWidgetConfiguration, in context: Context) async -> Timeline<FillUpEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: FillUpWidgetConfiguration) -> FillUpEntry {
        let id = configuration.car?.id
        let car = CarDirectory.car(id: id)
        return FillUpEntry(date: .now, car: car, carMissing: id != nil && car == nil)
    }
}

/// Lock Screen widgets that open the pump scanner: a round fuel-pump icon,
/// or a wider one with the car's name and last tank's MPG.
struct FillUpWidget: Widget {
    static let kind = "com.colinfriedel.Dipstick.FillUpWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: FillUpWidgetConfiguration.self, provider: FillUpProvider()) { entry in
            FillUpWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(CarDirectory.fillUpURL(carID: entry.car?.id))
        }
        .configurationDisplayName("Log Fill-Up")
        .description("Opens the pump scanner. Pick a car, or leave it empty to choose each time.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct FillUpWidgetView: View {
    let entry: FillUpEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        default: circular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel(entry.car.map { "Log fill-up for \($0.name)" } ?? "Log fill-up")
    }

    /// Sized to fit the Lock Screen's wide slot (about 3 short lines):
    /// name, MPG, "last tank". Text shrinks rather than cutting off.
    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.carMissing ? "Car removed" : entry.car?.name ?? "Log Fill-Up")
                    .font(.system(size: 14, weight: .semibold))
                    .widgetAccentable()
                if let mpg = entry.car?.lastMPG {
                    Text("\(mpg.formatted(.number.precision(.fractionLength(1)))) MPG")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("last tank")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.car == nil ? "Choose car" : "No MPG yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
