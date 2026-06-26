import AppKit
import AVFoundation
import Combine
import CoreGraphics
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

enum ScreenCaptureMode {
    case region
    case ocrRegion
    case window
    case application
    case display
    case recording
}

enum ScreenCaptureSettingKey {
    static let showsCursor = "screenCaptureShowsCursor"
    static let includesWindowShadow = "screenCaptureIncludesWindowShadow"
    static let includesChildWindows = "screenCaptureIncludesChildWindows"
    static let copiesAfterCapture = "screenCaptureCopiesAfterCapture"
    static let copiesOCRText = "screenCaptureCopiesOCRText"
}

@MainActor
final class ScreenCaptureService: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var isRecording = false
    @Published private(set) var isRecordingPaused = false
    @Published private(set) var statusText: String?
    @Published private(set) var lastCapturedItemIdentifier: String?
    @Published var errorMessage: String?
    @Published private(set) var canOpenScreenRecordingSettings = false

    private let clipboardMonitor: ClipboardMonitor
    private let picker = SCContentSharingPicker.shared
    private let regionSelectionController = ScreenRegionSelectionController()
    private var captureTask: Task<Void, Never>?
    private var pickerPurpose: PickerPurpose?
    private var recordingSession: ScreenRecordingSession?

    var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    init(clipboardMonitor: ClipboardMonitor) {
        self.clipboardMonitor = clipboardMonitor
        super.init()
        picker.add(self)
    }

    deinit {
        picker.remove(self)
    }

    func capture(_ mode: ScreenCaptureMode) {
        guard !isCapturing else {
            return
        }

        errorMessage = nil
        canOpenScreenRecordingSettings = false
        guard CGPreflightScreenCaptureAccess() else {
            let granted = CGRequestScreenCaptureAccess()
            errorMessage = granted
                ? "Screen Recording access was granted. Quit and reopen ClipSnap, then try again."
                : "ClipSnap needs Screen Recording access. Enable it in System Settings > Privacy & Security > Screen Recording."
            canOpenScreenRecordingSettings = true
            return
        }

        switch mode {
        case .region:
            selectRegion(for: .image)
        case .ocrRegion:
            selectRegion(for: .text)
        case .window, .application, .display, .recording:
            presentPicker(for: mode)
        }
    }

    private func presentPicker(for mode: ScreenCaptureMode) {
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = pickerMode(for: mode)
        configuration.allowsChangingSelectedContent = false
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleIdentifier]
        }

        picker.configuration = configuration
        picker.isActive = true
        pickerPurpose = mode == .recording ? .recording : .capture
        isCapturing = true
        statusText = mode == .recording ? "Choose a display to record" : "Choose content to capture"
        picker.present()
    }

    private func pickerMode(for mode: ScreenCaptureMode) -> SCContentSharingPickerMode {
        switch mode {
        case .window:
            return .singleWindow
        case .application:
            return .singleApplication
        case .display:
            return .singleDisplay
        case .recording:
            return .singleDisplay
        case .region, .ocrRegion:
            return []
        }
    }

    private func selectRegion(for purpose: RegionCapturePurpose) {
        isCapturing = true
        statusText = purpose == .text ? "Select an area to recognize text" : "Select an area to capture"
        regionSelectionController.selectRegion(
            instruction: purpose == .text
                ? "Drag around text to recognize • Esc cancels"
                : "Drag to capture a region • Esc cancels"
        ) { [weak self] rect in
            guard let self else {
                return
            }

            guard let rect else {
                self.isCapturing = false
                self.statusText = nil
                return
            }

            self.captureTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else {
                    return
                }
                await self.captureRegion(rect, for: purpose)
            }
        }
    }

    private func captureRegion(_ rect: CGRect, for purpose: RegionCapturePurpose) async {
        do {
            let image = try await SCScreenshotManager.captureImage(in: rect)
            switch purpose {
            case .image:
                await finishCapture(image: image, sourceDescription: "Region Capture")
            case .text:
                statusText = "Recognizing text…"
                let sourceIdentifier = clipboardMonitor.importScreenCapture(
                    image,
                    sourceDescription: "OCR Region Capture",
                    copyToPasteboard: false
                )
                try await finishOCRCapture(image: image, sourceItemIdentifier: sourceIdentifier)
            }
        } catch {
            failCapture(error)
        }
    }

    private func finishOCRCapture(
        image: CGImage,
        sourceItemIdentifier: String? = nil
    ) async throws {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: image)
        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ScreenCaptureError.noRecognizedText
        }

        let defaults = UserDefaults.standard
        let shouldCopy = defaults.object(forKey: ScreenCaptureSettingKey.copiesOCRText) == nil
            ? true
            : defaults.bool(forKey: ScreenCaptureSettingKey.copiesOCRText)
        lastCapturedItemIdentifier = clipboardMonitor.importRecognizedText(
            text,
            sourceItemIdentifier: sourceItemIdentifier,
            copyToPasteboard: shouldCopy
        )
        isCapturing = false
        statusText = nil
    }

    private func capture(filter: SCContentFilter) async {
        do {
            let defaults = UserDefaults.standard
            let configuration = SCScreenshotConfiguration()
            configuration.showsCursor = defaults.bool(forKey: ScreenCaptureSettingKey.showsCursor)
            configuration.ignoreShadows = defaults.object(forKey: ScreenCaptureSettingKey.includesWindowShadow) == nil
                ? false
                : !defaults.bool(forKey: ScreenCaptureSettingKey.includesWindowShadow)
            configuration.includeChildWindows = defaults.object(forKey: ScreenCaptureSettingKey.includesChildWindows) == nil
                ? true
                : defaults.bool(forKey: ScreenCaptureSettingKey.includesChildWindows)

            let output = try await SCScreenshotManager.captureScreenshot(
                contentFilter: filter,
                configuration: configuration
            )
            guard let image = output.sdrImage else {
                throw ScreenCaptureError.missingImage
            }

            await finishCapture(image: image, sourceDescription: sourceDescription(for: filter))
        } catch {
            failCapture(error)
        }
    }

    private func startRecording(filter: SCContentFilter) async {
        do {
            let streamConfiguration = recordingStreamConfiguration(for: filter)
            let session = ScreenRecordingSession(
                filter: filter,
                streamConfiguration: streamConfiguration,
                sourceDescription: recordingSourceDescription(for: filter)
            )
            session.activeSegment = try await startRecordingSegment(for: session)
            recordingSession = session
            isRecording = true
            isRecordingPaused = false
            isCapturing = true
            statusText = "Recording desktop"
            picker.isActive = false
        } catch {
            failCapture(error)
        }
    }

    func pauseRecording() {
        guard let session = recordingSession,
              session.activeSegment != nil,
              !isRecordingPaused else {
            return
        }

        captureTask = Task { [weak self] in
            await self?.pauseCurrentRecordingSegment()
        }
    }

    func resumeRecording() {
        guard let session = recordingSession,
              session.activeSegment == nil,
              isRecordingPaused else {
            return
        }

        captureTask = Task { [weak self] in
            await self?.resumeRecording(session: session)
        }
    }

    func stopRecording() {
        guard recordingSession != nil else {
            return
        }

        captureTask = Task { [weak self] in
            await self?.finishRecording()
        }
    }

    private func startRecordingSegment(for session: ScreenRecordingSession) async throws -> ScreenRecordingSegment {
        let outputURL = recordingOutputURL()
        let stream = SCStream(
            filter: session.filter,
            configuration: session.streamConfiguration,
            delegate: nil
        )
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let delegate = ScreenRecordingOutputDelegate()
        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: delegate
        )
        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()
        return ScreenRecordingSegment(
            stream: stream,
            recordingOutput: recordingOutput,
            delegate: delegate,
            outputURL: outputURL
        )
    }

    private func stopActiveRecordingSegment(for session: ScreenRecordingSession) async throws {
        guard let segment = session.activeSegment else {
            return
        }

        session.activeSegment = nil
        try await segment.stream.stopCapture()
        try? segment.stream.removeRecordingOutput(segment.recordingOutput)
        if let error = segment.delegate.error {
            throw error
        }

        guard fileExistsAndIsNotEmpty(at: segment.outputURL) else {
            throw ScreenCaptureError.emptyRecording
        }
        session.segmentURLs.append(segment.outputURL)
    }

    private func pauseCurrentRecordingSegment() async {
        guard let session = recordingSession else {
            return
        }

        statusText = "Pausing recording…"
        do {
            try await stopActiveRecordingSegment(for: session)
            isRecording = false
            isRecordingPaused = true
            statusText = "Recording paused"
        } catch {
            cleanUpRecordingFiles(for: session)
            failCapture(error)
        }
    }

    private func resumeRecording(session: ScreenRecordingSession) async {
        statusText = "Resuming recording…"
        do {
            session.activeSegment = try await startRecordingSegment(for: session)
            isRecording = true
            isRecordingPaused = false
            statusText = "Recording desktop"
        } catch {
            cleanUpRecordingFiles(for: session)
            failCapture(error)
        }
    }

    private func finishRecording() async {
        guard let session = recordingSession else {
            isCapturing = false
            statusText = nil
            return
        }

        recordingSession = nil
        isRecording = false
        isRecordingPaused = false
        statusText = "Saving recording…"

        do {
            try await stopActiveRecordingSegment(for: session)

            let outputURL = try await finalizedRecordingURL(for: session)
            let data = try Data(contentsOf: outputURL)
            guard !data.isEmpty else {
                throw ScreenCaptureError.emptyRecording
            }

            lastCapturedItemIdentifier = clipboardMonitor.importScreenRecording(
                data,
                sourceDescription: session.sourceDescription
            )
            cleanUpRecordingFiles(for: session, keeping: outputURL)
            try? FileManager.default.removeItem(at: outputURL)
            isCapturing = false
            statusText = nil
        } catch {
            cleanUpRecordingFiles(for: session)
            failCapture(error)
        }
    }

    private func recordingStreamConfiguration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        configuration.showsCursor = UserDefaults.standard.bool(forKey: ScreenCaptureSettingKey.showsCursor)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.width = max(1, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        configuration.height = max(1, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        return configuration
    }

    private func recordingOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipSnap Recording \(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func finalizedRecordingURL(for session: ScreenRecordingSession) async throws -> URL {
        guard !session.segmentURLs.isEmpty else {
            throw ScreenCaptureError.emptyRecording
        }

        guard session.segmentURLs.count > 1 else {
            return session.segmentURLs[0]
        }

        let outputURL = recordingOutputURL()
        try await mergeRecordingSegments(session.segmentURLs, to: outputURL)
        return outputURL
    }

    private func mergeRecordingSegments(_ segmentURLs: [URL], to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenCaptureError.emptyRecording
        }

        var cursor = CMTime.zero
        for segmentURL in segmentURLs {
            let asset = AVURLAsset(url: segmentURL)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            let duration = try await asset.load(.duration)
            guard duration > .zero else {
                continue
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: assetTrack,
                at: cursor
            )
            cursor = cursor + duration
        }

        guard cursor > .zero,
              let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
              ) else {
            throw ScreenCaptureError.emptyRecording
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        try await exportSession.export(to: outputURL, as: .mp4)
    }

    private func fileExistsAndIsNotEmpty(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return false
        }
        return fileSize.intValue > 0
    }

    private func cleanUpRecordingFiles(for session: ScreenRecordingSession, keeping preservedURL: URL? = nil) {
        let urls = session.segmentURLs + [session.activeSegment?.outputURL].compactMap { $0 }
        for url in urls where url != preservedURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func sourceDescription(for filter: SCContentFilter) -> String {
        switch filter.style {
        case .display:
            return "Display Capture"
        case .window:
            return "Window Capture"
        case .application:
            return "Application Capture"
        default:
            return "Screen Capture"
        }
    }

    private func recordingSourceDescription(for filter: SCContentFilter) -> String {
        switch filter.style {
        case .display:
            return "Display Recording"
        case .window:
            return "Window Recording"
        case .application:
            return "Application Recording"
        default:
            return "Screen Recording"
        }
    }

    private func finishCapture(image: CGImage, sourceDescription: String) async {
        let capturedIdentifier = clipboardMonitor.importScreenCapture(
            image,
            sourceDescription: sourceDescription,
            copyToPasteboard: UserDefaults.standard.bool(forKey: ScreenCaptureSettingKey.copiesAfterCapture)
        )
        lastCapturedItemIdentifier = capturedIdentifier

        let actions = ScreenCapturePostActions.load()
        if let capturedIdentifier {
            clipboardMonitor.applyPostCaptureActions(
                to: capturedIdentifier,
                actions: actions
            )
        }

        if actions.automaticallyRecognizesText, let capturedIdentifier {
            statusText = "Recognizing captured text…"
            do {
                try await finishOCRCapture(
                    image: image,
                    sourceItemIdentifier: capturedIdentifier
                )
                lastCapturedItemIdentifier = capturedIdentifier
            } catch ScreenCaptureError.noRecognizedText {
                lastCapturedItemIdentifier = capturedIdentifier
                isCapturing = false
                statusText = nil
            } catch {
                failCapture(error)
                return
            }
        }
        isCapturing = false
        statusText = nil
        picker.isActive = false
    }

    private func failCapture(_ error: Error) {
        guard !(error is CancellationError) else {
            isCapturing = false
            statusText = nil
            return
        }
        errorMessage = error.localizedDescription
        isRecording = false
        isRecordingPaused = false
        recordingSession = nil
        isCapturing = false
        statusText = nil
        picker.isActive = false
    }

    func cancelCapture() {
        if recordingSession != nil {
            stopRecording()
            return
        }

        captureTask?.cancel()
        captureTask = nil
        regionSelectionController.cancel()
        picker.isActive = false
        pickerPurpose = nil
        isRecording = false
        isRecordingPaused = false
        isCapturing = false
        statusText = nil
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func recognizeText(in item: ClipboardItem) {
        guard !isCapturing,
              let imageData = item.imageData,
              let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        isCapturing = true
        statusText = "Recognizing text…"
        captureTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.finishOCRCapture(
                    image: cgImage,
                    sourceItemIdentifier: item.id?.uuidString
                )
            } catch {
                self.failCapture(error)
            }
        }
    }
}

