import Foundation

@MainActor
extension BleConnection {
    /// Telefon anahtarını hazırlar, sertifikayı sunucudan alır/üretir ve araca sunar.
    /// Bağlantı ve kanal keşfi tamamlanmış olmalıdır.
    func authenticate(vehicle: Vehicle, api: ToggAPI, overwriteOwner: Bool = false) async throws {
        print("[BLE] authenticate start vin=\(vehicle.vin) overwrite=\(overwriteOwner)")
        do {
            let pair = try PhoneKeyStore.keyPair(for: vehicle.vin)
            let record = try await api.ensureCertificate(
                vin: vehicle.vin,
                phonePublicKeyHex: pair.publicKey.hexString,
                overwriteOwner: overwriteOwner
            )
            print("[BLE] certificate ready len=\(record.certificateBase64.count) carKey=\(record.carPublicKey.prefix(12))")
            try beginAuthentication(
                vin: vehicle.vin,
                certificateBase64: record.certificateBase64,
                carKey: record.carPublicKey
            )
            print("[BLE] certificate frames queued")
        } catch {
            print("[BLE] authenticate failed: \(error)")
            throw error
        }
    }
}
