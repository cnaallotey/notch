import SwiftUI

/// Quick toggles on the left, a brightness slider per display on the right.
struct ControlsView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 14) {
            ToggleGrid(toggles: vm.toggles) { vm.close() }
                .frame(width: 204)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)

            DisplayList(brightness: vm.brightness)
        }
    }
}

// MARK: - Quick toggles

private struct ToggleGrid: View {
    @ObservedObject var toggles: QuickToggles
    /// Screenshot and display-off need the notch out of the way.
    let closeNotch: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ToggleTile(symbol: "cup.and.saucer.fill", title: "Awake", isOn: toggles.keepAwake, tint: .orange) {
                toggles.toggleKeepAwake()
            }
            ToggleTile(symbol: "circle.lefthalf.filled", title: "Dark", isOn: toggles.darkMode, tint: .indigo) {
                toggles.toggleDarkMode()
            }
            ToggleTile(symbol: toggles.micMuted ? "mic.slash.fill" : "mic.fill", title: "Mic Off",
                       isOn: toggles.micMuted, tint: .red) {
                toggles.toggleMicMute()
            }
            ToggleTile(symbol: "menubar.dock.rectangle", title: "Hide Icons", isOn: toggles.desktopIconsHidden, tint: .teal) {
                toggles.toggleDesktopIcons()
            }
            ToggleTile(symbol: "camera.viewfinder", title: "Screenshot", isOn: false, tint: .white) {
                closeNotch()
                toggles.takeScreenshot()
            }
            ToggleTile(symbol: "moon.zzz.fill", title: "Display Off", isOn: false, tint: .white) {
                closeNotch()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { toggles.turnDisplayOff() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .onAppear { toggles.refresh() }
    }
}

private struct ToggleTile: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOn ? (tint == .white ? .black : .white) : .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isOn ? tint : Color.white.opacity(hovering ? 0.18 : 0.1)))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isOn ? .white : .gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Displays

private struct DisplayList: View {
    @ObservedObject var brightness: DisplayBrightness

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(brightness.displays) { display in
                    DisplayRow(display: display, minimum: brightness.minimum) { value in
                        brightness.setBrightness(value, for: display.id)
                    } onToggleOverlay: {
                        brightness.setUsesOverlay(!display.usesOverlay, for: display.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct DisplayRow: View {
    let display: ControlledDisplay
    let minimum: Double
    let onChange: (Double) -> Void
    let onToggleOverlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 18))
                .foregroundColor(.gray)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(display.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if display.usesOverlay {
                        Text("Overlay")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    Spacer()
                    Text("\(Int((display.brightness * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.gray)
                }
                HStack(spacing: 8) {
                    Image(systemName: "sun.min.fill").font(.system(size: 10)).foregroundColor(.gray)
                    BrightnessSlider(value: display.brightness, minimum: minimum, onChange: onChange)
                    Image(systemName: "sun.max.fill").font(.system(size: 12)).foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .contextMenu {
            Button("Reset to 100%") { onChange(1) }
            Button(display.usesOverlay ? "Dim with Gamma" : "Dim with Overlay", action: onToggleOverlay)
        }
    }
}

private struct BrightnessSlider: View {
    let value: Double
    let minimum: Double
    let onChange: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - minimum) / (1 - minimum)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(Color.white).frame(width: max(geo.size.width * fraction, 6))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let fraction = min(max(drag.location.x / geo.size.width, 0), 1)
                onChange(minimum + fraction * (1 - minimum))
            })
        }
        .frame(height: hovering ? 8 : 6)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}
