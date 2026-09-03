import Testing
@testable import Dipstick

@MainActor
struct VehicleFormViewModelTests {

    @Test func createTrimsNameAndSendsBlankOptionalFieldsAsNil() async {
        let repo = InMemoryVehicleRepository(vehicles: [])
        let viewModel = VehicleFormViewModel(mode: .create, repository: repo)
        viewModel.name = "  Track Car  "
        viewModel.year = "2001"
        viewModel.make = "   "          // blank -> nil
        viewModel.odometer = "12345"

        let saved = await viewModel.save()

        #expect(saved?.name == "Track Car")
        #expect(saved?.year == 2001)
        #expect(saved?.make == nil)
        #expect(saved?.currentOdometer == 12345)
        #expect(viewModel.saveError == nil)
    }

    @Test func editModePrefillsEveryField() {
        let vehicle = Vehicle(id: 7, name: "Van", year: 2010, make: "Ford",
                              model: "E-350", vin: "1FTSE3", currentOdometer: 99_000)
        let viewModel = VehicleFormViewModel(mode: .edit(vehicle), repository: InMemoryVehicleRepository())

        #expect(viewModel.name == "Van")
        #expect(viewModel.year == "2010")
        #expect(viewModel.make == "Ford")
        #expect(viewModel.vin == "1FTSE3")
        #expect(viewModel.odometer == "99000")
        #expect(viewModel.title == "Edit Vehicle")
    }

    @Test func editModeSavesThroughUpdate() async {
        let repo = InMemoryVehicleRepository()
        let original = try? await repo.list().first
        let viewModel = VehicleFormViewModel(mode: .edit(original!), repository: repo)
        viewModel.currentOdometerBump()

        let saved = await viewModel.save()

        #expect(saved?.id == original?.id)
        #expect(saved?.currentOdometer == (original!.currentOdometer + 1))
    }

    @Test func cannotSaveWithBlankName() {
        let viewModel = VehicleFormViewModel(mode: .create, repository: InMemoryVehicleRepository())
        viewModel.name = "   "
        #expect(viewModel.canSave == false)

        viewModel.name = "OK"
        #expect(viewModel.canSave == true)
    }

    @Test func invalidNumbersFallBackSafely() async {
        let repo = InMemoryVehicleRepository(vehicles: [])
        let viewModel = VehicleFormViewModel(mode: .create, repository: repo)
        viewModel.name = "Beater"
        viewModel.year = "not a year"
        viewModel.odometer = ""

        let saved = await viewModel.save()

        #expect(saved?.year == nil)
        #expect(saved?.currentOdometer == 0)
    }
}

private extension VehicleFormViewModel {
    /// Test helper: nudge the odometer field up by one.
    func currentOdometerBump() {
        odometer = String((Int(odometer) ?? 0) + 1)
    }
}
