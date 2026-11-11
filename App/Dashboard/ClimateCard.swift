// Klima ve iklimlendirme kartı
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

// MARK: - Klima

struct ClimateCard: View {
    let isOn: Bool
    let known: Bool
    @Binding var temperature: Double
    let busy: Bool
    let note: String?
    let onToggle: () -> Void
    let onApplyTemperature: () -> Void

    private var subtitle: String {
        if busy { return "İşlem sürüyor…" }
        if !known { return "Durum bilinmiyor · dokunarak dene" }
        return isOn ? "Otomatik iklimlendirme aktif" : "Kapalı"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isOn ? ToggTheme.cyan.opacity(0.2) : ToggTheme.surfaceVariant)
                            .frame(width: 36, height: 36)
                        Image(systemName: "snowflake")
                            .font(.system(size: 18))
                            .foregroundStyle(isOn ? ToggTheme.cyan : ToggTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Klima & İklimlendirme")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        Text(subtitle)
                            .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                    }
                }
                Spacer()
                Button(action: onToggle) {
                    ZStack(alignment: isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(isOn ? ToggTheme.cyan : ToggTheme.outline.opacity(0.5))
                            .frame(width: 52, height: 30)
                        Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                            .padding(3)
                    }
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.6 : 1)
            }

            HStack {
                circleButton("minus") { temperature = max(16, temperature - 0.5) }
                    .disabled(busy)
                Spacer()
                VStack(spacing: 2) {
                    Text("\(TurkishFormat.decimal(temperature, digits: 1))°C")
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(isOn ? ToggTheme.cyan : ToggTheme.muted)
                    Text("Hedef Sıcaklık")
                        .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
                circleButton("plus") { temperature = min(30, temperature + 0.5) }
                    .disabled(busy)
            }

            if isOn {
                Button(action: onApplyTemperature) {
                    Label("Sıcaklığı Uygula", systemImage: "thermometer.medium")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(ToggTheme.cyan)
                        )
                }
                .buttonStyle(.plain)
                .disabled(busy)
            } else {
                Text("Klima açılırken hedef \(TurkishFormat.decimal(temperature, digits: 1))°C uygulanır.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }

            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(ToggTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Komut Togg uzaktan kontrol servisine gönderilir; araç durumu ayrıca doğrulanır.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .toggCardBackground()
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(ToggTheme.surfaceVariant))
        }
        .buttonStyle(.plain)
    }
}
