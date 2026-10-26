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
/// one test type on one car, on the test's page. The page is only created
/// once something is added. (Services keep notes and photos on each logged
/// service instead; see `PastServiceNotes`.)
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
            // Clipping only hides the overflow of a tall or wide photo; this
            // stops the hidden part from taking taps meant for what's nearby.
            .contentShape(RoundedRectangle(cornerRadius: 12))
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

/// A photo not saved yet, on the service form.
struct PhotoDraft: Identifiable {
    let id = UUID()
    var data: Data?
    var caption: String?
    /// The saved photo this stands for, when editing a service.
    var existing: ReferencePhoto?
}

/// Full-screen view of the service form's photos before saving: swipe
/// between them, pinch to zoom, caption, remove.
struct DraftPhotoViewer: View {
    @Binding var drafts: [PhotoDraft]
    let start: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var current: UUID?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(drafts) { draft in
                    ZoomablePhoto(data: draft.data).tag(Optional(draft.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: drafts.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SmallControlButtonStyle())
                .accessibilityLabel("Close")
                Spacer()
                Button {
                    guard let current else { return }
                    dismiss()
                    drafts.removeAll { $0.id == current }
                } label: {
                    Image(systemName: "trash").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SmallControlButtonStyle(foreground: Theme.red))
                .accessibilityLabel("Remove photo")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let index = drafts.firstIndex(where: { $0.id == current }) {
                VStack {
                    Spacer()
                    TextField("Caption", text: Binding(get: { drafts[index].caption ?? "" },
                                                       set: { drafts[index].caption = $0.isEmpty ? nil : $0 }),
                              prompt: Text("Add a caption").foregroundStyle(Theme.faint), axis: .vertical)
                        .font(.dipstick(14, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.6)))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { current = start }
    }
}
