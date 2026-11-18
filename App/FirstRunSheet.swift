import SwiftUI

/// İlk açılış tanıtımı: 3 adım, atlanabilir, bir kez gösterilir.
///
/// Neden gerekli: gezinme değişti (Araç / Enerji / Bakım / Hesap) ve
/// "Güncel · Bekleniyor · Eski veri · Doğrulanamadı" dili ilk bakışta
/// anlaşılmalı. Ağ erişimi yok, komut göndermez, veri toplamaz.
struct FirstRunSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let message: String
    }

    private let pages: [Page] = [
        Page(icon: "car.side.fill",
             title: "Tek bakışta araç",
             message: "Araç sekmesi durumu, en fazla üç öncelikli başlığı ve hızlı kontrolleri gösterir. Klima, cam, yakınlık ve güvenlik ayarları \"Tüm kontroller\" altında."),
        Page(icon: "checkmark.seal",
             title: "Dürüst durum dili",
             message: "Güncel · Bekleniyor · Eski veri · Doğrulanamadı. \"Hazır\" yalnız araçtan gelen imzalı telemetriden gelir; komut onayı (ack) uygulandı anlamına gelmez."),
        Page(icon: "bolt.car.fill",
             title: "Enerji ve bakım ayrı",
             message: "Şarj, hedef ve geçmiş Enerji'de; 12 V, lastik ve servis Bakım'da. Widget ve saat aynı veriyi gösterir, kendi başına komut göndermez.")
    ]

    var body: some View {
        VStack(spacing: DSSpace.lg) {
            HStack {
                Text("Toqdas")
                    .font(ToggTheme.text(.caption, weight: .bold))
                    .foregroundStyle(DSColor.accent)
                Spacer()
                Button("Atla") { finish() }
                    .font(ToggTheme.text(.caption, weight: .bold))
                    .foregroundStyle(DSColor.muted)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.skip")
            }

            Spacer(minLength: 0)

            Image(systemName: pages[page].icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(DSColor.accent)
                .accessibilityHidden(true)

            Text(pages[page].title)
                .font(ToggTheme.text(.display, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(pages[page].message)
                .font(ToggTheme.text(.body))
                .foregroundStyle(DSColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DSSpace.xxs) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? DSColor.accent : DSColor.outline)
                        .frame(width: index == page ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            Button {
                if page + 1 < pages.count {
                    withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page + 1 < pages.count ? "Devam" : "Başla")
                    .font(ToggTheme.text(.body, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                        .fill(DSColor.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.continue")
        }
        .padding(DSSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background.ignoresSafeArea())
    }

    private func finish() {
        dismiss()
    }
}
