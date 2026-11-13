import Foundation

/// Yakınlık otomasyonu ayarlarının VIN bazlı kalıcılığı: profil, kalibrasyon
/// ölçümleri (yakın/uzak) ve oto-kapanma tercihi.
///
/// Neden gerekli: bu alanların okuma/yazma kodu DashboardView içinde
/// `UserDefaults.standard` üzerinden dağınık duruyordu (~28 çağrı);
/// davranış test edilemez ve ProximityDetectionMonitor ile anahtar biçimi
/// kopyalanma riski taşıyordu. Anahtar biçimleri burada tek kaynaktır ve
/// önceki literallerle **byte-identical**dir (mevcut veriler okunmaya
/// devam eder). Açma/kapama durumu (`enabled`) `GaragePreferences`'a
/// aittir; bu tip onu tekrar etmez.
///
/// Kasıtlı sınırlar:
/// - Kalibrasyon ölçümü ve süre limitleri gibi karar mantığı
///   `ProximityAutomation`/`ProximityAutoOffPolicy`'de kalır; burada
///   yalnız kalıcılık vardır.
/// - `nil` yazımı anahtarı kaldırır (`UserDefaults.removeObject`
///   davranışı); bu, "hiç yazılmamış" ile aynıdır.
/// - Deadline `Date` olarak saklanır; süre hesabı yapılmaz.
struct ProximitySettings {
    let store: KeyValueStore

    // MARK: Anahtar biçimleri (tek kaynak; değiştirilmez)

    static func profileKey(_ vin: String) -> String { "toqdas.proximity.profile.\(vin)" }
    static func nearKey(_ vin: String) -> String { "toqdas.proximity.near.\(vin)" }
    static func farKey(_ vin: String) -> String { "toqdas.proximity.far.\(vin)" }
    static func calibrationSavedAtKey(_ vin: String) -> String { "toqdas.proximity.calibrationAt.\(vin)" }
    static func autoOffEnabledKey(_ vin: String) -> String { "toqdas.proximity.autoOff.enabled.\(vin)" }
    static func autoOffMinutesKey(_ vin: String) -> String { "toqdas.proximity.autoOff.minutes.\(vin)" }
    static func autoOffCustomKey(_ vin: String) -> String { "toqdas.proximity.autoOff.custom.\(vin)" }
    static func autoOffDeadlineKey(_ vin: String) -> String { "toqdas.proximity.autoOff.deadline.\(vin)" }

    // MARK: Profil

    func profileRaw(vin: String) -> String? {
        store.string(forKey: Self.profileKey(vin))
    }

    func setProfileRaw(_ raw: String, vin: String) {
        store.set(raw, forKey: Self.profileKey(vin))
    }

    /// Kayıtlı profili çözer; bilinmeyen ham değer (veya boşluk) `nil`.
    func profile(vin: String) -> ProximityProfile? {
        profileRaw(vin: vin).flatMap(ProximityProfile.init(rawValue:))
    }

    // MARK: Kalibrasyon ölçümleri

    func nearSample(vin: String) -> Int? {
        store.object(forKey: Self.nearKey(vin)) as? Int
    }

    func setNearSample(_ sample: Int, vin: String) {
        store.set(sample, forKey: Self.nearKey(vin))
    }

    func farSample(vin: String) -> Int? {
        store.object(forKey: Self.farKey(vin)) as? Int
    }

    func setFarSample(_ sample: Int, vin: String) {
        store.set(sample, forKey: Self.farKey(vin))
    }

    /// Kalibrasyonun kaydedildiği an (eskime uyarısı için); yoksa `nil`.
    func calibrationSavedAt(vin: String) -> Date? {
        store.object(forKey: Self.calibrationSavedAtKey(vin)) as? Date
    }

    func setCalibrationSavedAt(_ date: Date?, vin: String) {
        if let date {
            store.set(date, forKey: Self.calibrationSavedAtKey(vin))
        } else {
            store.removeObject(forKey: Self.calibrationSavedAtKey(vin))
        }
    }

    /// Sıfırlama: yakın ve uzak ölçüm anahtarları kaldırılır.
    func clearCalibration(vin: String) {
        store.removeObject(forKey: Self.nearKey(vin))
        store.removeObject(forKey: Self.farKey(vin))
        store.removeObject(forKey: Self.calibrationSavedAtKey(vin))
    }

    // MARK: Oto-kapanma

    func autoOffEnabled(vin: String) -> Bool {
        store.bool(forKey: Self.autoOffEnabledKey(vin))
    }

    func setAutoOffEnabled(_ enabled: Bool, vin: String) {
        store.set(enabled, forKey: Self.autoOffEnabledKey(vin))
    }

    /// `nil` = hiç seçilmemiş (0 = özel dakika; değer ayrı anahtarda).
    func autoOffMinutes(vin: String) -> Int? {
        store.object(forKey: Self.autoOffMinutesKey(vin)) as? Int
    }

    func setAutoOffMinutes(_ minutes: Int?, vin: String) {
        store.set(minutes, forKey: Self.autoOffMinutesKey(vin))
    }

    /// Özel dakika tercihi (0..1440 aralığı doğrulaması çağırandadır).
    func autoOffCustomMinutes(vin: String) -> Int? {
        store.object(forKey: Self.autoOffCustomKey(vin)) as? Int
    }

    func setAutoOffCustomMinutes(_ minutes: Int?, vin: String) {
        store.set(minutes, forKey: Self.autoOffCustomKey(vin))
    }

    /// Sayaç sona erme zamanı; `nil` yazımı (veya okunamayan değer) = yok.
    func autoOffDeadline(vin: String) -> Date? {
        store.object(forKey: Self.autoOffDeadlineKey(vin)) as? Date
    }

    func setAutoOffDeadline(_ deadline: Date?, vin: String) {
        store.set(deadline, forKey: Self.autoOffDeadlineKey(vin))
    }
}
