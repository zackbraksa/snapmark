import AppKit
import Testing
@testable import Snapmark

@MainActor struct EditorTests {
    func image() -> CGImage {
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        return context.makeImage()!
    }
    @Test func undoRedoPreservesEditableAnnotationsAndCrop() {
        let board = MemoryClipboard()
        let doc = EditorDocument(image: image(), clipboard: board)
        let arrow = Annotation(tool: .arrow, points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40)], color: .red, width: 4)
        doc.add(arrow); doc.setCrop(CGRect(x: 5, y: 5, width: 60, height: 50))
        #expect(doc.renderedImage()?.width == 60)
        doc.undo(); #expect(doc.crop == nil); #expect(doc.annotations.first?.id == arrow.id)
        doc.undo(); #expect(doc.annotations.isEmpty)
        doc.redo(); #expect(doc.annotations.first?.id == arrow.id)
        doc.selectedID = arrow.id; doc.deleteSelection(); #expect(doc.annotations.isEmpty)
        doc.undo(); #expect(doc.annotations.count == 1)
    }
    @Test func clipboardPausesAfterExternalChangeAndExplicitCopyResumes() {
        let board = MemoryClipboard()
        let doc = EditorDocument(image: image(), clipboard: board)
        #expect(doc.copy()); #expect(board.png != nil)
        board.externalWrite("Something else")
        doc.automaticCopy(); #expect(board.text == "Something else")
        #expect(doc.copy()); #expect(board.png != nil)
        doc.automaticCopy(); #expect(doc.status == "Copied")
    }
    @Test func failedCopyReportsFailureSoEditorCanRemainOpen() {
        let board = MemoryClipboard()
        board.allowWrite = false
        let doc = EditorDocument(image: image(), clipboard: board)
        #expect(!doc.copy())
        #expect(doc.status == "Could not copy screenshot")
        board.allowWrite = true
        #expect(doc.copy())
        #expect(doc.status == "Copied")
    }
    @Test func renderedRedactionUsesTopLeftImageCoordinates() {
        let board = MemoryClipboard()
        let doc = EditorDocument(image: image(), clipboard: board)
        doc.annotations = [Annotation(tool: .redact, points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)], color: .red, width: 4)]
        let result = NSBitmapImageRep(cgImage: doc.renderedImage()!)
        #expect(result.colorAt(x: 10, y: 10)!.usingColorSpace(.deviceRGB)!.redComponent < 0.1)
        #expect(result.colorAt(x: 10, y: 65)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9)
    }
}

@MainActor private final class MemoryClipboard: ImageClipboard {
    var allowWrite = true
    var changeCount = 0
    var png: Data?
    var text: String?
    func clear() { changeCount += 1; png = nil; text = nil }
    func writePNG(_ data: Data) -> Bool { guard allowWrite else { return false }; changeCount += 1; png = data; return true }
    func externalWrite(_ value: String) { clear(); text = value }
}
