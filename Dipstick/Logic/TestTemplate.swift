//
//  TestTemplate.swift
//  Dipstick
//

import Foundation
import SwiftData

/// Built-in tests and inspections, each with its own readings. Specs and
/// how often to test aren't built in: they depend on the car, so they're
/// entered from the manual on the test's reference page.
nonisolated enum TestTemplate {
    struct Template: Identifiable, Equatable {
        let name: String
        let unit: String
        /// One reading per cylinder ("Cylinder 1"…), count set when logging.
        var perCylinder = false
        /// Fixed readings, when not per cylinder.
        var labels: [String] = []
        /// Name of an optional second reading per row: "Wet".
        var secondLabel: String?
        let about: String
        var id: String { name }

        func labels(cylinders: Int) -> [String] {
            perCylinder ? (1...max(1, cylinders)).map { "Cylinder \($0)" } : labels
        }
    }

    static let corners = ["Front left", "Front right", "Rear left", "Rear right"]

    static let builtIn: [Template] = [
        .init(name: "Compression test", unit: "psi", perCylinder: true, secondLabel: "Wet",
              about: "Dry reading per cylinder; add a wet reading (a little oil in the cylinder) to tell rings from valves."),
        .init(name: "Leak-down test", unit: "%", perCylinder: true,
              about: "Percent leakage per cylinder at TDC."),
        .init(name: "Battery and charging", unit: "V",
              labels: ["Resting (engine off)", "While cranking", "Charging (idle)"],
              about: "Battery voltage at rest, while cranking, and with the engine running."),
        .init(name: "Brake pads", unit: "mm", labels: corners,
              about: "Pad material thickness at each wheel."),
        .init(name: "Brake rotors", unit: "mm", labels: corners,
              about: "Rotor thickness at each wheel."),
        .init(name: "Tire tread", unit: "/32 in", labels: corners,
              about: "Tread depth at each tire."),
        .init(name: "Fuel pressure", unit: "psi", labels: ["Key on", "Idle"],
              about: "Fuel rail pressure."),
        .init(name: "Cooling system pressure", unit: "psi", labels: ["Starting pressure", "After 15 minutes"],
              about: "Pressure held by the cooling system."),
    ]

    static func template(named name: String) -> Template? {
        builtIn.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Built-in tests, then any custom ones used on this car.
    static func options<S: Sequence>(addingUsed used: S) -> [String] where S.Element == String {
        ServiceType.options(builtIn: builtIn.map(\.name), addingUsed: used)
    }
}

// MARK: - Spec

nonisolated enum TestSpec {
    struct Spec: Equatable {
        var min: Double?
        var max: Double?
        var maxSpread: Double?
    }

    /// Readings outside spec, by index, with a short reason: "below 135",
    /// "above 14.7", or "spread 32 (max 28)" on the highest and lowest.
    static func problems(_ values: [Double?], spec: Spec) -> [Int: String] {
        var problems: [Int: String] = [:]
        for (i, value) in values.enumerated() {
            guard let value else { continue }
            if let min = spec.min, value < min { problems[i] = "below \(number(min))" }
            if let max = spec.max, value > max { problems[i] = "above \(number(max))" }
        }
        let present = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        if let maxSpread = spec.maxSpread, present.count >= 2,
           let low = present.min(by: { $0.1 < $1.1 }), let high = present.max(by: { $0.1 < $1.1 }),
           high.1 - low.1 > maxSpread {
            let note = "spread \(number(high.1 - low.1)) (max \(number(maxSpread)))"
            problems[low.0] = problems[low.0] ?? note
            problems[high.0] = problems[high.0] ?? note
        }
        return problems
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

// MARK: - Vehicle bridge

extension Vehicle {
    /// Every test of a type on this car, newest first.
    func tests(ofType type: String) -> [TestEntry] {
        (testEntries ?? [])
            .filter { $0.testType.caseInsensitiveCompare(type) == .orderedSame }
            .sorted { ($0.date, $0.odometer) > ($1.date, $1.odometer) }
    }

    /// The reference page for a service or test type, if there is one.
    func referencePage(kind: String, name: String) -> ReferencePage? {
        (referencePages ?? []).first {
            $0.kind == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// The reference page for a type, made (and saved) if there isn't one yet.
    func referencePageCreating(kind: String, name: String, in context: ModelContext) -> ReferencePage {
        if let page = referencePage(kind: kind, name: name) { return page }
        let page = ReferencePage(kind: kind, name: name)
        context.insert(page)
        page.vehicle = self
        return page
    }
}

extension TestEntry {
    /// "165 · 160 · 158 · 162 psi", or the notes when there are no numbers.
    var summary: String? {
        let readings = sortedReadings
        let numbers = readings.compactMap(\.value)
        if !numbers.isEmpty {
            let units = Set(readings.filter { $0.value != nil }.map(\.unit))
            let unit = units.count == 1 ? " \(units.first!)" : ""
            return numbers.map(TestSpec.number).joined(separator: " · ") + unit
        }
        let texts = readings.compactMap(\.text).filter { !$0.isEmpty }
        return texts.isEmpty ? notes : texts.joined(separator: " · ")
    }
}
