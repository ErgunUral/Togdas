import Foundation

/// Son bir saatlik BLE sayaç özeti. Kaynak, VIN'i redakte edilmiş yerel olay
/// günlüğüdür; tanı özeti kimlik bilgisi veya ham paket içermez.
struct BLEDiagnosticReport: Equatable {
    static let window: TimeInterval = 60 * 60

    let generatedAt: Date
    let retainedEventCount: Int
    let events: [BLEDiagnosticEvent]
    let failureCounts: [BleFailureKind: Int]
    let scanStarts: Int
    let scanRotations: Int
    let scanExhaustions: Int
    let directReconnects: Int
    let radioOnEvents: Int
    let radioOffEvents: Int
    let successfulConnections: Int
    let disconnects: Int
    let readyTransitions: Int
    let missingVehicleKeys: Int
    let telemetryVerificationFailures: Int
    let staleGATTRSSISamples: Int
    let proximityFreshCycleResets: Int
    let rssiSamples: [Int]

    init(events allEvents: [BLEDiagnosticEvent], now: Date = Date()) {
        generatedAt = now
        retainedEventCount = allEvents.count
        let start = now.addingTimeInterval(-Self.window)
        events = allEvents.filter { $0.timestamp >= start && $0.timestamp <= now }

        var failures: [BleFailureKind: Int] = [:]
        var values: [Int] = []
        var scans = 0
        var rotations = 0
        var exhausted = 0
        var direct = 0
        var radioOn = 0
        var radioOff = 0
        var connected = 0
        var disconnected = 0
        var ready = 0
        var missingKeys = 0
        var badTelemetry = 0
        var staleRSSI = 0
        var freshCycleResets = 0
        let structuredFailureEvents = events.filter { $0.message.contains("failure_kind ·") }

        for event in events {
            let message = event.message
            if message.contains("gatt_scan_start") { scans += 1 }
            if message.contains("scan_rotate") { rotations += 1 }
            if message.contains("scan_exhausted") { exhausted += 1 }
            if message.contains("gatt_direct_reconnect") { direct += 1 }
            if message.contains("radio_on ·") { radioOn += 1 }
            if message.contains("radio_off ·") { radioOff += 1 }
            if message.contains("BLE bağlantısı kuruldu") { connected += 1 }
            if message.contains("BLEDisconnected") { disconnected += 1 }
            if message.contains("Bağlantı durumu: Komut hazır")
                || message.contains("Araç kimliği doğrulandı; komut kanalı hazır") { ready += 1 }
            if message.contains("vehicleKeyMissing") { missingKeys += 1 }
            if message.contains("telemetry_verify_failed") { badTelemetry += 1 }
            if message.contains("gatt_rssi_stale") { staleRSSI += 1 }
            if message.contains("proximity_fresh_cycle") { freshCycleResets += 1 }
            if let rssi = Self.rssi(in: message) { values.append(rssi) }

            if message.contains("failure_kind ·"),
               let kind = Self.failureKind(in: message) {
                failures[kind, default: 0] += 1
            } else if message.contains("BLEDisconnected") {
                // Eski tanı kayıtlarında failure_kind henüz yoktu.
                let hasStructuredPair = structuredFailureEvents.contains {
                    abs($0.timestamp.timeIntervalSince(event.timestamp)) <= 5
                }
                if !hasStructuredPair {
                    let kind = Self.legacyFailureKind(in: message)
                    failures[kind, default: 0] += 1
                }
            }
        }

        failureCounts = failures
        scanStarts = scans
        scanRotations = rotations
        scanExhaustions = exhausted
        directReconnects = direct
        radioOnEvents = radioOn
        radioOffEvents = radioOff
        successfulConnections = connected
        disconnects = disconnected
        readyTransitions = ready
        missingVehicleKeys = missingKeys
        telemetryVerificationFailures = badTelemetry
        staleGATTRSSISamples = staleRSSI
        proximityFreshCycleResets = freshCycleResets
        rssiSamples = values
    }

    var totalFailures: Int { failureCounts.values.reduce(0, +) }
    var averageRSSI: Double? {
        guard !rssiSamples.isEmpty else { return nil }
        return Double(rssiSamples.reduce(0, +)) / Double(rssiSamples.count)
    }
    var minimumRSSI: Int? { rssiSamples.min() }
    var maximumRSSI: Int? { rssiSamples.max() }
    var latestRSSI: Int? { rssiSamples.last }

    var rssiSummary: String {
        guard let minimumRSSI, let maximumRSSI, let averageRSSI else { return "—" }
        let latest = latestRSSI.map { " · son \($0)" } ?? ""
        return "min \(minimumRSSI) · ort \(Int(averageRSSI.rounded())) · max \(maximumRSSI)\(latest) dBm"
    }

    var shareText: String {
        let failures = BleFailureKind.allCases.compactMap { kind -> String? in
            guard let count = failureCounts[kind], count > 0 else { return nil }
            return "• \(kind.summary): \(count)"
        }
        return ([
            "Toqdas BLE tanı özeti · son 60 dk",
            "Olay: \(events.count) / kayıtlı toplam: \(retainedEventCount)",
            "Tarama: \(scanStarts) · devir: \(scanRotations) · sonuçsuz: \(scanExhaustions) · doğrudan yeniden bağlanma: \(directReconnects)",
            "Bağlantı: \(successfulConnections) · kopma: \(disconnects) · READY: \(readyTransitions)",
            "Radyo aç/kapat: \(radioOnEvents)/\(radioOffEvents) · anahtar eksik: \(missingVehicleKeys)",
            "RSSI örnek: \(rssiSamples.count) · \(rssiSummary)",
            "Telemetri doğrulama hatası: \(telemetryVerificationFailures) · eski GATT RSSI: \(staleGATTRSSISamples)",
            "Yakınlık yeni oturum sıfırlaması: \(proximityFreshCycleResets)",
            "Oluşturulma: \(generatedAt.formatted(date: .abbreviated, time: .standard))"
        ] + failures).joined(separator: "\n")
    }

    private static func failureKind(in message: String) -> BleFailureKind? {
        let detail = message.lowercased()
        if detail.contains("connection_timeout") || detail.contains("connection_failed") { return .signal }
        if detail.contains("peripheral_disconnected") { return .peerClosed }
        if detail.contains("pairing_lost") { return .pairingLost }
        if detail.contains("radio_off") { return .radioOff }
        if detail.contains("service_discovery") { return .serviceDiscovery }
        if detail.contains("gatt_error") { return .gatt }
        if detail.contains("connection_limit") { return .busy }
        if detail.contains("unknown") { return .unknown }
        return nil
    }

    private static func legacyFailureKind(in message: String) -> BleFailureKind {
        let lowercased = message.lowercased()
        if lowercased.contains("connection timeout") || lowercased.contains("timeout")
            || lowercased.contains("zaman aşımı") { return .signal }
        if lowercased.contains("eşleşme") || lowercased.contains("pairing") { return .pairingLost }
        if lowercased.contains("servis") { return .serviceDiscovery }
        if lowercased.contains("cberror 7") || lowercased.contains("araç bağlantıyı kapattı") { return .peerClosed }
        return .unknown
    }

    private static func rssi(in message: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)RSSI\s*[:=]?\s*(-?\d+)\s*dBm"#),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        return Int(message[range])
    }
}
