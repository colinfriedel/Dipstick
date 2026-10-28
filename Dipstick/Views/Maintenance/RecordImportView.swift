//
//  RecordImportView.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Import service records from photos, screenshots, PDFs or spreadsheets:
/// pick them, they're read on the phone, then you check what was found
/// (doubtful values are marked) before anything is saved. A Dipstick CSV
/// goes to the regular CSV import instead.
struct RecordImportView: View {
    let vehicle: Vehicle
    /// A Dipstick CSV was picked: the regular CSV import takes it.
    let onDipstickCSV: (_ filename: String, _ parsed: RecordCSV.Parsed) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase = Phase.choose
    @State private var pages: [RecordReader.Page] = []
    @State private var visits: [RecordImport.Visit] = []
    @State private var usedModel = true
    @State private var editing: RecordImport.Visit?
    @State private var viewingPage: PageToView?

    @State private var isPickingPhotos = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var isTakingPhoto = false
    @State private var isPickingFile = false
    @State private var isChoosingMore = false
    @State private var problem: String?

    private enum Phase: Equatable {
        case choose
        case reading(done: Int, total: Int)
        case review
        case imported(Int)
    }

    struct PageToView: Identifiable {
        let id: Int
    }

    /// Service names to match: this car's, its schedule's, then the usual ones.
    private var knownNames: [String] {
        var seen = Set<String>()
        var names: [String] = (vehicle.maintenanceEntries ?? []).map(\.serviceType)
        names += vehicle.sortedScheduleItems.map(\.serviceType)
        names += ServiceType.builtIn
        names += ["Tires", "Alignment", "Smog check"]
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            FormHeader(title: "Import records", vehicle: vehicle) { dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Theme.ground)
                .modifier(TopSafeAreaFallback())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch phase {
                    case .choose: chooseContent
                    case .reading(let done, let total): readingContent(done: done, total: total)
                    case .review: reviewContent
                    case .imported(let count): importedContent(count)
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
                let count = rowsToImport.count
                FormSaveBar(title: !canImport ? "Add the missing dates and mileage"
                                : count == 0 ? "Tick services to import"
                                : "Import \(count) service\(count == 1 ? "" : "s")",
                            isEnabled: canImport && count > 0, isKeyboardUp: false, onHideKeyboard: {}) {
                    importRecords()
                }
            }
        }
        .tint(Theme.accent)
        .photosPicker(isPresented: $isPickingPhotos, selection: $pickedPhotos, maxSelectionCount: 30,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: pickedPhotos) { readPickedPhotos() }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { data in
                isTakingPhoto = false
                guard let data else { return }
                read { [RecordReader.page(fromImage: data)].compactMap { $0 } }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isPickingFile,
                      allowedContentTypes: [.pdf, .commaSeparatedText, .tabSeparatedText, .plainText, .image]) { result in
            readFile(result)
        }
        .confirmationDialog("Add more pages", isPresented: $isChoosingMore) {
            Button("Photos or Screenshots") { isPickingPhotos = true }
            Button("Take Photo") { isTakingPhoto = true }
            Button("PDF or Spreadsheet") { isPickingFile = true }
        }
        .sheet(item: $editing) { visit in
            VisitEditor(visit: visit, hasPage: pages.indices.contains(visit.page) && pages[visit.page].preview != nil,
                        onShowPage: { viewingPage = PageToView(id: visit.page) }) { edited in
                if let i = visits.firstIndex(where: { $0.id == edited.id }) { visits[i] = edited }
            } onDelete: {
                visits.removeAll { $0.id == visit.id }
            }
        }
        .fullScreenCover(item: $viewingPage) { page in
            PageViewer(pages: pages.map(\.preview), start: min(page.id, pages.count - 1))
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
        Text("Add photos or screenshots of invoices, a vehicle history report (like Carfax) or your own service log, or a PDF or spreadsheet. Pick all the pages at once.")
            .font(.dipstick(15, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        Text("Everything is read on this iPhone. You'll check what was found before anything is saved.")
            .font(.dipstick(13, relativeTo: .footnote))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)

        VStack(spacing: 10) {
            sourceButton("Photos or screenshots", icon: "photo.on.rectangle") { isPickingPhotos = true }
            sourceButton("Take a photo", icon: "camera") { isTakingPhoto = true }
            sourceButton("PDF or spreadsheet", icon: "doc") { isPickingFile = true }
        }
        .padding(.top, 6)

        if !Self.hasLanguageModel {
            StatusLine(status: .dueSoon, text: "Apple Intelligence is off or not available on this iPhone, so only simple lists and invoices can be read. Turn it on in Settings › Apple Intelligence & Siri for best results.")
                .padding(.top, 6)
        }
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

    static var hasLanguageModel: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    // MARK: Reading

    private func readingContent(done: Int, total: Int) -> some View {
        VStack(spacing: 14) {
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
            } else {
                ProgressView()
            }
            Text(total > 1 ? "Reading part \(min(done + 1, total)) of \(total)…" : "Reading…")
                .font(.dipstick(15, relativeTo: .body))
                .foregroundStyle(Theme.muted)
            Text("This can take a minute for long reports. Keep the app open.")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func readPickedPhotos() {
        let items = pickedPhotos
        guard !items.isEmpty else { return }
        pickedPhotos = []
        phase = .reading(done: 0, total: 0)
        Task {
            var images: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
            }
            read { images.compactMap(RecordReader.page(fromImage:)) }
        }
    }

    private func readFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension)

        if type?.conforms(to: .pdf) == true {
            guard let data = try? Data(contentsOf: url) else { problem = "The file couldn't be opened."; return }
            let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".pdf")
            try? data.write(to: copy)
            read { RecordReader.pages(fromPDF: copy) }
        } else if type?.conforms(to: .image) == true {
            guard let data = try? Data(contentsOf: url) else { problem = "The file couldn't be opened."; return }
            read { [RecordReader.page(fromImage: data)].compactMap { $0 } }
        } else {
            guard let text = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
                problem = "The file couldn't be opened."
                return
            }
            let tabbed = url.pathExtension.lowercased() == "tsv" ? text.replacingOccurrences(of: "\t", with: ",") : text
            let dipstick = RecordCSV.decode(tabbed)
            if !dipstick.problems.contains(where: { $0.row == 1 }) {
                dismiss()
                onDipstickCSV(url.lastPathComponent, dipstick)
            } else if let found = RecordImport.visits(fromCSV: tabbed, known: knownNames), !found.isEmpty {
                pages = []
                finish(RecordImport.tidy(found), usedModel: true)
            } else {
                read { [RecordReader.Page(text: text, preview: nil)] }
            }
        }
    }

    /// Reads pages (made off the main thread) and shows what was found,
    /// adding to anything already found.
    private func read(_ makePages: @escaping @Sendable () -> [RecordReader.Page]) {
        phase = .reading(done: 0, total: 0)
        let known = knownNames
        Task {
            let newPages = await Task.detached(priority: .userInitiated) { makePages() }.value
            guard !newPages.isEmpty else {
                phase = visits.isEmpty ? .choose : .review
                problem = "No text could be read. Try a sharper, straighter photo."
                return
            }
            let offset = pages.count
            pages += newPages
            let result = await RecordReader.read(newPages, known: known) { done, total in
                await MainActor.run { phase = .reading(done: done, total: total) }
            }
            let shifted = result.visits.map { var v = $0; v.page += offset; return v }
            finish(RecordImport.tidy(visits + shifted), usedModel: result.usedModel)
        }
    }

    private func finish(_ found: [RecordImport.Visit], usedModel: Bool) {
        var found = found
        RecordImport.markDuplicates(&found, existing: (vehicle.maintenanceEntries ?? []).map { ($0.date, $0.serviceType) })
        visits = found
        self.usedModel = usedModel
        if found.isEmpty {
            phase = .choose
            problem = "No service records were found. Try clearer photos, or pages that list the services done."
        } else {
            phase = .review
        }
    }

    // MARK: Reviewing

    private var rowsToImport: [RecordCSV.ServiceRow] { visits.flatMap(RecordImport.rows) }

    private var canImport: Bool {
        visits.filter { $0.include && !$0.includedServices.isEmpty }.allSatisfy(\.isComplete)
    }

    @ViewBuilder
    private var reviewContent: some View {
        let serviceCount = visits.reduce(0) { $0 + $1.services.count }
        let toCheck = visits.reduce(0) { total, visit in
            total + visit.unsure.count + visit.services.filter { $0.priceUnsure || $0.nameUnsure }.count
        }
        let duplicates = visits.reduce(0) { $0 + $1.services.filter(\.isDuplicate).count }

        VStack(alignment: .leading, spacing: 6) {
            Text("Found \(serviceCount) service\(serviceCount == 1 ? "" : "s") from \(visits.count) visit\(visits.count == 1 ? "" : "s")")
                .font(.dipstick(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.text)
            if toCheck > 0 {
                StatusLine(status: .dueSoon, text: "\(toCheck) value\(toCheck == 1 ? "" : "s") to check: tap a visit to fix or confirm")
            }
            if duplicates > 0 {
                Text("\(duplicates) already in your log, so left unticked.")
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }
            if !usedModel {
                Text("Read without Apple Intelligence, so prices and parts weren't picked up. Check each visit.")
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.bottom, 4)

        ForEach($visits) { $visit in
            VisitCard(visit: $visit, onEdit: { editing = visit },
                      onShowPage: pages.indices.contains(visit.page) && pages[visit.page].preview != nil
                        ? { viewingPage = PageToView(id: visit.page) } : nil)
        }

        Button { isChoosingMore = true } label: {
            Label("Add more pages", systemImage: "plus")
                .font(.dipstick(14, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func importRecords() {
        let rows = rowsToImport
        vehicle.importRecords(fuel: [], services: rows, into: modelContext)
        modelContext.saveNow()
        phase = .imported(rows.count)
    }

    private func importedContent(_ count: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Imported \(count) service\(count == 1 ? "" : "s")")
                .font(.dipstick(18, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.text)
            Text("They're in \(vehicle.name)'s Maintenance tab.")
                .font(.dipstick(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - One visit

/// A visit in the review list: date, mileage and shop, then its services
/// to tick. Values to check are marked; tap to edit.
private struct VisitCard: View {
    @Binding var visit: RecordImport.Visit
    let onEdit: () -> Void
    let onShowPage: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        value(visit.date.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) },
                              missing: "Add date", field: .date)
                        Text("·").foregroundStyle(Theme.faint)
                        value(visit.odometer.map { "\($0.formatted()) mi" }, missing: "Add mileage", field: .odometer)
                        Spacer(minLength: 6)
                        if let total = visit.total {
                            value(Units.currency(total), missing: "", field: .total)
                        }
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                    }
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    if let shop = visit.shop {
                        Text([shop, visit.invoice.map { "#\($0)" }].compactMap { $0 }.joined(separator: " "))
                            .font(.dipstick(13, relativeTo: .footnote))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach($visit.services) { $service in
                FormDivider()
                Button { service.include.toggle() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: service.include ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(service.include ? Theme.accent : Theme.faint)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(service.name)
                                    .font(.dipstick(15, relativeTo: .body))
                                    .foregroundStyle(!service.include ? Theme.muted : service.nameUnsure ? Theme.amber : Theme.text)
                                if service.nameUnsure {
                                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.amber)
                                }
                            }
                            if service.isDuplicate {
                                Text("Already in your log")
                                    .font(.dipstick(12, relativeTo: .caption))
                                    .foregroundStyle(Theme.muted)
                            } else if !service.parts.isEmpty {
                                Text(service.parts.map(\.name).joined(separator: ", "))
                                    .font(.dipstick(12, relativeTo: .caption))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        if let price = service.price, price > 0 {
                            Text(Units.currency(price))
                                .font(.readout(14, relativeTo: .body))
                                .foregroundStyle(service.priceUnsure ? Theme.amber : Theme.text)
                            if service.priceUnsure {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.amber)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(service.include ? .isSelected : [])
            }

            if let onShowPage {
                FormDivider()
                Button(action: onShowPage) {
                    Label("See page \(visit.page + 1)", systemImage: "doc.text.magnifyingglass")
                        .font(.dipstick(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .panel(radius: Theme.Radius.field,
               border: !visit.isComplete ? Theme.red
                   : visit.unsure.isEmpty && !visit.services.contains(where: { $0.priceUnsure || $0.nameUnsure })
                   ? Theme.panelBorder : Theme.amber.opacity(0.7))
        .opacity(visit.includedServices.isEmpty ? 0.6 : 1)
    }

    /// A value, amber with a mark when it needs checking, red when missing.
    @ViewBuilder
    private func value(_ text: String?, missing: String, field: RecordImport.Visit.Field) -> some View {
        if let text {
            HStack(spacing: 3) {
                Text(text).foregroundStyle(visit.unsure.contains(field) ? Theme.amber : Theme.text)
                if visit.unsure.contains(field) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.amber)
                }
            }
        } else if !missing.isEmpty {
            Text(missing).foregroundStyle(Theme.red)
        }
    }
}

// MARK: - Editing a visit

/// Fix or confirm a visit: date, mileage, shop, total, and each service's
/// name and price. Editing a value counts as checking it.
private struct VisitEditor: View {
    @State var visit: RecordImport.Visit
    let hasPage: Bool
    let onShowPage: () -> Void
    let onSave: (RecordImport.Visit) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var odometer = ""
    @State private var total = ""
    @State private var prices: [UUID: String] = [:]
    @State private var date = Date()
    @State private var hasDate = false

    init(visit: RecordImport.Visit, hasPage: Bool, onShowPage: @escaping () -> Void,
         onSave: @escaping (RecordImport.Visit) -> Void, onDelete: @escaping () -> Void) {
        _visit = State(initialValue: visit)
        self.hasPage = hasPage
        self.onShowPage = onShowPage
        self.onSave = onSave
        self.onDelete = onDelete
        _odometer = State(initialValue: visit.odometer.map(String.init) ?? "")
        _total = State(initialValue: visit.total.map { String(format: "%.2f", $0) } ?? "")
        _prices = State(initialValue: Dictionary(uniqueKeysWithValues: visit.services.map {
            ($0.id, $0.price.map { String(format: "%.2f", $0) } ?? "")
        }))
        _date = State(initialValue: visit.date ?? Date())
        _hasDate = State(initialValue: visit.date != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasDate {
                        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    } else {
                        Button("Add date") { hasDate = true }
                    }
                    LabeledContent("Mileage") {
                        TextField("Odometer", text: $odometer)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Shop") {
                        TextField("Optional", text: Binding(get: { visit.shop ?? "" },
                                                            set: { visit.shop = $0.isEmpty ? nil : $0 }))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Visit total") {
                        TextField("Optional", text: $total)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if !visit.unsure.isEmpty {
                        Text("Values marked ⚠ weren't found on the page or don't fit with the other visits. Saving here confirms them.")
                    }
                }

                Section("Services") {
                    ForEach($visit.services) { $service in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle(isOn: $service.include) {
                                    TextField("Service", text: $service.name)
                                }
                            }
                            HStack {
                                Text("Price").foregroundStyle(.secondary)
                                TextField("Optional", text: Binding(get: { prices[service.id] ?? "" },
                                                                    set: { prices[service.id] = $0 }))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                            if let notes = service.notes {
                                Text(notes).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { visit.services.remove(atOffsets: $0) }
                    Button("Add service") { visit.services.append(.init(name: "")) }
                }

                Section {
                    if hasPage {
                        Button("See the page") { onShowPage() }
                    }
                    Button("Remove this visit", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(edited)
                        dismiss()
                    }
                }
            }
        }
    }

    /// The visit as edited; anything you looked at here counts as checked.
    private var edited: RecordImport.Visit {
        var v = visit
        v.date = hasDate ? date : nil
        v.odometer = Units.parseWholeNumber(odometer.replacingOccurrences(of: ",", with: ""))
        v.total = Units.parseDecimal(total)
        v.services = v.services.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { s in
            var s = s
            s.price = Units.parseDecimal(prices[s.id] ?? "")
            s.priceUnsure = false
            s.nameUnsure = false
            return s
        }
        v.unsure = []
        return v
    }
}

// MARK: - The original page

/// The photo or PDF page records were read from, to compare against.
private struct PageViewer: View {
    let pages: [Data?]
    let start: Int
    @Environment(\.dismiss) private var dismiss
    @State private var current = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(pages.indices, id: \.self) { i in
                    ZoomablePhoto(data: pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SmallControlButtonStyle())
                .accessibilityLabel("Close")
                Spacer()
                if pages.count > 1 {
                    Text("Page \(current + 1) of \(pages.count)")
                        .font(.dipstick(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { current = start }
    }
}
