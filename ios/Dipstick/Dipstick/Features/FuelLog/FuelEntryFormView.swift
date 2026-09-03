import SwiftUI

/// Modal form for logging a fill-up.
struct FuelEntryFormView: View {
    @State private var viewModel: FuelEntryFormViewModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    init(vehicleID: Int, repository: (any ActivityRepository)? = nil, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: FuelEntryFormViewModel(vehicleID: vehicleID, repository: repository))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                    TextField("Odometer", text: $viewModel.odometer)
                        .keyboardType(.numberPad)
                    TextField("Gallons", text: $viewModel.gallons)
                        .keyboardType(.decimalPad)
                }

                Section("Cost") {
                    Picker("Enter as", selection: $viewModel.costMode) {
                        ForEach(FuelEntryFormViewModel.CostMode.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch viewModel.costMode {
                    case .total:
                        TextField("Total cost", text: $viewModel.totalCost)
                            .keyboardType(.decimalPad)
                    case .perGallon:
                        TextField("Price per gallon", text: $viewModel.pricePerGallon)
                            .keyboardType(.decimalPad)
                    }
                }

                Section {
                    Toggle("Full tank", isOn: $viewModel.isFullTank)
                } footer: {
                    Text("Partial fill-ups are logged but excluded from MPG.")
                }

                Section("Optional") {
                    TextField("Station", text: $viewModel.stationName)
                    TextField("Notes", text: $viewModel.notes, axis: .vertical)
                }

                if let error = viewModel.saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Log Fill-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .overlay {
                if viewModel.isSaving { ProgressView().controlSize(.large) }
            }
        }
    }
}

#Preview {
    FuelEntryFormView(vehicleID: 1, repository: InMemoryActivityRepository()) {}
}
