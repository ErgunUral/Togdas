import Foundation
import CoreFoundation

/// Drive Experience yanıtlarının saf ayrıştırma ve biçimlendirme katmanı.
/// Alan adları Togg web istemcisinin kullandığı snake_case şemasını izler;
/// eski/yeni yanıtlar için birkaç bilinen alternatif de kabul edilir.
enum ExperienceKind: String, CaseIterable {
    case journeys
    case charges

    var title: String { self == .journeys ? "Yolculuklar" : "Şarj" }
    var detailKind: String { self == .journeys ? "journeyDetail" : "chargeDetail" }

    static func fromDetailKind(_ value: String) -> ExperienceKind? {
        value == "chargeDetail" ? .charges : (value == "journeyDetail" ? .journeys : nil)
    }
}

struct ExperienceMetric: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String
}

struct ExperienceSummarySection: Identifiable, Equatable {
    let id: String
    let title: String
    let distanceKM: Double?
    let journeyCount: Double?
    let durationMinutes: Double?
    let averageConsumption: Double?
    let economyScore: Double?
    let totalConsumptionKWh: Double?
    let averageSpeedKMH: Double?
    let chargeCount: Double?
    let addedEnergyKWh: Double?
    let preferredMode: String?
    let airCondition: String?
    let chargingType: String?

    var hasContent: Bool {
        distanceKM != nil || journeyCount != nil || durationMinutes != nil ||
        averageConsumption != nil || economyScore != nil || totalConsumptionKWh != nil ||
        averageSpeedKMH != nil || chargeCount != nil || addedEnergyKWh != nil ||
        preferredMode != nil || airCondition != nil || chargingType != nil
    }
}

struct ExperienceComparison: Identifiable, Equatable {
    let id: String
    let label: String
    let you: Double?
    let community: Double?
    let unit: String
    let lowerIsBetter: Bool
}

struct ExperienceHighlight: Identifiable, Equatable {
    let id: String
    let kind: ExperienceKind
    let detailID: String?
    let title: String
    let dateText: String
    let detailText: String
}

struct ExperienceDashboard: Equatable {
    let sections: [ExperienceSummarySection]
    let comparisons: [ExperienceComparison]
    let lastJourney: ExperienceHighlight?
    let lastCharge: ExperienceHighlight?
}

struct ExperienceBar: Identifiable, Equatable {
    let id: String
    let label: String
    let value: Double
    let unit: String
}

struct ExperienceRecord: Identifiable, Equatable {
    let id: String
    let detailID: String?
    let kind: ExperienceKind
    let dateText: String
    let subtitle: String
    let metrics: [ExperienceMetric]
}

struct ExperiencePeriod: Equatable {
    let metrics: [ExperienceMetric]
    let bars: [ExperienceBar]
    let records: [ExperienceRecord]
    let hasMore: Bool
    let nextOffset: Int
    let receivedCount: Int
}

struct ExperienceDetailSection: Identifiable, Equatable {
    let id: String
    let title: String
    let metrics: [ExperienceMetric]
}

struct ExperienceDetail: Equatable {
    let kind: ExperienceKind
    let dateText: String
    let subtitle: String
    let metrics: [ExperienceMetric]
    let notes: [String]
    let sections: [ExperienceDetailSection]
}

enum ExperienceFormat {
    // MARK: - Genel yardımcılar

    static func number(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let string = value as? String {
            let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard !text.isEmpty, let double = Double(text), double.isFinite else { return nil }
            return double
        }
        return nil
    }

