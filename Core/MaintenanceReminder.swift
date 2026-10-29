import Foundation

/// VIN bazlı bakım hatırlatıcısı.
///
/// Bu tip yalnızca veri tutar; bildirim planlama uygulama katmanındadır
/// (`MaintenanceNotifier`). Böylece Core katmanı UserNotifications'a bağlı
/// kalmadan test edilebilir.
struct MaintenanceItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var dueKm: Double
    var done: Bool
    /// Bakım tamamlandığında gerçek km (odometer o anki değeri).
    var completedAtKm: Double?

    init(id: UUID = UUID(), title: String, dueKm: Double, done: Bool = false, completedAtKm: Double? = nil) {
        self.id = id
        self.title = title
        self.dueKm = dueKm
        self.done = done
        self.completedAtKm = completedAtKm
    }

    /// Kalan km. Tamamlanmışsa 0.
    func remainingKm(currentOdometer: Double) -> Double {
        max(0, dueKm - currentOdometer)
    }
}

final class MaintenanceStore {
    private let vin: String
    private let defaults: UserDefaults
    private var key: String { "toqdas.maintenance.\(vin)" }

    init(vin: String, defaults: UserDefaults = .standard) {
        self.vin = vin
        self.defaults = defaults
    }

    var items: [MaintenanceItem] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([MaintenanceItem].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    @discardableResult
    func add(title: String, dueKm: Double) -> MaintenanceItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = MaintenanceItem(title: trimmed.isEmpty ? "Bakım" : trimmed, dueKm: max(0, dueKm))
        items.append(item)
        return item
    }

    func markDone(_ id: UUID, atOdometer odometer: Double? = nil) {
        var list = items
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].done = true
        list[idx].completedAtKm = odometer
        items = list
    }

    func markPending(_ id: UUID) {
        var list = items
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].done = false
        list[idx].completedAtKm = nil
        items = list
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Yaklaşan bakımlar: bitmemiş ve kalan km `within` sınırının altında.
    func upcoming(currentOdometer: Double, within: Double = 500) -> [MaintenanceItem] {
        items
            .filter { !$0.done && $0.remainingKm(currentOdometer: currentOdometer) <= within }
            .sorted { $0.dueKm < $1.dueKm }
    }

    /// Gecikmiş bakımlar.
    func overdue(currentOdometer: Double) -> [MaintenanceItem] {
        items.filter { !$0.done && $0.dueKm <= currentOdometer }.sorted { $0.dueKm < $1.dueKm }
    }
}