extension ScreenCaptureService: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            switch self?.pickerPurpose {
            case .recording:
                self?.pickerPurpose = nil
                await self?.startRecording(filter: filter)
            case .capture, .none:
                self?.pickerPurpose = nil
                await self?.capture(filter: filter)
            }
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.isRecording = false
            self?.isRecordingPaused = false
            self?.statusText = nil
            self?.pickerPurpose = nil
            picker.isActive = false
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.failCapture(error)
        }
    }
}

private enum ScreenCaptureError: LocalizedError {
    case missingImage
    case noRecognizedText
    case emptyRecording
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "The screen capture completed without producing an image."
        case .noRecognizedText:
            return "No readable text was found in the selected area."
        case .emptyRecording:
            return "The screen recording completed without producing a video."
        case .exportFailed:
            return "The screen recording could not be saved."
        }
    }
}

private enum PickerPurpose {
    case capture
    case recording
}

private final class ScreenRecordingSession {
    let filter: SCContentFilter
    let streamConfiguration: SCStreamConfiguration
    let sourceDescription: String
    var activeSegment: ScreenRecordingSegment?
    var segmentURLs: [URL] = []

    init(
        filter: SCContentFilter,
        streamConfiguration: SCStreamConfiguration,
        sourceDescription: String
    ) {
        self.filter = filter
        self.streamConfiguration = streamConfiguration
        self.sourceDescription = sourceDescription
    }
}

