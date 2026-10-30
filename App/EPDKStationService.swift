import Foundation
import Network

struct EPDKCatalogLoad: Equatable {
    let catalog: EPDKCatalog
    let usedCache: Bool
    let warning: String?
    let nextFetchAt: Date?
}

actor EPDKStationService {
    static let shared = EPDKStationService()
    private static let refreshInterval: TimeInterval = 60 * 60
    private static let fetchedAtKey = "toqdas.epdk.fetchedAt"
    private static let nextFetchAtKey = "toqdas.epdk.nextFetchAt"

    private var cachedCatalog: EPDKCatalog?
    private let cacheURL: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EPDK", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("public-catalog-v1.json")
    }()

    func load(forceRefresh: Bool = false) async throws -> EPDKCatalogLoad {
        let catalog = loadCacheIfNeeded()
        let now = Date()
        let nextFetchAt = UserDefaults.standard.object(forKey: Self.nextFetchAtKey) as? Date
        let cacheIsFresh = catalog.map { now.timeIntervalSince($0.fetchedAt) < Self.refreshInterval } ?? false

        if !forceRefresh, let catalog, cacheIsFresh {
            return EPDKCatalogLoad(catalog: catalog, usedCache: true, warning: nil, nextFetchAt: nextFetchAt)
        }
        if let nextFetchAt, nextFetchAt > now {
            if let catalog {
                return EPDKCatalogLoad(
                    catalog: catalog,
                    usedCache: true,
                    warning: "EPDK sorgu aralığı dolmadı; kayıtlı katalog gösteriliyor.",
                    nextFetchAt: nextFetchAt
                )
            }
            throw EPDKStationError.rateLimited(nextFetchAt)
        }

        do {
            let response = try await EPDKHTTPGetBodyTransport().fetchCatalog()
            defer { try? FileManager.default.removeItem(at: response.bodyURL) }
            if response.statusCode == 429 {
                let retryAt = Self.retryDate(from: response.headers, now: Date())
                UserDefaults.standard.set(retryAt, forKey: Self.nextFetchAtKey)
                if let catalog {
                    return EPDKCatalogLoad(
                        catalog: catalog,
                        usedCache: true,
                        warning: "EPDK saatlik sorgu sınırına ulaşıldı; son katalog kullanılıyor.",
                        nextFetchAt: retryAt
                    )
                }
                throw EPDKStationError.rateLimited(retryAt)
            }
            guard response.statusCode == 200 else {
                throw EPDKStationError.http(response.statusCode)
            }
            guard response.headers["content-encoding"] == nil
                    || response.headers["content-encoding"]?.lowercased() == "identity" else {
                throw EPDKStationError.unsupportedEncoding
            }

            let fileData = try Data(contentsOf: response.bodyURL, options: .mappedIfSafe)
            guard fileData.count <= EPDKHTTPGetBodyTransport.maximumBodyBytes else {
                throw EPDKStationError.responseTooLarge
            }
            let parsed = try EPDKCatalogParser.parse(fileData)
            try save(parsed)
            cachedCatalog = parsed
            let next = Date().addingTimeInterval(Self.refreshInterval)
            UserDefaults.standard.set(parsed.fetchedAt, forKey: Self.fetchedAtKey)
            UserDefaults.standard.set(next, forKey: Self.nextFetchAtKey)
            return EPDKCatalogLoad(catalog: parsed, usedCache: false, warning: nil, nextFetchAt: next)
        } catch {
            if let catalog {
                return EPDKCatalogLoad(
                    catalog: catalog,
                    usedCache: true,
                    warning: "EPDK’ye ulaşılamadı; son kayıtlı katalog gösteriliyor.",
                    nextFetchAt: nextFetchAt
                )
            }
            throw error
        }
    }

    private func loadCacheIfNeeded() -> EPDKCatalog? {
        if let cachedCatalog { return cachedCatalog }
        guard let data = try? Data(contentsOf: cacheURL, options: .mappedIfSafe),
              let catalog = try? JSONDecoder().decode(EPDKCatalog.self, from: data) else { return nil }
        cachedCatalog = catalog
        return catalog
    }

    private func save(_ catalog: EPDKCatalog) throws {
        let data = try JSONEncoder().encode(catalog)
        try data.write(to: cacheURL, options: .atomic)
    }

    private static func retryDate(from headers: [String: String], now: Date) -> Date {
        if let seconds = headers["retry-after"].flatMap(TimeInterval.init), seconds > 0 {
            return now.addingTimeInterval(min(seconds, 24 * 60 * 60))
        }
        return now.addingTimeInterval(refreshInterval)
    }
}

enum EPDKStationError: LocalizedError {
    case rateLimited(Date)
    case http(Int)
    case unsupportedEncoding
    case responseTooLarge
    case invalidHTTPResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let date):
            return "EPDK saatlik sorgu sınırı. Yeniden deneme: \(TurkishFormat.date(date, format: "HH:mm"))."
        case .http(let code): return "EPDK HTTP \(code) yanıtı verdi."
        case .unsupportedEncoding: return "EPDK desteklenmeyen yanıt sıkıştırması kullandı."
        case .responseTooLarge: return "EPDK kataloğu izin verilen boyutu aşıyor."
        case .invalidHTTPResponse: return "EPDK yanıtı geçerli bir HTTP yanıtı değil."
        case .transport(let message): return "EPDK bağlantısı kurulamadı: \(message)"
        }
    }
}

private struct EPDKHTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let bodyURL: URL
}

