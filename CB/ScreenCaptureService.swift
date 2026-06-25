import AppKit
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
    @Published private(set) var statusText: String?
    @Published private(set) var lastCapturedItemIdentifier: String?
    @Published var errorMessage: String?
    @Published private(set) var canOpenScreenRecordingSettings = false

    private let clipboardMonitor: ClipboardMonitor
    private let picker = SCContentSharingPicker.shared
    private let regionSelectionController = ScreenRegionSelectionController()
    private var captureTask: Task<Void, Never>?

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
                ? "Screen Recording access was granted. Quit and reopen Clipboard Bro, then try again."
                : "Clipboard Bro needs Screen Recording access. Enable it in System Settings > Privacy & Security > Screen Recording."
            canOpenScreenRecordingSettings = true
            return
        }

        switch mode {
        case .region:
            selectRegion(for: .image)
        case .ocrRegion:
            selectRegion(for: .text)
        case .window, .application, .display:
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
        isCapturing = true
        statusText = "Choose content to capture"
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
                finishCapture(image: image, sourceDescription: "Region Capture")
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

            finishCapture(image: image, sourceDescription: sourceDescription(for: filter))
        } catch {
            failCapture(error)
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

    private func finishCapture(image: CGImage, sourceDescription: String) {
        lastCapturedItemIdentifier = clipboardMonitor.importScreenCapture(
            image,
            sourceDescription: sourceDescription,
            copyToPasteboard: UserDefaults.standard.bool(forKey: ScreenCaptureSettingKey.copiesAfterCapture)
        )
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
        isCapturing = false
        statusText = nil
        picker.isActive = false
    }

    func cancelCapture() {
        captureTask?.cancel()
        captureTask = nil
        regionSelectionController.cancel()
        picker.isActive = false
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
            await self?.capture(filter: filter)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.statusText = nil
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

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "The screen capture completed without producing an image."
        case .noRecognizedText:
            return "No readable text was found in the selected area."
        }
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
