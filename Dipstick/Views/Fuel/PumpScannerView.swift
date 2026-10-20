//
//  PumpScannerView.swift
//  Dipstick
//

import SwiftUI
import VisionKit
import AVFoundation

/// Full-screen pump scanner (design board G). Reads the pump's display from
/// the live camera feed; once a reading checks out on a few frames it's
/// handed back. If live reading doesn't lock on (glare, odd angle), the
/// capture button reads one still photo harder (see `PumpPhotoReader`); the
/// photo is never saved. Always dark, since it sits over the camera.
///
/// Debug builds also show the raw text being read, and can share a capture
/// that failed, for tuning with tools/scan_pump_photo.swift.
struct PumpScannerView: View {
    let vehicle: Vehicle
    /// The car's recent price per gallon, to reject implausible readings.
    var expectedPrice: Double?
    let onReading: (PumpReadingParser.Reading) -> Void
    let onEnterManually: () -> Void
    let onClose: () -> Void

    @State private var boxes: [ScanBox] = []
    @State private var isTorchOn = false
    @State private var handle = ScannerHandle()
    @State private var liveText: [String] = []
    @State private var isReadingPhoto = false
    @State private var captureFailed = false
    /// Debug builds: the failed capture, to share for tuning.
    @State private var failedPhotoURL: URL?

    private var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isSupported {
                LiveTextScanner(expectedPrice: expectedPrice, handle: handle, onConfirmed: onReading,
                                onText: { liveText = $0 }) { boxes = $0 }
                    .ignoresSafeArea()
                    .overlay {
                        ForEach(boxes) { box in
                            ScanBoxView(box: box)
                        }
                    }
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                #if DEBUG
                debugStrip
                #endif
                Spacer()
                if isSupported {
                    ScanFrame()
                        .frame(width: 260, height: 240)
                        .allowsHitTesting(false)
                    Text(statusText)
                        .font(.dipstick(16, .semibold, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 28)
                    #if DEBUG
                    if captureFailed, let failedPhotoURL {
                        ShareLink(item: failedPhotoURL) {
                            Label("Share photo for tuning", systemImage: "square.and.arrow.up")
                                .font(.dipstick(13, .semibold, relativeTo: .footnote))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 10)
                    }
                    #endif
                } else {
                    Text("Scanning isn't available on this device, or camera access is off in Settings › Dipstick.")
                        .font(.dipstick(15, relativeTo: .body))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
                if isSupported {
                    captureButton.padding(.bottom, 16)
                }
                Button(action: onEnterManually) {
                    Text("Enter manually")
                }
                .buttonStyle(BigActionButtonStyle(height: 56))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .environment(\.colorScheme, .dark)
        .onDisappear { setTorch(false) }
    }

    private var statusText: String {
        if isReadingPhoto { return "Reading photo…" }
        if captureFailed { return "Couldn't read that one. Try another angle, or shade the screen from the sun." }
        return "Point at the pump display"
    }

    /// Takes one still photo and reads it harder than the live feed.
    private var captureButton: some View {
        Button(action: capture) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 68, height: 68)
                if isReadingPhoto {
                    ProgressView().tint(.white)
                } else {
                    Circle().fill(.white).frame(width: 54, height: 54)
                }
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isReadingPhoto)
        .accessibilityLabel("Capture photo of the display")
    }

    private func capture() {
        guard let scanner = handle.scanner else { return }
        isReadingPhoto = true
        captureFailed = false
        let expectedPrice = expectedPrice
        Task {
            defer { isReadingPhoto = false }
            guard let photo = try? await scanner.capturePhoto(), let cgImage = photo.cgImage else {
                captureFailed = true
                return
            }
            let orientation = CGImagePropertyOrientation(photo.imageOrientation)
            let result = await Task.detached(priority: .userInitiated) {
                PumpPhotoReader.read(cgImage, orientation: orientation, expectedPrice: expectedPrice)
            }.value
            if let reading = result.reading {
                handle.finish()
                onReading(reading)
            } else {
                captureFailed = true
                #if DEBUG
                failedPhotoURL = Self.writeForSharing(photo)
                #endif
            }
        }
    }

    #if DEBUG
    /// Raw text the live scanner reads, newest frame, numbers only.
    private var debugStrip: some View {
        let numeric = liveText.filter { $0.contains(where: \.isNumber) }
        return Text(numeric.isEmpty ? "DEBUG · no numbers read" : "DEBUG · " + numeric.joined(separator: " | "))
            .font(.readout(12, relativeTo: .caption))
            .foregroundStyle(.white)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.6)))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    private static func writeForSharing(_ photo: UIImage) -> URL? {
        guard let data = photo.jpegData(compressionQuality: 0.9) else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pump-\(stamp).jpg")
        return (try? data.write(to: url)) != nil ? url : nil
    }
    #endif

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("Close scanner")

            Spacer()

            HStack(spacing: 8) {
                vehicle.chip
                Text(vehicle.name.uppercased())
                    .font(.dipstick(13, .semibold, relativeTo: .subheadline))
                    .tracking(1.5)
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minimumHitTarget)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.controlSmallBorder, lineWidth: 1))

            Spacer()

            Button { setTorch(!isTorchOn) } label: {
                Image(systemName: isTorchOn ? "bolt.fill" : "bolt").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle(foreground: isTorchOn ? Theme.accent : Theme.text))
            .accessibilityLabel(isTorchOn ? "Turn flashlight off" : "Turn flashlight on")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch,
              (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
        isTorchOn = on && device.torchMode == .on
    }
}

