import SwiftUI

/// The compact content that hugs either side of the closed notch.
struct LiveActivityView: View {
    @EnvironmentObject var vm: NotchViewModel
    let activity: LiveActivity

    var body: some View {
        let side = vm.activitySideWidth
        let iconSize = vm.notchSize.height - 8

        HStack(spacing: 0) {
            leading(iconSize: iconSize)
                .frame(width: side, alignment: .center)
            Spacer(minLength: vm.notchSize.width)
            trailing(iconSize: iconSize)
                .frame(width: side, alignment: .center)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func leading(iconSize: CGFloat) -> some View {
        switch activity {
        case .media:
            Group {
                if let artwork = vm.media.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").resizable().scaledToFit().padding(3)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .power(_, let pluggedIn):
            Image(systemName: pluggedIn ? "bolt.fill" : "powerplug")
                .font(.system(size: iconSize * 0.7, weight: .bold))
                .foregroundColor(pluggedIn ? .green : .gray)
        case .shelf:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: iconSize * 0.7))
                .foregroundColor(.accentColor)
        }
    }

    @ViewBuilder
    private func trailing(iconSize: CGFloat) -> some View {
        switch activity {
        case .media:
            AudioBars(isPlaying: vm.media.isPlaying, tint: vm.media.accent, maxHeight: iconSize)
        case .power(let level, let pluggedIn):
            Text("\(level)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(pluggedIn ? .green : .white)
        case .shelf(let count):
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

struct AudioBars: View {
    let isPlaying: Bool
    let tint: Color
    let maxHeight: CGFloat
    @State private var levels: [CGFloat] = [0.4, 0.8, 0.55, 0.9]

    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: max(3, levels[index] * maxHeight))
            }
        }
        .frame(height: maxHeight)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                levels = levels.map { _ in isPlaying ? .random(in: 0.25...1) : 0.2 }
            }
        }
    }
}
