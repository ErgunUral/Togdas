import Foundation
import CryptoKit
import Security
import CoreFoundation

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct OAuthAttempt {
    let state: String
    let verifier: String
    let createdAt: Date
    static let redirect = "superapp://prod/callback"

    init() throws {
        state = try Self.random()
        verifier = try Self.random()
        createdAt = Date()
    }

    init(state: String, verifier: String, createdAt: Date) {
        self.state = state
        self.verifier = verifier
        self.createdAt = createdAt
    }

    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AppError.message("Güvenli giriş anahtarı üretilemedi.")
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    var authorizationURL: URL {
        var url = URLComponents(string: "https://toggid.togg.cloud/auth/realms/toggid/protocol/openid-connect/auth")!
        url.queryItems = [
            .init(name: "client_id", value: "super-app"),
            .init(name: "redirect_uri", value: Self.redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        return url.url!
    }

    func code(from url: URL, now: Date = Date()) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "superapp", parts.host == "prod", parts.path == "/callback",
              parts.port == nil, parts.user == nil, parts.password == nil, parts.fragment == nil,
              (0...600).contains(now.timeIntervalSince(createdAt)) else {
            throw AppError.message("Giriş dönüş adresi veya süresi geçersiz.")
        }
        let items = parts.queryItems ?? []
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }
        guard values("state") == [state], items.filter({ $0.name == "state" }).count == 1 else {
            throw AppError.message("Giriş doğrulanamadı. Yeniden deneyin.")
        }
        guard !items.contains(where: { $0.name == "error" }) else {
            throw AppError.message("Togg ID giriş isteğini tamamlamadı.")
        }
        let codes = values("code")
        guard codes.count == 1, items.filter({ $0.name == "code" }).count == 1,
              !codes[0].isEmpty, codes[0].count <= 10000 else {
            throw AppError.message("Geçerli giriş kodu alınamadı.")
        }
        return codes[0]
    }
}

struct Vehicle: Identifiable, Equatable {
    let vin: String
    let name: String
    let plate: String
    let model: String
    var id: String { vin }
    var title: String { !name.isEmpty ? name : (!model.isEmpty ? model : "Togg") }

    static func parse(_ data: Data) throws -> [Vehicle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ownedVins"] is [Any] || json["friendVins"] is [Any] else {
            throw AppError.message("Araç listesi beklenen biçimde değil.")
        }
        var seen = Set<String>()
        return ["ownedVins", "friendVins"].flatMap { json[$0] as? [Any] ?? [] }.compactMap { item in
            let fields = item as? [String: Any] ?? ["vin": item]
            let vin = fields["vin"] as? String ?? fields["vinNumber"] as? String ?? ""
            guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil,
                  seen.insert(vin).inserted else { return nil }
            return Vehicle(vin: vin, name: fields["name"] as? String ?? "",
                           plate: fields["plateNumber"] as? String ?? "", model: fields["model"] as? String ?? "")
        }
    }
}

enum FormEncoding {
    static func data(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
}

enum TirePosition: String, CaseIterable, Equatable {
    case frontLeft, frontRight, rearLeft, rearRight

    var title: String {
        switch self {
        case .frontLeft: return "Sol Ön"
        case .frontRight: return "Sağ Ön"
        case .rearLeft: return "Sol Arka"
        case .rearRight: return "Sağ Arka"
        }
    }
}

struct TireReading: Equatable {
    let position: TirePosition
    let pressurePSI: Double?
    let temperatureC: Double?
}

struct VehicleTelemetry {
    let batteryPercent: Double?
    let rangeKM: Double?
    let auxiliaryBatteryPercent: Double?
    let chargingState: String?
    let vehicleUpdatedAt: Date?
    let odometerKM: Double?
    let outsideTemperatureC: Double?
    let insideTemperatureC: Double?
    let brakeWarning: Bool?
    let engineWarning: Bool?
    let driveMode: String?
    let latitude: Double?
    let longitude: Double?
    let tirePressureAvailable: Bool
    let tires: [TireReading]

    var coordinateText: String? {
        guard let latitude, let longitude else { return nil }
        return String(
            format: "%.5f, %.5f",
            locale: Locale(identifier: "en_US_POSIX"),
            latitude,
            longitude
        )
    }

