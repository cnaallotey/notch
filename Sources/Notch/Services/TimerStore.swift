import AppKit

/// A single countdown timer that can be paused, extended and cancelled.
final class TimerStore: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var duration: TimeInterval = 0

    /// Called on the main queue when the countdown reaches zero.
    var onFinish: (() -> Void)?

    private var finishWork: DispatchWorkItem?
    private let maxDuration: TimeInterval = 99 * 60

    var isRunning: Bool { endDate != nil }
    var isActive: Bool { endDate != nil || pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(endDate.timeIntervalSince(date), 0) }
        return pausedRemaining ?? 0
    }

    func progress(at date: Date) -> Double {
        duration > 0 ? remaining(at: date) / duration : 0
    }

    func start(minutes: Int) {
        duration = TimeInterval(minutes * 60)
        pausedRemaining = nil
        schedule(remaining: duration)
    }

    func pause() {
        guard let endDate else { return }
        finishWork?.cancel()
        pausedRemaining = max(endDate.timeIntervalSinceNow, 0)
        self.endDate = nil
    }

    func resume() {
        guard let pausedRemaining else { return }
        self.pausedRemaining = nil
        schedule(remaining: pausedRemaining)
    }

    func add(minutes: Int) {
        let extra = TimeInterval(minutes * 60)
        let remaining = min(remaining(at: Date()) + extra, maxDuration)
        duration = max(duration, remaining)
        if isRunning {
            schedule(remaining: remaining)
        } else if pausedRemaining != nil {
            pausedRemaining = remaining
        }
    }

    func cancel() {
        finishWork?.cancel()
        endDate = nil
        pausedRemaining = nil
    }

    private func schedule(remaining: TimeInterval) {
        finishWork?.cancel()
        endDate = Date().addingTimeInterval(remaining)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.endDate = nil
            NSSound(named: "Glass")?.play()
            self.onFinish?()
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
