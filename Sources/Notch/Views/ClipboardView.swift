import SwiftUI

/// Recently copied text. Click a snippet to copy it again.
struct ClipboardView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        ClipboardList(clipboard: vm.clipboard)
    }
}

private struct ClipboardList: View {
    @ObservedObject var clipboard: ClipboardStore
    @State private var copiedText: String?

    var body: some View {
        if clipboard.items.isEmpty {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 24))
                        Text("Nothing copied yet").font(.system(size: 12, weight: .medium))
                        Text("Text you copy shows up here so you can paste it again")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.white.opacity(0.8))
                )
        } else {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(clipboard.items) { item in
                            ClipboardItemView(item: item, isCopied: copiedText == item.text) {
                                copy(item)
                            } onRemove: {
                                withAnimation { clipboard.remove(item) }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))

                ShelfActionButton(symbol: "trash", title: "Clear") { withAnimation { clipboard.clear() } }
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func copy(_ item: ClipboardItem) {
        let text = item.text
        withAnimation(.easeOut(duration: 0.15)) {
            clipboard.copy(item)
            copiedText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedText == text { withAnimation { copiedText = nil } }
        }
    }
}

private struct ClipboardItemView: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11))
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if isCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Text(item.date, format: .relative(presentation: .named))
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(width: 150)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(hovering ? 0.12 : 0.06)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.gray.opacity(0.8))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Remove", action: onRemove)
        }
        .help("Click to copy")
    }
}
