import Foundation


enum CertificateServiceError: LocalizedError {
    case ownerTransferRequired

    var errorDescription: String? {
        switch self {
        case .ownerTransferRequired:
            return "Araç başka bir telefon anahtarına bağlı. Sahip anahtarını bu iPhone'a taşımak için onay gerekiyor."
        }
    }
}

private let SUPERAPP_URL = "https://superapp-api.channels.togg.cloud"

struct ClimateStatus: Equatable {
    let active: Bool
    let temperature: Double?
}

struct ClimateCommandResult: Equatable {
    let requestId: String
    let status: String
    let code: String
}

final class NoRedirects: NSObject, URLSessionTaskDelegate {


    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class ToggAPI {
    private let store = SessionStore()
    private let session: URLSession
    private var refreshTask: Task<SessionTokens, Error>?
    private var generation = 0
    private let tokenURL = URL(string: "https://toggid.togg.cloud/auth/realms/toggid/protocol/openid-connect/token")!
    private let smartAccessURL = URL(string: "https://tva-api.togg.cloud/smart-access/api/v1")!
    private let grpcURL = URL(string: "https://tva-api.togg.cloud:9443/tr.com.togg.tva.remotecontrol.gRpcRemoteControlService/")!
    private let language = "TR"
    private lazy var grpcSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 240
        config.timeoutIntervalForResource = 260
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 50
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    func hasSession() throws -> Bool { try store.load() != nil }

    func logout() throws {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        try store.clear()
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("Servis yanıtı geçersiz.") }
        print("[HTTP] \(http.statusCode) \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
        guard (200...299).contains(http.statusCode) else {
            var body = Data()
            do {
                for try await byte in bytes {
                    if body.count >= 2048 { break }
                    body.append(byte)
                }
            } catch {}
            // Error bodies can echo account/VIN data; never copy them into device logs.
            print("[HTTP] \(http.statusCode) \(request.url?.path ?? "?") yanıt gövdesi gizlendi")
            throw AppError.message(http.statusCode == 401 ? "Oturum kabul edilmedi; yeniden giriş yapın." : "Servis hatası: HTTP \(http.statusCode) (\(request.url?.path ?? "bilinmeyen adres"))")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw AppError.message("Servis yanıtı çok büyük.") }
            data.append(byte)
        }
        return data
    }

    private func exchange(_ fields: [String: String], previousRefresh: String? = nil) async throws -> SessionTokens {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = FormEncoding.data(fields)
        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String, !access.isEmpty, access.count <= 32768 else {
            throw AppError.message("Geçerli oturum bilgisi alınamadı.")
        }
        return SessionTokens(access: access, refresh: json["refresh_token"] as? String ?? previousRefresh,
                             expiresAt: Date().addingTimeInterval(max(1, (json["expires_in"] as? NSNumber)?.doubleValue ?? 300)))
    }

    func login(code: String, verifier: String) async throws {
        let current = generation
        let tokens = try await exchange(["client_id": "super-app", "grant_type": "authorization_code",
                                         "redirect_uri": OAuthAttempt.redirect, "code": code, "code_verifier": verifier])
        try Task.checkCancellation()
        guard current == generation else { throw CancellationError() }
        try store.save(tokens)
    }

