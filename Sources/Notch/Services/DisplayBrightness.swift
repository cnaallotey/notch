import AppKit
import CoreGraphics

struct ControlledDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let key: String
    let isBuiltIn: Bool
    let usesOverlay: Bool
    var brightness: Double
}

/// Software brightness for every connected display, built-in and mirrored ones included. Displays
/// are dimmed by scaling their gamma table; AirPlay, Sidecar and DisplayLink screens ignore gamma,
/// so they get a click-through black overlay instead. Nothing touches the monitor's own hardware settings, and macOS restores
/// the normal colours as soon as the app quits.
final class DisplayBrightness: ObservableObject {
    typealias GammaTable = (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue])

    @Published private(set) var displays: [ControlledDisplay] = []

    /// Software dimming stops at 10% so a screen can never go fully black.
    let minimum = 0.1

    private var defaultTables: [CGDirectDisplayID: GammaTable] = [:]
    private var overlays: [CGDirectDisplayID: NSWindow] = [:]
    private var reloadWork: DispatchWorkItem?
    private let defaults = UserDefaults.standard

    /// WindowServer only re-reads a display's gamma table when something on it redraws, so a
    /// nearly invisible 1×1 window is nudged onto the display whenever its brightness changes.
    private lazy var redrawNudge: NSWindow = {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return window
    }()

    init() {
        reload()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReload()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReload()
        }
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(value, minimum), 1)
        displays[index].brightness = clamped
        defaults.set(clamped, forKey: "brightness.\(displays[index].key)")
        apply(displays[index])
    }

    func setUsesOverlay(_ usesOverlay: Bool, for id: CGDirectDisplayID) {
        guard let display = displays.first(where: { $0.id == id }) else { return }
        defaults.set(usesOverlay, forKey: "overlay.\(display.key)")
        reload()
    }

    /// Puts every display back to its normal colours. Called on quit.
    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
        overlays.values.forEach { $0.orderOut(nil) }
    }

    // MARK: - Discovery

    /// Display changes arrive in bursts and gamma is reset slightly after them, so wait a moment.
    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func reload() {
        // Start from the system's colour profiles so the captured tables are the real defaults.
        CGDisplayRestoreColorSyncSettings()
        defaultTables.removeAll()

        var found: [ControlledDisplay] = []
        for id in Self.onlineDisplays() {
            let key = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let screen = Self.screen(for: id)
            let name = screen?.localizedName ?? (isBuiltIn ? "Built-in Display" : "Display \(CGDisplayUnitNumber(id) + 1)")

            let table = Self.gammaTable(for: id)
            if let table { defaultTables[id] = table }

            // Overlay windows can only cover a screen macOS lists, which excludes mirror copies.
            let forcedOverlay = defaults.object(forKey: "overlay.\(key)") as? Bool
            let usesOverlay = screen != nil && (forcedOverlay ?? (table == nil || Self.ignoresGamma(name)))
            let saved = defaults.object(forKey: "brightness.\(key)") as? Double ?? 1

            found.append(ControlledDisplay(id: id, name: name, key: key, isBuiltIn: isBuiltIn, usesOverlay: usesOverlay,
                                           brightness: min(max(saved, minimum), 1)))
        }

        for (id, window) in overlays where !found.contains(where: { $0.id == id && $0.usesOverlay }) {
            window.orderOut(nil)
            overlays[id] = nil
        }

        displays = found.sorted { $0.isBuiltIn && !$1.isBuiltIn }
        displays.forEach(apply)
    }

    /// Every display that's showing a picture, including ones that mirror another display.
    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsActive($0) != 0 || CGDisplayMirrorsDisplay($0) != 0 }
    }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == id }
    }

    private static func ignoresGamma(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["airplay", "sidecar", "displaylink", "dummy"].contains { name.contains($0) }
    }

    private static func gammaTable(for id: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &count) == .success, count > 0 else {
            return nil
        }
        return (Array(red.prefix(Int(count))), Array(green.prefix(Int(count))), Array(blue.prefix(Int(count))))
    }

    // MARK: - Applying

    private func apply(_ display: ControlledDisplay) {
        if display.usesOverlay {
            applyOverlay(display)
        } else if let table = defaultTables[display.id] {
            let scale = CGGammaValue(display.brightness)
            let red = table.red.map { $0 * scale }
            let green = table.green.map { $0 * scale }
            let blue = table.blue.map { $0 * scale }
            CGSetDisplayTransferByTable(display.id, UInt32(red.count), red, green, blue)
            nudgeRedraw(on: display.id)
        }
    }

    private func applyOverlay(_ display: ControlledDisplay) {
        guard display.brightness < 1, let screen = Self.screen(for: display.id) else {
            overlays[display.id]?.orderOut(nil)
            return
        }

        let window = overlays[display.id] ?? {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .black
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            overlays[display.id] = window
            return window
        }()
        window.setFrame(screen.frame, display: false)
        window.alphaValue = 1 - display.brightness
        window.orderFrontRegardless()
    }

    private func nudgeRedraw(on id: CGDirectDisplayID) {
        // A mirror copy has no screen of its own; nudge the display it mirrors.
        let mirrored = CGDisplayMirrorsDisplay(id)
        guard let screen = Self.screen(for: mirrored != 0 ? mirrored : id) else { return }
        redrawNudge.setFrameOrigin(screen.frame.origin)
        redrawNudge.alphaValue = redrawNudge.alphaValue == 0.01 ? 0.02 : 0.01
        redrawNudge.orderFrontRegardless()
    }
}
