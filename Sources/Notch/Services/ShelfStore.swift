import AppKit
import UniformTypeIdentifiers

/// Temporary holding area for files dragged onto the notch. Stores references, not copies.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []

    var onAdd: (() -> Void)?

    private let defaultsKey = "shelf.paths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    @discardableResult
    func add(providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(identifier) }
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                DispatchQueue.main.async { self?.add(url) }
            }
        }
        return !fileProviders.isEmpty
    }

    func add(_ url: URL) {
        guard !items.contains(url) else { return }
        items.append(url)
        save()
        onAdd?()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: defaultsKey)
    }
}
