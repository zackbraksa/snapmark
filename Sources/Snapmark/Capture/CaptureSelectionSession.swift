import AppKit
import ScreenCaptureKit

struct DisplaySnapshot {
    let screen: NSScreen
    let image: CGImage
}

enum CaptureSelection {
    case area(DisplaySnapshot, CGRect)
    case window(SCWindow)
}

@MainActor
final class CaptureSelectionSession {
    private let snapshots: [DisplaySnapshot]
    private let windows: [SCWindow]
    private let primaryScreenTop: CGFloat
    private var windowMode: Bool
    private var overlays: [CaptureOverlayWindow] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<CaptureSelection?, Never>?

    init(snapshots: [DisplaySnapshot], windows: [SCWindow], primaryScreenTop: CGFloat, mode: CaptureMode) {
        self.snapshots = snapshots
        self.windows = windows
        self.primaryScreenTop = primaryScreenTop
        windowMode = mode == .window
    }

    func select() async -> CaptureSelection? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { finish(nil); return }
                present()
            }
        } onCancel: {
            Task { @MainActor in self.finish(nil) }
        }
    }

    private func present() {
        for snapshot in snapshots {
            let overlay = CaptureOverlayWindow(contentRect: snapshot.screen.frame, styleMask: .borderless,
                                               backing: .buffered, defer: false)
            overlay.level = .screenSaver
            overlay.backgroundColor = .black
            overlay.isOpaque = true
            overlay.hasShadow = false
            overlay.isReleasedWhenClosed = false
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            overlay.acceptsMouseMovedEvents = true
            let view = CaptureSelectionView(snapshot: snapshot)
            view.windowMode = windowMode
            view.onHover = { [weak self] in self?.updateHoveredWindow() }
            view.onArea = { [weak self] rect in self?.finish(.area(snapshot, rect)) }
            view.onWindow = { [weak self] in
                guard let self, let window = self.windowUnderPointer() else { return }
                self.finish(.window(window))
            }
            overlay.contentView = view
            overlays.append(overlay)
            overlay.orderFrontRegardless()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.finish(nil); return nil }
            if event.keyCode == 49 {
                self.windowMode.toggle()
                for overlay in self.overlays {
                    (overlay.contentView as? CaptureSelectionView)?.setWindowMode(self.windowMode)
                }
                self.updateHoveredWindow()
                return nil
            }
            return event
        }
        NSApp.activate(ignoringOtherApps: true)
        (overlays.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? overlays.first)?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
        updateHoveredWindow()
    }

    private func windowUnderPointer() -> SCWindow? {
        let pointer = NSEvent.mouseLocation
        return windows.first {
            CaptureGeometry.appKitRect(from: $0.frame, primaryScreenTop: primaryScreenTop).contains(pointer)
        }
    }

    private func updateHoveredWindow() {
        let selected = windowMode ? windowUnderPointer() : nil
        for overlay in overlays {
            let view = overlay.contentView as? CaptureSelectionView
            view?.highlight = selected.map {
                CaptureGeometry.appKitRect(from: $0.frame, primaryScreenTop: primaryScreenTop)
                    .offsetBy(dx: -overlay.frame.minX, dy: -overlay.frame.minY)
                    .intersection(CGRect(origin: .zero, size: overlay.frame.size))
            }
            view?.needsDisplay = true
        }
    }

    private func finish(_ selection: CaptureSelection?) {
        guard let continuation else { return }
        self.continuation = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        for overlay in overlays { overlay.orderOut(nil); overlay.close() }
        overlays.removeAll()
        NSCursor.arrow.set()
        continuation.resume(returning: selection)
    }
}

private final class CaptureOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CaptureSelectionView: NSView {
    private let snapshot: DisplaySnapshot
    private let frozenImage: NSImage
    private var start: CGPoint?
    private var selection: CGRect?
    var highlight: CGRect?
    var windowMode = false
    var onHover: (() -> Void)?
    var onArea: ((CGRect) -> Void)?
    var onWindow: (() -> Void)?

    init(snapshot: DisplaySnapshot) {
        self.snapshot = snapshot
        frozenImage = NSImage(cgImage: snapshot.image, size: snapshot.screen.frame.size)
        super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: windowMode ? .pointingHand : .crosshair) }
    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) {
        guard !windowMode else { onWindow?(); return }
        start = clampedPoint(event)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !windowMode, let start else { return }
        let point = clampedPoint(event)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(start.x - point.x), height: abs(start.y - point.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !windowMode, start != nil else { return }
        mouseDragged(with: event)
        start = nil
        if let selection, selection.width >= 2, selection.height >= 2 { onArea?(selection) }
    }

    func setWindowMode(_ enabled: Bool) {
        windowMode = enabled
        start = nil
        selection = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func clampedPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        frozenImage.draw(in: bounds)
        let selected = windowMode ? highlight : selection
        let dim = NSBezierPath(rect: bounds)
        if let selected, !selected.isNull { dim.appendRect(selected) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill()
        dim.fill()
        if let selected, !selected.isNull {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selected.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
        let text = windowMode
            ? "Click a window · Space for area · Esc to cancel"
            : "Drag to select on one display · Space for windows · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: (bounds.width - size.width) / 2 - 16, y: bounds.height - 78,
                         width: size.width + 32, height: size.height + 24)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 16, y: box.minY + 12), withAttributes: attributes)
    }
}
