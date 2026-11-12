import Foundation

/// Dijital anahtar tanıtma (keyDiscovery) aday seçim politikası.
///
/// Android `.57.18` paritesi: aday geçerliliği, VIN-ad eşleşmesi ve
/// seçim tazeliği kuralları `Q4.java`'dan birebir taşındı (saf mantık;
/// BLE taşıma yok). Kasıtlı sınırlar:
/// - Karar yalnızca polittir; tarama/bağlantı `BleLinkCoordinator`'da
///   kalır ve tanıtma akışı **araç komutu göndermez** (Android
///   invariant'ı: "hiçbir araç komutu gönderilmez").
/// - `matchesRegisteredAddress` iOS'ta eşlenmiş sunucu adresi/önceki
///   tanıma kaydına göre çağıran tarafından kurulur; Android
///   `bondState` sistemi eşleşmesi iOS'ta GATT kimlik doğrulamasıyla
///   ayrıca doğrulanır.
/// - Öncelik sırası ve uyarı metinleri Android'dekiyle aynıdır
///   (VIN-ad > kayıtlı adres > servis kanıtı > genel ad).
enum KeyDiscoveryPolicy {
    /// Tarama penceresi: "Tanıtma taraması etkin · en çok 12sn".
    static let scanWindow: TimeInterval = 12
    /// Seçim tazeliği: taramadan sonra aday seçimi için süre.
    static let selectionFreshness: TimeInterval = 120
    /// Ham gözlem limiti (Android `g` haritası).
    static let maxRawCandidates = 128
    /// Geçerli aday limiti (Android `h` haritası).
    static let maxValidCandidates = 32

    // MARK: VIN-ad eşleşmesi (Android `C0015a0.j1`)

    /// VIN biçimi: [A-HJ-NPR-Z0-9]{17} (I, O, Q yok).
    static func isValidVIN(_ vin: String) -> Bool {
        guard vin.count == 17 else { return false }
        let allowed = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
        return vin.allSatisfy { allowed.contains($0) }
    }

    /// Cihaz adı VIN ile uyumlu mu? Ad (trim + büyük harf) şu üçlerinden
    /// biri olmalı: "MY T-SAS <son 8>", "MY T-SAS <son 6>",
    /// "MY T-SAS <tam VIN>".
    static func deviceNameMatches(vin: String, name: String?) -> Bool {
        guard let name, isValidVIN(vin) else { return false }
        let upper = name.trimmingCharacters(in: .whitespaces).uppercased()
        let vinUTF8 = Array(vin)
        let suffix8 = String(vinUTF8.suffix(8))
        let suffix6 = String(vinUTF8.suffix(6))
        return upper == "MY T-SAS \(suffix8)"
            || upper == "MY T-SAS \(suffix6)"
            || upper == "MY T-SAS \(vin)"
    }

    /// Genel ad eşleşmesi (Android `o`): ad tam olarak "My T-SAS"
    /// (büyüklük duyarsız, trim'li). Bu tek başına kanıt sayılır ama
    /// en düşük önceliklidir.
    static func nameIsGenericTSAS(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("My T-SAS") == .orderedSame
    }

    // MARK: Seçim tazeliği (Android `Q4.x`)

    /// Aday seçimi izni: oturumda en az bir tarama koşmuş olmalı ve ya
    /// tarama hâlâ etkin olmalı ya da son aday güncellemesi 120 sn
    /// içinde olmalı. Değilse "Cihazları Tara ile güncel aday seçin."
    static func isSelectionAllowed(
        hasScanRun: Bool,
        scanActive: Bool,
        lastCandidateUpdate: Date?,
        now: Date
    ) -> Bool {
        guard hasScanRun else { return false }
        if scanActive { return true }
        guard let last = lastCandidateUpdate else { return false }
        return now.timeIntervalSince(last) <= selectionFreshness
    }

    /// Kullanıcıya gösterilecek tazeliği kaybetme mesajı (Android birebir).
    static let selectionStaleMessage = "Cihazları Tara ile güncel aday seçin."

    // MARK: Durum kodu (Android `Q4.j`)

