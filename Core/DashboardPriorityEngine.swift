import Foundation

/// Panonun "şimdi ne önemli" motoru.
///
/// Neden gerekli: tek ekranda ~12 blok vardı; acil bilgi (bağlantı koptu,
/// 12 V kritik, komut doğrulanamadı) ile arşiv bilgisi (geçmiş, istatistik)
/// aynı görsel ağırlıktaydı. Bu motor **yalnız sıralama ve metin** üretir;
/// komut göndermez, veri çekmez, otomasyon açmaz.
///
/// Dürüstlük sınırları:
/// - Metinler ölçüleni söyler: "bağlı değil" bilgisi bağlantı durumundan,
///   "hazır" yalnız `powerState == 4` imzalı telemetriden gelir.
/// - Eksik değer için yüzde/süre **uydurulmaz**; kart hiç üretilmez.
/// - "Araç reddetti" yazılmaz: araç gerekçe bildirmiyor.
struct DashboardPriorities {

    enum Kind: String, CaseIterable, Equatable {
        case connectionLost
        case auxiliaryCritical
        case lockUnverified
        case doorOpen
        case telemetryStale
        case weakSignal
        case chargingTarget
        case readyToDrive
    }

    enum Severity: Int, Comparable, Equatable {
        case info = 0
        case warning = 1
        case critical = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Item: Equatable, Identifiable {
        let kind: Kind
        let title: String
        let detail: String
        let severity: Severity
        var actionTitle: String?
        var id: Kind { kind }
    }

    /// Girdiler yalnız gözlemlenmiş değerlerdir; nil = "bilinmiyor".
    struct Inputs: Equatable {
        /// Dijital anahtar / BLE bağlantısı hazır mı.
        var linkReady: Bool = true
        /// "4 dk önce" gibi hazır metin (saat/tarih biçimlendirmesi UI'da).
        var lastSeenText: String?
        /// İmzalı telemetrinin yaşı (sn); nil = hiç veri yok.
        var telemetryAge: TimeInterval?
        /// Son komut doğrulanamadıysa bağlam metni.
        var commandUnverifiedDetail: String?
        var auxiliaryPercent: Double?
        var chargingActive: Bool = false
        /// Hedefe kalan yüzde puanı; nil = hedef yok.
        var chargingTargetRemaining: Int?
        /// "42 dk" gibi tahmini süre metni; nil = yeterli veri yok.
        var chargingEtaText: String?
        var openDoorCount: Int = 0
        var trunkAjar: Bool = false
        var powerState: Int?
        var weakSignal: Bool = false
    }

    /// İlk ekranda en fazla üç kart: gerisi "Tüm kontroller" derinliğinde.
    static let maximumItems = 3

    /// Eşit ciddiyette sıra: güvenlik → bağlantı → konfor → bilgi.
    private static let order: [Kind] = [
        .connectionLost, .auxiliaryCritical, .lockUnverified, .doorOpen,
        .telemetryStale, .weakSignal, .chargingTarget, .readyToDrive
    ]

    static func make(_ inputs: Inputs) -> [Item] {
        var items: [Item] = []

        if !inputs.linkReady {
            items.append(Item(
                kind: .connectionLost,
                title: "Araçla bağlantı yok",
                detail: lastSeenDetail(inputs)
                    + " Komutlar için bağlantı gerekir; otomatik yeniden deneme yok.",
                severity: .warning,
                actionTitle: "Bağlan"))
        }

        if let aux = inputs.auxiliaryPercent {
            if aux <= 25 {
                items.append(Item(
                    kind: .auxiliaryCritical,
                    title: "12 V akü kritik: %\(Int(aux.rounded()))",
                    detail: "Kritik eşik %25. Aracı çalıştırmak veya şarj etmek gerekir.",
                    severity: .critical))
            } else if aux <= 40 {
                items.append(Item(
                    kind: .auxiliaryCritical,
                    title: "12 V akü düşük: %\(Int(aux.rounded()))",
                    detail: "Uyarı eşiği %40. Uzun süre park hâlinde düşmeye devam edebilir.",
                    severity: .warning))
            }
        }

        if let detail = inputs.commandUnverifiedDetail, !detail.isEmpty {
            items.append(Item(
                kind: .lockUnverified,
                title: "Son komut doğrulanamadı",
                detail: detail,
                severity: .warning,
                actionTitle: "Komutlar"))
        }

        if inputs.openDoorCount > 0 || inputs.trunkAjar {
            let what = inputs.openDoorCount > 0 && inputs.trunkAjar
                ? "Kapı ve bagaj açık"
                : (inputs.trunkAjar ? "Bagaj açık" : "Kapı açık")
            items.append(Item(
                kind: .doorOpen,
                title: what,
                detail: "Açık kapı/bagaj varken araç kilitleme komutunu uygulamayabilir.",
                severity: .warning))
        }

        if let age = inputs.telemetryAge, age >= 45 {
            // 45 sn üstü gerçekten bayat; 15–45 sn normal dönem arasıdır.
            items.append(Item(
                kind: .telemetryStale,
                title: "İmzalı veri eski",
                detail: lastSeenDetail(inputs) + " Son durum eski olabilir.",
                severity: age >= 300 ? .warning : .info))
        }

        if inputs.weakSignal, inputs.linkReady {
            items.append(Item(
                kind: .weakSignal,
                title: "Sinyal zayıf",
                detail: "Komutlar gecikebilir veya yarıda kesilebilir; otomatik yeniden deneme yok.",
                severity: .info))
        }

        if inputs.chargingActive, let remaining = inputs.chargingTargetRemaining, remaining > 0 {
            let eta = inputs.chargingEtaText.map { "Tahmini \($0)." }
                ?? "Tahmini süre için yeterli veri yok."
            items.append(Item(
                kind: .chargingTarget,
                title: "Şarj hedefine %\(remaining) kaldı",
                detail: eta,
                severity: .info,
                actionTitle: "Enerji"))
        }

        // "Hazır" yalnız imzalı telemetriden (powerState 4).
        if inputs.powerState == 4 {
            items.append(Item(
                kind: .readyToDrive,
                title: "Araç hazır",
                detail: "Start/Stop akışı tamamlandı; durum imzalı telemetriden.",
                severity: .info))
        }

        let ranked = items.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            let li = order.firstIndex(of: lhs.kind) ?? order.count
            let ri = order.firstIndex(of: rhs.kind) ?? order.count
            return li < ri
        }
        return Array(ranked.prefix(maximumItems))
    }

    private static func lastSeenDetail(_ inputs: Inputs) -> String {
        guard let lastSeen = inputs.lastSeenText else {
            return "Henüz araç verisi alınmadı."
        }
        return "Son veri \(lastSeen)."
    }
}
