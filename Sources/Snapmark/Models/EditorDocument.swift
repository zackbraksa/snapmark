import AppKit
import Observation

@MainActor @Observable final class EditorDocument {
    let image: CGImage
    var annotations: [Annotation] = []
    var crop: CGRect?
    var selectedID: UUID?
    var tool: AnnotationTool {
        didSet {
            annotationPreferences.tool = tool
            color = annotationPreferences.color(for: tool)
            strokeWidth = annotationPreferences.strokeWidth(for: tool)
        }
    }
    var color: NSColor { didSet { annotationPreferences.setColor(color, for: tool) } }
    var strokeWidth: CGFloat { didSet { annotationPreferences.setStrokeWidth(strokeWidth, for: tool) } }
    var text = ""
    var zoom: CGFloat = 1
    var status = ""
    var revision = 0
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let clipboard: any ImageClipboard
    private let annotationPreferences: AnnotationPreferences
    private var clipboardCount: Int?
    private var autoCopyPaused = false
    private struct Snapshot { var annotations: [Annotation]; var crop: CGRect? }
    init(image: CGImage, clipboard: (any ImageClipboard)? = nil, annotationPreferences: AnnotationPreferences? = nil) {
        let preferences = annotationPreferences ?? AnnotationPreferences()
        self.image = image; self.clipboard = clipboard ?? SystemImageClipboard(); self.annotationPreferences = preferences
        tool = preferences.tool; color = preferences.color; strokeWidth = preferences.strokeWidth
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    func checkpoint() {
        undoStack.append(Snapshot(annotations: annotations, crop: crop)); redoStack.removeAll()
    }
    func commit() { revision += 1; automaticCopy() }
    func add(_ annotation: Annotation) { checkpoint(); annotations.append(annotation); selectedID = annotation.id; commit() }
    func addMarker(at center: CGPoint) {
        let number = annotations.filter { $0.tool == .marker }.compactMap(\.number).max().map { $0 + 1 } ?? 1
        let radius = max(28, strokeWidth * 8) / 2
        add(Annotation(tool: .marker, points: [CGPoint(x: center.x - radius, y: center.y - radius), CGPoint(x: center.x + radius, y: center.y + radius)], color: color, width: strokeWidth, number: number))
    }
    func setCrop(_ rect: CGRect) {
        let clipped = rect.integral.intersection(CGRect(origin: .zero, size: imageSize))
        guard clipped.width >= 2, clipped.height >= 2 else { return }
        checkpoint(); crop = clipped; commit()
    }
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(annotations: annotations, crop: crop)); annotations = previous.annotations; crop = previous.crop; selectedID = nil; commit()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(annotations: annotations, crop: crop)); annotations = next.annotations; crop = next.crop; selectedID = nil; commit()
    }
    func deleteSelection() {
        guard let selectedID, annotations.contains(where: { $0.id == selectedID }) else { return }
        checkpoint(); annotations.removeAll { $0.id == selectedID }; self.selectedID = nil; commit()
    }
    func updateSelectedText() {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID && $0.tool == .text }) else { return }
        checkpoint(); annotations[index].text = text; commit()
    }
    func renderedImage() -> CGImage? { AnnotationRenderer.render(image: image, annotations: annotations, crop: crop) }
    func automaticCopy() {
        guard UserDefaults.standard.object(forKey: "automaticCopy") as? Bool ?? true else { return }
        guard !autoCopyPaused else { return }
        if let clipboardCount, clipboard.changeCount != clipboardCount {
            autoCopyPaused = true; status = "Auto-copy paused: clipboard changed. Copy to resume."; return
        }
        copy()
    }
    @discardableResult func copy() -> Bool {
        guard let rendered = renderedImage() else { status = "Could not render screenshot"; return false }
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { status = "Could not encode screenshot"; return false }
        clipboard.clear()
        guard clipboard.writePNG(png) else { status = "Could not copy screenshot"; return false }
        clipboardCount = clipboard.changeCount; autoCopyPaused = false; status = "Copied"
        return true
    }
    func exportPNG() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Screenshot.png"
        guard panel.runModal() == .OK, let url = panel.url, let rendered = renderedImage(), let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { return }
        do { try data.write(to: url, options: .atomic); status = "Saved \(url.lastPathComponent)" }
        catch { status = error.localizedDescription }
    }
}
