import SwiftUI

/// Capsule tab bar that floats over the content, replacing the system tab bar chrome.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 66)
        .background(.ultraThinMaterial, in: Capsule())
        .background(PrivionyxTheme.Colors.glassFill, in: Capsule())
        .overlay(Capsule().stroke(PrivionyxTheme.Colors.tabBarStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 26, y: 10)
        .padding(.horizontal, 20)
    }

    private func item(for tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            withAnimation(.snappy(duration: 0.22)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 19, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isSelected ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.tertiaryInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(PrivionyxTheme.Colors.accentSoft)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    @Previewable @State var selection: AppTab = .dashboard

    ZStack(alignment: .bottom) {
        PrivionyxTheme.appBackground.ignoresSafeArea()
        FloatingTabBar(selection: $selection)
    }
}
