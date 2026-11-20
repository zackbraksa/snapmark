import AppKit

@MainActor protocol ImageClipboard: AnyObject {
    var changeCount: Int { get }
    func clear()
    func writePNG(_ data: Data) -> Bool
}

@MainActor final class SystemImageClipboard: ImageClipboard {
    private let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    func clear() { pasteboard.clearContents() }
    func writePNG(_ data: Data) -> Bool { pasteboard.setData(data, forType: .png) }
}
