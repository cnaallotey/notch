import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        let size = vm.currentSize
        let topRadius = vm.isOpen ? vm.openTopRadius : vm.closedTopRadius
        let bottomRadius = vm.isOpen ? vm.openBottomRadius : vm.closedBottomRadius
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)

        ZStack(alignment: .top) {
            if vm.isOpen {
                OpenNotchView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(NotchViewModel.spring.delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            } else {
                ClosedNotchView()
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, topRadius)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .overlay(
            shape
                .stroke(Color.white.opacity(vm.isDropTargeted ? 0.6 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .padding(.horizontal, 1)
        )
        .contentShape(shape)
        .scaleEffect(!vm.isOpen && vm.isHovering ? 1.04 : 1, anchor: .top)
        .shadow(color: .black.opacity(vm.isOpen ? 0.55 : 0), radius: 14, y: 6)
        .onDrop(of: [UTType.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            vm.tab = .shelf
            return vm.shelf.add(providers: providers)
        }
        .onChange(of: vm.isDropTargeted) { targeted in
            if targeted { vm.open(tab: .shelf) }
        }
        .animation(NotchViewModel.spring, value: size)
        .animation(NotchViewModel.spring, value: vm.isHovering)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Closed

private struct ClosedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        ZStack {
            if let activity = vm.activity {
                LiveActivityView(activity: activity)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.open() }
    }
}

// MARK: - Open

private struct OpenNotchView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .frame(height: max(vm.notchSize.height, 30))

            Group {
                switch vm.tab {
                case .home: HomeView()
                case .shelf: ShelfView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }
}
