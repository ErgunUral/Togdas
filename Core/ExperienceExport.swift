import Foundation

/// Seyahatname kayıtlarını dışa aktarma (CSV).
///
/// Yalnız yüklenmiş kayıtlar aktarılır; sunucuda henüz yüklenmemiş sayfalar
/// varmış gibi gösterilmez. Türkçe Excel için noktalı virgül ayırıcı ve UTF-8 BOM
/// kullanılır. Sayılar/etiketler ekrandaki gerçek değerlerdir; dönüştürülmez.
enum ExperienceExport {
    static func csv(records: [ExperienceRecord]) -> String {
        var metricLabels: [String] = []
        for record in records {
            for metric in record.metrics where !metricLabels.contains(metric.label) {
                metricLabels.append(metric.label)
            }
        }

        let headers = ["Tür", "Tarih", "Konum/Rota"] + metricLabels
        var lines = [headers.map(escape).joined(separator: ";")]

        for record in records {
            var values: [String: String] = [:]
            for metric in record.metrics { values[metric.label] = metric.value }
            let row = [record.kind.title, record.dateText, record.subtitle]
                + metricLabels.map { values[$0] ?? "" }
            lines.append(row.map(escape).joined(separator: ";"))
        }

        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Örn. `Seyahatname-sarj-2026-10.csv`; çapa yoksa tarih eklenir.
    static func filename(kind: ExperienceKind, anchor: String?, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let suffix = sanitized(anchor ?? formatter.string(from: date))
        return "Seyahatname-\(kind == .charges ? "sarj" : "yolculuk")-\(suffix).csv"
    }

    private static func sanitized(_ value: String) -> String {
        var result = ""
        var lastWasDash = false
        for character in value.lowercased() {
            let isAllowed = character.isLetter || character.isNumber
            if isAllowed {
                result.append(character)
                lastWasDash = false
            } else if !lastWasDash, !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "kayit" : result
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
