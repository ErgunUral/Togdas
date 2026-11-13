import Foundation

/// BLE bağlantısının tek, açık faz modeli.
///
/// Neden gerekli: yaşam döngüsü üç yerde ayrı ayrı string/boolean olarak
/// tutuluyordu (`BleConnection.state`, koordinatördeki `reconnecting`/
/// `attempts`, panodaki sayaçlar). Aynı anda birden fazla "doğru" durum
/// olabiliyordu. Bu model **saf** bir eşlemedir; durum yazmaz, komut
/// göndermez, yalnız mevcut sinyallerden tek bir faz üretir.
///
/// Öncelik sırası (üstteki kazanır): onarım > radyo kapalı > eşleştirme
/// beklemesi > bağlantı fazı. Böylece "bağlı görünürken onarım gerekiyor"
/// gibi çelişkili gösterim oluşmaz.
enum BlePhase: String, Equatable, CaseIterable {
    /// Hiç başlatılmadı ya da kullanıcı durdurdu.
    case idle
    /// Tarama / geri çekilme beklemesi.
    case searching
    case connecting
    /// Sertifika akışı ve meydan okuma.
    case authenticating
    case ready
    /// Bağlı ama telemetri/sinyal zayıf; komut güvenliği etkilenebilir.
    case degraded
    /// Araç eşleşme kaydını sildi; kullanıcı adımları gerekli.
    case repairRequired
    /// Araç anahtarı yok; araç ekranından eşleştirme bekleniyor.
    case pairingWait
    case radioOff
    /// Deneme bütçesi tükendi.
    case stopped

    var isConnected: Bool {
        self == .ready || self == .degraded
    }

    /// Kısa Türkçe etiket (UI tek satırı ve tanı günlüğü aynı kaynağı kullanır).
    var label: String {
        switch self {
        case .idle: return "Hazır değil"
        case .searching: return "Araç aranıyor"
        case .connecting: return "Bağlanıyor"
        case .authenticating: return "Kimlik doğrulanıyor"
        case .ready: return "Bağlı ve hazır"
        case .degraded: return "Bağlı; sinyal zayıf"
        case .repairRequired: return "Eşleşme onarımı gerekli"
        case .pairingWait: return "Eşleştirme bekleniyor"
        case .radioOff: return "Bluetooth kapalı"
        case .stopped: return "Otomatik deneme durdu"
        }
    }
}

/// Faz eşlemesinin saf kuralı (test edilebilir).
enum BlePhaseMachine {
    static func phase(
        state: BleConnection.State,
        needsRepair: Bool,
        pairingRequired: Bool,
        radioAvailable: Bool,
        reconnecting: Bool,
        telemetryFresh: Bool = true
    ) -> BlePhase {
        if needsRepair { return .repairRequired }
        if !radioAvailable { return .radioOff }
        if pairingRequired { return .pairingWait }

        switch state {
        case .disconnected:
            return reconnecting ? .searching : .idle
        case .connecting, .discovering:
            return .connecting
        case .certificate, .challenge, .authenticated:
            return .authenticating
        case .ready:
            return telemetryFresh ? .ready : .degraded
        case .failed:
            return reconnecting ? .searching : .stopped
        }
    }
}
