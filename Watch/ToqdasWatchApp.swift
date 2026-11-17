import SwiftUI
import WatchKit

@main
struct ToqdasWatchApp: App {
    @StateObject private var link = WatchLink()
    var body: some Scene {
        WindowGroup {
            WatchGarageView(link: link)
                .environment(\.locale, Locale(identifier: "tr_TR"))
        }
    }
}

struct WatchGarageView: View {
    @ObservedObject var link: WatchLink
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingCommand: String?
    @State private var showCommandConfirmation = false
    @State private var pendingAutomation: WatchProximityAutomationAction?

    private var snapshot: WatchSnapshot? { link.snapshot }

    private func telemetryAge(at now: Date) -> TimeInterval? {
        guard let snapshot, let age = snapshot.telemetryAge else { return nil }
        let elapsed = now.timeIntervalSince1970 - snapshot.updatedAt
        guard elapsed >= 0 else { return nil }
        return age + elapsed
    }

    private func telemetryFresh(at now: Date) -> Bool {
        guard let age = telemetryAge(at: now) else { return false }
        return age < 15
    }

    private func canCommand(at now: Date) -> Bool {
        link.reachable && snapshot?.ready == true && snapshot?.vin.isEmpty == false
            && telemetryFresh(at: now) && snapshot?.locked != nil
    }

    /// Gösterim tazeliği: komut eşiği (15 sn) ile karıştırılmamalıdır.
    /// İmzalı telemetri ~30 sn aralıklı gelir; 15–45 sn arası normal dönem
    /// arasıdır ve "eski" değil "bekleniyor" der (sağlıklı bağlantıda
    /// flap yapmaz). 45 sn üstü gerçekten bayat sayılır.
    private func displayStale(at now: Date) -> Bool {
        guard let age = telemetryAge(at: now) else { return true }
        return age >= 45
    }

    private func lockText(at now: Date) -> String {
        if displayStale(at: now) { return "Kilit verisi eski" }
        if !telemetryFresh(at: now) { return "Kilit durumu bekleniyor" }
        switch snapshot?.locked {
        case true: return "Kilitli"
        case false: return "Kilit açık"
        default: return "Kilit bilinmiyor"
        }
    }

    private func lockSymbol(at now: Date) -> String {
        guard !displayStale(at: now) else { return "questionmark.circle" }
        switch snapshot?.locked {
        case true: return "lock.fill"
        case false: return "lock.open.fill"
        default: return "questionmark.circle"
        }
    }

    private func lockColor(at now: Date) -> Color {
        // U2 ton sözlüğü: karar Core'da (LockVisual), renk saat paletinden.
        let tone = LockVisual.tone(locked: snapshot?.locked, isStale: !telemetryFresh(at: now))
        switch tone {
        case .positive: return .green
        case .warning: return .orange
        case .negative: return .red
        case .neutral: return .secondary
        }
    }

    private func connectionText(at now: Date) -> String {
        if snapshot == nil { return "iPhone’dan veri bekleniyor" }
        if snapshot?.recovering == true { return "iPhone bağlantıyı yeniden kuruyor…" }
        if !link.reachable {
            return "iPhone’a ulaşılamıyor · son veri \(dataAgeText(at: now))"
        }
        if snapshot?.ready != true { return "Dijital anahtar hazır değil" }
        if telemetryFresh(at: now) { return "Telemetri güncel" }
        if let age = telemetryAge(at: now), age < 45 {
            return "İmzalı telemetri bekleniyor (\(Int(age)) sn önce)"
        }
        return "İmzalı telemetri eski (\(dataAgeText(at: now)))"
    }

    private func dataAgeText(at now: Date) -> String {
        guard let age = telemetryAge(at: now) else { return "süre bilinmiyor" }
        if age < 60 { return "\(Int(age)) sn önce" }
        if age < 3600 { return "\(Int(age / 60)) dk önce" }
        return "\(Int(age / 3600)) sa önce"
    }

