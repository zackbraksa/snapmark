import CoreGraphics
import XCTest
@testable import Snapmark

final class CaptureTests: XCTestCase {
    func testRetinaCropFlipsVerticalOrigin() {
        let crop = CaptureGeometry.pixelCrop(for: CGRect(x: 100, y: 50, width: 200, height: 100),
                                             screenSize: CGSize(width: 1000, height: 800),
                                             imageSize: CGSize(width: 2000, height: 1600))
        XCTAssertEqual(crop, CGRect(x: 200, y: 1300, width: 400, height: 200))
    }

    func testCropClampsToOneDisplayAndRoundsOutward() {
        let crop = CaptureGeometry.pixelCrop(for: CGRect(x: -10, y: 10.25, width: 30.25, height: 90),
                                             screenSize: CGSize(width: 100, height: 100),
                                             imageSize: CGSize(width: 200, height: 200))
        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 41, height: 180))
    }

    func testQuartzCoordinatesAcrossDisplayOrigins() {
        XCTAssertEqual(CaptureGeometry.appKitRect(from: CGRect(x: -1200, y: -400, width: 300, height: 200),
                                                  primaryScreenTop: 900),
                       CGRect(x: -1200, y: 1100, width: 300, height: 200))
        XCTAssertEqual(CaptureGeometry.appKitRect(from: CGRect(x: 100, y: 950, width: 300, height: 200),
                                                  primaryScreenTop: 900),
                       CGRect(x: 100, y: -250, width: 300, height: 200))
    }

    func testSelectionOutsideDisplayIsEmpty() {
        XCTAssertEqual(CaptureGeometry.pixelCrop(for: CGRect(x: 200, y: 200, width: 10, height: 10),
                                                 screenSize: CGSize(width: 100, height: 100),
                                                 imageSize: CGSize(width: 200, height: 200)), .zero)
    }
}
