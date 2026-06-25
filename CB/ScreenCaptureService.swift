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
    @Published private(set) var lastCapturedItemIdentifier: String?
    @Published var errorMessage: String?

    private let clipboardMonitor: ClipboardMonitor
    private let picker = SCContentSharingPicker.shared
    private let regionSelectionController = ScreenRegionSelectionController()

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
        guard CGPreflightScreenCaptureAccess() else {
            let granted = CGRequestScreenCaptureAccess()
            errorMessage = granted
                ? "Screen Recording access was granted. Quit and reopen Clipboard Bro, then try again."
                : "Clipboard Bro needs Screen Recording access. Enable it in System Settings > Privacy & Security > Screen Recording."
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
        regionSelectionController.selectRegion { [weak self] rect in
            guard let self else {
                return
            }

            guard let rect else {
                self.isCapturing = false
                return
            }

            Task {
                try? await Task.sleep(for: .milliseconds(150))
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
                try await finishOCRCapture(image: image)
            }
        } catch {
            failCapture(error)
        }
    }

    private func finishOCRCapture(image: CGImage) async throws {
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
            copyToPasteboard: shouldCopy
        )
        isCapturing = false
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
        picker.isActive = false
    }

    private func failCapture(_ error: Error) {
        errorMessage = error.localizedDescription
        isCapturing = false
        picker.isActive = false
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

private enum RegionCapturePurpose {
    case image
    case text
}

@MainActor
private final class ScreenRegionSelectionController {
    private var window: ScreenRegionSelectionWindow?

    func selectRegion(completion: @escaping (CGRect?) -> Void) {
        guard window == nil else {
            return
        }

        let desktopFrame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard !desktopFrame.isNull else {
            completion(nil)
            return
        }

        let window = ScreenRegionSelectionWindow(
            contentRect: desktopFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let selectionView = ScreenRegionSelectionView(frame: CGRect(origin: .zero, size: desktopFrame.size))
        selectionView.onCompletion = { [weak self] localRect in
            guard let self else {
                return
            }

            let screenRect = localRect.map {
                CGRect(
                    x: desktopFrame.minX + $0.minX,
                    y: desktopFrame.minY + $0.minY,
                    width: $0.width,
                    height: $0.height
                )
            }
            window.orderOut(nil)
            self.window = nil
            completion(screenRect)
        }

        window.contentView = selectionView
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private final class ScreenRegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}

private final class ScreenRegionSelectionView: NSView {
    var onCompletion: ((CGRect?) -> Void)?

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

        guard !selectionRect.isEmpty else {
            return
        }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 2
        border.stroke()
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
