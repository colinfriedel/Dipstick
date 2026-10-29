//
//  ScheduleImportView.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Read the car's schedule from photos, screenshots or a PDF of its owner's
/// manual, check what was found, then use it as the car's schedule.
struct ScheduleImportView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase = Phase.choose
    @State private var pages: [ScheduleReader.Page] = []
    @State private var items: [ScheduleReader.Item] = []
    @State private var editing: ScheduleReader.Item?
    @State private var viewingPage = false
    @State private var replaces = true
    @State private var isPickingPhotos = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var isTakingPhoto = false
    @State private var isPickingFile = false
    @State private var isChoosingMore = false
    @State private var problem: String?

    private enum Phase: Equatable { case choose, reading, review }

    /// Keeping what's there is only offered when it's the car's own.
    private var hasOwnSchedule: Bool { !(vehicle.scheduleItems ?? []).isEmpty && !vehicle.hasStandardSchedule }

    private var knownNames: [String] {
        var seen = Set<String>()
        var names: [String] = (vehicle.maintenanceEntries ?? []).map(\.serviceType)
        names += ServiceType.builtIn
        names += ["Tires", "Alignment", "Smog check", "Drive belts", "Timing belt"]
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            FormHeader(title: "From owner's manual", vehicle: vehicle) { dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Theme.ground)
                .modifier(TopSafeAreaFallback())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch phase {
                    case .choose: chooseContent
                    case .reading:
                        VStack(spacing: 14) {
                            ProgressView()
                            Text("Reading the schedule…")
                                .font(.dipstick(15, relativeTo: .body))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    case .review: reviewContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            if phase == .review {
                let count = items.filter { $0.include && $0.hasInterval }.count
                FormSaveBar(title: count == 0 ? "Tick items to use"
                                : (replaces || !hasOwnSchedule ? "Use these \(count) items" : "Add \(count) items"),
                            isEnabled: count > 0, isKeyboardUp: false, onHideKeyboard: {}) { save() }
            }
        }
        .tint(Theme.accent)
        .photosPicker(isPresented: $isPickingPhotos, selection: $pickedPhotos, maxSelectionCount: 10,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: pickedPhotos) { readPickedPhotos() }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { data in
                isTakingPhoto = false
                guard let data else { return }
                read { [RecordReader.schedulePage(fromImage: data)].compactMap { $0 } }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .image]) { readFile($0) }
        .confirmationDialog("Add more pages", isPresented: $isChoosingMore) {
            Button("Photos or Screenshots") { isPickingPhotos = true }
            Button("Take Photo") { isTakingPhoto = true }
            Button("PDF") { isPickingFile = true }
        }
        .sheet(item: $editing) { item in
            ScheduleItemEditor(item: item, onShowPages: pages.contains { $0.preview != nil } ? { viewingPage = true } : nil) { edited in
                if let i = items.firstIndex(where: { $0.id == edited.id }) { items[i] = edited }
            } onDelete: {
                items.removeAll { $0.id == item.id }
            }
        }
        .fullScreenCover(isPresented: $viewingPage) {
            ManualPageViewer(pages: pages.compactMap(\.preview))
        }
        .alert("Couldn't read that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(problem ?? "")
        }
    }

    // MARK: Choosing

    @ViewBuilder
    private var chooseContent: some View {
        Text("Add a photo or screenshot of the maintenance schedule in your owner's manual, or the whole manual as a PDF. Tables with mileage columns and lists like \"every 7,500 miles or 12 months\" both work.")
            .font(.dipstick(15, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        Text("Read on this iPhone. You'll check every item before it's used.")
            .font(.dipstick(13, relativeTo: .footnote))
            .foregroundStyle(Theme.muted)
        VStack(spacing: 10) {
            sourceButton("Photos or screenshots", icon: "photo.on.rectangle") { isPickingPhotos = true }
            sourceButton("Take a photo", icon: "camera") { isTakingPhoto = true }
            sourceButton("PDF", icon: "doc") { isPickingFile = true }
        }
        .padding(.top, 6)
        Text("Tip: for a photo, hold the phone straight above the page so the columns line up.")
            .font(.dipstick(12, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)

    }

    private func sourceButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 28)
                Text(title)
                    .font(.dipstick(16, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .panel(radius: Theme.Radius.field)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Reading

    private func readPickedPhotos() {
        let picked = pickedPhotos
        guard !picked.isEmpty else { return }
        pickedPhotos = []
        phase = .reading
        Task {
            var images: [Data] = []
            for item in picked {
                if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
            }
            read { images.compactMap(RecordReader.schedulePage(fromImage:)) }
        }
    }

    private func readFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { problem = "The file couldn't be opened."; return }
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".pdf")
            try? data.write(to: copy)
            read { RecordReader.schedulePages(fromPDF: copy) }
        } else {
            read { [RecordReader.schedulePage(fromImage: data)].compactMap { $0 } }
        }
    }

    private func read(_ makePages: @escaping @Sendable () -> [ScheduleReader.Page]) {
        phase = .reading
        let known = knownNames
        Task {
            let newPages = await Task.detached(priority: .userInitiated) { makePages() }.value
            pages += newPages
            let found = await ScheduleReader.read(newPages, known: known)
            let fresh = found.filter { new in !items.contains { $0.name.caseInsensitiveCompare(new.name) == .orderedSame } }
            items += fresh
            if items.isEmpty {
                phase = .choose
                problem = newPages.isEmpty
                    ? "No maintenance schedule pages were found in that file. Try a screenshot of just the schedule page."
                    : "No schedule was found on that page. Try the page with the table or list of services and their mileage."
            } else {
                phase = .review
            }
        }
    }

    // MARK: Reviewing

    @ViewBuilder
    private var reviewContent: some View {
        let unsure = items.filter(\.unsure).count
        VStack(alignment: .leading, spacing: 6) {
            Text("Found \(items.count) item\(items.count == 1 ? "" : "s")")
                .font(.dipstick(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.text)
            if unsure > 0 {
                StatusLine(status: .dueSoon, text: "\(unsure) to check: tap to fix or confirm")
            }
            Text("Each item counts when you log the service under it.")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
        }

        if hasOwnSchedule {
            Picker("Current schedule", selection: $replaces) {
                Text("Replace current schedule").tag(true)
                Text("Add to it").tag(false)
            }
            .pickerStyle(.segmented)
        }

        VStack(spacing: 0) {
            ForEach($items) { $item in
                if item.id != items.first?.id { FormDivider() }
                HStack(spacing: 12) {
                    Button { item.include.toggle() } label: {
                        Image(systemName: item.include ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(item.include ? Theme.accent : Theme.faint)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.include ? "Included" : "Left out")
                    Button { editing = item } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.dipstick(15, .semibold, relativeTo: .body))
                                    .foregroundStyle(item.include ? Theme.text : Theme.muted)
                                HStack(spacing: 4) {
                                    if item.unsure {
                                        Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                                    }
                                    Text(rule(item).summary ?? "No interval")
                                }
                                .font(.dipstick(13, relativeTo: .footnote))
                                .foregroundStyle(item.unsure ? Theme.amber : Theme.text)
                                Text("Counts as \(item.serviceType)")
                                    .font(.dipstick(12, relativeTo: .caption))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
            }
        }
        .panel(radius: Theme.Radius.field)

        Button { isChoosingMore = true } label: {
            Label("Add another page", systemImage: "plus")
                .font(.dipstick(14, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    private func rule(_ item: ScheduleReader.Item) -> FactorySchedule.Rule {
        .init(everyMiles: item.everyMiles, everyMonths: item.everyMonths,
              firstMiles: item.firstMiles, firstMonths: item.firstMonths)
    }

    private func save() {
        let chosen = items.filter { $0.include && $0.hasInterval }.map {
            FactorySchedule.PresetItem(name: $0.name, serviceType: $0.serviceType, rule: rule($0), note: $0.note)
        }
        if replaces || !hasOwnSchedule {
            vehicle.replaceSchedule(with: chosen, source: FactorySchedule.manualSource, in: modelContext)
        } else {
            vehicle.loadSchedule(FactorySchedule.Preset(name: "", items: chosen), into: modelContext)
            vehicle.scheduleSource = FactorySchedule.manualSource
        }
        modelContext.saveNow()
        dismiss()
    }
}

// MARK: - Editing an item

private struct ScheduleItemEditor: View {
    @State var item: ScheduleReader.Item
    let onShowPages: (() -> Void)?
    let onSave: (ScheduleReader.Item) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var everyMiles = ""
    @State private var everyMonths = ""
    @State private var firstMiles = ""
    @State private var firstMonths = ""

    init(item: ScheduleReader.Item, onShowPages: (() -> Void)?, onSave: @escaping (ScheduleReader.Item) -> Void,
         onDelete: @escaping () -> Void) {
        _item = State(initialValue: item)
        self.onShowPages = onShowPages
        self.onSave = onSave
        self.onDelete = onDelete
        _everyMiles = State(initialValue: item.everyMiles.map(String.init) ?? "")
        _everyMonths = State(initialValue: item.everyMonths.map(String.init) ?? "")
        _firstMiles = State(initialValue: item.firstMiles.map(String.init) ?? "")
        _firstMonths = State(initialValue: item.firstMonths.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $item.name)
                    LabeledContent("Counts as") {
                        TextField("Service", text: $item.serviceType).multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    number("Every (miles)", $everyMiles)
                    number("Or every (months)", $everyMonths)
                } header: {
                    Text("Interval")
                } footer: {
                    Text("Whichever comes first. Leave one blank if the manual only gives the other.")
                }
                Section {
                    number("First at (miles)", $firstMiles)
                    number("Or first at (months)", $firstMonths)
                } header: {
                    Text("First time, if different")
                } footer: {
                    Text("For items like coolant: first at 120,000 miles, then every 60,000.")
                }
                Section {
                    if let onShowPages { Button("See the page", action: onShowPages) }
                    Button("Remove this item", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Schedule item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var edited = item
                        edited.everyMiles = Units.parseWholeNumber(everyMiles)
                        edited.everyMonths = Units.parseWholeNumber(everyMonths)
                        edited.firstMiles = Units.parseWholeNumber(firstMiles)
                        edited.firstMonths = Units.parseWholeNumber(firstMonths)
                        edited.unsure = false
                        onSave(edited)
                        dismiss()
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func number(_ label: String, _ text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("—", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing)
        }
    }
}

/// The manual pages that were read, to compare against.
private struct ManualPageViewer: View {
    let pages: [Data]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView {
                ForEach(pages.indices, id: \.self) { ZoomablePhoto(data: pages[$0]) }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("Close")
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .environment(\.colorScheme, .dark)
    }
}
