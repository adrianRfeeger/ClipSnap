import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ImageClipboardEditor: View {
    let saveAction: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workingImageData: Data
    @State private var selection = CGRect.zero
    @State private var normalizedSelection = CGRect.zero
    @State private var dragStart: CGPoint?
    @State private var selectionStart = CGPoint.zero
    @State private var selectionEnd = CGPoint.zero
    @State private var normalizedSelectionStart = CGPoint.zero
    @State private var normalizedSelectionEnd = CGPoint.zero
    @State private var freehandPoints: [CGPoint] = []
    @State private var normalizedFreehandPoints: [CGPoint] = []
    @State private var displayToPixelScale: CGFloat = 1
    @State private var selectedTool = ClipboardImageEditing.Tool.rectangle
    @State private var annotationColor = Color.red
    @State private var fillColor = Color.clear
    @State private var fillsShape = false
    @State private var lineWidth: Double = 5
    @State private var textSize: Double = 24
    @State private var annotationText = ""
    @State private var annotations: [ImageAnnotation] = []
    @State private var selectedAnnotationID: UUID?
    @State private var annotationDragSnapshot: ImageAnnotation?
    @State private var activeAnnotationHandle: AnnotationHandle?
    @FocusState private var annotationTextIsFocused: Bool

    init(image: NSImage, saveAction: @escaping (Data) -> Void) {
        self.saveAction = saveAction
        _workingImageData = State(
            initialValue: ClipboardImageEditing.pngData(from: image) ?? Data()
        )
    }

    private var image: NSImage {
        NSImage(data: workingImageData) ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 14) {
            toolControls

            GeometryReader { geometry in
                let imageRect = fittedImageRect(in: geometry.size)

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.08)

                    if imageRect.isRenderable {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .offset(x: imageRect.minX, y: imageRect.minY)
                    }

                    ForEach(annotations) { annotation in
                        annotationView(annotation, in: imageRect)
                    }

                    if !selection.isEmpty {
                        annotationPreview
                    }

                    if selectedTool == .freehand, freehandPoints.count > 1 {
                        FreehandShape(points: freehandPoints)
                            .stroke(annotationColor, style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(selectionGesture(in: imageRect))
            }
            .onChange(of: selectedTool) {
                if selectedTool == .text {
                    annotationTextIsFocused = true
                }
                clearSelection()
            }
            .onChange(of: selectedAnnotationID) {
                loadSelectedAnnotationControls()
            }
            .onChange(of: annotationColor) {
                updateSelectedAnnotation()
            }
            .onChange(of: fillColor) {
                updateSelectedAnnotation()
            }
            .onChange(of: fillsShape) {
                updateSelectedAnnotation()
            }
            .onChange(of: lineWidth) {
                updateSelectedAnnotation()
            }
            .onChange(of: textSize) {
                updateSelectedAnnotation()
            }
            .onChange(of: annotationText) {
                updateSelectedAnnotation()
            }

            HStack {
                Text(statusText)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Delete Annotation") {
                    deleteSelectedAnnotation()
                }
                .disabled(selectedAnnotationID == nil)

                if !selectedTool.appliesLive {
                    Button(primaryActionTitle) {
                        applySelectedTool()
                    }
                    .disabled(!canApplySelectedTool)
                }

                Button("Done") {
                    saveAction(rasterizedImageData() ?? workingImageData)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(workingImageData.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 540)
    }

    @ViewBuilder
    private var annotationPreview: some View {
        switch selectedTool {
        case .crop, .redact:
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                .frame(width: selection.width, height: selection.height)
                .offset(x: selection.minX, y: selection.minY)
        case .rectangle:
            Rectangle()
                .fill(fillsShape ? fillColor : Color.clear)
                .stroke(annotationColor, lineWidth: CGFloat(lineWidth))
                .frame(width: selection.width, height: selection.height)
                .offset(x: selection.minX, y: selection.minY)
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: min(14, min(selection.width, selection.height) / 4))
                .fill(fillsShape ? fillColor : Color.clear)
                .stroke(annotationColor, lineWidth: CGFloat(lineWidth))
                .frame(width: selection.width, height: selection.height)
                .offset(x: selection.minX, y: selection.minY)
        case .oval:
            Ellipse()
                .fill(fillsShape ? fillColor : Color.clear)
                .stroke(annotationColor, lineWidth: CGFloat(lineWidth))
                .frame(width: selection.width, height: selection.height)
                .offset(x: selection.minX, y: selection.minY)
        case .line:
            LineShape(start: selectionStart, end: selectionEnd)
                .stroke(annotationColor, style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round))
        case .arrow:
            ArrowShape(start: selectionStart, end: selectionEnd)
                .stroke(annotationColor, style: StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round, lineJoin: .round))
        case .highlight:
            Rectangle()
                .fill(annotationColor.opacity(0.35))
                .frame(width: selection.width, height: selection.height)
                .offset(x: selection.minX, y: selection.minY)
        case .freehand:
            EmptyView()
        case .text:
            Text(annotationText.isEmpty ? "Text" : annotationText)
                .font(.system(size: textSize, weight: .semibold))
                .foregroundStyle(annotationColor)
                .frame(width: selection.width, height: selection.height, alignment: .topLeading)
                .offset(x: selection.minX, y: selection.minY)
        }
    }

    private struct LineShape: Shape {
        let start: CGPoint
        let end: CGPoint

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            return path
        }
    }

    private struct ArrowShape: Shape {
        let start: CGPoint
        let end: CGPoint

        func path(in rect: CGRect) -> Path {
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = max(14, hypot(end.x - start.x, end.y - start.y) * 0.18)
            let spread = CGFloat.pi / 7
            let first = CGPoint(
                x: end.x - length * cos(angle - spread),
                y: end.y - length * sin(angle - spread)
            )
            let second = CGPoint(
                x: end.x - length * cos(angle + spread),
                y: end.y - length * sin(angle + spread)
            )
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            path.move(to: end)
            path.addLine(to: first)
            path.move(to: end)
            path.addLine(to: second)
            return path
        }
    }

    private struct FreehandShape: Shape {
        let points: [CGPoint]

        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard let first = points.first else {
                return path
            }

            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            return path
        }
    }

    @ViewBuilder
    private func annotationView(_ annotation: ImageAnnotation, in imageRect: CGRect) -> some View {
        let displayScale = pixelScale(for: imageRect)
        let displayRect = annotation.displayRect(in: imageRect)
        let strokeWidth = max(1, annotation.lineWidth / displayScale)
        let strokeColor = Color(nsColor: annotation.color)
        let fillColor = annotation.fillColor.map(Color.init(nsColor:)) ?? Color.clear

        ZStack(alignment: .topLeading) {
            switch annotation.tool {
            case .rectangle:
                Rectangle()
                    .fill(fillColor)
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .offset(x: displayRect.minX, y: displayRect.minY)
            case .roundedRectangle:
                RoundedRectangle(cornerRadius: min(14, min(displayRect.width, displayRect.height) / 4))
                    .fill(fillColor)
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .offset(x: displayRect.minX, y: displayRect.minY)
            case .oval:
                Ellipse()
                    .fill(fillColor)
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .offset(x: displayRect.minX, y: displayRect.minY)
            case .line:
                LineShape(
                    start: annotation.start.displayPoint(in: imageRect),
                    end: annotation.end.displayPoint(in: imageRect)
                )
                .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
            case .arrow:
                ArrowShape(
                    start: annotation.start.displayPoint(in: imageRect),
                    end: annotation.end.displayPoint(in: imageRect)
                )
                .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
            case .highlight:
                Rectangle()
                    .fill(strokeColor.opacity(0.35))
                    .frame(width: displayRect.width, height: displayRect.height)
                    .offset(x: displayRect.minX, y: displayRect.minY)
            case .freehand:
                FreehandShape(points: annotation.points.map { $0.displayPoint(in: imageRect) })
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
            case .text:
                Text(annotation.text.isEmpty ? "Text" : annotation.text)
                    .font(.system(size: max(10, annotation.textSize / displayScale), weight: .semibold))
                    .foregroundStyle(strokeColor)
                    .frame(width: displayRect.width, height: displayRect.height, alignment: .topLeading)
                    .offset(x: displayRect.minX, y: displayRect.minY)
            case .crop, .redact:
                EmptyView()
            }

            if selectedAnnotationID == annotation.id {
                Rectangle()
                    .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .frame(width: displayRect.width, height: displayRect.height)
                    .offset(x: displayRect.minX, y: displayRect.minY)

                ForEach(annotation.handles(in: imageRect)) { handle in
                    Circle()
                        .fill(.background)
                        .stroke(.tint, lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                        .position(handle.position)
                }
            }
        }
    }

    private var hasUsableSelection: Bool {
        selection.width >= 4 && selection.height >= 4
    }

    private var canApplySelectedTool: Bool {
        guard hasUsableSelection || selectedTool == .text || selectedTool == .freehand else {
            return false
        }

        if selectedTool == .freehand {
            return normalizedFreehandPoints.count > 1
        }

        if selectedTool == .text {
            return hasUsableSelection
                && !annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    private var statusText: String {
        if selectedTool == .text {
            return annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Type annotation text, then click or drag on the image to place it."
                : "Click or drag on the image to place the text."
        }

        if selectedTool == .freehand {
            return "Drag on the image to sketch."
        }

        if selectedTool.appliesLive {
            return selection.isEmpty ? "Drag on the image to draw." : "Release to apply the annotation."
        }

        return selection.isEmpty ? "Drag over the image to select an area." : "Selected area is ready to edit."
    }

    private var primaryActionTitle: String {
        switch selectedTool {
        case .crop:
            return "Crop"
        case .redact:
            return "Redact"
        default:
            return "Apply"
        }
    }

    private var toolControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                toolButton(.crop)
                toolButton(.redact)
                Divider().frame(height: 24)
                toolButton(.freehand)
                toolButton(.line)
                toolButton(.arrow)

                Menu {
                    toolMenuButton(.rectangle)
                    toolMenuButton(.roundedRectangle)
                    toolMenuButton(.oval)
                } label: {
                    Label("Shapes", systemImage: "square.on.circle")
                        .labelStyle(.iconOnly)
                }
                .help("Shapes")

                toolButton(.highlight)
                toolButton(.text)

                Divider().frame(height: 24)
                transformButton("Rotate Left", systemImage: "rotate.left") {
                    apply(.rotateLeft)
                }
                transformButton("Rotate Right", systemImage: "rotate.right") {
                    apply(.rotateRight)
                }
                transformButton("Flip Horizontal", systemImage: "flip.horizontal") {
                    apply(.flipHorizontal)
                }
                transformButton("Flip Vertical", systemImage: "arrow.up.and.down") {
                    apply(.flipVertical)
                }

                Spacer()

                Menu {
                    ForEach([1.0, 3.0, 5.0, 8.0, 12.0, 18.0], id: \.self) { width in
                        Button("\(Int(width)) px") {
                            lineWidth = width
                        }
                    }
                } label: {
                    Label("Stroke Width", systemImage: "line.3.horizontal")
                        .labelStyle(.iconOnly)
                }
                .disabled(!selectedTool.usesLineWidth)
                .help("Stroke Width")

                ColorPicker("Stroke Color", selection: $annotationColor, supportsOpacity: true)
                    .labelsHidden()
                    .disabled(!selectedTool.usesColor)

                Toggle(isOn: $fillsShape) {
                    Label("Fill", systemImage: "drop.fill")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .disabled(!selectedTool.usesFill)
                .help("Fill Shape")

                ColorPicker("Fill Color", selection: $fillColor, supportsOpacity: true)
                    .labelsHidden()
                    .disabled(!selectedTool.usesFill || !fillsShape)

                Menu {
                    Button("Duplicate") {
                        duplicateSelectedAnnotation()
                    }
                    Button("Bring Forward") {
                        moveSelectedAnnotationForward()
                    }
                    Button("Send Backward") {
                        moveSelectedAnnotationBackward()
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        deleteSelectedAnnotation()
                    }
                } label: {
                    Label("Object", systemImage: "square.3.layers.3d")
                        .labelStyle(.iconOnly)
                }
                .disabled(selectedAnnotationID == nil)
                .help("Object Actions")
            }

            HStack(spacing: 12) {
                Slider(value: $lineWidth, in: 1...32, step: 1) {
                    Text("Stroke")
                }
                .disabled(!selectedTool.usesLineWidth)

                Text("\(Int(lineWidth)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)

                Stepper("Text \(Int(textSize)) pt", value: $textSize, in: 10...96, step: 1)
                    .disabled(selectedTool != .text)

                TextField("Annotation text", text: $annotationText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedTool != .text)
                    .focused($annotationTextIsFocused)
                    .onSubmit {
                        selectedTool = .text
                    }
            }
        }
    }

    private func toolButton(_ tool: ClipboardImageEditing.Tool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            Label(tool.title, systemImage: tool.systemImageName)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(tool.title)
        .tint(selectedTool == tool ? .accentColor : nil)
    }

    private func toolMenuButton(_ tool: ClipboardImageEditing.Tool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            Label(tool.title, systemImage: tool.systemImageName)
        }
    }

    private func transformButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(title)
        .disabled(workingImageData.isEmpty)
    }

    private func fittedImageRect(in size: CGSize) -> CGRect {
        guard size.isRenderable,
              image.size.isRenderable else {
            return .zero
        }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        guard scale.isFinite, scale > 0 else {
            return .zero
        }
        let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        guard fittedSize.isRenderable else {
            return .zero
        }
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
                guard imageRect.isRenderable else {
                    selection = .zero
                    normalizedSelection = .zero
                    return
                }
                let point = clamped(value.location, to: imageRect)
                if beginOrContinueAnnotationManipulation(at: point, translation: value.translation, in: imageRect) {
                    return
                }

                let start = dragStart ?? point
                if dragStart == nil {
                    freehandPoints = selectedTool == .freehand ? [start] : []
                    normalizedFreehandPoints = selectedTool == .freehand
                        ? [normalized(point: start, in: imageRect)]
                        : []
                }
                dragStart = start
                displayToPixelScale = pixelScale(for: imageRect)
                selectionStart = start
                selectionEnd = point
                if selectedTool == .freehand {
                    freehandPoints.append(point)
                    normalizedFreehandPoints.append(normalized(point: point, in: imageRect))
                }
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
                normalizedSelectionStart = normalized(point: start, in: imageRect)
                normalizedSelectionEnd = normalized(point: point, in: imageRect)
            }
            .onEnded { value in
                if annotationDragSnapshot != nil || activeAnnotationHandle != nil {
                    annotationDragSnapshot = nil
                    activeAnnotationHandle = nil
                    dragStart = nil
                    return
                }

                if selectedTool == .text, selection.width < 4 || selection.height < 4 {
                    placeDefaultTextBox(at: clamped(value.location, to: imageRect), in: imageRect)
                }
                dragStart = nil
                if selectedTool.appliesLive, canApplySelectedTool {
                    applySelectedTool()
                }
            }
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        guard rect.isRenderable else {
            return .zero
        }
        return CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func normalized(point: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.isRenderable else {
            return .zero
        }

        return CGPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )
    }

    private func placeDefaultTextBox(at point: CGPoint, in imageRect: CGRect) {
        guard imageRect.isRenderable else {
            return
        }

        displayToPixelScale = pixelScale(for: imageRect)
        let size = CGSize(width: min(260, imageRect.width), height: 64)
        let origin = CGPoint(
            x: min(max(point.x, imageRect.minX), max(imageRect.minX, imageRect.maxX - size.width)),
            y: min(max(point.y, imageRect.minY), max(imageRect.minY, imageRect.maxY - size.height))
        )
        selectionStart = origin
        selectionEnd = CGPoint(x: origin.x + size.width, y: origin.y + size.height)
        selection = CGRect(origin: origin, size: size)
        normalizedSelection = CGRect(
            x: (selection.minX - imageRect.minX) / imageRect.width,
            y: (selection.minY - imageRect.minY) / imageRect.height,
            width: selection.width / imageRect.width,
            height: selection.height / imageRect.height
        )
        normalizedSelectionStart = normalized(point: selectionStart, in: imageRect)
        normalizedSelectionEnd = normalized(point: selectionEnd, in: imageRect)
    }

    private func beginOrContinueAnnotationManipulation(
        at point: CGPoint,
        translation: CGSize,
        in imageRect: CGRect
    ) -> Bool {
        guard selectedTool.appliesLive else {
            return false
        }

        if let selectedAnnotation = selectedAnnotation,
           annotationDragSnapshot == nil,
           let handle = selectedAnnotation.hitHandle(at: point, in: imageRect) {
            annotationDragSnapshot = selectedAnnotation
            activeAnnotationHandle = handle
        } else if annotationDragSnapshot == nil,
                  let hitAnnotation = annotations.reversed().first(where: { $0.hitTest(point, in: imageRect) }) {
            select(hitAnnotation)
            annotationDragSnapshot = hitAnnotation
            activeAnnotationHandle = nil
        }

        guard let snapshot = annotationDragSnapshot,
              let index = annotations.firstIndex(where: { $0.id == snapshot.id }) else {
            return false
        }

        let delta = CGSize(
            width: translation.width / imageRect.width,
            height: translation.height / imageRect.height
        )
        if let activeAnnotationHandle {
            annotations[index] = snapshot.resized(handle: activeAnnotationHandle, by: delta)
        } else {
            annotations[index] = snapshot.moved(by: delta)
        }
        return true
    }

    private func applySelectedTool() {
        if selectedTool.appliesLive {
            addAnnotation()
        } else {
            applyDestructive(
                selectedTool.operation(
                    color: NSColor(annotationColor),
                    fillColor: fillsShape ? NSColor(fillColor) : nil,
                    lineWidth: CGFloat(lineWidth),
                    text: annotationText,
                    textSize: CGFloat(textSize),
                    start: normalizedSelectionStart,
                    end: normalizedSelectionEnd,
                    points: normalizedFreehandPoints,
                    displayScale: displayToPixelScale
                )
            )
        }
    }

    private func apply(_ operation: ClipboardImageEditing.Operation) {
        applyDestructive(operation)
    }

    private func applyDestructive(_ operation: ClipboardImageEditing.Operation) {
        let sourceData = rasterizedImageData() ?? workingImageData
        guard let editedData = ClipboardImageEditing.edit(
                sourceData,
                normalizedSelection: normalizedSelection,
                operation: operation
              ) else {
            return
        }
        workingImageData = editedData
        annotations = []
        selectedAnnotationID = nil
        clearSelection()
    }

    private func addAnnotation() {
        let text = annotationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedTool != .text || !text.isEmpty else {
            return
        }

        let annotation = ImageAnnotation(
            tool: selectedTool,
            normalizedSelection: normalizedSelection,
            start: normalizedSelectionStart,
            end: normalizedSelectionEnd,
            points: normalizedFreehandPoints,
            color: NSColor(annotationColor),
            fillColor: fillsShape ? NSColor(fillColor) : nil,
            lineWidth: max(1, CGFloat(lineWidth) * displayToPixelScale),
            text: annotationText,
            textSize: max(10, CGFloat(textSize) * displayToPixelScale),
            displayScale: max(displayToPixelScale, 1)
        )
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        clearSelection()
    }

    private func rasterizedImageData() -> Data? {
        guard !annotations.isEmpty else {
            return workingImageData
        }

        var data = workingImageData
        for annotation in annotations {
            guard let editedData = ClipboardImageEditing.edit(
                data,
                normalizedSelection: annotation.normalizedSelection,
                operation: annotation.operation
            ) else {
                continue
            }
            data = editedData
        }
        return data
    }

    private func select(_ annotation: ImageAnnotation) {
        selectedAnnotationID = annotation.id
        selectedTool = annotation.tool
    }

    private func loadSelectedAnnotationControls() {
        guard let annotation = selectedAnnotation else {
            return
        }

        annotationColor = Color(nsColor: annotation.color)
        if let annotationFillColor = annotation.fillColor {
            fillColor = Color(nsColor: annotationFillColor)
            fillsShape = true
        } else {
            fillsShape = false
        }
        lineWidth = Double(max(1, annotation.lineWidth / annotation.displayScale))
        textSize = Double(max(10, annotation.textSize / annotation.displayScale))
        annotationText = annotation.text
    }

    private var selectedAnnotation: ImageAnnotation? {
        guard let selectedAnnotationID else {
            return nil
        }
        return annotations.first { $0.id == selectedAnnotationID }
    }

    private func updateSelectedAnnotation() {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }

        annotations[index].color = NSColor(annotationColor)
        annotations[index].fillColor = fillsShape ? NSColor(fillColor) : nil
        annotations[index].lineWidth = max(1, CGFloat(lineWidth) * annotations[index].displayScale)
        annotations[index].textSize = max(10, CGFloat(textSize) * annotations[index].displayScale)
        annotations[index].text = annotationText
    }

    private func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else {
            return
        }
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
    }

    private func duplicateSelectedAnnotation() {
        guard let selectedAnnotation,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotation.id }) else {
            return
        }

        let duplicate = selectedAnnotation.copyWithNewID().moved(by: CGSize(width: 0.025, height: 0.025))
        annotations.insert(duplicate, at: min(index + 1, annotations.count))
        selectedAnnotationID = duplicate.id
    }

    private func moveSelectedAnnotationForward() {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              index < annotations.count - 1 else {
            return
        }

        annotations.swapAt(index, index + 1)
    }

    private func moveSelectedAnnotationBackward() {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              index > 0 else {
            return
        }

        annotations.swapAt(index, index - 1)
    }

    private func clearSelection() {
        selection = .zero
        normalizedSelection = .zero
        selectionStart = .zero
        selectionEnd = .zero
        normalizedSelectionStart = .zero
        normalizedSelectionEnd = .zero
        freehandPoints = []
        normalizedFreehandPoints = []
        displayToPixelScale = 1
    }

    private func pixelScale(for imageRect: CGRect) -> CGFloat {
        guard imageRect.isRenderable,
              let bitmap = NSBitmapImageRep(data: workingImageData),
              bitmap.pixelsWide > 0 else {
            return 1
        }

        let scale = CGFloat(bitmap.pixelsWide) / imageRect.width
        return scale.isFinite && scale > 0 ? scale : 1
    }
}

