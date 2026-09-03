import SwiftUI

/// A modal form for creating or editing a vehicle. Presented as a sheet from the
/// list (create) and the detail screen (edit).
struct VehicleFormView: View {
    @State private var viewModel: VehicleFormViewModel
    @Environment(\.dismiss) private var dismiss

    /// Called with the saved vehicle after a successful create/update.
    let onSaved: (Vehicle) -> Void

    init(
        mode: VehicleFormMode,
        repository: (any VehicleRepository)? = nil,
        onSaved: @escaping (Vehicle) -> Void
    ) {
        let repository = repository ?? AppEnvironment.vehicleRepository
        _viewModel = State(initialValue: VehicleFormViewModel(mode: mode, repository: repository))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Daily Driver", text: $viewModel.name)
                }

                Section("Vehicle") {
                    TextField("Year", text: $viewModel.year)
                        .keyboardType(.numberPad)
                    TextField("Make", text: $viewModel.make)
                    TextField("Model", text: $viewModel.model)
                    TextField("VIN", text: $viewModel.vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("Odometer") {
                    TextField("Current mileage", text: $viewModel.odometer)
                        .keyboardType(.numberPad)
                }

                if let error = viewModel.saveError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!viewModel.canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .overlay {
                if viewModel.isSaving {
                    ProgressView().controlSize(.large)
                }
            }
        }
    }

    private func save() {
        Task {
            if let saved = await viewModel.save() {
                onSaved(saved)
                dismiss()
            }
        }
    }
}

#Preview("Create") {
    VehicleFormView(mode: .create, repository: InMemoryVehicleRepository()) { _ in }
}

#Preview("Edit") {
    VehicleFormView(mode: .edit(InMemoryVehicleRepository.sample[0]),
                    repository: InMemoryVehicleRepository()) { _ in }
}
