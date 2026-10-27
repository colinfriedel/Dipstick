//
//  FillUpCarPicker.swift
//  Dipstick
//

import SwiftUI

/// "Fill-up for which car?", shown when Log Fill-Up comes from Control
/// Center or Shortcuts and there's more than one car. The likeliest car is
/// first.
struct FillUpCarPicker: View {
    let vehicles: [Vehicle]
    let onPick: (Vehicle) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FILL-UP FOR")
                    .font(.dipstick(15, .semibold, relativeTo: .headline))
                    .tracking(2)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SmallControlButtonStyle())
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(vehicles) { vehicle in
                        Button { onPick(vehicle) } label: {
                            HStack(spacing: 12) {
                                vehicle.chip
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vehicle.name)
                                        .font(.dipstick(17, .semibold, relativeTo: .headline))
                                        .foregroundStyle(Theme.text)
                                    Text("\(vehicle.currentOdometer.formatted()) mi")
                                        .font(.readout(13, relativeTo: .caption))
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "fuelpump")
                                    .foregroundStyle(Theme.accentText)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .panel(radius: Theme.Radius.field)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.ground)
        .presentationDetents([.medium, .large])
    }
}
