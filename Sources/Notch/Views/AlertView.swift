import SwiftUI

/// An iOS-style notification banner that drops out of the notch. Click it to open the sending app.
struct AlertView: View {
    @EnvironmentObject var vm: NotchViewModel
    let alert: NotchAlert

    var body: some View {
        VStack(spacing: 0) {
            // Keep everything below the (real or virtual) notch.
            Color.clear.frame(height: vm.notchSize.height)

            HStack(alignment: .center, spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(alert.appName.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        Spacer()
                        Text("now")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    Text(alert.title.isEmpty ? alert.appName : alert.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !alert.subtitle.isEmpty {
                        Text(alert.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    if !alert.body.isEmpty {
                        Text(alert.body)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(alert.subtitle.isEmpty ? 2 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .foregroundColor(.white)
        .contentShape(Rectangle())
        .onTapGesture { vm.openAlertSource() }
        .help("Open \(alert.appName)")
    }

    @ViewBuilder
    private var icon: some View {
        if let image = alert.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: alert.symbol ?? "app.badge.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(alert.bundleID.hasSuffix("focus") ? Color.indigo : Color.gray))
                .padding(2)
        }
    }
}
