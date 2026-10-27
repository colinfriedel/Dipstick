//
//  BackupView.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backups: where they go, when the last one was made, back up now, and
/// restore from any kept backup.
struct BackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var manager = BackupManager.shared
    @State private var backups: [BackupFiles.Entry] = []
    @State private var isLoadingList = true
    @State private var isPickingFolder = false
    @State private var loading: BackupFiles.Entry?
    @State private var toRestore: BackupManager.Loaded?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Button("Done") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    Text("BACKUP")
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.bottom, 6)

                statusPanel
                protectionPanel
                locationPanel

                Button {
                    manager.backUp(context: modelContext, force: true)
                } label: {
                    Label(manager.isWorking ? "Backing up…" : "Back up now", systemImage: "externaldrive.badge.checkmark")
                }
                .buttonStyle(BigActionButtonStyle(height: 56))
                .disabled(manager.isWorking)

                SectionTitle("Restore") {
                    Text("Replaces everything on this iPhone")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 8)
                restoreList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .task(id: "\(manager.folderName ?? "")\(manager.lastBackup?.timeIntervalSince1970 ?? 0)") {
            await refresh()
            await manager.checkUploads()
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do { try manager.choose(folder: url, context: modelContext) } catch {
                    message = "Couldn't use that folder: \(error.localizedDescription)"
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .sheet(item: $toRestore) { loaded in
            RestoreConfirmView(loaded: loaded) {
                toRestore = nil
                Task {
                    do {
                        try await manager.restore(loaded, context: modelContext)
                        message = "Restored the backup from \(Self.title(for: loaded.entry))."
                    } catch {
                        message = "Didn't restore: \(error.localizedDescription) Nothing was changed."
                    }
                }
            }
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: manager.problem == nil && manager.lastBackup != nil
                      ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(manager.problem == nil && manager.lastBackup != nil ? Theme.muted : Theme.amber)
                Text(manager.lastBackup.map { "Last backup \($0.formRowText)" } ?? "Not backed up yet")
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
            }
            if let problem = manager.problem {
                Text(problem)
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.amber)
            }
            Text("Backs up by itself whenever you leave the app after a change. Keeps the last week, plus one a month for six months.")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: Theme.Radius.field)
    }

    /// What the backups survive where they are now, and what to do to be
    /// fully protected.
    private var protectionPanel: some View {
        let place = manager.place
        let uploadProblem = manager.uploadProblem
        let fullyProtected = place == .iCloud && uploadProblem == nil
        return VStack(alignment: .leading, spacing: 10) {
            SmallCapsLabel("Your data is safe if…")
            protectionRow("The app has a problem or data goes wrong", safe: true)
            protectionRow("Dipstick is deleted", safe: place.survivesAppDeleted)
            // Newest backups not in iCloud yet are lost with the phone.
            protectionRow("Your iPhone is lost or replaced", safe: uploadProblem == nil ? place.survivesPhoneLost : false)
            Text(uploadProblem ?? advice(for: place))
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(fullyProtected ? Theme.muted : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: Theme.Radius.field, border: fullyProtected ? Theme.panelBorder : Theme.amber.opacity(0.6))
    }

    /// safe: true = yes, false = no, nil = depends on the folder.
    private func protectionRow(_ text: String, safe: Bool?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: safe == true ? "checkmark.circle.fill" : safe == false ? "xmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(safe == true ? Theme.muted : safe == false ? Theme.red : Theme.amber)
            Text(text)
                .font(.dipstick(14, relativeTo: .body))
                .foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text): \(safe == true ? "yes" : safe == false ? "no" : "depends on the folder")")
    }

    private func advice(for place: BackupManager.Place) -> String {
        switch place {
        case .appFolder:
            "Backups are only in Dipstick's own folder, which is erased if the app is deleted. To protect your data: tap Choose a folder below, tap iCloud Drive, make a new folder (for example \"Dipstick\"), then tap Open."
        case .iCloud:
            "Fully protected. Keep iCloud Drive turned on (Settings › your name › iCloud) with some free iCloud storage. Backups upload whenever your iPhone is online."
        case .otherFolder:
            "This folder isn't in iCloud Drive. If it's On My iPhone, it goes with the phone unless your iPhone itself is backed up. To be fully protected, choose a folder in iCloud Drive instead."
        }
    }

    private var locationPanel: some View {
        VStack(spacing: 0) {
            FormRow("Saved to", subtitle: manager.folderName == nil ? "Files › On My iPhone › Dipstick" : nil) {
                Text(manager.folderName.map {
                    (manager.place == .iCloud ? "iCloud Drive › " : "") + "\($0) › \(BackupFiles.folderName)"
                } ?? "Dipstick's folder")
                    .font(.dipstick(14, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.trailing)
            }
            FormDivider()
            Button {
                isPickingFolder = true
            } label: {
                Label(manager.folderName == nil ? "Choose a folder (e.g. iCloud Drive)…" : "Change folder…",
                      systemImage: "folder")
                    .font(.dipstick(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if manager.folderName != nil {
                FormDivider()
                Button {
                    manager.useThisPhone(context: modelContext)
                } label: {
                    Label("Save in Dipstick's folder instead", systemImage: "iphone")
                        .font(.dipstick(14, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .panel(radius: Theme.Radius.field)
    }

    @ViewBuilder
    private var restoreList: some View {
        if isLoadingList && backups.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if backups.isEmpty {
            Text("No backups here yet.")
                .font(.dipstick(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
        } else {
            PanelList(backups) { entry in
                Button { open(entry) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.title(for: entry))
                                .font(.dipstick(15, .semibold, relativeTo: .body))
                                .foregroundStyle(Theme.text)
                            if entry.isBeforeRestore {
                                Text("Saved before a restore")
                                    .font(.dipstick(12, relativeTo: .caption))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        if loading == entry {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loading != nil || manager.isWorking)
            }
        }
    }

    static func title(for entry: BackupFiles.Entry) -> String {
        guard let day = entry.day else { return entry.name }
        let text = Calendar.current.isDateInToday(day) ? "Today"
            : Calendar.current.isDateInYesterday(day) ? "Yesterday"
            : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        guard entry.isBeforeRestore, let made = entry.madeAt else { return text }
        return "\(text), \(made.formatted(date: .omitted, time: .shortened))"
    }

    private func refresh() async {
        isLoadingList = true
        backups = await manager.backups()
        isLoadingList = false
    }

    private func open(_ entry: BackupFiles.Entry) {
        loading = entry
        Task {
            defer { loading = nil }
            do { toRestore = try await manager.load(entry) } catch {
                message = "Couldn't read that backup: \(error.localizedDescription)"
            }
        }
    }
}

/// What's in a backup, and the button to restore it.
private struct RestoreConfirmView: View {
    let loaded: BackupManager.Loaded
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restore \(BackupView.title(for: loaded.entry))?")
                .font(.dipstick(20, .semibold, relativeTo: .title2))
                .foregroundStyle(Theme.text)
            Text(loaded.file.data.summary.isEmpty ? "This backup is empty." : loaded.file.data.summary)
                .font(.dipstick(15, relativeTo: .body))
                .foregroundStyle(Theme.text)
            Text("Made \(loaded.file.created.formatted(date: .abbreviated, time: .shortened)). Everything on this iPhone is replaced with it. What's here now is backed up first, so you can go back.")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
            if loaded.missingPhotos > 0 {
                StatusLine(status: .dueSoon,
                           text: "\(loaded.missingPhotos) photo\(loaded.missingPhotos == 1 ? " is" : "s are") missing and will be skipped")
            }
            Spacer(minLength: 0)
            Button("Restore", action: onRestore)
                .buttonStyle(PrimaryButtonStyle())
            Button("Cancel") { dismiss() }
                .buttonStyle(SmallControlButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .presentationDetents([.medium])
        .background(Theme.ground)
    }
}
