//
//  ScheduleItemDetailView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// One factory schedule item: where it stands, your interval next to the
/// factory one, a button to log it, and every past service that counts for
/// it (tap one to edit it).
struct ScheduleItemDetailView: View {
    let vehicle: Vehicle
    let item: ScheduleItem

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isLogging = false
    @State private var editingEntry: MaintenanceEntry?
    /// Set just before the item is deleted, so nothing reads it afterwards.
    @State private var isRemoved = false

    var body: some View {
        ScrollView {
            if !isRemoved {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.ground)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isEditing) {
            ScheduleItemFormView(vehicle: vehicle, item: item) {
                isRemoved = true
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $isLogging) {
            MaintenanceEntryFormView(vehicle: vehicle, serviceType: item.serviceType)
        }
        .fullScreenCover(item: $editingEntry) { entry in
            MaintenanceEntryFormView(vehicle: vehicle, entry: entry)
        }
    }

    private var content: some View {
        let progress = vehicle.scheduleProgress(for: item)
        let history = vehicle.entries(for: item)

        return VStack(alignment: .leading, spacing: 12) {
            navRow.padding(.bottom, 2)
            header.padding(.bottom, 6)

            if let progress, !progress.needsRecord {
                ScheduleChartRow(item: item, progress: progress, showsName: false)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .panel()
            } else {
                ScheduleTextRow(item: item, progress: progress)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .panel()
            }

            intervalPanel

            Button { isLogging = true } label: {
                Label("Log \(item.serviceType)", systemImage: "wrench.adjustable")
            }
            .buttonStyle(BigActionButtonStyle(height: 56))
            .padding(.top, 4)

            SectionTitle("History") {
                Text(history.isEmpty ? "None yet" : "\(history.count) logged")
                    .font(.dipstick(11.5, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 8)

            if history.isEmpty {
                Text("No \(item.serviceType) logged yet. Log one to start tracking.")
                    .font(.dipstick(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
            } else {
                PanelList(history) { entry in
                    Button { editingEntry = entry } label: {
                        MaintenanceEntryRow(entry: entry, dueItem: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var navRow: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("Back")
            Spacer()
            Button("Edit") { isEditing = true }
                .buttonStyle(SmallControlButtonStyle())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                vehicle.chip
                Text(item.name)
                    .font(.dipstick(22, .semibold, relativeTo: .title))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Counts when you log \(item.serviceType)")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
            if let note = item.note {
                Text(note)
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// Your interval (if set) above the factory one.
    @ViewBuilder
    private var intervalPanel: some View {
        if item.rule.isTracked {
            VStack(spacing: 0) {
                if item.hasCustomInterval {
                    FormRow("Your interval") {
                        intervalText(item.effectiveRule.summary, color: Theme.text)
                    }
                    FormDivider()
                }
                FormRow("Factory") {
                    intervalText(item.rule.summary, color: item.hasCustomInterval ? Theme.muted : Theme.text)
                }
            }
            .padding(.vertical, 4)
            .panel(radius: Theme.Radius.field)
        }
    }

    private func intervalText(_ text: String?, color: Color) -> some View {
        Text(text ?? "—")
            .font(.dipstick(14, relativeTo: .body))
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
    }
}
