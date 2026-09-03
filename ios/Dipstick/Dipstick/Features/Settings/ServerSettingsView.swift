import SwiftUI

/// Lets you point the app at a different backend without rebuilding — the local
/// Docker stack while developing, the deployed server otherwise.
///
/// Saving writes to `@AppStorage` (UserDefaults). `DipstickApp` keys the whole
/// view tree off this value, so a change reloads every screen against the new URL.
struct ServerSettingsView: View {
    @AppStorage(AppEnvironment.backendOverrideKey) private var override = ""
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://your-mac.local:8081", text: $draft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Backend URL")
                } footer: {
                    Text("Leave blank to use the built-in default:\n\(AppEnvironment.defaultBackendURLString)\n\nChanging this reloads the app.")
                }

                Section {
                    LabeledContent("Currently using", value: AppEnvironment.vehicleServiceURL.absoluteString)
                        .font(.footnote)
                }

                if !override.isEmpty {
                    Button("Reset to default", role: .destructive) {
                        override = ""
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
                        override = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
            .onAppear { draft = override }
        }
    }
}

#Preview {
    ServerSettingsView()
}
