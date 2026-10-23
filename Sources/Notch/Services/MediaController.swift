import AppKit
import SwiftUI

/// Reads and controls system-wide "Now Playing" (Music, Spotify, browsers…) through the
/// private MediaRemote framework, loaded at runtime. Works on macOS 13 and 14.
final class MediaController: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var elapsedTimestamp = Date()
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var appPID: pid_t = 0

    var hasTrack: Bool { !title.isEmpty }

    private enum Command: Int32 {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetBoolFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private let getInfo: GetInfoFn?
    private let getIsPlaying: GetBoolFn?
    private let getPID: GetPIDFn?
    private let sendCommand: SendCommandFn?
    private let setElapsed: SetElapsedFn?
    private var lastArtworkTitle = ""

    init() {
        let url = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        let bundle = CFBundleCreate(kCFAllocatorDefault, url)

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let bundle, let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        getInfo = load("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getIsPlaying = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetBoolFn.self)
        getPID = load("MRMediaRemoteGetNowPlayingApplicationPID", as: GetPIDFn.self)
        sendCommand = load("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        setElapsed = load("MRMediaRemoteSetElapsedTime", as: SetElapsedFn.self)
        load("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)?(DispatchQueue.main)

        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    // MARK: - Reading state

    func refresh() {
        getInfo?(DispatchQueue.main) { [weak self] dict in
            self?.apply(info: (dict as NSDictionary?) as? [String: Any] ?? [:])
        }
        getIsPlaying?(DispatchQueue.main) { [weak self] playing in
            self?.isPlaying = playing
        }
        getPID?(DispatchQueue.main) { [weak self] pid in
            guard let self, pid != self.appPID else { return }
            self.appPID = pid
            self.appIcon = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.icon : nil
        }
    }

    private func apply(info: [String: Any]) {
        let newTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        title = newTitle
        artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        elapsedTimestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date()

        if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, let image = NSImage(data: data) {
            artwork = image
            accent = Self.accentColor(for: image)
            lastArtworkTitle = newTitle
        } else if newTitle != lastArtworkTitle {
            artwork = nil
            accent = .white
        }
    }

    /// Elapsed time extrapolated to `date`, since MediaRemote only reports it on changes.
    func elapsed(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let value = isPlaying ? elapsed + date.timeIntervalSince(elapsedTimestamp) : elapsed
        return min(max(value, 0), duration)
    }

    // MARK: - Controls

    func togglePlayPause() {
        isPlaying.toggle()
        send(.togglePlayPause)
    }

    func next() { send(.nextTrack) }
    func previous() { send(.previousTrack) }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        let time = duration * fraction
        setElapsed?(time)
        elapsed = time
        elapsedTimestamp = Date()
    }

    func activateSourceApp() {
        guard appPID > 0 else { return }
        NSRunningApplication(processIdentifier: appPID)?.activate(options: [.activateIgnoringOtherApps])
    }

    private func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.refresh() }
    }

    // MARK: - Artwork colour

    /// Average colour of the artwork, lifted so it stays visible on black.
    private static func accentColor(for image: NSImage) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return .white }

        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.2, 0.85), brightness: max(brightness, 0.75))
    }
}