private final class ScreenRecordingSegment {
    let stream: SCStream
    let recordingOutput: SCRecordingOutput
    let delegate: ScreenRecordingOutputDelegate
    let outputURL: URL

    init(
        stream: SCStream,
        recordingOutput: SCRecordingOutput,
        delegate: ScreenRecordingOutputDelegate,
        outputURL: URL
    ) {
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.delegate = delegate
        self.outputURL = outputURL
    }
}

private final class ScreenRecordingOutputDelegate: NSObject, SCRecordingOutputDelegate {
    private(set) var error: Error?

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        self.error = error
    }
}

private enum RegionCapturePurpose: Equatable {
    case image
    case text
}

@MainActor
private final class ScreenRegionSelectionController {
    private var windows: [ScreenRegionSelectionWindow] = []

    func selectRegion(instruction: String, completion: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else {
            return
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(nil)
            return
        }

        windows = screens.map { screen in
            let window = ScreenRegionSelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            let selectionView = ScreenRegionSelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size)
            )
            selectionView.instruction = instruction
            selectionView.onCompletion = { [weak self] localRect in
                guard let self else {
                    return
                }

                let screenRect = localRect.map {
                    CGRect(
                        x: screen.frame.minX + $0.minX,
                        y: screen.frame.minY + $0.minY,
                        width: $0.width,
                        height: $0.height
                    )
                }
                self.closeWindows()
                completion(screenRect)
            }

