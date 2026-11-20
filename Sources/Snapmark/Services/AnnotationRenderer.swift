import AppKit
import CoreImage

@MainActor enum AnnotationRenderer {
    final class BlurSource {
        let image: CGImage
        private static let context = CIContext()
        private static let softwareContext = CIContext(options: [.useSoftwareRenderer: true])
        private let renderBlur: (CIImage, CGRect) -> CGImage?
        private lazy var blurredImage: NSImage? = {
            let source = CIImage(cgImage: image)
            let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: 32).cropped(to: source.extent)
            guard let result = renderBlur(blurred, source.extent) else { return nil }
            return NSImage(cgImage: result, size: CGSize(width: image.width, height: image.height))
        }()

        init(image: CGImage, renderBlur: ((CIImage, CGRect) -> CGImage?)? = nil) {
            self.image = image
            self.renderBlur = renderBlur ?? { image, extent in
                Self.context.createCGImage(image, from: extent) ?? Self.softwareContext.createCGImage(image, from: extent)
            }
        }

        func draw(in rect: CGRect) -> Bool {
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let clipped = rect.integral.intersection(bounds)
            guard !clipped.isEmpty else { return true }
            guard let blurredImage else {
                NSColor.black.setFill(); clipped.fill()
                return false
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: clipped).addClip()
            blurredImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    @discardableResult static func draw(_ annotations: [Annotation], image: CGImage, blurSource: BlurSource? = nil) -> Bool {
        let source = blurSource ?? BlurSource(image: image)
        var succeeded = true
        for annotation in annotations where annotation.tool == .blur {
            if !source.draw(in: annotation.rect) { succeeded = false }
        }
        for annotation in annotations where annotation.tool != .blur { draw(annotation) }
        return succeeded
    }

    private static func draw(_ item: Annotation) {
        guard let start = item.points.first else { return }
        let end = item.points.last ?? start
        item.color.setStroke(); item.color.setFill()
        let path = NSBezierPath(); path.lineWidth = item.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        switch item.tool {
        case .arrow:
            path.move(to: start); path.line(to: end); path.stroke()
            let angle = atan2(end.y - start.y, end.x - start.x), length = max(14, item.width * 4)
            path.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
            path.line(to: end)
            path.line(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
            path.stroke()
        case .rectangle: NSBezierPath(rect: item.rect).styledStroke(item.width)
        case .ellipse: NSBezierPath(ovalIn: item.rect).styledStroke(item.width)
        case .pen:
            path.move(to: start); for point in item.points.dropFirst() { path.line(to: point) }; path.stroke()
        case .highlight:
            item.color.withAlphaComponent(0.3).setFill(); item.rect.fill(using: .sourceOver)
        case .redact:
            NSColor.black.setFill(); item.rect.integral.fill()
        case .text:
            (item.text as NSString).draw(at: start, withAttributes: [.font: NSFont.systemFont(ofSize: max(18, item.width * 5), weight: .semibold), .foregroundColor: item.color])
        case .marker:
            NSBezierPath(ovalIn: item.rect).fill()
            let label = String(item.number ?? 1) as NSString
            let diameter = min(item.rect.width, item.rect.height)
            let font = NSFont.systemFont(ofSize: diameter * 0.58, weight: .bold)
            let naturalSize = label.size(withAttributes: [.font: font])
            let fittedFont = NSFont.systemFont(ofSize: font.pointSize * min(1, diameter * 0.75 / max(1, naturalSize.width)), weight: .bold)
            let size = label.size(withAttributes: [.font: fittedFont])
            let color = item.color.usingColorSpace(.sRGB) ?? .black
            func linear(_ component: CGFloat) -> CGFloat { component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4) }
            let luminance = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
            let ink = luminance > 0.179 ? NSColor.black : NSColor.white
            label.draw(at: CGPoint(x: item.rect.midX - size.width / 2, y: item.rect.midY - size.height / 2), withAttributes: [.font: fittedFont, .foregroundColor: ink])
        case .select, .crop, .blur: break
        }
    }
    static func render(image: CGImage, annotations: [Annotation], crop: CGRect?) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSImage(cgImage: image, size: size).draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let rendered = draw(annotations, image: image)
        NSGraphicsContext.restoreGraphicsState()
        guard rendered, let result = context.makeImage() else { return nil }
        return crop.map { result.cropping(to: $0.integral) } ?? result
    }
}
private extension NSBezierPath {
    func styledStroke(_ width: CGFloat) { lineWidth = width; stroke() }
}
