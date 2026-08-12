import AppKit
import SwiftUI

@MainActor
final class DesktopPetWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false
    @Published private(set) var isPerformingCute = false
    @Published private(set) var isFacingRight = true
    @Published private(set) var isMoving = false

    private static let windowSize = CGSize(width: 164, height: 168)
    private static let isVisibleKey = "desktopPet.isVisible"
    private static let positionXKey = "desktopPet.position.x"
    private static let positionYKey = "desktopPet.position.y"
    private static let lastCutenessKey = "desktopPet.lastCuteness"
    private let defaults = UserDefaults.standard
    private var panel: NSPanel?
    private weak var dashboardCoordinator: WindowCoordinator?
    private var positionSaveTask: Task<Void, Never>?
    private var roamingTask: Task<Void, Never>?
    private var cuteTask: Task<Void, Never>?
    private var dragOffset: CGPoint?
    private var movementTarget: CGPoint?
    private var nextMovementDate = Date()
    private var lastMovementDate = Date()
    private var lastCutenessDate = Date()
    private var didRestoreVisibility = false

    deinit {
        positionSaveTask?.cancel()
        roamingTask?.cancel()
        cuteTask?.cancel()
    }

    func prepare(model: AppModel, dashboardCoordinator: WindowCoordinator) {
        self.dashboardCoordinator = dashboardCoordinator
        ensurePanel(model: model)
        guard !didRestoreVisibility else { return }
        didRestoreVisibility = true
        lastCutenessDate = HourlyCutenessSchedule.restoredLastPerformed(
            timestamp: storedCutenessTimestamp(),
            now: Date()
        )

        let shouldShow = defaults.object(forKey: Self.isVisibleKey) == nil
            || defaults.bool(forKey: Self.isVisibleKey)
        if shouldShow {
            show(model: model, dashboardCoordinator: dashboardCoordinator)
        }
    }

    func toggle(model: AppModel, dashboardCoordinator: WindowCoordinator) {
        isVisible ? hide() : show(model: model, dashboardCoordinator: dashboardCoordinator)
    }

    func show(model: AppModel, dashboardCoordinator: WindowCoordinator) {
        self.dashboardCoordinator = dashboardCoordinator
        ensurePanel(model: model)
        panel?.orderFrontRegardless()
        isVisible = true
        defaults.set(true, forKey: Self.isVisibleKey)
        startRoaming()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.triggerCutenessIfDue(at: Date())
        }
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        defaults.set(false, forKey: Self.isVisibleKey)
        roamingTask?.cancel()
        roamingTask = nil
        cuteTask?.cancel()
        cuteTask = nil
        isPerformingCute = false
        isMoving = false
    }

    private func ensurePanel(model: AppModel) {
        guard panel == nil else { return }

        let panel = DesktopPetPanel(
            contentRect: CGRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.title = "ShiftPaw 桌面宠物"
        panel.onDragStarted = { [weak self] point in self?.beginPanelDrag(at: point) }
        panel.onDragChanged = { [weak self] point in self?.movePanel(to: point) }
        panel.onDragEnded = { [weak self] in self?.endPanelDrag() }
        panel.onDoubleClick = { [weak self] in self?.dashboardCoordinator?.show() }

        let rootView = DesktopPetWindowView(
            model: model,
            controller: self,
            onOpenDashboard: { [weak self] in self?.dashboardCoordinator?.show() },
            onHide: { [weak self] in self?.hide() }
        )
        let hostingView = DesktopPetHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        let storedOrigin = storedOrigin()
        if let restored = DesktopPetPlacement.restoredFrame(
            origin: storedOrigin,
            windowSize: Self.windowSize,
            screenVisibleFrames: screenFrames
        ) {
            panel.setFrame(restored, display: false)
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrameOrigin(DesktopPetPlacement.defaultOrigin(
                windowSize: Self.windowSize,
                screenVisibleFrame: screen.visibleFrame
            ))
        }

        self.panel = panel
    }

    private func startRoaming() {
        guard roamingTask == nil else { return }
        lastMovementDate = Date()
        roamingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    return
                }
                self?.advanceRoaming(at: Date())
            }
        }
    }

    private func advanceRoaming(at now: Date) {
        guard isVisible else { return }
        triggerCutenessIfDue(at: now)
        guard dragOffset == nil, !isPerformingCute, let panel else {
            isMoving = false
            return
        }
        let elapsed = min(max(now.timeIntervalSince(lastMovementDate), 0), 0.2)
        lastMovementDate = now
        guard now >= nextMovementDate else {
            isMoving = false
            return
        }

        guard let screen = screen(for: panel) else { return }
        let area = DesktopPetMovement.movementArea(
            windowSize: Self.windowSize,
            screenVisibleFrame: screen.visibleFrame
        )
        let currentOrigin = CGPoint(
            x: min(max(panel.frame.minX, area.minX), area.maxX),
            y: min(max(panel.frame.minY, area.minY), area.maxY)
        )
        if panel.frame.origin != currentOrigin {
            panel.setFrameOrigin(currentOrigin)
        }
        if movementTarget == nil {
            movementTarget = randomTarget(in: area)
        }
        guard let target = movementTarget else { return }
        let step = DesktopPetMovement.advance(
            from: currentOrigin,
            toward: target,
            speed: 44,
            elapsed: elapsed,
            within: area
        )
        panel.setFrameOrigin(step.origin)
        isFacingRight = step.isFacingRight
        isMoving = !step.didReachTarget
        if step.didReachTarget {
            movementTarget = nil
            nextMovementDate = now.addingTimeInterval(Double.random(in: 0.45...1.1))
        }
    }

    private func triggerCutenessIfDue(at now: Date) {
        guard !isPerformingCute, HourlyCutenessSchedule.isDue(lastPerformed: lastCutenessDate, now: now) else { return }
        lastCutenessDate = now
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastCutenessKey)
        isPerformingCute = true
        isMoving = false
        movementTarget = nil
        isMoving = false
        cuteTask?.cancel()
        cuteTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(12))
            } catch {
                return
            }
            self?.isPerformingCute = false
        }
    }

    private func randomTarget(in area: CGRect) -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: area.minX...area.maxX),
            y: CGFloat.random(in: area.minY...area.maxY)
        )
    }

    private func screen(for panel: NSWindow) -> NSScreen? {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func storedOrigin() -> CGPoint? {
        guard let x = defaults.object(forKey: Self.positionXKey) as? NSNumber,
              let y = defaults.object(forKey: Self.positionYKey) as? NSNumber else {
            return nil
        }
        return CGPoint(x: x.doubleValue, y: y.doubleValue)
    }

    private func storedCutenessTimestamp() -> TimeInterval? {
        let value = defaults.object(forKey: Self.lastCutenessKey)
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func beginPanelDrag(at mouse: CGPoint) {
        guard let panel else { return }
        dragOffset = CGPoint(
            x: mouse.x - panel.frame.minX,
            y: mouse.y - panel.frame.minY
        )
        movementTarget = nil
    }

    private func endPanelDrag() {
        dragOffset = nil
        nextMovementDate = Date().addingTimeInterval(0.8)
        persistPanelOrigin()
    }

    private func persistPanelOrigin() {
        guard let panel else { return }
        let origin = panel.frame.origin
        positionSaveTask?.cancel()
        positionSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            self?.defaults.set(Double(origin.x), forKey: Self.positionXKey)
            self?.defaults.set(Double(origin.y), forKey: Self.positionYKey)
        }
    }

    private func movePanel(to mouse: CGPoint) {
        guard let panel else { return }
        guard let dragOffset else { return }
        panel.setFrameOrigin(CGPoint(
            x: mouse.x - dragOffset.x,
            y: mouse.y - dragOffset.y
        ))
    }
}

