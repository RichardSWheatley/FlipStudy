import Foundation
import Security

/// FlipStudy Cloud access, unlocked by a family code that's typed in or scanned
/// from a QR. The code is the only door to the cloud engine: without one, the
/// app behaves exactly as it did before — Apple Intelligence or nothing.
///
/// The split mirrors the cloud-translation feature: the **secret** (the device
/// token earned by redeeming) lives in the Keychain, while the plain facts a
/// view needs to render — whether it's on, and whose code it is — live in
/// `AppSettings` so SwiftUI updates on its own when a code is redeemed.
///
/// The raw code is deliberately *not* kept after redemption. It is worth more
/// than the token (it works on any phone, the token only on this one), so the
/// app forgets it as soon as it has been exchanged.
enum FamilyAccess {
    private static let service = "com.flipstudy.app.cloud"
    private static let tokenAccount = "familyToken"
    private static let deviceAccount = "familyDevice"

    /// Whether this phone holds a redeemed token.
    static var isActive: Bool { !token.isEmpty }

    static var token: String { readRaw(account: tokenAccount) }

    /// A stable id for this install, so the Worker can cap how many phones one
    /// code unlocks and revoke a single one. Keychain items outlive app
    /// deletion, so reinstalling doesn't burn another device slot.
    static var deviceID: String {
        let existing = readRaw(account: deviceAccount)
        if !existing.isEmpty { return existing }
        let fresh = UUID().uuidString
        writeRaw(fresh, account: deviceAccount)
        return fresh
    }

    // MARK: - Redeeming

    /// Exchange a family code for a device token. Returns the code's label (for
    /// example "Sam's iPhone") so Settings can show which code is in use.
    @discardableResult
    static func redeem(_ rawCode: String) async throws -> String {
        guard let code = normalized(rawCode) else {
            throw CloudCardError.invalidCode
        }

        var request = URLRequest(url: CloudCardGenerator.endpoint.appending(path: "v1/redeem"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RedeemRequest(code: code, device: deviceID)
        )
        request.timeoutInterval = 20

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudCardError.server
        }
        guard http.statusCode == 200 else {
            throw CloudCardError(serverCode: Self.errorCode(in: data), status: http.statusCode)
        }

        let redeemed = try JSONDecoder().decode(RedeemResponse.self, from: data)
        writeRaw(redeemed.token, account: tokenAccount)
        return redeemed.label
    }

    /// Forget this phone's access. The code itself stays valid elsewhere —
    /// revoking it for everyone is a Worker-side action (see worker/README.md).
    static func signOut() {
        deleteRaw(account: tokenAccount)
    }

    // MARK: - Code parsing

    /// Clean a typed or scanned code into the form the Worker expects, or nil
    /// if it couldn't plausibly be a FlipStudy code. Accepts a bare code, or a
    /// URL carrying one, so a QR can hold either.
    static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // A QR may hold "flipstudy://redeem?code=FLIP-..." or an https link.
        if text.contains("://"),
           let components = URLComponents(string: text),
           let queried = components.queryItems?.first(where: { $0.name == "code" })?.value {
            text = queried
        }

        let condensed = text.uppercased().filter { $0.isLetter || $0.isNumber }
        // FLIP + two four-character groups.
        guard condensed.count == 12, condensed.hasPrefix("FLIP") else { return nil }
        return condensed
    }

    // MARK: - Networking

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet
                                        || error.code == .networkConnectionLost
                                        || error.code == .cannotFindHost
                                        || error.code == .cannotConnectToHost
                                        || error.code == .dnsLookupFailed {
            throw CloudCardError.offline
        } catch {
            throw CloudCardError.network(error.localizedDescription)
        }
    }

    /// Pull the Worker's machine-readable error code out of a failure body.
    static func errorCode(in data: Data) -> String {
        (try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? ""
    }

    private struct RedeemRequest: Encodable {
        let code: String
        let device: String
    }

    private struct RedeemResponse: Decodable {
        let token: String
        let label: String
    }

    private struct ServerError: Decodable {
        let error: String
    }

    // MARK: - Keychain primitives

    private static func readRaw(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    private static func writeRaw(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func deleteRaw(account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
    }
}
