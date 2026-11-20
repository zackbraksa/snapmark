import AppKit

enum AnnotationSizePreset: String, CaseIterable, Identifiable {
    case small, medium, big
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AnnotationColorPreset: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, black, white
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: NSColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .red: rgb = (1, 0.27, 0.23)
        case .orange: rgb = (1, 0.58, 0)
        case .yellow: rgb = (1, 0.84, 0.04)
        case .green: rgb = (0.19, 0.82, 0.35)
        case .blue: rgb = (0.04, 0.52, 1)
        case .purple: rgb = (0.75, 0.35, 0.95)
        case .black: rgb = (0, 0, 0)
        case .white: rgb = (1, 1, 1)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
    var checkmarkColor: NSColor { self == .black ? .white : .black }

    static func nearest(to value: NSColor) -> Self {
        guard let value = value.usingColorSpace(.sRGB) else { return .red }
        return allCases.min { first, second in
            func distance(_ preset: Self) -> CGFloat {
                let color = preset.color
                return pow(color.redComponent - value.redComponent, 2)
                    + pow(color.greenComponent - value.greenComponent, 2)
                    + pow(color.blueComponent - value.blueComponent, 2)
            }
            return distance(first) < distance(second)
        } ?? .red
    }
}
