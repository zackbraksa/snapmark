import AppKit
import SwiftUI

enum SnapmarkTint {
    static let canvasGuide = NSColor(srgbRed: 1, green: 138.0 / 255, blue: 82.0 / 255, alpha: 1)
    private static let light = Color(.sRGB, red: 184.0 / 255, green: 58.0 / 255, blue: 11.0 / 255)

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(nsColor: canvasGuide) : light
    }
}

struct EditorView: View {
    static let minimumContentSize = CGSize(width: 850, height: 480)

    @Bindable var document: EditorDocument
    let onCopy: () -> Void
    @FocusState private var isNewTextFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(document: document, onSelect: selectTool)
            EditorToolOptions(document: document, isNewTextFocused: $isNewTextFocused)
            Divider()
            canvas
            Divider()
            EditorFooter(document: document, onCopy: onCopy)
        }
        .frame(minWidth: Self.minimumContentSize.width, minHeight: Self.minimumContentSize.height)
        .onChange(of: document.tool) { _, tool in
            isNewTextFocused = tool == .text
        }
    }

    private func selectTool(_ tool: AnnotationTool) {
        if document.tool != tool {
            document.tool = tool
        } else if tool == .text {
            isNewTextFocused = true
        }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 20
            let imageSize = document.imageSize
            let fit = min((geometry.size.width - inset * 2) / imageSize.width,
                          (geometry.size.height - inset * 2) / imageSize.height, 1)
            let scale = max(0.01, fit) * document.zoom

            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvas(document: document)
                    .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                    .overlay {
                        Rectangle().strokeBorder(.primary.opacity(0.12))
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
                    .padding(inset)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.primary.opacity(0.04))
        }
    }
}

private struct EditorToolbar: View {
    let document: EditorDocument
    let onSelect: (AnnotationTool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                GlassEffectContainer {
                    toolbar
                }
            } else {
                toolbar
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            controlSurface {
                HStack(spacing: 10) {
                    toolGroup([.select], label: "Selection")
                    toolGroup([.arrow, .rectangle, .ellipse, .pen], label: "Drawing")
                    toolGroup([.text, .marker, .highlight], label: "Emphasis")
                    toolGroup([.redact, .blur], label: "Obscure details")
                    toolGroup([.crop], label: "Crop")
                }
            }

            Spacer(minLength: 0)

            controlSurface {
                HStack(spacing: 1) {
                    EditorIconButton(
                        symbol: "arrow.uturn.backward", title: "Undo",
                        help: "Undo the last edit (⌘Z)", action: document.undo
                    )
                    .disabled(!document.canUndo)
                    EditorIconButton(
                        symbol: "arrow.uturn.forward", title: "Redo",
                        help: "Redo the last undone edit (⇧⌘Z)", action: document.redo
                    )
                    .disabled(!document.canRedo)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Edit history")
            }
        }
    }

