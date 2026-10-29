//
//  FuelStatsSection.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import Charts

/// Stats tab of vehicle detail (design board F / P, with City · Highway ·
/// Combined tiles in place of the board's summary tiles, which now live on
/// the Fuel tab): city/highway MPG with current-tank progress, the MPG trend
/// chart, fuel spend, and the car's recorded drives.
struct FuelStatsSection: View {
    let vehicle: Vehicle

    enum Range: String, CaseIterable, Identifiable {
        case sixMonths = "6M", year = "1Y", all = "ALL"
        var id: Self { self }

        var start: Date? {
            switch self {
            case .sixMonths: Calendar.current.date(byAdding: .month, value: -6, to: .now)
            case .year: Calendar.current.date(byAdding: .year, value: -1, to: .now)
            case .all: nil
            }
        }
    }

    @State private var range: Range = .all
    @State private var isShowingTrips = false
    @State private var isShowingRecorder = false
    @State private var isShowingSetup = false
    @State private var isShowingLearnMore = false
    @Environment(TripRecorder.self) private var recorder

    var body: some View {
        let stats = vehicle.fuelStats()
        let estimate = CityHighwayMPG.estimate(from: vehicle.trackedTanks)
        let hasTrips = !(vehicle.trips ?? []).isEmpty

        Section {
            TileRow {
                ReadoutTile("City") { MPGReadout(value: estimate?.cityMPG) }
                ReadoutTile("Highway") { MPGReadout(value: estimate?.highwayMPG) }
                ReadoutTile("Combined", highlighted: true) {
                    // Measured from tracked tanks; all-time MPG until there are any.
                    MPGReadout(value: estimate?.combinedMPG ?? stats.averageMPG, color: Theme.accent)
                }
            }
            .plainRow(top: 12, bottom: 2)

            Text(estimateCaption(estimate, hasTrips: hasTrips))
                .font(.dipstick(11.5, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .plainRow(top: 4, bottom: 6)

            // Until drives are set up: right under the numbers they unlock.
            TripSetupCard(vehicle: vehicle, onSetUp: { isShowingSetup = true }, onLearnMore: { isShowingLearnMore = true })
                .plainRow(top: 4, bottom: 6)
                .sheet(isPresented: $isShowingSetup) { TripSetupView(vehicle: vehicle) }
                .sheet(isPresented: $isShowingLearnMore) { TripsLearnMoreView() }

            if hasTrips, let current = vehicle.currentTankRecording {
                CurrentTankBar(tank: current)
                    .plainRow(top: 6, bottom: 10)
            }

            trendHeader.plainRow(top: 12, bottom: 6)
            trendPanel(stats: stats).plainRow(top: 0, bottom: 6)

            SectionTitle("Fuel spend").plainRow(top: 12, bottom: 6)
            FuelSpendPanel(stats: stats).plainRow(top: 0, bottom: 4)
            if stats.unknownCostCount > 0 {
                Text("\(stats.unknownCostCount) fill-up\(stats.unknownCostCount == 1 ? "" : "s") with no recorded cost \(stats.unknownCostCount == 1 ? "isn't" : "aren't") included.")
                    .font(.dipstick(11.5, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .plainRow(top: 2, bottom: 6)
            }

            SectionTitle("Drives") {
                Button("How it works") { isShowingLearnMore = true }
                    .font(.dipstick(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(Theme.accentText)
                    .buttonStyle(.borderless)
            }
            .plainRow(top: 14, bottom: 6)
            // The sheets sit on this row, not the Section: a modifier on a
            // Section is copied onto every row.
            DrivesPanel(vehicle: vehicle, onShowAll: { isShowingTrips = true }) {
                if !recorder.isRecording { recorder.start(for: vehicle) }
                isShowingRecorder = true
            }
            .plainRow(top: 0, bottom: 16)
            .sheet(isPresented: $isShowingTrips) {
                TripsListView(vehicle: vehicle)
            }
            .fullScreenCover(isPresented: $isShowingRecorder) {
                TripRecordingView()
            }
        }
    }

    private func estimateCaption(_ estimate: CityHighwayMPG.Estimate?, hasTrips: Bool) -> String {
        guard let estimate else {
            return hasTrips
                ? "City and highway appear after a tank whose drives were recorded · Combined is all-time"
                : "Record drives to see city and highway MPG · Combined is all-time"
        }
        let tanks = "\(estimate.tankCount) tank\(estimate.tankCount == 1 ? "" : "s") tracked"
        return estimate.isRough ? "Rough estimate · \(tanks) so far" : "Based on \(tanks)"
    }

    private var trendHeader: some View {
        HStack {
            SectionTitle("MPG per fill-up")
            HStack(spacing: 6) {
                ForEach(Range.allCases) { option in
                    Button { range = option } label: {
                        Text(option.rawValue)
                            .font(.dipstick(12, .semibold, relativeTo: .caption))
                            .foregroundStyle(range == option ? Theme.text : Theme.muted)
                            .frame(minWidth: 40, minHeight: 32)
                            .background(Capsule().fill(range == option ? Theme.selectedFill : Theme.panel))
                            .overlay(Capsule().strokeBorder(range == option ? Theme.accent : Theme.panelBorder,
                                                            lineWidth: range == option ? 1.5 : 1))
                            .contentShape(Capsule())
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Show \(option == .all ? "all time" : option == .year ? "last year" : "last 6 months")")
                    .accessibilityAddTraits(range == option ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private func trendPanel(stats: FuelStats) -> some View {
        let tanks = stats.tanks.filter { tank in range.start.map { tank.date >= $0 } ?? true }
        Group {
            if tanks.count < 3 {
                Text("Log a few more tanks to see a trend")
                    .font(.dipstick(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                MPGTrendChart(tanks: tanks, average: MPGCalculator.average(of: tanks.map(\.result)))
                    .frame(height: 180)
            }
        }
        .padding(14)
        .panel()
    }
}

/// CURRENT TANK: recorded miles and highway share since the last full fill-up,
/// as a city/highway split bar.
private struct CurrentTankBar: View {
    let tank: CityHighwayMPG.CurrentTank

    var body: some View {
        let fraction = tank.highwayFraction ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SmallCapsLabel("Current tank")
                Spacer()
                Text("\(tank.recordedMiles.formatted(.number.precision(.fractionLength(1)))) mi recorded · \(fraction.formatted(.percent.precision(.fractionLength(0)))) highway")
                    .font(.dipstick(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(Theme.text)
            }
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.faint)
                    Rectangle().fill(Theme.accent)
                        .frame(width: proxy.size.width * fraction)
                }
                .clipShape(Capsule())
                .opacity(tank.recordedMiles > 0 ? 1 : 0.35)
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One point per full tank, accent line, dashed average with an AVG label,
/// the latest tank emphasized. Tap a point for its date and MPG.
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
        let padding = max((high - low) * 0.25, 1.5)
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
        let latest = tanks.max { $0.date < $1.date }
        Chart {
            ForEach(tanks) { tank in
                LineMark(x: .value("Date", tank.date), y: .value("MPG", tank.mpg))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Date", tank.date), y: .value("MPG", tank.mpg))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(tank.id == latest?.id ? 0 : 22)
            }
            if let latest {
                PointMark(x: .value("Date", latest.date), y: .value("MPG", latest.mpg))
                    .symbol {
                        Circle().fill(Theme.accent)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Theme.panel, lineWidth: 2.5))
                    }
                    .annotation(position: .bottom, alignment: .trailing, spacing: 6) {
                        Text(String(format: "%.1f", latest.mpg))
                            .font(.readout(12, relativeTo: .caption))
                            .foregroundStyle(Theme.text)
                    }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("AVG \(String(format: "%.1f", average))")
                            .font(.readout(10, relativeTo: .caption2))
                            .foregroundStyle(Theme.muted)
                    }
            }
            if let tank = selectedTank {
                RuleMark(x: .value("Date", tank.date))
                    .foregroundStyle(Theme.muted.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                        VStack(spacing: 2) {
                            MonoNumber(text: String(format: "%.1f", tank.mpg), size: 14)
                            Text(tank.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.dipstick(10, relativeTo: .caption2))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.panelBorder, lineWidth: 1))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Theme.divider)
            }
        }
        .chartXAxis {
            AxisMarks(values: [tanks.first?.date, tanks.last?.date].compactMap { $0 }) { value in
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) {
                    if let date = value.as(Date.self) {
                        Text(date, format: value.index == 0 ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day())
                            .font(.dipstick(10, relativeTo: .caption2))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
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
        .accessibilityLabel("MPG per fill-up")
    }
}

/// THIS YEAR and ALL-TIME spend beside monthly bars for the last six months
/// (current month in the accent).
private struct FuelSpendPanel: View {
    let stats: FuelStats

    var body: some View {
        let months = Array(stats.monthlySpend.suffix(6))
        let peak = max(months.map(\.total).max() ?? 0, 1)

        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    SmallCapsLabel("This year")
                    MonoNumber(text: Units.currency(stats.spendThisYear), size: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    SmallCapsLabel("All-time")
                    MonoNumber(text: Units.currency(stats.totalSpend), size: 22)
                }
            }
            .layoutPriority(1)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                    let isCurrent = index == months.count - 1
                    VStack(spacing: 3) {
                        Text(month.total > 0 ? "$\(Int(month.total.rounded()))" : "")
                            .font(.readout(9, relativeTo: .caption2))
                            .foregroundStyle(isCurrent ? Theme.text : Theme.muted)
                            .lineLimit(1)
                            .fixedSize()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isCurrent ? Theme.accent : Theme.faint)
                            .frame(height: max(2, 64 * month.total / peak))
                        Text(month.month, format: .dateTime.month(.abbreviated))
                            .font(.dipstick(9, relativeTo: .caption2))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
        .padding(14)
        .panel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fuel spend: \(Units.currency(stats.spendThisYear)) this year, \(Units.currency(stats.totalSpend)) all time")
    }
}
