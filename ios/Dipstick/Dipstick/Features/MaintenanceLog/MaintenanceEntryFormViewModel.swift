import Foundation

/// Backs the "log a service" form, including the repeatable parts list and the
/// optional "next due" targets.
@Observable
@MainActor
final class MaintenanceEntryFormViewModel {
    var date = Date()
    var odometer = ""

    /// One of `ServiceType.common`, or the sentinel "Other" meaning use `customServiceType`.
    var serviceTypeChoice = ServiceType.common[0]
    var customServiceType = ""

    var cost = ""
    var parts: [Part] = []
    var notes = ""

    var setNextDueByMileage = false
    var nextDueOdometer = ""

    var setNextDueByDate = false
    var nextDueDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now

    private(set) var isSaving = false
    var saveError: String?

    let vehicleID: Int
    private let repository: any ActivityRepository

    init(vehicleID: Int, repository: (any ActivityRepository)? = nil) {
        self.vehicleID = vehicleID
        self.repository = repository ?? AppEnvironment.activityRepository
    }

    static let otherServiceType = "Other"

    var isCustomServiceType: Bool { serviceTypeChoice == Self.otherServiceType }

    var resolvedServiceType: String {
        isCustomServiceType ? customServiceType.trimmingCharacters(in: .whitespacesAndNewlines) : serviceTypeChoice
    }

    func addPart() {
        parts.append(Part(name: "", cost: 0))
    }

    func removeParts(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            parts.remove(at: index)
        }
    }

    var validationProblem: String? {
        guard let odo = Int(odometer), odo > 0 else { return "Enter an odometer reading." }
        if resolvedServiceType.isEmpty { return "Enter a service type." }
        if let c = Double(cost), c < 0 { return "Cost can't be negative." }
        if parts.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Every part needs a name."
        }
        if setNextDueByMileage {
            guard let due = Int(nextDueOdometer), due > odo else {
                return "Next-due mileage must be above the current odometer."
            }
        }
        if setNextDueByDate, CalendarDate(nextDueDate) <= CalendarDate(date) {
            return "Next-due date must be after the service date."
        }
        return nil
    }

    var canSave: Bool { !isSaving && validationProblem == nil }

    func save() async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let cleanedParts = parts.map {
            Part(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), cost: $0.cost)
        }

        let input = MaintenanceEntryInput(
            date: CalendarDate(date),
            odometer: Int(odometer) ?? 0,
            serviceType: resolvedServiceType,
            cost: Double(cost) ?? 0,
            partsUsed: cleanedParts.isEmpty ? nil : cleanedParts,
            notes: notes.nilIfBlank,
            nextDueOdometer: setNextDueByMileage ? Int(nextDueOdometer) : nil,
            nextDueDate: setNextDueByDate ? CalendarDate(nextDueDate) : nil
        )

        do {
            _ = try await repository.createMaintenanceEntry(vehicleID: vehicleID, input)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}