    var driveModeText: String? {
        guard let driveMode else { return nil }
        switch driveMode.uppercased() {
        case "DRIVEMODE_COMFORT": return "Konfor"
        default:
            let cleaned = driveMode.replacingOccurrences(of: "DRIVEMODE_", with: "")
            return cleaned.isEmpty ? driveMode : cleaned.capitalized(with: Locale(identifier: "tr_TR"))
        }
    }

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let telemetry = root["telemetry"] as? [String: Any] else {
            throw AppError.message("Araç telemetrisi beklenen biçimde değil.")
        }
        func value(_ path: [String]) -> Any? {
            var current: Any = telemetry
            for key in path {
                guard let next = (current as? [String: Any])?[key] else { return nil }
                current = next
            }
            return current
        }
        func number(_ path: [String], range: ClosedRange<Double>) -> Double? {
            guard let raw = value(path) as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() else { return nil }
            let result = raw.doubleValue
            return result.isFinite && range.contains(result) ? result : nil
        }
        func boolean(_ path: [String]) -> Bool? {
            if let raw = value(path) as? NSNumber, CFGetTypeID(raw) == CFBooleanGetTypeID() {
                return raw.boolValue
            }
            if let text = value(path) as? String {
                switch text.lowercased() {
                case "true": return true
                case "false": return false
                default: return nil
                }
            }
            return nil
        }
        batteryPercent = number(["battery", "content", "batteryStateOfCharge", "batteryStateOfChargeValue"], range: 0...100)
        rangeKM = number(["vehicleRange", "content", "estRange", "range"], range: 0...Double.greatestFiniteMagnitude)
        // 12 V akü API'de iç içe nesne olarak gelir; düz sayı biçimini de destekle.
        auxiliaryBatteryPercent =
            number(["batteryPowerStatus", "batteryPowerStatusContent", "lowVoltageStateOfChargeValue", "lowVoltageStateOfChargeValue"], range: 0...100)
            ?? number(["batteryPowerStatus", "batteryPowerStatusContent", "lowVoltageStateOfChargeValue"], range: 0...100)
        let charging = value(["obcState", "content", "chargeMode", "chargeModeEnumValue"]) as? String
        chargingState = charging?.isEmpty == false ? charging : nil
        if let raw = value(["updatedOn"]) as? String {
            vehicleUpdatedAt = VehicleTelemetry.date(from: raw)
        } else {
            vehicleUpdatedAt = nil
        }
        // Sayaç metre cinsinden gelir; ekranda kilometre gösterilir.
        let odometerMeters = number(
            ["odometerStatus", "odometerStatusContent", "odometer", "odometerValue"],
            range: 0...2_000_000_000
        ) ?? number(
            ["odometerStatus", "content", "odometer", "odometerValue"],
            range: 0...2_000_000_000
        )
        odometerKM = odometerMeters.map { $0 / 1000 }
        outsideTemperatureC = number(
            ["odometerStatus", "odometerStatusContent", "outsideTemp", "outsideTempValue"],
            range: -60...80
        ) ?? number(
            ["odometerStatus", "content", "outsideTemp", "outsideTempValue"],
            range: -60...80
        )
        insideTemperatureC = number(
            ["odometerStatus", "odometerStatusContent", "insideTemp", "insideTempValue"],
            range: -60...80
        ) ?? number(
            ["odometerStatus", "content", "insideTemp", "insideTempValue"],
            range: -60...80
        )
        brakeWarning = boolean(["breakWarning"])
        engineWarning = boolean(["engineWarning"])
        let mode = value(["driveMode", "content", "driveModeState", "driveMode"]) as? String
        driveMode = mode?.isEmpty == false ? mode : nil
        latitude = number(["location", "content", "latitude", "latitudeValue"], range: -90...90)
        longitude = number(["location", "content", "longitude", "longitudeValue"], range: -180...180)

        let readings = TirePosition.allCases.map { position -> TireReading in
            let pressureKPa = number(
                ["tirePressure", "content", position.rawValue, position.rawValue + "Value"],
                range: 0...1_000
            )
            let temperature = number(
                ["tireTemperature", "tireTemperatureContent",
                 position.rawValue + "TireTemp", position.rawValue + "TireTempValue"],
                range: -60...150
            )
            return TireReading(
                position: position,
                pressurePSI: pressureKPa.map { $0 / 6.894757293168 },
                temperatureC: temperature
            )
        }
        tires = readings
        tirePressureAvailable = readings.contains { $0.pressurePSI != nil }
    }

    private static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
