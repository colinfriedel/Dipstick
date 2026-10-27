//
//  VehicleListView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Home screen (design board C1a / M): a card per car with its last-tank MPG
/// gauge, due count and odometer, then the "service lamps" list of everything
/// due soon or overdue. Tap a card for its details. Swipe a card right to log
/// a fill-up (opens the pump scanner) or service, left to delete.
struct VehicleListView: View {
    /// A request to log a service, optionally for a specific service type.
    struct ServiceRequest: Identifiable {
        let id = UUID()
        let vehicle: Vehicle
        var serviceType: String?
    }

    /// One due/overdue service on one vehicle, for the service lamps list.
    struct DueRow: Identifiable {
        let vehicle: Vehicle
        let item: MaintenanceDueCalculator.Item<PersistentIdentifier>
        var id: PersistentIdentifier { item.id }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]

    @State private var path: [Vehicle] = []
    @State private var isAdding = false
    @State private var isShowingBackup = false
    @State private var vehicleToDelete: Vehicle?
    @State private var vehicleToFuel: Vehicle?
    @State private var serviceRequest: ServiceRequest?
    #if DEBUG
    @Query(filter: #Predicate<Trip> { $0.vehicle == nil }) private var unassignedTrips: [Trip]
    @State private var isShowingUnassigned = false
    #endif

    /// Everything due soon or overdue, most overdue first across all vehicles.
    private var dueRows: [DueRow] {
        vehicles
            .flatMap { vehicle in
                vehicle.maintenanceDueItems()
                    .filter { $0.status != .ok }
                    .map { DueRow(vehicle: vehicle, item: $0) }
            }
            .sorted { ($0.item.status, -$0.item.urgency) > ($1.item.status, -$1.item.urgency) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                header
                    .plainRow(top: 4, bottom: 10)

                if vehicles.isEmpty {
                    emptyState.plainRow()
                } else {
                    SmallCapsLabel("Vehicles").plainRow(top: 0, bottom: 4)
                    ForEach(vehicles) { vehicle in
                        VehicleCard(vehicle: vehicle)
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(vehicle) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { path.append(vehicle) }
                        .plainRow()
                        .swipeActions(edge: .leading) {
                            Button("Log Fill-Up", systemImage: "fuelpump") { vehicleToFuel = vehicle }
                                .tint(Theme.accent)
                            Button("Log Service", systemImage: "wrench.and.screwdriver") {
                                serviceRequest = ServiceRequest(vehicle: vehicle)
                            }
                            .tint(Theme.amber)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { vehicleToDelete = vehicle }
                                .tint(Theme.red)
                        }
                    }

                    let due = dueRows
                    SectionTitle("Service lamps") {
                        SmallCapsLabel("\(due.count) active")
                    }
                    .plainRow(top: 16, bottom: 4)
                    ServiceLampsPanel(rows: due) { row in
                        serviceRequest = ServiceRequest(vehicle: row.vehicle, serviceType: row.item.serviceType)
                    }
                    .plainRow()
                }

                #if DEBUG
                if !unassignedTrips.isEmpty {
                    DebugDashedRow(title: "Unassigned trips (testing) · \(unassignedTrips.count)") {
                        isShowingUnassigned = true
                    }
                    .plainRow(top: 18)
                }
                #endif
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Vehicle.self) { vehicle in
                VehicleDetailView(vehicle: vehicle)
            }
            .fullScreenCover(isPresented: $isAdding) {
                VehicleFormView()
            }
            .sheet(isPresented: $isShowingBackup) {
                BackupView()
            }
            .fullScreenCover(item: $vehicleToFuel) { vehicle in
                FillUpFlowView(vehicle: vehicle, startInScanner: true)
            }
            .fullScreenCover(item: $serviceRequest) { request in
                MaintenanceEntryFormView(vehicle: request.vehicle, serviceType: request.serviceType)
            }
            #if DEBUG
            .sheet(isPresented: $isShowingUnassigned) {
                NavigationStack {
                    List { UnassignedTripsSection() }
                        .navigationTitle("Unassigned Trips")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            #endif
            .deleteVehicleConfirmation(for: $vehicleToDelete) { vehicle in
                modelContext.delete(vehicle)
                modelContext.saveNow()
            }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack {
            Text("DIPSTICK")
                .font(.dipstick(24, .semibold, relativeTo: .largeTitle))
                .tracking(4)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { isShowingBackup = true } label: {
                Image(systemName: "externaldrive").font(.system(size: 17, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        // Until backups are in iCloud Drive, or when one failed
                        // or isn't uploading.
                        if backupNeedsAttention {
                            Circle().fill(Theme.amber).frame(width: 8, height: 8).offset(x: 5, y: -4)
                        }
                    }
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel(backupNeedsAttention ? "Backup, needs attention" : "Backup")
            Button { isAdding = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
            }
            .buttonStyle(SmallControlButtonStyle(foreground: Theme.accent))
            .accessibilityLabel("Add vehicle")
        }
    }

    private var backupNeedsAttention: Bool { BackupManager.shared.needsAttention }

    private var emptyState: some View {
        VStack(spacing: 16) {
            MPGGauge(mpg: nil, size: 96)
            Text("No vehicles yet")
                .font(.dipstick(18, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.text)
            Text("Add a car to start logging fuel and maintenance.")
                .font(.dipstick(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Add vehicle") { isAdding = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 60)
    }
}

/// One car on Home: gauge, name with due count, model line, odometer. Swipe
/// the card right to log a fill-up or service.
private struct VehicleCard: View {
    let vehicle: Vehicle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let gauge = MPGGauge(mpg: vehicle.mpgSummary.latest, size: 84)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: gauge on top, details full width below.
                VStack(alignment: .leading, spacing: 10) {
                    gauge
                    details
                }
            } else {
                HStack(spacing: 12) {
                    gauge
                    details.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 108)
        .panel()
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        let dueCount = vehicle.maintenanceDueItems().filter { $0.status != .ok }.count
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                vehicle.chip
                Text(vehicle.name.uppercased())
                    .font(.dipstick(17, .semibold, relativeTo: .headline))
                    .tracking(2)
                    .foregroundStyle(Theme.text)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.8)
                if dueCount > 0 {
                    CountPill(count: dueCount)
                }
            }
            if !vehicle.yearMakeModel.isEmpty {
                Text(vehicle.yearMakeModel)
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            OdometerView(miles: vehicle.currentOdometer, size: 22)
                .padding(.top, 3)
        }
    }
}

/// The "service lamps" list: due-soon and overdue services across all cars.
private struct ServiceLampsPanel: View {
    let rows: [VehicleListView.DueRow]
    let onSelect: (VehicleListView.DueRow) -> Void

    var body: some View {
        if rows.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Theme.muted)
                Text("Nothing due")
                    .font(.dipstick(15, relativeTo: .body))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(16)
            .panel()
        } else {
            PanelList(rows) { row in
                Button { onSelect(row) } label: { ServiceLampRow(row: row) }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Logs this service")
            }
        }
    }
}

private struct ServiceLampRow: View {
    let row: VehicleListView.DueRow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let item = row.item
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(systemName: item.status.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.status.tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(item.status.tint.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.status.tint.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.serviceType)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 5) {
                    CarChip(colorHex: row.vehicle.colorHex, size: 8)
                    Text("\(row.vehicle.name) · Last done \(item.lastDone.formatted(.dateTime.month(.abbreviated).year()))".uppercased())
                        .font(.dipstick(10, .semibold, relativeTo: .caption2))
                        .tracking(1)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.8)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }

            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                Text(item.shortSummary.uppercased())
                    .font(.readout(12, relativeTo: .caption))
                    .foregroundStyle(item.status.tint)
                Text(item.dueLabel.uppercased())
                    .font(.readout(10, relativeTo: .caption2))
                    .foregroundStyle(Theme.muted)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A dashed, out-of-the-way row for Debug-only tools.
struct DebugDashedRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.panelBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

extension View {
    /// Asks before deleting, since deleting a vehicle will also delete its fuel and
    /// maintenance history once those exist.
    func deleteVehicleConfirmation(
        for vehicle: Binding<Vehicle?>,
        onDelete: @escaping (Vehicle) -> Void
    ) -> some View {
        confirmationDialog(
            "Delete \(vehicle.wrappedValue?.name ?? "vehicle")?",
            isPresented: Binding(
                get: { vehicle.wrappedValue != nil },
                set: { if !$0 { vehicle.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: vehicle.wrappedValue
        ) { target in
            Button("Delete Vehicle", role: .destructive) { onDelete(target) }
        } message: { _ in
            Text("This also deletes all of its fuel and maintenance records. This can't be undone.")
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(Vehicle(name: "Daily Driver", year: 2019, make: "Honda", model: "Civic", currentOdometer: 48_210))
    container.mainContext.insert(Vehicle(name: "Project Car", year: 1994, make: "Mazda", model: "Miata", currentOdometer: 131_870))
    return VehicleListView()
        .modelContainer(container)
}
