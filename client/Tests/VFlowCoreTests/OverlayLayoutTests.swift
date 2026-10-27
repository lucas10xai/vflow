import Testing
@testable import VFlowCore

@Suite struct OverlayLayoutTests {
    let screen = OverlayLayout.Rect(minX: 0, minY: 0, width: 1440, height: 900)
    let visible = OverlayLayout.Rect(minX: 0, minY: 0, width: 1440, height: 875) // trừ thanh menu 25pt
    let content = OverlayLayout.Rect(minX: 0, minY: 0, width: 300, height: 40)

    @Test func bottomPositionMatchesOldBehaviorNearBottomCenter() {
        let r = OverlayLayout.frame(contentSize: content, screenFrame: screen, visibleFrame: visible,
                                    auxiliaryLeft: nil, auxiliaryRight: nil, position: .bottom)
        #expect(r.minY == visible.minY + OverlayLayout.edgeMargin)
        #expect(abs(r.midX - visible.midX) < 0.001)
    }

    @Test func topNearNotchWithoutNotchCentersUnderMenuBar() {
        let r = OverlayLayout.frame(contentSize: content, screenFrame: screen, visibleFrame: visible,
                                    auxiliaryLeft: nil, auxiliaryRight: nil, position: .topNearNotch)
        #expect(abs(r.midX - screen.midX) < 0.001)
        #expect(r.maxY == visible.maxY - OverlayLayout.edgeMargin)
    }

    @Test func topNearNotchWithNotchCentersBetweenAuxiliaryAreas() {
        let left = OverlayLayout.Rect(minX: 0, minY: 0, width: 200, height: 40)
        let right = OverlayLayout.Rect(minX: 900, minY: 0, width: 200, height: 40) // notch giữa 200–900
        let r = OverlayLayout.frame(contentSize: content, screenFrame: screen, visibleFrame: visible,
                                    auxiliaryLeft: left, auxiliaryRight: right, position: .topNearNotch)
        let expectedMid = (left.maxX + right.minX) / 2 // = 550
        #expect(abs(r.midX - expectedMid) < 0.001)
    }

    @Test func neverOverflowsScreenHorizontallyEvenWhenNotchGapIsNarrow() {
        // Vùng an toàn hẹp hơn nội dung ⇒ vẫn phải kẹp trong màn hình, không tràn ra ngoài.
        let left = OverlayLayout.Rect(minX: 0, minY: 0, width: 690, height: 40)
        let right = OverlayLayout.Rect(minX: 710, minY: 0, width: 730, height: 40) // notch giữa 690–710 (rất hẹp)
        let r = OverlayLayout.frame(contentSize: content, screenFrame: screen, visibleFrame: visible,
                                    auxiliaryLeft: left, auxiliaryRight: right, position: .topNearNotch)
        #expect(r.minX >= screen.minX)
        #expect(r.maxX <= screen.maxX)
    }

    @Test func secondaryScreenAtNonZeroOriginStaysWithinItsOwnBounds() {
        let secondaryScreen = OverlayLayout.Rect(minX: 1440, minY: 0, width: 1920, height: 1080)
        let secondaryVisible = OverlayLayout.Rect(minX: 1440, minY: 0, width: 1920, height: 1055)
        let r = OverlayLayout.frame(contentSize: content, screenFrame: secondaryScreen, visibleFrame: secondaryVisible,
                                    auxiliaryLeft: nil, auxiliaryRight: nil, position: .bottom)
        #expect(r.minX >= secondaryScreen.minX)
        #expect(r.maxX <= secondaryScreen.maxX)
    }

    @Test func largeContentWiderThanScreenIsClampedNotNegative() {
        let wideContent = OverlayLayout.Rect(minX: 0, minY: 0, width: 2000, height: 40)
        let r = OverlayLayout.frame(contentSize: wideContent, screenFrame: screen, visibleFrame: visible,
                                    auxiliaryLeft: nil, auxiliaryRight: nil, position: .bottom)
        #expect(r.minX == screen.minX)
    }
}

@Suite struct OverlaySizeTests {
    @Test func compactHasNoLivePreviewLines() {
        #expect(OverlaySize.compact.livePreviewLineCount == 0)
    }

    @Test func mediumMatchesCurrentTwoLineBehavior() {
        #expect(OverlaySize.medium.livePreviewLineCount == 2)
    }

    @Test func largeHasFourLines() {
        #expect(OverlaySize.large.livePreviewLineCount == 4)
    }

    @Test func largeIsWiderThanMedium() {
        #expect(OverlaySize.large.maxPreviewWidth > OverlaySize.medium.maxPreviewWidth)
    }
}

/// Hình học THẬT đo trên Mac của chủ dự án (MacBook Pro có notch + màn hình phụ đặt lệch): chặn lỗi
/// HUD chui vào dải notch hoặc tràn ra ngoài màn hình.
@Suite struct OverlayNotchGeometryTests {
    // MacBook: 2056×1329, thanh menu 38pt = đúng chiều cao notch, dải trái 918pt, dải phải 918pt.
    let notchScreen = OverlayLayout.Rect(minX: 0, minY: 0, width: 2056, height: 1329)
    let notchVisible = OverlayLayout.Rect(minX: 0, minY: 80, width: 2056, height: 1210) // trừ Dock đáy + menu trên
    let notchBand = (minY: 1329.0 - 38.0, maxY: 1329.0) // dải y bị notch/thanh menu chiếm

    func size(_ s: OverlaySize, lines: Int? = nil) -> OverlayLayout.Rect {
        // Chiều cao xấp xỉ: 1 dòng trạng thái 32pt + mỗi dòng chữ trực tiếp 15pt.
        OverlayLayout.Rect(minX: 0, minY: 0, width: s.maxContainerWidth, height: 32 + 15 * Double(lines ?? s.livePreviewLineCount))
    }

