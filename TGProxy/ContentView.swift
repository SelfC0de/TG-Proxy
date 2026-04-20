import SwiftUI

struct ContentView: View {
    @StateObject private var fetcher = ProxyFetcher()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainProxyView(fetcher: fetcher)
                .tabItem {
                    Label("Главная", systemImage: "shield.fill")
                }
                .tag(0)

            ProxiesView()
                .tabItem {
                    Label("Серверы", systemImage: "list.bullet.rectangle.fill")
                }
                .tag(1)
        }
        .accentColor(Color(red: 0.38, green: 0.74, blue: 1.0))
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.05, green: 0.10, blue: 0.24, alpha: 1)
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.35)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.35)
            ]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Main tab

struct MainProxyView: View {
    @ObservedObject var fetcher: ProxyFetcher

    var body: some View {
        ZStack {
            Color(red: 0.059, green: 0.118, blue: 0.275)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 20)
                Spacer()
                mainCard
                    .padding(.horizontal, 20)
                Spacer()
                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .onAppear { fetcher.fetch() }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(.white)
            }
            Text("TG Proxy")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            Text("SelfCode")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private var mainCard: some View {
        Group {
            switch fetcher.state {
            case .idle:
                progressCard(progress: 0, label: "Подготовка...")
            case .loading(let p):
                progressCard(progress: p, label: progressLabel(p))
            case .ready(let data):
                readyCard(data: data)
            case .error(let msg):
                errorCard(message: msg)
            }
        }
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func progressCard(progress: Double, label: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                HStack {
                    Text("Загрузка прокси")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.38, green: 0.74, blue: 1.0))
                            .frame(width: geo.size.width * CGFloat(progress), height: 5)
                            .animation(.linear(duration: 0.1), value: progress)
                    }
                }
                .frame(height: 5)
            }
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.6))
                    .scaleEffect(0.8)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(20)
    }

    private func readyCard(data: ProxyData) -> some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(Color(red: 0.13, green: 0.85, blue: 0.47))
                    .frame(width: 8, height: 8)
                Text("Прокси получен")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.13, green: 0.85, blue: 0.47))
                Spacer()
            }
            Divider().background(Color.white.opacity(0.1))
            infoRow(label: "Сервер", value: shortServer(data.server))
            infoRow(label: "Порт",   value: data.port)
        }
        .padding(20)
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.22))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                guard case .ready(let data) = fetcher.state,
                      let url = URL(string: data.tgURL) else { return }
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill").font(.system(size: 15))
                    Text("Подключить Telegram").font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(connectBgColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!isReady)

            Button { fetcher.fetch() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14))
                    Text("Обновить прокси").font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
    }

    private var isReady: Bool {
        if case .ready = fetcher.state { return true }
        return false
    }

    private var connectBgColor: Color {
        isReady ? Color(red: 0.15, green: 0.47, blue: 0.96) : Color.white.opacity(0.08)
    }

    private func progressLabel(_ p: Double) -> String {
        let secs = Int(ceil((1.0 - p) * 5.0))
        return secs > 0 ? "Ещё ~\(secs) сек" : "Получаем данные..."
    }

    private func shortServer(_ s: String) -> String {
        let parts = s.split(separator: ".")
        if parts.count > 3 { return "…" + parts.dropFirst().joined(separator: ".") }
        return s
    }
}
