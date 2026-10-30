import Foundation

/// Türkçe arayüz için tek biçim kaynağı.
///
/// Uygulama tek dilli Türkçe olduğundan cihaz dili farklı olsa da para/tarih
/// biçimleri tr_TR kalır. Metinler ileride String Catalog'a taşındığında buradaki
/// yerel ayar tek noktadan değiştirilebilir.
enum TurkishFormat {
    static let locale = Locale(identifier: "tr_TR")

    /// Binlik ayırıcı nokta, kuruş yok: 3940,34 → "3.940".
    static func integer(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return decimal(max(0, value), digits: 0)
    }

    static func money(_ value: Double) -> String {
        "\(integer(value)) ₺"
    }

    /// Türkçe ondalık ayırıcı ve binlik ayırıcı: 12.3 → "12,3",
    /// 1234.5 → "1.234,5". Teknik/protokol metinleri bu yardımcıyı kullanmaz.
    static func decimal(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "—" }
        let places = min(6, max(0, digits))
        let normalized = abs(value) < 0.5 * pow(10, Double(-places)) ? 0 : value
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: normalized)) ?? "—"
    }

    static func decimal(_ value: Double?, digits: Int) -> String {
        guard let value else { return "—" }
        return decimal(value, digits: digits)
    }

    /// Örn. "29 Eki 23:45". Saat dilimi cihazın yerel saatidir.
    static func date(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
