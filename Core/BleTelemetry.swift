import Foundation

struct BLEDiagnosticEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String
}

struct BleTelemetry: Equatable {
    let locked: Int
    let doors: [Int]
    let trunkAjar: Int
    let powerState: Int
    let counter: Int
    let receivedAt: Date

    /// Resmî web uygulamasındaki eşleme: 1 kilitli, 2 kilit açık.
    var isLocked: Bool? {
        switch locked {
        case 1: return true
        case 2: return false
        default: return nil
        }
    }

    var lockText: String {
        switch isLocked {
        case true: return "Kilitli"
        case false: return "Kilit açık"
        case nil: return "Kilit durumu doğrulanıyor"
        }
    }

    var hasDoorReadings: Bool { doors.count == 4 }

    /// door1–door4 alanları sırasıyla 1–4 olarak gösterilir. Fiziksel kapı
    /// konumları resmî uygulamada doğrulanmadığı için sol/sağ etiketi kullanılmaz.
    func isDoorOpen(_ index: Int) -> Bool? {
        guard doors.indices.contains(index) else { return nil }
        return doors[index] != 0
    }

    var openDoorCount: Int {
        doors.filter { $0 != 0 }.count
    }

    var doorsText: String {
        guard hasDoorReadings else { return "Kapı durumu doğrulanıyor" }
        let open = doors.indices.filter { doors[$0] != 0 }.map { "Kapı \($0 + 1)" }
        return open.isEmpty ? "Tüm kapılar kapalı" : open.joined(separator: ", ") + " açık"
    }

    /// Kilit/kapı/bagaj telemetrisinden türetilen güvenlik özeti.
    var securityWarning: String? {
        var openItems: [String] = []
        if hasDoorReadings, openDoorCount > 0 {
            openItems.append(doorsText)
        }
        if trunkAjar == 1 {
            openItems.append("Bagaj açık")
        }
        if !openItems.isEmpty { return openItems.joined(separator: " · ") }
        if powerState == 2, isLocked == false { return "Araç beklemede ve kilit açık" }
        return nil
    }

    /// Resmî web uygulamasındaki eşleme: 2 bekleme, 3 aksesuar, 4 hazır.
    var powerStateText: String {
        switch powerState {
        case 2: return "Bekleme"
        case 3: return "Aksesuar"
        case 4: return "Hazır"
        default: return "Durum doğrulanıyor"
        }
    }
}
