import AppKit

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, rectangle, ellipse, pen, text, marker, highlight, redact, blur, crop
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var helpText: String {
        switch self {
        case .select: "Click an annotation to select it, then drag to move or resize it."
        case .arrow: "Drag from the arrow’s tail to its tip."
        case .rectangle: "Drag to draw a rectangular outline."
        case .ellipse: "Drag to draw an oval outline."
        case .pen: "Drag to draw a freehand line."
        case .text: "Enter text above, then click the screenshot to place it."
        case .marker: "Click to place the next numbered marker. Select to move or resize it."
        case .highlight: "Drag to add a translucent highlight."
        case .redact: "Drag to cover an area with solid black."
        case .blur: "Drag over an area to strongly blur its details."
        case .crop: "Drag to choose the area to keep in copied and saved images."
        }
    }
    var showsColor: Bool {
        switch self {
        case .arrow, .rectangle, .ellipse, .pen, .text, .marker, .highlight: true
        case .select, .redact, .blur, .crop: false
        }
    }
    var sizeTitle: String? {
        switch self {
        case .arrow, .rectangle, .ellipse, .pen: "Stroke"
        case .text: "Font size"
        case .marker: "Badge size"
        case .select, .highlight, .redact, .blur, .crop: nil
        }
    }
    var sizeChoices: [CGFloat] { AnnotationSizePreset.allCases.map { width(for: $0) } }
    func width(for size: AnnotationSizePreset) -> CGFloat {
        switch (self, size) {
        case (.text, .small): 3.6
        case (.text, .medium): 4.8
        case (.text, .big): 7.2
        case (.marker, .small): 4
        case (.marker, .medium): 6
        case (.marker, .big): 8
        case (_, .small): 2
        case (_, .medium): 4
        case (_, .big): 8
        }
    }
    func nearestSize(to width: CGFloat) -> AnnotationSizePreset {
        AnnotationSizePreset.allCases.min {
            abs(sizeInPixels(for: self.width(for: $0)) - sizeInPixels(for: width))
                < abs(sizeInPixels(for: self.width(for: $1)) - sizeInPixels(for: width))
        } ?? .medium
    }
    var legacySizeChoices: [CGFloat] {
        switch self {
        case .text: [2, 4, 4.8, 6.4, 7.2, 8]
        case .marker: [2, 4, 6, 8]
        default: [2, 4, 8]
        }
    }
    func sizeInPixels(for width: CGFloat) -> Int {
        switch self {
        case .text: Int(max(18, width * 5).rounded())
        case .marker: Int(max(28, width * 8).rounded())
        default: Int(width.rounded())
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .marker: "1.circle.fill"
        case .highlight: "highlighter"
        case .redact: "rectangle.fill"
        case .blur: "drop.halffull"
        case .crop: "crop"
        }
    }
}

struct Annotation: Identifiable {
    let id: UUID
    var tool: AnnotationTool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text: String
    var number: Int?
    init(tool: AnnotationTool, points: [CGPoint], color: NSColor, width: CGFloat, text: String = "", number: Int? = nil) {
        id = UUID(); self.tool = tool; self.points = points; self.color = color; self.width = width; self.text = text; self.number = number
    }
    var rect: CGRect {
        guard let first = points.first else { return .zero }
        let xs = points.map(\.x), ys = points.map(\.y)
        if tool == .text {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: max(18, width * 5), weight: .semibold)])
            return CGRect(origin: first, size: size)
        }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
