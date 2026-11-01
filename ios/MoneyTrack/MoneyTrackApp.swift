import SwiftUI
import OSLog

@main
struct MoneyTrackApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if NSClassFromString("XCTestCase") != nil && !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                // Hosted unit tests open their own temporary stores, never a real profile.
                Color.clear
            } else {
                StoreBootstrapView()
            }
            #else
            StoreBootstrapView()
            #endif
        }
    }
}

private struct StoreBootstrapView: View {
    @State private var app: AppSession?
    @State private var failed = false

    var body: some View {
        Group {
            if let app, let store = app.store {
                AppRootView(store: store).environment(store).environment(app).id(app.profileKey)
            } else if failed {
                ContentUnavailableView {
                    Label("Couldn't open your expenses", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Your saved data hasn't been reset.")
                } actions: {
                    Button("Try Again", action: openStore)
                }
            } else {
                ProgressView("Opening MoneyTrack")
            }
        }
        .task { if app == nil { openStore() } }
    }

    private func openStore() {
        do {
            var namespace: StoreNamespace = .localDevice
            var today: Date?
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                namespace = .uiTesting
                if let iso = ProcessInfo.processInfo.environment["MONEYTRACK_TEST_TODAY"] {
                    today = try ExpenseDay(iso: iso).date
                }
                if ProcessInfo.processInfo.arguments.contains("--reset-ui-testing-data") {
                    let root = try FileManager.default.url(
                        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
                    ).appending(path: "MoneyTrack/ui-testing", directoryHint: .isDirectory)
                    if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
                }
            }
            #endif
            let isUITesting = namespace.directoryName == "ui-testing"
            let vault = KeychainVault(serviceSuffix: isUITesting ? ".ui-testing.session" : ".session")
            if isUITesting && ProcessInfo.processInfo.arguments.contains("--reset-ui-testing-data") { try vault.clear() }
            let session = AppSession(vault: vault,
                                     localNamespace: namespace, today: today)
            try session.open()
            app = session
            failed = false
        } catch {
            let failure = error as NSError
            Logger(subsystem: "MoneyTrack", category: "Startup").error("Store/account open failed: \(failure.domain, privacy: .public) \(failure.code)")
            failed = true
        }
    }
}
