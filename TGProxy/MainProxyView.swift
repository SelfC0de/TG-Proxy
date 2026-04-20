import SwiftUI

struct MainProxyView: View {
    @ObservedObject var fetcher: ProxyFetcher
    @State private var appeared = false
    @State private var showQR = false
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 56)

                Spacer()

                stateCard
                    .padding(.horizontal, 20)

                Spacer()

                bottomButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 96)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                appeared = true
            }
            fetcher.fetch()
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color(red: 0.13, green: 0.85, blue: 0.47).opacity(0.92)))
                    .padding(.bottom, 110)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal:   .opacity.combined(with: .offset(y: 12))
                    ))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastMessage)
        .sheet(isPresented: $showQR) {
            if case .ready(let data) = fetcher.state {
                QRSheet(item: ProxyItem(
                    server: data.server,
                    port: data.port,
                    tgURL: data.tgURL,
                    sourceName: "mtproto.ru"
                ))
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
                    .frame(width: 72, height: 72)
                    .scaleEffect(appeared ? 1.18 : 1)
                    .opacity(appeared ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                        value: appeared
                    )
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(-35))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -12)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

            Text("Telegram Proxy")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: appeared)

            Link("SelfCode", destination: URL(string: "https://t.me/selfcode_dev")!)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.3))
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
        }
    }

    // MARK: - State card

    @ViewBuilder
    private var stateCard: some View {
        switch fetcher.state {
        case .idle:
            loadingCard(progress: 0, label: "Подготовка…")
        case .loading(let p):
            loadingCard(progress: p, label: countdownLabel(p))
        case .ready(let data):
            readyCard(data: data)
        case .error(let msg):
            errorCard(msg: msg)
        }
    }

    // MARK: - Loading card

    private func loadingCard(progress: Double, label: String) -> some View {
        VStack(spacing: 18) {
            HStack {
                Text("Получение прокси")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: Int(progress * 100))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent, Color(red: 0.4, green: 0.8, blue: 1.0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(progress)), height: 4)
                        .animation(.linear(duration: 0.15), value: progress)
                }
            }
            .frame(height: 4)

            HStack(spacing: 8) {
                PulsingDot(color: AppTheme.accent)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: label)
            }
        }
        .padding(20)
        .background(cardBackground)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
    }

    // MARK: - Ready card

    private func readyCard(data: ProxyData) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(AppTheme.green).frame(width: 7, height: 7)
                    .shadow(color: AppTheme.green.opacity(0.6), radius: 4)
                Text("Прокси активен")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.green)
                Spacer()
                Text("mtproto.ru")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.bottom, 14)

            Divider().background(Color.white.opacity(0.07)).padding(.bottom, 14)

            InfoRow(label: "Сервер", value: shortServer(data.server))
            Spacer().frame(height: 10)
            InfoRow(label: "Порт", value: data.port)

            // Ping row
            if fetcher.autoPingState != .idle {
                Spacer().frame(height: 10)
                HStack {
                    Text("Ping")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    pingLabel
                }
            }
        }
        .padding(20)
        .background(cardBackground)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal:   .opacity.combined(with: .offset(y: -8))
        ))
    }

    @ViewBuilder
    private var pingLabel: some View {
        switch fetcher.autoPingState {
        case .idle:
            EmptyView()
        case .pinging:
            HStack(spacing: 6) {
                ProgressView().progressViewStyle(.circular).tint(AppTheme.accent).scaleEffect(0.6)
                Text("Проверка…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
        case .done:
            let ms = fetcher.autoPingMs ?? 0
            let color = ms < 150 ? AppTheme.green : ms < 400 ? AppTheme.amber : AppTheme.red
            Text("\(ms) ms")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        case .failed:
            Text("Недоступен")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.red)
        }
    }

    // MARK: - Error card

    private func errorCard(msg: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundColor(AppTheme.amber)
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(20)
        .background(cardBackground)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Card background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }

    // MARK: - Bottom buttons

    private var bottomButtons: some View {
        VStack(spacing: 10) {
            // Connect
            Button {
                guard case .ready(let data) = fetcher.state,
                      let url = URL(string: data.tgURL) else { return }
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill").font(.system(size: 14))
                    Text("Подключить Telegram").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isReady ? AppTheme.accent : Color.white.opacity(0.07))
                        .animation(.easeInOut(duration: 0.3), value: isReady)
                )
            }
            .disabled(!isReady)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)

            // Ping + QR row
            HStack(spacing: 10) {
                // Ping button
                Button {
                    guard case .ready(let data) = fetcher.state else { return }
                    fetcher.autoPingState = .pinging
                    fetcher.autoPingMs = nil
                    Task {
                        let port = UInt16(data.port) ?? 443
                        let ms = await PingService.shared.ping(server: data.server, port: port)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            fetcher.autoPingMs = ms
                            fetcher.autoPingState = ms != nil ? .done : .failed
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .medium))
                            .symbolEffect(.variableColor.iterative.reversing, isActive: fetcher.autoPingState == .pinging)
                        Text("Ping")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(isReady ? .white.opacity(0.65) : .white.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                }
                .disabled(!isReady || fetcher.autoPingState == .pinging)

                // QR button
                Button {
                    showQR = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 13, weight: .medium))
                        Text("QR")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(isReady ? .white.opacity(0.65) : .white.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                }
                .disabled(!isReady)

                // Copy button
                Button {
                    guard case .ready(let data) = fetcher.state else { return }
                    UIPasteboard.general.string = data.tgURL
                    showMainToast("Скопировано")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isReady ? .white.opacity(0.65) : .white.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                }
                .disabled(!isReady)
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.22), value: appeared)

            RefreshButton(label: "Обновить") {
                fetcher.fetch()
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.27), value: appeared)
        }
    }

    // MARK: - Helpers

    private func showMainToast(_ msg: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toastMessage = msg }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { toastMessage = nil }
            }
        }
    }

    private var isReady: Bool {
        if case .ready = fetcher.state { return true }
        return false
    }

    private func countdownLabel(_ p: Double) -> String {
        let s = Int(ceil((1.0 - p) * 10.0))
        let retry = fetcher.retryCount
        if retry > 0 { return "Попытка \(retry + 1) из 6…" }
        return s > 0 ? "Ещё ~\(s) сек" : "Получаем данные…"
    }

    private func shortServer(_ s: String) -> String {
        let parts = s.split(separator: ".")
        return parts.count > 3 ? "…" + parts.dropFirst().joined(separator: ".") : s
    }
}

// MARK: - Shared components

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

// MARK: - Refresh button (single 360° spin on tap, no repeat)

struct RefreshButton: View {
    var label: String = ""
    let action: () -> Void

    @State private var angle: Double = 0
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
                angle += 360
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                busy = false
            }
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .rotationEffect(.degrees(angle))
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundColor(.white.opacity(0.38))
            .frame(maxWidth: label.isEmpty ? nil : .infinity)
            .frame(height: label.isEmpty ? 36 : 40)
        }
        .buttonStyle(.plain)
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 14, height: 14)
                .scaleEffect(pulsing ? 1.6 : 1)
                .opacity(pulsing ? 0 : 0.7)
                .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulsing)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .onAppear { pulsing = true }
    }
}
