import Foundation

/// Android .57'de cihaz açılışı (boot) sonrası servis otomatik başlar ve
/// BLE wake bridge yeniden kurulur. iOS'ta boot alıcısı yoktur; paritenin
/// iOS karşılığı **CBCentralManager state restoration** ile arka planda
/// yeniden başlatmadır.
///
/// Bu tip restore olayından sonra izlenecek yolu (planı) belirler:
/// - `resumeSession`: sistem, restore anında hâlâ bağlı oturumu verdi.
///   Servis keşfi ve imzalı telemetri akışı, yeni el sıkışma olmadan devam
///   eder (`connect(connectedPeripheral)` çağrısının `didConnect` tetiklemesi
///   CoreBluetooth garantisiyle kullanılır).
/// - `reconnect`: restore bildirimi geldi ama bağlantı kopuk; mevcut
///   yeniden bağlanma politikası akışı çalışır.
/// - `none`: restore yok ya da radyo kapalı; normal başlangıç.
///
/// **Kasıtlı sınırlar (kural, test invariant'ı):**
/// - Plan **asla komut göndermez** (`sendsCommand` her zaman `false`):
///   arka planda yalnız oturum/telemetri başlatılır; kilit/açma gibi
///   eylemler yalnız ön plandaki mevcut kapılarla verilir.
/// - Kullanıcı uygulamayı sweep-kill ile kapatırsa iOS restoration teslim
///   etmez; Android otomatik servis başlangıç paritesi o senaryoda daha
///   güçlüdür. Bu sınır dokümanda açıkça yazılır, kapatılamaz.
struct BleRestorePlan: Equatable {
    enum Action: Equatable {
        case none
        case resumeSession
        case reconnect
    }

    let action: Action

    /// Plan en az bir komut üretmeyi içermmez; karar çekirdeği arka plan
    /// güvenlik invariant'ıdır.
    var sendsCommand: Bool { false }

    static func nonePlan() -> BleRestorePlan { BleRestorePlan(action: .none) }

    static func evaluate(
        restoredCount: Int,
        systemConnected: Bool,
        isRadioOn: Bool
    ) -> BleRestorePlan {
        guard isRadioOn, restoredCount > 0 else { return nonePlan() }
        if systemConnected {
            return BleRestorePlan(action: .resumeSession)
        }
        return BleRestorePlan(action: .reconnect)
    }
}
