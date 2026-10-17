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
            navRow.plainRow(top: 4, bottom: 6)
            titleBlock.plainRow(top: 6, bottom: 10)

            TabSwitch(tabs: Log.allCases, selection: $log) { $0.rawValue }
                .plainRow(top: 4, bottom: 4)

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
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            readImport(result)
        }
        .fullScreenCover(item: $importFile) { file in
            ImportPreviewView(vehicle: vehicle, filename: file.filename, parsed: file.parsed) {
                // Change file: reopen the picker once the preview has closed.
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    isImporting = true
                }
            }
        }
        .alert("Couldn't read file", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
        .fullScreenCover(isPresented: $isEditing) {
            VehicleFormView(vehicle: vehicle)
        }
        .sheet(isPresented: $isUpdatingOdometer) {
            OdometerUpdateView(vehicle: vehicle)
        }
        .fullScreenCover(isPresented: $isLoggingFuel) {
            FillUpFlowView(vehicle: vehicle)
        }
        .fullScreenCover(item: $editingFuelEntry) { entry in
            FillUpFlowView(vehicle: vehicle, entry: entry)
        }
        .fullScreenCover(isPresented: $isLoggingService) {
            MaintenanceEntryFormView(vehicle: vehicle)
        }
        .fullScreenCover(item: $editingServiceEntry) { entry in
            MaintenanceEntryFormView(vehicle: vehicle, entry: entry)
        }
        .deleteVehicleConfirmation(for: $vehicleToDelete) { vehicle in
            dismiss()
            modelContext.delete(vehicle)
            modelContext.saveNow()
        }
    }

    // MARK: Header

    private var navRow: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("Back")

            Spacer()

            Button("Edit") { isEditing = true }
                .buttonStyle(SmallControlButtonStyle())

            Menu {
                ShareLink(item: vehicle.csvExportFile, preview: SharePreview("\(vehicle.name) records")) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                Button("Import CSV…", systemImage: "square.and.arrow.down") { isImporting = true }
                Divider()
                Button("Delete Vehicle", systemImage: "trash", role: .destructive) { vehicleToDelete = vehicle }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("More")
        }
    }

    private var titleBlock: some View {
        let dueCount = vehicle.maintenanceDueItems().filter { $0.status != .ok }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                CarChip(colorHex: vehicle.colorHex, size: 14)
                Text(vehicle.name.uppercased())
                    .font(.dipstick(30, .semibold, relativeTo: .largeTitle))
                    .tracking(2)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if dueCount > 0 {
                    CountPill(count: dueCount)
                }
            }
            if !vehicle.yearMakeModel.isEmpty {
                Text(vehicle.yearMakeModel)
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 4) {
                OdometerView(miles: vehicle.currentOdometer, size: 24)
                Button { isUpdatingOdometer = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Update odometer")
            }
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
        .environment(TripRecorder.shared)
}
