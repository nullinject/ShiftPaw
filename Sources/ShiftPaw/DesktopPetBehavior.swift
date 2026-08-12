import CoreGraphics
import Foundation

enum DesktopPetMovement {
    struct Step: Equatable, Sendable {
        let origin: CGPoint
        let didReachTarget: Bool
        let isFacingRight: Bool
    }

    static func movementArea(windowSize: CGSize, screenVisibleFrame: CGRect) -> CGRect {
        let inset: CGFloat = 12
        let width = max(0, screenVisibleFrame.width - windowSize.width - inset * 2)
        let height = max(0, screenVisibleFrame.height - windowSize.height - inset * 2)
        return CGRect(
            x: screenVisibleFrame.minX + inset,
            y: screenVisibleFrame.minY + inset,
            width: width,
            height: height
        )
    }

    static func advance(
        from origin: CGPoint,
        toward target: CGPoint,
        speed: CGFloat,
        elapsed: TimeInterval,
        within area: CGRect
    ) -> Step {
        let boundedTarget = CGPoint(
            x: min(max(target.x, area.minX), area.maxX),
            y: min(max(target.y, area.minY), area.maxY)
        )
        let dx = boundedTarget.x - origin.x
        let dy = boundedTarget.y - origin.y
        let distance = hypot(dx, dy)
        guard distance > 0.5 else {
            return Step(origin: boundedTarget, didReachTarget: true, isFacingRight: dx >= 0)
        }

        let travel = max(0, speed * CGFloat(elapsed))
        let ratio = min(1, travel / distance)
        let next = CGPoint(
            x: origin.x + dx * ratio,
            y: origin.y + dy * ratio
        )
        return Step(
            origin: next,
            didReachTarget: ratio >= 1,
            isFacingRight: dx >= 0
        )
    }
}

enum HourlyCutenessSchedule {
    static let interval: TimeInterval = 60 * 60

    static func isDue(lastPerformed: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastPerformed) >= interval
    }

    static func restoredLastPerformed(timestamp: TimeInterval?, now: Date) -> Date {
        guard let timestamp, timestamp.isFinite else { return now }
        let saved = Date(timeIntervalSince1970: timestamp)
        guard saved <= now else { return now }
        return saved
    }
}
