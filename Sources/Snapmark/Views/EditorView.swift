import SwiftUI

struct EditorView: View {
    @Bindable var document: EditorDocument
    let onCopy: () -> Void
    @State private var hoveredTool: AnnotationTool?

    var body: some View {
        VStack(spacing: 0) {
            annotationToolbar
            toolOptions
            if document.tool == .text || isEditingSelectedText {
                textControls
            }
            Divider()
            canvas
            Divider()
            footer
        }
        .frame(minWidth: 850, minHeight: 480)
    }

    private var annotationToolbar: some View {
        HStack(spacing: 10) {
            toolGroup([.select], label: "Selection")
            toolbarDivider
            toolGroup([.arrow, .rectangle, .ellipse, .pen], label: "Drawing")
            toolbarDivider
            toolGroup([.text, .marker, .highlight], label: "Emphasis")
            toolbarDivider
            toolGroup([.redact, .blur], label: "Obscure details")
            toolbarDivider
            toolGroup([.crop], label: "Crop")
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!document.canUndo)
                    .help("Undo the last edit (⌘Z)")
                    .accessibilityLabel("Undo")
                Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!document.canRedo)
                    .help("Redo the last undone edit (⇧⌘Z)")
                    .accessibilityLabel("Redo")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var toolOptions: some View {
        HStack(spacing: 12) {
            Text(document.tool.title)
                .font(.headline)
                .frame(width: 76, alignment: .leading)
            if document.tool.showsColor {
                colorPresets
            }
            if let title = document.tool.sizeTitle {
                Picker(title, selection: Binding(
                    get: { document.tool.nearestSize(to: document.strokeWidth) },
                    set: { document.strokeWidth = document.tool.width(for: $0) }
                )) {
                    ForEach(AnnotationSizePreset.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .frame(width: 155)
                .help("\(title) for new \(document.tool.title.lowercased()) annotations")
            }
            if document.tool.showsColor {
                Text("New annotations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("These settings apply to annotations you add next. Each tool remembers its own settings.")
            }
            Spacer(minLength: 0)
            if document.tool == .select, document.selectedID != nil {
                Button("Delete Selected", role: .destructive) { document.deleteSelection() }
                    .help("Delete the selected annotation (Delete)")
            }
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var colorPresets: some View {
        HStack(spacing: 8) {
            Text("Color")
            HStack(spacing: 4) {
                ForEach(AnnotationColorPreset.allCases) { preset in
                    colorSwatch(preset)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Color presets")
        }
        .fixedSize()
    }

    private func colorSwatch(_ preset: AnnotationColorPreset) -> some View {
        let selected = AnnotationColorPreset.nearest(to: document.color) == preset
        return Button { document.color = preset.color } label: {
            Circle().fill(Color(nsColor: preset.color))
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(nsColor: preset.checkmarkColor))
                    }
                }
                .frame(width: 18, height: 18)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .help(preset.title)
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var textControls: some View {
        HStack(spacing: 10) {
            Text(isEditingSelectedText ? "Edit text" : "Text")
                .frame(width: 76, alignment: .leading)
            TextField("Enter text, then click the screenshot to place it", text: $document.text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(isEditingSelectedText ? "Selected annotation text" : "Text to place on screenshot")
                .onSubmit {
                    if isEditingSelectedText { document.updateSelectedText() }
                }
            if isEditingSelectedText {
                Button("Update Selected") { document.updateSelectedText() }
                    .help("Apply the text to the selected annotation (Return)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let fit = min((geometry.size.width - 40) / document.imageSize.width, (geometry.size.height - 40) / document.imageSize.height, 1)
            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvas(document: document)
                    .frame(width: document.imageSize.width * max(0.01, fit) * document.zoom, height: document.imageSize.height * max(0.01, fit) * document.zoom)
                    .overlay {
                        Rectangle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(20)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.035))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(footerHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(footerHelp)
                Text(document.status.isEmpty ? "\(document.image.width) × \(document.image.height) px" : document.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(document.status)
            }
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            zoomControls
            Button("Save PNG…") { document.exportPNG() }
                .help("Save the annotated image as a PNG file")
            Button("Copy & Close", action: onCopy)
                .buttonStyle(.borderedProminent)
                .help("Copy the annotated image, close the editor, and return to your previous app")
                .accessibilityHint("Returns to your previous app after a successful copy")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                    .frame(width: 64)
            }
            .help("Reset to fit. Zoom is relative to the fitted view and does not change exported resolution.")
            .accessibilityLabel("Reset zoom to fit")
            .accessibilityValue("\(Int(document.zoom * 100)) percent of fitted view")
            Button { document.zoom = min(4, document.zoom + 0.25) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(document.zoom >= 4)
            .help("Zoom in")
            .accessibilityLabel("Zoom in")
        }
    }

    private var isEditingSelectedText: Bool {
        document.tool == .select && document.annotations.contains { $0.id == document.selectedID && $0.tool == .text }
    }

    private var footerHelp: String {
        if let hoveredTool { return "\(hoveredTool.title): \(hoveredTool.helpText)" }
        if isEditingSelectedText { return "Edit the text above and choose Update Selected. Drag the annotation to move it." }
        return document.tool.helpText
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 22)
    }

    private func toolGroup(_ tools: [AnnotationTool], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(tools) { tool in toolButton(tool) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button { document.tool = tool } label: {
            Image(systemName: tool.symbol)
                .frame(width: 27, height: 26)
                .foregroundStyle(document.tool == tool ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.bordered)
        .tint(document.tool == tool ? Color.accentColor : nil)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(document.tool == tool ? Color.accentColor : Color.clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .help("\(tool.title): \(tool.helpText)")
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.helpText)
        .accessibilityAddTraits(document.tool == tool ? .isSelected : [])
        .onHover { hovering in
            if hovering { hoveredTool = tool }
            else if hoveredTool == tool { hoveredTool = nil }
        }
    }
}
