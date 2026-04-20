import SwiftUI

struct ContentView: View {
    @StateObject private var fetcher = ProxyFetcher()
    @State private var selectedTab = 0
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                MainProxyView(fetcher: fetcher)
                    .tag(0)
                ProxiesView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: selectedTab)

            CustomTabBar(selected: $selectedTab)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
                appeared = true
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            tabItem(index: 0, icon: "shield.fill",              label: "Главная")
            tabItem(index: 1, icon: "list.bullet.rectangle.fill", label: "Серверы")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
    }

    private func tabItem(index: Int, icon: String, label: String) -> some View {
        let active = selected == index
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selected = index
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .symbolEffect(.bounce, value: active)
                if active {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: -4)),
                            removal:   .opacity.combined(with: .offset(x: -4))
                        ))
                }
            }
            .foregroundColor(active ? .white : Color.white.opacity(0.35))
            .padding(.horizontal, active ? 16 : 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? AppTheme.accent.opacity(0.25) : .clear)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme

enum AppTheme {
    static let bg      = Color(red: 0.047, green: 0.094, blue: 0.224)
    static let surface = Color(red: 0.09,  green: 0.14,  blue: 0.30)
    static let card    = Color(red: 0.11,  green: 0.17,  blue: 0.33)
    static let accent  = Color(red: 0.22,  green: 0.53,  blue: 0.98)
    static let green   = Color(red: 0.13,  green: 0.85,  blue: 0.47)
    static let amber   = Color(red: 1.0,   green: 0.73,  blue: 0.22)
    static let red     = Color(red: 1.0,   green: 0.33,  blue: 0.33)
}
