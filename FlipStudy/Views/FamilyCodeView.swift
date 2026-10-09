import SwiftUI

/// Turns on FlipStudy Cloud by redeeming a family code — typed in, or scanned
/// from a QR someone sent or printed. This screen is the only way into the
/// cloud engine; with no code the app never talks to a server.
///
/// Reached from Settings *after* the grown-up gate, because switching it on
/// means page text starts leaving the phone.
struct FamilyCodeView: View {
    /// A code that arrived by join link, shown ready to confirm. Empty when the
    /// user opened this screen themselves.
    var initialCode: String = ""
    /// Called with the code's label ("Sam's iPhone") once it is redeemed.
    var onRedeemed: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isRedeeming = false
    @State private var errorMessage: String?
    @State private var showingScanner = false

    private var canRedeem: Bool {
        FamilyAccess.normalized(code) != nil && !isRedeeming
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("FLIP-XXXX-XXXX", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onSubmit { if canRedeem { redeem(code) } }

                    if QRCodeScanner.isSupported {
                        Button {
                            errorMessage = nil
                            showingScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        }
                    }
                } header: {
                    Text("Family Code")
                } footer: {
                    Text("Type the code you were given, or scan its QR. Codes look like FLIP-A7K2-9QX4.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        redeem(code)
                    } label: {
                        if isRedeeming {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Turning on…")
                            }
                        } else {
                            Label("Turn On FlipStudy Cloud", systemImage: "cloud")
                        }
                    }
                    .disabled(!canRedeem)
                } footer: {
                    Text("FlipStudy Cloud makes cards with a much larger AI than the one built into this phone, so it works even on iPhones without Apple Intelligence. The text you scan or type, and any card you ask it to explain, is sent over an encrypted connection to FlipStudy's own service, and is not stored there. Everything else — your decks, your study progress — stays on this phone.")
                }
            }
            .navigationTitle("FlipStudy Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Pre-filled, not auto-redeemed: turning Cloud on sends text off the
            // phone, so the tap on Turn On stays the user's own.
            .onAppear {
                if code.isEmpty, !initialCode.isEmpty {
                    code = Self.formatted(initialCode)
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                NavigationStack {
                    QRCodeScanner { payload in
                        showingScanner = false
                        // Scanning is itself the deliberate action, so a good
                        // scan goes straight through rather than asking the
                        // user to confirm what they just pointed the camera at.
                        code = Self.formatted(payload)
                        redeem(payload)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingScanner = false }
                        }
                    }
                }
            }
        }
    }

    /// Group a scanned payload back into the readable FLIP-XXXX-XXXX shape so
    /// the field shows what the user expects to see.
    static func formatted(_ raw: String) -> String {
        guard let condensed = FamilyAccess.normalized(raw) else { return raw }
        let body = condensed.dropFirst(4)
        return "FLIP-\(body.prefix(4))-\(body.suffix(4))"
    }

    private func redeem(_ raw: String) {
        guard !isRedeeming else { return }
        errorMessage = nil
        isRedeeming = true
        Task {
            do {
                let label = try await FamilyAccess.redeem(raw)
                onRedeemed(label)
                dismiss()
            } catch {
                errorMessage = CardEngine.friendlyMessage(for: error)
            }
            isRedeeming = false
        }
    }
}
