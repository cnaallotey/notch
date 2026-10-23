import SwiftUI

struct ShelfView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        let shelf = vm.shelf
        if shelf.items.isEmpty {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(vm.isDropTargeted ? 0.5 : 0.18),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(vm.isDropTargeted ? 0.08 : 0.03)))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 24))
                        Text("Drop files here").font(.system(size: 12, weight: .medium))
                        Text("Drag them back out whenever you need them")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.white.opacity(0.8))
                )
        } else {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url, shelf: shelf)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))

                VStack(spacing: 8) {
                    ShelfActionButton(symbol: "airplayaudio", title: "AirDrop") { shelf.airDrop(shelf.items) }
                    ShelfActionButton(symbol: "trash", title: "Clear") { withAnimation { shelf.clear() } }
                }
            }
        }
    }
}

private struct ShelfItemView: View {
    let url: URL
    @ObservedObject var shelf: ShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 52, height: 52)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation { shelf.remove(url) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.gray.opacity(0.8))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(url) }
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.reveal(url) }
            Button("AirDrop") { shelf.airDrop([url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.path)
    }
}

private struct ShelfActionButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 9, weight: .medium))
            }
            .frame(width: 64, height: 56)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.14 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
