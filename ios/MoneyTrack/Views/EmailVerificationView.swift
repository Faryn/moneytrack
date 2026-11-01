import SwiftUI

struct EmailVerificationView: View {
    @Environment(AppSession.self) private var app
    @State private var status: AccountEmailStatus?
    @State private var address = ""
    @State private var code = ""
    @State private var requestID = UUID()
    @State private var working = true
    @State private var error: String?
    @State private var action: Task<Void, Never>?
    @FocusState private var focused: Field?
    private enum Field { case address, code }

    var body: some View {
        Form {
            if let verified = status?.verifiedEmail {
                Section {
                    Label("Email Verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(verified).textSelection(.enabled)
                } footer: { Text("This address identifies your account for sharing invitations. Continue signing in with your username and password.") }
            } else {
                Section {
                    TextField("Email address", text: $address)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused, equals: .address)
                        .accessibilityIdentifier("email.address")
                    Button(status?.verificationID == nil ? "Send Verification Code" : "Send New Code") {
                        run {
                            // Keep the ID across an uncertain response; start a fresh request after acknowledgment.
                            status = try await app.requestEmail(address, requestID: requestID)
                            requestID = UUID()
                            code = ""
                            focused = .code
                        }
                    }
                    .disabled(working || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("email.send")
                } footer: {
                    Text("Verify ownership of your mailbox to receive sharing invitations. Email isn't used for login or password recovery.")
                }
                if let id = status?.verificationID, let pending = status?.pendingEmail {
                    Section {
                        if status?.deliveryStatus == "failed" {
                            Text("We couldn't send the code to \(pending). Request a new code.").foregroundStyle(.red)
                        } else {
                            Text("Check \(pending) for your eight-digit code. Delivery can take a moment.")
                        }
                        TextField("Verification code", text: $code)
                            .textContentType(.oneTimeCode).keyboardType(.numberPad)
                            .focused($focused, equals: .code).privacySensitive()
                            .accessibilityIdentifier("email.code")
                        Button("Verify Email") {
                            run {
                                status = try await app.verifyEmail(id: id, code: code)
                                code = ""
                                focused = nil
                            }
                        }
                        .disabled(working || code.count != 8 || !code.utf8.allSatisfy { (48...57).contains($0) })
                        .accessibilityIdentifier("email.verify")
                    } header: { Text("Verification Code") } footer: {
                        Text("Codes expire after 30 minutes and allow five attempts. Only the newest code works.")
                    }
                }
            }
            if working { ProgressView().accessibilityLabel("Checking email verification") }
            if let error {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("email.error") }
            }
        }
        .navigationTitle("Email for Sharing")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } }
        }
        .task {
            defer { working = false }
            do {
                status = try await app.emailStatus()
                address = status?.pendingEmail ?? ""
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        .onChange(of: address) { requestID = UUID() }
        .onDisappear { action?.cancel() }
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        working = true; error = nil
        action = Task { @MainActor in
            defer { working = false }
            do { try await work() }
            catch is CancellationError {} catch {
                self.error = error.localizedDescription
                // If verification succeeded but its response was lost, refreshing restores the verified state.
                if let refreshed = try? await app.emailStatus() {
                    status = refreshed
                    if refreshed.verificationID == requestID || refreshed.verificationID == nil { requestID = UUID() }
                }
            }
        }
    }
}
