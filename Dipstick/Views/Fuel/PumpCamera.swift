//
//  PumpCamera.swift
//  Dipstick
//

@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import SwiftUI

/// The pump scanner's camera: a portrait preview, live text reading of the
/// scan frame, and still photos. Replaces VisionKit's DataScanner, which
/// couldn't read segment digits, couldn't crop or brighten frames, and whose
/// photo capture failed often (AVFoundation -11800).
///
/// Session work and frame reading run on `queue`; callbacks arrive on the
/// main thread.
nonisolated final class PumpCamera: NSObject, @unchecked Sendable {
    struct LiveFrame {
        let reading: PumpReadingParser.Reading?
        /// The frame it was read from, kept in case it's reported as a misread.
        let evidence: ScanEvidence?
    }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "Dipstick.PumpCamera")
    private var device: AVCaptureDevice?
    private var photoContinuation: CheckedContinuation<(CGImage, CGImagePropertyOrientation), Error>?

    // Set from the main thread, read on `queue`.
    private let lock = NSLock()
    private var _layout = Layout()
    private var _expectedPrice: Double?
    private var _isPaused = false

    private var isReadingFrame = false
    private var lastFrameRead = Date.distantPast
    /// Seconds between live frame reads; Vision's accurate mode is slow.
    private static let frameInterval = 0.35

    /// Called on the main thread with each frame read live.
    var onLiveFrame: ((LiveFrame) -> Void)?

    /// Where the scan frame is on screen, to crop frames.
    struct Layout {
        var frame: CGRect = .zero
        var viewSize: CGSize = .zero
    }

    var layout: Layout {
        get { lock.withLock { _layout } }
        set { lock.withLock { _layout = newValue } }
    }

    var expectedPrice: Double? {
        get { lock.withLock { _expectedPrice } }
        set { lock.withLock { _expectedPrice = newValue } }
    }

    /// Stops live reading (e.g. while a still is being read).
    var isPaused: Bool {
        get { lock.withLock { _isPaused } }
        set { lock.withLock { _isPaused = newValue } }
    }

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    // MARK: Session

    /// Asks for camera access if needed, then starts the camera. Returns
    /// false if access is denied or there's no camera.
    func start() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        default: return false
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.configureAndRun())
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        setTorch(false)
    }

    private func configureAndRun() -> Bool {
        if session.isRunning { return true }
        if session.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { return false }
            self.device = device
            session.beginConfiguration()
            // 4:3 frames, the same shape as stills, so one crop fits both.
            session.sessionPreset = .photo
            guard session.canAddInput(input), session.canAddOutput(photoOutput),
                  session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                return false
            }
            session.addInput(input)
            session.addOutput(photoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
            for output in [photoOutput, videoOutput] as [AVCaptureOutput] {
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90  // portrait
                }
            }
            session.commitConfiguration()

            // Pump displays are a hand's length away: focus near and keep refocusing.
            if (try? device.lockForConfiguration()) != nil {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
                device.unlockForConfiguration()
            }
        }
        session.startRunning()
        return session.isRunning
    }

    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    // MARK: Stills

    /// Takes a full-resolution photo; its pixels and orientation.
    func capturePhoto() async throws -> (CGImage, CGImagePropertyOrientation) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning, self.photoContinuation == nil else {
                    continuation.resume(throwing: CaptureError.notReady)
                    return
                }
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    enum CaptureError: LocalizedError {
        case notReady, noImage
        var errorDescription: String? {
            switch self {
            case .notReady: "camera not ready"
            case .noImage: "photo had no image data"
            }
        }
    }
}

extension PumpCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async {
            let continuation = self.photoContinuation
            self.photoContinuation = nil
            if let error {
                continuation?.resume(throwing: error)
                return
            }
            guard let data = photo.fileDataRepresentation(),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                continuation?.resume(throwing: CaptureError.noImage)
                return
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
                .flatMap(CGImagePropertyOrientation.init) ?? .up
            continuation?.resume(returning: (image, orientation))
        }
    }
}

extension PumpCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Live reading: a few times a second, crop the frame to the scan frame
    /// and read its segment display.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isPaused, !isReadingFrame, Date().timeIntervalSince(lastFrameRead) >= Self.frameInterval,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let layout = layout
        guard layout.frame.width > 0, layout.viewSize.width > 0 else { return }
        isReadingFrame = true
        lastFrameRead = Date()
        defer { isReadingFrame = false }

        let image = CIImage(cvPixelBuffer: pixels)
        let crop = PumpPhotoReader.crop(for: layout.frame, in: layout.viewSize,
                                        photoSize: image.extent.size, margin: 0.35)
        guard let cropped = PumpPhotoReader.cropped(image, to: crop) else { return }
        let result = SegmentDisplayReader.readLive(cropped, expectedPrice: expectedPrice)
        // Only frames that read something are kept (a copy: the camera
        // reuses its buffers).
        let evidence = result.reading.flatMap { reading in
            PumpPhotoReader.context.createCGImage(image, from: image.extent).map {
                ScanEvidence(image: $0, orientation: .up, crop: crop, reading: reading)
            }
        }
        let frame = LiveFrame(reading: result.reading, evidence: evidence)
        DispatchQueue.main.async { self.onLiveFrame?(frame) }
    }
}

/// The camera preview, filling its view like the photos are cropped.
struct PumpCameraPreview: UIViewRepresentable {
    let camera: PumpCamera

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90),
           connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }
}
