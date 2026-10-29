import Foundation

enum DashboardCard: String, CaseIterable, Codable, Hashable, Identifiable {
    case quickActions
    case proximity
    case technical
    case premiumControls
    case chargingShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickActions: "Hızlı araç kontrolleri"
        case .proximity: "Yakınlıkla kapı kilidi"
        case .technical: "Canlı BLE tanısı"
        case .premiumControls: "Konfor ve güvenlik kartları"
        case .chargingShortcut: "Şarj ve yolculuk"
        }
    }

    var detail: String {
        switch self {
        case .quickActions: "Kapı, bagaj ve iklim hızlı erişimi"
        case .proximity: "RSSI kalibrasyonu ve otomasyon durumu"
        case .technical: "Bağlantı, telemetri ve tanı kayıtları"
        case .premiumControls: "Yan cam komutları ve desteklenmeyen özellikler"
        case .chargingShortcut: "Şarj hesaplayıcısı ve istasyonlara geçiş"
        }
    }
}

struct DashboardCustomization: Codable, Equatable {
    static let storageKey = "toqdas.dashboard.customization.v1"
    static let defaultOrder: [DashboardCard] = [
        .quickActions, .proximity, .premiumControls, .technical, .chargingShortcut
    ]

    var order: [DashboardCard]
    var hidden: Set<DashboardCard>

    static let `default` = DashboardCustomization(order: defaultOrder, hidden: [])

    init(order: [DashboardCard] = Self.defaultOrder, hidden: Set<DashboardCard> = []) {
        self.order = Self.complete(order)
        self.hidden = hidden
    }

    var visibleCards: [DashboardCard] { order.filter { !hidden.contains($0) } }

    func isVisible(_ card: DashboardCard) -> Bool { !hidden.contains(card) }

    mutating func setVisible(_ visible: Bool, for card: DashboardCard) {
        if visible { hidden.remove(card) }
        else { hidden.insert(card) }
    }

    mutating func move(_ card: DashboardCard, offset: Int) {
        guard let index = order.firstIndex(of: card) else { return }
        let destination = min(max(0, index + offset), order.count - 1)
        guard destination != index else { return }
        order.swapAt(index, destination)
    }

    static func load(from defaults: UserDefaults = .standard) -> DashboardCustomization {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(DashboardCustomization.self, from: data) else {
            return .default
        }
        return DashboardCustomization(order: decoded.order, hidden: decoded.hidden)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func complete(_ input: [DashboardCard]) -> [DashboardCard] {
        var result: [DashboardCard] = []
        for card in input where !result.contains(card) { result.append(card) }
        for card in defaultOrder where !result.contains(card) { result.append(card) }
        return result
    }
}
