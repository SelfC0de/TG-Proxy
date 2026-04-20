import SwiftUI

struct ProxiesView: View {
    @StateObject private var fetcher = SourcesFetcher()

    var body: some View {
        ZStack {
            Color(red: 0.059, green: 0.118, blue: 0.275).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Прокси-серверы")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(fetcher.proxies.count) серверов")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        if fetcher.isPinging {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white.opacity(0.6))
                                .scaleEffect(0.75)
                        } else {
                            Button {
                                fetcher.pingAll()
                            } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 16))
                                    .foregroundColor(fetcher.proxies.isEmpty ? .white.opacity(0.25) : .white.opacity(0.7))
                            }
                            .disabled(fetcher.proxies.isEmpty)
                        }

                        Button {
                            fetcher.loadAll()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.7))
                                .rotationEffect(.degrees(isLoading ? 360 : 0))
                                .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()
                    .background(Color.white.opacity(0.08))

                // Content
                switch fetcher.loadState {
                case .idle:
                    idlePlaceholder
                case .loading:
                    loadingView
                case .done:
                    proxyList
                case .error(let msg):
                    errorView(msg)
                }
            }
        }
        .onAppear {
            if case .idle = fetcher.loadState { fetcher.loadAll() }
        }
    }

    // MARK: - Idle
    private var idlePlaceholder: some View {
        Spacer()
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.5))
            Text("Загружаем серверы...")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
    }

    // MARK: - Error
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.22))
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Proxy list
    private var proxyList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Group by source
                let sources = Array(Set(fetcher.proxies.map { $0.sourceName })).sorted()
                ForEach(sources, id: \.self) { src in
                    let items = fetcher.proxies.filter { $0.sourceName == src }
                    Section {
                        ForEach(items) { item in
                            ProxyRowView(item: item)
                        }
                    } header: {
                        HStack {
                            Text(src)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.35))
                                .textCase(.uppercase)
                            Spacer()
                            Text("\(items.count)")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var isLoading: Bool {
        if case .loading = fetcher.loadState { return true }
        return false
    }
}

// MARK: - Row

struct ProxyRowView: View {
    let item: ProxyItem

    var body: some View {
        HStack(spacing: 12) {
            // Ping indicator
            pingBadge

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.shortServer)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(":\(item.port)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                    if !item.countryName.isEmpty {
                        Text("·")
                            .foregroundColor(.white.opacity(0.2))
                        Text(item.countryName)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }

            Spacer()

            // Connect button
            Button {
                guard let url = URL(string: item.tgURL) else { return }
                UIApplication.shared.open(url)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.15, green: 0.47, blue: 0.96).opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var pingBadge: some View {
        switch item.pingState {
        case .idle:
            pingCircle(color: Color.white.opacity(0.15), label: "—")
        case .pinging:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.4))
                    .scaleEffect(0.6)
            }
        case .done:
            let ms = item.pingMs ?? 9999
            let color: Color = ms < 150 ? Color(red: 0.13, green: 0.85, blue: 0.47)
                             : ms < 400 ? Color(red: 1.0,  green: 0.78, blue: 0.22)
                             : Color(red: 1.0, green: 0.35, blue: 0.35)
            pingCircle(color: color, label: ms < 1000 ? "\(ms)" : ">1s", small: ms >= 1000)
        case .failed:
            pingCircle(color: Color(red: 1.0, green: 0.35, blue: 0.35), label: "✕")
        }
    }

    private func pingCircle(color: Color, label: String, small: Bool = false) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 1.5)
                .frame(width: 44, height: 44)
            Text(label)
                .font(.system(size: small ? 9 : 11, weight: .medium))
                .foregroundColor(color)
        }
    }
}
