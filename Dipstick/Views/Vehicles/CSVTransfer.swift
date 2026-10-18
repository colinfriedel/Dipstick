//
//  CSVTransfer.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A vehicle's records as a .csv file for the share sheet. The text is built
/// when the menu opens; the file is written only when the user shares.
nonisolated struct CSVExportFile: Transferable {
    let filename: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.filename)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.filename }
    }
}

extension Vehicle {
    var csvExportFile: CSVExportFile {
        let day = RecordCSV.format(Date(), .current)
        let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        return CSVExportFile(filename: "Dipstick \(safeName) \(day).csv", text: exportCSV())
    }
}

/// Import preview (design board L): what the file contains before anything
/// is saved. Every row is marked NEW, SKIP (already in the app) or FIX (can't
/// be read). Choose the car to import into; nothing in the file is changed.
struct ImportPreviewView: View {
    let filename: String
    let parsed: RecordCSV.Parsed
    /// Pick a different file.
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]

    @State private var vehicle: Vehicle
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", new = "New", skipped = "Skipped", problems = "Problems"
        var id: Self { self }
    }

    init(vehicle: Vehicle, filename: String, parsed: RecordCSV.Parsed, onChange: @escaping () -> Void) {
        _vehicle = State(initialValue: vehicle)
        self.filename = filename
        self.parsed = parsed
        self.onChange = onChange
    }

    var body: some View {
        let items = vehicle.importPreview(for: parsed)
        let plan = vehicle.importPlan(for: parsed)
        let total = plan.fuel.count + plan.services.count
        let counts: [Filter: Int] = [
            .all: items.count,
            .new: items.filter { $0.status == .new }.count,
            .skipped: items.filter { $0.status == .skip }.count,
            .problems: items.filter { if case .fix = $0.status { true } else { false } }.count,
        ]
        let shown = items.filter { item in
            switch filter {
            case .all: true
            case .new: item.status == .new
            case .skipped: item.status == .skip
            case .problems: if case .fix = item.status { true } else { false }
            }
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    Text("IMPORT CSV")
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 6)

                fileCard

                TileRow {
                    ReadoutTile("New", highlighted: true, height: 80) {
                        MonoNumber(text: "\(counts[.new] ?? 0)", size: 28, color: Theme.accent)
                    }
                    ReadoutTile("Skipped", height: 80) {
                        MonoNumber(text: "\(counts[.skipped] ?? 0)", size: 28)
                    }
                    ReadoutTile("Problems", height: 80) {
                        MonoNumber(text: "\(counts[.problems] ?? 0)", size: 28,
                                   color: (counts[.problems] ?? 0) > 0 ? Theme.red : Theme.text)
                    }
                }

                importInto

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { option in
                            ChipButton(title: "\(option.rawValue) \(counts[option] ?? 0)", isSelected: filter == option) {
                                filter = option
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()

                if shown.isEmpty {
                    Text(items.isEmpty ? "No rows found in this file." : "Nothing here.")
                        .font(.dipstick(14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .panel()
                } else {
                    PanelList(shown) { item in ImportRow(item: item) }
                }

                Text("Skipped rows and problem rows are left out. Nothing is changed in your file.")
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            Button(total == 0 ? "Nothing to import" : "Import \(total) record\(total == 1 ? "" : "s")") {
                vehicle.importRecords(fuel: plan.fuel, services: plan.services, into: modelContext)
                modelContext.saveNow()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(total == 0)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Theme.ground)
        }
        .tint(Theme.accent)
    }

    private var fileCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 20))
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(parsed.rowCount) row\(parsed.rowCount == 1 ? "" : "s") found")
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Change") {
                dismiss()
                onChange()
            }
            .buttonStyle(SmallControlButtonStyle())
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .panel(radius: Theme.Radius.field)
    }

    private var importInto: some View {
        Menu {
            Picker("Import into", selection: $vehicle) {
                ForEach(vehicles) { option in
                    Text(option.name).tag(option)
                }
            }
        } label: {
            HStack {
                SmallCapsLabel("Import into")
                Spacer()
                vehicle.chip
                Text(vehicle.name)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .panel(radius: Theme.Radius.field)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Import into \(vehicle.name)")
    }
}

private struct ImportRow: View {
    let item: RecordCSV.PreviewItem

    private var isSkip: Bool { item.status == .skip }
    private var fixMessage: String? {
        if case .fix(let message) = item.status { message } else { nil }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                Text(isSkip ? "Already in the app" : (fixMessage ?? item.detail))
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(fixMessage == nil ? Theme.muted : Theme.red)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            badge
        }
        .opacity(isSkip ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch item.kind {
        case .fuel: "fuelpump"
        case .service: "wrench.adjustable"
        case .unknown: "doc.text"
        }
    }

    private var title: String {
        guard let date = item.date else { return item.title }
        return "\(date.formatted(.dateTime.month(.abbreviated).day().year())) · \(item.title)"
    }

    @ViewBuilder
    private var badge: some View {
        switch item.status {
        case .new:
            Text("NEW")
                .font(.dipstick(10, .semibold, relativeTo: .caption2))
                .tracking(1)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.controlBorder, lineWidth: 1))
        case .skip:
            Text("SKIP")
                .font(.dipstick(10, .semibold, relativeTo: .caption2))
                .tracking(1)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.panelBorder, lineWidth: 1))
        case .fix:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 9, weight: .semibold))
                Text("FIX").font(.dipstick(10, .semibold, relativeTo: .caption2)).tracking(1)
            }
            .foregroundStyle(Theme.red)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.redPillFill))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.redPillBorder, lineWidth: 1))
        }
    }
}
