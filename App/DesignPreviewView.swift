import SwiftUI

/// Tasarım sistemi önizlemesi (F0 doğrulama ekranı).
///
/// Neden var: yeni görsel dil cihazda tek ekranda görülsün — token'lar,
/// durum dili, kartlar, boş durum ve iskelet. **Üretim akışına girmez**:
/// hiçbir veri okumaz, komut göndermez; yalnız `DesignSystem` bileşenlerini
/// sabit örnek değerlerle çizer. Onay sonrası menüden kaldırılabilir.
struct DesignPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toastVisible = true

    var body: some View {
        SheetShell(
            title: "Tasarım önizleme",
            subtitle: "Kurumsal görsel dil: tek kart zemini, tek durum dili, 8pt ızgara.",
            footnote: "Örnek değerler sabittir; bu ekran araç verisi okumaz ve komut göndermez."
        ) {
            VStack(alignment: .leading, spacing: DSSpace.lg) {
                SectionHeader(title: "Durum şeridi", subtitle: "Durum dili her ekranda aynı")

                StatusHero(
                    eyebrow: "ARAÇ DURUMU",
                    title: "Kilitli · Hazır",
                    subtitle: "Son imzalı veri 12 sn önce",
                    status: .fresh,
                    statusDetail: "Güncel",
                    metrics: [
                        HeroMetric(label: "Batarya", value: "%64", icon: "battery.75"),
                        HeroMetric(label: "Menzil", value: "312 km", icon: "road.lanes"),
                        HeroMetric(label: "12 V", value: "%78", icon: "bolt.batteryblock")
                    ],
                    footer: "Komut onayı uygulandı anlamına gelmez; sonuç imzalı telemetriden doğrulanır.",
                    primaryTitle: "Veriyi yenile",
                    primaryIcon: "arrow.clockwise",
                    primaryAction: {}
                )

                HStack(spacing: DSSpace.xs) {
                    StatusPill(status: .fresh)
                    StatusPill(status: .waiting)
                    StatusPill(status: .stale)
                    StatusPill(status: .unverified)
                    StatusPill(status: .offline)
                    StatusPill(status: .critical)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                SectionHeader(title: "Öncelik", subtitle: "En fazla üç kart · gerekçe metinli")
                PriorityCard(
                    title: "Bağlantı yok",
                    detail: "Son veri 4 dk önce · iPhone uygulaması arka planda olabilir.",
                    icon: "wifi.slash",
                    severity: .offline,
                    actionTitle: "Yeniden bağlan",
                    action: {}
                )
                PriorityCard(
                    title: "Şarj hedefine %18 kaldı",
                    detail: "Tahmini 42 dk · hız son 15 dakikadan.",
                    icon: "bolt.car",
                    severity: .waiting,
                    actionTitle: "Enerji",
                    action: {}
                )

                SectionHeader(title: "Hızlı kontroller", subtitle: "2 sütun · en az 56pt dokunma hedefi")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DSSpace.sm),
                                    GridItem(.flexible(), spacing: DSSpace.sm)],
                          spacing: DSSpace.sm) {
                    ActionTile(title: "Açık", subtitle: "Kapılar",
                               icon: "lock.open.fill", active: true, tint: DSColor.warning) {}
                    ActionTile(title: "Kapalı", subtitle: "İklimlendirme",
                               icon: "snowflake") {}
                    ActionTile(title: "Kapalı", subtitle: "Arka Bagaj",
                               icon: "car.side.rear.open") {}
                    ActionTile(title: "Hazır", subtitle: "Sürüş",
                               icon: "steeringwheel", active: true, tint: DSColor.accent) {}
                }

                SectionHeader(title: "Veri satırları")
                VStack(spacing: DSSpace.xs) {
                    DataRow(label: "Kilit", value: "Kilitli", detail: "Elle · doğrulandı")
                    Divider().overlay(DSColor.outline.opacity(0.5))
                    DataRow(label: "Şarj hedefi", value: "%80", detail: "Hedefe %18")
                    Divider().overlay(DSColor.outline.opacity(0.5))
                    DataRow(label: "Son komut", value: "Doğrulanamadı",
                            detail: "Bağlantı komuttan önce kapandı", tint: DSColor.warning)
                }
                .padding(DSSpace.md)
                .dsCard()

                SectionHeader(title: "Boş durum ve yükleniyor")
                EmptyState(icon: "car.side",
                           title: "Henüz veri yok",
                           message: "Telefon anahtarı hazır olduğunda araç durumu burada görünür.",
                           actionTitle: "Eşleştirmeyi aç",
                           action: {})
                VStack(spacing: DSSpace.xs) {
                    SkeletonRow()
                    SkeletonRow(height: 10)
                    SkeletonRow(height: 10)
                }
                .padding(DSSpace.md)
                .dsCard()

                if toastVisible {
                    ToastBanner(text: "Tema \"Kurumsal\" olarak güncellendi.",
                                status: .fresh) { toastVisible = false }
                }

                Text("Hareket: \(reduceMotion ? "kapalı (Reduce Motion)" : "açık") · "
                     + "kart girişleri 40 ms aralıkla.")
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(DSColor.muted)
            }
            .dsAppear(index: 0, reduceMotion: reduceMotion)
        }
    }
}
