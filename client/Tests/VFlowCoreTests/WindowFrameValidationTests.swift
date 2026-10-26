import CoreGraphics
import Testing
@testable import VFlowCore

struct WindowFrameValidationTests {
    let mainScreen = CGRect(x: 0, y: 0, width: 2056, height: 1210)
    let minSize = CGSize(width: 800, height: 560)

    @Test func parsesLeadingRectIgnoringScreenTrailer() {
        let r = WindowFrameValidation.parseLeadingRect("837 203 880 1048 0 0 2056 1210")
        #expect(r == CGRect(x: 837, y: 203, width: 880, height: 1048))
    }

    @Test func parseReturnsNilForGarbage() {
        #expect(WindowFrameValidation.parseLeadingRect("") == nil)
        #expect(WindowFrameValidation.parseLeadingRect("not a frame") == nil)
    }

    @Test func validFrameWithinScreenIsUnchanged() {
        let frame = CGRect(x: 100, y: 100, width: 960, height: 680)
        let n = WindowFrameValidation.normalize(frame: frame, minSize: minSize, screens: [mainScreen], mainScreen: mainScreen)
        #expect(n == frame)
    }

    @Test func tooSmallFrameClampedUpToMinSize() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let n = WindowFrameValidation.normalize(frame: frame, minSize: minSize, screens: [mainScreen], mainScreen: mainScreen)
        #expect(n.width == minSize.width)
        #expect(n.height == minSize.height)
    }

    @Test func largerThanScreenFrameClampedDownToScreenSize() {
        let frame = CGRect(x: -500, y: -200, width: 5000, height: 4000)
        let n = WindowFrameValidation.normalize(frame: frame, minSize: minSize, screens: [mainScreen], mainScreen: mainScreen)
        #expect(n.width == mainScreen.width)
        #expect(n.height == mainScreen.height)
    }

    @Test func offAllScreensFrameRecenteredOnMainScreen() {
        // Màn hình ngoài đã lưu lúc trước (vd. 1920x1080 ở x=3000) không còn tồn tại.
        let frame = CGRect(x: 30000, y: 30000, width: 960, height: 680)
        let n = WindowFrameValidation.normalize(frame: frame, minSize: minSize, screens: [mainScreen], mainScreen: mainScreen)
        #expect(WindowFrameValidation.intersectsAnyScreen(n, screens: [mainScreen]))
        #expect(abs(n.midX - mainScreen.midX) < 1)
        #expect(abs(n.midY - mainScreen.midY) < 1)
    }

    @Test func overflowingRightEdgeShiftedBackIntoScreen() {
        // Khung lưu đúng kích thước nhưng x đẩy nó tràn mép phải sau khi màn hình đổi độ phân giải
        // (nhỏ hơn trước) — phải dịch vào trong, KHÔNG đổi kích thước.
        let smallerScreen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = CGRect(x: 900, y: 100, width: 880, height: 700)
        let n = WindowFrameValidation.normalize(frame: frame, minSize: minSize, screens: [smallerScreen], mainScreen: smallerScreen)
        #expect(n.width == 880)
        #expect(n.height == 700)
        #expect(n.maxX <= smallerScreen.maxX)
        #expect(n.minX >= smallerScreen.minX)
    }

    @Test func emptyScreensReturnsFrameUnchanged() {
        let frame = CGRect(x: 30000, y: 30000, width: 10, height: 10)
        let n = WindowFrameValidation.normalize(frame: frame, minSize: minSize, screens: [], mainScreen: nil)
        #expect(n == frame)
    }

    @Test func pickssContainingScreenAmongMultiple() {
        let second = CGRect(x: 2056, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 2100, y: 100, width: 960, height: 680)
        let n = WindowFrameValidation.normalize(frame: frame, minSize: minSize, screens: [mainScreen, second], mainScreen: mainScreen)
        // Giữ nguyên vì nằm gọn trong màn hình thứ hai, không bị kẹp theo kích thước màn hình chính.
        #expect(n == frame)
    }
}
