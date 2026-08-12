import CoreGraphics
import Foundation

enum DesktopPetPlacement {
    private static let edgeInset: CGFloat = 24
    private static let minimumVisibleSide: CGFloat = 48

    static func defaultOrigin(windowSize: CGSize, screenVisibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenVisibleFrame.maxX - windowSize.width - edgeInset,
            y: screenVisibleFrame.minY + edgeInset
        )
    }

    static func restoredFrame(
        origin: CGPoint?,
        windowSize: CGSize,
        screenVisibleFrames: [CGRect]
    ) -> CGRect? {
        guard let origin, origin.x.isFinite, origin.y.isFinite,
              windowSize.width > 0, windowSize.height > 0 else {
            return nil
        }
        let frame = CGRect(origin: origin, size: windowSize)
        let isReachable = screenVisibleFrames.contains { screen in
            let visible = frame.intersection(screen)
            return !visible.isNull
                && visible.width >= min(minimumVisibleSide, frame.width)
                && visible.height >= min(minimumVisibleSide, frame.height)
        }
        return isReachable ? frame : nil
    }
}
