import Foundation

struct EPDKConnector: Codable, Equatable, Identifiable {
    let id: String
    let type: String
    let socket: String
    let powerKW: Double?

    var displayText: String {
        let socketName: String
        switch socket {
        case "AC_TYPE2": socketName = "Type 2"
        case "DC_CCS": socketName = "CCS"
        case "DC_CHADEMO": socketName = "CHAdeMO"
        case "UNKNOWN", "": socketName = "Tip bilgisi yok"
        default: socketName = socket
        }
        let power = powerKW.map { " · \(Int($0.rounded())) kW" } ?? ""
        return "\(type) · \(socketName)\(power)"
    }
}

struct EPDKStation: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let brand: String
    let operatorName: String
    let address: String
    let access: String
    let latitude: Double?
    let longitude: Double?
    let connectors: [EPDKConnector]

    var isPublic: Bool { access == "HALKA_ACIK" }

    var searchableText: String {
        [name, brand, operatorName, address]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
    }

    func distanceKM(fromLatitude latitude: Double, longitude: Double) -> Double? {
        guard let stationLatitude = self.latitude,
              let stationLongitude = self.longitude,
              latitude.isFinite, longitude.isFinite else { return nil }
        let radians = Double.pi / 180
        let dLat = (stationLatitude - latitude) * radians
        let dLon = (stationLongitude - longitude) * radians
        let a = pow(sin(dLat / 2), 2)
            + cos(latitude * radians) * cos(stationLatitude * radians) * pow(sin(dLon / 2), 2)
        return 12_742 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}

struct EPDKCatalog: Codable, Equatable {
    let fetchedAt: Date
    let stations: [EPDKStation]

    var isOlderThanOneDay: Bool { Date().timeIntervalSince(fetchedAt) > 86_400 }

    func filtered(
        query: String,
        connectorType: String,
        minimumPowerKW: Double = 0,
        publicOnly: Bool = true,
        origin: (latitude: Double, longitude: Double)?,
        radiusKM: Double,
        limit: Int = 30
    ) -> [(station: EPDKStation, distanceKM: Double?)] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))

        return stations.compactMap { station in
            guard !publicOnly || station.isPublic else { return nil }
            guard normalizedQuery.isEmpty || station.searchableText.contains(normalizedQuery) else { return nil }

            let connectors = station.connectors.filter { connector in
                let typeMatches = connectorType == "ALL" || connector.type == connectorType
                let powerMatches = minimumPowerKW <= 0 || (connector.powerKW ?? 0) >= minimumPowerKW
                return typeMatches && powerMatches
            }
            guard connectorType == "ALL" && minimumPowerKW <= 0 || !connectors.isEmpty else { return nil }

            let distance = origin.flatMap {
                station.distanceKM(fromLatitude: $0.latitude, longitude: $0.longitude)
            }
            if origin != nil, radiusKM > 0 {
                guard let distance, distance <= radiusKM else { return nil }
            }
            return (station, distance)
        }
        .sorted { lhs, rhs in
            switch (lhs.distanceKM, rhs.distanceKM) {
            case let (left?, right?):
                if left != right { return left < right }
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            return lhs.station.name.localizedStandardCompare(rhs.station.name) == .orderedAscending
        }
        .prefix(max(0, limit))
        .map { $0 }
    }
}

enum EPDKCatalogParser {
    enum ParseError: LocalizedError, Equatable {
        case invalidContract
        case rowCountMismatch
        case invalidStationID

        var errorDescription: String? {
            switch self {
            case .invalidContract: "EPDK yanıt biçimi beklenen sözleşmeyle uyuşmuyor."
            case .rowCountMismatch: "EPDK kataloğu eksik veya tutarsız geldi."
            case .invalidStationID: "EPDK kataloğunda kimliği eksik/tekrarlı istasyon var."
            }
        }
    }

