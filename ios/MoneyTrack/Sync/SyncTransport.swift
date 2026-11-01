import Foundation

protocol SyncTransport: Sendable {
    func signIn(server: URL, username: String, password: String) async throws -> SessionCredential
    func push(_ data: Data, credential: SessionCredential) async throws -> RemoteRecord
    func pull(cursor: String?, credential: SessionCredential) async throws -> ChangePage
    func signOut(_ credential: SessionCredential) async throws
    func emailStatus(credential: SessionCredential) async throws -> AccountEmailStatus
    func requestEmail(_ address: String, requestID: UUID, credential: SessionCredential) async throws -> AccountEmailStatus
    func verifyEmail(id: UUID, code: String, credential: SessionCredential) async throws -> AccountEmailStatus
}

struct ServerRejection: LocalizedError, Sendable {
    let message: String
    let current: RemoteRecord?
    var errorDescription: String? { message }
}

struct HTTPTransport: SyncTransport {
    let session: URLSession
    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }
    func signIn(server: URL, username: String, password: String) async throws -> SessionCredential {
        struct Login: Encodable { let username: String; let password: String; let deviceName = "iPhone" }
        struct Response: Decodable {
            struct User: Decodable { let id: UUID; let username: String }
            let user: User; let token: String
        }
        let data = try JSONEncoder().encode(Login(username: username, password: password))
        let response = try await request(server: server, path: "api/v1/sessions", method: "POST", body: data)
        let value = try JSONDecoder().decode(Response.self, from: response)
        return SessionCredential(userID: value.user.id, username: value.user.username, server: server, token: value.token)
    }
    func push(_ data: Data, credential: SessionCredential) async throws -> RemoteRecord {
        struct Response: Decodable { let record: RemoteRecord }
        return try JSONDecoder().decode(Response.self, from: await request(server: credential.server,
            path: "api/v2/sync", method: "POST", body: data, token: credential.token)).record
    }
    func pull(cursor: String?, credential: SessionCredential) async throws -> ChangePage {
        let query = cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
        return try JSONDecoder().decode(ChangePage.self, from: await request(server: credential.server,
            path: "api/v2/sync", method: "GET", query: query, token: credential.token))
    }
    func signOut(_ credential: SessionCredential) async throws {
        _ = try await request(server: credential.server, path: "api/v1/session", method: "DELETE", token: credential.token)
    }
    private func request(server: URL, path: String, method: String, body: Data? = nil,
                         query: [URLQueryItem] = [], token: String? = nil) async throws -> Data {
        _ = try ServerAddress.parse(server.absoluteString)
        guard var components = URLComponents(url: server.appending(path: path), resolvingAgainstBaseURL: false) else { throw ConnectionError.invalidServer }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ConnectionError.invalidServer }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ConnectionError.invalidData }
        if (200...299).contains(response.statusCode) { return data }
        struct Failure: Decodable { let error: String; let message: String; let current: RemoteRecord? }
        let failure = try? JSONDecoder().decode(Failure.self, from: data)
        if response.statusCode == 401 {
            if token == nil { throw ConnectionError.rejected(failure?.message ?? "Couldn't sign in.") }
            throw ConnectionError.unauthorized
        }
        if response.statusCode == 400 && failure?.error == "invalid_cursor" { throw ConnectionError.invalidCursor }
        if [404, 409, 422].contains(response.statusCode) {
            throw ServerRejection(message: failure?.message ?? "This change needs review.", current: failure?.current)
        }
        throw ConnectionError.rejected(failure?.message ?? "The server is unavailable. Your local changes are preserved.")
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}


struct AccountEmailStatus: Codable, Equatable, Sendable {
    let deliveryStatus: String?
    let verifiedEmail: String?
    let pendingEmail: String?
    let verificationID: UUID?
    let expiresAt: String?
}

extension SyncTransport {
    func emailStatus(credential: SessionCredential) async throws -> AccountEmailStatus { throw ConnectionError.rejected("Email verification is unavailable.") }
    func requestEmail(_ address: String, requestID: UUID, credential: SessionCredential) async throws -> AccountEmailStatus { throw ConnectionError.rejected("Email verification is unavailable.") }
    func verifyEmail(id: UUID, code: String, credential: SessionCredential) async throws -> AccountEmailStatus { throw ConnectionError.rejected("Email verification is unavailable.") }
}

extension HTTPTransport {
    func emailStatus(credential: SessionCredential) async throws -> AccountEmailStatus {
        try JSONDecoder().decode(AccountEmailStatus.self, from: await request(server: credential.server,
            path: "api/v1/account/email", method: "GET", token: credential.token))
    }
    func requestEmail(_ address: String, requestID: UUID, credential: SessionCredential) async throws -> AccountEmailStatus {
        struct Request: Encodable { let email: String; let requestID: UUID }
        return try JSONDecoder().decode(AccountEmailStatus.self, from: await request(server: credential.server,
            path: "api/v1/account/email", method: "POST", body: JSONEncoder().encode(Request(email: address, requestID: requestID)), token: credential.token))
    }
    func verifyEmail(id: UUID, code: String, credential: SessionCredential) async throws -> AccountEmailStatus {
        struct Request: Encodable { let verificationID: UUID; let code: String }
        return try JSONDecoder().decode(AccountEmailStatus.self, from: await request(server: credential.server,
            path: "api/v1/account/email/verify", method: "POST", body: JSONEncoder().encode(Request(verificationID: id, code: code)), token: credential.token))
    }
}
