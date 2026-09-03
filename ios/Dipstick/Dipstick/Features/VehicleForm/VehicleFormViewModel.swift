import Foundation

/// Whether the form is creating a new vehicle or editing an existing one.
enum VehicleFormMode {
    case create
    case edit(Vehicle)

    var title: String {
        switch self {
        case .create: "New Vehicle"
        case .edit: "Edit Vehicle"
        }
    }
}

/// Backs the add/edit form. Holds the field text as `String`s (that's what
/// `TextField` binds to), validates, and converts to a `VehicleInput` on save.
@Observable
@MainActor
final class VehicleFormViewModel {
    var name = ""
    var year = ""
    var make = ""
    var model = ""
    var vin = ""
    var odometer = ""

    private(set) var isSaving = false
    var saveError: String?

    private let mode: VehicleFormMode
    private let repository: any VehicleRepository

    init(mode: VehicleFormMode, repository: any VehicleRepository = AppEnvironment.vehicleRepository) {
        self.mode = mode
        self.repository = repository

        if case .edit(let vehicle) = mode {
            name = vehicle.name
            year = vehicle.year.map(String.init) ?? ""
            make = vehicle.make ?? ""
            model = vehicle.model ?? ""
            vin = vehicle.vin ?? ""
            odometer = String(vehicle.currentOdometer)
        }
    }

    var title: String { mode.title }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// Persists the vehicle. Returns the saved value on success, or `nil` after
    /// setting `saveError`.
    func save() async -> Vehicle? {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let input = VehicleInput(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            year: Int(year.trimmingCharacters(in: .whitespaces)),
            make: cleaned(make),
            model: cleaned(model),
            vin: cleaned(vin),
            currentOdometer: Int(odometer.trimmingCharacters(in: .whitespaces)) ?? 0
        )

        do {
            switch mode {
            case .create:
                return try await repository.create(input)
            case .edit(let vehicle):
                return try await repository.update(id: vehicle.id, with: input)
            }
        } catch {
            saveError = error.localizedDescription
            return nil
        }
    }

    /// Trims a field and turns "" into nil, so blank optional fields are sent as
    /// null rather than empty strings.
    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
