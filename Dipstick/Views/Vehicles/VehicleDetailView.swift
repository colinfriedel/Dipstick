//
//  VehicleDetailView.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// One vehicle's details, with a switch between its fuel log, maintenance log
/// and stats.
struct VehicleDetailView: View {
    let vehicle: Vehicle

    enum Log: String, CaseIterable, Identifiable {
        case fuel = "Fuel"
        case maintenance = "Maintenance"
        case stats = "Stats"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var vehicleToDelete: Vehicle?
    @State private var isLoggingFuel = false
    @State private var editingFuelEntry: FuelEntry?
    @State private var isLoggingService = false
    @State private var editingServiceEntry: MaintenanceEntry?
    @State private var log: Log = .fuel
    @State private var isUpdatingOdometer = false
    @State private var isImporting = false
    @State private var importFile: ImportFile?
    @State private var importError: String?

    /// A CSV the user picked, parsed and waiting for confirmation.
    struct ImportFile: Identifiable {
        let id = UUID()
        let filename: String
        let parsed: RecordCSV.Parsed
    }

    var body: some View {
        List {
            Section {
                Button { isUpdatingOdometer = true } label: {
                    LabeledContent("Odometer") {
                        HStack(spacing: 4) {
                            Text(Units.miles(vehicle.currentOdometer))
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .tint(.primary)
                .accessibilityHint("Update the odometer reading")
                if let year = vehicle.year {
                    LabeledContent("Year", value: String(year))
                }
                if let make = vehicle.make {
                    LabeledContent("Make", value: make)
                }
                if let model = vehicle.model {
                    LabeledContent("Model", value: model)
                }
                if let vin = vehicle.vin {
                    LabeledContent("VIN") {
                        Text(vin)
                            .textSelection(.enabled)
                    }
                }
            }

            Picker("Log", selection: $log) {
                ForEach(Log.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch log {
            case .fuel:
                FuelHistorySection(
                    vehicle: vehicle,
                    onLog: { isLoggingFuel = true },
                    onEdit: { editingFuelEntry = $0 }
                )
            case .maintenance:
                MaintenanceHistorySection(
                    vehicle: vehicle,
                    onLog: { isLoggingService = true },
                    onEdit: { editingServiceEntry = $0 }
                )
            case .stats:
                FuelStatsSection(vehicle: vehicle)
            }

            Section {
                Button("Delete Vehicle", role: .destructive) {
                    vehicleToDelete = vehicle
                }
            }
        }
        .navigationTitle(vehicle.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    ShareLink(item: vehicle.csvExportFile, preview: SharePreview("\(vehicle.name) records")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    Button("Import CSV…", systemImage: "square.and.arrow.down") { isImporting = true }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            readImport(result)
        }
        .sheet(item: $importFile) { file in
            ImportPreviewView(vehicle: vehicle, filename: file.filename, parsed: file.parsed)
        }
        .alert("Couldn't read file", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $isEditing) {
            VehicleFormView(vehicle: vehicle)
        }
        .sheet(isPresented: $isUpdatingOdometer) {
            OdometerUpdateView(vehicle: vehicle)
        }
        .sheet(isPresented: $isLoggingFuel) {
            FuelEntryFormView(vehicle: vehicle)
        }
        .sheet(item: $editingFuelEntry) { entry in
            FuelEntryFormView(vehicle: vehicle, entry: entry)
        }
        .sheet(isPresented: $isLoggingService) {
            MaintenanceEntryFormView(vehicle: vehicle)
        }
        .sheet(item: $editingServiceEntry) { entry in
            MaintenanceEntryFormView(vehicle: vehicle, entry: entry)
        }
        .deleteVehicleConfirmation(for: $vehicleToDelete) { vehicle in
            dismiss()
            modelContext.delete(vehicle)
        }
    }

    private func readImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // Files from the picker are outside the app's sandbox; ask for access.
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            importFile = ImportFile(filename: url.lastPathComponent, parsed: RecordCSV.decode(text))
        } catch {
            importError = error.localizedDescription
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let vehicle = Vehicle(name: "Project Car", year: 1994, make: "Mazda", model: "Miata", vin: "JM1NA3510R0512345", currentOdometer: 131_870)
    container.mainContext.insert(vehicle)
    return NavigationStack { VehicleDetailView(vehicle: vehicle) }
        .modelContainer(container)
}