            window.contentView = selectionView
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.orderFrontRegardless()
            return window
        }
        windows.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() {
        closeWindows()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private final class ScreenRegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}

private final class ScreenRegionSelectionView: NSView {
    var onCompletion: ((CGRect?) -> Void)?
    var instruction = "Drag to select • Esc cancels"

    private var startPoint: CGPoint?
    private var selectionRect = CGRect.zero

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else {
            return
        }

        selectionRect = CGRect(from: startPoint, to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard selectionRect.width >= 2, selectionRect.height >= 2 else {
            onCompletion?(nil)
            return
        }

        onCompletion?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCompletion?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dimmingPath = NSBezierPath(rect: bounds)
        if !selectionRect.isEmpty {
            dimmingPath.appendRect(selectionRect)
        }
        dimmingPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dimmingPath.fill()

        drawInstruction()

        guard !selectionRect.isEmpty else {
            return
        }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 2
        border.stroke()
        drawDimensions()
    }

    private func drawInstruction() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = instruction as NSString
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 12,
            y: bounds.maxY - size.height - 36,
            width: size.width + 24,
            height: size.height + 12
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(
            at: CGPoint(x: rect.minX + 12, y: rect.minY + 6),
            withAttributes: attributes
        )
    }

    private func drawDimensions() {
        let label = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attributes)
        let origin = CGPoint(
            x: min(selectionRect.maxX - size.width, bounds.maxX - size.width - 12),
            y: max(selectionRect.minY - size.height - 12, 12)
        )
        label.draw(at: origin, withAttributes: attributes)
    }
}

private extension CGRect {
    init(from first: CGPoint, to second: CGPoint) {
        self.init(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }
}