private extension CGSize {
    var isRenderable: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

private extension CGRect {
    var isRenderable: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.isRenderable
    }
}

private extension CGPoint {
    func displayPoint(in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + x * imageRect.width,
            y: imageRect.minY + y * imageRect.height
        )
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    func clampedToUnit() -> CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    func distanceToSegment(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else {
            return hypot(x - start.x, y - start.y)
        }

        let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(x - projection.x, y - projection.y)
    }
}

private struct ImageAnnotation: Identifiable {
    var id = UUID()
    var tool: ClipboardImageEditing.Tool
    var normalizedSelection: CGRect
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint]
    var color: NSColor
    var fillColor: NSColor?
    var lineWidth: CGFloat
    var text: String
    var textSize: CGFloat
    var displayScale: CGFloat

    var operation: ClipboardImageEditing.Operation {
        switch tool {
        case .rectangle:
            return .rectangle(color: color.cgColor, fillColor: fillColor?.cgColor, lineWidth: lineWidth)
        case .roundedRectangle:
            return .roundedRectangle(color: color.cgColor, fillColor: fillColor?.cgColor, lineWidth: lineWidth)
        case .oval:
            return .oval(color: color.cgColor, fillColor: fillColor?.cgColor, lineWidth: lineWidth)
        case .line:
            return .line(color: color.cgColor, lineWidth: lineWidth, start: start, end: end)
        case .arrow:
            return .arrow(color: color.cgColor, lineWidth: lineWidth, start: start, end: end)
        case .highlight:
            return .highlight(color: color.cgColor)
        case .freehand:
            return .freehand(color: color.cgColor, lineWidth: lineWidth, points: points)
        case .text:
            return .text(text, color: color.cgColor, fontSize: textSize)
        case .crop:
            return .crop
        case .redact:
            return .redact
        }
    }

    func copyWithNewID() -> ImageAnnotation {
        var copy = self
        copy.id = UUID()
        return copy
    }

    func displayRect(in imageRect: CGRect) -> CGRect {
        let rect = normalizedSelection.standardized
        return CGRect(
            x: imageRect.minX + rect.minX * imageRect.width,
            y: imageRect.minY + rect.minY * imageRect.height,
            width: rect.width * imageRect.width,
            height: rect.height * imageRect.height
        )
    }

    func hitTest(_ point: CGPoint, in imageRect: CGRect) -> Bool {
        let tolerance: CGFloat = 8
        switch tool {
        case .line, .arrow:
            return point.distanceToSegment(
                from: start.displayPoint(in: imageRect),
                to: end.displayPoint(in: imageRect)
            ) <= tolerance
        case .freehand:
            let displayPoints = points.map { $0.displayPoint(in: imageRect) }
            guard displayPoints.count > 1 else {
                return false
            }
            return zip(displayPoints, displayPoints.dropFirst()).contains { first, second in
                point.distanceToSegment(from: first, to: second) <= tolerance
            }
        case .crop, .redact:
            return false
        case .rectangle, .roundedRectangle, .oval, .highlight, .text:
            return displayRect(in: imageRect).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    func hitHandle(at point: CGPoint, in imageRect: CGRect) -> AnnotationHandle? {
        handles(in: imageRect).first { handle in
            hypot(point.x - handle.position.x, point.y - handle.position.y) <= 9
        }?.kind
    }

    func handles(in imageRect: CGRect) -> [AnnotationHandlePosition] {
        switch tool {
        case .line, .arrow:
            return [
                AnnotationHandlePosition(kind: .start, position: start.displayPoint(in: imageRect)),
                AnnotationHandlePosition(kind: .end, position: end.displayPoint(in: imageRect))
            ]
        case .freehand, .crop, .redact:
            return []
        case .rectangle, .roundedRectangle, .oval, .highlight, .text:
            let rect = displayRect(in: imageRect)
            return [
                AnnotationHandlePosition(kind: .topLeft, position: CGPoint(x: rect.minX, y: rect.minY)),
                AnnotationHandlePosition(kind: .topRight, position: CGPoint(x: rect.maxX, y: rect.minY)),
                AnnotationHandlePosition(kind: .bottomLeft, position: CGPoint(x: rect.minX, y: rect.maxY)),
                AnnotationHandlePosition(kind: .bottomRight, position: CGPoint(x: rect.maxX, y: rect.maxY))
            ]
        }
    }

    func moved(by delta: CGSize) -> ImageAnnotation {
        var copy = self
        let clampedDelta = clampedMoveDelta(delta)
        copy.normalizedSelection = normalizedSelection.offsetBy(
            dx: clampedDelta.width,
            dy: clampedDelta.height
        )
        copy.start = start.offsetBy(dx: clampedDelta.width, dy: clampedDelta.height)
        copy.end = end.offsetBy(dx: clampedDelta.width, dy: clampedDelta.height)
        copy.points = points.map { $0.offsetBy(dx: clampedDelta.width, dy: clampedDelta.height) }
        return copy
    }

    func resized(handle: AnnotationHandle, by delta: CGSize) -> ImageAnnotation {
        var copy = self
        switch handle {
        case .start:
            copy.start = start.offsetBy(dx: delta.width, dy: delta.height).clampedToUnit()
            copy.normalizedSelection = CGRect(
                x: min(copy.start.x, end.x),
                y: min(copy.start.y, end.y),
                width: abs(end.x - copy.start.x),
                height: abs(end.y - copy.start.y)
            )
        case .end:
            copy.end = end.offsetBy(dx: delta.width, dy: delta.height).clampedToUnit()
            copy.normalizedSelection = CGRect(
                x: min(start.x, copy.end.x),
                y: min(start.y, copy.end.y),
                width: abs(copy.end.x - start.x),
                height: abs(copy.end.y - start.y)
            )
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            copy.normalizedSelection = resizedRect(handle: handle, by: delta)
                .standardized
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return copy
    }

    private func resizedRect(handle: AnnotationHandle, by delta: CGSize) -> CGRect {
        var rect = normalizedSelection.standardized
        switch handle {
        case .topLeft:
            rect = CGRect(x: rect.minX + delta.width, y: rect.minY + delta.height, width: rect.width - delta.width, height: rect.height - delta.height)
        case .topRight:
            rect = CGRect(x: rect.minX, y: rect.minY + delta.height, width: rect.width + delta.width, height: rect.height - delta.height)
        case .bottomLeft:
            rect = CGRect(x: rect.minX + delta.width, y: rect.minY, width: rect.width - delta.width, height: rect.height + delta.height)
        case .bottomRight:
            rect = CGRect(x: rect.minX, y: rect.minY, width: rect.width + delta.width, height: rect.height + delta.height)
        case .start, .end:
            break
        }
        let minimum: CGFloat = 0.01
        if abs(rect.width) < minimum {
            rect.size.width = rect.width < 0 ? -minimum : minimum
        }
        if abs(rect.height) < minimum {
            rect.size.height = rect.height < 0 ? -minimum : minimum
        }
        return rect
    }

    private func clampedMoveDelta(_ delta: CGSize) -> CGSize {
        let bounds = overallBounds
        return CGSize(
            width: min(max(delta.width, -bounds.minX), 1 - bounds.maxX),
            height: min(max(delta.height, -bounds.minY), 1 - bounds.maxY)
        )
    }

    private var overallBounds: CGRect {
        switch tool {
        case .line, .arrow:
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case .freehand:
            guard let first = points.first else {
                return .zero
            }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
                rect.union(CGRect(origin: point, size: .zero))
            }
        case .crop, .redact, .rectangle, .roundedRectangle, .oval, .highlight, .text:
            return normalizedSelection.standardized
        }
    }
}

private enum AnnotationHandle {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case start
    case end
}

private struct AnnotationHandlePosition: Identifiable {
    let id = UUID()
    let kind: AnnotationHandle
    let position: CGPoint
}

enum ClipboardImageEditing {
    enum Tool: String, CaseIterable, Identifiable {
        case crop
        case redact
        case rectangle
        case roundedRectangle
        case oval
        case line
        case arrow
        case highlight
        case freehand
        case text

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .crop:
                return "Crop"
            case .redact:
                return "Redact"
            case .rectangle:
                return "Rectangle"
            case .roundedRectangle:
                return "Rounded Rectangle"
            case .oval:
                return "Oval"
            case .line:
                return "Line"
            case .arrow:
                return "Arrow"
            case .highlight:
                return "Highlight"
            case .freehand:
                return "Sketch"
            case .text:
                return "Text"
            }
        }

        var systemImageName: String {
            switch self {
            case .crop:
                return "crop"
            case .redact:
                return "rectangle.fill"
            case .rectangle:
                return "rectangle"
            case .roundedRectangle:
                return "capsule"
            case .oval:
                return "oval"
            case .line:
                return "line.diagonal"
            case .arrow:
                return "arrow.up.right"
            case .highlight:
                return "highlighter"
            case .freehand:
                return "pencil.and.scribble"
            case .text:
                return "textformat"
            }
        }

        var usesColor: Bool {
            switch self {
            case .crop, .redact:
                return false
            case .rectangle, .roundedRectangle, .oval, .line, .arrow, .highlight, .freehand, .text:
                return true
            }
        }

        var usesLineWidth: Bool {
            switch self {
            case .crop, .redact, .highlight, .text:
                return false
            case .rectangle, .roundedRectangle, .oval, .line, .arrow, .freehand:
                return true
            }
        }

        var usesFill: Bool {
            switch self {
            case .rectangle, .roundedRectangle, .oval:
                return true
            case .crop, .redact, .line, .arrow, .highlight, .freehand, .text:
                return false
            }
        }

        var appliesLive: Bool {
            switch self {
            case .crop, .redact:
                return false
            case .rectangle, .roundedRectangle, .oval, .line, .arrow, .highlight, .freehand, .text:
                return true
            }
        }

        func operation(
            color: NSColor,
            fillColor: NSColor?,
            lineWidth: CGFloat,
            text: String,
            textSize: CGFloat,
            start: CGPoint,
            end: CGPoint,
            points: [CGPoint],
            displayScale: CGFloat
        ) -> Operation {
            let scaledLineWidth = max(1, lineWidth * displayScale)
            let scaledFontSize = max(10, textSize * displayScale)
            switch self {
            case .crop:
                return .crop
            case .redact:
                return .redact
            case .rectangle:
                return .rectangle(
                    color: color.cgColor,
                    fillColor: fillColor?.cgColor,
                    lineWidth: scaledLineWidth
                )
            case .roundedRectangle:
                return .roundedRectangle(
                    color: color.cgColor,
                    fillColor: fillColor?.cgColor,
                    lineWidth: scaledLineWidth
                )
            case .oval:
                return .oval(
                    color: color.cgColor,
                    fillColor: fillColor?.cgColor,
                    lineWidth: scaledLineWidth
                )
            case .line:
                return .line(color: color.cgColor, lineWidth: scaledLineWidth, start: start, end: end)
            case .arrow:
                return .arrow(color: color.cgColor, lineWidth: scaledLineWidth, start: start, end: end)
            case .highlight:
                return .highlight(color: color.cgColor)
            case .freehand:
                return .freehand(color: color.cgColor, lineWidth: scaledLineWidth, points: points)
            case .text:
                return .text(text, color: color.cgColor, fontSize: scaledFontSize)
            }
        }
    }

    enum Operation {
        case crop
        case redact
        case outline
        case rectangle(color: CGColor, fillColor: CGColor?, lineWidth: CGFloat)
        case roundedRectangle(color: CGColor, fillColor: CGColor?, lineWidth: CGFloat)
        case oval(color: CGColor, fillColor: CGColor?, lineWidth: CGFloat)
        case line(color: CGColor, lineWidth: CGFloat, start: CGPoint, end: CGPoint)
        case arrow(color: CGColor, lineWidth: CGFloat, start: CGPoint, end: CGPoint)
        case highlight(color: CGColor)
        case freehand(color: CGColor, lineWidth: CGFloat, points: [CGPoint])
        case text(String, color: CGColor, fontSize: CGFloat)
        case rotateLeft
        case rotateRight
        case flipHorizontal
        case flipVertical
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

        let result: CGImage?
        switch operation {
        case .rotateLeft:
            result = rotated(image, clockwise: false)
        case .rotateRight:
            result = rotated(image, clockwise: true)
        case .flipHorizontal:
            result = flipped(image, horizontally: true)
        case .flipVertical:
            result = flipped(image, horizontally: false)
        case .crop:
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = image.cropping(to: pixelRect(for: selection, in: image, origin: .topLeft))
        case .redact:
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = redacted(image, pixelRect: pixelRect(for: selection, in: image, origin: .bottomLeft))
        case .outline:
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = outlined(image, pixelRect: pixelRect(for: selection, in: image, origin: .bottomLeft))
        case .rectangle(let color, let fillColor, let lineWidth):
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = strokedRectangle(
                image,
                pixelRect: pixelRect(for: selection, in: image, origin: .bottomLeft),
                color: color,
                fillColor: fillColor,
                lineWidth: lineWidth
            )
        case .roundedRectangle(let color, let fillColor, let lineWidth):
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = strokedRoundedRectangle(
                image,
                pixelRect: pixelRect(for: selection, in: image, origin: .bottomLeft),
                color: color,
                fillColor: fillColor,
                lineWidth: lineWidth
            )
        case .oval(let color, let fillColor, let lineWidth):
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = strokedOval(
                image,
                pixelRect: pixelRect(for: selection, in: image, origin: .bottomLeft),
                color: color,
                fillColor: fillColor,
                lineWidth: lineWidth
            )
        case .line(let color, let lineWidth, let start, let end):
            result = line(
                image,
                start: pixelPoint(for: start, in: image, origin: .bottomLeft),
                end: pixelPoint(for: end, in: image, origin: .bottomLeft),
                color: color,
                lineWidth: lineWidth,
                drawsArrow: false
            )
        case .arrow(let color, let lineWidth, let start, let end):
            result = line(
                image,
                start: pixelPoint(for: start, in: image, origin: .bottomLeft),
                end: pixelPoint(for: end, in: image, origin: .bottomLeft),
                color: color,
                lineWidth: lineWidth,
                drawsArrow: true
            )
        case .highlight(let color):
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = highlighted(
                image,
                pixelRect: pixelRect(for: selection, in: image, origin: .bottomLeft),
                color: color
            )
        case .freehand(let color, let lineWidth, let points):
            result = freehand(
                image,
                points: points.map { pixelPoint(for: $0, in: image, origin: .bottomLeft) },
                color: color,
                lineWidth: lineWidth
            )
        case .text(let text, let color, let fontSize):
            guard let selection = usableSelection(normalizedSelection) else {
                return nil
            }
            result = textAnnotation(
                image,
                pixelRect: pixelRect(for: selection, in: image, origin: .bottomLeft),
                text: text,
                color: color,
                fontSize: fontSize
            )
        }
        return result.flatMap(encodedPNGData)
    }

    private static func usableSelection(_ normalizedSelection: CGRect) -> CGRect? {
        let selection = normalizedSelection.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        return selection.width > 0 && selection.height > 0 ? selection : nil
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

    private static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let outputWidth = image.height
        let outputHeight = image.width
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        if clockwise {
            context.translateBy(x: CGFloat(outputWidth), y: 0)
            context.rotate(by: .pi / 2)
        } else {
            context.translateBy(x: 0, y: CGFloat(outputHeight))
            context.rotate(by: -.pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func flipped(_ image: CGImage, horizontally: Bool) -> CGImage? {
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

        if horizontally {
            context.translateBy(x: CGFloat(image.width), y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: CGFloat(image.height))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func outlined(_ image: CGImage, pixelRect: CGRect) -> CGImage? {
        strokedRectangle(
            image,
            pixelRect: pixelRect,
            color: CGColor(red: 1, green: 0.15, blue: 0.1, alpha: 1),
            fillColor: nil,
            lineWidth: max(3, CGFloat(image.width) / 300)
        )
    }

    private static func strokedRectangle(
        _ image: CGImage,
        pixelRect: CGRect,
        color: CGColor,
        fillColor: CGColor?,
        lineWidth: CGFloat
    ) -> CGImage? {
        editedImage(image) { context in
            if let fillColor {
                context.setFillColor(fillColor)
                context.fill(pixelRect)
            }
            configureStroke(context, color: color, lineWidth: lineWidth)
            let inset = max(1, lineWidth / 2)
            context.stroke(pixelRect.insetBy(dx: inset, dy: inset))
        }
    }

    private static func strokedRoundedRectangle(
        _ image: CGImage,
        pixelRect: CGRect,
        color: CGColor,
        fillColor: CGColor?,
        lineWidth: CGFloat
    ) -> CGImage? {
        editedImage(image) { context in
            let cornerRadius = min(pixelRect.width, pixelRect.height) * 0.16
            let rectPath = CGPath(
                roundedRect: pixelRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            if let fillColor {
                context.setFillColor(fillColor)
                context.addPath(rectPath)
                context.fillPath()
            }
            configureStroke(context, color: color, lineWidth: lineWidth)
            context.addPath(rectPath)
            context.strokePath()
        }
    }

    private static func strokedOval(
        _ image: CGImage,
        pixelRect: CGRect,
        color: CGColor,
        fillColor: CGColor?,
        lineWidth: CGFloat
    ) -> CGImage? {
        editedImage(image) { context in
            if let fillColor {
                context.setFillColor(fillColor)
                context.fillEllipse(in: pixelRect)
            }
            configureStroke(context, color: color, lineWidth: lineWidth)
            let inset = max(1, lineWidth / 2)
            context.strokeEllipse(in: pixelRect.insetBy(dx: inset, dy: inset))
        }
    }

    private static func freehand(
        _ image: CGImage,
        points: [CGPoint],
        color: CGColor,
        lineWidth: CGFloat
    ) -> CGImage? {
        guard let first = points.first, points.count > 1 else {
            return nil
        }

        return editedImage(image) { context in
            configureStroke(context, color: color, lineWidth: lineWidth)
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
    }

    private static func line(
        _ image: CGImage,
        start: CGPoint,
        end: CGPoint,
        color: CGColor,
        lineWidth: CGFloat,
        drawsArrow: Bool
    ) -> CGImage? {
        editedImage(image) { context in
            configureStroke(context, color: color, lineWidth: lineWidth)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

            if drawsArrow {
                drawArrowhead(in: context, from: start, to: end, color: color, lineWidth: lineWidth)
            }
        }
    }

    private static func highlighted(_ image: CGImage, pixelRect: CGRect, color: CGColor) -> CGImage? {
        editedImage(image) { context in
            context.setBlendMode(.multiply)
            context.setFillColor(color.copy(alpha: 0.35) ?? color)
            context.fill(pixelRect)
        }
    }

    private static func textAnnotation(
        _ image: CGImage,
        pixelRect: CGRect,
        text: String,
        color: CGColor,
        fontSize: CGFloat
    ) -> CGImage? {
        editedImage(image) { context in
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(10, fontSize), weight: .semibold),
                .foregroundColor: NSColor(cgColor: color) ?? .red,
                .paragraphStyle: paragraphStyle
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            attributedText.draw(in: pixelRect.insetBy(dx: 4, dy: 4))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func configureStroke(_ context: CGContext, color: CGColor, lineWidth: CGFloat) {
        context.setStrokeColor(color)
        context.setLineWidth(max(1, lineWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    private static func drawArrowhead(
        in context: CGContext,
        from start: CGPoint,
        to end: CGPoint,
        color: CGColor,
        lineWidth: CGFloat
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(14, lineWidth * 4)
        let spread = CGFloat.pi / 7
        let first = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let second = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )
        context.setFillColor(color)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: first)
        context.addLine(to: second)
        context.closePath()
        context.fillPath()
    }

    private enum PixelCoordinateOrigin {
        case topLeft
        case bottomLeft
    }

    private static func pixelRect(
        for selection: CGRect,
        in image: CGImage,
        origin: PixelCoordinateOrigin
    ) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        let y = switch origin {
        case .topLeft:
            selection.minY * imageSize.height
        case .bottomLeft:
            (1 - selection.maxY) * imageSize.height
        }

        return CGRect(
            x: selection.minX * imageSize.width,
            y: y,
            width: selection.width * imageSize.width,
            height: selection.height * imageSize.height
        ).integral
    }

    private static func pixelPoint(
        for point: CGPoint,
        in image: CGImage,
        origin: PixelCoordinateOrigin
    ) -> CGPoint {
        let imageSize = CGSize(width: image.width, height: image.height)
        let y = switch origin {
        case .topLeft:
            point.y * imageSize.height
        case .bottomLeft:
            (1 - point.y) * imageSize.height
        }

        return CGPoint(
            x: point.x * imageSize.width,
            y: y
        )
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
