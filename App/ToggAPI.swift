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
            let text = String(data: body, encoding: .utf8) ?? ""
            print("[HTTP] \(http.statusCode) \(request.url?.path ?? "?") body=\(text)")
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
            if let anchor, !anchor.isEmpty { query.append(.init(name: "anchor", value: anchor)) }
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

    func checkPhoneRelation(publicKey: String, language: String = "TR") async throws -> Data {
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
            "Platform": ["android"],
            "Language": [language],
            "PushNotificationToken": [""]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
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
        print("[CERT] create response: \(String(data: data, encoding: .utf8)?.prefix(3000) ?? "")")
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
    func ensureCertificate(vin: String, phonePublicKeyHex: String, overwriteOwner: Bool = false) async throws -> CertificateRecord {
        if let cached = CertificateCache.load(vin: vin, phonePublicKeyHex: phonePublicKeyHex) {
            print("[CERT] cached certificate used len=\(cached.certificateBase64.count)")
            return CertificateRecord(certificateBase64: cached.certificateBase64, carPublicKey: cached.carPublicKey)
        }
        print("[CERT] getCertificate başlıyor")
        do {
            let data = try await getCertificate(phonePublicKey: phonePublicKeyHex, vin: vin)
            print("[CERT] getCertificate response: \(String(data: data, encoding: .utf8)?.prefix(4000) ?? "")")
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
            print("[CERT] check response: \(String(data: check, encoding: .utf8)?.prefix(2000) ?? "")")
        }
        print("[CERT] claimCar overwrite=\(overwriteOwner)")
        let claim = try await claimCar(ownerPublicKey: phonePublicKeyHex, vin: vin, overwritePhoneRelation: overwriteOwner)
        let claimText = String(data: claim, encoding: .utf8) ?? ""
        print("[CERT] claim response: \(claimText.prefix(2000))")
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
        print("[CERT] body=\(body.hexString) key=\(keyPair.publicKey.hexString) sig=\(signature.count)")
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
        guard let certificate = findString(root, keys: certificateKeys), !certificate.isEmpty else {
            return nil
        }
        let carKey = findString(root, keys: vehicleKeyKeys)
            ?? findString(root, keys: ["publicKey"]).flatMap { $0 == excluding ? nil : $0 }
            ?? ""
        return CertificateRecord(certificateBase64: certificate, carPublicKey: carKey)
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
