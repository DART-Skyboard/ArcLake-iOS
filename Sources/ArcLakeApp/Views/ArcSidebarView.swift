
import SwiftUI

public struct ArcSidebarView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Binding var sidebarCollapsed: Bool

    public var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            // Tab content
            ZStack {
                switch labVM.activeTab {
                case .molecule: MoleculeTabView()
                case .physics:  PhysicsTabView()
                case .math:     MathTabView()
                case .arc:      ArcTabView()
                case .env:      EnvTabView()
                case .log:      LogTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            // Collapse button
            Button {
                withAnimation(.spring()) { sidebarCollapsed = true }
            } label: {
                Image(systemName: "chevron.right.circle")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 28)
            }

            ForEach(ArcTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        labVM.activeTab = tab
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.rawValue)
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundColor(labVM.activeTab == tab ? themeVM.accent : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(labVM.activeTab == tab ?
                        themeVM.accent.opacity(0.1) : Color.clear)
                }
            }
        }
        .background(Color.black.opacity(0.4))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(themeVM.accent.opacity(0.3)),
            alignment: .bottom
        )
    }
}
