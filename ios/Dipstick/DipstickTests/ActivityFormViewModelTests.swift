import Foundation
import Testing
@testable import Dipstick

@MainActor
struct FuelEntryFormViewModelTests {

    @Test func cannotSaveUntilRequiredFieldsAreValid() {
        let vm = FuelEntryFormViewModel(vehicleID: 1, repository: InMemoryActivityRepository())
        #expect(vm.canSave == false)

        vm.odometer = "62000"
        vm.gallons = "10.5"
        vm.totalCost = "38.20"
        #expect(vm.canSave == true)

        vm.gallons = "0"
        #expect(vm.canSave == false)
    }

    @Test func savesTotalCostInTotalMode() async {
        let repo = InMemoryActivityRepository(fuel: [:], maintenance: [:])
        let vm = FuelEntryFormViewModel(vehicleID: 5, repository: repo)
        vm.odometer = "62000"
        vm.gallons = "10"
        vm.costMode = .total
        vm.totalCost = "35"

        #expect(await vm.save())

        let saved = try? await repo.fuelEntries(vehicleID: 5).first
        #expect(saved?.totalCost == 35)
        #expect(saved?.isFullTank == true)
    }

    @Test func derivesCostFromPerGallonMode() async {
        let repo = InMemoryActivityRepository(fuel: [:], maintenance: [:])
        let vm = FuelEntryFormViewModel(vehicleID: 5, repository: repo)
        vm.odometer = "62000"
        vm.gallons = "10"
        vm.costMode = .perGallon
        vm.pricePerGallon = "3.50"
        vm.isFullTank = false

        #expect(await vm.save())

        let saved = try? await repo.fuelEntries(vehicleID: 5).first
        #expect(saved?.totalCost == 35)
        #expect(saved?.isFullTank == false)
    }
}

@MainActor
struct MaintenanceEntryFormViewModelTests {

    private func validVM(repo: InMemoryActivityRepository? = nil) -> MaintenanceEntryFormViewModel {
        let repo = repo ?? InMemoryActivityRepository(fuel: [:], maintenance: [:])
        let vm = MaintenanceEntryFormViewModel(vehicleID: 1, repository: repo)
        vm.odometer = "50000"
        vm.serviceTypeChoice = "Oil change"
        vm.cost = "60"
        return vm
    }

    @Test func flagsMissingOdometer() {
        let vm = MaintenanceEntryFormViewModel(vehicleID: 1, repository: InMemoryActivityRepository())
        #expect(vm.validationProblem != nil)
    }

    @Test func nextDueMileageMustExceedOdometer() {
        let vm = validVM()
        vm.setNextDueByMileage = true
        vm.nextDueOdometer = "49000"
        #expect(vm.validationProblem != nil)

        vm.nextDueOdometer = "55000"
        #expect(vm.validationProblem == nil)
    }

    @Test func nextDueDateMustBeAfterServiceDate() {
        let vm = validVM()
        vm.date = .now
        vm.setNextDueByDate = true
        vm.nextDueDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        #expect(vm.validationProblem != nil)
    }

    @Test func everyPartNeedsAName() {
        let vm = validVM()
        vm.addPart()
        #expect(vm.parts.count == 1)
        #expect(vm.validationProblem != nil)   // blank name

        vm.parts[0].name = "Filter"
        #expect(vm.validationProblem == nil)

        vm.removeParts(at: IndexSet(integer: 0))
        #expect(vm.parts.isEmpty)
    }

    @Test func customServiceTypeIsUsedWhenOtherIsSelected() async {
        let repo = InMemoryActivityRepository(fuel: [:], maintenance: [:])
        let vm = validVM(repo: repo)
        vm.serviceTypeChoice = MaintenanceEntryFormViewModel.otherServiceType
        vm.customServiceType = "  Timing belt  "

        #expect(vm.resolvedServiceType == "Timing belt")
        #expect(await vm.save())

        let saved = try? await repo.maintenanceEntries(vehicleID: 1).first
        #expect(saved?.serviceType == "Timing belt")
    }
}
