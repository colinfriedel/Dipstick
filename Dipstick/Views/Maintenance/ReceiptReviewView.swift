//
//  ReceiptReviewView.swift
//  Dipstick
//

import SwiftUI
import ImageIO
import UIKit

/// Review a receipt before adding its parts to a service: tick the items
/// that were for this job (fix any name or price), see the tax (and
/// shipping) split across them, and add them as parts. Items not ticked,
/// and their share of the tax, stay out of the job's cost.
struct ReceiptReviewView: View {
    let imageData: Data
    /// Adds the parts; `keepPhoto` is the receipt to keep with the
    /// service's notes and photos, if chosen.
    let onAdd: (_ parts: [ReceiptSplit.Part], _ keepPhoto: Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.reading
    @State private var receipt = ReceiptParser.Receipt()
    @State private var chosen: Set<UUID> = []
    @State private var includeShipping = true
    @State private var keepsPhoto = false
    @State private var prices: [UUID: String] = [:]
    @State private var quantities: [UUID: Int] = [:]
    /// Debug builds: the lines text recognition read, for tuning.
    @State private var readLines: [String] = []
    @State private var usedModel = false
    @FocusState private var focused: UUID?

    private enum Phase { case reading, ready, failed }

    // MARK: Numbers

    /// The receipt with any prices typed over.
    private var edited: ReceiptParser.Receipt {
        var r = receipt
        for index in r.items.indices {
            if let text = prices[r.items[index].id], let value = Units.parseDecimal(text) {
                r.items[index].lineTotal = value
            }
            if let quantity = quantities[r.items[index].id] { r.items[index].quantity = quantity }
        }
        return r
    }

    private var parts: [ReceiptSplit.Part] {
        ReceiptSplit.parts(of: edited, chosen: chosen, includeShipping: includeShipping)
    }

    private var partsTotal: Double { parts.reduce(0) { $0 + $1.total } }

    // MARK: Body

    var body: some View {
        // The header stays put above the scrolling list, so Cancel can't
        // scroll up under the status bar.
        VStack(spacing: 0) {
            FormHeader(title: "From receipt", vehicle: nil) { dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Theme.ground)
                .modifier(TopSafeAreaFallback())
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch phase {
                case .reading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading receipt…")
                            .font(.dipstick(15, relativeTo: .body))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                case .failed:
                    Text("Couldn't find any items on that receipt. Try a sharper, straighter photo, or add the parts by hand.")
                        .font(.dipstick(15, relativeTo: .body))
                        .foregroundStyle(Theme.muted)
                        .padding(16)
                        .panel()
                case .ready:
                    content
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            if phase == .ready {
                FormSaveBar(title: parts.isEmpty ? "Tick this job's items"
                                : "Add \(parts.count) part\(parts.count == 1 ? "" : "s") · \(Units.currency(partsTotal))",
                            isEnabled: !parts.isEmpty, isKeyboardUp: focused != nil,
                            onHideKeyboard: { focused = nil }) {
                    onAdd(parts, keepsPhoto ? PhotoStore.downsized(imageData) : nil)
                    dismiss()
                }
            }
        }
        .tint(Theme.accent)
        .task { await read() }
    }

    @ViewBuilder
    private var content: some View {
        let r = edited
        SectionTitle("Items") {
            Text("Tick the ones for this job")
                .font(.dipstick(11.5, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
        VStack(spacing: 0) {
            ForEach(Array(receipt.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { FormDivider() }
                itemRow(item)
            }
        }
        .panel(radius: Theme.Radius.field)

        SectionTitle("Receipt").padding(.top, 8)
        VStack(spacing: 0) {
            summaryRow("Subtotal", r.subtotal ?? r.itemsTotal)
            if let tax = r.tax {
                FormDivider()
                summaryRow("Tax", tax, detail: (r.subtotal ?? r.itemsTotal) > 0
                           ? String(format: "%.2f%%", tax / (r.subtotal ?? r.itemsTotal) * 100) : nil)
            }
            if let shipping = r.shipping, shipping > 0 {
                FormDivider()
                summaryRow("Shipping", shipping)
            }
            if let total = r.total {
                FormDivider()
                summaryRow("Total", total)
            }
        }
        .panel(radius: Theme.Radius.field)
        if r.checks {
            StatusLine(status: .ok, text: "Items, tax and total add up")
        } else {
            StatusLine(status: .dueSoon, text: "Items add up to \(Units.currency(r.itemsTotal)), not \(Units.currency(r.subtotal ?? r.total ?? 0)). Check the prices, or a missed item.")
        }

        VStack(spacing: 0) {
            if (r.shipping ?? 0) > 0 {
                Toggle(isOn: $includeShipping) { toggleLabel("Include shipping", "Split across the ticked items, like tax") }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                FormDivider()
            }
            Toggle(isOn: $keepsPhoto) { toggleLabel("Keep the receipt", "Saved with this service's notes and photos") }
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .panel(radius: Theme.Radius.field)
        .padding(.top, 8)

        if !parts.isEmpty {
            Text(splitSummary)
                .font(.dipstick(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }

        #if DEBUG
        DisclosureGroup("DEBUG · what was read\(usedModel ? " (model)" : "")") {
            Text(readLines.joined(separator: "\n"))
                .font(.readout(11, relativeTo: .caption2))
                .foregroundStyle(Theme.muted)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.dipstick(12, relativeTo: .caption))
        .foregroundStyle(Theme.muted)
        .padding(.top, 8)
        #endif
    }

    private var splitSummary: String {
        let itemsOnly = edited.items.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.lineTotal }
        let extra = partsTotal - itemsOnly
        return "This job: \(Units.currency(itemsOnly)) in items + \(Units.currency(extra)) of the tax"
            + (includeShipping && (edited.shipping ?? 0) > 0 ? " and shipping" : "") + " = \(Units.currency(partsTotal))"
    }

    private func itemRow(_ item: ReceiptParser.Item) -> some View {
        let isChosen = chosen.contains(item.id)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isChosen ? Theme.accent : Theme.faint)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(isChosen ? Theme.text : Theme.muted)
                let quantity = quantities[item.id] ?? item.quantity
                HStack(spacing: 8) {
                    if let partNumber = item.partNumber {
                        Text("#\(partNumber)")
                            .font(.readout(12, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                    }
                    quantityStepper(item.id, quantity)
                }
                .padding(.top, 2)
                if quantity > 1, let total = edited.items.first(where: { $0.id == item.id })?.lineTotal {
                    Text("\(Units.currency(total / Double(quantity))) each")
                        .font(.readout(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            TextField("Price", text: Binding(
                get: { prices[item.id] ?? String(format: "%.2f", item.lineTotal) },
                set: { prices[item.id] = $0 }))
                .font(.readout(16, relativeTo: .body))
                .foregroundStyle(isChosen ? Theme.text : Theme.muted)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 80)
                .focused($focused, equals: item.id)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // Tap anywhere but the price to tick or untick.
        .onTapGesture {
            focused = nil
            if isChosen { chosen.remove(item.id) } else { chosen.insert(item.id) }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isChosen ? "For this job" : "Not for this job")
    }

    /// "− ×2 +": how many of the item (a "Pack of 2" is two).
    private func quantityStepper(_ id: UUID, _ quantity: Int) -> some View {
        HStack(spacing: 0) {
            Button { quantities[id] = max(1, quantity - 1) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 30)
            }
            .disabled(quantity <= 1)
            Text("×\(quantity)")
                .font(.readout(13, relativeTo: .caption))
                .foregroundStyle(Theme.text)
                .frame(minWidth: 26)
            Button { quantities[id] = min(99, quantity + 1) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 30)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .background(Capsule().fill(Theme.selectedFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quantity")
        .accessibilityValue("\(quantity)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: quantities[id] = min(99, quantity + 1)
            case .decrement: quantities[id] = max(1, quantity - 1)
            @unknown default: break
            }
        }
    }

    private func summaryRow(_ label: String, _ value: Double, detail: String? = nil) -> some View {
        FormRow(label, subtitle: detail) {
            MonoNumber(text: Units.currency(value), size: 15)
        }
    }

    private func toggleLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.dipstick(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.text)
            Text(subtitle).font(.dipstick(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Reading

    private func read() async {
        // Once: the task can run again when the view reappears, and new
        // items would orphan the ticks.
        guard phase == .reading, receipt.items.isEmpty else { return }
        guard let (image, orientation) = Self.decode(imageData) else {
            phase = .failed
            return
        }
        let result = await ReceiptReader.read(image, orientation: orientation)
        guard phase == .reading else { return }
        receipt = result.receipt
        chosen = chosen.intersection(receipt.items.map(\.id))
        readLines = result.lines
        usedModel = result.usedModel
        // One item: it's surely for this job.
        if receipt.items.count == 1 { chosen = [receipt.items[0].id] }
        phase = receipt.items.isEmpty ? .failed : .ready
    }

    static func decode(_ data: Data) -> (CGImage, CGImagePropertyOrientation)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init) ?? .up
        return (image, orientation)
    }
}

/// Opened right as the photo picker closes, a full-screen cover can be laid
/// out with no top safe area, putting Cancel under the status bar. If so,
/// pad by the window's own inset.
private struct TopSafeAreaFallback: ViewModifier {
    @State private var missing: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.top, missing)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { top in
                let window = UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.top ?? 0
                missing = top < 1 ? window : 0
            }
    }
}

/// The system camera, for photographing a paper receipt. Returns JPEG data.
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPhoto: onPhoto) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPhoto: (Data?) -> Void
        init(onPhoto: @escaping (Data?) -> Void) { self.onPhoto = onPhoto }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPhoto((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPhoto(nil) }
    }
}
