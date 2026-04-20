import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Sort

enum ProxySort: String, CaseIterable {
    case none = "По умолчанию"
    case ping = "Пинг"
}

// MARK: - ProxiesView

struct ProxiesView: View {
    @StateObject private var fetcher = SourcesFetcher()
    @State private var appeared    = false
    @State private var qrItem: ProxyItem? = nil
    @State private var searchText  = ""
    @State private var selectedCountry = "Все"
    @State private var selectedSort: ProxySort = .none
    @State private var showFilters = false

    // Notification pill queue
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.top, 56)

                // Search bar
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.1), value: appeared)

                // Sort + filter pills
                filterPills
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.15), value: appeared)

                // Ping progress bar
                if fetcher.isPinging && fetcher.pingTotal > 0 {
                    pingProgressBar
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.top, 8)

                contentArea
            }

            // Toast notification pill
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.13, green: 0.85, blue: 0.47).opacity(0.92))
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12)),
                            removal:   .opacity.combined(with: .offset(y: 12))
                        ))
                        .padding(.bottom, 110)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
            if case .idle = fetcher.loadState { fetcher.loadAll() }
        }
        .sheet(item: $qrItem) { item in QRSheet(item: item) }
        .animation(.easeInOut(duration: 0.2), value: fetcher.isPinging)
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

                HStack(spacing: 4) {
                    Text(totalLabel)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                    if fetcher.availableCount > 0 {
                        Text("|")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.15))
                        Text("Доступно \(fetcher.availableCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.green)
                    }
                }
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: fetcher.proxies.count)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)
            }

            Spacer()

            HStack(spacing: 10) {
                // Ping all
                Button { fetcher.pingAll() } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(pingButtonColor)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: fetcher.isPinging)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppTheme.surface))
                }
                .disabled(fetcher.proxies.isEmpty || fetcher.isPinging)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -8)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.1), value: appeared)

                // Refresh
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

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
            TextField("", text: $searchText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
                .placeholder(when: searchText.isEmpty) {
                    Text("Поиск по серверу, стране…")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.25))
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Filter pills (sort + country)

    private var filterPills: some View {
        HStack(spacing: 8) {
            // Country dropdown
            Menu {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedCountry = "Все"
                    }
                } label: {
                    Label("Все страны", systemImage: selectedCountry == "Все" ? "checkmark" : "globe")
                }
                Divider()
                ForEach(availableCountries, id: \.self) { country in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCountry = country
                        }
                    } label: {
                        Label(country, systemImage: selectedCountry == country ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                    Text(selectedCountry == "Все" ? "Страна" : selectedCountry)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(selectedCountry == "Все" ? .white.opacity(0.5) : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selectedCountry == "Все" ? AppTheme.card : AppTheme.accent.opacity(0.25))
                        .overlay(
                            Capsule()
                                .stroke(selectedCountry == "Все" ? Color.white.opacity(0.08) : AppTheme.accent.opacity(0.45), lineWidth: 0.5)
                        )
                )
            }

            // Sort pills: По умолчанию / Пинг
            HStack(spacing: 6) {
                ForEach(ProxySort.allCases, id: \.self) { sort in
                    let active = selectedSort == sort
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedSort = sort
                        }
                    } label: {
                        Text(sort.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(active ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(active ? AppTheme.surface : .clear)
                                    .overlay(
                                        Capsule()
                                            .stroke(active ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Ping progress bar

    private var pingProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Пингуем серверы…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("\(fetcher.pingProgress) / \(fetcher.pingTotal)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.1), value: fetcher.pingProgress)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 3)
                    let w = fetcher.pingTotal > 0
                        ? geo.size.width * CGFloat(fetcher.pingProgress) / CGFloat(fetcher.pingTotal)
                        : 0
                    Capsule()
                        .fill(LinearGradient(
                            colors: [AppTheme.accent, Color(red: 0.4, green: 0.8, blue: 1.0)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(0, w), height: 3)
                        .animation(.linear(duration: 0.1), value: fetcher.pingProgress)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Content area

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
            let items = filteredProxies
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Ничего не найдено")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        ProxyRow(item: item, onPing: {
                            fetcher.pingSingle(item)
                        }, onQR: {
                            qrItem = item
                        }, onCopy: {
                            UIPasteboard.general.string = item.tgURL
                            showToast("Скопировано")
                        })
                        .padding(.horizontal, 16)
                        .padding(.vertical, 3)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.8)
                                .delay(Double(min(i, 20)) * 0.02),
                            value: appeared
                        )
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    // MARK: - Toast

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = msg
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { toastMessage = nil }
            }
        }
    }

    // MARK: - Computed

    private var filteredProxies: [ProxyItem] {
        var list = fetcher.proxies.filter { $0.pingState != .failed }

        // Search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.server.lowercased().contains(q) ||
                $0.countryName.lowercased().contains(q) ||
                $0.port.contains(q)
            }
        }

        // Country filter
        if selectedCountry != "Все" {
            list = list.filter { $0.countryName == selectedCountry }
        }

        // Sort
        switch selectedSort {
        case .none: break
        case .ping:
            list.sort {
                switch ($0.pingState, $1.pingState) {
                case (.done, .done): return ($0.pingMs ?? 9999) < ($1.pingMs ?? 9999)
                case (.done, _):     return true
                case (_, .done):     return false
                default:             return false
                }
            }

        }
        return list
    }

    private var availableCountries: [String] {
        let all = fetcher.proxies.compactMap { $0.countryName.isEmpty ? nil : $0.countryName }
        return Array(Set(all)).sorted()
    }

    private var totalLabel: String {
        fetcher.proxies.isEmpty ? "Загрузка…" : "\(fetcher.proxies.count) серверов"
    }

    private var pingButtonColor: Color {
        if fetcher.proxies.isEmpty { return .white.opacity(0.2) }
        return fetcher.isPinging ? AppTheme.accent : .white.opacity(0.55)
    }
}


// MARK: - Placeholder modifier

extension View {
    func placeholder<Content: View>(when condition: Bool, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            if condition { content() }
            self
        }
    }
}

// MARK: - ProxyRow

struct ProxyRow: View {
    let item: ProxyItem
    let onPing: () -> Void
    let onQR: () -> Void
    let onCopy: () -> Void

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
            Button { onPing() } label: {
                Label("Ping", systemImage: "antenna.radiowaves.left.and.right")
            }
            Button { onQR() } label: {
                Label("QR-код", systemImage: "qrcode")
            }
            Button { onCopy() } label: {
                Label("Копировать ссылку", systemImage: "doc.on.doc")
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

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }

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
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 24)

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

                if let qr = generateQR(item.tgURL) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                        .scaleEffect(appeared ? 1 : 0.85)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.1), value: appeared)
                }

                Spacer()

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
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                )
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.2), value: appeared)

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
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.accent))
                    }
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 50, height: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.25), value: appeared)
            }
        }
        .onAppear { withAnimation { appeared = true } }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.35))
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.85))
        }
    }

    private func generateQR(_ string: String) -> UIImage? {
        let ctx = CIContext()
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(string.utf8)
        f.correctionLevel = "M"
        guard let ci = f.outputImage else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
