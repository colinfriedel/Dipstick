//
//  ServiceNotesViews.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Notes and photos from earlier times a service was done, newest first, one
/// card per service. Shown on the service form, a schedule item's page and
/// from the Maintenance tab.
struct PastServiceNotes: View {
    let vehicle: Vehicle
    let serviceType: String
    /// The service being edited, which shows its own notes in the form.
    var excluding: MaintenanceEntry?

    @Environment(\.modelContext) private var modelContext
    @State private var viewing: ViewingPhoto?

    private struct ViewingPhoto: Identifiable {
        let id = UUID()
        let photos: [ReferencePhoto]
        let start: ReferencePhoto
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(vehicle.pastServiceNotes(ofType: serviceType, excluding: excluding)) { entry in
                card(title: "\(entry.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(entry.odometer.formatted()) mi",
                     notes: entry.notes, photos: entry.sortedPhotos)
            }
            if let page = vehicle.leftoverServicePage(ofType: serviceType) {
                card(title: "Saved before", notes: page.notes, photos: page.sortedPhotos)
            }
        }
        .fullScreenCover(item: $viewing) { item in
            PhotoViewer(photos: item.photos, start: item.start) { removed in
                modelContext.delete(removed)
                modelContext.saveNow()
            }
        }
    }

    private func card(title: String, notes: String?, photos: [ReferencePhoto]) -> some View {
        let text = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.dipstick(12, .semibold, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
            if !text.isEmpty {
                Text(text)
                    .font(.dipstick(15, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(photos) { photo in
                        Button { viewing = ViewingPhoto(photos: photos, start: photo) } label: {
                            PhotoThumbnail(data: photo.data)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.caption ?? "Photo")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: Theme.Radius.field)
    }
}

extension Vehicle {
    /// True when a service has notes or photos from earlier times.
    func hasPastServiceNotes(ofType type: String, excluding: MaintenanceEntry? = nil) -> Bool {
        !pastServiceNotes(ofType: type, excluding: excluding).isEmpty || leftoverServicePage(ofType: type) != nil
    }
}

/// Past notes and photos for one service on their own, from the Maintenance
/// tab's service filter.
struct ServiceNotesPage: View {
    let vehicle: Vehicle
    let serviceType: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Button("Done") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    vehicle.chip
                    Text(serviceType.uppercased())
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.bottom, 6)
                if vehicle.hasPastServiceNotes(ofType: serviceType) {
                    PastServiceNotes(vehicle: vehicle, serviceType: serviceType)
                } else {
                    Text("No notes or photos yet. Add them when you log \(serviceType.lowercased()).")
                        .font(.dipstick(14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
    }
}

/// A row opening a service's past notes and photos: "Notes and photos",
/// with what's there ("2 services · 3 photos").
struct ServiceNotesLink: View {
    let vehicle: Vehicle
    let serviceType: String
    let action: () -> Void

    var body: some View {
        let entries = vehicle.pastServiceNotes(ofType: serviceType)
        let leftover = vehicle.leftoverServicePage(ofType: serviceType)
        let photoCount = entries.reduce(0) { $0 + ($1.photos?.count ?? 0) } + (leftover?.photos?.count ?? 0)
        let noteCount = entries.count + (leftover == nil ? 0 : 1)
        let summary = ["\(noteCount) with notes", photoCount > 0 ? "\(photoCount) photo\(photoCount == 1 ? "" : "s")" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes and photos")
                        .font(.dipstick(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.text)
                    Text(summary)
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .panel(radius: Theme.Radius.field)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
