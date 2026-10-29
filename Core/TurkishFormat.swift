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
        let rounded = Int(max(0, value).rounded())
        let digits = String(rounded)
        var grouped = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(".") }
            grouped.append(character)
        }
        return String(grouped.reversed())
    }

    static func money(_ value: Double) -> String {
        "\(integer(value)) ₺"
    }

    /// Örn. "29 Eki 23:45". Saat dilimi cihazın yerel saatidir.
    static func date(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
