import AppKit
import CoreImage
import Testing
@testable import Snapmark

@MainActor struct BlurTests {
    private func image() -> CGImage {
        let bytes: [UInt8] = (0..<64).flatMap { y in
            (0..<80).flatMap { x -> [UInt8] in
                let level: UInt8 = (x / 2 + y / 2).isMultiple(of: 2) ? 0 : 255
                return y < 32 ? [level, level, level, 255] : [255 - level, 32, 255, 255]
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: 80, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 320, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func blur(_ rect: CGRect) -> Annotation {
        Annotation(tool: .blur, points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)], color: .red, width: 4)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return (0..<image.height).flatMap { y in
            (0..<image.width).map { x in
                UInt8((bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!.redComponent * 255).rounded())
            }
        }
    }

    private func horizontalContrast(_ pixels: [UInt8], in rect: CGRect) -> Double {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 80, height: 64))
        let differences = (Int(clipped.minY)..<Int(clipped.maxY)).flatMap { y in
            (Int(clipped.minX)..<(Int(clipped.maxX) - 1)).map { x in
                abs(Int(pixels[y * 80 + x + 1]) - Int(pixels[y * 80 + x]))
            }
        }
        return Double(differences.reduce(0, +)) / Double(differences.count)
    }

    @Test func blurSuppressesFaceScaleDetailMoreThanThePreviousStrength() throws {
        let width = 384, height = 256
        let bytes: [UInt8] = (0..<height).flatMap { y in
            (0..<width).flatMap { x -> [UInt8] in
                let detail = sin(Double(x) * .pi / 40) + cos(Double(y) * .pi / 40)
                let level = UInt8((128 + 55 * detail).rounded())
                return [level, level, level, 255]
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let original = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let source = CIImage(cgImage: original)
        let previous = try #require(CIContext().createCGImage(source.clampedToExtent().applyingGaussianBlur(sigma: 10).cropped(to: source.extent), from: source.extent))
        let region = CGRect(x: 48, y: 32, width: 288, height: 192)
        let stronger = try #require(AnnotationRenderer.render(image: original, annotations: [blur(region)], crop: nil))
        let previousRendered = try #require(AnnotationRenderer.render(image: previous, annotations: [], crop: nil))
        let oldPixels = pixels(previousRendered), newPixels = pixels(stronger)
        func deviation(_ values: [UInt8]) -> Double {
            let detail = (80..<176).flatMap { y in (128..<256).map { x in Double(values[y * width + x]) } }
            let mean = detail.reduce(0, +) / Double(detail.count)
            return sqrt(detail.map { pow($0 - mean, 2) }.reduce(0, +) / Double(detail.count))
        }
        #expect(deviation(oldPixels) > 15)
        #expect(deviation(newPixels) < deviation(oldPixels) / 3)
        let baseline = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [], crop: nil)))
        for y in 0..<height {
            for x in 0..<width where !region.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                #expect(newPixels[y * width + x] == baseline[y * width + x])
            }
        }
    }

    @Test func blurSoftensOnlyTheSelectedTopLeftPixels() throws {
        let original = image()
        let baseline = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [], crop: nil)))
        let rect = CGRect(x: 6, y: 4, width: 24, height: 18)
        let result = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [blur(rect)], crop: nil)))
        #expect(result[12 * 80 + 12] != baseline[12 * 80 + 12])
        #expect(horizontalContrast(result, in: rect) < horizontalContrast(baseline, in: rect) / 4)
        for y in 0..<64 {
            for x in 0..<80 where !rect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                #expect(result[y * 80 + x] == baseline[y * 80 + x])
            }
        }
    }

    @Test func blurKeepsAsymmetricSourceColorsInTheirOriginalRows() throws {
        let original = image()
        let baseline = NSBitmapImageRep(cgImage: try #require(AnnotationRenderer.render(image: original, annotations: [], crop: nil)))
        let result = NSBitmapImageRep(cgImage: try #require(AnnotationRenderer.render(image: original, annotations: [blur(CGRect(x: 4, y: 4, width: 24, height: 18))], crop: nil)))
        let top = try #require(result.colorAt(x: 12, y: 12)?.usingColorSpace(.sRGB))
        let source = CIImage(cgImage: original)
        let reference = try #require(CIContext().createCGImage(source.clampedToExtent().applyingGaussianBlur(sigma: 32).cropped(to: source.extent), from: source.extent))
        let renderedReference = try #require(AnnotationRenderer.render(image: reference, annotations: [], crop: nil))
        let expectedTop = try #require(NSBitmapImageRep(cgImage: renderedReference).colorAt(x: 12, y: 12)?.usingColorSpace(.sRGB))
        #expect(abs(top.redComponent - expectedTop.redComponent) < 0.02)
        #expect(abs(top.greenComponent - expectedTop.greenComponent) < 0.02)
        #expect(abs(top.blueComponent - expectedTop.blueComponent) < 0.02)
        for point in [(0, 0), (79, 0), (0, 63), (79, 63), (12, 51)] {
            let expected = try #require(baseline.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
            let actual = try #require(result.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
            #expect(actual.redComponent == expected.redComponent)
            #expect(actual.greenComponent == expected.greenComponent)
            #expect(actual.blueComponent == expected.blueComponent)
        }
    }

    @Test func blurClipsAtImageEdgesWithoutChangingOtherCorners() throws {
        let original = image()
        let baseline = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [], crop: nil)))
        let rect = CGRect(x: -8, y: -6, width: 26, height: 22)
        let result = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [blur(rect)], crop: nil)))
        #expect(result[0] != baseline[0])
        #expect(horizontalContrast(result, in: rect) < horizontalContrast(baseline, in: rect) / 4)
        for y in 0..<64 {
            for x in 0..<80 where x >= 18 || y >= 16 {
                #expect(result[y * 80 + x] == baseline[y * 80 + x])
            }
        }
    }

    @Test func vectorAnnotationsStaySharpAcrossBlurOrderAndOverlap() throws {
        let original = image()
        let overlay = Annotation(tool: .redact, points: [CGPoint(x: 8, y: 8), CGPoint(x: 24, y: 20)], color: .red, width: 4)
        let first = blur(CGRect(x: 0, y: 0, width: 30, height: 28))
        let second = blur(CGRect(x: 16, y: 12, width: 30, height: 28))
        let before = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [overlay, first, second], crop: nil)))
        let after = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [first, second, overlay], crop: nil)))
        #expect(before == after)
        for y in 8..<20 {
            for x in 8..<24 { #expect(before[y * 80 + x] == 0) }
        }
        let single = pixels(try #require(AnnotationRenderer.render(image: original, annotations: [first], crop: nil)))
        #expect(before[24 * 80 + 20] == single[24 * 80 + 20])
    }

    @Test func movingResizingDeletingAndUndoKeepBlurEditable() throws {
        let document = EditorDocument(image: image(), clipboard: BlurClipboard())
        document.add(blur(CGRect(x: 2, y: 2, width: 20, height: 16)))
        let initial = pixels(try #require(document.renderedImage()))
        document.checkpoint()
        document.annotations[0].points = [CGPoint(x: 40, y: 36), CGPoint(x: 68, y: 58)]
        document.commit()
        let moved = pixels(try #require(document.renderedImage()))
        #expect(moved != initial)
        #expect(document.annotations[0].rect == CGRect(x: 40, y: 36, width: 28, height: 22))
        document.undo()
        #expect(pixels(try #require(document.renderedImage())) == initial)
        document.redo()
        #expect(pixels(try #require(document.renderedImage())) == moved)
        document.selectedID = document.annotations[0].id
        document.deleteSelection()
        #expect(document.annotations.isEmpty)
        document.undo()
        #expect(pixels(try #require(document.renderedImage())) == moved)
    }

    @Test func cachedPreviewCopyAndCroppedExportUseTheSamePixels() throws {
        let original = image()
        let board = BlurClipboard()
        let document = EditorDocument(image: original, clipboard: board)
        let annotation = blur(CGRect(x: 4, y: 3, width: 32, height: 22))
        document.add(annotation)
        let full = try #require(document.renderedImage())
        let expected = pixels(full)
        let context = CGContext(data: nil, width: 80, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 64)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSImage(cgImage: original, size: document.imageSize).draw(in: CGRect(origin: .zero, size: document.imageSize), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        AnnotationRenderer.draw(document.annotations, image: original, blurSource: AnnotationRenderer.BlurSource(image: original))
        NSGraphicsContext.restoreGraphicsState()
        #expect(pixels(try #require(context.makeImage())) == expected)
        document.copy()
        let copiedPNG = try #require(board.png)
        let copiedImage = try #require(NSBitmapImageRep(data: copiedPNG)?.cgImage)
        #expect(pixels(copiedImage) == expected)
        let crop = CGRect(x: 8, y: 6, width: 24, height: 20)
        document.setCrop(crop)
        let exported = try #require(document.renderedImage())
        #expect(exported.width == 24 && exported.height == 20)
        #expect(pixels(exported) == pixels(try #require(full.cropping(to: crop))))
        document.copy()
        let croppedPNG = try #require(board.png)
        let croppedImage = try #require(NSBitmapImageRep(data: croppedPNG)?.cgImage)
        #expect(pixels(croppedImage) == pixels(exported))
    }
}

@MainActor private final class BlurClipboard: ImageClipboard {
    var changeCount = 0
    var png: Data?
    func clear() { changeCount += 1; png = nil }
    func writePNG(_ data: Data) -> Bool { changeCount += 1; png = data; return true }
}
