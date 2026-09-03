import SwiftUI

/// Modal form for logging a service.
struct MaintenanceEntryFormView: View {
    @State private var viewModel: MaintenanceEntryFormViewModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    init(vehicleID: Int, repository: (any ActivityRepository)? = nil, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: MaintenanceEntryFormViewModel(vehicleID: vehicleID, repository: repository))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                    TextField("Odometer", text: $viewModel.odometer)
                        .keyboardType(.numberPad)

                    Picker("Service", selection: $viewModel.serviceTypeChoice) {
                        ForEach(ServiceType.common, id: \.self) { Text($0).tag($0) }
                        Text("Other…").tag(MaintenanceEntryFormViewModel.otherServiceType)
                    }
                    if viewModel.isCustomServiceType {
                        TextField("Service type", text: $viewModel.customServiceType)
                    }

                    TextField("Cost", text: $viewModel.cost)
                        .keyboardType(.decimalPad)
                }

                partsSection

                Section("Next due (optional)") {
                    Toggle("By mileage", isOn: $viewModel.setNextDueByMileage)
                    if viewModel.setNextDueByMileage {
                        TextField("Due at odometer", text: $viewModel.nextDueOdometer)
                            .keyboardType(.numberPad)
                    }
                    Toggle("By date", isOn: $viewModel.setNextDueByDate)
                    if viewModel.setNextDueByDate {
                        DatePicker("Due date", selection: $viewModel.nextDueDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $viewModel.notes, axis: .vertical)
                }

                if let error = viewModel.saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Log Service")
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

    private var partsSection: some View {
        Section("Parts") {
            ForEach($viewModel.parts) { $part in
                HStack {
                    TextField("Part name", text: $part.name)
                    Spacer()
                    TextField("Cost", value: $part.cost, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            }
            .onDelete { viewModel.removeParts(at: $0) }

            Button {
                viewModel.addPart()
            } label: {
                Label("Add part", systemImage: "plus.circle")
            }
        }
    }
}

#Preview {
    MaintenanceEntryFormView(vehicleID: 1, repository: InMemoryActivityRepository()) {}
}
