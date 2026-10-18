//
//  MPGGauge.swift
//  Dipstick
//

import SwiftUI

/// The home card gauge: a 270° arc (open at the bottom) with tick marks, the
/// value arc in the accent, and the MPG number in the middle. Without a value
/// it draws only the empty track and a dash.
struct MPGGauge: View {
    let mpg: Double?
    var size: CGFloat = 84
    /// MPG at a full sweep.
    static let fullScale = 40.0

    private let sweep = 0.75            // 270° of the circle
    private let startRotation = 135.0   // starts at 7:30, opens at the bottom
    private let tickCount = 28

    private var fraction: Double {
        guard let mpg else { return 0 }
        return min(max(mpg / Self.fullScale, 0), 1)
    }

    var body: some View {
        let lineWidth = size * 0.045
        let ringInset = size * 0.1

        ZStack {
            ticks
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Theme.gaugeTick, style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))
                .rotationEffect(.degrees(startRotation))
                .padding(ringInset)
            if mpg != nil {
                Circle()
                    .trim(from: 0, to: sweep * fraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(startRotation))
                    .padding(ringInset)
            }
            VStack(spacing: 0) {
                MonoNumber(text: mpg.map { String(format: "%.1f", $0) } ?? "--.-",
                           size: size * 0.24, color: mpg == nil ? Theme.gaugeEmpty : Theme.text)
                Text("MPG")
                    .font(.dipstick(size * 0.085, .semibold, relativeTo: .caption2))
                    .tracking(1)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mpg.map { "Last tank \(String(format: "%.1f", $0)) miles per gallon" } ?? "No MPG yet")
    }

    private func tickAngle(_ index: Int) -> Double {
        startRotation + 270 * Double(index) / Double(tickCount)
    }

    private var tick: some View {
        let length: CGFloat = size * 0.055
        let thickness: CGFloat = max(1, size * 0.014)
        let radius: CGFloat = size / 2 - size * 0.03
        return Capsule()
            .fill(Theme.gaugeTick)
            .frame(width: length, height: thickness)
            .offset(x: radius)
    }

    /// Short marks around the outside of the arc.
    private var ticks: some View {
        ZStack {
            ForEach(0...tickCount, id: \.self) { index in
                tick.rotationEffect(.degrees(tickAngle(index)))
            }
        }
    }
}
