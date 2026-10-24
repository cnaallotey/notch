import Foundation
import IOBluetooth

/// Reports Bluetooth devices (AirPods, headphones, keyboards, mice…) connecting and disconnecting.
final class BluetoothMonitor: NSObject {
    /// Called on the main queue: (device name, SF Symbol, connected).
    var onChange: ((String, String, Bool) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()

    func start() {
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Registering reports every device that's already connected; only announce new ones.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        report(device, connected: true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        report(device, connected: false)
    }

    private func report(_ device: IOBluetoothDevice, connected: Bool) {
        let name = device.name ?? "Bluetooth device"
        let symbol = Self.symbol(for: device, name: name)
        DispatchQueue.main.async { self.onChange?(name, symbol, connected) }
    }

    private static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("beats") { return "beats.headphones" }

        switch device.deviceClassMajor {
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio):
            return "headphones"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral):
            let minor = device.deviceClassMinor
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse" }
            return "gamecontroller"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone):
            return "iphone"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}
