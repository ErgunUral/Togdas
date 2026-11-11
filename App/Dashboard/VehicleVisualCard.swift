// Araç durumu kartı (menzil, pil, kilit, kilometre, dış sıcaklık)
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

// MARK: - Araç kartı

struct VehicleVisualCard: View {
    /// `nil` = veri yok ("—"); 0 = gerçek araç verisi.
    let battery: Int?
    let range: Int?
    let batteryColor: Color
    let updatedAt: Date?
    let lockState: Bool?
    let odometer: Double?
    let outsideTemperature: Double?

    private var lockBadge: (text: String, color: Color, icon: String) {
        switch lockState {
        case true: return ("KİLİTLİ", ToggTheme.green, "lock.fill")
        case false: return ("KİLİT AÇIK", ToggTheme.pink, "lock.open.fill")
        case nil: return ("KİLİT BİLİNMİYOR", ToggTheme.muted, "lock.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: lockBadge.icon).font(.subheadline)
                    Text(lockBadge.text).font(.footnote.weight(.bold))
                }
                .foregroundStyle(lockBadge.color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(lockBadge.color.opacity(0.15)))

                Spacer()

                Text(updatedCaption)
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.body).foregroundStyle(ToggTheme.teal)
                        Text("KALAN MENZİL")
                            .font(.footnote.weight(.semibold)).foregroundStyle(ToggTheme.muted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(range.map { "\($0)" } ?? "—")
                            .font(.largeTitle.weight(.black)).foregroundStyle(.white)
                        Text("KM")
                            .font(.body.weight(.bold)).foregroundStyle(ToggTheme.teal)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.body).foregroundStyle(batteryColor)
                        Text(battery.map { "%\($0)" } ?? "—")
                            .font(.title3.weight(.bold)).foregroundStyle(batteryColor)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(batteryColor.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(batteryColor.opacity(0.4), lineWidth: 1))
                    )
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ToggTheme.surfaceVariant)
                    if let battery {
                        Capsule().fill(batteryColor)
                            .frame(width: geo.size.width * CGFloat(min(max(battery, 0), 100)) / 100)
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Image(systemName: "gauge")
                        .font(.footnote).foregroundStyle(ToggTheme.orange)
                    Text(odometer.map { "\($0.formatted(.number.precision(.fractionLength(0)))) km" } ?? "— km")
                        .font(.footnote.weight(.semibold)).foregroundStyle(ToggTheme.muted)
                }
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium")
                        .font(.footnote).foregroundStyle(ToggTheme.cyan)
                    Text(outsideTemperature.map { "\(Int($0.rounded()))°C" } ?? "—°C")
                        .font(.footnote.weight(.semibold)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [ToggTheme.surfaceVariant, ToggTheme.surface],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(ToggTheme.outline.opacity(0.5), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Araç durumu")
        .accessibilityValue(accessibilitySummary)
    }

    /// Güncellenme satırı: taze veride saat, eski veride toplu yaş bilgisi.
    /// Verinin ne kadar önce geldiği dolaysız yazılır; hiç yoksa "Veri
    /// bekleniyor" yazılır, 0'a sıkıştırılmış sahte değer gösterilmez.
    private var updatedCaption: String {
        guard let updatedAt else { return "Veri bekleniyor" }
        let time = updatedAt.formatted(date: .omitted, time: .shortened)
        let seconds = Date().timeIntervalSince(updatedAt)
        guard seconds >= 300 else { return "Güncellendi \(time)" }
        if seconds < 3_600 {
            return "Güncellendi \(time) · \(max(1, Int(seconds / 60))) dk önce"
        }
        if seconds < 86_400 {
            return "Güncellendi \(time) · \(max(1, Int(seconds / 3_600))) sa önce"
        }
        let day = updatedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "Güncellendi \(day)"
    }

    private var accessibilitySummary: String {
        let lockText = lockBadge.text.lowercased()
        let rangeText = range.map { "\($0) kilometre menzil" } ?? "menzil bilgisi yok"
        let batteryText = battery.map { "batarya yüzde \($0)" } ?? "batarya bilgisi yok"
        let odometerText = odometer.map { "kilometre \(Int($0.rounded()))" } ?? "kilometre bilgisi yok"
        let temperatureText = outsideTemperature.map { "dış sıcaklık \(Int($0.rounded())) derece" } ?? "dış sıcaklık bilgisi yok"
        return [lockText, rangeText, batteryText, odometerText, temperatureText].joined(separator: ", ")
    }
}
