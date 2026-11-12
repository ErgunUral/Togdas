import SwiftUI
import WidgetKit

/// iOS 17+ `.containerBackground` zorunluluğu; iOS 16'da eski `.background`
/// kullanımı korunur. Aksi halde WidgetKit console'a
/// "Please adopt containerBackground API" uyarısını basar.
private extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background(color)
        }
    }
}

private struct VehicleStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: VehicleWidgetSnapshot?
    var command: VehicleCommandStatus?
}

private struct VehicleStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> VehicleStatusEntry {
        VehicleStatusEntry(date: .now, snapshot: nil, command: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (VehicleStatusEntry) -> Void) {
        completion(VehicleStatusEntry(date: .now, snapshot: VehicleWidgetSnapshotStore.load(), command: VehicleCommandStatusStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleStatusEntry>) -> Void) {
        let entry = VehicleStatusEntry(
            date: .now,
            snapshot: VehicleWidgetSnapshotStore.load(),
            // 24 saatten eski komut kayıtları isStale kuralıyla ekranda çıkarılmaz.
            command: VehicleCommandStatusStore.load()
        )
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct ToqdasVehicleStatusWidget: Widget {
    static let kind = VehicleWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VehicleStatusProvider()) { entry in
            VehicleStatusView(snapshot: entry.snapshot, command: entry.command)
        }
        .configurationDisplayName("Toqdas Araç Durumu")
        .description("Kilit, batarya, menzil ve bu ayın şarj harcamasını gösterir. Komut göndermez.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ToqdasWidgetBundle: WidgetBundle {
    var body: some Widget { ToqdasVehicleStatusWidget() }
}

/// Widget hedefinde App paletiyle aynı hex değerleri (karar Core'daki
/// VisualTone'da; hexler App hedefindeki `Color(hex:)` ile aynı sabitler).
private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

private struct VehicleStatusView: View {
    let snapshot: VehicleWidgetSnapshot?
    /// Son komut sonucu; 24 saatten eski/bilgi yok ise satır çıkarılmaz.
    let command: VehicleCommandStatus?

    /// Durum tonu → widget paleti (U2 sözlüğü; Dashboard ile aynı karar,
    /// Core'daki VisualTone'dan çözülür: yeşil=canlı · turuncu=eski/açık ·
    /// gri=bilgi yok).
    private func toneColor(_ tone: VisualTone) -> Color {
        switch tone {
        case .positive: return Color(hex: 0x00E676)
        case .warning: return Color(hex: 0xFF9100)
        case .negative: return Color(hex: 0xFF5252)
        case .neutral: return Color(hex: 0x9AA7BD)
        }
    }

    private var lockTint: Color {
        let stale = snapshot?.lockDataIsStale ?? true
        return toneColor(LockVisual.tone(locked: snapshot?.locked, isStale: stale))
    }

    var body: some View {
        Group {
            if let snapshot {
                widgetContent(snapshot)
            } else {
                unavailableContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBackground(Color(red: 0.025, green: 0.075, blue: 0.13))
    }

    @ViewBuilder
    private func widgetContent(_ snapshot: VehicleWidgetSnapshot) -> some View {
        if contextFamily == .systemMedium {
            mediumContent(snapshot)
        } else {
            smallContent(snapshot)
        }
    }

    @Environment(\.widgetFamily) private var contextFamily

    private func smallContent(_ snapshot: VehicleWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header(snapshot.vehicleName, extra: snapshot.displayVehicleCountBadge)
            Label(snapshot.displayLock, systemImage: snapshot.locked == true ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(lockTint)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                metric("Battery.100", snapshot.displayBattery)
                metric("road.lanes", snapshot.displayRange)
            }
            metric("car.battery", snapshot.displayAuxiliaryBattery, tint: auxiliaryTint(snapshot))
            metric("bolt.car.fill", "Bu ay \(snapshot.displayChargeSpend)")
            freshness(snapshot)
        }
        .accessibilityElement(children: .combine)
    }

    private func mediumContent(_ snapshot: VehicleWidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header(snapshot.vehicleName, extra: snapshot.displayVehicleCountBadge)
                Label(snapshot.displayLock, systemImage: snapshot.locked == true ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(lockTint)
                    .lineLimit(1)
                freshness(snapshot)
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 10) {
                metric("Battery.100", snapshot.displayBattery)
                metric("car.battery", snapshot.displayAuxiliaryBattery, tint: auxiliaryTint(snapshot))
                if !snapshot.auxiliaryHistoryPercents.isEmpty {
                    auxiliaryHistoryChart(snapshot)
                }
                metric("road.lanes", snapshot.displayRange)
                metric("bolt.car.fill", "Bu ay \(snapshot.displayChargeSpend)")
                metric("gauge", snapshot.displayOdometer)
                metric("thermometer.medium", snapshot.displayOutsideTemperature)
                if let commandText = command?.displayText {
                    Text(commandText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .accessibilityLabel("Son komut sonucu: \(command?.verificationText ?? "bilgi yok")")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOQDAS").font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(Color.cyan)
            Text("Araç verisi yok")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text("Uygulamayı açıp araç verilerini yenileyin.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func header(_ name: String, extra: String?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color.cyan).frame(width: 6, height: 6)
            Text(name.isEmpty ? "Toqdas" : name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            if let extra {
                Text("· \(extra)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private func metric(_ icon: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint ?? Color.cyan)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? .white).lineLimit(1)
        }
    }

    /// 12 V akü rengi: `AuxiliaryBatteryPolicy` kuralı — ≤%25 kırmızı,
    /// ≤%40 turuncu; bilgi yoksa normal renk ("—" asla uyarıya dönüştürülmez).
    private func auxiliaryTint(_ snapshot: VehicleWidgetSnapshot) -> Color? {
        guard let assessment = AuxiliaryBatteryPolicy.assess(snapshot.auxiliaryBatteryPercent) else {
            return nil
        }
        return assessment.isCritical ? Color(red: 1.0, green: 0.32, blue: 0.24) : Color.orange
    }

    /// Son 7 günün 12 V mini grafiği (eskiden yeniye; sağdaki en son gün).
    /// Kaydı olmayan gün çukur çizilir ve erişilebilirlikte "bilgi yok"
    /// anlatılır — asla 0 gibi gösterilmez. Salt okunur: widget komut
    /// göndermez, VIN içermez.
    private func auxiliaryHistoryChart(_ snapshot: VehicleWidgetSnapshot) -> some View {
        let values = Array(snapshot.auxiliaryHistoryPercents.suffix(7))
        let labels = values.map { value -> String in
            guard let value, value.isFinite else { return "bilgi yok" }
            return AuxiliaryBatteryPolicy.percentText(value) ?? "bilgi yok"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text("Son 7 gün (12 V)")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(value))
                        .frame(width: 14, height: barHeight(value))
                        .frame(height: 18, alignment: .bottom)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Son 7 gün 12 V akü: \(labels.joined(separator: ", "))")
    }

    private func barHeight(_ value: Double?) -> CGFloat {
        guard let value, value.isFinite, value >= 0, value <= 100 else { return 3 }
        return max(4, CGFloat(value) / 100 * 18)
    }

    private func barColor(_ value: Double?) -> Color {
        guard let value, value.isFinite, value >= 0, value <= 100 else {
            return .white.opacity(0.18)
        }
        if let assessment = AuxiliaryBatteryPolicy.assess(value) {
            return assessment.isCritical
                ? Color(red: 1.0, green: 0.32, blue: 0.24)
                : Color.orange.opacity(0.85)
        }
        return .cyan.opacity(0.85)
    }

    private func freshness(_ snapshot: VehicleWidgetSnapshot) -> some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.freshnessIsLive ? "dot.radiowaves.left.and.right" : "clock")
            Text(snapshot.freshnessText)
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(snapshot.freshnessIsLive ? toneColor(.positive) : toneColor(.warning))
        .lineLimit(1)
    }
}
