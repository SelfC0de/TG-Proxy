import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - ProxiesView

struct ProxiesView: View {
    @StateObject private var fetcher = SourcesFetcher()
    @State private var appeared = false
    @State private var qrItem: ProxyItem? = nil

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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
            if case .idle = fetcher.loadState { fetcher.loadAll() }
        }
        .sheet(item: $qrItem) { item in
            QRSheet(item: item)
        }
    }

    // MARK: - Header

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
                Button {
                    fetcher.pingAll()
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
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

                RefreshButton { fetcher.loadAll() }
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppTheme.surface))
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
            LazyVStack(spacing: 0) {
                let visible = fetcher.proxies.filter { $0.pingState != .failed }
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, item in
                    ProxyRow(item: item, onPing: {
                        fetcher.pingSingle(item)
                    }, onQR: {
                        qrItem = item
                    })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.8)
                            .delay(Double(i) * 0.025),
                        value: appeared
                    )
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    // MARK: - Helpers

    private var countLabel: String {
        if fetcher.proxies.isEmpty { return "Загрузка…" }
        let total = fetcher.proxies.count
        let avail = fetcher.availableCount
        if avail > 0 {
            return "\(total) серверов  |  Доступно \(avail)"
        }
        return "\(total) серверов"
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

// MARK: - ProxyRow

struct ProxyRow: View {
    let item: ProxyItem
    let onPing: () -> Void
    let onQR: () -> Void

    @State private var pressed = false
    @State private var showMenu = false

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
                        Text("·").foregroundColor(.white.opacity(0.15))
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
        .background(rowBackground)
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        .contextMenu {
            Button {
                onPing()
            } label: {
                Label("Ping", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button {
                onQR()
            } label: {
                Label("QR-код", systemImage: "qrcode")
            }

            Divider()

            Button {
                guard let url = URL(string: item.tgURL) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("Подключить", systemImage: "paperplane.fill")
            }
        } preview: {
            contextPreview
        }
    }

    // MARK: - Context preview

    private var contextPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.accent)
                Text(item.shortServer)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            HStack(spacing: 16) {
                Label(":\(item.port)", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                if !item.countryName.isEmpty {
                    Label(item.countryName, systemImage: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            if case .done = item.pingState, let ms = item.pingMs {
                Label("\(ms) ms", systemImage: "speedometer")
                    .font(.system(size: 12))
                    .foregroundColor(pingColor(ms))
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(AppTheme.card)
    }

    // MARK: - Row background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
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
            Circle().stroke(color.opacity(0.35), lineWidth: 1.5)
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

// MARK: - QR Sheet

struct QRSheet: View {
    let item: ProxyItem
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 24)

                // Title
                Text("QR-код прокси")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: appeared)

                Text(item.shortServer)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 4)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.05), value: appeared)

                Spacer()

                // QR image
                if let qr = generateQR(item.tgURL) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                        .scaleEffect(appeared ? 1 : 0.85)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.1), value: appeared)
                }

                Spacer()

                // Info rows
                VStack(spacing: 8) {
                    infoRow(label: "Сервер", value: item.shortServer)
                    infoRow(label: "Порт",   value: item.port)
                    if !item.countryName.isEmpty {
                        infoRow(label: "Страна", value: item.countryName)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.2), value: appeared)

                // Buttons
                HStack(spacing: 12) {
                    Button {
                        guard let url = URL(string: item.tgURL) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill").font(.system(size: 14))
                            Text("Подключить").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.accent)
                        )
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.card)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.25), value: appeared)
            }
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private func generateQR(_ string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
