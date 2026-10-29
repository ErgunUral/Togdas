import SwiftUI

@main
struct ToqdasWatchApp: App {
    @StateObject private var link = WatchLink()
    var body: some Scene {
        WindowGroup { WatchGarageView(link: link) }
    }
}

struct WatchGarageView: View {
    @ObservedObject var link: WatchLink
    @State private var pendingCommand: String?
    @State private var showCommandConfirmation = false

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

    private func lockText(at now: Date) -> String {
        guard telemetryFresh(at: now) else { return "Kilit verisi eski" }
        switch snapshot?.locked {
        case true: return "Kilitli"
        case false: return "Kilit açık"
        default: return "Kilit bilinmiyor"
        }
    }

    private func lockSymbol(at now: Date) -> String {
        guard telemetryFresh(at: now) else { return "questionmark.circle" }
        switch snapshot?.locked {
        case true: return "lock.fill"
        case false: return "lock.open.fill"
        default: return "questionmark.circle"
        }
    }

    private func lockColor(at now: Date) -> Color {
        guard telemetryFresh(at: now) else { return .secondary }
        switch snapshot?.locked {
        case true: return .green
        case false: return .orange
        default: return .secondary
        }
    }

    private func connectionText(at now: Date) -> String {
        if snapshot == nil { return "iPhone’dan veri bekleniyor" }
        if snapshot?.recovering == true { return "iPhone bağlantıyı yeniden kuruyor…" }
        if !link.reachable { return "iPhone’a ulaşılamıyor" }
        if snapshot?.ready != true { return "Dijital anahtar hazır değil" }
        return telemetryFresh(at: now) ? "Telemetri güncel" : "İmzalı telemetri eski"
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
                        .font(.system(size: 34, weight: .semibold))
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

                    if snapshot?.proximityEnabled == true {
                        Text("Pasif giriş: açık (yalnızca algılama)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

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
                            metric(auxBatteryText, systemImage: "bolt.batteryblock")
                            metric(odometerText, systemImage: "speedometer")
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

                    Text(link.lastResult?.message ?? "İstek iPhone üzerinden iletilir. Kilit onayı araç telemetrisinden gelir.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)

                    Text("Bagaj komutu iPhone üzerinden iletilir; cam komutları kapalı.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
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
        return "12V %\(Int(value.rounded()))"
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

    private func metric(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
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
