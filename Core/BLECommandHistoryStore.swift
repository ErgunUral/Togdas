import Foundation

/// BLE komut geçmişini uygulama yeniden başlasa da korur.
/// Yalnızca komut kodu, adı, aşaması, kısa açıklama ve zaman saklanır;
/// anahtar, imza veya ham paket saklanmaz.
enum BLECommandHistoryStore {
    static let key = "toqdas.ble.commandHistory.v1"
    static let limit = 20

    static func load(from defaults: UserDefaults = .standard) -> [BLECommandReceipt] {
        guard let data = defaults.data(forKey: key),
              let receipts = try? JSONDecoder().decode([BLECommandReceipt].self, from: data)
        else { return [] }
        return Array(receipts.prefix(limit))
    }

    static func save(_ receipts: [BLECommandReceipt], to defaults: UserDefaults = .standard) {
        let trimmed = Array(receipts.prefix(limit))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        defaults.set(data, forKey: key)
    }

    static func append(
        _ receipt: BLECommandReceipt,
        to receipts: [BLECommandReceipt]
    ) -> [BLECommandReceipt] {
        var updated = receipts.filter { $0.id != receipt.id }
        updated.insert(receipt, at: 0)
        return Array(updated.prefix(limit))
    }

    static func update(
        _ receipt: BLECommandReceipt,
        in receipts: [BLECommandReceipt]
    ) -> [BLECommandReceipt] {
        guard let index = receipts.firstIndex(where: { $0.id == receipt.id }) else {
            return append(receipt, to: receipts)
        }
        var updated = receipts
        updated[index] = receipt
        return Array(updated.prefix(limit))
    }
}
