// Cam ve güvenlik bölümü (BLE cam komutları + desteklenmeyenler)
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

// MARK: - Premium kontroller

struct PremiumControlsSection: View {
    let onWindowCommand: (DashboardCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cam ve Güvenlik")
                .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    windowButton(title: "Yan camları aç", subtitle: "İmzalı BLE komutu",
                                 icon: "rectangle.split.3x3.fill", color: ToggTheme.cyan) {
                        onWindowCommand(.windowsOpen)
                    }
                    windowButton(title: "Yan camları kapat", subtitle: "İmzalı BLE komutu",
                                 icon: "xmark", color: ToggTheme.teal) {
                        onWindowCommand(.windowsClose)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "sun.max")
                        .font(ToggTheme.text(.headline)).foregroundStyle(ToggTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Panoramik cam tavan").font(ToggTheme.text(.caption, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Araç protokolünde komut yok").font(ToggTheme.text(.micro))
                            .foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    Text("Desteklenmiyor")
                        .font(ToggTheme.text(.micro, weight: .bold))
                        .foregroundStyle(ToggTheme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(ToggTheme.muted.opacity(0.15)))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))

                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(ToggTheme.text(.headline)).foregroundStyle(ToggTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nöbetçi (Sentry) güvenlik").font(ToggTheme.text(.caption, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Araç API'sinde açma/kapama yok").font(ToggTheme.text(.micro))
                            .foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    Text("Desteklenmiyor")
                        .font(ToggTheme.text(.micro, weight: .bold))
                        .foregroundStyle(ToggTheme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(ToggTheme.muted.opacity(0.15)))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
            }
            .padding(18)
            .toggCardBackground(24)

            Text("Yan cam komutları onay ister; araç cam konumunu BLE ile doğrulamıyor. Panoramik tavan ve sentry bu uygulamada komut olarak sunulmaz.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func windowButton(title: String, subtitle: String, icon: String,
                              color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(ToggTheme.text(.lead)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(ToggTheme.text(.micro, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Komut onay sorulduktan sonra araca gönderilir")
    }
}
