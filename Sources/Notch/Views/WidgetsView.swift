import SwiftUI

/// Weather, a countdown timer and live system usage, side by side.
struct WidgetsView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 14) {
            WeatherCard(weather: vm.weather)
                .frame(maxWidth: .infinity, alignment: .leading)
            divider
            TimerCard(timer: vm.timer)
                .frame(maxWidth: .infinity, alignment: .leading)
            divider
            StatsCard(stats: vm.stats)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 6)
    }
}

private struct CardTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
    }
}

// MARK: - Weather

private struct WeatherCard: View {
    @ObservedObject var weather: WeatherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CardTitle(text: weather.place ?? "Weather")
            content
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { weather.refreshIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch weather.access {
        case .notDetermined:
            PromptButton(symbol: "location.fill", title: "Show local weather") { weather.requestAccess() }
        case .denied:
            PromptButton(symbol: "lock.fill", title: "Allow location access") { weather.openPrivacySettings() }
        case .granted:
            if let conditions = weather.conditions {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: conditions.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 30))
                        Text("\(Int(conditions.temperature.rounded()))°")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                    }
                    Text(conditions.summary)
                        .font(.system(size: 12, weight: .medium))
                    Text("H:\(Int(conditions.high.rounded()))°  L:\(Int(conditions.low.rounded()))°")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            } else if weather.failed {
                Text("Weather unavailable")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                PromptButton(symbol: "arrow.clockwise", title: "Try again") { weather.refreshIfNeeded() }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Timer

private struct TimerCard: View {
    @ObservedObject var timer: TimerStore

    private let presets = [1, 5, 10, 15, 25, 45]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CardTitle(text: "Timer")
            Group {
                if timer.isActive {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        running(now: context.date)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(presets, id: \.self) { minutes in
                            PillButton(title: "\(minutes)m") { timer.start(minutes: minutes) }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func running(now: Date) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: timer.progress(at: now))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress(at: now))
                Text(TimerStore.format(timer.remaining(at: now)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(timer.isRunning ? .white : .gray)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 6) {
                if timer.isRunning {
                    PillButton(symbol: "pause.fill") { timer.pause() }
                } else {
                    PillButton(symbol: "play.fill") { timer.resume() }
                }
                PillButton(title: "+1m") { timer.add(minutes: 1) }
                PillButton(symbol: "xmark") { timer.cancel() }
            }
            .frame(width: 44)
        }
        .padding(.top, 2)
    }
}

private struct PillButton: View {
    var title: String?
    var symbol: String?
    let action: () -> Void
    @State private var hovering = false

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    init(symbol: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                } else if let title {
                    Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - System stats

private struct StatsCard: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CardTitle(text: "System")
            VStack(spacing: 9) {
                StatRow(label: "CPU", value: "\(Int((stats.cpu * 100).rounded()))%", fraction: stats.cpu, tint: .blue)
                StatRow(label: "Memory",
                        value: "\(Self.gigabytes(stats.memoryUsed)) of \(Self.gigabytes(stats.memoryTotal))",
                        fraction: stats.memory, tint: .green)
                StatRow(label: "Disk",
                        value: ByteCountFormatter.string(fromByteCount: stats.diskFree, countStyle: .file) + " free",
                        fraction: stats.disk, tint: .purple)
            }
            .padding(.top, 2)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { stats.startWatching() }
        .onDisappear { stats.stopWatching() }
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.gray)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint).frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.4), value: fraction)
        }
    }
}
