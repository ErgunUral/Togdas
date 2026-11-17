import Foundation

/// Yakınlık otomasyonunun (ve uzaklaşma biletinin) güç durumu kapısı.
///
/// Cihaz kanıtı (2026-11-17): park hâlindeki araç `powerState` alanında
/// 0/1 (eşlemesi bilinmiyor) bildiriyor; kilit komutları bu durumda
/// **uygulanıyor** (18:22 ve 18:39 imzalı telemetriyle doğrulandı). Eski
/// `powerState == 2` şartı otomasyonu en sık senaryoda (araçtan yeni
/// ayrılırken araç uykuya geçmişken) sessizce durduruyordu.
///
/// Kasıtlı sınır: yalnız aksesuar (3) ve hazır (4) durumlarında otomatik
/// komut gönderilmez — araç çalışırken yaklaşma/uzaklaşma komutu istenmez.
/// Bilinmeyen değerler engellemez; kilit/açma güvenliği `BLECommandPolicy`
/// (READY + taze imzalı telemetri + kilit durumu bilinir) ve kapı kapalı
/// kontrolüyle ayrıca korunur.
enum ProximityPowerGate {
    static let blockedStates: Set<Int> = [3, 4]

    static func allowsAutomation(powerState: Int?) -> Bool {
        guard let powerState else { return true }
        return !blockedStates.contains(powerState)
    }

    static func blockReason(powerState: Int?) -> String? {
        guard let powerState, blockedStates.contains(powerState) else { return nil }
        return powerState == 4
            ? "Araç hazır durumda; otomatik komut gönderilmedi."
            : "Araç aksesuar durumunda; otomatik komut gönderilmedi."
    }
}
