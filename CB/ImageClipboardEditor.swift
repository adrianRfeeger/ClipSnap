import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ImageClipboardEditor: View {
    let image: NSImage
    let saveAction: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection = CGRect.zero
    @State private var normalizedSelection = CGRect.zero
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let imageRect = fittedImageRect(in: geometry.size)

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.08)

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .offset(x: imageRect.minX, y: imageRect.minY)

                    if !selection.isEmpty {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                            .frame(width: selection.width, height: selection.height)
                            .offset(x: selection.minX, y: selection.minY)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(selectionGesture(in: imageRect))
            }

            HStack {
                Text(selection.isEmpty ? "Drag over the image to select an area." : "Selected area is ready to edit.")
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Redact") {
                    apply(.redact)
                }
                .disabled(!hasUsableSelection)

                Button("Outline") {
                    apply(.outline)
                }
                .disabled(!hasUsableSelection)

                Button("Crop") {
                    apply(.crop)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUsableSelection)
            }
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 480)
    }

    private var hasUsableSelection: Bool {
        selection.width >= 4 && selection.height >= 4
    }

    private func fittedImageRect(in size: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else {
            return .zero
        }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func selectionGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = clamped(value.location, to: imageRect)
                let start = dragStart ?? point
                dragStart = start
                selection = CGRect(
                    x: min(start.x, point.x),
                    y: min(start.y, point.y),
                    width: abs(point.x - start.x),
                    height: abs(point.y - start.y)
                )
                normalizedSelection = CGRect(
                    x: (selection.minX - imageRect.minX) / imageRect.width,
                    y: (selection.minY - imageRect.minY) / imageRect.height,
                    width: selection.width / imageRect.width,
                    height: selection.height / imageRect.height
                )
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func apply(_ operation: ClipboardImageEditing.Operation) {
        guard let sourceData = ClipboardImageEditing.pngData(from: image),
              let editedData = ClipboardImageEditing.edit(
                sourceData,
                normalizedSelection: normalizedSelection,
                operation: operation
              ) else {
            return
        }
        saveAction(editedData)
        dismiss()
    }
}

enum ClipboardImageEditing {
    enum Operation {
        case crop
        case redact
        case outline
    }

    static func edit(
        _ data: Data,
        normalizedSelection: CGRect,
        operation: Operation
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let selection = normalizedSelection.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        guard selection.width > 0, selection.height > 0 else {
            return nil
        }

        let pixelRect = CGRect(
            x: selection.minX * CGFloat(image.width),
            y: (1 - selection.maxY) * CGFloat(image.height),
            width: selection.width * CGFloat(image.width),
            height: selection.height * CGFloat(image.height)
        ).integral

        let result: CGImage?
        switch operation {
        case .crop:
            result = image.cropping(to: pixelRect)
        case .redact:
            result = redacted(image, pixelRect: pixelRect)
        case .outline:
            result = outlined(image, pixelRect: pixelRect)
        }
        return result.flatMap(encodedPNGData)
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func thumbnailData(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size))
        thumbnail.unlockFocus()
        return pngData(from: thumbnail)
    }

    private static func redacted(_ image: CGImage, pixelRect: CGRect) -> CGImage? {
        editedImage(image) { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(pixelRect)
        }
    }

    private static func outlined(_ image: CGImage, pixelRect: CGRect) -> CGImage? {
        editedImage(image) { context in
            let lineWidth = max(3, CGFloat(image.width) / 300)
            context.setStrokeColor(CGColor(red: 1, green: 0.15, blue: 0.1, alpha: 1))
            context.setLineWidth(lineWidth)
            context.stroke(pixelRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        }
    }

    private static func editedImage(
        _ image: CGImage,
        edit: (CGContext) -> Void
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        edit(context)
        return context.makeImage()
    }

    nonisolated private static func encodedPNGData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
