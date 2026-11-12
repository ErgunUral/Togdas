import Foundation

/// Dijital anahtar tanıtma oturumu: aday kataloğu, tarama penceresi ve
/// seçim durumunun saf yönetimi.
///
/// Android `.57.18` paritesi (`Q4.java`): tarama penceresi 12 sn, seçim
/// tazeliği 120 sn, 128 ham / 32 geçerli aday limiti. Karar
/// `KeyDiscoveryPolicy`'dedir; BLE taşıma ve UI burada yoktur ve bu
/// oturum **araç komutu göndermez** — "Bağlan" adımı çağıran tarafta,
/// mevcut bağlantı akışıyla yapılır.
///
/// Kasıtlı sınırlar:
/// - Aday anahtarı iOS'ta `CBPeripheral.identifier`'dır (Android'deki
///   MAC adresine karşılık gelir; cihaz başına stabil).
/// - "Kayıtlı adres" kanıtı iOS'ta son bağlanılan çevrebirim tanımıdır
///   (`matchesRegisteredAddress`); Android `bondState` yerine geçmez,
///   kimlik bağlantı sonrası GATT el sıkışmasıyla doğrulanır.
/// - `nil`/boş kanıt birikimi `KeyDiscoveryCandidate.observe` ile
///   birleştirilir; bayraklar temizlenmez.
struct KeyDiscoverySession {
    let vin: String

    /// Adaylar, çevrebirim tanımlayıcısına göre (ekleme sırası korunur).
    private(set) var candidates: [String: KeyDiscoveryCandidate] = [:]
    /// Ekleme sırası (aday listesi kararlı dursun diye).
    private(set) var candidateOrder: [String] = []

    private(set) var scanRequested = false
    private(set) var scanStarted = false
    private(set) var scanActive = false
    private(set) var scanFailedMessage: String?
    /// Bu oturumda hiç aday görüldü mü (reklam gözlendi mi) — K02/K03 ayrımı.
    private(set) var rawSightingCount = 0
    private(set) var selectedID: String?
    private(set) var lastCandidateUpdate: Date?

    /// Sunulan geçerli aday sayısı — `sortedValidCandidates.count`
    /// (32'yle sınırlı; Android `h.size()`).

    init(vin: String) {
        self.vin = vin.uppercased()
    }

    // MARK: Tarama

    mutating func requestScan() {
        scanRequested = true
    }

    mutating func beginScan(at date: Date = Date()) {
        scanRequested = true
        scanStarted = true
        scanActive = true
        scanFailedMessage = nil
        selectedID = nil
    }

    mutating func endScan(at date: Date = Date()) {
        scanActive = false
        // Android `Q4.w` birebir: tazelik penceresi tarama bitişini izler
        // (son aday güncellemesini değil); taramadan sonra 120 sn içinde
        // seçim yapılabilir.
        lastCandidateUpdate = date
    }

    mutating func failScan(_ message: String) {
        scanActive = false
        scanFailedMessage = message
    }

    // MARK: Gözlem

    /// Bir çevrebirim gözlemi ekler/birleştirir. Limitler Android
    /// birebir: 128 ham aday, 32 geçerli aday; geçerli aday listesi
    /// doluysa yeni geçerli aday eklenmez (mevcutlar birikmeye devam
    /// eder).
    mutating func observe(
        identifier: String,
        name: String?,
        rssi: Int?,
        advertisesSupportedService: Bool,
        matchesRegisteredAddress: Bool = false,
        at date: Date = Date()
    ) {
        guard !identifier.isEmpty else { return }
        rawSightingCount += 1
        if var candidate = candidates[identifier] {
            candidate.observe(
                name: name,
                rssi: rssi,
                nameMatchesVIN: KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: name),
                matchesRegisteredAddress: matchesRegisteredAddress,
                advertisesSupportedService: advertisesSupportedService,
                at: date
            )
            candidates[identifier] = candidate
        } else {
            guard candidates.count < KeyDiscoveryPolicy.maxRawCandidates else { return }
            let candidate = KeyDiscoveryCandidate.fromSighting(
                id: identifier,
                name: name,
                rssi: rssi,
                vin: vin,
                advertisesSupportedService: advertisesSupportedService,
                matchesRegisteredAddress: matchesRegisteredAddress,
                at: date
            )
            candidates[identifier] = candidate
            candidateOrder.append(identifier)
        }
        lastCandidateUpdate = date
    }

    /// Geçerli adaylar; RSSI'a göre sıralı (yoksa tazeliğe göre).
    /// Android `h` limiti uygulanır: en fazla 32 geçerli aday sunulur.
    /// `nil` RSSI asla 0 sayılmaz — listenin sonuna konur.
    var sortedValidCandidates: [KeyDiscoveryCandidate] {
        Array(candidates.values
            .filter(\.isValid)
            .sorted { lhs, rhs in
                switch (lhs.rssi, rhs.rssi) {
                case let (l?, r?):
                    return l > r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.lastSeen > rhs.lastSeen
                }
            }
            .prefix(KeyDiscoveryPolicy.maxValidCandidates))
    }

    /// Sunulan geçerli aday sayısı (32'yle sınırlı; Android `h.size()`).
    var validCount: Int {
        sortedValidCandidates.count
    }

    // MARK: Seçim (Android `Q4.x`)

    /// Seçim izni politikadadır: tarama etkin ya da son aday
    /// güncellemesi 120 sn içinde olmalı.
    func isSelectionAllowed(now: Date = Date()) -> Bool {
        KeyDiscoveryPolicy.isSelectionAllowed(
            hasScanRun: scanStarted,
            scanActive: scanActive,
            lastCandidateUpdate: lastCandidateUpdate,
            now: now
        )
    }

    /// Aday seçer; geçersizse nil döner (hata metni çağırandadır).
    /// Yalnız sunulan geçerli aday listesindeki adaylar seçilebilir
    /// (Android `h` haritası birebir).
    mutating func select(_ identifier: String, now: Date = Date()) -> KeyDiscoveryCandidate? {
        guard isSelectionAllowed(now: now) else { return nil }
        guard sortedValidCandidates.contains(where: { $0.id == identifier }) else { return nil }
        selectedID = identifier
        return candidates[identifier]
    }

    // MARK: Durum kodu (Android `Q4.j`)

    func statusCode(now: Date = Date()) -> String {
        KeyDiscoveryPolicy.statusCode(
            scanFailed: scanFailedMessage != nil,
            scanRequested: scanRequested,
            scanStarted: scanStarted,
            rawSightingCount: rawSightingCount,
            validCandidateCount: validCount
        )
    }
}