    static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> EPDKCatalog {
        let envelope = try JSONDecoder().decode(RawEnvelope.self, from: data)
        guard envelope.statusCode == 200,
              let rows = envelope.data,
              envelope.errors?.isEmpty != false else {
            throw ParseError.invalidContract
        }
        guard envelope.numRows == rows.count, rows.count <= 30_000 else {
            throw ParseError.rowCountMismatch
        }

        var ids = Set<String>()
        var stations: [EPDKStation] = []
        stations.reserveCapacity(rows.count)
        for row in rows {
            let id = row.stationID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, ids.insert(id).inserted else { throw ParseError.invalidStationID }

            let coordinatesAreValid: Bool
            if let latitude = row.latitude, let longitude = row.longitude {
                coordinatesAreValid = latitude.isFinite && longitude.isFinite
                    && (35...43).contains(latitude) && (25...46).contains(longitude)
            } else {
                coordinatesAreValid = false
            }

            let connectors = (row.sockets ?? []).prefix(200).enumerated().map { index, socket in
                let power = socket.powerKW.flatMap { value in
                    value.isFinite && value > 0 && value <= 2_000 ? value : nil
                }
                let rawType = socket.type.uppercased()
                let type = rawType == "AC" || rawType == "DC" ? rawType : "UNKNOWN"
                let rawSocket = socket.socket.uppercased()
                let knownSockets = ["AC_TYPE2", "DC_CCS", "DC_CHADEMO"]
                let socketType = knownSockets.contains(rawSocket) ? rawSocket : "UNKNOWN"
                return EPDKConnector(
                    id: socket.socketID.isEmpty ? "\(id)-\(index)" : socket.socketID,
                    type: type,
                    socket: socketType,
                    powerKW: power
                )
            }

            stations.append(EPDKStation(
                id: id,
                name: String(row.name.prefix(240)),
                brand: String(row.brand.prefix(600)),
                operatorName: String(row.operatorName.prefix(600)),
                address: String(row.address.prefix(800)),
                access: String(row.access.prefix(40)).uppercased(),
                latitude: coordinatesAreValid ? row.latitude : nil,
                longitude: coordinatesAreValid ? row.longitude : nil,
                connectors: connectors
            ))
        }
        return EPDKCatalog(fetchedAt: fetchedAt, stations: stations)
    }
}

private struct RawEnvelope: Decodable {
    let statusCode: Int?
    let numRows: Int?
    let errors: [JSONValue]?
    let data: [RawStation]?
}

private struct RawStation: Decodable {
    let stationID: String
    let name: String
    let brand: String
    let operatorName: String
    let address: String
    let access: String
    let latitude: Double?
    let longitude: Double?
    let sockets: [RawSocket]?

    private enum CodingKeys: String, CodingKey {
        case stationID = "sarjIstasyonuNo"
        case name = "sarjIstasyonuAdi"
        case brand = "marka"
        case operatorName = "sarjAgiIsletmecisiUnvan"
        case address = "adres"
        case access = "hizmetSekli"
        case latitude = "enlem"
        case longitude = "boylam"
        case sockets = "soketler"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stationID = values.flexibleString(.stationID) ?? ""
        name = values.flexibleString(.name) ?? ""
        brand = values.flexibleString(.brand) ?? ""
        operatorName = values.flexibleString(.operatorName) ?? ""
        address = values.flexibleString(.address) ?? ""
        access = values.flexibleString(.access) ?? "UNKNOWN"
        latitude = values.flexibleDouble(.latitude)
        longitude = values.flexibleDouble(.longitude)
        sockets = try? values.decodeIfPresent([RawSocket].self, forKey: .sockets)
    }
}

private struct RawSocket: Decodable {
    let socketID: String
    let type: String
    let socket: String
    let powerKW: Double?

    private enum CodingKeys: String, CodingKey {
        case socketID = "soketNo"
        case type = "soketTipi"
        case socket = "soketTuru"
        case powerKW = "soketGucu"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        socketID = values.flexibleString(.socketID) ?? ""
        type = values.flexibleString(.type) ?? "UNKNOWN"
        socket = values.flexibleString(.socket) ?? "UNKNOWN"
        powerKW = values.flexibleDouble(.powerKW)
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? [JSONValue](from: decoder) { self = .array(array) }
        else { self = .object(try [String: JSONValue](from: decoder)) }
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}
