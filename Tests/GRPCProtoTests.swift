import XCTest
@testable import ToqdasCore

final class GRPCProtoTests: XCTestCase {
    private let vin = "ABC12345678901234"

    func testClimateCommandEncodesVINAndTemperature() throws {
        let payload = try GRPCProto.climateCommandRequest(vin: vin, active: true, temperature: 22.5)
        let outer = try GRPCProto.fields(payload)
        guard case .bytes(let vinData)? = outer[1],
              case .bytes(let hvacData)? = outer[2] else {
            return XCTFail("Komut alanları eksik")
        }
        XCTAssertEqual(String(data: vinData, encoding: .utf8), vin)

        let hvac = try GRPCProto.fields(hvacData)
        XCTAssertEqual(hvac[1], .varint(1))
        guard case .bytes(let temperatureData)? = hvac[2] else {
            return XCTFail("Sıcaklık alanı eksik")
        }
        let temperature = try GRPCProto.fields(temperatureData)
        guard case .fixed32(let bits)? = temperature[1] else {
            return XCTFail("Sıcaklık float alanı eksik")
        }
        XCTAssertEqual(Float(bitPattern: bits), 22.5, accuracy: 0.001)
    }

    func testClimateOffOmitsActiveAndTemperature() throws {
        let payload = try GRPCProto.climateCommandRequest(vin: vin, active: false, temperature: nil)
        let outer = try GRPCProto.fields(payload)
        guard case .bytes(let hvacData)? = outer[2] else {
            return XCTFail("HVAC alanı eksik")
        }
        XCTAssertTrue(try GRPCProto.fields(hvacData).isEmpty)
    }

    func testClimateCommandRejectsTemperatureOutsideRange() {
        XCTAssertThrowsError(try GRPCProto.climateCommandRequest(vin: vin, active: true, temperature: 15.9))
        XCTAssertThrowsError(try GRPCProto.climateCommandRequest(vin: vin, active: true, temperature: 30.1))
    }

    func testClimateStatusDecodesActiveAndTemperature() throws {
        var temperature = Data()
        temperature.append(try field(1, float: 22.5))
        var inner = Data()
        inner.append(try field(1, varint: 1))
        inner.append(try field(2, bytes: temperature))
        var outer = Data()
        outer.append(try field(1, bytes: inner))

        let status = try GRPCProto.decodeClimateStatus(outer)
        XCTAssertTrue(status.active)
        XCTAssertEqual(status.temperature ?? 0, 22.5, accuracy: 0.001)
    }

    func testClimateStatusWithoutTemperature() throws {
        var inner = Data()
        inner.append(try field(1, varint: 0))
        var outer = Data()
        outer.append(try field(1, bytes: inner))
        let status = try GRPCProto.decodeClimateStatus(outer)
        XCTAssertFalse(status.active)
        XCTAssertNil(status.temperature)
    }

    func testCommandReplyDecodesStreamFields() throws {
        var payload = Data()
        payload.append(try field(1, string: "request-1"))
        payload.append(try field(2, string: "COMPLETED"))
        payload.append(try field(3, string: "OK"))
        let reply = try GRPCProto.decodeCommandReply(payload)
        XCTAssertEqual(reply.requestId, "request-1")
        XCTAssertEqual(reply.status, "COMPLETED")
        XCTAssertEqual(reply.code, "OK")
    }

    func testFrameRoundTrip() throws {
        let payload = try GRPCProto.climateCommandRequest(vin: vin, active: true, temperature: 21)
        let frame = try GRPCProto.frame(payload)
        XCTAssertEqual(frame.count, payload.count + 5)
        XCTAssertEqual(try GRPCProto.firstFrame(frame), payload)
        XCTAssertEqual(try GRPCProto.firstFrame(frame + Data([1, 2, 3])), payload)
    }

    func testRejectsCompressedFrame() {
        XCTAssertThrowsError(try GRPCProto.firstFrame(Data([1, 0, 0, 0, 0])))
    }

    private func field(_ number: Int, varint value: UInt64) throws -> Data {
        var data = Data()
        data.append(varintData((UInt64(number) << 3) | 0))
        data.append(varintData(value))
        return data
    }

    private func field(_ number: Int, bytes value: Data) throws -> Data {
        var data = Data()
        data.append(varintData((UInt64(number) << 3) | 2))
        data.append(varintData(UInt64(value.count)))
        data.append(value)
        return data
    }

    private func field(_ number: Int, string value: String) throws -> Data {
        try field(number, bytes: Data(value.utf8))
    }

    private func field(_ number: Int, float value: Float) throws -> Data {
        var data = Data()
        data.append(varintData((UInt64(number) << 3) | 5))
        let bits = value.bitPattern.littleEndian
        data.append(UInt8(bits & 0xff))
        data.append(UInt8((bits >> 8) & 0xff))
        data.append(UInt8((bits >> 16) & 0xff))
        data.append(UInt8((bits >> 24) & 0xff))
        return data
    }

    private func varintData(_ value: UInt64) -> Data {
        var data = Data()
        var current = value
        while current >= 0x80 {
            data.append(UInt8((current & 0x7f) | 0x80))
            current >>= 7
        }
        data.append(UInt8(current))
        return data
    }
}
