import Foundation

@MainActor
extension BleConnection {
    /// Telefon anahtarını hazırlar, sertifikayı sunucudan alır/üretir ve araca sunar.
    /// Bağlantı ve kanal keşfi tamamlanmış olmalıdır.
    func authenticate(vehicle: Vehicle, api: ToggAPI, overwriteOwner: Bool = false) async throws {
        print("[BLE] authenticate start vin=…\(vehicle.vin.suffix(4)) shared=\(vehicle.isShared) overwrite=\(overwriteOwner)")
        do {
            let pair = try PhoneKeyStore.keyPair(for: vehicle.vin)
            let record = try await api.ensureCertificate(
                vin: vehicle.vin,
                phonePublicKeyHex: pair.publicKey.hexString,
                overwriteOwner: overwriteOwner,
                isShared: vehicle.isShared
            )
            print("[BLE] certificate ready len=\(record.certificateBase64.count) carKeyPresent=\(!record.carPublicKey.isEmpty)")
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
