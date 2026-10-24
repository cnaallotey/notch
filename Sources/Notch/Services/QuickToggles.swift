import AppKit
import CoreAudio
import IOKit.pwr_mgt

/// One-click system controls: keep awake, dark mode, microphone mute and desktop icons,
/// plus screenshot and display-off actions.
final class QuickToggles: ObservableObject {
    @Published private(set) var keepAwake = false
    @Published private(set) var darkMode = false
    @Published private(set) var micMuted = false
    @Published private(set) var desktopIconsHidden = false

    private var sleepAssertion: IOPMAssertionID = 0
    /// Input volume to restore for microphones that have no mute control.
    private var savedInputVolume: Float32?

    init() {
        refresh()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.darkMode = Self.isDarkMode()
        }
    }

    deinit {
        if keepAwake { IOPMAssertionRelease(sleepAssertion) }
    }

    /// Re-reads anything that may have been changed elsewhere.
    func refresh() {
        darkMode = Self.isDarkMode()
        micMuted = Self.inputDevice().map(isMuted) ?? false
        let createDesktop = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString) as? Bool
        desktopIconsHidden = createDesktop == false
    }

    // MARK: - Keep awake

    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(sleepAssertion)
            keepAwake = false
        } else {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Notch Keep Awake" as CFString, &sleepAssertion)
            keepAwake = result == kIOReturnSuccess
        }
    }

    // MARK: - Dark mode

    private static func isDarkMode() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Asks System Events to flip the appearance; macOS asks for Automation permission the first time.
    func toggleDarkMode() {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        darkMode = Self.isDarkMode()
    }

    // MARK: - Microphone

    func toggleMicMute() {
        guard let device = Self.inputDevice() else { return }
        let mute = !isMuted(device)

        var muteAddress = Self.address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(device, &muteAddress),
           AudioObjectIsPropertySettable(device, &muteAddress, &settable) == noErr, settable.boolValue {
            var value: UInt32 = mute ? 1 : 0
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else {
            // No mute switch on this microphone: drop its input volume to zero instead.
            var volumeAddress = Self.address(kAudioDevicePropertyVolumeScalar)
            if mute {
                savedInputVolume = Self.inputVolume(device) ?? 1
            }
            var volume: Float32 = mute ? 0 : (savedInputVolume ?? 1)
            AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        }
        micMuted = isMuted(device)
    }

    private func isMuted(_ device: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyMute)
        if AudioObjectHasProperty(device, &address) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return value != 0
            }
        }
        return Self.inputVolume(device) == 0
    }

    private static func inputVolume(_ device: AudioObjectID) -> Float32? {
        var address = address(kAudioDevicePropertyVolumeScalar)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func inputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: - Desktop icons

    /// Finder only re-reads this setting on launch, so it's relaunched (its windows reopen).
    func toggleDesktopIcons() {
        let hide = !desktopIconsHidden
        run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"])
        run("/usr/bin/killall", ["Finder"])
        desktopIconsHidden = hide
    }

    // MARK: - Actions

    func takeScreenshot() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    }

    func turnDisplayOff() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    private func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