private final class DesktopPetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class DesktopPetPanel: NSPanel {
    var onDragStarted: ((CGPoint) -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if event.clickCount >= 2 {
                onDoubleClick?()
            } else {
                onDragStarted?(NSEvent.mouseLocation)
            }
        case .leftMouseDragged:
            onDragChanged?(NSEvent.mouseLocation)
        case .leftMouseUp:
            onDragEnded?()
        default:
            super.sendEvent(event)
        }
    }
}

private struct DesktopPetWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: DesktopPetWindowController
    let onOpenDashboard: () -> Void
    let onHide: () -> Void
    @State private var isHovering = false

    private var isOnDuty: Bool { model.snapshot?.isOnDuty ?? false }

    private var statusText: String {
        if controller.isPerformingCute {
            return "本喵来卖萌啦"
        }
        if let alertText = model.alertText {
            return alertText
        }
        guard let snapshot = model.snapshot else { return "等待排班" }
        let seconds = max(0, snapshot.next.date.timeIntervalSince(model.now))
        return "距\(snapshot.next.event.action) \(CountdownText.format(seconds: seconds))"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Text(statusText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DutyPalette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(DutyPalette.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(DutyPalette.separator, lineWidth: 1)
                }
                .opacity(isHovering || model.alertText != nil || controller.isPerformingCute ? 1 : 0)
                .scaleEffect(isHovering || model.alertText != nil || controller.isPerformingCute ? 1 : 0.92)
                .allowsHitTesting(false)

            TimelineView(.periodic(from: .now, by: 1 / 12)) { context in
                DutyPetArtwork(
                    phase: context.date.timeIntervalSinceReferenceDate,
                    isOnDuty: isOnDuty,
                    isPerformingCute: controller.isPerformingCute,
                    isFacingRight: controller.isFacingRight,
                    isMoving: controller.isMoving
                )
            }
            .frame(width: 108, height: 92)
            .scaleEffect(1.22)
            .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
            .offset(y: 43)

        }
        .frame(width: 164, height: 168)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("打开值守面板", systemImage: "rectangle.on.rectangle") {
                onOpenDashboard()
            }
            Button("隐藏桌面宠物", systemImage: "eye.slash") {
                onHide()
            }
        }
        .help("双击打开值守面板")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOnDuty ? "值守桌面宠物正在工作" : "值守桌面宠物正在待机")
    }
}
