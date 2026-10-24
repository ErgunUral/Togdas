import Foundation

/// Togg uzaktan kontrol servisinin kullandığı küçük protobuf ve gRPC çerçeve
/// yardımcıları. Alan numaraları resmî Toqdaş köprüsündeki iklim çağrılarıyla
/// aynıdır; yalnızca ihtiyaç duyulan mesajlar kodlanır.
enum GRPCProto {
    enum Value: Equatable {
        case varint(UInt64)
        case fixed32(UInt32)
        case bytes(Data)
    }

    /// gRPC length-prefixed mesaj çerçevesi (sıkıştırılmamış).
    static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= 1_048_576 else {
            throw AppError.message("Klima isteği çok büyük.")
        }
        var data = Data([0])
        let length = UInt32(payload.count)
        data.append(UInt8((length >> 24) & 0xff))
        data.append(UInt8((length >> 16) & 0xff))
        data.append(UInt8((length >> 8) & 0xff))
        data.append(UInt8(length & 0xff))
        data.append(payload)
        return data
    }

    /// Tamamlanmış bir gRPC gövdesinden ilk mesajı çıkarır.
    static func firstFrame(_ data: Data) throws -> Data? {
        guard data.count >= 5 else { return nil }
        let start = data.startIndex
        guard data[start] == 0 else {
            throw AppError.message("Klima yanıtı sıkıştırılmış; desteklenmiyor.")
        }
        let length = (Int(data[start + 1]) << 24)
            | (Int(data[start + 2]) << 16)
            | (Int(data[start + 3]) << 8)
            | Int(data[start + 4])
        guard length >= 0, length <= 1_048_576 else {
            throw AppError.message("Klima yanıtı beklenen boyutta değil.")
        }
        guard data.count >= 5 + length else { return nil }
        return Data(data[(start + 5)..<(start + 5 + length)])
    }

    // MARK: - İstekler

    static func climateStatusRequest(vin: String) -> Data {
        stringField(1, vin)
    }

    /// SendClimateControlCommand gövdesi:
    ///   field 1: VIN
    ///   field 2: HVAC { field 1: aktif, field 2: sıcaklık { field 1: float } }
    static func climateCommandRequest(vin: String, active: Bool, temperature: Double?) throws -> Data {
        var hvac = Data()
        if active {
            hvac.append(varintField(1, 1))
        }
        if let temperature {
            guard temperature.isFinite, (16...30).contains(temperature) else {
                throw AppError.message("Hedef sıcaklık 16–30°C arasında olmalı.")
            }
            var temperatureMessage = Data()
            temperatureMessage.append(fixed32Field(1, Float(temperature)))
            hvac.append(bytesField(2, temperatureMessage))
        }
        var out = Data()
        out.append(stringField(1, vin))
        out.append(bytesField(2, hvac))
        return out
    }

    // MARK: - Yanıtlar

    /// GetClimateControlStatus yanıtı: dış field 1 içinde `active` (field 1) ve
    /// isteğe bağlı sıcaklık (field 2 → field 1 float).
    static func decodeClimateStatus(_ payload: Data) throws -> (active: Bool, temperature: Double?) {
        let outer = try fields(payload)
        guard case .bytes(let innerData)? = outer[1] else {
            throw AppError.message("Klima durumu beklenen biçimde değil.")
        }
        let inner = try fields(innerData)
        let active: Bool
        if case .varint(let value)? = inner[1] {
            active = value != 0
        } else {
            active = false
        }
        var temperature: Double?
        if case .bytes(let temperatureData)? = inner[2] {
            let temperatureFields = try fields(temperatureData)
            if case .fixed32(let bits)? = temperatureFields[1] {
                let value = Float(bitPattern: bits)
                if value.isFinite, (16...30).contains(Double(value)) {
                    temperature = Double(value)
                }
            }
        }
        return (active, temperature)
    }

    /// SendClimateControlCommand akışındaki her mesaj:
    ///   field 1 requestId, field 2 status, field 3 code.
    static func decodeCommandReply(_ payload: Data) throws -> (requestId: String, status: String, code: String) {
        let message = try fields(payload)
        return (
            stringValue(message[1]),
            stringValue(message[2]),
            stringValue(message[3])
        )
    }

    // MARK: - Protobuf

    static func fields(_ data: Data) throws -> [Int: Value] {
        var result: [Int: Value] = [:]
        var index = data.startIndex

        func readVarint() throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            for _ in 0..<10 {
                guard index < data.endIndex else {
                    throw AppError.message("Klima yanıtı eksik.")
                }
                let byte = data[index]
                index = data.index(after: index)
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            throw AppError.message("Klima yanıtı geçersiz.")
        }

        while index < data.endIndex {
            let key = try readVarint()
            let number = Int(key >> 3)
            let wire = Int(key & 7)
            guard number > 0 else {
                throw AppError.message("Klima yanıtı geçersiz.")
            }
            switch wire {
            case 0:
                result[number] = .varint(try readVarint())
            case 1:
                guard data.distance(from: index, to: data.endIndex) >= 8 else {
                    throw AppError.message("Klima yanıtı eksik.")
                }
                index = data.index(index, offsetBy: 8)
            case 2:
                let length = try readVarint()
                guard length <= UInt64(data.count) else {
                    throw AppError.message("Klima yanıtı geçersiz.")
                }
                let count = Int(length)
                guard data.distance(from: index, to: data.endIndex) >= count else {
                    throw AppError.message("Klima yanıtı eksik.")
                }
                let end = data.index(index, offsetBy: count)
                result[number] = .bytes(Data(data[index..<end]))
                index = end
            case 5:
                guard data.distance(from: index, to: data.endIndex) >= 4 else {
                    throw AppError.message("Klima yanıtı eksik.")
                }
                let end = data.index(index, offsetBy: 4)
                let bytes = Array(data[index..<end])
                let value = UInt32(bytes[0])
                    | (UInt32(bytes[1]) << 8)
                    | (UInt32(bytes[2]) << 16)
                    | (UInt32(bytes[3]) << 24)
                result[number] = .fixed32(value)
                index = end
            default:
                throw AppError.message("Klima yanıtı desteklenmeyen alan içeriyor.")
            }
        }
        return result
    }

    private static func stringValue(_ value: Value?) -> String {
        guard case .bytes(let data)? = value else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var current = value
        while current >= 0x80 {
            data.append(UInt8((current & 0x7f) | 0x80))
            current >>= 7
        }
        data.append(UInt8(current))
    }

    private static func stringField(_ field: Int, _ value: String) -> Data {
        bytesField(field, Data(value.utf8))
    }

    private static func bytesField(_ field: Int, _ value: Data) -> Data {
        var data = Data()
        appendVarint((UInt64(field) << 3) | 2, to: &data)
        appendVarint(UInt64(value.count), to: &data)
        data.append(value)
        return data
    }

    private static func varintField(_ field: Int, _ value: UInt64) -> Data {
        var data = Data()
        appendVarint(UInt64(field) << 3, to: &data)
        appendVarint(value, to: &data)
        return data
    }

    private static func fixed32Field(_ field: Int, _ value: Float) -> Data {
        var data = Data()
        appendVarint((UInt64(field) << 3) | 5, to: &data)
        let bits = value.bitPattern.littleEndian
        data.append(UInt8(bits & 0xff))
        data.append(UInt8((bits >> 8) & 0xff))
        data.append(UInt8((bits >> 16) & 0xff))
        data.append(UInt8((bits >> 24) & 0xff))
        return data
    }
}
