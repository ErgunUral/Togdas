// Araç sağlığı kartı (12 V, lastikler, iç sıcaklık, uyarılar)
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

// MARK: - Sağlık

struct VehicleHealthCard: View {
    let auxiliaryBattery: Double?
    /// "Son 3 gün (12 V): %72 · %74 · —" satırı; kayıt yoksa nil.
    let auxiliaryHistoryLine: String?
    let tires: [TireReading]
    let insideTemperature: Double?
    let brakeWarning: Bool?
    let engineWarning: Bool?
    let driveMode: String?
    let chargingState: String
    let updatedAt: Date?

    @State private var showTireSettings = false
    /// Reduce Motion: lastik ayarı genişleme animasyonunu kapatır (U3).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tireLowThreshold = TirePressurePolicy.default.lowThresholdPSI

    private var tirePressureAvailable: Bool {
        tires.contains { $0.pressurePSI != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 12 V akü düşükse belirgin uyarı bandı.
            // Kural: AuxiliaryBatteryPolicy.assess; eksik veri asla uyarıya
            // dönüştürülmez ("—" gösteriminde kalır).
            if let batteryAlert = AuxiliaryBatteryPolicy.assess(auxiliaryBattery) {
                batteryAlertBanner(batteryAlert)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(ToggTheme.green.opacity(0.2)).frame(width: 38, height: 38)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(ToggTheme.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Araç Sağlığı & Lastik Basınçları")
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                    Text(updatedAt.map { "Canlı API • \($0.formatted(date: .omitted, time: .shortened))" }
                         ?? "Canlı veri bekleniyor")
                        .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Lastik Basınçları (TPMS - PSI)")
                        .font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) { showTireSettings.toggle() }
                    } label: {
                        Label("Eşik", systemImage: "slider.horizontal.3")
                            .font(ToggTheme.text(.micro, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ToggTheme.teal)
                    // Denetim bulgusu: "Eşik" hedefi 44 pt'den küçüktü.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                HStack(spacing: 10) {
                    tireBox(.frontLeft)
                    tireBox(.frontRight)
                    tireBox(.rearLeft)
                    tireBox(.rearRight)
                }
                if showTireSettings {
                    tireThresholdEditor
                } else {
                    Text(tireThresholdSummary)
                        .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                }
                if !tirePressureAvailable {
                    Text("Lastik basıncı verisi şu an gelmiyor. Araç uyanıkken tekrar deneyin; eksik değer 0 PSI olarak gösterilmez.")
                        .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.orange)
                }
            }

            HStack(spacing: 12) {
                statBox(title: "12 V Akü", value: auxiliaryBattery.flatMap { AuxiliaryBatteryPolicy.percentText($0) } ?? "—",
                        icon: "car.battery", color: ToggTheme.teal)
                statBox(title: "Şarj Durumu", value: chargingState,
                        icon: "bolt.circle", color: ToggTheme.cyan)
            }

            if let auxiliaryHistoryLine {
                Text(auxiliaryHistoryLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ToggTheme.muted)
                    .accessibilityLabel("Son üç gün 12 volt akü geçmişi")
            }

            HStack(spacing: 12) {
                statBox(title: "İç Sıcaklık",
                        value: insideTemperature.map { "\(Int($0.rounded()))°C" } ?? "—",
                        icon: "thermometer.medium", color: ToggTheme.orange)
                statBox(title: "Sürüş Modu", value: driveMode ?? "—",
                        icon: "steeringwheel", color: ToggTheme.teal)
            }

            if brakeWarning != nil || engineWarning != nil {
                HStack(spacing: 12) {
                    warningBox(title: "Fren Uyarısı", warning: brakeWarning)
                    warningBox(title: "Motor Uyarısı", warning: engineWarning)
                }
            }

            Text("Lastik basınç/sıcaklıkları, 12 V akü, şarj durumu, iç sıcaklık, sürüş modu ve fren/motor uyarıları VehicleInfo API'sinden gösterilir. Lastik basıncı kPa'dan PSI'ye çevrilir; uyarı alanları yalnızca API'de dolu geldiğinde gösterilir. Batarya, menzil, kilometre ve dış sıcaklık üst araç kartındadır.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .toggCardBackground()
    }

    private var tireThresholdSummary: String {
        let policy = TirePressureSettings().policy
        return "Uyarı eşiği \(Int(policy.lowThresholdPSI.rounded())) PSI · kritik \(Int(policy.criticalThresholdPSI.rounded())) PSI"
    }

    private var tireThresholdEditor: some View {
        let policy = TirePressureSettings().policy
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Uyarı eşiği").font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text("\(Int(tireLowThreshold.rounded())) PSI")
                    .font(ToggTheme.text(.caption, weight: .semibold)).foregroundStyle(ToggTheme.teal)
            }
            Slider(
                value: $tireLowThreshold,
                in: TirePressurePolicy.minimumAllowedThreshold...TirePressurePolicy.maximumAllowedThreshold,
                step: 1
            ) { editing in
                if !editing { saveTireThreshold() }
            }
            .tint(ToggTheme.teal)
            Text("Kritik eşik otomatik olarak \(Int(max(TirePressurePolicy.minimumAllowedThreshold, tireLowThreshold - 4).rounded())) PSI olur. Değerler PSI'dır.")
                .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
            Button("Varsayılana dön (\(Int(TirePressurePolicy.default.lowThresholdPSI)) PSI)") {
                tireLowThreshold = TirePressurePolicy.default.lowThresholdPSI
                saveTireThreshold()
            }
            .font(ToggTheme.text(.micro)).buttonStyle(.bordered)
        }
        .onAppear { tireLowThreshold = policy.lowThresholdPSI }
    }

    private func saveTireThreshold() {
        let policy = TirePressurePolicy(
            lowThresholdPSI: tireLowThreshold,
            criticalThresholdPSI: tireLowThreshold - 4
        )
        TirePressureSettings().policy = policy
    }

    private func tireBox(_ position: TirePosition) -> some View {
        let reading = tires.first { $0.position == position }
        let severity = reading.flatMap { TirePressureSettings().policy.severity(for: $0) }
        let tint: Color = severity == .critical ? ToggTheme.pink : (severity == .low ? ToggTheme.orange : .white)
        return VStack(spacing: 4) {
            Image(systemName: severity == nil ? "car.side.fill" : "exclamationmark.triangle.fill")
                .font(ToggTheme.text(.lead))
                .foregroundStyle(severity == nil ? ToggTheme.teal : tint)
            Text(reading?.pressurePSI.map { "\(TurkishFormat.decimal($0, digits: 1)) PSI" } ?? "— PSI")
                .font(ToggTheme.text(.body, weight: .bold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(reading?.temperatureC.map { "\(Int($0.rounded()))°C" } ?? "—°C")
                .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
            Text(position.title).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.title)
        .accessibilityValue(tireAccessibilityValue(reading, severity: severity))
    }

    private func tireAccessibilityValue(_ reading: TireReading?, severity: TirePressurePolicy.Severity?) -> String {
        guard let reading, let psi = reading.pressurePSI else { return "basınç bilgisi yok" }
        let pressure = "\(TurkishFormat.decimal(psi, digits: 1)) PSI"
        let temperature = reading.temperatureC.map { ", \(Int($0.rounded())) derece" } ?? ""
        let warning: String
        switch severity {
        case .critical: warning = ", kritik düşük basınç"
        case .low: warning = ", düşük basınç"
        case nil: warning = ""
        }
        return pressure + temperature + warning
    }

    /// 12 V akü uyarı bandı: uyarı "belirgin" olması için kartın en üstünden
    /// başlar, renk (kritik: kırmızı, uyarı: turuncu) ve kalın metinle
    /// ayrışır; ekran okuyucu için tam cümle etiketi içerir. VIN/token
    /// içermez; mesafe/menzil iddiası taşımaz.
    @ViewBuilder
    private func batteryAlertBanner(_ assessment: AuxiliaryBatteryAssessment) -> some View {
        let critical = assessment.isCritical
        let color: Color = critical ? ToggTheme.red : ToggTheme.orange
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: critical ? "battery.0percent" : "battery.25percent")
                    .font(ToggTheme.text(.title, weight: .bold))
                    .foregroundStyle(color)
                Text(critical ? "12 V Akü Kritik Düşük" : "12 V Akü Zayıf")
                    .font(ToggTheme.text(.body, weight: .heavy))
                    .foregroundStyle(color)
                Spacer()
                Text("%\(assessment.percent)")
                    .font(ToggTheme.text(.lead, weight: .heavy))
                    .foregroundStyle(color)
            }
            Text(critical
                 ? "12 V akü %\(assessment.percent). Uzun parklarda araç açılmayabilir; en kısa sürede şarj/bakım kontrolü önerilir."
                 : "12 V akü %\(assessment.percent). Yakında şarj/bakım kontrolü önerilir.")
                .font(ToggTheme.text(.caption, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(color.opacity(0.8), lineWidth: 1.5)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(critical ? "Uyarı: 12 volt akü kritik düşük" : "Uyarı: 12 volt akü zayıf")
        .accessibilityValue("Akü yüzde \(assessment.percent)")
    }

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(ToggTheme.text(.title)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                Text(value).font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func warningBox(title: String, warning: Bool?) -> some View {
        let active = warning == true
        let color = active ? ToggTheme.red : ToggTheme.green
        return HStack(spacing: 10) {
            Image(systemName: active ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(ToggTheme.text(.title)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                Text(warning == nil ? "—" : (active ? "Uyarı var" : "Yok"))
                    .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(warning == nil ? "bilgi yok" : (active ? "uyarı var" : "uyarı yok"))
    }
}