/// URLSession iOS 13+ sürümlerinde GET gövdeli istekleri reddeder; EPDK'nın
/// `/sarjIstasyonlari` uç noktası ise GET + `{}` gövdesi bekler. Bu taşıma,
/// Network.framework TLS doğrulamasını kullanarak HTTP/1.1 isteğini yollar ve
/// büyük kataloğu bellekte biriktirmeden geçici dosyaya akıtır.
private final class EPDKHTTPGetBodyTransport: @unchecked Sendable {
    static let maximumBodyBytes = 32 * 1024 * 1024
    private static let maximumHeaderBytes = 64 * 1024

    private let queue = DispatchQueue(label: "com.toqdas.epdk.http", qos: .utility)
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<EPDKHTTPResponse, Error>?
    private var temporaryURL: URL?
    private var fileHandle: FileHandle?
    private var headerBuffer = Data()
    private var headersParsed = false
    private var responseHeaders: [String: String] = [:]
    private var statusCode: Int?
    private var expectedBodyLength: Int?
    private var receivedBodyLength = 0
    private var completed = false

    func fetchCatalog() async throws -> EPDKHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                let bodyURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("toqdas-epdk-\(UUID().uuidString).body")
                self.temporaryURL = bodyURL
                FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
                do {
                    self.fileHandle = try FileHandle(forWritingTo: bodyURL)
                } catch {
                    self.finish(.failure(error))
                    return
                }

                let tls = NWProtocolTLS.Options()
                let tcp = NWProtocolTCP.Options()
                let parameters = NWParameters(tls: tls, tcp: tcp)
                let connection = NWConnection(
                    host: NWEndpoint.Host("apigateway.epdk.gov.tr"),
                    port: 443,
                    using: parameters
                )
                self.connection = connection
                connection.stateUpdateHandler = { [self] state in
                    guard !self.completed else { return }
                    switch state {
                    case .ready:
                        self.sendRequest()
                    case .failed(let error):
                        self.finish(.failure(EPDKStationError.transport(error.localizedDescription)))
                    case .cancelled:
                        if !self.completed {
                            self.finish(.failure(EPDKStationError.transport("İstek iptal edildi.")))
                        }
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 60) { [self] in
                    guard !self.completed else { return }
                    self.finish(.failure(EPDKStationError.transport("Zaman aşımı.")))
                }
            }
        }
    }

    private func sendRequest() {
        let request = """
        GET /sarjIstasyonlari HTTP/1.1\r
        Host: apigateway.epdk.gov.tr\r
        User-Agent: Toqdas/EPDK-iOS\r
        Content-Type: application/json\r
        Accept: application/json\r
        Accept-Encoding: identity\r
        Content-Length: 2\r
        Connection: close\r
        \r
        {}
        """
        connection?.send(content: Data(request.utf8), completion: .contentProcessed { [weak self] error in
            guard let self, !self.completed else { return }
            if let error {
                self.finish(.failure(EPDKStationError.transport(error.localizedDescription)))
            } else {
                self.receiveNext()
            }
        })
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.completed else { return }
            do {
                if let data, !data.isEmpty { try self.consume(data) }
                if self.completed { return }
                if let error { throw error }
                if isComplete {
                    guard self.headersParsed, let status = self.statusCode else {
                        throw EPDKStationError.invalidHTTPResponse
                    }
                    if let expected = self.expectedBodyLength, expected != self.receivedBodyLength {
                        throw EPDKStationError.invalidHTTPResponse
                    }
                    self.finish(.success(EPDKHTTPResponse(
                        statusCode: status,
                        headers: self.responseHeaders,
                        bodyURL: self.temporaryURL!
                    )))
                } else {
                    self.receiveNext()
                }
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    private func consume(_ data: Data) throws {
        if !headersParsed {
            headerBuffer.append(data)
            guard headerBuffer.count <= Self.maximumHeaderBytes else {
                throw EPDKStationError.invalidHTTPResponse
            }
            guard let separator = headerBuffer.range(of: Data([13, 10, 13, 10])) else { return }
            let headerData = headerBuffer[..<separator.lowerBound]
            let bodyStart = separator.upperBound
            try parseHeaders(Data(headerData))
            headersParsed = true
            let firstBody = Data(headerBuffer[bodyStart...])
            headerBuffer.removeAll(keepingCapacity: false)
            if !firstBody.isEmpty { try writeBody(firstBody) }
        } else {
            try writeBody(data)
        }

        if let expectedBodyLength, receivedBodyLength == expectedBodyLength {
            guard let statusCode else { throw EPDKStationError.invalidHTTPResponse }
            finish(.success(EPDKHTTPResponse(
                statusCode: statusCode,
                headers: responseHeaders,
                bodyURL: temporaryURL!
            )))
        }
    }

    private func parseHeaders(_ data: Data) throws {
        guard let text = String(data: data, encoding: .isoLatin1) else {
            throw EPDKStationError.invalidHTTPResponse
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let statusLine = lines.first,
              let code = statusLine.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) else {
            throw EPDKStationError.invalidHTTPResponse
        }
        statusCode = code
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            responseHeaders[name] = value
        }
        if let transferEncoding = responseHeaders["transfer-encoding"],
           transferEncoding.lowercased().contains("chunked") {
            throw EPDKStationError.invalidHTTPResponse
        }
        if let rawLength = responseHeaders["content-length"], let length = Int(rawLength) {
            guard length >= 0, length <= Self.maximumBodyBytes else {
                throw EPDKStationError.responseTooLarge
            }
            expectedBodyLength = length
        }
    }

    private func writeBody(_ data: Data) throws {
        receivedBodyLength += data.count
        guard receivedBodyLength <= Self.maximumBodyBytes else {
            throw EPDKStationError.responseTooLarge
        }
        try fileHandle?.write(contentsOf: data)
    }

    private func finish(_ result: Result<EPDKHTTPResponse, Error>) {
        guard !completed else { return }
        completed = true
        try? fileHandle?.close()
        fileHandle = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        if case .failure = result, let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}
