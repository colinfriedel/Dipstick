import Foundation

/// Backs the "log a fill-up" form.
@Observable
@MainActor
final class FuelEntryFormViewModel {
    enum CostMode: String, CaseIterable {
        case total = "Total cost"
        case perGallon = "Price / gal"
    }

    var date = Date()
    var odometer = ""
    var gallons = ""
    var costMode: CostMode = .total
    var totalCost = ""
    var pricePerGallon = ""
    var isFullTank = true
    var stationName = ""
    var notes = ""

    private(set) var isSaving = false
    var saveError: String?

    let vehicleID: Int
    private let repository: any ActivityRepository

    init(vehicleID: Int, repository: (any ActivityRepository)? = nil) {
        self.vehicleID = vehicleID
        self.repository = repository ?? AppEnvironment.activityRepository
    }

    private var costValue: Double? {
        switch costMode {
        case .total: Double(totalCost)
        case .perGallon: Double(pricePerGallon)
        }
    }

    var canSave: Bool {
        guard !isSaving,
              let odo = Int(odometer), odo > 0,
              let gal = Double(gallons), gal > 0,
              let cost = costValue, cost >= 0
        else { return false }
        return true
    }

    /// Returns true on success; on failure sets `saveError` and returns false.
    func save() async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let input = FuelEntryInput(
            date: CalendarDate(date),
            odometer: Int(odometer) ?? 0,
            gallons: Double(gallons) ?? 0,
            totalCost: costMode == .total ? costValue : nil,
            pricePerGallon: costMode == .perGallon ? costValue : nil,
            isFullTank: isFullTank,
            stationName: stationName.nilIfBlank,
            notes: notes.nilIfBlank
        )

        do {
            _ = try await repository.createFuelEntry(vehicleID: vehicleID, input)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}
