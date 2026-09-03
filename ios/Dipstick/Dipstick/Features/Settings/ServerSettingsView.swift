import SwiftUI

/// Point the app at a different backend without rebuilding — the local Docker
/// stack while developing, a deployed server otherwise. Both services are
/// configured separately since they may live on different hosts once deployed.
///
/// Saving writes `@AppStorage` (UserDefaults); `DipstickApp` keys the view tree
/// off these values, so a change reloads every screen against the new URLs.
struct ServerSettingsView: View {
    @AppStorage(AppEnvironment.vehicleOverrideKey) private var vehicleOverride = ""
    @AppStorage(AppEnvironment.activityOverrideKey) private var activityOverride = ""
    @Environment(\.dismiss) private var dismiss

    @State private var vehicleDraft = ""
    @State private var activityDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppEnvironment.defaultVehicleURLString, text: $vehicleDraft)
                        .modifier(URLFieldStyle())
                } header: {
                    Text("Vehicle service")
                }

                Section {
                    TextField(AppEnvironment.defaultActivityURLString, text: $activityDraft)
                        .modifier(URLFieldStyle())
                } header: {
                    Text("Activity service (fuel, maintenance)")
                } footer: {
                    Text("Leave a field blank to use its built-in default. Changing either reloads the app.")
                }

                Section("Currently using") {
                    LabeledContent("Vehicle", value: AppEnvironment.vehicleServiceURL.absoluteString)
                    LabeledContent("Activity", value: AppEnvironment.activityServiceURL.absoluteString)
                }
                .font(.footnote)

                if !vehicleOverride.isEmpty || !activityOverride.isEmpty {
                    Button("Reset both to defaults", role: .destructive) {
                        vehicleOverride = ""
                        activityOverride = ""
                        dismiss()
                    }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vehicleOverride = vehicleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        activityOverride = activityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
            .onAppear {
                vehicleDraft = vehicleOverride
                activityDraft = activityOverride
            }
        }
    }
}

private struct URLFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

#Preview {
    ServerSettingsView()
}