    @Test func auxiliaryAreasUseWidthsOnlySoSecondaryOriginDoesNotMatter() {
        let secondary = OverlayLayout.Rect(minX: -249, minY: 1329, width: 2560, height: 1440)
        let a = OverlayLayout.auxiliaryAreas(screenFrame: secondary, leftWidth: 1000, rightWidth: 1000, height: 40)
        #expect(a?.left.minX == -249)
        #expect(a?.right.maxX == secondary.maxX)
        // khe notch = [minX + 1000, maxX - 1000]
        #expect(a?.left.maxX == 751)
        #expect(a?.right.minX == 1311)
    }

    @Test func auxiliaryAreasAreNilWithoutBothSidesOrWhenImpossible() {
        #expect(OverlayLayout.auxiliaryAreas(screenFrame: notchScreen, leftWidth: nil, rightWidth: 918, height: 38) == nil)
        #expect(OverlayLayout.auxiliaryAreas(screenFrame: notchScreen, leftWidth: 918, rightWidth: nil, height: 38) == nil)
        #expect(OverlayLayout.auxiliaryAreas(screenFrame: notchScreen, leftWidth: 1100, rightWidth: 1000, height: 38) == nil)
    }

    @Test func topNearNotchCentersUnderTheNotchAndBelowTheBandForEverySize() throws {
        let aux = try #require(OverlayLayout.auxiliaryAreas(screenFrame: notchScreen, leftWidth: 918, rightWidth: 918, height: 38))
        for s in OverlaySize.allCases {
            let c = size(s)
            let r = OverlayLayout.frame(contentSize: c, screenFrame: notchScreen, visibleFrame: notchVisible,
                                        auxiliaryLeft: aux.left, auxiliaryRight: aux.right,
                                        position: .topNearNotch, topInset: 38)
            #expect(abs(r.midX - 1028) < 0.001, "cỡ \(s)")
            #expect(r.maxY <= notchBand.minY, "cỡ \(s): HUD không được chạm dải notch")
            #expect(r.minX >= notchScreen.minX && r.maxX <= notchScreen.maxX)
            #expect(r.minY >= notchScreen.minY)
        }
    }

    /// Toàn màn hình: thanh menu tự ẩn nên `visibleFrame.maxY` chạm đỉnh màn hình — chỉ `topInset` giữ
    /// HUD khỏi chui vào dải notch. Phá nhánh `min(..., screenFrame.maxY - topInset)` ⇒ test này đỏ.
    @Test func fullScreenAppWithHiddenMenuBarStillAvoidsNotchBand() throws {
        let fullVisible = OverlayLayout.Rect(minX: 0, minY: 0, width: 2056, height: 1329)
        let aux = try #require(OverlayLayout.auxiliaryAreas(screenFrame: notchScreen, leftWidth: 918, rightWidth: 918, height: 38))
        let r = OverlayLayout.frame(contentSize: size(.medium), screenFrame: notchScreen, visibleFrame: fullVisible,
                                    auxiliaryLeft: aux.left, auxiliaryRight: aux.right,
                                    position: .topNearNotch, topInset: 38)
        #expect(r.maxY <= notchBand.minY)
    }

    @Test func bottomPositionKeepsLegacyPlacementForEverySize() {
        for s in OverlaySize.allCases {
            let c = size(s)
            let r = OverlayLayout.frame(contentSize: c, screenFrame: notchScreen, visibleFrame: notchVisible,
                                        auxiliaryLeft: nil, auxiliaryRight: nil, position: .bottom)
            #expect(r.minY == notchVisible.minY + OverlayLayout.edgeMargin, "cỡ \(s)")
            #expect(abs(r.midX - notchVisible.midX) < 0.001)
        }
    }

    @Test func secondaryMonitorWithNegativeOriginStaysInsideForEveryPositionAndSize() {
        let screen = OverlayLayout.Rect(minX: -249, minY: 1329, width: 2560, height: 1440)
        for position in OverlayPosition.allCases {
            for s in OverlaySize.allCases {
                let r = OverlayLayout.frame(contentSize: size(s), screenFrame: screen, visibleFrame: screen,
                                            auxiliaryLeft: nil, auxiliaryRight: nil, position: position)
                #expect(r.minX >= screen.minX && r.maxX <= screen.maxX, "\(position) \(s)")
                #expect(r.minY >= screen.minY && r.maxY <= screen.maxY, "\(position) \(s)")
                #expect(abs(r.midX - screen.midX) < 0.001, "\(position) \(s): giữa màn hình phụ")
            }
        }
    }

    @Test func contentTallerThanAvailableSpaceIsClampedInsideTheScreen() {
        let small = OverlayLayout.Rect(minX: 0, minY: 0, width: 800, height: 120)
        let tall = OverlayLayout.Rect(minX: 0, minY: 0, width: 500, height: 200)
        for position in OverlayPosition.allCases {
            let r = OverlayLayout.frame(contentSize: tall, screenFrame: small, visibleFrame: small,
                                        auxiliaryLeft: nil, auxiliaryRight: nil, position: position)
            #expect(r.minY >= small.minY && r.maxY <= max(small.maxY, small.minY + tall.height), "\(position)")
            #expect(r.minY == small.minY || r.maxY <= small.maxY)
        }
    }

    @Test func largeContainerFitsItsPreviewPlusPadding() {
        for s in OverlaySize.allCases where s.livePreviewLineCount > 0 {
            #expect(s.maxContainerWidth >= s.maxPreviewWidth + 28, "cỡ \(s): lề 14pt mỗi bên")
        }
    }
}
