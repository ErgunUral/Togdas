import Foundation

/// Tek bir BLE komutunun araç tarafındaki ilerlemesi.
/// `lastEvent` serbest metninden bağımsız olarak komutun hangi aşamada
/// olduğunu gösterir.
struct BLECommandReceipt: Codable, Equatable, Identifiable {
    enum Phase: String, Codable, Equatable {
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

    let id: UUID
    let code: UInt8
    let action: String
    var phase: Phase
    var detail: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        code: UInt8,
        action: String,
        phase: Phase,
        detail: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.code = code
        self.action = action
        self.phase = phase
        self.detail = detail
        self.updatedAt = updatedAt
    }

    var summary: String {
        "\(action) · \(phase.title)"
    }
}
