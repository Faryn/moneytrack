import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), integer(Int64), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: JSONEncoder().encode(self))
    }
    static func value<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(Self.self, from: encoder.encode(value))
    }
}

struct RemoteRecord: Codable, Equatable, Sendable {
    let entity: String
    let entityID: UUID
    let revision: Int64
    let deleted: Bool
    let payload: JSONValue
    var key: String { Self.key(entity, entityID) }
    static func key(_ entity: String, _ id: UUID) -> String { entity + ":" + id.uuidString.lowercased() }
}
struct ChangePage: Codable, Sendable {
    let changes: [RemoteRecord]
    let cursor: String
    let hasMore: Bool
}
struct WireOperation: Codable, Sendable {
    let operationID: UUID
    let entity: String
    let entityID: UUID
    let action: String
    let expectedRevision: Int64
    let payload: JSONValue
}
struct SyncIssue: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let entity: String
    let entityID: UUID
    let message: String
    let current: RemoteRecord?
}
struct SessionCredential: Codable, Equatable, Sendable {
    let userID: UUID
    let username: String
    let server: URL
    let token: String
    var profileKey: String { server.absoluteString + "|" + userID.uuidString }
}

enum ConnectionError: LocalizedError {
    case invalidServer, unauthorized, invalidData, invalidCursor, notEmpty, rejected(String)
    var errorDescription: String? {
        switch self {
        case .invalidServer: String(localized: "Enter an HTTPS server address. Local HTTP is available only in development.")
        case .unauthorized: String(localized: "Sign in again to continue syncing. Your saved expenses are still available.")
        case .invalidData: String(localized: "The server returned incompatible data. Your local changes are preserved.")
        case .invalidCursor: String(localized: "Synchronization needs to catch up again. Your local changes are preserved.")
        case .notEmpty: String(localized: "This account already has entries. Sign in with copying turned off to keep the two sets separate.")
        case .rejected(let message): Bundle.main.localizedString(forKey: message, value: message, table: nil)
        }
    }
}

enum ServerAddress {
    static var defaultSignInAddress: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return initialSignInAddress(configured: nil, isTesting: true,
                testingServer: ProcessInfo.processInfo.environment["MONEYTRACK_TEST_SERVER"])
        }
        #endif
        return initialSignInAddress(configured: Bundle.main.object(forInfoDictionaryKey: "MoneyTrackDefaultServerURL") as? String)
    }

    static func initialSignInAddress(configured: String?, isTesting: Bool = false, testingServer: String? = nil) -> String {
        // A missing test override must never fall through to the real instance.
        let candidate = isTesting ? testingServer : configured
        guard let candidate, !candidate.contains("$("), let url = try? parse(candidate) else { return "" }
        return url.absoluteString
    }

    static func parse(_ text: String) throws -> URL {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host?.lowercased(), !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/" else { throw ConnectionError.invalidServer }
        let scheme = c.scheme?.lowercased()
        var allowed = scheme == "https"
        #if DEBUG
        allowed = allowed || (scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host))
        #endif
        guard allowed else { throw ConnectionError.invalidServer }
        c.scheme = scheme; c.host = host; c.path = ""
        if (scheme == "https" && c.port == 443) || (scheme == "http" && c.port == 80) { c.port = nil }
        guard let url = c.url else { throw ConnectionError.invalidServer }
        return url
    }
}
