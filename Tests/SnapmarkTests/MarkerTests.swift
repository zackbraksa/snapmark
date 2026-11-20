import AppKit
import Testing
@testable import Snapmark

@MainActor struct MarkerTests {
    private let suite = "Snapmark.MarkerTests.\(UUID().uuidString)"

    @Test func markerNumberingFollowsCurrentScreenshotAndUndoHistory() {
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let document = document()
        document.addMarker(at: CGPoint(x: 40, y: 40))
        document.addMarker(at: CGPoint(x: 90, y: 40))
        #expect(document.annotations.map(\.number) == [1, 2])
        #expect(document.annotations[0].rect.midX == 40 && document.annotations[0].rect.midY == 40)
        document.undo()
        document.redo()
        #expect(document.annotations.map(\.number) == [1, 2])
        document.undo()
        document.addMarker(at: CGPoint(x: 90, y: 80))
        #expect(document.annotations.map(\.number) == [1, 2])
        #expect(!document.canRedo)
        document.selectedID = document.annotations[0].id
        document.deleteSelection()
        document.addMarker(at: CGPoint(x: 40, y: 80))
        #expect(document.annotations.map(\.number) == [2, 3])
        let nextCapture = self.document()
        nextCapture.addMarker(at: CGPoint(x: 40, y: 40))
        #expect(nextCapture.annotations.first?.number == 1)
    }

    @Test func canvasPlacesOnClickAndResizesAMarkerAsACircle() throws {
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let document = document()
        document.tool = .marker
        let canvas = CanvasView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 160, height: 120)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 60, y: 60)))
        #expect(document.annotations.count == 1)
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 60, y: 60)))
        #expect(document.annotations.count == 1)
        let original = try #require(document.annotations.first)
        document.tool = .select
        let handle = CGPoint(x: original.rect.maxX + 5, y: original.rect.maxY + 5)
        canvas.mouseDown(with: try event(.leftMouseDown, handle))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: original.rect.maxX + 20, y: original.rect.maxY + 12)))
        canvas.mouseUp(with: try event(.leftMouseUp, handle))
        let resized = try #require(document.annotations.first)
        #expect(resized.number == 1)
        #expect(resized.rect.width == resized.rect.height)
        #expect(resized.rect.width == original.rect.width + 20)
        document.undo()
        #expect(document.annotations.first?.rect == original.rect)
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: original.rect.midX, y: original.rect.midY)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: original.rect.midX + 15, y: original.rect.midY + 10)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: original.rect.midX + 15, y: original.rect.midY + 10)))
        #expect(document.annotations.first?.rect == original.rect.offsetBy(dx: 15, dy: 10))
        #expect(document.annotations.first?.number == 1)
    }

    @Test func renderedBadgeUsesImageCoordinatesStaysWithinBoundsAndCopiesIdentically() throws {
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let clipboard = MarkerClipboard()
        let document = document(clipboard: clipboard)
        document.color = .black
        document.addMarker(at: CGPoint(x: 40, y: 36))
        let annotation = try #require(document.annotations.first)
        let rendered = try #require(document.renderedImage())
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        #expect(try #require(bitmap.colorAt(x: 29, y: 36)).redComponent < 0.1)
        var lightTextPixels = 0
        for y in 24..<48 {
            for x in 34..<46 where try #require(bitmap.colorAt(x: x, y: y)).redComponent > 0.9 { lightTextPixels += 1 }
        }
        #expect(lightTextPixels > 10)
        for y in 0..<120 {
            for x in 0..<160 where !annotation.rect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                #expect(try #require(bitmap.colorAt(x: x, y: y)).redComponent > 0.99)
            }
        }
        #expect(document.copy())
        let copiedPNG = try #require(clipboard.png)
        let copied = try #require(NSBitmapImageRep(data: copiedPNG))
        for y in 20..<52 {
            for x in 24..<56 {
                let expected = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let actual = try #require(copied.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                #expect(abs(expected.redComponent - actual.redComponent) < 0.001)
                #expect(abs(expected.greenComponent - actual.greenComponent) < 0.001)
                #expect(abs(expected.blueComponent - actual.blueComponent) < 0.001)
            }
        }
        document.setCrop(CGRect(x: 24, y: 20, width: 32, height: 32))
        #expect(document.renderedImage()?.width == 32)
    }

    @Test func brightBadgesUseDarkLegibleNumbers() throws {
        let marker = Annotation(tool: .marker, points: [CGPoint(x: 20, y: 20), CGPoint(x: 68, y: 68)], color: .yellow, width: 4, number: 12)
        let rendered = try #require(AnnotationRenderer.render(image: image(), annotations: [marker], crop: nil))
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        let darkPixels = (28..<60).flatMap { y in (28..<60).map { x in bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!.redComponent } }.filter { $0 < 0.2 }
        #expect(darkPixels.count > 30)
    }

    private func document(clipboard: MarkerClipboard? = nil) -> EditorDocument {
        EditorDocument(image: image(), clipboard: clipboard ?? MarkerClipboard(), annotationPreferences: AnnotationPreferences(defaults: UserDefaults(suiteName: suite)!))
    }

    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
        return context.makeImage()!
    }
}

@MainActor private final class MarkerClipboard: ImageClipboard {
    var changeCount = 0
    var png: Data?
    func clear() { changeCount += 1; png = nil }
    func writePNG(_ data: Data) -> Bool { changeCount += 1; png = data; return true }
}
