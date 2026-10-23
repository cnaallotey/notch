import AppKit

// Private SkyLight (CGS) calls. Windows added to a space created here sit above every
// user Space, so they stay perfectly still while macOS animates between desktops instead
// of being hidden and re-shown like `.canJoinAllSpaces` windows.
private typealias CGSConnectionID = UInt32
private typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)

/// A dedicated, always-visible space that floats above all desktops and full-screen apps.
final class NotchSpace {
    private let connection = _CGSDefaultConnection()
    private let identifier: CGSSpaceID

    init() {
        // The flag must be 1; other values make Finder draw desktop icons into the space.
        identifier = CGSSpaceCreate(connection, 1, nil)
        CGSSpaceSetAbsoluteLevel(connection, identifier, Int(Int32.max))
        CGSShowSpaces(connection, [identifier] as NSArray)
    }

    deinit {
        CGSHideSpaces(connection, [identifier] as NSArray)
        CGSSpaceDestroy(connection, identifier)
    }

    func add(_ window: NSWindow) {
        CGSAddWindowsToSpaces(connection, [window.windowNumber] as NSArray, [identifier] as NSArray)
    }
}
