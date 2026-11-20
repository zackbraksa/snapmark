import AppKit
import Testing
@testable import Snapmark

@MainActor struct AnnotationPreferencesTests {
    @Test func choicesRoundTripAcrossDocumentsWithoutPersistingCaptureContents() throws {
        let suite = "Snapmark.AnnotationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AnnotationPreferences(defaults: defaults)
        let first = EditorDocument(image: image(), clipboard: PreferencesClipboard(), annotationPreferences: preferences)
        first.tool = .marker
        first.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.7, alpha: 1)
        first.strokeWidth = 8
        first.text = "Private screenshot note"
        first.addMarker(at: CGPoint(x: 30, y: 30))

        let second = EditorDocument(image: image(), clipboard: PreferencesClipboard(), annotationPreferences: AnnotationPreferences(defaults: defaults))
        #expect(second.tool == .marker)
        #expect(second.strokeWidth == 8)
        let color = try #require(second.color.usingColorSpace(.sRGB))
        let expectedColor = AnnotationColorPreset.blue.color
        #expect(abs(color.redComponent - expectedColor.redComponent) < 0.001)
        #expect(abs(color.greenComponent - expectedColor.greenComponent) < 0.001)
        #expect(abs(color.blueComponent - expectedColor.blueComponent) < 0.001)
        #expect(second.text.isEmpty && second.annotations.isEmpty)
        #expect(Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? []) == Set([AnnotationPreferences.Key.tool, AnnotationPreferences.Key.toolSettings]))
        #expect(defaults.string(forKey: AnnotationPreferences.Key.tool) == "marker")
    }

    @Test func allToolsAndSupportedWidthsRoundTrip() throws {
        let suite = "Snapmark.AnnotationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AnnotationPreferences(defaults: defaults)
        for tool in AnnotationTool.allCases {
            preferences.tool = tool
            #expect(AnnotationPreferences(defaults: defaults).tool == tool)
        }
        for tool in AnnotationTool.allCases {
            preferences.tool = tool
            for width in tool.sizeChoices {
                preferences.strokeWidth = width
                #expect(AnnotationPreferences(defaults: defaults).strokeWidth == width)
            }
        }
    }

    @Test func invalidPersistedChoicesFallBackWithoutBeingRewrittenOnDocumentCreation() throws {
        let suite = "Snapmark.AnnotationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown-tool", forKey: AnnotationPreferences.Key.tool)
        defaults.set(99, forKey: AnnotationPreferences.Key.strokeWidth)
        defaults.set([0.2, 0.4, 2.0, 1.0], forKey: AnnotationPreferences.Key.color)
        let document = EditorDocument(image: image(), clipboard: PreferencesClipboard(), annotationPreferences: AnnotationPreferences(defaults: defaults))
        #expect(document.tool == .arrow)
        #expect(document.strokeWidth == 4)
        #expect(document.color == AnnotationColorPreset.red.color)
        #expect(defaults.string(forKey: AnnotationPreferences.Key.tool) == "unknown-tool")
        #expect(defaults.integer(forKey: AnnotationPreferences.Key.strokeWidth) == 99)

        let preferences = AnnotationPreferences(defaults: defaults)
        for invalid: Any in [[0.2, 0.4, 0.6], [Double.nan, 0.4, 0.6, 1], [0.2, -0.4, 0.6, 1], "red"] {
            defaults.set(invalid, forKey: AnnotationPreferences.Key.color)
            #expect(preferences.color == AnnotationColorPreset.red.color)
        }
        for invalid in [Double.infinity, Double.nan, 0, -2, 3] {
            defaults.set(invalid, forKey: AnnotationPreferences.Key.strokeWidth)
            #expect(preferences.strokeWidth == 4)
        }
    }

    @Test func eachToolKeepsItsOwnColorAndSizeAcrossSwitchesAndRelaunch() throws {
        let suite = "Snapmark.AnnotationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let document = EditorDocument(image: image(), clipboard: PreferencesClipboard(), annotationPreferences: AnnotationPreferences(defaults: defaults))
        document.tool = .arrow
        document.color = .blue
        document.strokeWidth = 8
        document.tool = .text
        #expect(document.strokeWidth == 4.8)
        document.color = .green
        document.strokeWidth = 4.8
        document.tool = .marker
        #expect(document.strokeWidth == 6)
        document.strokeWidth = 6
        document.tool = .arrow
        #expect(document.strokeWidth == 8)
        #expect(try #require(document.color.usingColorSpace(.sRGB)).blueComponent > 0.99)
        document.tool = .text
        #expect(document.strokeWidth == 4.8)
        #expect(AnnotationTool.text.sizeInPixels(for: document.strokeWidth) == 24)
        #expect(try #require(document.color.usingColorSpace(.sRGB)).greenComponent == AnnotationColorPreset.green.color.greenComponent)
        let restored = EditorDocument(image: image(), clipboard: PreferencesClipboard(), annotationPreferences: AnnotationPreferences(defaults: defaults))
        #expect(restored.tool == .text && restored.strokeWidth == 4.8)
        restored.tool = .marker
        #expect(AnnotationTool.marker.sizeInPixels(for: restored.strokeWidth) == 48)
        restored.tool = .pen
        #expect(restored.strokeWidth == 4)
    }

    @Test func existingGlobalPreferencesSeedEachToolWithoutBeingOverwritten() throws {
        let suite = "Snapmark.AnnotationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(8.0, forKey: AnnotationPreferences.Key.strokeWidth)
        defaults.set([0.2, 0.3, 0.4, 1.0], forKey: AnnotationPreferences.Key.color)
        let preferences = AnnotationPreferences(defaults: defaults)
        #expect(preferences.strokeWidth(for: .arrow) == 8)
        #expect(preferences.strokeWidth(for: .text) == 7.2)
        preferences.setStrokeWidth(2, for: .arrow)
        #expect(preferences.strokeWidth(for: .arrow) == 2)
        #expect(preferences.strokeWidth(for: .text) == 7.2)
        #expect(defaults.double(forKey: AnnotationPreferences.Key.strokeWidth) == 8)
        defaults.set(["text": ["size": 999.0, "color": [-1.0, 0.0, 0.0, 1.0]]], forKey: AnnotationPreferences.Key.toolSettings)
        #expect(preferences.strokeWidth(for: .text) == 4.8)
        #expect(preferences.color(for: .text) == AnnotationColorPreset.red.color)
    }

    @Test func toolControlsHaveRelevantLabelsAndSizes() {
        #expect(AnnotationTool.arrow.sizeTitle == "Stroke")
        #expect(AnnotationTool.text.sizeTitle == "Font size")
        #expect(AnnotationTool.marker.sizeTitle == "Badge size")
        for tool in [AnnotationTool.select, .blur, .crop, .redact] {
            #expect(!tool.showsColor)
            #expect(tool.sizeTitle == nil)
        }
        #expect(AnnotationTool.highlight.showsColor && AnnotationTool.highlight.sizeTitle == nil)
    }

    @Test func legacyCustomColorsAndSizesBecomeMatchingPresetsWithoutChangingOtherTools() throws {
        let suite = "Snapmark.AnnotationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([
            "text": ["size": 6.4, "color": [0.2, 0.4, 0.7, 1]],
            "marker": ["size": 2.0, "color": [1.0, 0.98, 0.97, 1]]
        ], forKey: AnnotationPreferences.Key.toolSettings)
        let preferences = AnnotationPreferences(defaults: defaults)
        #expect(preferences.strokeWidth(for: .text) == AnnotationTool.text.width(for: .big))
        #expect(preferences.strokeWidth(for: .marker) == AnnotationTool.marker.width(for: .small))
        #expect(preferences.color(for: .text) == AnnotationColorPreset.blue.color)
        #expect(preferences.color(for: .marker) == AnnotationColorPreset.white.color)
        preferences.setColor(AnnotationColorPreset.red.color, for: .text)
        preferences.setStrokeWidth(AnnotationTool.text.width(for: .medium), for: .text)
        #expect(preferences.color(for: .marker) == AnnotationColorPreset.white.color)
        #expect(preferences.strokeWidth(for: .marker) == AnnotationTool.marker.width(for: .small))
        for preset in AnnotationColorPreset.allCases {
            preferences.setColor(preset.color, for: .arrow)
            #expect(preferences.color(for: .arrow) == preset.color)
        }
    }

    private func image() -> CGImage {
        CGContext(data: nil, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}

@MainActor private final class PreferencesClipboard: ImageClipboard {
    var changeCount = 0
    func clear() { changeCount += 1 }
    func writePNG(_ data: Data) -> Bool { changeCount += 1; return true }
}
