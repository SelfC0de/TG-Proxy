import SwiftUI

struct ProxiesView: View {
    @StateObject private var fetcher = SourcesFetcher()
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.top, 56)

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.top, 12)

                contentArea
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
            if case .idle = fetcher.loadState { fetcher.loadAll() }
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Серверы")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -10)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: appeared)

                Text(countLabel)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: fetcher.proxies.count)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)
            }

            Spacer()

            HStack(spacing: 12) {
                // Ping button
                Button {
                    fetcher.pingAll()
                } label: {
                    Image(systemName: fetcher.isPinging ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(pingButtonColor)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: fetcher.isPinging)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppTheme.surface))
                }
                .disabled(fetcher.proxies.isEmpty || fetcher.isPinging)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -8)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.1), value: appeared)

                // Refresh button
                Button {
                    fetcher.loadAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .rotationEffect(.degrees(isLoading ? 360 : 0))
                        .animation(
                            isLoading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                            value: isLoading
                        )
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppTheme.surface))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -8)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.15), value: appeared)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch fetcher.loadState {
        case .idle:
            Spacer()
        case .loading:
            loadingPlaceholder
        case .done:
            proxyList
        case .error(let msg):
            errorView(msg)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            PulsingDot(color: AppTheme.accent)
            Text("Загружаем серверы…")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .transition(.opacity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundColor(AppTheme.amber)
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .transition(.opacity)
    }

    private var proxyList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                let sources = Array(Set(fetcher.proxies.map { $0.sourceName })).sorted()
                ForEach(Array(sources.enumerated()), id: \.element) { sIdx, src in
                    let items = fetcher.proxies.filter { $0.sourceName == src }
                    Section {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            ProxyRow(item: item)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 3)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 10)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.8)
                                        .delay(Double(sIdx * 4 + i) * 0.03),
                                    value: appeared
                                )
                        }
                    } header: {
                        HStack {
                            Text(src.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.25))
                                .kerning(0.8)
                            Spacer()
                            Text("\(items.count)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.2))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(AppTheme.bg.opacity(0.95))
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    // MARK: - Helpers

    private var countLabel: String {
        fetcher.proxies.isEmpty ? "Загрузка…" : "\(fetcher.proxies.count) серверов"
    }

    private var isLoading: Bool {
        if case .loading = fetcher.loadState { return true }
        return false
    }

    private var pingButtonColor: Color {
        if fetcher.proxies.isEmpty { return .white.opacity(0.2) }
        return fetcher.isPinging ? AppTheme.accent : .white.opacity(0.55)
    }
}

// MARK: - Proxy Row

struct ProxyRow: View {
    let item: ProxyItem
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 12) {
            pingIndicator
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.shortServer)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(":\(item.port)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    if !item.countryName.isEmpty {
                        Text("·")
                            .foregroundColor(.white.opacity(0.15))
                        Text(item.countryName)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }

            Spacer()

            connectButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
    }

    // MARK: - Ping indicator

    @ViewBuilder
    private var pingIndicator: some View {
        switch item.pingState {
        case .idle:
            pingRing(color: Color.white.opacity(0.12), label: "—", labelColor: .white.opacity(0.25))
        case .pinging:
            ZStack {
                Circle().stroke(AppTheme.accent.opacity(0.2), lineWidth: 1.5)
                ProgressView().progressViewStyle(.circular).tint(AppTheme.accent.opacity(0.6)).scaleEffect(0.55)
            }
        case .done:
            let ms = item.pingMs ?? 9999
            let c = pingColor(ms)
            pingRing(color: c, label: ms < 1000 ? "\(ms)" : ">1s", labelColor: c)
        case .failed:
            pingRing(color: AppTheme.red, label: "✕", labelColor: AppTheme.red)
        }
    }

    private func pingRing(color: Color, label: String, labelColor: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1.5)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(labelColor)
        }
    }

    private func pingColor(_ ms: Int) -> Color {
        ms < 150 ? AppTheme.green : ms < 400 ? AppTheme.amber : AppTheme.red
    }

    // MARK: - Connect button

    private var connectButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { pressed = false }
                guard let url = URL(string: item.tgURL) else { return }
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
    }
}
