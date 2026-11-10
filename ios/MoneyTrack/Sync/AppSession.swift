import Foundation
import Observation
import Network

@MainActor @Observable
final class AppSession {
    private(set) var store: LedgerStore?
    private(set) var credential: SessionCredential?
    private(set) var isSyncing = false
    private(set) var needsAuthentication = false
    private(set) var status = String(localized: "On this iPhone")
    private(set) var lastSync: Date?
    private(set) var syncError: String?
    private let vault: any CredentialVault
    private let transport: any SyncTransport
    private let root: URL?
    private let localNamespace: StoreNamespace
    private let fixedToday: Date?
    private let monitor = NWPathMonitor()
    private var monitoring = false
    private var generation = 0
    private var requestedAgain = false
    var profileKey: String { credential?.profileKey ?? localNamespace.directoryName }

    init(vault: any CredentialVault = KeychainVault(), transport: any SyncTransport = HTTPTransport(),
         root: URL? = nil, localNamespace: StoreNamespace = .localDevice, today: Date? = nil) {
        self.vault = vault; self.transport = transport; self.root = root
        self.localNamespace = localNamespace; fixedToday = today
    }

    deinit { monitor.cancel() }

    func open() throws {
        let saved = try vault.read()
        let namespace = saved.map { StoreNamespace.serverAccount($0.server, $0.userID) } ?? localNamespace
        let opened = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace), today: fixedToday)
        credential = saved; store = opened
        status = saved == nil ? String(localized: "On this iPhone") : String(localized: "Ready to sync")
        if !monitoring {
            monitoring = true
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in await self?.synchronize() }
            }
            monitor.start(queue: DispatchQueue(label: "MoneyTrack.Connectivity"))
        }
    }

    func signIn(server: String, username: String, password: String, copyLocal: Bool) async throws {
        let url = try ServerAddress.parse(server)
        let signedIn = try await transport.signIn(server: url, username: username, password: password)
        if let current = credential, current.profileKey != signedIn.profileKey {
            try? await transport.signOut(signedIn)
            throw ConnectionError.rejected(String(localized: "Sign out before switching to a different account or server. Your saved entries will stay separate."))
        }
        do {
            try Task.checkCancellation()
            let destination = try LedgerStore(container: LedgerPersistence.container(root: root,
                namespace: .serverAccount(url, signedIn.userID)), today: fixedToday)
            if copyLocal && credential == nil {
                // Catch up first so copying cannot overwrite an account that already has records.
                try await pullAll(into: destination, credential: signedIn)
                let source = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: localNamespace), today: fixedToday)
                try destination.importLocal(source)
            }
            try Task.checkCancellation()
            try vault.write(signedIn)
            generation += 1
            credential = signedIn; store = destination; needsAuthentication = false
            status = String(localized: "Ready to sync")
            Task { await self.synchronize() }
        } catch {
            try? await transport.signOut(signedIn)
            throw error
        }
    }

    func signOut() async throws {
        let local = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: localNamespace), today: fixedToday)
        let old = credential
        try vault.clear()
        generation += 1
        credential = nil; store = local; needsAuthentication = false
        status = String(localized: "On this iPhone"); lastSync = nil
        if let old { try? await transport.signOut(old) }
    }

    func synchronize() async {
        guard let credential, let store, !needsAuthentication else { return }
        if isSyncing { requestedAgain = true; return }
        let started = generation
        isSyncing = true
        status = String(localized: "Syncing…")
        syncError = nil
        defer {
            isSyncing = false
            if requestedAgain {
                requestedAgain = false
                Task { await self.synchronize() }
            }
        }
        do {
            while let (id, data) = try store.prepareNextOperation() {
                do {
                    let record = try await transport.push(data, credential: credential)
                    guard generation == started else { return }
                    try store.acknowledge(id, record: record)
                } catch let issue as ServerRejection {
                    guard generation == started else { return }
                    try store.recordIssue(id, message: issue.message, current: issue.current)
                    break
                }
            }
            var restarted = false
            repeat {
                let page: ChangePage
                do { page = try await transport.pull(cursor: store.cursor, credential: credential) }
                catch ConnectionError.invalidCursor {
                    guard generation == started else { return }
                    guard !restarted else { throw ConnectionError.invalidCursor }
                    restarted = true
                    try store.restartPull()
                    continue
                }
                guard generation == started else { return }
                try store.receive(page)
                if !page.hasMore { break }
            } while true
            guard generation == started else { return }
            lastSync = .now
            status = store.issues.isEmpty ? String(localized: "Up to date") : String(localized: "Changes need review")
        } catch ConnectionError.unauthorized {
            guard generation == started else { return }
            needsAuthentication = true
            status = String(localized: "Sign in again to resume syncing")
        } catch {
            guard generation == started else { return }
            status = String(localized: "Saved on this iPhone · couldn't sync")
            syncError = error.localizedDescription
        }
    }

    private func pullAll(into store: LedgerStore, credential: SessionCredential) async throws {
        var restarted = false
        repeat {
            let page: ChangePage
            do { page = try await transport.pull(cursor: store.cursor, credential: credential) }
            catch ConnectionError.invalidCursor {
                guard !restarted else { throw ConnectionError.invalidCursor }
                restarted = true
                try store.restartPull()
                continue
            }
            try Task.checkCancellation()
            try store.receive(page)
            if !page.hasMore { break }
        } while true
    }
}


extension AppSession {
    func emailStatus() async throws -> AccountEmailStatus {
        try await emailOperation { try await self.transport.emailStatus(credential: $0) }
    }
    func requestEmail(_ address: String, requestID: UUID) async throws -> AccountEmailStatus {
        try await emailOperation { try await self.transport.requestEmail(address, requestID: requestID, credential: $0) }
    }
    func verifyEmail(id: UUID, code: String) async throws -> AccountEmailStatus {
        let value = try await emailOperation { try await self.transport.verifyEmail(id: id, code: code, credential: $0) }
        Task { await self.synchronize() }
        return value
    }
    private func emailOperation(_ operation: (SessionCredential) async throws -> AccountEmailStatus) async throws -> AccountEmailStatus {
        guard let credential, !needsAuthentication else { throw ConnectionError.unauthorized }
        let started = generation
        do {
            let result = try await operation(credential)
            try Task.checkCancellation()
            guard started == generation else { throw CancellationError() }
            return result
        } catch {
            if started == generation, case ConnectionError.unauthorized = error {
                needsAuthentication = true
                status = String(localized: "Sign in to sync")
            }
            throw error
        }
    }
}
