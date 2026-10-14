//
//  PumpScannerView.swift
//  Dipstick
//

import SwiftUI
import VisionKit

/// Live camera view that reads the pump display and fills in the fill-up.
/// No photo is taken or stored: text is read from the camera feed and only
/// the numbers are kept. A reading is accepted once it checks out
/// (gallons × price = total) on several frames.
struct PumpScannerView: View {
    /// The car's recent price per gallon, to reject implausible readings.
    var expectedPrice: Double?
    let onReading: (PumpReadingParser.Reading) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var latest: PumpReadingParser.Reading?

    private var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSupported {
                    LiveTextScanner(expectedPrice: expectedPrice) { reading in
                        onReading(reading)
                        dismiss()
                    } onFrame: { latest = $0 }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) { statusCard }
                } else {
                    ContentUnavailableView(
                        "Scanning Not Available",
                        systemImage: "camera.metering.unknown",
                        description: Text("This device can't scan text live (the simulator can't), or camera access is off in Settings > Dipstick.")
                    )
                }
            }
            .navigationTitle("Scan Pump")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 6) {
            if let latest {
                Text("\(Units.gallons(latest.gallons)) · \(Units.currency(latest.total))")
                    .font(.headline)
                    .monospacedDigit()
                Text("Hold steady…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Point at the pump's main screen")
                    .font(.headline)
                Text("Fit the total and gallons in the frame and hold steady.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding()
    }
}

/// VisionKit's `DataScannerViewController` wrapped for SwiftUI. Every time the
/// recognized text changes, all of it is parsed as one frame.
private struct LiveTextScanner: UIViewControllerRepresentable {
    let expectedPrice: Double?
    let onConfirmed: (PumpReadingParser.Reading) -> Void
    let onFrame: (PumpReadingParser.Reading?) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(expectedPrice: expectedPrice, onConfirmed: onConfirmed, onFrame: onFrame)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onConfirmed: (PumpReadingParser.Reading) -> Void
        private let onFrame: (PumpReadingParser.Reading?) -> Void
        private var voter = PumpReadingVoter()
        private var done = false
        private let expectedPrice: Double?

        init(expectedPrice: Double?,
             onConfirmed: @escaping (PumpReadingParser.Reading) -> Void,
             onFrame: @escaping (PumpReadingParser.Reading?) -> Void) {
            self.expectedPrice = expectedPrice
            self.onConfirmed = onConfirmed
            self.onFrame = onFrame
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !done else { return }
            let lines = items.compactMap { item -> String? in
                if case .text(let text) = item { return text.transcript }
                return nil
            }
            let reading = PumpReadingParser.parse(lines, expectedPrice: expectedPrice)
            onFrame(reading)
            if let confirmed = voter.add(reading) {
                done = true
                onConfirmed(confirmed)
            }
        }
    }
}
