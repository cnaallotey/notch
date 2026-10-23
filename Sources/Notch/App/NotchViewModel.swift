import AppKit
import Combine
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        }
    }
}

/// Compact "live activity" shown beside the closed notch.
enum LiveActivity: Equatable {
    case media
    case power(level: Int, pluggedIn: Bool)
    case shelf(count: Int)
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

    private var flashWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        for publisher in [media.objectWillChange, battery.objectWillChange, shelf.objectWillChange, calendar.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        battery.onPowerSourceChange = { [weak self] pluggedIn, level in
            self?.showFlash(.power(level: level, pluggedIn: pluggedIn))
        }
        shelf.onAdd = { [weak self] in
            guard let self, !self.isOpen else { return }
            self.showFlash(.shelf(count: self.shelf.items.count))
        }
    }

    // MARK: - Geometry

    var closedTopRadius: CGFloat { 6 }
    var closedBottomRadius: CGFloat { notchSize.height * 0.4 }
    var openTopRadius: CGFloat { 14 }
    var openBottomRadius: CGFloat { 30 }

    /// Width added on each side of the notch when a live activity is showing.
    var activitySideWidth: CGFloat { notchSize.height + 16 }

    var activity: LiveActivity? {
        if let flash { return flash }
        if showMediaActivity && media.isPlaying && media.hasTrack { return .media }
        return nil
    }

    var closedSize: CGSize {
        var width = notchSize.width + closedTopRadius * 2
        if activity != nil { width += activitySideWidth * 2 }
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
