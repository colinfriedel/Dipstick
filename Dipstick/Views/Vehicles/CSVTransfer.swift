//
//  CSVTransfer.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A vehicle's records as a .csv file for the share sheet. The text is built
/// when the menu opens; the file is written only when the user shares.
nonisolated struct CSVExportFile: Transferable {
    let filename: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.filename)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.filename }
    }
}

extension Vehicle {
    var csvExportFile: CSVExportFile {
        let day = RecordCSV.format(Date(), .current)
        let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        return CSVExportFile(filename: "Dipstick \(safeName) \(day).csv", text: exportCSV())
    }
}

/// Shows what an imported file contains before anything is saved: how many new
/// fill-ups and services, how many duplicates will be skipped, and any rows
/// that couldn't be read.
struct ImportPreviewView: View {
    let vehicle: Vehicle
    let filename: String
    let parsed: RecordCSV.Parsed

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = vehicle.importPlan(for: parsed)
        let total = plan.fuel.count + plan.services.count

        NavigationStack {
            List {
                Section {
                    LabeledContent("Fill-ups", value: String(plan.fuel.count))
                    LabeledContent("Services", value: String(plan.services.count))
                    if plan.duplicates > 0 {
                        LabeledContent("Already in log (skipped)", value: String(plan.duplicates))
                    }
                } header: {
                    Text("To import into \(vehicle.name)")
                } footer: {
                    Text(filename)
                }

                if !parsed.problems.isEmpty {
                    Section {
                        ForEach(parsed.problems, id: \.row) { problem in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Row \(problem.row)").font(.subheadline.bold())
                                Text(problem.message).font(.subheadline)
                            }
                        }
                    } header: {
                        Label("\(parsed.problems.count) row\(parsed.problems.count == 1 ? "" : "s") can't be read", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("These rows will be skipped. Fix them in the file and import again; rows already imported won't be duplicated.")
                    }
                }

                if total > 0 {
                    Section("Preview") {
                        ForEach(Array(plan.fuel.prefix(3).enumerated()), id: \.offset) { _, row in
                            Text("Fill-up · \(row.date.formatted(date: .abbreviated, time: .omitted)) · \(Units.miles(row.odometer)) · \(Units.gallons(row.gallons))")
                                .font(.subheadline)
                        }
                        ForEach(Array(plan.services.prefix(3).enumerated()), id: \.offset) { _, row in
                            Text("\(row.serviceType) · \(row.date.formatted(date: .abbreviated, time: .omitted)) · \(Units.miles(row.odometer))")
                                .font(.subheadline)
                        }
                        if total > 6 {
                            Text("…and \(total - min(plan.fuel.count, 3) - min(plan.services.count, 3)) more")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(total == 0 ? "Nothing to Import" : "Import \(total)") {
                        vehicle.importRecords(fuel: plan.fuel, services: plan.services, into: modelContext)
                        dismiss()
                    }
                    .disabled(total == 0)
                }
            }
        }
    }
}
