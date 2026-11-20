import AppKit
import ScreenCaptureKit

enum CaptureMode {
    case area, window, fullScreen
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case displayUnavailable
    case imageUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Allow Snapmark in System Settings → Privacy & Security → Screen Recording, then quit and reopen Snapmark. If it is already enabled, remove its entry with the minus button and add the current Snapmark app again with the plus button. This repairs a permission entry left by an older development build."
        case .displayUnavailable:
            "The selected display is no longer available. Try capturing again."
        case .imageUnavailable:
            "The selected area could not be captured. Try selecting it again."
        }
    }
}

@MainActor
final class CaptureService {
    func capture(_ mode: CaptureMode) async throws -> CGImage? {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screens = NSScreen.screens
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        let pointer = NSEvent.mouseLocation
        guard let pointerScreen = screens.first(where: { $0.frame.contains(pointer) }) ?? screens.first,
              let display = Self.display(for: pointerScreen, in: content) else {
            throw CaptureError.displayUnavailable
        }
        if mode == .fullScreen {
            return try await captureDisplay(display, excluding: ownWindows, screen: pointerScreen)
        }

        var snapshots: [DisplaySnapshot] = []
        for screen in screens {
            guard let display = Self.display(for: screen, in: content) else { continue }
            let image = try await captureDisplay(display, excluding: ownWindows, screen: screen)
            snapshots.append(DisplaySnapshot(screen: screen, image: image))
        }
        try Task.checkCancellation()
        let primaryTop = screens.first(where: { Self.displayID(for: $0) == CGMainDisplayID() })?.frame.maxY ?? 0
        let windows = selectableWindows(content.windows)
        let session = CaptureSelectionSession(snapshots: snapshots, windows: windows,
                                              primaryScreenTop: primaryTop, mode: mode)
        guard let selection = await session.select() else { return nil }
        try Task.checkCancellation()
        switch selection {
        case let .area(snapshot, rect):
            let crop = CaptureGeometry.pixelCrop(for: rect, screenSize: snapshot.screen.frame.size,
                                                 imageSize: CGSize(width: snapshot.image.width, height: snapshot.image.height))
            guard let image = snapshot.image.cropping(to: crop) else { throw CaptureError.imageUnavailable }
            return image
        case let .window(window):
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
            configuration.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    }

    private func captureDisplay(_ display: SCDisplay, excluding windows: [SCWindow], screen: NSScreen) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: windows)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((screen.frame.width * screen.backingScaleFactor).rounded()))
        configuration.height = max(1, Int((screen.frame.height * screen.backingScaleFactor).rounded()))
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func selectableWindows(_ windows: [SCWindow]) -> [SCWindow] {
        let eligible = windows.filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width > 1 && $0.frame.height > 1 &&
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
        }
        let descriptions = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let order = descriptions.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return eligible.sorted { (ranks[$0.windowID] ?? Int.max) < (ranks[$1.windowID] ?? Int.max) }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func display(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { $0.displayID == displayID(for: screen) }
    }
}