    private func token() async throws -> String {
        guard let tokens = try store.load() else { throw AppError.message("Önce Togg ID ile giriş yapın.") }
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.access }
        if let refreshTask { return try await refreshTask.value.access }
        guard let refresh = tokens.refresh, !refresh.isEmpty else {
            throw AppError.message("Oturum süresi doldu; yeniden giriş yapın.")
        }
        let current = generation
        let task = Task { @MainActor in
            let updated = try await self.exchange(["client_id": "super-app", "grant_type": "refresh_token", "refresh_token": refresh], previousRefresh: refresh)
            try Task.checkCancellation()
            guard current == self.generation else { throw CancellationError() }
            try self.store.save(updated)
            return updated
        }
        refreshTask = task
        defer { if current == generation { refreshTask = nil } }
        return try await task.value.access
    }

    private func get(_ path: String, query: [URLQueryItem] = [], base: String = "https://tva-api.togg.cloud") async throws -> Data {
        var components = URLComponents(string: base)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TR", forHTTPHeaderField: "language")
        request.setValue("663", forHTTPHeaderField: "x-app-build-number")
        return try await send(request)
    }

    func vehicles() async throws -> [Vehicle] {
        try Vehicle.parse(await get("/vin-manage/api/v1/Vin/retrieveOwnerAndFriendVins"))
    }

    func details(for vehicle: Vehicle) async throws -> String {
        let data = try await get("/info/api/v2/VehicleInfo", query: [.init(name: "vin", value: vehicle.vin)])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["telemetry"] != nil else {
            throw AppError.message("Araç verisi beklenen biçimde değil.")
        }
        let formatted = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: formatted, as: UTF8.self)
    }

    // MARK: - İklimlendirme (gRPC uzaktan kontrol)

    /// Resmî Toqdaş uygulamasının kullandığı `GetClimateControlStatus` çağrısı.
    func climateStatus(vin: String) async throws -> ClimateStatus {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw AppError.message("Geçersiz VIN.")
        }
        let request = try await grpcRequest(
            method: "GetClimateControlStatus",
            payload: GRPCProto.climateStatusRequest(vin: vin),
            timeout: 35
        )
        let (bytes, response) = try await grpcSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("Klima servisi yanıtı geçersiz.")
        }
        try grpcCheck(http)
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= 1_048_576 else {
                throw AppError.message("Klima yanıtı çok büyük.")
            }
        }
        guard let frame = try GRPCProto.firstFrame(data) else {
            throw AppError.message("Klima durumu servisten gelmedi.")
        }
        let status = try GRPCProto.decodeClimateStatus(frame)
        return ClimateStatus(active: status.active, temperature: status.temperature)
    }

    /// Resmî Toqdaş uygulamasının kullandığı `SendClimateControlCommand` çağrısı.
    /// Sunucu ilerleme mesajlarını akış olarak döndürür; sonuç kodu gelene kadar okunur.
    func setClimate(vin: String, active: Bool, temperature: Double) async throws -> ClimateCommandResult {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw AppError.message("Geçersiz VIN.")
        }
        guard temperature.isFinite, (16...30).contains(temperature) else {
            throw AppError.message("Hedef sıcaklık 16–30°C arasında olmalı.")
        }
        let request = try await grpcRequest(
            method: "SendClimateControlCommand",
            payload: try GRPCProto.climateCommandRequest(
                vin: vin,
                active: active,
                temperature: active ? temperature : nil
            ),
            timeout: 240
        )
        let (bytes, response) = try await grpcSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("Klima servisi yanıtı geçersiz.")
        }
        try grpcCheck(http)

        let terminal: Set<String> = ["COMPLETED", "FAILED", "REJECTED", "ERROR", "CANCELLED"]
        var buffer = Data()
        var last: ClimateCommandResult?
        for try await byte in bytes {
            buffer.append(byte)
            while buffer.count >= 5 {
                let start = buffer.startIndex
                guard buffer[start] == 0 else {
                    throw AppError.message("Klima yanıtı sıkıştırılmış; desteklenmiyor.")
                }
                let length = (Int(buffer[start + 1]) << 24)
                    | (Int(buffer[start + 2]) << 16)
                    | (Int(buffer[start + 3]) << 8)
                    | Int(buffer[start + 4])
                guard length >= 0, length <= 1_048_576 else {
                    throw AppError.message("Klima yanıtı beklenen boyutta değil.")
                }
                guard buffer.count >= 5 + length else { break }
                let frame = Data(buffer[(start + 5)..<(start + 5 + length)])
                let end = start + 5 + length
                if end < buffer.endIndex {
                    buffer = Data(buffer[end...])
                } else {
                    buffer.removeAll(keepingCapacity: true)
                }
                let reply = try GRPCProto.decodeCommandReply(frame)
                last = ClimateCommandResult(
                    requestId: reply.requestId,
                    status: reply.status,
                    code: reply.code
                )
                if terminal.contains(reply.status), let last {
                    return last
                }
            }
            guard buffer.count <= 1_048_576 else {
                throw AppError.message("Klima yanıtı çok büyük.")
            }
        }
        if let last {
            throw AppError.message("Klima komutu tamamlanmadı (son durum: \(last.status)).")
        }
        throw AppError.message("Klima komutu sonucu alınamadı.")
    }

    private func grpcRequest(method: String, payload: Data, timeout: TimeInterval) async throws -> URLRequest {
        guard let url = URL(string: grpcURL.absoluteString + method) else {
            throw AppError.message("Klima servis adresi geçersiz.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
        request.setValue("application/grpc", forHTTPHeaderField: "Accept")
        request.setValue("trailers", forHTTPHeaderField: "TE")
        request.setValue("identity", forHTTPHeaderField: "grpc-accept-encoding")
        request.setValue(String(format: "%.0fm", timeout * 1000), forHTTPHeaderField: "grpc-timeout")
        request.setValue("dart-grpc/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.httpBody = try GRPCProto.frame(payload)
        return request
    }

    private func grpcCheck(_ response: HTTPURLResponse) throws {
        if let status = response.value(forHTTPHeaderField: "grpc-status"), status != "0" {
            let detail = response.value(forHTTPHeaderField: "grpc-message") ?? ""
            if status == "14" || detail.contains("upstream connect error") {
                throw AppError.message("Araç servisine şu anda ulaşılamıyor (gRPC 14). Birkaç dakika sonra tekrar deneyin.")
            }
            throw AppError.message("Klima servisi gRPC \(status)\(detail.isEmpty ? "" : ": \(detail)")")
        }
        guard (200...299).contains(response.statusCode) else {
            throw AppError.message("Klima servisi HTTP \(response.statusCode) döndürdü.")
        }
    }

    /// Drive Experience: özet, yolculuk ve şarj geçmişi (Garajm ApiClient ile aynı uçlar).
    func driveExperience(vin: String, kind: String, period: String = "Monthly",
                         offset: Int = 0, anchor: String? = nil, id: String? = nil) async throws -> Data {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw AppError.message("Geçersiz VIN.")
        }
        guard ["summary", "journeys", "charges", "journeyDetail", "chargeDetail"].contains(kind),
              ["Weekly", "Monthly", "Annual"].contains(period) else {
            throw AppError.message("Geçersiz analiz seçimi.")
        }
        var path = "/info/api/v1/DriveExperience/\(vin)"
        var query: [URLQueryItem] = []
        switch kind {
        case "summary":
            path += "/insightsDashboard"
        case "journeys", "charges":
            path += kind == "charges" ? "/chargingOverview\(period)" : "/journeysOverview\(period)"
            query = [.init(name: "limit", value: "20"), .init(name: "offset", value: String(max(0, offset)))]
            if let anchor, !anchor.isEmpty {
                // Sunucu dönem türüne göre ayrı parametre bekliyor; "anchor" yok sayılıyor.
                let key: String
                switch period {
                case "Annual": key = "anchor_year"
                case "Monthly": key = "anchor_month"
                default: key = "anchor_date"
                }
                query.append(.init(name: key, value: anchor))
            }
        case "journeyDetail":
            path += "/journeys/\(id ?? "")"
        case "chargeDetail":
            path += "/charging/\(id ?? "")"
        default:
            throw AppError.message("Geçersiz analiz seçimi.")
        }
        return try await get(path, query: query)
    }

    func serviceCards(for vin: String) async throws -> Data {
        try await get("/vin-manage/api/v1/Vin/ServiceCards/\(vin)")
    }

    /// Superapp hesap uçları (Garajm BridgeContract ile aynı yollar).
    func notifications() async throws -> Data {
        try await get("/integration/api/v1/Notifications/all", base: SUPERAPP_URL)
    }

    func supportTickets() async throws -> Data {
        try await get("/integration/api/v1/Tickets/Tur", base: SUPERAPP_URL)
    }

    func subscriptions() async throws -> Data {
        try await get("/integration/api/v1/Package/Tur/subscriptions", base: SUPERAPP_URL)
    }

    func ticketNotes(for ticketId: String) async throws -> Data {
        try await get("/integration/api/v1/Tickets/Tur/\(ticketId)/notes", base: SUPERAPP_URL)
    }

    func checkPhoneRelation(publicKey: String, language: String = "TR", platform: String = "ios") async throws -> Data {
        var components = URLComponents(url: smartAccessURL, resolvingAgainstBaseURL: false)!
        components.path = smartAccessURL.path + "/UserPhoneRelation/CheckUserPhoneRelation"
        components.queryItems = [URLQueryItem(name: "publicKey", value: publicKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(language, forHTTPHeaderField: "language")
        request.setValue("663", forHTTPHeaderField: "x-app-build-number")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "Platform": [platform],
            "Language": [language],
            "PushNotificationToken": [""]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// Togg/Trumore tarafından üretilen paylaşım davetini imzalı olarak kabul eder.
    /// Bu akış araç sahipliği talep etmez ve `ClaimCarToUser` çağırmaz.
    func acceptSharedKeyInvitation(vin: String, invitationURL: String) async throws {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw AppError.message("Geçerli 17 karakterli VIN girin.")
        }
        let invitation = try KeySharingInvitation.parse(invitationURL)
        guard !SharedKeyRequestStore.wasRequested(vin: vin, fingerprint: invitation.replayFingerprint) else {
            throw AppError.message("Bu davet için kabul isteği zaten gönderildi. Sahip onayından sonra sertifikayı okuyun; istek otomatik tekrarlanmaz.")
        }

        let pair = try PhoneKeyStore.keyPair(for: vin)
        let account = try accountUUID()
        let message = try invitation.signatureMessage(accountUUID: account, phonePublicKey: pair.publicKey)
        let signature = try PhoneKeyStore.sign(message, with: pair.key)
        let publicKey = pair.publicKey.hexString

        let relation = try await checkPhoneRelation(publicKey: publicKey, platform: "ios")
        if let result = Self.resultEnum(in: relation),
           !["Success", "Updated", "OwnerChange", "RelationAlreadyExists"].contains(result) {
            throw AppError.message("Telefon anahtarı hesabınıza kaydedilemedi (\(result)).")
        }

        // İstek gönderildikten sonra yanıt kaybolsa bile aynı daveti tekrarlamayız.
        SharedKeyRequestStore.markRequested(vin: vin, fingerprint: invitation.replayFingerprint)
        let response = try await replyToShareSession(
            sessionID: invitation.sessionID,
            signatureBase64: signature.base64EncodedString(),
            phonePublicKey: publicKey
        )
        if let result = Self.resultEnum(in: response),
           ["Failure", "Rejected", "Error"].contains(result) {
            throw AppError.message("Paylaşım daveti sunucu tarafından reddedildi (\(result)).")
        }
    }

    /// Araç sahibi Trumore'da onay verdikten sonra yalnızca bu VIN ve telefon
    /// açık anahtarına bağlı paylaşılan sertifikayı bulur ve Keychain'e yazar.
    func readSharedCertificate(vin: String) async throws -> CertificateRecord {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw AppError.message("Geçerli 17 karakterli VIN girin.")
        }
        let pair = try PhoneKeyStore.keyPair(for: vin)
        let phonePublicKey = pair.publicKey.hexString
        let cached = CertificateCache.loadCertificate(vin: vin, phonePublicKeyHex: phonePublicKey)
        // A valid VIN/device-bound cache is safe to reuse even when the vehicle
        // list labels the VIN as shared. It must not fall through to owner claim.
        if let cached,
           SharedKeyRequestStore.hasCertificate(vin: vin) || !cached.carPublicKey.isEmpty {
            return CertificateRecord(certificateBase64: cached.certificateBase64, carPublicKey: cached.carPublicKey)
        }
        guard SharedKeyRequestStore.canCheckCertificate(vin: vin) else {
            throw AppError.message("Paylaşılan sertifika için son sorgu yapıldı. Araç sahibinin Trumore onayından sonra en az bir dakika bekleyip yeniden deneyin.")
        }
        SharedKeyRequestStore.markCertificateCheck(vin: vin)

        let data = try await getAllCertificates(phonePublicKey: phonePublicKey)
        guard let record = try CertificateRecord.parseShared(
            data, vin: vin, phonePublicKey: pair.publicKey
        ) else {
            if let cached {
                return CertificateRecord(certificateBase64: cached.certificateBase64, carPublicKey: cached.carPublicKey)
            }
            throw AppError.message("Paylaşılan sertifika bulunamadı. Araç sahibinin Trumore onayını kontrol edin.")
        }
        guard let certificateData = Data(base64Encoded: record.certificateBase64),
              let expiry = BLEProtocol.certificateEndDate(certificateData),
              CertificateLifecycle(expiresAt: expiry).state == .valid else {
            throw AppError.message("Paylaşılan sertifika süresi geçmiş veya geçersiz.")
        }

        let existingKey = cached?.carPublicKey ?? ""
        let returnedKey = Self.normalizedVehiclePublicKey(record.carPublicKey)
        let cachedKey = Self.normalizedVehiclePublicKey(existingKey)
        if let returnedKey, let cachedKey, returnedKey != cachedKey {
            throw AppError.message("Paylaşılan sertifikadaki araç anahtarı daha önce güvenilen anahtarla eşleşmiyor; önbellek değiştirilmedi.")
        }
        let trustedKey = returnedKey ?? cachedKey
        CertificateCache.save(
            certificateBase64: record.certificateBase64,
            carPublicKey: trustedKey?.hexString ?? "",
            vin: vin,
            phonePublicKeyHex: phonePublicKey
        )
        guard let saved = CertificateCache.loadCertificate(vin: vin, phonePublicKeyHex: phonePublicKey),
              saved.certificateBase64 == record.certificateBase64 else {
            throw AppError.message("Paylaşılan sertifika Keychain'e güvenle kaydedilemedi.")
        }
        SharedKeyRequestStore.markCertificateAvailable(vin: vin)
        return CertificateRecord(certificateBase64: saved.certificateBase64, carPublicKey: saved.carPublicKey)
    }

    private func getAllCertificates(phonePublicKey: String) async throws -> Data {
        var components = URLComponents(url: smartAccessURL, resolvingAgainstBaseURL: false)!
        components.path = smartAccessURL.path + "/Certificates/GetAllCertificates"
        components.queryItems = [URLQueryItem(name: "phonePublicKey", value: phonePublicKey)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language, forHTTPHeaderField: "language")
        request.setValue("663", forHTTPHeaderField: "x-app-build-number")
        return try await send(request)
    }

    private func replyToShareSession(sessionID: String, signatureBase64: String,
                                     phonePublicKey: String) async throws -> Data {
        var components = URLComponents(url: smartAccessURL, resolvingAgainstBaseURL: false)!
        components.path = smartAccessURL.path + "/ShareProcess/ReplyToSession"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(language, forHTTPHeaderField: "language")
        request.setValue("663", forHTTPHeaderField: "x-app-build-number")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "sessionId": sessionID,
            "signatureBase64": signatureBase64,
            "phonePublicKey": phonePublicKey,
            "sharedName": "Toqdas",
            "friendName": "Toqdas"
        ])
        let data = try await send(request)
        if let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? Bool,
           !value {
            throw AppError.message("Paylaşım daveti kabul edilmedi.")
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["success"] as? Bool == false {
            throw AppError.message("Paylaşım daveti kabul edilmedi.")
        }
        return data
    }

    private static func normalizedVehiclePublicKey(_ text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutPrefix = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        let raw = Data(hexBytes: withoutPrefix) ?? Data(base64Encoded: trimmed)
        guard let normalized = raw.flatMap(PhoneKeyStore.normalizedPublicKey),
              (try? BLEProtocol.publicKey(normalized)) != nil else { return nil }
        return normalized
    }

    func getCertificate(phonePublicKey: String, vin: String, isOwner: Bool = true) async throws -> Data {
        var components = URLComponents(url: smartAccessURL, resolvingAgainstBaseURL: false)!
        components.path = smartAccessURL.path + "/Certificates/GetCertificate"
        components.queryItems = [
            URLQueryItem(name: "phonePublicKey", value: phonePublicKey),
            URLQueryItem(name: "vin", value: vin),
            URLQueryItem(name: "isOwner", value: isOwner ? "true" : "false")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language, forHTTPHeaderField: "language")
        request.setValue("663", forHTTPHeaderField: "x-app-build-number")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func createCertificate(phonePublicKey: String, vin: String,
                           shortCertificateBase64: String? = nil,
                           isOwnerCertificate: Bool = true) async throws -> Data {
        var components = URLComponents(url: smartAccessURL, resolvingAgainstBaseURL: false)!
        components.path = smartAccessURL.path + "/Certificates/CreateCertificate"
        components.queryItems = [URLQueryItem(name: "phonePublicKey", value: phonePublicKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(language, forHTTPHeaderField: "language")
        request.setValue("663", forHTTPHeaderField: "x-app-build-number")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "vin": vin,
            "isOwnerCertificate": isOwnerCertificate
        ]
        if let shortCertificateBase64 {
            body["shortCertificateBase64"] = shortCertificateBase64
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        print("[CERT] create response result=\(Self.resultEnum(in: data) ?? "bilinmiyor")")
        return data
    }

    /// JWT içindeki hesap kimliği (sahip sertifikası gövdesi için).
    func accountUUID() throws -> String {
        guard let sub = try jwtPayload()["sub"] as? String, !sub.isEmpty else {
            throw AppError.message("Hesap kimliği okunamadı.")
        }
        return sub
    }

    /// JWT içindeki e-posta / kullanıcı adı; arayüz başlığı için.
    func accountEmail() -> String? {
        guard let payload = try? jwtPayload() else { return nil }
        return (payload["email"] as? String) ?? (payload["preferred_username"] as? String)
    }

    private static func resultEnum(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["resultEnum"] as? String
    }

    private func jwtPayload() throws -> [String: Any] {
        guard let tokens = try store.load() else { throw AppError.message("Önce Togg ID ile giriş yapın.") }
        let parts = tokens.access.split(separator: ".")
        guard parts.count >= 2 else { throw AppError.message("Oturum kimliği okunamadı.") }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.message("Oturum kimliği okunamadı.")
        }
        return json
    }

    /// Sertifikayı sunucudan alır; yoksa sahip sertifikası üretir.
    /// Dönen sertifika, telefonun açık anahtarına bağlı doğrulanmış 247 byte'lık kayıttır.
    func ensureCertificate(vin: String, phonePublicKeyHex: String, overwriteOwner: Bool = false,
                           isShared: Bool = false) async throws -> CertificateRecord {
        // Araç listesi authoritative'dir; SharedKeyRequestStore yalnızca API verisi
        // henüz yüklenmediğinde fallback olarak kullanılır.
        let sharedFlow = isShared
        if sharedFlow {
            guard !overwriteOwner else {
                throw AppError.message("Paylaşılan anahtar sahiplik devrine dönüştürülemez.")
            }
            return try await readSharedCertificate(vin: vin)
        }
        // "Yeniden eşleştir" (overwriteOwner) önbelleği atlamalı; aksi halde buton
        // hiçbir şey yapmaz ve araç anahtarı sunucudan hiç istenmez.
        if !overwriteOwner,
           let cached = CertificateCache.loadCertificate(vin: vin, phonePublicKeyHex: phonePublicKeyHex) {
            let lifecycle = CertificateLifecycle(certificateBase64: cached.certificateBase64)
            print("[CERT] cached certificate used len=\(cached.certificateBase64.count) carKey=\(cached.carPublicKey.isEmpty ? "yok" : "var") status=\(lifecycle?.state.rawValue ?? "bilinmiyor")")
            if !cached.carPublicKey.isEmpty {
                guard lifecycle?.needsRefresh == true else {
                    return CertificateRecord(certificateBase64: cached.certificateBase64, carPublicKey: cached.carPublicKey)
                }
                // Son 24 saat: yeni sertifika almayı dene. Ağ yoksa hâlâ
                // geçerli olan önbellek sertifikası kullanılmaya devam eder.
                print("[CERT] cached certificate needs refresh; requesting new certificate")
                if let data = try? await getCertificate(phonePublicKey: phonePublicKeyHex, vin: vin),
                   let fresh = try? CertificateRecord.parse(data, vin: vin, excluding: phonePublicKeyHex),
                   !fresh.certificateBase64.isEmpty {
                    CertificateCache.save(
                        certificateBase64: fresh.certificateBase64,
                        carPublicKey: fresh.carPublicKey,
                        vin: vin,
                        phonePublicKeyHex: phonePublicKeyHex
                    )
                    let carKey = fresh.carPublicKey.isEmpty ? cached.carPublicKey : fresh.carPublicKey
                    print("[CERT] certificate refreshed len=\(fresh.certificateBase64.count) carKeyPresent=\(!carKey.isEmpty)")
                    return CertificateRecord(certificateBase64: fresh.certificateBase64, carPublicKey: carKey)
                }
                print("[CERT] refresh failed; using still-valid cached certificate")
                return CertificateRecord(certificateBase64: cached.certificateBase64, carPublicKey: cached.carPublicKey)
            }
            // Sertifika var ama araç açık anahtarı yok: el sıkışma araç anahtarı
            // adımında kopar. Sunucudan yalnızca anahtarı tazelemeyi dene.
            print("[CERT] cache has no vehicle key; refreshing from server")
            if let data = try? await getCertificate(phonePublicKey: phonePublicKeyHex, vin: vin),
               let fresh = try? CertificateRecord.parse(data, vin: vin, excluding: phonePublicKeyHex),
               !fresh.carPublicKey.isEmpty {
                CertificateCache.updateCarKey(vin: vin, phonePublicKeyHex: phonePublicKeyHex, carKey: fresh.carPublicKey)
                print("[CERT] vehicle key refreshed from server")
                return CertificateRecord(certificateBase64: cached.certificateBase64, carPublicKey: fresh.carPublicKey)
            }
            print("[CERT] server returned no vehicle key; using cached certificate only")
            return CertificateRecord(certificateBase64: cached.certificateBase64, carPublicKey: "")
        }
        print("[CERT] getCertificate başlıyor")
        do {
            let data = try await getCertificate(phonePublicKey: phonePublicKeyHex, vin: vin)
            if let record = try CertificateRecord.parse(data, vin: vin, excluding: phonePublicKeyHex), !record.certificateBase64.isEmpty {
                print("[CERT] mevcut sertifika alındı len=\(record.certificateBase64.count)")
                CertificateCache.save(certificateBase64: record.certificateBase64, carPublicKey: record.carPublicKey, vin: vin, phonePublicKeyHex: phonePublicKeyHex)
                return record
            }
            print("[CERT] yanıtta sertifika yok")
        } catch {
            print("[CERT] getCertificate hatası: \(error.localizedDescription)")
        }
        let publicKey = try BLEProtocol.publicKey(Data(hexBytes: phonePublicKeyHex) ?? Data())
        let keyPair = try PhoneKeyStore.keyPair(for: vin)
        // Android akışıyla aynı: telefon anahtarını kaydet, aracı hesaba bağla, sertifika üret.
        print("[CERT] checkPhoneRelation")
        if let check = try? await checkPhoneRelation(publicKey: phonePublicKeyHex) {
            print("[CERT] phone relation result=\(Self.resultEnum(in: check) ?? "bilinmiyor")")
        }
        print("[CERT] claimCar overwrite=\(overwriteOwner)")
        let claim = try await claimCar(ownerPublicKey: phonePublicKeyHex, vin: vin, overwritePhoneRelation: overwriteOwner)
        print("[CERT] claim result=\(Self.resultEnum(in: claim) ?? "bilinmiyor")")
        let claimResult = Self.resultEnum(in: claim)
        // RelationAlreadyExists, bu telefon anahtarı için ilişkinin zaten kurulu
        // olduğu anlamına gelir; sertifika üretimine devam edilebilir.
        let transferResults: Set<String> = ["OverwriteDetection", "OwnerChange", "NotOwner"]
        if !overwriteOwner, let claimResult, claimResult == "OverwriteDetection" {
            throw CertificateServiceError.ownerTransferRequired
        }
        if !overwriteOwner, let claimResult, transferResults.contains(claimResult) {
            throw CertificateServiceError.ownerTransferRequired
        }
        if overwriteOwner, let claimResult, transferResults.contains(claimResult) {
            throw AppError.message("Araç sahiplik ilişkisi taşınamadı (\(claimResult)).")
        }
        let start = Date()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = utc.date(byAdding: .day, value: 365, to: start) ?? start
        let body = try BLEProtocol.ownerBody(
            vin: vin,
            accountUUID: try accountUUID(),
            phonePublicKey: publicKey.x963Representation,
            start: start,
            end: end
        )
        print("[CERT] createCertificate")
        // Resmî akış: 119 byte gövde + 64 byte ECDSA imzası = 183 byte.
        let signature = try PhoneKeyStore.sign(body, with: keyPair.key)
        print("[CERT] signed owner certificate bodyBytes=\(body.count) signatureBytes=\(signature.count)")
        do {
            try BLEProtocol.verify(signature: signature, message: body, trustedKey: try BLEProtocol.publicKey(keyPair.publicKey))
            print("[CERT] local signature verify OK")
        } catch {
            print("[CERT] local signature verify FAILED: \(error)")
        }
        let shortCertificate = body + signature
        let data = try await createCertificate(
            phonePublicKey: phonePublicKeyHex,
            vin: vin,
            shortCertificateBase64: shortCertificate.base64EncodedString()
        )
        if let record = try CertificateRecord.parse(data, vin: vin, excluding: phonePublicKeyHex), !record.certificateBase64.isEmpty {
            CertificateCache.save(certificateBase64: record.certificateBase64, carPublicKey: record.carPublicKey, vin: vin, phonePublicKeyHex: phonePublicKeyHex)
            return record
        }
        // Sunucu sertifikayı hemen döndürmezse timeToWaitBeforeFetch kadar
        // bekleyip GetCertificate ile birkaç kez sorgular.
        print("[CERT] create response has no certificate; polling GetCertificate")
        for attempt in 0..<10 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                let fetched = try await getCertificate(phonePublicKey: phonePublicKeyHex, vin: vin)
                if let record = try CertificateRecord.parse(fetched, vin: vin, excluding: phonePublicKeyHex), !record.certificateBase64.isEmpty {
                    print("[CERT] certificate fetched after create attempt \(attempt + 1) len=\(record.certificateBase64.count)")
                    CertificateCache.save(certificateBase64: record.certificateBase64, carPublicKey: record.carPublicKey, vin: vin, phonePublicKeyHex: phonePublicKeyHex)
                    return record
                }
            } catch {
                print("[CERT] poll error: \(error.localizedDescription)")
            }
        }
        throw AppError.message("Sertifika servisi sertifika döndürmedi.")
    }

    func claimCar(ownerPublicKey: String, vin: String, overwritePhoneRelation: Bool = false) async throws -> Data {
        var components = URLComponents(url: smartAccessURL, resolvingAgainstBaseURL: false)!
        components.path = smartAccessURL.path + "/VehicleOwnerRelation/ClaimCarToUser"
        components.queryItems = [
            URLQueryItem(name: "ownerPublicKey", value: ownerPublicKey),
            URLQueryItem(name: "vin", value: vin),
            URLQueryItem(name: "overwritePhoneRelation", value: overwritePhoneRelation ? "true" : "false")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(language, forHTTPHeaderField: "language")
        request.setValue("663", forHTTPHeaderField: "x-app-build-number")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        return try await send(request)
    }
}

/// Smart-access sertifika yanıtından çıkarılan kayıt.
struct CertificateRecord {
    let certificateBase64: String
    let carPublicKey: String

    private static let certificateKeys = ["certificateBase64", "shortCertificateBase64", "certificate", "cert"]
    private static let vehicleKeyKeys = ["carPublicKey", "samPublicKey", "vehiclePublicKey", "smartAccessCarPubKey"]

    static func parse(_ data: Data, vin: String, excluding: String? = nil) throws -> CertificateRecord? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        let phoneKey = excluding.flatMap { Data(hexBytes: $0) }
            .flatMap(PhoneKeyStore.normalizedPublicKey)
        var candidates: [(certificate: String, carKey: String, vin: String?)] = []
        collectSharedCandidates(root, inheritedVIN: nil, excluding: excluding, depth: 0, into: &candidates)
        for candidate in candidates {
            if let candidateVIN = candidate.vin, candidateVIN != vin { continue }
            guard let packet = Data(base64Encoded: candidate.certificate) else { continue }
            let normalized: Data
            if let phoneKey {
                guard let bound = try? BLEProtocol.boundCertificate(packet, vin: vin, devicePublicKey: phoneKey) else { continue }
                normalized = bound
            } else {
                guard packet.count == 247,
                      let packetVIN = String(data: packet[17..<34], encoding: .utf8), packetVIN == vin else { continue }
                normalized = packet
            }
            guard let expiry = BLEProtocol.certificateEndDate(normalized), expiry > Date() else { continue }
            let record = CertificateRecord(
                certificateBase64: normalized.base64EncodedString(),
                carPublicKey: candidate.carKey
            )
            if record.carPublicKey.isEmpty {
                debugLogResponseShape(root, vin: vin)
            }
            return record
        }
        debugLogResponseShape(root, vin: vin)
        return nil
    }

    /// Sertifika yanıtında araç anahtarı yoksa alan adlarını teşhis eder.
    /// Yalnızca anahtar adları ve değer uzunlukları yazılır; hassas değerler
    /// (sertifika, telefon anahtarı, araç anahtarı) loglanmaz.
    private static func debugLogResponseShape(_ root: Any, vin: String) {
        #if DEBUG
        let suffix = String(vin.suffix(4))
        if let object = root as? [String: Any] {
            print("[CERT][DEBUG] vin=…\(suffix) rootKeys=\(object.keys.sorted())")
        } else if let array = root as? [Any] {
            print("[CERT][DEBUG] vin=…\(suffix) rootArrayCount=\(array.count)")
        } else {
            print("[CERT][DEBUG] vin=…\(suffix) rootType=\(type(of: root))")
        }

        var certObjectKeys: [String]?
        var longStringPaths: [String] = []
        var visited = 0

        func walk(_ node: Any, path: String, depth: Int) {
            guard depth <= 8, visited < 400 else { return }
            visited += 1
            if let object = node as? [String: Any] {
                if certObjectKeys == nil,
                   certificateKeys.contains(where: { object[$0] is String }) {
                    certObjectKeys = object.keys.sorted()
                }
                for key in object.keys.sorted() {
                    let childPath = path.isEmpty ? key : "\(path).\(key)"
                    walk(object[key] as Any, path: childPath, depth: depth + 1)
                }
            } else if let array = node as? [Any] {
                for (index, value) in array.enumerated() where index < 50 {
                    walk(value, path: "\(path)[\(index)]", depth: depth + 1)
                }
            } else if let string = node as? String {
                let length = string.count
                if (60...400).contains(length), longStringPaths.count < 30 {
                    longStringPaths.append("\(path)(len=\(length))")
                }
            }
        }

        walk(root, path: "", depth: 0)
        if let certObjectKeys {
            print("[CERT][DEBUG] certObjectKeys=\(certObjectKeys)")
        } else {
            print("[CERT][DEBUG] certObjectKeys=bulunamadı")
        }
        print("[CERT][DEBUG] longStringPaths=\(longStringPaths)")
        #endif
    }

    /// GetAllCertificates yanıtında önce VIN ve telefon anahtarına bağlanan
    /// sertifika bulunur; yanıt dizisindeki başka araca ait kayıt seçilmez.
    static func parseShared(_ data: Data, vin: String, phonePublicKey: Data) throws -> CertificateRecord? {
        try parse(data, vin: vin, excluding: phonePublicKey.hexString)
    }

    private static func collectSharedCandidates(
        _ node: Any,
        inheritedVIN: String?,
        excluding: String?,
        depth: Int,
        into result: inout [(certificate: String, carKey: String, vin: String?)]
    ) {
        guard depth <= 12, result.count < 500 else { return }
        if let object = node as? [String: Any] {
            let localVIN = (object["vin"] as? String)
                ?? (object["vinNumber"] as? String)
                ?? (object["VIN"] as? String)
                ?? inheritedVIN
            let carKey = vehicleKeyKeys.compactMap { object[$0] as? String }.first
                ?? (object["publicKey"] as? String).flatMap { $0 == excluding ? nil : $0 }
                ?? ""
            for key in certificateKeys {
                if let certificate = object[key] as? String, !certificate.isEmpty {
                    result.append((certificate, carKey, localVIN))
                }
            }
            for value in object.values {
                collectSharedCandidates(value, inheritedVIN: localVIN, excluding: excluding, depth: depth + 1, into: &result)
            }
        } else if let array = node as? [Any] {
            for value in array.prefix(500) {
                collectSharedCandidates(value, inheritedVIN: inheritedVIN, excluding: excluding, depth: depth + 1, into: &result)
            }
        }
    }

    private static func findString(_ node: Any, keys: [String], depth: Int = 0) -> String? {

        guard depth <= 8 else { return nil }
        if let object = node as? [String: Any] {
            for key in keys {
                if let value = object[key] as? String, !value.isEmpty { return value }
            }
            for value in object.values {
                if let found = findString(value, keys: keys, depth: depth + 1) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findString(value, keys: keys, depth: depth + 1) { return found }
            }
        }
        return nil
    }
}