    @ViewBuilder
    private func controlSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content()
                .padding(4)
                .glassEffect(.regular, in: .capsule)
        } else {
            content()
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor), in: .capsule)
                .overlay {
                    Capsule().strokeBorder(.primary.opacity(0.12))
                        .allowsHitTesting(false)
                }
        }
    }

    private func toolGroup(_ tools: [AnnotationTool], label: String) -> some View {
        HStack(spacing: 1) {
            ForEach(tools) { tool in
                EditorIconButton(
                    symbol: tool.symbol, title: tool.title,
                    help: "\(tool.title): \(tool.helpText)",
                    isSelected: document.tool == tool
                ) { onSelect(tool) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct EditorIconButton: View {
    let symbol: String
    let title: String
    let help: String
    var isSelected = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            let accent = SnapmarkTint.accent(for: colorScheme)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? accent : Color.primary.opacity(isEnabled ? 0.85 : 0.30))
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? accent.opacity(0.16) : .primary.opacity(isHovered && isEnabled ? 0.08 : 0))
                }
                .contentShape(.rect)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EditorToolOptions: View {
    @Bindable var document: EditorDocument
    let isNewTextFocused: FocusState<Bool>.Binding

    var body: some View {
        let selected = document.tool == .select ? selectedAnnotation : nil
        HStack(spacing: 12) {
            if document.tool.showsColor {
                colorPresets
            }
            if let title = document.tool.sizeTitle {
                sizePicker(title)
            }
            if document.tool == .text {
                TextField("Enter text, then click the screenshot to place it", text: $document.text)
                    .accessibilityLabel("Text to place on screenshot")
                    .focused(isNewTextFocused)
            } else if selected?.tool == .text {
                TextField("Selected annotation text", text: $document.text)
                    .onSubmit(document.updateSelectedText)
                Button("Update Selected", action: document.updateSelectedText)
                    .help("Apply the text to the selected annotation (Return)")
            } else if selected == nil, !document.tool.showsColor {
                Text(document.tool.helpText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if document.tool != .text {
                Spacer(minLength: 0)
            }
            if selected != nil {
                Button("Delete Selected", role: .destructive, action: document.deleteSelection)
                    .help("Delete the selected annotation (Delete)")
            }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .frame(height: 36)
        .padding(.horizontal, 16)
    }

    private var selectedAnnotation: Annotation? {
        guard let selectedID = document.selectedID else { return nil }
        return document.annotations.first { $0.id == selectedID }
    }

    private var colorPresets: some View {
        HStack(spacing: 6) {
            Text("Color")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                let selected = AnnotationColorPreset.nearest(to: document.color)
                ForEach(AnnotationColorPreset.allCases) { preset in
                    colorSwatch(preset, selected: preset == selected)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Color for new annotations")
        }
        .fixedSize()
    }

    private func colorSwatch(_ preset: AnnotationColorPreset, selected: Bool) -> some View {
        Button {
            document.color = preset.color
        } label: {
            Circle().fill(Color(nsColor: preset.color))
                .overlay { Circle().strokeBorder(.primary.opacity(0.24)) }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(nsColor: preset.checkmarkColor))
                    }
                }
                .frame(width: 16, height: 16)
                .frame(width: 23, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(preset.title)
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sizePicker(_ title: String) -> some View {
        let tool = document.tool
        return Picker(title, selection: Binding(
            get: { tool.nearestSize(to: document.strokeWidth) },
            set: { document.strokeWidth = tool.width(for: $0) }
        )) {
            ForEach(AnnotationSizePreset.allCases) { size in
                Text(size.title).tag(size)
            }
        }
        .fixedSize()
        .help("\(title) for new \(tool.title.lowercased()) annotations")
    }
}

private struct EditorFooter: View {
    let document: EditorDocument
    let onCopy: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("\(document.image.width) × \(document.image.height) px")
                    .monospacedDigit()
                    .fixedSize()

                if !document.status.isEmpty {
                    Text(document.status)
                        .lineLimit(1)
                        .help(document.status)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                zoomControls
                Button("Save PNG…", action: document.exportPNG)
                    .help("Save the annotated image as a PNG file")
                Button(action: onCopy) {
                    Text("Copy & Close")
                        .foregroundStyle(appearsActive ? copyAccentForeground : Color.primary)
                }
                .buttonStyle(.borderedProminent)
                .tint(SnapmarkTint.accent(for: colorScheme))
                .help("Copy the annotated image, close the editor, and return to your previous app")
                .accessibilityHint("Returns to your previous app after a successful copy")
            }
            .fixedSize()
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }

    private var copyAccentForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { document.zoom = max(0.5, document.zoom - 0.25) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(document.zoom <= 0.5)
            .help("Zoom out")
            .accessibilityLabel("Zoom out")

            Button { document.zoom = 1 } label: {
                Text(document.zoom == 1 ? "Fit" : "\(Double(document.zoom).formatted(.number.precision(.fractionLength(0...2))))× Fit")
                    .monospacedDigit()
                    .frame(width: 54)
            }
            .help("Reset to fit. Zoom is relative to the fitted view.")
            .accessibilityLabel("Reset zoom to fit")
            .accessibilityValue("\(Int(document.zoom * 100)) percent of fitted view")

            Button { document.zoom = min(4, document.zoom + 0.25) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(document.zoom >= 4)
            .help("Zoom in")
            .accessibilityLabel("Zoom in")
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zoom")
    }
}