    static func number(_ dictionary: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            if let value = value(in: dictionary, path: key), let number = number(value) {
                return number
            }
        }
        return nil
    }

    static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func text(_ dictionary: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = value(in: dictionary, path: key), let text = text(value) {
                return text
            }
        }
        return nil
    }

    static func value(in node: Any?, path: String) -> Any? {
        var current = node
        for component in path.split(separator: ".") {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[String(component)] else { return nil }
            current = next
        }
        return current
    }

    static func whole(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f", value)
    }

    static func oneDecimal(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f", value)
    }

    static func twoDecimals(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.2f", value)
    }

    static func distance(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return "\(oneDecimal(value)) km"
    }

    static func energy(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return "\(twoDecimals(value)) kWh"
    }

    static func consumption(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return "\(twoDecimals(value)) kWh/100 km"
    }

    static func duration(minutes: Double?) -> String? {
        guard let minutes, minutes.isFinite, minutes >= 0 else { return nil }
        if minutes >= 60 {
            let total = Int(minutes.rounded())
            let hours = total / 60
            let remainder = total % 60
            return remainder == 0 ? "\(hours) sa" : "\(hours) sa \(remainder) dk"
        }
        return "\(Int(minutes.rounded())) dk"
    }

    static func percent(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return "\(whole(value))%"
    }

    static func date(from value: Any?) -> Date? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let raw = number.doubleValue
            guard raw.isFinite, raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
        }
        guard let string = text(value) else { return nil }
        if let number = Double(string), number.isFinite, number > 0 {
            return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    static func dateText(_ value: Any?) -> String {
        if let date = date(from: value) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "tr_TR")
            formatter.timeZone = .current
            formatter.dateFormat = "d MMM yyyy HH:mm"
            return formatter.string(from: date)
        }
        guard let string = text(value) else { return "" }
        if string.count >= 10, string[string.index(string.startIndex, offsetBy: 4)] == "-" {
            return String(string.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        return string
    }

    static func periodLabel(_ value: Any?) -> String {
        guard let raw = text(value) else { return "" }
        let parts = raw.upperCasedTr.split(separator: "-")
        if raw.count == 4, Int(raw) != nil { return raw }
        if raw.count >= 7, parts.count >= 2, Int(parts[0]) != nil {
            let month = Int(parts[1])
            if raw.count == 7, let month, (1...12).contains(month) {
                return "\(monthNames[month - 1]) \(parts[0])"
            }
            if raw.count >= 10, let day = Int(parts[2]), let month, (1...12).contains(month) {
                return "\(day) \(monthNames[month - 1])"
            }
        }
        if raw.uppercased().contains("W"), let week = raw.split(whereSeparator: { !$0.isNumber }).last {
            return "\(week). hafta"
        }
        return raw
    }

    static func display(_ value: String?) -> String? {
        guard let value = text(value) else { return nil }
        let key = value.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let map: [String: String] = [
            "FAST": "Hızlı şarj", "SLOW": "Yavaş şarj", "NORMAL": "Normal",
            "WEEKLY": "Haftalık", "MONTHLY": "Aylık", "ANNUAL": "Yıllık",
            "ECO": "Eko", "COMFORT": "Konfor", "SPORT": "Spor",
            "LOW": "Düşük", "MEDIUM": "Orta", "HIGH": "Yüksek",
            "LOW_AC": "Düşük AC", "MEDIUM_AC": "Orta AC", "HIGH_AC": "Yüksek AC",
            "LOW AC": "Düşük AC", "MEDIUM AC": "Orta AC", "HIGH AC": "Yüksek AC",
            "AC": "AC", "DC": "DC", "START": "Başlangıç", "END": "Varış",
            "DESTINATION": "Varış", "STOP": "Ara durak"
        ]
        if let mapped = map[key] { return mapped }
        if key.hasPrefix("DRIVEMODE_") {
            let mode = String(key.dropFirst("DRIVEMODE_".count)).lowercased()
            return map[mode.uppercased()] ?? mode.capitalized
        }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func label(forKey key: String) -> String {
        let map: [String: String] = [
            "eco": "Eko", "comfort": "Konfor", "sport": "Spor",
            "ac": "Klima", "heating": "Isıtma", "cooling": "Soğutma",
            "city": "Şehir içi", "highway": "Otoyol", "mixed": "Karma"
        ]
        if let mapped = map[key.lowercased()] { return mapped }
        return key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Dashboard

    static func dashboard(from data: Data) -> ExperienceDashboard? {
        guard let root = root(from: data) else { return nil }
        let specs: [(String, String)] = [
            ("this_month", "Son 30 gün"),
            ("last_month", "Önceki dönem"),
            ("last_month_calendar", "Önceki takvim ayı"),
            ("all_time", "Tüm zamanlar")
        ]
        var sections: [ExperienceSummarySection] = []
        for (key, title) in specs {
            guard let dictionary = root[key] as? [String: Any] else { continue }
            let section = summarySection(id: key, title: title, dictionary: dictionary)
            if section.hasContent { sections.append(section) }
        }

        let comparisons = parseComparisons(root)
        let lastJourney = highlight(root["last_journey"], kind: .journeys, title: "Son yolculuk")
        let lastCharge = highlight(root["last_charge"], kind: .charges, title: "Son şarj")
        guard !sections.isEmpty || !comparisons.isEmpty || lastJourney != nil || lastCharge != nil else {
            return nil
        }
        return ExperienceDashboard(sections: sections, comparisons: comparisons,
                                   lastJourney: lastJourney, lastCharge: lastCharge)
    }

    private static func summarySection(id: String, title: String, dictionary: [String: Any]) -> ExperienceSummarySection {
        let hours = number(dictionary, ["driving_time_hours"])
        let duration = number(dictionary, ["total_duration_min", "duration_min_total", "duration_min"])
            ?? hours.map { $0 * 60 }
        let distance = number(dictionary, ["total_distance_km", "total_km", "km_total", "distance_km"])
        let consumption = number(dictionary, ["avg_consumption_per_100km", "avg_kwh_per_100km", "monthly_average_consumption_kwh"])
        let score = number(dictionary, ["avg_economy_score", "economy_score", "journey_score"])
        return ExperienceSummarySection(
            id: id,
            title: title,
            distanceKM: nonNegative(distance),
            journeyCount: nonNegative(number(dictionary, ["journey_count", "total_journeys", "drive_count"])),
            durationMinutes: nonNegative(duration),
            averageConsumption: nonNegative(consumption),
            economyScore: score.flatMap { (0...100).contains($0) ? $0 : nil },
            totalConsumptionKWh: nonNegative(number(dictionary, ["total_kwh_consumed", "total_consumption_kwh", "consumption_kwh", "kwh_consumed"])),
            averageSpeedKMH: nonNegative(number(dictionary, ["avg_speed_kmh"])),
            chargeCount: nonNegative(number(dictionary, ["monthly_charges", "total_sessions", "charge_count", "total_charges"])),
            addedEnergyKWh: nonNegative(number(dictionary, ["total_kwh_added", "total_energy_kwh"])),
            preferredMode: display(text(dictionary, ["preferred_mode"])),
            airCondition: display(text(dictionary, ["air_condition"])),
            chargingType: display(text(dictionary, ["charging_type"]))
        )
    }

    private static func parseComparisons(_ root: [String: Any]) -> [ExperienceComparison] {
        guard let comparison = root["community_comparison"] as? [String: Any]
                ?? root["comparison"] as? [String: Any] else { return [] }
        let specs: [(String, String, String, Bool)] = [
            ("avg_consumption_per_100km", "Ortalama tüketim", "kWh/100 km", true),
            ("total_journeys", "Yolculuk", "adet", false),
            ("monthly_charges", "Şarj sayısı", "adet", false)
        ]
        let youValues = comparison["you"] as? [String: Any]
        let communityValues = comparison["community"] as? [String: Any]
        return specs.compactMap { key, label, unit, lowerIsBetter in
            let metric = comparison[key] as? [String: Any]
            let you = number(metric?["you"] ?? youValues?[key] ?? metric?["value"])
            let community = number(metric?["community"] ?? communityValues?[key])
            guard you != nil || community != nil else { return nil }
            return ExperienceComparison(id: key, label: label, you: you, community: community,
                                        unit: unit, lowerIsBetter: lowerIsBetter)
        }
    }

    private static func highlight(_ value: Any?, kind: ExperienceKind, title: String) -> ExperienceHighlight? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let detailID = text(dictionary, ["charge_id", "journey_id", "trip_id", "id"])
        let dateText = dateText(firstValue(dictionary, ["start_ts", "start_time", "event_date", "date", "created_at"]))
        var parts: [String] = []
        if kind == .charges {
            if let energy = energy(number(dictionary, ["kwh_added"])) { parts.append(energy) }
            let start = number(dictionary, ["soc_start_pct"])
            let end = number(dictionary, ["soc_end_pct"])
            if start != nil || end != nil {
                parts.append("\(whole(start))% → \(whole(end))%")
            }
        } else {
            if let distance = distance(number(dictionary, ["total_distance_km", "distance_km", "total_km"])) {
                parts.append(distance)
            }
            if let kwh = energy(number(dictionary, ["total_kwh_consumed", "kwh_consumed"])) {
                parts.append(kwh)
            }
        }
        guard !dateText.isEmpty || !parts.isEmpty || detailID != nil else { return nil }
        return ExperienceHighlight(id: kind.rawValue + ":" + (detailID ?? dateText),
                                   kind: kind, detailID: detailID, title: title,
                                   dateText: dateText, detailText: parts.joined(separator: " · "))
    }

    // MARK: - Dönem ve kayıtlar

    /// - Parameter pricePerKWh: Verilirse dönemin enerji miktarından tahmini
    ///   maliyet ve km başına maliyet eklenir. Sunucu maliyet alanı döndürmediğinde
    ///   kullanıcının birim fiyatıyla hesaplanır; değer "tahmini" olarak etiketlenir.
    /// Sunucudan maliyet gelmediğinde enerji × kullanıcı birim fiyatı.
    /// Değer tahmindir; fatura değildir, bu yüzden "≈" ile gösterilir.
    private static func appendCostMetrics(_ metrics: inout [ExperienceMetric],
                                          energyKWh: Double?,
                                          distanceKM: Double?,
                                          pricePerKWh: Double?) {
        guard let pricePerKWh else { return }
        let pricing = EnergyPricing(pricePerKWh: pricePerKWh)
        guard let cost = pricing.cost(forEnergyKWh: energyKWh) else { return }
        metrics.append(ExperienceMetric(label: "Tahmini maliyet", value: "≈ \(whole(cost)) ₺"))
        if let perKM = pricing.costPerKM(energyKWh: energyKWh, distanceKM: distanceKM) {
            metrics.append(ExperienceMetric(label: "Km başına", value: "\(twoDecimals(perKM)) ₺/km"))
        }
    }

    static func period(from data: Data, kind: ExperienceKind, offset: Int = 0,
                       pricePerKWh: Double? = nil) -> ExperiencePeriod? {
        guard let root = root(from: data) else { return nil }
        let listKey = kind == .journeys ? "journeys" : "charges"
        let hasList = root[listKey] != nil || root["items"] != nil
        guard hasList || root["summary"] != nil || root["period_km"] != nil || root["period_energy"] != nil else {
            return nil
        }
        let list = (root[listKey] as? [Any]) ?? (root["items"] as? [Any]) ?? []
        let summary = (root["summary"] as? [String: Any]) ?? root

        var metrics: [ExperienceMetric] = []
        if kind == .journeys {
            let totalDistance = number(summary, ["total_distance_km", "total_km", "km_total"])
            let totalEnergy = number(summary, ["total_kwh_consumed", "total_consumption_kwh", "consumption_kwh", "kwh_consumed"])
            appendMetric(&metrics, "Mesafe", distance(totalDistance))
            appendMetric(&metrics, "Toplam tüketim", energy(totalEnergy))
            appendMetric(&metrics, "Ort. tüketim", consumption(number(summary, ["avg_consumption_per_100km", "avg_kwh_per_100km", "monthly_average_consumption_kwh"])))
            appendMetric(&metrics, "Yolculuk", number(summary, ["journey_count", "total_journeys", "drive_count"]).map { whole($0) })
            let durationValue = number(summary, ["total_duration_min", "duration_min_total", "duration_min"])
                ?? number(summary, ["driving_time_hours"]).map { $0 * 60 }
            appendMetric(&metrics, "Sürüş süresi", duration(minutes: durationValue))
            appendMetric(&metrics, "Ort. hız", number(summary, ["avg_speed_kmh"]).map { "\(oneDecimal($0)) km/sa" })
            appendMetric(&metrics, "Verim puanı", number(summary, ["avg_economy_score", "economy_score", "journey_score"])
                .flatMap { (0...100).contains($0) ? "\(whole($0)) / 100" : nil })
            appendCostMetrics(&metrics, energyKWh: totalEnergy, distanceKM: totalDistance, pricePerKWh: pricePerKWh)
        } else {
            let totalEnergy = number(summary, ["total_energy_kwh", "total_kwh_added"])
            let sessions = number(summary, ["total_sessions", "monthly_charges", "charge_count", "total_charges"])
            appendMetric(&metrics, "Şarj sayısı", sessions.map { whole($0) })
            appendMetric(&metrics, "Toplam enerji", energy(totalEnergy))
            appendMetric(&metrics, "Süre", duration(minutes: number(summary, ["total_duration_min", "duration_min_total", "duration_min"])))
            if let sessions, sessions > 0, let totalEnergy, totalEnergy.isFinite, totalEnergy > 0 {
                appendMetric(&metrics, "Seans başına", "\(oneDecimal(totalEnergy / sessions)) kWh")
            }
            appendMetric(&metrics, "Birim maliyet", number(summary, ["avg_cost_per_kwh"]).map { "\(twoDecimals($0)) ₺/kWh" })
            // Sunucu gerçek tutarı döndürüyorsa tahmin gösterilmez; çelişki olmasın.
            let serverTotal = number(summary, ["total_price", "total_cost"])
            appendMetric(&metrics, "Toplam harcama", serverTotal.map { "\(twoDecimals($0)) ₺" })
            if let serverTotal, let sessions, sessions > 0 {
                appendMetric(&metrics, "Seans başına tutar", "\(twoDecimals(serverTotal / sessions)) ₺")
            } else {
                appendCostMetrics(&metrics, energyKWh: totalEnergy, distanceKM: nil, pricePerKWh: pricePerKWh)
                if let sessions, sessions > 0, let totalEnergy,
                   let estimate = EnergyPricing(pricePerKWh: pricePerKWh).cost(forEnergyKWh: totalEnergy) {
                    appendMetric(&metrics, "Seans başına tutar", "≈ \(whole(estimate / sessions)) ₺")
                }
            }
        }

        let barKey = kind == .journeys ? "period_km" : "period_energy"
        let barUnit = kind == .journeys ? "km" : "kWh"
        var bars: [ExperienceBar] = []
        if let rawBars = root[barKey] as? [Any] {
            for (index, item) in rawBars.enumerated() {
                guard let dictionary = item as? [String: Any] else { continue }
                let value = kind == .journeys
                    ? number(dictionary, ["km_total", "total_km", "distance_km", "value"])
                    : number(dictionary, ["kwh_total", "total_kwh", "kwh_added", "value"])
                guard let value, value.isFinite, value >= 0 else { continue }
                let rawLabel = firstValue(dictionary, ["period_label", "period_start", "period", "label"])
                bars.append(ExperienceBar(id: "\(index)-\(dateText(rawLabel))",
                                          label: periodLabel(rawLabel), value: value, unit: barUnit))
            }
            bars = Array(bars.suffix(12))
        }

        let records = list.enumerated().compactMap { index, item -> ExperienceRecord? in
            guard let dictionary = item as? [String: Any] else { return nil }
            return record(dictionary, kind: kind, index: offset + index, pricePerKWh: pricePerKWh)
        }

        let paginationKey = kind == .journeys ? "journeys_pagination" : "charges_pagination"
        let pagination = root[paginationKey] as? [String: Any]
        let hasMore = bool(pagination?["has_more"]) ?? bool(root["has_more"]) ?? (list.count >= 20)
        let nextOffset = offset + list.count
        return ExperiencePeriod(metrics: metrics, bars: bars, records: records, hasMore: hasMore,
                                nextOffset: nextOffset, receivedCount: list.count)
    }

    private static func record(_ dictionary: [String: Any], kind: ExperienceKind, index: Int,
                               pricePerKWh: Double? = nil) -> ExperienceRecord {
        let rawID = recordID(dictionary)
        let stableID = rawID.isEmpty ? "\(kind.rawValue)-\(index)" : rawID
        let dateText = dateText(firstValue(dictionary, ["start_ts", "start_time", "event_date", "date", "created_at"]))
        var metrics: [ExperienceMetric] = []
        let subtitle: String
        if kind == .charges {
            let start = number(dictionary, ["soc_start_pct"])
            let end = number(dictionary, ["soc_end_pct"])
            if start != nil || end != nil {
                metrics.append(ExperienceMetric(label: "SOC", value: "\(whole(start))% → \(whole(end))%"))
            }
            let addedEnergy = number(dictionary, ["kwh_added", "total_energy_kwh"])
            if let energy = energy(addedEnergy) {
                metrics.append(ExperienceMetric(label: "Enerji", value: energy))
            }
            // Gerçek yanıtta `cost` birim fiyat (₺/kWh), `total_price` seans tutarıdır.
            if let servedCost = number(dictionary, ["total_price"]) {
                metrics.append(ExperienceMetric(label: "Tutar", value: "\(twoDecimals(servedCost)) ₺"))
            } else if let pricePerKWh,
                      let estimate = EnergyPricing(pricePerKWh: pricePerKWh).cost(forEnergyKWh: addedEnergy) {
                metrics.append(ExperienceMetric(label: "Tahmini tutar", value: "≈ \(whole(estimate)) ₺"))
            }
            if let duration = duration(minutes: number(dictionary, ["duration_min", "total_duration_min"])) {
                metrics.append(ExperienceMetric(label: "Süre", value: duration))
            }
            if let type = display(text(dictionary, ["charge_type"])) {
                metrics.append(ExperienceMetric(label: "Tür", value: type))
            }
            subtitle = chargePlace(dictionary) ?? ""
        } else {
            if let distance = distance(number(dictionary, ["total_distance_km", "distance_km", "total_km"])) {
                metrics.append(ExperienceMetric(label: "Mesafe", value: distance))
            }
            if let energy = energy(number(dictionary, ["total_kwh_consumed", "kwh_consumed"])) {
                metrics.append(ExperienceMetric(label: "Tüketim", value: energy))
            }
            if let consumption = consumption(number(dictionary, ["avg_consumption_per_100km", "avg_kwh_per_100km"])) {
                metrics.append(ExperienceMetric(label: "Ort. tüketim", value: consumption))
            }
            if let duration = duration(minutes: number(dictionary, ["duration_min", "duration_min_total"])) {
                metrics.append(ExperienceMetric(label: "Süre", value: duration))
            }
            if let speed = number(dictionary, ["avg_speed_kmh"]) {
                metrics.append(ExperienceMetric(label: "Ort. hız", value: "\(oneDecimal(speed)) km/sa"))
            }
            subtitle = journeyRoute(dictionary) ?? ""
        }
        return ExperienceRecord(id: stableID, detailID: rawID.isEmpty ? nil : rawID, kind: kind,
                                dateText: dateText, subtitle: subtitle, metrics: metrics)
    }

    // MARK: - Ayrıntı

    static func detail(from data: Data, kind: ExperienceKind, pricePerKWh: Double? = nil) -> ExperienceDetail? {
        guard let root = root(from: data) else { return nil }
        let dateText = dateText(firstValue(root, ["start_ts", "start_time", "event_date", "date", "created_at"]))
        let subtitle = kind == .charges ? (chargePlace(root) ?? "") : (journeyRoute(root) ?? "")
        var metrics: [ExperienceMetric] = []
        var notes: [String] = []
        var sections: [ExperienceDetailSection] = []

        if kind == .charges {
            appendMetric(&metrics, "Başlangıç SOC", percent(number(root, ["soc_start_pct"])))
            appendMetric(&metrics, "Bitiş SOC", percent(number(root, ["soc_end_pct"])))
            appendMetric(&metrics, "Eklenen enerji", energy(number(root, ["kwh_added"])))
            appendMetric(&metrics, "Süre", duration(minutes: number(root, ["duration_min", "total_duration_min"])))
            appendMetric(&metrics, "Birim maliyet", number(root, ["avg_cost_per_kwh"]).map { "\(twoDecimals($0)) ₺/kWh" })

            let added = number(root, ["kwh_added"])
            let minutes = number(root, ["duration_min", "total_duration_min"])
            if let added, let minutes, minutes > 0 {
                notes.append("Seans ortalama gücü: \(oneDecimal(added / (minutes / 60))) kW")
            }
            if let type = display(text(root, ["charge_type"])) {
                notes.append("Şarj türü: \(type)")
            }
            if let price = number(root, ["total_price"]) {
                notes.append("Servisteki maliyet: \(twoDecimals(price)) ₺ · Ödeme/fatura olarak doğrulanmadı.")
            } else if let pricePerKWh,
                      let estimate = EnergyPricing(pricePerKWh: pricePerKWh).cost(forEnergyKWh: added) {
                let pricing = EnergyPricing(pricePerKWh: pricePerKWh)
                notes.append("Tahmini tutar: ≈ \(whole(estimate)) ₺ · \(pricing.priceText) varsayımıyla; fatura değildir.")
            }
        } else {
            appendMetric(&metrics, "Mesafe", distance(number(root, ["total_distance_km", "distance_km", "total_km"])))
            appendMetric(&metrics, "Tüketim", energy(number(root, ["total_kwh_consumed", "kwh_consumed"])))
            appendMetric(&metrics, "Ort. tüketim", consumption(number(root, ["avg_consumption_per_100km", "avg_kwh_per_100km"])))
            appendMetric(&metrics, "Ort. hız", number(root, ["avg_speed_kmh"]).map { "\(oneDecimal($0)) km/sa" })
            let durationValue = number(root, ["duration_min_total", "duration_min", "total_duration_min"])
            appendMetric(&metrics, "Süre", duration(minutes: durationValue))
            appendMetric(&metrics, "Verim", percent(number(root, ["trip_efficiency_pct"])))
            appendMetric(&metrics, "Ekonomi puanı", number(root, ["avg_economy_score", "economy_score"])
                .flatMap { (0...100).contains($0) ? "\(whole($0)) / 100" : nil })
            appendMetric(&metrics, "Rakım değişimi", number(root, ["elevation_change_m"]).map { "\(oneDecimal($0)) m" })
            appendMetric(&metrics, "Dış sıcaklık farkı", number(root, ["outside_temp_change_c"]).map { "\(oneDecimal($0)) °C" })
            appendMetric(&metrics, "Tercih edilen mod", number(root, ["preferred_mode_rate_pct"]).map { "\(whole($0))%" })

            let sectionSpecs: [(String, String)] = [
                ("ac_usage", "Klima kullanımı"),
                ("elevation_profile", "Rakım profili"),
                ("drive_mode_profile", "Sürüş modu dağılımı")
            ]
            for (key, title) in sectionSpecs {
                guard let dictionary = root[key] as? [String: Any] else { continue }
                var values: [ExperienceMetric] = []
                for (index, entry) in dictionary.keys.sorted().enumerated() where index < 12 {
                    guard let raw = dictionary[entry] else { continue }
                    if let value = detailValue(raw, key: entry, section: key) {
                        values.append(ExperienceMetric(label: label(forKey: entry), value: value))
                    }
                }
                if !values.isEmpty {
                    sections.append(ExperienceDetailSection(id: key, title: title, metrics: values))
                }
            }
        }

        guard !metrics.isEmpty || !notes.isEmpty || !sections.isEmpty else { return nil }
        return ExperienceDetail(kind: kind, dateText: dateText, subtitle: subtitle,
                                metrics: metrics, notes: notes, sections: sections)
    }

    private static func detailValue(_ value: Any, key: String, section: String) -> String? {
        if let number = number(value) {
            let lower = key.lowercased()
            if section == "ac_usage" || section == "drive_mode_profile" {
                guard (0...100).contains(number) else { return oneDecimal(number) }
                return "\(whole(number))%"
            }
            if lower.contains("pct") || lower.contains("percent") { return "\(whole(number))%" }
            if lower.contains("kwh") { return "\(twoDecimals(number)) kWh" }
            if lower.contains("min") { return duration(minutes: number) }
            if lower.contains("km") { return "\(oneDecimal(number)) km" }
            return oneDecimal(number)
        }
        if let string = text(value) { return display(string) }
        return nil
    }

    // MARK: - Yer / rota

    private static func recordID(_ dictionary: [String: Any]) -> String {
        text(dictionary, ["charge_id", "journey_id", "trip_id", "id"]) ?? ""
    }

    private static func chargePlace(_ dictionary: [String: Any]) -> String? {
        for key in ["station_name", "charge_location", "charging_location", "station_address",
                    "location", "address", "station"] {
            if let value = dictionary[key], let text = placeText(value) ?? coordinateText(value) {
                return text
            }
        }
        return coordinateText(dictionary)
    }

    private static func journeyRoute(_ dictionary: [String: Any]) -> String? {
        let start = routePlace(dictionary, prefix: "start")
        let end = routePlace(dictionary, prefix: "end")
        if let start, let end { return "\(start) → \(end)" }
        return start ?? end
    }

    private static func routePlace(_ dictionary: [String: Any], prefix: String) -> String? {
        let keys = [
            "\(prefix)_location", "\(prefix)Location", "\(prefix)_address", "\(prefix)Address",
            prefix, prefix == "start" ? "origin" : "destination"
        ]
        for key in keys {
            if let value = dictionary[key] {
                if let text = placeText(value) { return text }
                if let coordinate = coordinateText(value) { return coordinate }
            }
        }
        let latitude = number(dictionary, ["\(prefix)_lat", "\(prefix)_latitude", "\(prefix)Latitude"])
        let longitude = number(dictionary, ["\(prefix)_lon", "\(prefix)_lng", "\(prefix)_longitude", "\(prefix)Longitude"])
        if let latitude, let longitude, validCoordinate(latitude, longitude) {
            return String(format: "%.5f, %.5f", latitude, longitude)
        }
        return nil
    }

    private static func placeText(_ value: Any?, depth: Int = 0) -> String? {
        guard depth <= 4 else { return nil }
        if let string = text(value) {
            if string.hasPrefix("{"), let data = string.data(using: .utf8),
               let dictionary = try? JSONSerialization.jsonObject(with: data) {
                return placeText(dictionary, depth: depth + 1)
            }
            if coordinate(from: string) != nil { return nil }
            return string
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        for key in ["name", "title", "station_name", "display_name", "displayName",
                    "formatted_address", "formattedAddress", "address", "addressLine"] {
            if let text = placeText(dictionary[key], depth: depth + 1) { return text }
        }
        let parts = ["neighborhood", "district", "county", "city", "province"]
            .compactMap { placeText(dictionary[$0], depth: depth + 1) }
        if !parts.isEmpty {
            var unique: [String] = []
            for part in parts where !unique.contains(part) { unique.append(part) }
            return unique.joined(separator: ", ")
        }
        for key in ["location", "content", "position", "place", "station"] {
            if let text = placeText(dictionary[key], depth: depth + 1) { return text }
        }
        return nil
    }

    private static func coordinateText(_ value: Any?) -> String? {
        guard let coordinate = coordinate(from: value) else { return nil }
        return String(format: "%.5f, %.5f", coordinate.0, coordinate.1)
    }

    private static func coordinate(from value: Any?, depth: Int = 0) -> (Double, Double)? {
        guard depth <= 5 else { return nil }
        if let string = text(value) {
            let numbers = string.replacingOccurrences(of: ";", with: ",")
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if numbers.count == 2, validCoordinate(numbers[0], numbers[1]) {
                return (numbers[0], numbers[1])
            }
            if string.hasPrefix("{"), let data = string.data(using: .utf8),
               let dictionary = try? JSONSerialization.jsonObject(with: data) {
                return coordinate(from: dictionary, depth: depth + 1)
            }
            return nil
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        let latitude = coordinateNumber(dictionary["latitude"] ?? dictionary["lat"], keys: ["latitudeValue", "latitude", "lat", "value"])
        let longitude = coordinateNumber(dictionary["longitude"] ?? dictionary["lon"] ?? dictionary["lng"] ?? dictionary["long"], keys: ["longitudeValue", "longitude", "lon", "lng", "long", "value"])
        if let latitude, let longitude, validCoordinate(latitude, longitude) {
            return (latitude, longitude)
        }
        if let coordinates = dictionary["coordinates"] as? [Any], coordinates.count >= 2,
           let longitude = number(coordinates[0]), let latitude = number(coordinates[1]),
           validCoordinate(latitude, longitude) {
            return (latitude, longitude)
        }
        for key in ["location", "content", "position", "point", "place", "station"] {
            if let found = coordinate(from: dictionary[key], depth: depth + 1) { return found }
        }
        return nil
    }

    private static func coordinateNumber(_ value: Any?, keys: [String]) -> Double? {
        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let value = number(dictionary[key]) { return value }
            }
            return nil
        }
        return number(value)
    }

    private static func validCoordinate(_ latitude: Double, _ longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        !(latitude == 0 && longitude == 0)
    }

    // MARK: - Ortak

    private static func root(from data: Data) -> [String: Any]? {
        guard var root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            return nil
        }
        if let nested = root["data"] as? [String: Any], looksLikeExperience(nested) {
            root = nested
        }
        return root
    }

    private static func looksLikeExperience(_ dictionary: [String: Any]) -> Bool {
        ["this_month", "last_month", "all_time", "journeys", "charges", "summary",
         "last_journey", "last_charge", "period_km", "period_energy", "community_comparison"]
            .contains { dictionary[$0] != nil }
    }

    private static func appendMetric(_ metrics: inout [ExperienceMetric], _ label: String, _ value: String?) {
        guard let value, metrics.count < 10, !metrics.contains(where: { $0.label == label }) else { return }
        metrics.append(ExperienceMetric(label: label, value: value))
    }

    private static func firstValue(_ dictionary: [String: Any], _ keys: [String]) -> Any? {
        for key in keys {
            if let value = dictionary[key], !(value is NSNull) { return value }
        }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        return nil
    }

    private static func nonNegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static let monthNames = ["Oca", "Şub", "Mar", "Nis", "May", "Haz",
                                     "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
}

private extension String {
    var upperCasedTr: String { uppercased(with: Locale(identifier: "tr_TR")) }
}
