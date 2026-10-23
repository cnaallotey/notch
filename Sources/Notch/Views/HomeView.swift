import SwiftUI

struct HomeView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 14) {
            NowPlayingView(media: vm.media)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)

            CalendarCard(calendar: vm.calendar)
                .frame(width: 214)
        }
    }
}

// MARK: - Now playing

struct NowPlayingView: View {
    @ObservedObject var media: MediaController

    var body: some View {
        if media.hasTrack {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(media.artist.isEmpty ? media.album : media.artist)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(1)

                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        progress(at: context.date)
                    }
                    .padding(.top, 4)

                    controls
                }
            }
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 92, height: 92)
                    .overlay(Image(systemName: "music.note").font(.system(size: 28)).foregroundColor(.gray))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Play something in Music, Spotify\nor your browser to control it here.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = media.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.08)
                        .overlay(Image(systemName: "music.note").font(.system(size: 26)).foregroundColor(.gray))
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: media.accent.opacity(0.35), radius: 10)

            if let icon = media.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .offset(x: 6, y: 6)
            }
        }
        .onTapGesture { media.activateSourceApp() }
        .help("Open source app")
    }

    private func progress(at date: Date) -> some View {
        let elapsed = media.elapsed(at: date)
        let fraction = media.duration > 0 ? elapsed / media.duration : 0
        return VStack(spacing: 3) {
            SeekBar(fraction: fraction, tint: media.accent) { media.seek(toFraction: $0) }
            HStack {
                Text(Self.format(elapsed))
                Spacer()
                Text("-" + Self.format(max(media.duration - elapsed, 0)))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.gray)
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            ControlButton(symbol: "backward.fill", size: 14) { media.previous() }
            ControlButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 20) { media.togglePlayPause() }
            ControlButton(symbol: "forward.fill", size: 14) { media.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct SeekBar: View {
    let fraction: Double
    let tint: Color
    let onSeek: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(tint).frame(width: geo.size.width * fraction)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                onSeek(min(max(value.location.x / geo.size.width, 0), 1))
            })
        }
        .frame(height: hovering ? 6 : 4)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 28)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
