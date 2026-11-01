import SwiftUI

@main
struct MoneyTrackApp: App {
    var body: some Scene {
        WindowGroup {
            StoreBootstrapView()
        }
    }
}

private struct StoreBootstrapView: View {
    @State private var store: LedgerStore?
    @State private var failed = false

    var body: some View {
        Group {
            if let store {
                AppRootView(store: store).environment(store)
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
        .task { if store == nil { openStore() } }
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
            store = try LedgerStore(container: LedgerPersistence.container(namespace: namespace), today: today)
            failed = false
        } catch {
            failed = true
        }
    }
}
