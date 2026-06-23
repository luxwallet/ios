import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

public struct OidcSession: Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresAt: TimeInterval // unix seconds
    public let scope: String?

    public init(accessToken: String, refreshToken: String?, idToken: String?, expiresAt: TimeInterval, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresAt = expiresAt
        self.scope = scope
    }
}

public enum OidcError: Error {
    case notAuthenticated
    case invalidCallback
    case stateMismatch
    case authorizationFailed(String)
    case tokenExchangeFailed
    case userInfoFailed
    case randomGenerationFailed
}

// IAM (hanzo.id) OIDC sign-in, layered over AccountManager + CloudBackupManager.
// HIP-0111: PKCE S256 always; public client (no secret); canonical /v1/iam/oauth/* paths only.
//
// SYNC SEAM: bind accessToken() to CloudBackupManager-style cloud backup/restore once the
// Lux cloud sync endpoint is finalized.
public final class OidcAuthManager: NSObject {
    private static let serverUrl = "https://hanzo.id"
    private static let clientId = "lux-wallet"
    private static let redirectScheme = "luxwallet"
    private static let redirectUri = "luxwallet://oidc/callback"
    private static let scopes = "openid profile email"
    private static let sessionKey = "oidc_session"
    private static let expirySkew: TimeInterval = 30

    private static let authorizeUrl = "\(serverUrl)/v1/iam/oauth/authorize"
    private static let tokenUrl = "\(serverUrl)/v1/iam/oauth/token"
    private static let userInfoUrl = "\(serverUrl)/v1/iam/oauth/userinfo"

    private let keychainStorage: KeychainStorage
    private var webAuthSession: ASWebAuthenticationSession?

    public init(keychainStorage: KeychainStorage) {
        self.keychainStorage = keychainStorage
        super.init()
    }

    // MARK: - Public API

    public func signIn() async throws -> OidcSession {
        let verifier = try Self.randomBase64Url(byteCount: 32)
        let challenge = Self.codeChallenge(for: verifier)
        let state = try Self.randomBase64Url(byteCount: 32)

        let code = try await authorize(challenge: challenge, state: state)
        let session = try await exchange(code: code, verifier: verifier)

        try persist(session: session)
        return session
    }

    public func signOut() {
        try? keychainStorage.removeValue(for: Self.sessionKey)
    }

    public func currentSession() -> OidcSession? {
        guard let data: Data = keychainStorage.value(for: Self.sessionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(OidcSession.self, from: data)
    }

    /// Persist a session produced outside the PKCE web flow — e.g. a Web3 / SIWx
    /// login completed in the @hanzo/gui RN screen and handed back over the
    /// LuxSession bridge. Same keychain as the OIDC path; one way in.
    public func setSession(_ session: OidcSession) throws {
        try persist(session: session)
    }

    public func accessToken() -> String? {
        guard let session = currentSession(),
              session.expiresAt > Date().timeIntervalSince1970 + Self.expirySkew
        else {
            return nil
        }
        return session.accessToken
    }

    public func userInfo() async throws -> [String: Any] {
        guard let token = accessToken() else {
            throw OidcError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: Self.userInfoUrl)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw OidcError.userInfoFailed
        }
        return json
    }

    // MARK: - Authorize (ASWebAuthenticationSession)

    private func authorize(challenge: String, state: String) async throws -> String {
        var components = URLComponents(string: Self.authorizeUrl)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authUrl = components.url else {
            throw OidcError.invalidCallback
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authUrl, callbackURLScheme: Self.redirectScheme) { callbackUrl, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackUrl,
                      let items = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false)?.queryItems
                else {
                    continuation.resume(throwing: OidcError.invalidCallback)
                    return
                }
                if let serverError = items.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: OidcError.authorizationFailed(serverError))
                    return
                }
                guard items.first(where: { $0.name == "state" })?.value == state else {
                    continuation.resume(throwing: OidcError.stateMismatch)
                    return
                }
                guard let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: OidcError.invalidCallback)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }
    }

    // MARK: - Token exchange

    private func exchange(code: String, verifier: String) async throws -> OidcSession {
        var request = URLRequest(url: URL(string: Self.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectUri,
            "client_id": Self.clientId,
            "code_verifier": verifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue
        else {
            throw OidcError.tokenExchangeFailed
        }

        return OidcSession(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            idToken: json["id_token"] as? String,
            expiresAt: Date().timeIntervalSince1970 + expiresIn,
            scope: json["scope"] as? String
        )
    }

    private func persist(session: OidcSession) throws {
        let data = try JSONEncoder().encode(session)
        try keychainStorage.set(value: data, for: Self.sessionKey)
    }

    // MARK: - Helpers

    private static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func randomBase64Url(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw OidcError.randomGenerationFailed
        }
        return base64Url(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64Url(Data(digest))
    }

    private static func base64Url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension OidcAuthManager: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        return window ?? ASPresentationAnchor()
    }
}
