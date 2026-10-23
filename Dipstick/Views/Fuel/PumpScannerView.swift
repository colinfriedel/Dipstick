//
//  PumpScannerView.swift
//  Dipstick
//

import SwiftUI
import AVFoundation

/// Full-screen pump scanner (design board G). Reads the seven-segment
/// display in the scan frame (see `SegmentDisplayReader`): live, a reading
/// fills the form once it's seen on a few frames and its price works out to
/// a usual x.xx9 pump price (or matches a price on the display); the capture
/// button reads one full-resolution still and takes its best reading.
/// Photos are never saved. Always dark, since it sits over the camera.
///
/// Debug builds also show what's being read, and can share a capture that
/// failed, for tuning with tools/scan_segments.swift.
struct PumpScannerView: View {
    let vehicle: Vehicle
    /// The car's recent price per gallon, to reject implausible readings.
    var expectedPrice: Double?
    /// A reading, with the photo it came from (for reporting a misread).
    let onReading: (PumpReadingParser.Reading, ScanEvidence?) -> Void
    /// Carries the last capture that couldn't be read, if any.
    let onEnterManually: (ScanEvidence?) -> Void
    let onClose: () -> Void

    @State private var camera = PumpCamera()
    @State private var cameraState = CameraState.starting
    @State private var isTorchOn = false
    /// Debug builds: what live reading last saw.
    @State private var liveSummary = ""
    @State private var liveVoter = PumpReadingVoter()
    @State private var isReadingPhoto = false
    @State private var captureFailed = false
    @State private var isFinished = false
    /// The last capture that couldn't be read, offered for reporting.
    @State private var unreadCapture: ScanEvidence?
    /// The latest live frame that read something.
    @State private var liveEvidence: ScanEvidence?
    /// Scan frame on screen, in the camera view's coordinates.
    @State private var frameRect: CGRect = .zero
    /// Debug builds: what the last still read.
    @State private var lastCaptureSummary = ""

    private enum CameraState { case starting, running, unavailable }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if cameraState != .unavailable {
                    PumpCameraPreview(camera: camera)
                }

                VStack(spacing: 0) {
                    topBar
                    #if DEBUG
                    debugStrip
                    #endif
                    Spacer()
                    if cameraState != .unavailable {
                        // Pump displays are wide and short.
                        ScanFrame()
                            .frame(width: 330, height: 200)
                            .allowsHitTesting(false)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { rect in
                                frameRect = rect
                                camera.layout = .init(frame: rect, viewSize: proxy.size)
                            }
                        Text(statusText)
                            .font(.dipstick(16, .semibold, relativeTo: .headline))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 28)
                    } else {
                        Text("Scanning isn't available on this device, or camera access is off in Settings › Dipstick.")
                            .font(.dipstick(15, relativeTo: .body))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                    if cameraState == .running {
                        captureButton.padding(.bottom, 16)
                    }
                    Button { onEnterManually(unreadCapture) } label: {
                        Text("Enter manually")
                    }
                    .buttonStyle(BigActionButtonStyle(height: 56))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .padding(.top, proxy.safeAreaInsets.top)
                .padding(.bottom, proxy.safeAreaInsets.bottom)
            }
            .ignoresSafeArea()
            .onChange(of: proxy.size) { camera.layout = .init(frame: frameRect, viewSize: proxy.size) }
        }
        .coordinateSpace(.named(Self.space))
        .environment(\.colorScheme, .dark)
        .task { await startCamera() }
        .onDisappear {
            camera.stop()
            isTorchOn = false
        }
    }

    /// The camera view's coordinate space (full screen, under the safe areas).
    private static let space = "PumpScanner"

    private var statusText: String {
        if isReadingPhoto { return "Reading photo…" }
        if captureFailed { return "Couldn't read that one. Try another angle, or shade the screen from the sun." }
        return "Point at the pump display, or tap to capture"
    }

    // MARK: Camera

    private func startCamera() async {
        camera.expectedPrice = expectedPrice
        camera.onLiveFrame = { handleLive($0) }
        guard PumpCamera.isAvailable, await camera.start() else {
            cameraState = .unavailable
            return
        }
        cameraState = .running
    }

    /// Live reading: fill the form once a reading has held for a few frames.
    private func handleLive(_ frame: PumpCamera.LiveFrame) {
        guard !isFinished, !isReadingPhoto else { return }
        #if DEBUG
        liveSummary = frame.reading.map(Self.describe) ?? "nothing"
        #endif
        if let evidence = frame.evidence { liveEvidence = evidence }
        if let confirmed = liveVoter.add(frame.reading) {
            finish(with: confirmed, evidence: liveEvidence)
        }
    }

    private func finish(with reading: PumpReadingParser.Reading, evidence: ScanEvidence?) {
        guard !isFinished else { return }
        isFinished = true
        camera.isPaused = true
        onReading(reading, evidence)
    }

    private static func describe(_ reading: PumpReadingParser.Reading) -> String {
        String(format: "%.3f gal $%.2f %@", reading.gallons, reading.total,
               reading.confidence == .priceInferred ? "(price unchecked)" : "✓")
    }

    // MARK: Capture

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

    /// The capture button: reads one still and takes its best reading.
    private func capture() {
        isReadingPhoto = true
        captureFailed = false
        camera.isPaused = true
        Task {
            defer {
                isReadingPhoto = false
                if !isFinished { camera.isPaused = false }
            }
            let (cgImage, orientation): (CGImage, CGImagePropertyOrientation)
            do {
                (cgImage, orientation) = try await camera.capturePhoto()
            } catch {
                noteCapture("still: capture failed: \(error.localizedDescription)")
                captureFailed = true
                return
            }
            let size = Self.orientedSize(of: cgImage, orientation)
            // Generous: the reader finds the digits itself, and a digit cut
            // off at the crop's edge would mean no reading.
            let crop = PumpPhotoReader.crop(for: frameRect, in: camera.layout.viewSize, photoSize: size, margin: 0.35)
            let expectedPrice = expectedPrice
            let result = await Task.detached(priority: .userInitiated) {
                SegmentDisplayReader.read(cgImage, orientation: orientation, crop: crop, expectedPrice: expectedPrice)
            }.value
            noteCapture("still: " + (result.reading.map(Self.describe) ?? "no reading"))
            let evidence = ScanEvidence(image: cgImage, orientation: orientation, crop: crop, reading: result.reading)
            if let reading = result.reading {
                finish(with: reading, evidence: evidence)
            } else {
                captureFailed = true
                unreadCapture = evidence
            }
        }
    }

    private static func orientedSize(of image: CGImage, _ orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: CGSize(width: image.height, height: image.width)
        default: CGSize(width: image.width, height: image.height)
        }
    }

    /// Debug builds: shows what the last capture did on the debug strip.
    private func noteCapture(_ text: String) {
        #if DEBUG
        lastCaptureSummary = text
        #endif
    }

    #if DEBUG
    /// What live reading sees, and the last capture.
    private var debugStrip: some View {
        Text("DEBUG · live: \(liveSummary.isEmpty ? "starting" : liveSummary)"
             + (lastCaptureSummary.isEmpty ? "" : "\n\(lastCaptureSummary)"))
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

            Button {
                isTorchOn.toggle()
                camera.setTorch(isTorchOn)
            } label: {
                Image(systemName: isTorchOn ? "bolt.fill" : "bolt").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle(foreground: isTorchOn ? Theme.accent : Theme.text))
            .accessibilityLabel(isTorchOn ? "Turn flashlight off" : "Turn flashlight on")
            .disabled(cameraState != .running)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