    private func needsRefresh(at now: Date) -> Bool {
        snapshot != nil && !telemetryFresh(at: now) && link.reachable
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let now = timeline.date
            ScrollView {
                VStack(spacing: 8) {
                    Text(snapshot?.vehicleName ?? "Toqdas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: lockSymbol(at: now))
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(lockColor(at: now))
                        .padding(.top, 2)

                    Text(lockText(at: now))
                        .font(.headline)

                    Text(connectionText(at: now))
                        .font(.caption2)
                        .foregroundStyle(canCommand(at: now) ? .green : .orange)
                        .multilineTextAlignment(.center)

                    if telemetryFresh(at: now), let detailLine {
                        Text(detailLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if needsRefresh(at: now) {
                        Button {
                            link.requestRefresh()
                        } label: {
                            Label("Veriyi yenile", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    automationSection

                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            metric(batteryText, systemImage: batteryIcon)
                            metric(rangeText, systemImage: "road.lanes")
                        }
                        HStack(spacing: 6) {
                            metric(temperatureText, systemImage: "thermometer.medium")
                            metric(telemetryFresh(at: now) ? trunkText : "Bagaj —", systemImage: "car.side")
                        }
                        HStack(spacing: 6) {
                            metric(auxBatteryText, systemImage: "bolt.batteryblock", tint: auxTint)
                            metric(odometerText, systemImage: "speedometer")
                        }
                        HStack(spacing: 6) {
                            metric(snapshot?.lastSeenText ?? "—", systemImage: "eye")
                            metric(snapshot?.sessionQualityText ?? "—",
                                   systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .padding(.top, 2)

                    HStack(spacing: 8) {
                        commandButton("Kilitle", systemImage: "lock.fill", action: "lock", tint: .blue,
                                      enabled: canCommand(at: now))
                        commandButton("Aç", systemImage: "lock.open.fill", action: "unlock", tint: .orange,
                                      enabled: canCommand(at: now))
                    }
                    .padding(.top, 4)

                    HStack(spacing: 6) {
                        commandButton(trunkCommandTitle, systemImage: "car.side", action: trunkAction, tint: .green,
                                      enabled: canCommand(at: now))
                    }
                    .padding(.top, 2)

                    Text(!link.reachable
                        ? "iPhone’a ulaşılamıyor; son bilinen veri gösteriliyor. Komutlar kapalı."
                        : (link.lastResult?.message ?? "İstek iPhone üzerinden iletilir. Kilit onayı araç telemetrisinden gelir."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)

                    // iPhone uygulamasından yapılan son komutun sonucu
                    // (metin iPhone tarafında hazırlandı; 24 saatten eski kayıt süzülür).
                    if let lastCommand = snapshot?.lastCommandText {
                        Text(lastCommand)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Bagaj komutu iPhone üzerinden iletilir; cam komutları kapalı.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog("Yakınlık otomasyonu",
                            isPresented: Binding(
                                get: { pendingAutomation != nil },
                                set: { if !$0 { pendingAutomation = nil } }),
                            titleVisibility: .visible) {
            Button(pendingAutomation == .enable ? "Aç" : "Kapat") {
                if let automation = pendingAutomation {
                    link.request(automation.action, vin: snapshot?.vin ?? "")
                }
                pendingAutomation = nil
            }
            Button("Vazgeç", role: .cancel) { pendingAutomation = nil }
        } message: {
            Text(pendingAutomation?.confirmationText ?? "")
        }
        .confirmationDialog("Araç komutu gönderilsin mi?", isPresented: $showCommandConfirmation,
                            titleVisibility: .visible) {
            Button(confirmationTitle, role: .destructive) {
                if let pendingCommand { request(pendingCommand) }
            }
            Button("Vazgeç", role: .cancel) { pendingCommand = nil }
        } message: {
            Text("Komut iPhone üzerinden iletilir. İşlemden önce dijital anahtarın hazır ve imzalı araç durumu güncel olmalı.")
        }
        .onChange(of: link.lastResult?.id) { _ in
            guard let result = link.lastResult else { return }
            Self.playHaptic(for: result)
        }
        .onAppear { refreshIfStale() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshIfStale() }
        }
        .onChange(of: link.reachable) { reachable in
            if reachable { refreshIfStale() }
        }
    }

    /// Saat açıldığında veri 30 saniyeden eskiyse iPhone'dan tazeleme ister.
    /// Böylece kullanıcı "Veriyi yenile" düğmesini aramak zorunda kalmaz;
    /// istek yalnız telefon erişilebilirse gider (kuyruk yok).
    private func refreshIfStale() {
        guard link.reachable else { return }
        guard WatchSnapshot.isStale(updatedAt: snapshot?.updatedAt, after: 30) else { return }
        link.requestRefresh()
    }

    /// Yakınlık otomasyonu anahtarı: araç komutu göndermez; iPhone'a
    /// uygulama içi geçiş isteği iletir. Durum snapshot'tan gelir.
    private var automationSection: some View {
        let state = snapshot?.proximityEnabled
        let canToggle = link.reachable && snapshot?.vin.isEmpty == false
            && pendingAutomation == nil && !stateIsLoading
        return VStack(spacing: 6) {
            HStack {
                Text("Yakınlık otomasyonu")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(state == true ? "Açık" : state == false ? "Kapalı" : "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state == true ? Color.green : Color.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    pendingAutomation = .enable
                } label: {
                    Label("Aç", systemImage: "location.north.circle")
                        .font(.caption)
                }
                .disabled(!canToggle || state == true)
                Button {
                    pendingAutomation = .disable
                } label: {
                    Label("Kapat", systemImage: "location.slash")
                        .font(.caption)
                }
                .disabled(!canToggle || state == false)
            }
            .buttonStyle(.bordered)
            if !link.reachable {
                Text("Aç/kapat için iPhone erişilebilir olmalı.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Uygulama anahtarı, araç komutlarının READY/telemetri şartına
    /// tabi değildir; yalnız iPhone erişimi yeterlidir.
    private var stateIsLoading: Bool { false }

    /// Komut yanıtına göre dokunsal geri bildirim. "forwarded" başarının
    /// kanıtı değildir; onay telemetriden gelir, bu nedenle bildirim/hata
    /// tipi kullanılır ve kesin onay tıklaması çalınmaz.
    private static func playHaptic(for result: WatchCommandResult) {
        switch result.status {
        case "forwarded":
            WKInterfaceDevice.current().play(.notification)
        case "rejected", "unavailable":
            WKInterfaceDevice.current().play(.failure)
        default:
            break
        }
    }

    private var batteryText: String {
        guard let value = snapshot?.batteryPercent else { return "— %" }
        return "%\(Int(value.rounded()))"
    }

    private var isCharging: Bool {
        snapshot?.chargingState?.lowercased() == "charging"
    }

    private var batteryIcon: String {
        isCharging ? "battery.100percent.bolt" : "battery.100percent"
    }

    private var auxBatteryText: String {
        guard let value = snapshot?.auxiliaryBatteryPercent else { return "12V —" }
        return "12V \(AuxiliaryBatteryPolicy.percentText(value) ?? "—")"
    }

    /// 12 V renk kuralı widget ile aynıdır (`AuxiliaryBatteryPolicy`):
    /// ≤%25 kırmızı, ≤%40 turuncu; eksik veri (nil) renklenmez ("bilgi
    /// yok" ≠ uyarı).
    private var auxTint: Color? {
        guard let assessment = AuxiliaryBatteryPolicy.assess(snapshot?.auxiliaryBatteryPercent) else { return nil }
        return assessment.isCritical ? .red : .orange
    }

    private var odometerText: String {
        guard let value = snapshot?.odometerKM else { return "— km" }
        return "\(Int(value.rounded()).formatted()) km"
    }

    private var powerText: String? {
        switch snapshot?.powerState {
        case 2: return "Bekleme"
        case 3: return "Aksesuar"
        case 4: return "Hazır"
        default: return nil
        }
    }

    private var detailLine: String? {
        guard let snapshot else { return nil }
        var parts: [String] = []
        if let powerText { parts.append("Güç: \(powerText)") }
        if snapshot.doorCount == 4 {
            parts.append(snapshot.openDoors == 0 ? "Kapılar kapalı" : "\(snapshot.openDoors) kapı açık")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var confirmationTitle: String {
        switch pendingCommand {
        case "unlock": return "Kilidi aç"
        case "trunkOpen": return "Bagajı aç"
        case "trunkClose": return "Bagajı kapat"
        default: return "Kilitle"
        }
    }

    private var trunkCommandTitle: String {
        snapshot?.trunkAjar == true ? "Bagaj kapat" : "Bagaj aç"
    }

    private var trunkAction: String {
        snapshot?.trunkAjar == true ? "trunkClose" : "trunkOpen"
    }

    private var rangeText: String {
        guard let value = snapshot?.rangeKM else { return "— km" }
        return "\(Int(value.rounded())) km"
    }

    private var temperatureText: String {
        guard let value = snapshot?.outsideTemperatureC else { return "—°C" }
        return "\(Int(value.rounded()))°C"
    }

    private var trunkText: String {
        switch snapshot?.trunkAjar {
        case true: return "Bagaj açık"
        case false: return "Bagaj kapalı"
        default: return "Bagaj —"
        }
    }

    private func metric(_ text: String, systemImage: String, tint: Color? = nil) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint ?? .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commandButton(_ title: String, systemImage: String, action: String,
                               tint: Color, enabled: Bool) -> some View {
        Button {
            pendingCommand = action
            showCommandConfirmation = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 68)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint("Komut iPhone üzerinden gönderilir; taze imzalı telemetri gerekir.")
    }

    private func previewButton(_ title: String) -> some View {
        Button(title) {}
            .buttonStyle(.bordered)
            .font(.caption2.weight(.semibold))
            .disabled(true)
    }

    private func request(_ action: String) {
        guard let vin = snapshot?.vin, !vin.isEmpty else { return }
        link.request(action, vin: vin)
    }
}
