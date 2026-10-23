import AppKit
import SwiftUI

/// Owns the panel, keeps it pinned to the top-centre of the notch screen, and turns
/// mouse position into hover / open / close decisions.
final class NotchController {
    private let viewModel: NotchViewModel
    private let panel: NotchPanel
    private let space = NotchSpace()
    private var screen: NSScreen
    private var timer: Timer?

    private var hoverStartedAt: Date?
    private var exitStartedAt: Date?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    private let hoverDelay: TimeInterval = 0.12
    private let closeDelay: TimeInterval = 0.35

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.screen = Self.targetScreen()
        self.panel = NotchPanel(contentRect: .zero)

        let hosting = NotchHostingView(rootView: NotchView().environmentObject(viewModel))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func start() {
        layout()
        panel.orderFrontRegardless()
        // Needs a window number, so only once the panel is on screen.
        space.add(panel)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.layout()
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["NOTCH_SNAPSHOT_DIR"] {
            captureSnapshots(into: directory)
        }
        #endif
    }

    #if DEBUG
    /// Renders closed / open / shelf states to PNGs so the UI can be checked without screen recording.
    private func captureSnapshots(into directory: String) {
        let steps: [(String, () -> Void)] = [
            ("closed", { self.viewModel.close() }),
            ("activity", { self.viewModel.showFlash(.power(level: 76, pluggedIn: true), duration: 5) }),
            ("open-home-prompt", { self.viewModel.open(tab: .home, pinned: true) }),
            ("open-home", { self.viewModel.calendar.loadPreviewEvents() }),
            ("open-shelf", { self.viewModel.tab = .shelf }),
            ("open-widgets", { self.viewModel.weather.loadPreviewWeather(); self.viewModel.tab = .widgets }),
            ("open-widgets-timer", { self.viewModel.timer.start(minutes: 25) }),
            ("open-clipboard", { self.viewModel.clipboard.loadPreviewItems(); self.viewModel.tab = .clipboard }),
            ("timer-activity", { self.viewModel.close() }),
        ]
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.5 + 0.5) { step.1() }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.5 + 1.4) { [weak self] in
                guard let view = self?.panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: directory).appendingPathComponent("\(step.0).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }
    #endif

    // MARK: - Layout

    /// Prefer the built-in display (where the notch lives); fall back to the main screen.
    private static func targetScreen() -> NSScreen {
        let builtIn = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return CGDisplayIsBuiltin(id) != 0
        }
        return builtIn ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func layout() {
        screen = Self.targetScreen()

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            viewModel.hasPhysicalNotch = true
            viewModel.notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                                         height: screen.safeAreaInsets.top)
        } else {
            // No hardware notch: draw a virtual one that sits flush with the menu bar.
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            viewModel.hasPhysicalNotch = false
            viewModel.notchSize = CGSize(width: 190, height: menuBarHeight > 20 ? menuBarHeight : 24)
        }

        // The panel is sized for the fully-open state plus room for the shadow; the
        // transparent remainder ignores the mouse so the menu bar stays usable.
        let width = viewModel.openSize.width + 80
        let height = viewModel.openSize.height + 40
        let frame = NSRect(x: screen.frame.midX - width / 2,
                           y: screen.frame.maxY - height,
                           width: width,
                           height: height)
        panel.setFrame(frame, display: true)
    }

    // MARK: - Mouse tracking

    private func hotRect() -> NSRect {
        let size = viewModel.currentSize
        let rect = NSRect(x: screen.frame.midX - size.width / 2,
                          y: screen.frame.maxY - size.height,
                          width: size.width,
                          height: size.height)
        return viewModel.isOpen ? rect.insetBy(dx: -10, dy: -10) : rect.insetBy(dx: -12, dy: -8)
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let inside = hotRect().contains(mouse)
        let now = Date()

        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        let dragCount = NSPasteboard(name: .drag).changeCount
        let isDraggingContent = buttonDown && dragCount != dragChangeCount
        if !buttonDown { dragChangeCount = dragCount }

        panel.ignoresMouseEvents = !inside

        if inside != viewModel.isHovering { viewModel.isHovering = inside }

        if inside {
            exitStartedAt = nil
            guard !viewModel.isOpen else { return }
            if isDraggingContent {
                viewModel.open(tab: .shelf)
                return
            }
            let started = hoverStartedAt ?? now
            hoverStartedAt = started
            if viewModel.openOnHover && !buttonDown && now.timeIntervalSince(started) >= hoverDelay {
                viewModel.open()
            }
        } else {
            hoverStartedAt = nil
            guard viewModel.isOpen, !viewModel.isPinned, !viewModel.isDropTargeted else {
                exitStartedAt = nil
                return
            }
            let started = exitStartedAt ?? now
            exitStartedAt = started
            if now.timeIntervalSince(started) >= closeDelay {
                viewModel.close()
                exitStartedAt = nil
            }
        }
    }
}
