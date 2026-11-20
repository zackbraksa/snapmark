import AppKit

@MainActor final class AnnotationPreferences {
    enum Key {
        static let tool = "annotationTool"
        static let color = "annotationColorRGBA"
        static let strokeWidth = "annotationStrokeWidth"
        static let toolSettings = "annotationToolSettings.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var tool: AnnotationTool {
        get { defaults.string(forKey: Key.tool).flatMap(AnnotationTool.init(rawValue:)) ?? .arrow }
        set { defaults.set(newValue.rawValue, forKey: Key.tool) }
    }

    var color: NSColor {
        get { color(for: tool) }
        set { setColor(newValue, for: tool) }
    }

    var strokeWidth: CGFloat {
        get { strokeWidth(for: tool) }
        set { setStrokeWidth(newValue, for: tool) }
    }

    func color(for tool: AnnotationTool) -> NSColor {
        let stored = settings(for: tool)["color"] ?? defaults.object(forKey: Key.color)
        guard let components = stored as? [Double], components.count == 4,
              components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return AnnotationColorPreset.red.color }
        return AnnotationColorPreset.nearest(to: NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])).color
    }

    func setColor(_ value: NSColor, for tool: AnnotationTool) {
        let color = AnnotationColorPreset.nearest(to: value).color
        update(tool, key: "color", value: [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent])
    }

    func strokeWidth(for tool: AnnotationTool) -> CGFloat {
        let stored = settings(for: tool)["size"] ?? defaults.object(forKey: Key.strokeWidth)
        guard let width = stored as? Double, width.isFinite,
              (tool.legacySizeChoices + tool.sizeChoices).contains(CGFloat(width)) else { return tool.width(for: .medium) }
        return tool.width(for: tool.nearestSize(to: CGFloat(width)))
    }

    func setStrokeWidth(_ value: CGFloat, for tool: AnnotationTool) {
        update(tool, key: "size", value: Double(tool.width(for: tool.nearestSize(to: value))))
    }

    private func settings(for tool: AnnotationTool) -> [String: Any] {
        defaults.dictionary(forKey: Key.toolSettings)?[tool.rawValue] as? [String: Any] ?? [:]
    }

    private func update(_ tool: AnnotationTool, key: String, value: Any) {
        var allSettings = defaults.dictionary(forKey: Key.toolSettings) ?? [:]
        var toolSettings = settings(for: tool)
        toolSettings[key] = value
        allSettings[tool.rawValue] = toolSettings
        defaults.set(allSettings, forKey: Key.toolSettings)
    }
}
