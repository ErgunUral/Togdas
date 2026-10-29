import SwiftUI

extension Notification.Name {
    /// Şarj harcaması önbelleği güncellendiğinde pano kartını tazeler.
    static let chargingBudgetDidChange = Notification.Name("toqdas.chargingBudgetDidChange")
}

/// Panodaki aylık şarj bütçesi kartı.
///
/// Harcama yalnız Seyahatname > Şarjlar > Bu ay açıldığında sunucudan gelir ve
/// `ChargingSpendStore` içine yazılır; kart bu önbelleği okur. Limit VIN bazlıdır.
/// Bütçe ödeme/kesinti yapmaz; %80/%100 eşiklerinde ayda bir bildirim tetikler.
struct ChargingBudgetCard: View {
    let vin: String

    @State private var limit = 0.0
    @State private var spent: Double?
    @State private var updatedAt: Date?

    private var store: ChargingSpendStore { ChargingSpendStore(vin: vin) }
    private var hasLimit: Bool { limit > 0 }
    private var hasSpend: Bool { spent != nil }

    var body: some View {
        let budget = ChargingBudget(limitTRY: limit, spentTRY: spent ?? 0)
        let tint: Color = budget.status == .exceeded ? ToggTheme.pink
            : (budget.status == .nearLimit ? ToggTheme.orange : ToggTheme.teal)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Şarj Bütçesi", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(monthTitle(ChargingSpendStore.monthString()))
                    .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hasSpend ? ChargingBudget.money(budget.spentTRY) : "—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(hasSpend ? tint : ToggTheme.muted)
                    .monospacedDigit()
                if hasLimit {
                    Text("/ \(ChargingBudget.money(limit))")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
                if hasLimit, hasSpend {
                    Text(budget.percentText)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                        .monospacedDigit()
                }
            }
            if hasLimit, hasSpend {
                ProgressView(value: budget.ratio)
                    .tint(tint)
                Text(budget.message)
                    .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 4) {
                HStack {
                    Text("Aylık limit").font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(hasLimit ? ChargingBudget.money(limit) : "Kapalı")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .monospacedDigit()
                }
                Slider(value: limitBinding, in: 0...30_000, step: 500)
                    .tint(ToggTheme.teal)
                    .accessibilityLabel("Aylık şarj bütçesi limiti")
                    .accessibilityValue(hasLimit ? ChargingBudget.money(limit) : "Kapalı")
            }
            if !hasSpend {
                Text("Bu ay harcama verisi yok. Seyahatname → Şarj → Bu ay görünümü açıldığında sunucudan gelen gerçek tutar buraya işlenir.")
                    .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let updatedAt {
                Text("Son güncelleme: \(updatedText(updatedAt)). Harcama sunucunun gerçek şarj toplamıdır; tahmin değildir.")
                    .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Bütçe yalnız uyarı amaçlıdır; ödeme veya otomatik kesinti yapılmaz. %80 ve %100 eşiklerinde ayda bir bildirim gönderilir.")
                .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).toggCardBackground()
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .chargingBudgetDidChange)) { _ in
            reload()
        }
    }

    private var limitBinding: Binding<Double> {
        Binding(
            get: { limit },
            set: { newValue in
                limit = newValue
                let budgetStore = self.store
                budgetStore.setMonthlyLimit(newValue)
                guard newValue > 0 else { return }
                ChargingBudgetNotifier.notifyIfNeeded(budget: budgetStore.budget(), vin: vin, store: budgetStore)
            }
        )
    }

    private func reload() {
        let budgetStore = self.store
        limit = budgetStore.monthlyLimit()
        let snapshot = budgetStore.snapshot()
        spent = snapshot?.amountTRY
        updatedAt = snapshot?.updatedAt
    }

    private func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let monthNumber = Int(parts[1]),
              (1...12).contains(monthNumber) else { return month }
        let names = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                     "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
        return "\(names[monthNumber - 1]) \(parts[0])"
    }

    private func updatedText(_ date: Date) -> String {
        TurkishFormat.date(date, format: "d MMM HH:mm")
    }
}
