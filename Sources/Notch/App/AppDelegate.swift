import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let viewModel = NotchViewModel()
    private var controller: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchController(viewModel: viewModel)
        controller.start()
        self.controller = controller
        setUpStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.brightness.restoreAll()
    }

    // MARK: - Menu bar item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Notch")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(viewModel.isOpen ? "Close Notch" : "Open Notch", #selector(toggleNotch)))
        menu.addItem(.separator())
        menu.addItem(item("Open on Hover", #selector(toggleHover), checked: viewModel.openOnHover))
        menu.addItem(item("Show Music Activity", #selector(toggleMediaActivity), checked: viewModel.showMediaActivity))
        menu.addItem(item("Show App Notifications", #selector(toggleNotifications), checked: viewModel.showAppNotifications))
        menu.addItem(item("Haptic Feedback", #selector(toggleHaptics), checked: viewModel.hapticsEnabled))
        menu.addItem(item("Launch at Login", #selector(toggleLogin), checked: LoginItem.isEnabled))
        menu.addItem(.separator())
        menu.addItem(item("Quit Notch", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    @objc private func toggleNotch() { viewModel.isOpen ? viewModel.close() : viewModel.open(pinned: true) }
    @objc private func toggleHover() { viewModel.openOnHover.toggle() }
    @objc private func toggleMediaActivity() { viewModel.showMediaActivity.toggle() }
    @objc private func toggleNotifications() { viewModel.showAppNotifications.toggle() }
    @objc private func toggleHaptics() { viewModel.hapticsEnabled.toggle() }
    @objc private func toggleLogin() { LoginItem.setEnabled(!LoginItem.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }
}
