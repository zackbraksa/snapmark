import AppKit
import SwiftUI

struct AnnotationCanvas: NSViewRepresentable {
    let document: EditorDocument
    func makeNSView(context: Context) -> CanvasView { CanvasView(document: document) }
    func updateNSView(_ view: CanvasView, context: Context) {
        view.document = document
        view.refreshCursorRects(tool: document.tool, selection: document.selectedID, revision: document.revision)
        view.needsDisplay = true
    }
}

@MainActor final class CanvasView: NSView {
    var document: EditorDocument
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var originalPoints: [CGPoint]?
    private var originalRect: CGRect?
    private var resizing = false
    private var moved = false
    private var cursorTool: AnnotationTool?
    private var cursorSelection: UUID?
    private var cursorRevision = -1
    private var blurSource: AnnotationRenderer.BlurSource
    init(document: EditorDocument, blurSource: AnnotationRenderer.BlurSource? = nil) { self.document = document; self.blurSource = blurSource ?? AnnotationRenderer.BlurSource(image: document.image); super.init(frame: .zero); setAccessibilityLabel("Screenshot annotation canvas"); setAccessibilityRole(.image) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var scale: CGFloat { bounds.width / CGFloat(document.image.width) }
    func refreshCursorRects(tool: AnnotationTool, selection: UUID?, revision: Int) {
        if cursorTool != tool || cursorSelection != selection || cursorRevision != revision {
            cursorTool = tool
            cursorSelection = selection
            cursorRevision = revision
            window?.invalidateCursorRects(for: self)
        }
    }

    private func selectionRect(for annotation: Annotation) -> CGRect {
        annotation.rect.insetBy(dx: -5 / scale, dy: -5 / scale)
    }

    private func resizeHandle(for annotation: Annotation) -> CGRect? {
        guard annotation.tool != .text else { return nil }
        let rect = selectionRect(for: annotation)
        let side = 8 / scale
        let inset = 1 / scale
        return CGRect(x: min(max(inset, rect.maxX - side / 2), document.imageSize.width - side - inset),
                      y: min(max(inset, rect.maxY - side / 2), document.imageSize.height - side - inset),
                      width: side, height: side)
    }

    private func resizeHitRect(for annotation: Annotation) -> CGRect? {
        resizeHandle(for: annotation)?.insetBy(dx: -8 / scale, dy: -8 / scale)
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    private var resizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .bottomRight, directions: [.inward, .outward])
        }
        return .crosshair
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard scale > 0 else { return }
        addCursorRect(bounds, cursor: document.tool == .select ? .arrow : .crosshair)
        guard document.tool == .select else { return }
        for annotation in document.annotations {
            let rect = viewRect(annotation.rect.insetBy(dx: -10 / scale, dy: -10 / scale)).intersection(bounds)
            if !rect.isEmpty { addCursorRect(rect, cursor: .openHand) }
        }
        if let selected = document.annotations.first(where: { $0.id == document.selectedID }),
           let handle = resizeHitRect(for: selected) {
            addCursorRect(viewRect(handle).intersection(bounds), cursor: resizeCursor)
        }
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x / scale, 0), CGFloat(document.image.width)), y: min(max(p.y / scale, 0), CGFloat(document.image.height)))
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
        NSImage(cgImage: document.image, size: document.imageSize).draw(in: CGRect(origin: .zero, size: document.imageSize), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        if blurSource.image !== document.image { blurSource = AnnotationRenderer.BlurSource(image: document.image) }
        let drawingAnnotations = document.annotations + (draft.map { [$0] } ?? [])
        let rendered = AnnotationRenderer.draw(drawingAnnotations, image: document.image, blurSource: blurSource)
        toolTip = rendered ? nil : "Could not render blur. Affected areas are covered."
        if let draft, draft.tool == .crop {
            let path = NSBezierPath(rect: draft.rect)
            path.setLineDash([6 / scale, 4 / scale], count: 2, phase: 0)
            strokeEditorGuide(path, width: 2)
        }
        if let crop = document.crop {
            NSColor.black.withAlphaComponent(0.35).setFill()
            let mask = NSBezierPath(rect: CGRect(origin: .zero, size: document.imageSize)); mask.appendRect(crop); mask.windingRule = .evenOdd; mask.fill()
        }
        if let selected = document.annotations.first(where: { $0.id == document.selectedID }) {
            let rect = selectionRect(for: selected)
            strokeEditorGuide(NSBezierPath(rect: rect), width: 1)
            if document.tool == .select, let handle = resizeHandle(for: selected) {
                NSColor.black.setFill()
                handle.insetBy(dx: -1 / scale, dy: -1 / scale).fill()
                SnapmarkTint.canvasGuide.setFill()
                handle.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func strokeEditorGuide(_ path: NSBezierPath, width: CGFloat) {
        NSColor.black.setStroke()
        path.lineWidth = (width + 2) / scale
        path.stroke()
        SnapmarkTint.canvasGuide.setStroke()
        path.lineWidth = width / scale
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event); dragStart = p; moved = false
        if document.tool == .select {
            if let selected = document.annotations.first(where: { $0.id == document.selectedID }), resizeHitRect(for: selected)?.contains(p) == true {
                resizing = true; originalPoints = selected.points; originalRect = selected.rect; resizeCursor.set(); return
            }
            document.selectedID = document.annotations.reversed().first(where: { $0.rect.insetBy(dx: -10 / scale, dy: -10 / scale).contains(p) })?.id
            let selected = document.annotations.first(where: { $0.id == document.selectedID })
            originalPoints = selected?.points
            originalRect = selected?.rect
            window?.invalidateCursorRects(for: self)
            if let selected, selected.tool == .text { document.text = selected.text }
            needsDisplay = true; return
        }
        if document.tool == .text {
            guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { document.status = "Enter text in the options row, then click the image"; return }
            document.add(Annotation(tool: .text, points: [p], color: document.color, width: document.strokeWidth, text: document.text)); needsDisplay = true; return
        }
        if document.tool == .marker {
            document.addMarker(at: p); needsDisplay = true; return
        }
        draft = Annotation(tool: document.tool, points: [p, p], color: document.color, width: document.strokeWidth)
    }
    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        if document.tool == .select, let start = dragStart, let originalPoints, let index = document.annotations.firstIndex(where: { $0.id == document.selectedID }) {
            if !moved && p == start { return }
            if !moved { document.checkpoint(); moved = true }
            if resizing { resizeCursor.set() } else { NSCursor.closedHand.set() }
            let originalRect = self.originalRect ?? document.annotations[index].rect
            if resizing && (originalRect.width > 0 || originalRect.height > 0) {
                if document.annotations[index].tool == .marker {
                    let diameter = max(16, originalRect.width + p.x - start.x, originalRect.height + p.y - start.y)
                    document.annotations[index].points = [originalRect.origin, CGPoint(x: originalRect.minX + diameter, y: originalRect.minY + diameter)]
                } else {
                    let sx = max(2, originalRect.width + p.x - start.x) / max(1, originalRect.width), sy = max(2, originalRect.height + p.y - start.y) / max(1, originalRect.height)
                    document.annotations[index].points = originalPoints.map { CGPoint(x: originalRect.minX + ($0.x - originalRect.minX) * sx, y: originalRect.minY + ($0.y - originalRect.minY) * sy) }
                }
            } else {
                document.annotations[index].points = originalPoints.map { CGPoint(x: $0.x + p.x - start.x, y: $0.y + p.y - start.y) }
            }
        } else if draft != nil {
            if draft?.tool == .pen { draft?.points.append(p) } else { draft?.points[1] = p }
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let draft, draft.rect.width > 1 || draft.rect.height > 1 {
            if draft.tool == .crop { document.setCrop(draft.rect) } else { document.add(draft) }
        } else if moved { document.commit() }
        draft = nil; dragStart = nil; originalPoints = nil; originalRect = nil; resizing = false; moved = false; needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { document.deleteSelection(); needsDisplay = true }
        else if event.keyCode == 53 { document.selectedID = nil; draft = nil; needsDisplay = true }
        else { super.keyDown(with: event) }
    }
}
