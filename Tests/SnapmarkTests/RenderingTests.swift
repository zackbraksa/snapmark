import AppKit
import Testing
@testable import Snapmark

@MainActor struct RenderingTests {
    private func image() -> CGImage {
        let bytes: [UInt8] = (0..<64).flatMap { y in
            (0..<80).flatMap { x -> [UInt8] in
                [UInt8(x * 3), UInt8(y * 4), y < 32 ? 64 : 224, 255]
            }
        }
        return CGImage(width: 80, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 320,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func color(_ image: CGImage, x: Int, y: Int) throws -> NSColor {
        try #require(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }

    private func preview(_ document: EditorDocument, scale: CGFloat, blurSource: AnnotationRenderer.BlurSource? = nil) throws -> CGImage {
        let width = Int(document.imageSize.width * scale), height = Int(document.imageSize.height * scale)
        let canvas = CanvasView(document: document, blurSource: blurSource)
        canvas.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return try #require(context.makeImage())
    }

    @Test func fractionalRedactionCoversEveryIntersectedPixelWithOpaqueBlack() throws {
        let source = image()
        let rect = CGRect(x: 6.7, y: 4.6, width: 17.6, height: 12.8)
        let annotation = Annotation(tool: .redact, points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)], color: .red, width: 4)
        let full = try #require(AnnotationRenderer.render(image: source, annotations: [annotation], crop: nil))
        let crop = CGRect(x: 3, y: 2, width: 30, height: 26)
        let cropped = try #require(AnnotationRenderer.render(image: source, annotations: [annotation], crop: crop))
        let data = try #require(NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]))
        let decoded = try #require(NSBitmapImageRep(data: data)?.cgImage)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let actual = try color(full, x: x, y: y)
                if rect.integral.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                    #expect(actual.redComponent == 0 && actual.greenComponent == 0 && actual.blueComponent == 0)
                    #expect(actual.alphaComponent == 1)
                    let saved = try color(decoded, x: x - Int(crop.minX), y: y - Int(crop.minY))
                    #expect(saved.redComponent == 0 && saved.greenComponent == 0 && saved.blueComponent == 0 && saved.alphaComponent == 1)
                } else {
                    let expected = try color(source, x: x, y: y)
                    #expect(abs(actual.redComponent - expected.redComponent) < 0.01)
                    #expect(abs(actual.greenComponent - expected.greenComponent) < 0.01)
                    #expect(abs(actual.blueComponent - expected.blueComponent) < 0.01)
                }
            }
        }
    }

    @Test func actualCanvasMatchesExportAtImageScaleAndKeepsGeometryAtOtherZooms() throws {
        let source = image()
        let document = EditorDocument(image: source, clipboard: RenderingClipboard())
        document.annotations = [
            Annotation(tool: .blur, points: [CGPoint(x: 4, y: 4), CGPoint(x: 32, y: 24)], color: .red, width: 4),
            Annotation(tool: .redact, points: [CGPoint(x: 44.4, y: 8.3), CGPoint(x: 62.7, y: 22.8)], color: .red, width: 4),
            Annotation(tool: .highlight, points: [CGPoint(x: 8, y: 40), CGPoint(x: 28, y: 56)], color: .yellow, width: 4)
        ]
        let full = try #require(document.renderedImage())
        let canvas = try preview(document, scale: 1)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let actual = try color(canvas, x: x, y: y), expected = try color(full, x: x, y: y)
                #expect(actual == expected)
            }
        }
        for scale: CGFloat in [0.5, 2] {
            let canvas = try preview(document, scale: scale)
            for point in [(16, 12), (52, 14), (16, 48), (68, 48)] {
                let actual = try color(canvas, x: Int(CGFloat(point.0) * scale), y: Int(CGFloat(point.1) * scale))
                let expected = try color(full, x: point.0, y: point.1)
                #expect(abs(actual.redComponent - expected.redComponent) < 0.03)
                #expect(abs(actual.greenComponent - expected.greenComponent) < 0.03)
                #expect(abs(actual.blueComponent - expected.blueComponent) < 0.03)
            }
        }
    }

    @Test func failedBlurPreviewCoversEveryAffectedRegionWithoutChangingDocumentState() throws {
        let source = image()
        let document = EditorDocument(image: source, clipboard: RenderingClipboard())
        document.annotations = [
            Annotation(tool: .blur, points: [CGPoint(x: 4.2, y: 4.4), CGPoint(x: 22.8, y: 20.6)], color: .red, width: 4),
            Annotation(tool: .blur, points: [CGPoint(x: 40, y: 36), CGPoint(x: 68, y: 58)], color: .red, width: 4)
        ]
        let unavailable = AnnotationRenderer.BlurSource(image: source, renderBlur: { _, _ in nil })
        let canvas = try preview(document, scale: 1, blurSource: unavailable)
        for annotation in document.annotations {
            let rect = annotation.rect.integral
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let actual = try color(canvas, x: x, y: y)
                    #expect(actual.redComponent == 0 && actual.greenComponent == 0 && actual.blueComponent == 0 && actual.alphaComponent == 1)
                }
            }
        }
        #expect(document.status.isEmpty)
        let outside = try color(canvas, x: 72, y: 30), expected = try color(source, x: 72, y: 30)
        #expect(outside == expected)
    }
}

@MainActor private final class RenderingClipboard: ImageClipboard {
    var changeCount = 0
    func clear() { changeCount += 1 }
    func writePNG(_ data: Data) -> Bool { changeCount += 1; return true }
}
