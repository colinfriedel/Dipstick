//
//  ReferenceSection.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// "For next time": notes and photos (manual pages, parts, screenshots) for
/// one service or test type on one car. Shown on a schedule item's page, a
/// test's page, and from the service form. The page is only created once
/// something is added.
struct ReferenceSection: View {
    let vehicle: Vehicle
    let kind: String
    let name: String

    @Environment(\.modelContext) private var modelContext
    @State private var picked: [PhotosPickerItem] = []
    @State private var isAddingPhotos = false
    @State private var viewing: ReferencePhoto?
    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    private var page: ReferencePage? { vehicle.referencePage(kind: kind, name: name) }

    var body: some View {
        let photos = page?.sortedPhotos ?? []
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("For next time") {
                Text("Notes and photos")
                    .font(.dipstick(11.5, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }

            TextField("Notes", text: $notes,
                      prompt: Text("Torque specs, part numbers, what to have ready…").foregroundStyle(Theme.faint),
                      axis: .vertical)
                .font(.dipstick(15, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .lineLimit(3...)
                .focused($notesFocused)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                .panel(radius: Theme.Radius.field, border: notesFocused ? Theme.accent : Theme.panelBorder,
                       lineWidth: notesFocused ? 1.5 : 1)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(photos) { photo in
                    Button { viewing = photo } label: {
                        PhotoThumbnail(data: photo.data)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.caption ?? "Photo")
                }
                Button { isAddingPhotos = true } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .medium))
                                Text("Add photos")
                                    .font(.dipstick(12, .semibold, relativeTo: .caption))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(Theme.accentText)
                            .padding(6)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.panelBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { notes = page?.notes ?? "" }
        .onChange(of: notesFocused) { if !notesFocused { saveNotes() } }
        .onDisappear { saveNotes() }
        .photosPicker(isPresented: $isAddingPhotos, selection: $picked, maxSelectionCount: 20,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: picked) { addPicked() }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(photos: photos, start: photo) { removed in
                modelContext.delete(removed)
                modelContext.saveNow()
            }
        }
    }

    private func saveNotes() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let page {
            guard page.notes != notes else { return }
            page.notes = trimmed.isEmpty ? "" : notes
        } else {
            guard !trimmed.isEmpty else { return }
            vehicle.referencePageCreating(kind: kind, name: name, in: modelContext).notes = notes
        }
        modelContext.saveNow()
    }

    private func addPicked() {
        let items = picked
        guard !items.isEmpty else { return }
        picked = []
        Task {
            var images: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let small = await Task.detached(operation: { PhotoStore.downsized(data) }).value {
                    images.append(small)
                }
            }
            guard !images.isEmpty else { return }
            let page = vehicle.referencePageCreating(kind: kind, name: name, in: modelContext)
            var order = (page.photos ?? []).map(\.order).max().map { $0 + 1 } ?? 0
            for data in images {
                let photo = ReferencePhoto(data: data, order: order)
                modelContext.insert(photo)
                photo.page = page
                order += 1
            }
            modelContext.saveNow()
        }
    }
}

/// Reference photos are kept at up to 2,000 px on the long side, which keeps
/// manual pages readable while saving space.
nonisolated enum PhotoStore {
    static func downsized(_ data: Data, maxPixels: Int = 2_000) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    static func thumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }
}

/// A square, filled thumbnail, decoded off the main thread.
struct PhotoThumbnail: View {
    let data: Data?
    @State private var image: CGImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Theme.selectedFill
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.panelBorder, lineWidth: 1))
            .task(id: data) {
                guard let data else { return }
                image = await Task.detached { PhotoStore.thumbnail(data, maxPixels: 400) }.value
            }
    }
}

/// Full-screen photos, swipe between them, pinch to zoom; caption and delete.
struct PhotoViewer: View {
    let photos: [ReferencePhoto]
    let start: ReferencePhoto
    let onDelete: (ReferencePhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var current: PersistentIdentifier?
    @State private var isConfirmingDelete = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(photos) { photo in
                    ZoomablePhoto(data: photo.data).tag(Optional(photo.persistentModelID))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SmallControlButtonStyle())
                .accessibilityLabel("Close")
                Spacer()
                if let photo = currentPhoto, let data = photo.data, let image = UIImage(data: data) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Photo", image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(SmallControlButtonStyle())
                    .accessibilityLabel("Share photo")
                }
                Button { isConfirmingDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SmallControlButtonStyle(foreground: Theme.red))
                .accessibilityLabel("Delete photo")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let photo = currentPhoto {
                VStack {
                    Spacer()
                    CaptionField(photo: photo)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { current = start.persistentModelID }
        .confirmationDialog("Delete this photo?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                guard let photo = currentPhoto else { return }
                dismiss()
                onDelete(photo)
            }
        }
    }

    private var currentPhoto: ReferencePhoto? {
        photos.first { $0.persistentModelID == current }
    }
}

private struct CaptionField: View {
    @Bindable var photo: ReferencePhoto
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TextField("Caption", text: Binding(get: { photo.caption ?? "" },
                                           set: { photo.caption = $0.isEmpty ? nil : $0 }),
                  prompt: Text("Add a caption").foregroundStyle(Theme.faint), axis: .vertical)
            .font(.dipstick(14, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .lineLimit(1...4)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.6)))
            .onSubmit { modelContext.saveNow() }
            .onDisappear { modelContext.saveNow() }
    }
}

/// One photo, fit to the screen, pinch or double-tap to zoom.
private struct ZoomablePhoto: View {
    let data: Data?
    @State private var image: CGImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(MagnifyGesture()
                            .onChanged { scale = max(1, lastScale * $0.magnification) }
                            .onEnded { _ in
                                lastScale = scale
                                if scale == 1 { offset = .zero; lastOffset = .zero }
                            })
                        .simultaneousGesture(DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset })
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = scale > 1 ? 1 : 2.5
                                lastScale = scale
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: data) {
            guard let data else { return }
            image = await Task.detached { PhotoStore.thumbnail(data, maxPixels: 2_400) }.value
        }
    }
}

/// A reference page on its own (from the service form or the Maintenance
/// tab), for service types without a schedule item page.
struct ReferencePageView: View {
    let vehicle: Vehicle
    let kind: String
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Button("Done") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    vehicle.chip
                    Text(name.uppercased())
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.bottom, 6)
                ReferenceSection(vehicle: vehicle, kind: kind, name: name)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground)
    }
}

/// A row linking to a type's reference page: "Notes & photos for next
/// time", with what's there ("3 photos · notes").
struct ReferenceLink: View {
    let vehicle: Vehicle
    let kind: String
    let name: String
    let action: () -> Void

    var body: some View {
        let page = vehicle.referencePage(kind: kind, name: name)
        let photoCount = page?.photos?.count ?? 0
        let hasNotes = !(page?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let summary = [photoCount > 0 ? "\(photoCount) photo\(photoCount == 1 ? "" : "s")" : nil,
                       hasNotes ? "notes" : nil].compactMap { $0 }.joined(separator: " · ")
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("For next time")
                        .font(.dipstick(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.text)
                    Text(summary.isEmpty ? "Add notes and photos for \(name.lowercased())" : summary)
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
