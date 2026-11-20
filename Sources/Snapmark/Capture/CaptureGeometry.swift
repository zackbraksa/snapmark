import CoreGraphics

enum CaptureGeometry {
    static func appKitRect(from quartzRect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: quartzRect.minX, y: primaryScreenTop - quartzRect.maxY,
               width: quartzRect.width, height: quartzRect.height)
    }

    static func pixelCrop(for selection: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect {
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: screenSize))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return .zero }
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        let left = floor(clipped.minX * scaleX)
        let top = floor((screenSize.height - clipped.maxY) * scaleY)
        let right = ceil(clipped.maxX * scaleX)
        let bottom = ceil((screenSize.height - clipped.minY) * scaleY)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(CGRect(origin: .zero, size: imageSize))
    }
}