/// Off-white corner brackets framing the scan area.
private struct ScanFrame: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height, arm: CGFloat = 36, r: CGFloat = 14
            Path { p in
                // top-left
                p.move(to: CGPoint(x: 0, y: arm)); p.addLine(to: CGPoint(x: 0, y: r))
                p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero); p.addLine(to: CGPoint(x: arm, y: 0))
                // top-right
                p.move(to: CGPoint(x: w - arm, y: 0)); p.addLine(to: CGPoint(x: w - r, y: 0))
                p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: arm))
                // bottom-right
                p.move(to: CGPoint(x: w, y: h - arm)); p.addLine(to: CGPoint(x: w, y: h - r))
                p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - arm, y: h))
                // bottom-left
                p.move(to: CGPoint(x: arm, y: h)); p.addLine(to: CGPoint(x: r, y: h))
                p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - arm))
            }
            .stroke(Color(hex: 0xEEF2F7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

/// A recognized number on the pump display, outlined and labeled.
struct ScanBox: Identifiable, Equatable {
    let label: String
    let rect: CGRect
    var id: String { label }
}

private struct ScanBoxView: View {
    let box: ScanBox

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .frame(width: box.rect.width + 12, height: box.rect.height + 8)
            .overlay(alignment: .topLeading) {
                Text(box.label)
                    .font(.dipstick(10, .semibold, relativeTo: .caption2))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                    .fixedSize()
                    .offset(y: -15)
            }
            .position(x: box.rect.midX, y: box.rect.midY)
            .allowsHitTesting(false)
    }
}

/// VisionKit's `DataScannerViewController` wrapped for SwiftUI. Every time the
/// recognized text changes, all of it is parsed as one frame, and the numbers
/// used are reported as boxes in the scanner view's coordinates.
private struct LiveTextScanner: UIViewControllerRepresentable {
    let expectedPrice: Double?
    let handle: ScannerHandle
    let onConfirmed: (PumpReadingParser.Reading) -> Void
    let onText: ([String]) -> Void
    let onBoxes: ([ScanBox]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        handle.scanner = scanner
        handle.coordinator = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(expectedPrice: expectedPrice, onConfirmed: onConfirmed, onText: onText, onBoxes: onBoxes)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let expectedPrice: Double?
        private let onConfirmed: (PumpReadingParser.Reading) -> Void
        private let onText: ([String]) -> Void
        private let onBoxes: ([ScanBox]) -> Void
        private var voter = PumpReadingVoter()
        /// Set once a reading has been handed back (live or from a capture).
        var done = false

        init(expectedPrice: Double?,
             onConfirmed: @escaping (PumpReadingParser.Reading) -> Void,
             onText: @escaping ([String]) -> Void,
             onBoxes: @escaping ([ScanBox]) -> Void) {
            self.expectedPrice = expectedPrice
            self.onConfirmed = onConfirmed
            self.onText = onText
            self.onBoxes = onBoxes
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removed: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !done else { return }
            let texts: [(transcript: String, rect: CGRect)] = items.compactMap { item in
                guard case .text(let text) = item else { return nil }
                let b = text.bounds
                let xs = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x]
                let ys = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y]
                let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                return (text.transcript, rect)
            }
            onText(texts.map(\.transcript))
            let reading = PumpReadingParser.parse(texts.map(\.transcript), expectedPrice: expectedPrice)
            onBoxes(reading.map { Self.boxes(for: $0, in: texts) } ?? [])
            if let confirmed = voter.add(reading) {
                done = true
                onConfirmed(confirmed)
            }
        }

        /// Which recognized lines hold the total, gallons and price.
        private static func boxes(for reading: PumpReadingParser.Reading,
                                  in texts: [(transcript: String, rect: CGRect)]) -> [ScanBox] {
            var result: [ScanBox] = []
            func find(_ label: String, _ value: Double, decimals: Int) {
                guard let match = texts.first(where: { text in
                    PumpReadingParser.numbers(in: text.transcript).contains {
                        abs($0.value - value) < 0.0005 && $0.decimals == decimals
                    }
                }) else { return }
                result.append(ScanBox(label: label, rect: match.rect))
            }
            find("TOTAL", reading.total, decimals: 2)
            find("GALLONS", reading.gallons, decimals: 3)
            if reading.confidence == .checked {
                find("PRICE / GAL", reading.pricePerGallon, decimals: 3)
            }
            return result
        }
    }
}

/// Lets the SwiftUI view reach the live scanner to capture a still photo, and
/// stop live reading once a capture has filled the form.
@MainActor
final class ScannerHandle {
    weak var scanner: DataScannerViewController?
    fileprivate weak var coordinator: LiveTextScanner.Coordinator?

    func finish() { coordinator?.done = true }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
