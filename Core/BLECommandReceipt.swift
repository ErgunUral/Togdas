import Foundation

/// Tek bir BLE komutunun araç tarafındaki ilerlemesi.
/// `lastEvent` serbest metninden bağımsız olarak komutun hangi aşamada
/// olduğunu gösterir.
struct BLECommandReceipt: Equatable {
    enum Phase: String, Equatable {
        case queued
        case sent
        case acknowledged
        case verified
        case failed

        var title: String {
            switch self {
            case .queued: return "Sıraya alındı"
            case .sent: return "Gönderildi"
            case .acknowledged: return "Araç aldı"
            case .verified: return "Doğrulandı"
            case .failed: return "Başarısız"
            }
        }

        var isFailure: Bool { self == .failed }
    }

    let code: UInt8
    let action: String
    var phase: Phase
    var detail: String?
    var updatedAt: Date

    var summary: String {
        "\(action) · \(phase.title)"
    }
}
