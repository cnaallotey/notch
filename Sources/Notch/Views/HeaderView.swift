import SwiftUI

/// Top row of the open notch. The middle stays empty so nothing hides behind a real notch.
struct HeaderView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(NotchTab.allCases) { tab in
                    TabButton(tab: tab, isSelected: vm.tab == tab) {
                        withAnimation(.easeInOut(duration: 0.18)) { vm.tab = tab }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: vm.notchSize.width)

            HStack(spacing: 10) {
                if vm.battery.hasBattery {
                    BatteryBadge(battery: vm.battery)
                }
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                SettingsMenu()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .foregroundColor(.white)
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 22)
                .foregroundColor(isSelected ? .white : .gray)
                .background(Color.white.opacity(isSelected ? 0.16 : (hovering ? 0.08 : 0)), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.rawValue.capitalized)
    }
}

private struct BatteryBadge: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HStack(spacing: 4) {
            Text("\(battery.level)%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.gray)
            Image(systemName: battery.symbolName)
                .font(.system(size: 13))
                .symbolRenderingMode(.palette)
                .foregroundStyle(battery.isCharging ? Color.green : (battery.level <= 20 ? Color.red : Color.white),
                                 Color.white.opacity(0.4))
        }
    }
}

private struct SettingsMenu: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        Menu {
            Toggle("Open on Hover", isOn: $vm.openOnHover)
            Toggle("Show Music Activity", isOn: $vm.showMediaActivity)
            Toggle("Haptic Feedback", isOn: $vm.hapticsEnabled)
            Toggle("Launch at Login", isOn: Binding(get: { LoginItem.isEnabled }, set: { LoginItem.setEnabled($0) }))
            Divider()
            Button("Quit Notch") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
