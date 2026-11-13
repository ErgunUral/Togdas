import Foundation

/// Yeniden bağlanma bütçesi: deneme, zayıf sinyal ve eşleştirme sayaçları
/// **tek** değer tipinde.
///
/// Neden gerekli: aynı üç sayacı koordinatör, pano ve politika ayrı ayrı
/// tutuyordu; biri sıfırlanırken diğeri kalıyor, "bazen 8 bazen 30 deneme"
/// davranışı oluşuyordu. Bu tip yalnız sayaç tutar; karar `BleReconnectPolicy`
/// içinde kalır.
///
/// Kasıtlı sınırlar:
/// - Saf değer tipi; kalıcılık yok (onarım durumu ayrı: `PairingRepairStore`).
/// - Sayaçlar asla negatife inmez.
struct ReconnectBudget: Equatable {
    private(set) var attempts = 0
    private(set) var weakDrops = 0
    private(set) var pairingAttempts = 0

    /// Yeni kopma turu: deneme ve zayıf sinyal sayacı sıfırlanır,
    /// eşleştirme sayacı korunur (eşleştirme beklemesi ayrı bir akıştır).
    mutating func resetAttempts() {
        attempts = 0
        weakDrops = 0
    }

    /// 60 sn kararlı bağlantı: tüm sayaçlar sıfırlanır.
    mutating func resetAll() {
        attempts = 0
        weakDrops = 0
        pairingAttempts = 0
    }

    /// Ön plana gelme: kullanıcı etkileşimi sayacı sıfırlar.
    mutating func noteForeground() {
        resetAttempts()
    }

    /// Planlanan deneme numarasını kaydeder (1 tabanlı).
    mutating func startAttempt(_ attempt: Int) {
        attempts = max(0, attempt)
    }

    /// Zayıf sinyalle kopma sayısını artırır ve yeni değeri döner.
    @discardableResult
    mutating func noteWeakDrop() -> Int {
        weakDrops += 1
        return weakDrops
    }

    mutating func resetWeakDrops() {
        weakDrops = 0
    }

    mutating func notePairingWait() {
        pairingAttempts += 1
    }

    mutating func resetPairing() {
        pairingAttempts = 0
    }
}
