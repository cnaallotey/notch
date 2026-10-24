import AppKit
import Combine
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, widgets, controls, clipboard, shelf

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .controls: return "slider.horizontal.3"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        }
    }
}

/// A short alert shown in the closed notch: an icon and title on the left, a detail on the right.
struct Notice: Equatable {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
}

/// Compact "live activity" shown beside the closed notch.
enum LiveActivity: Equatable {
    case media
    case power(level: Int, pluggedIn: Bool)
    case shelf(count: Int)
    case timer
    case timerDone
    case notice(Notice)
}

final class NotchViewModel: ObservableObject {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.78)

    @Published var isOpen = false
    @Published var isPinned = false
    @Published var isHovering = false
    @Published var isDropTargeted = false
    @Published var tab: NotchTab = .home
    @Published var notchSize = CGSize(width: 190, height: 24)
    @Published var hasPhysicalNotch = false
    @Published private(set) var flash: LiveActivity?

    @Published var openOnHover = UserDefaults.standard.object(forKey: "openOnHover") as? Bool ?? true {
        didSet { UserDefaults.standard.set(openOnHover, forKey: "openOnHover") }
    }
    @Published var showMediaActivity = UserDefaults.standard.object(forKey: "showMediaActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMediaActivity, forKey: "showMediaActivity") }
    }
    @Published var hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    let openSize = CGSize(width: 600, height: 206)

    let media = MediaController()
    let battery = BatteryMonitor()
    let shelf = ShelfStore()
    let calendar = CalendarStore()
    let timer = TimerStore()
    let clipboard = ClipboardStore()
    let stats = SystemStats()
    let weather = WeatherStore()
    let brightness = DisplayBrightness()
    let toggles = QuickToggles()
    private let bluetooth = BluetoothMonitor()

    private var flashWork: DispatchWorkItem?
    private var meetingTimer: Timer?
    private var announcedMeetings = Set<String>()
    private var cancellables = Set<AnyCancellable>()

    init() {
        for publisher in [media.objectWillChange, battery.objectWillChange, shelf.objectWillChange, calendar.objectWillChange,
                          timer.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        battery.onPowerSourceChange = { [weak self] pluggedIn, level in
            self?.showFlash(.power(level: level, pluggedIn: pluggedIn))
        }
        shelf.onAdd = { [weak self] in
            guard let self, !self.isOpen else { return }
            self.showFlash(.shelf(count: self.shelf.items.count))
        }
        timer.onFinish = { [weak self] in
            guard let self else { return }
            if self.hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            self.showFlash(.timerDone, duration: 4)
        }
        setUpNotices()
    }

    // MARK: - Notices

    private func setUpNotices() {
        bluetooth.onChange = { [weak self] name, symbol, connected in
            self?.showNotice(Notice(symbol: symbol, tint: connected ? .blue : .gray, title: name,
                                    detail: connected ? "Connected" : "Disconnected"))
        }
        bluetooth.start()

        battery.onLowBattery = { [weak self] level in
            self?.showNotice(Notice(symbol: level <= 10 ? "battery.0" : "battery.25", tint: .red,
                                    title: "Low Battery", detail: "\(level)%"))
        }

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.checkUpcomingMeetings() }
        RunLoop.main.add(timer, forMode: .common)
        meetingTimer = timer
    }

    /// Announces each timed event once, in the five minutes before it starts.
    private func checkUpcomingMeetings() {
        let now = Date()
        guard let event = calendar.events.first(where: { event in
            let lead = event.start.timeIntervalSince(now)
            return !event.isAllDay && lead > 0 && lead <= 5 * 60 && !announcedMeetings.contains(event.id + "\(event.start)")
        }) else { return }

        announcedMeetings.insert(event.id + "\(event.start)")
        let minutes = max(Int((event.start.timeIntervalSince(now) / 60).rounded(.up)), 1)
        showNotice(Notice(symbol: event.meetingURL != nil ? "video.fill" : "calendar", tint: event.color,
                          title: event.title, detail: "in \(minutes) min"), duration: 6)
    }

    private func showNotice(_ notice: Notice, duration: TimeInterval = 4) {
        guard !isOpen else { return }
        if hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        showFlash(.notice(notice), duration: duration)
    }

    // MARK: - Geometry

    var closedTopRadius: CGFloat { 6 }
    var closedBottomRadius: CGFloat { notchSize.height * 0.4 }
    var openTopRadius: CGFloat { 14 }
    var openBottomRadius: CGFloat { 30 }

    /// Width added on each side of the notch when a live activity is showing.
    var activitySideWidth: CGFloat { notchSize.height + 16 }

    /// Notices carry text, so they push out further than the icon-only activities.
    func sideWidth(for activity: LiveActivity) -> CGFloat {
        if case .notice = activity { return 130 }
        return activitySideWidth
    }

    var activity: LiveActivity? {
        if let flash { return flash }
        if timer.isActive { return .timer }
        if showMediaActivity && media.isPlaying && media.hasTrack { return .media }
        return nil
    }

    var closedSize: CGSize {
        var width = notchSize.width + closedTopRadius * 2
        if let activity { width += sideWidth(for: activity) * 2 }
        return CGSize(width: width, height: notchSize.height)
    }

    var currentSize: CGSize { isOpen ? openSize : closedSize }

    // MARK: - Actions

    func open(tab: NotchTab? = nil, pinned: Bool = false) {
        if let tab { self.tab = tab }
        isPinned = pinned
        guard !isOpen else { return }
        calendar.reload()
        if hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(Self.spring) { isOpen = true }
    }

    func close() {
        isPinned = false
        guard isOpen else { return }
        withAnimation(Self.spring) { isOpen = false }
    }

    func showFlash(_ activity: LiveActivity, duration: TimeInterval = 2.5) {
        flashWork?.cancel()
        withAnimation(Self.spring) { flash = activity }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.spring) { self?.flash = nil }
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
