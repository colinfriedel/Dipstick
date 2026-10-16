//
//  FuelStatsSection.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import Charts

/// Stats tab of the vehicle detail list: MPG summary and trend chart, city and
/// highway MPG (for cars with recorded trips), then fuel spend and a monthly
/// spend chart.
struct FuelStatsSection: View {
    let vehicle: Vehicle

    var body: some View {
        let stats = vehicle.fuelStats()

        Section("MPG") {
            if stats.tanks.isEmpty {
                Text("Log two full tanks to see your MPG.")
                    .foregroundStyle(.secondary)
            } else {
                if let average = stats.averageMPG {
                    LabeledContent("Average", value: Units.mpg(average))
                }
                if let recent = stats.recentMPG, stats.tanks.count > FuelStats.recentTankCount {
                    LabeledContent("Last \(FuelStats.recentTankCount) tanks", value: Units.mpg(recent))
                }
                if let best = stats.best, let worst = stats.worst, stats.tanks.count > 1 {
                    LabeledContent("Best", value: Units.mpg(best.mpg))
                    LabeledContent("Worst", value: Units.mpg(worst.mpg))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Each full tank · dashed line is the average · tap a point for details")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MPGTrendChart(tanks: stats.tanks, average: stats.averageMPG)
                        .frame(height: 220)
                }
                .padding(.vertical, 8)
            }
        }

        if !(vehicle.trips ?? []).isEmpty {
            CityHighwaySection(vehicle: vehicle)
        }

        Section {
            LabeledContent("This year", value: Units.currency(stats.spendThisYear))
            LabeledContent("All time", value: Units.currency(stats.totalSpend))
            if let price = stats.averagePricePerGallon {
                LabeledContent("Average price", value: Units.pricePerGallon(price))
            }
            if let costPerMile = stats.costPerMile {
                LabeledContent("Cost per mile", value: Units.costPerMile(costPerMile))
            }
            if stats.totalSpend > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Monthly, last 12 months")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MonthlySpendChart(months: stats.monthlySpend)
                        .frame(height: 180)
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text("Fuel spend")
        } footer: {
            if stats.unknownCostCount > 0 {
                Text("\(stats.unknownCostCount) fill-up\(stats.unknownCostCount == 1 ? "" : "s") with no recorded cost \(stats.unknownCostCount == 1 ? "isn't" : "aren't") included in spend or price.")
            }
        }
    }
}

/// One point per full tank over time, with the average as a dashed line.
/// Tap near a point to read its exact MPG; tap again to hide it. (A tap
/// rather than press-and-drag, so it doesn't fight with scrolling the list.)
private struct MPGTrendChart: View {
    let tanks: [FuelStats.Tank]
    let average: Double?

    @State private var selectedDate: Date?

    private var selectedTank: FuelStats.Tank? {
        guard let selectedDate else { return nil }
        return tanks.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    /// Pad the y-axis around the data so small changes are visible.
    private var yDomain: ClosedRange<Double> {
        let values = tanks.map(\.mpg) + [average].compactMap { $0 }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.2, 2)
        return max(0, low - padding)...(high + padding)
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let x = location.x - geometry[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return }
        let nearest = tanks.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
        // Tapping the selected tank again hides the callout.
        selectedDate = (nearest?.date == selectedTank?.date) ? nil : nearest?.date
    }

    var body: some View {
        Chart {
            ForEach(tanks) { tank in
                LineMark(x: .value("Date", tank.date), y: .value("MPG", tank.mpg))
                PointMark(x: .value("Date", tank.date), y: .value("MPG", tank.mpg))
                    .symbolSize(30)
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            if let tank = selectedTank {
                RuleMark(x: .value("Date", tank.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                        VStack(spacing: 2) {
                            Text(Units.mpg(tank.mpg)).font(.caption.bold())
                            Text(tank.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(.background, in: .rect(cornerRadius: 6))
                        .shadow(radius: 1)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        select(at: location, proxy: proxy, geometry: geometry)
                    }
            }
        }
        .accessibilityLabel("MPG per tank over time")
    }
}

/// Fuel spend per month for the last 12 months.
private struct MonthlySpendChart: View {
    let months: [FuelStats.MonthSpend]

    var body: some View {
        Chart(months) { month in
            BarMark(
                x: .value("Month", month.month, unit: .month),
                y: .value("Spend", month.total)
            )
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 2)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                }
            }
        }
        .accessibilityLabel("Fuel spend per month, last 12 months")
    }
}

/// City, highway and combined MPG from fully recorded tanks, plus how much of
/// the current tank has been recorded so far.
private struct CityHighwaySection: View {
    let vehicle: Vehicle

    var body: some View {
        let estimate = CityHighwayMPG.estimate(from: vehicle.trackedTanks)

        Section {
            if let estimate {
                LabeledContent("City", value: Units.mpg(estimate.cityMPG))
                LabeledContent("Highway", value: Units.mpg(estimate.highwayMPG))
                LabeledContent("Combined", value: Units.mpg(estimate.combinedMPG))
            } else {
                Text("Record every drive on a tank to see city and highway MPG.")
                    .foregroundStyle(.secondary)
            }
            if let current = vehicle.currentTankRecording {
                LabeledContent("Current tank") {
                    VStack(alignment: .trailing) {
                        Text("\(current.recordedMiles.formatted(.number.precision(.fractionLength(0)))) mi recorded")
                        if let fraction = current.highwayFraction {
                            Text("\(fraction.formatted(.percent.precision(.fractionLength(0)))) highway")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("City & highway")
        } footer: {
            if let estimate {
                let tanks = "\(estimate.tankCount) tracked tank\(estimate.tankCount == 1 ? "" : "s")"
                let mix = "\(estimate.highwayShare.formatted(.percent.precision(.fractionLength(0)))) highway overall"
                if estimate.isRough {
                    Text("Rough estimate from \(tanks) (\(mix)). City and highway get more accurate as you log tanks with different mixes, like a road trip or an all-city week. Combined is measured.")
                } else {
                    Text("Based on \(tanks) (\(mix)). Combined is measured from those tanks.")
                }
            } else if let current = vehicle.currentTankRecording {
                Text("A tank counts once recorded trips cover at least \(CityHighwayMPG.minimumCoverage.formatted(.percent)) of its miles. This tank started \(current.since.formatted(date: .abbreviated, time: .omitted)); log your next fill-up at the pump.")
            }
        }
    }
}