    /// Kanonik durum kodu; tanı ekranında gösterilir.
    static func statusCode(
        identityVerified: Bool = false,
        authenticationFailed: Bool = false,
        pairingFailed: Bool = false,
        connectFailed: Bool = false,
        scanFailed: Bool = false,
        scanRequested: Bool = false,
        scanStarted: Bool = false,
        rawSightingCount: Int,
        validCandidateCount: Int
    ) -> String {
        if identityVerified { return "K07_READY" }
        if authenticationFailed { return "K06_AUTH_FAILED" }
        if pairingFailed { return "K05_PAIR_FAILED" }
        if connectFailed { return "K04_CONNECT_FAILED" }
        if scanFailed { return "K01_SCAN_FAILED" }
        if !scanRequested { return "K00_NOT_REQUESTED" }
        if !scanStarted { return "K01_NOT_STARTED" }
        if validCandidateCount == 0 {
            return rawSightingCount == 0 ? "K02_NO_RAW" : "K03_NO_CANDIDATE"
        }
        return "K04_CANDIDATE"
    }
}

/// Tek bir tanıtma adayı. Gözlemler birikir (Android `|=` semantiği):
/// birden çok reklamdan gelen kanıtlar toplanır; geçerlilik
/// `nameMatchesVIN || matchesRegisteredAddress ||
/// advertisesSupportedService || nameIsGeneric` ile belirlenir.
struct KeyDiscoveryCandidate: Equatable {
    /// Rastgele aday kimliği (Android `b.f301a`); adres/UUID yerine
    /// stabil UI anahtarıdır.
    let id: String
    /// Taramada görülen ad (reklam adı veya cihaz adı).
    var name: String?
    /// Son görülen RSSI (dBm); yoksa nil (asla 0 sahtesi yapılmaz).
    var rssi: Int?
    /// İlk görülme zamanı.
    var firstSeen: Date
    /// Son görülme zamanı (tazelik gösterimi için).
    var lastSeen: Date

    var nameMatchesVIN = false
    var matchesRegisteredAddress = false
    var advertisesSupportedService = false
    var nameIsGeneric = false

    var isValid: Bool {
        nameMatchesVIN || matchesRegisteredAddress || advertisesSupportedService || nameIsGeneric
    }

    /// Öncelik sırası Android birebir: VIN-ad > kayıtlı adres > servis >
    /// genel ad > elendi. Metinler Android'dekiyle aynıdır.
    var reason: String {
        if nameMatchesVIN {
            return "VIN ile cihaz adı uyumlu; kimlik doğrulama henüz yapılmadı"
        }
        if matchesRegisteredAddress {
            return "Kayıtlı adres eşleşti; bond ve imzalı kimlik ayrıca doğrulanmalı"
        }
        if advertisesSupportedService {
            return "My T-SAS servis adayı; VIN/araç kimliği henüz doğrulanmadı"
        }
        if nameIsGeneric {
            return "My T-SAS adı var; VIN ve araç kimliği henüz doğrulanmadı"
        }
        return "Elendi: VIN-ad, kayıtlı adres veya desteklenen servis kanıtı yok"
    }

    /// Yeni bir gözlemi mevcut adayla birleştirir (bayraklar yalnız
    /// birikir, temizlenmez — Android `|=` davranışı). `nil` alanlar
    /// mevcut değeri korur.
    mutating func observe(
        name: String?,
        rssi: Int?,
        nameMatchesVIN: Bool,
        matchesRegisteredAddress: Bool = false,
        advertisesSupportedService: Bool,
        at date: Date = Date()
    ) {
        if let name { self.name = name }
        if let rssi { self.rssi = rssi }
        self.nameMatchesVIN = self.nameMatchesVIN || nameMatchesVIN
        self.matchesRegisteredAddress = self.matchesRegisteredAddress || matchesRegisteredAddress
        self.advertisesSupportedService = self.advertisesSupportedService || advertisesSupportedService
        self.nameIsGeneric = self.nameIsGeneric || KeyDiscoveryPolicy.nameIsGenericTSAS(name)
        lastSeen = date
    }

    /// Ham gözlemden aday kurar (reklam adı/UUID kanıtlarıyla).
    /// `id` boşsa rastgele atanır; oturum çevrebirim tanımlayıcısını
    /// geçer (aday anahtarı stabil kalır).
    static func fromSighting(
        id: String = UUID().uuidString,
        name: String?,
        rssi: Int?,
        vin: String,
        advertisesSupportedService: Bool,
        matchesRegisteredAddress: Bool = false,
        at date: Date = Date()
    ) -> KeyDiscoveryCandidate {
        var candidate = KeyDiscoveryCandidate(
            id: id,
            name: name,
            rssi: rssi,
            firstSeen: date,
            lastSeen: date
        )
        candidate.observe(
            name: name,
            rssi: rssi,
            nameMatchesVIN: KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: name),
            matchesRegisteredAddress: matchesRegisteredAddress,
            advertisesSupportedService: advertisesSupportedService,
            at: date
        )
        return candidate
    }
}
