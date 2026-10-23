import Darwin
import Foundation

/// CPU, memory and startup-disk usage, sampled every two seconds while something is watching.
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var diskFree: Int64 = 0

    let memoryTotal = ProcessInfo.processInfo.physicalMemory

    private var timer: Timer?
    private var watchers = 0
    private var previousTicks: (used: UInt64, total: UInt64)?

    var memory: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var disk: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }

    func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        watchers = max(watchers - 1, 0)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        previousTicks = nil
    }

    private func sample() {
        if let cpu = cpuUsage() { self.cpu = cpu }
        if let memory = memoryInUse() { memoryUsed = memory }
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                                                 .volumeAvailableCapacityForImportantUsageKey]) {
            diskTotal = Int64(values.volumeTotalCapacity ?? 0)
            diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }

    /// Share of CPU time spent busy since the previous sample, across all cores.
    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = info.cpu_ticks
        let used = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3) // user + system + nice
        let total = used + UInt64(ticks.2)                              // + idle
        defer { previousTicks = (used, total) }
        guard let previous = previousTicks, total > previous.total else { return nil }
        return Double(used - previous.used) / Double(total - previous.total)
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    private func memoryInUse() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let appPages = UInt64(stats.internal_page_count) - UInt64(min(stats.purgeable_count, stats.internal_page_count))
        let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(vm_kernel_page_size)
    }
}
