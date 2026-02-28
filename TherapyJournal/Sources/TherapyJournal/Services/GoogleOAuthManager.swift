import Foundation
import AppKit

final class GoogleOAuthManager: ObservableObject {
    static let shared = GoogleOAuthManager()

    @Published var isAuthenticated = false

    private let redirectURI = "http://127.0.0.1:8089/oauth/callback"
    private let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.send"
    ].joined(separator: " ")

    private var httpServer: HTTPOAuthServer?
    private var currentToken: GoogleOAuthToken?

    private init() {
        loadToken()
    }

    // MARK: - Public

    func startOAuthFlow() {
        let config = AppConfig.load()
        guard !config.googleClientID.isEmpty else {
            AppLogger.shared.error("Google Client ID not configured")
            return
        }

        httpServer = HTTPOAuthServer(port: 8089) { [weak self] code in
            Task {
                await self?.exchangeCodeForToken(code: code)
            }
        }
        httpServer?.start()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.googleClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
            AppLogger.shared.info("Opened Google OAuth consent screen")
        }
    }

    func getValidAccessToken() async throws -> String {
        guard var token = currentToken else {
            throw GoogleOAuthError.notAuthenticated
        }

        if token.isExpired {
            token = try await refreshToken(token)
            self.currentToken = token
            try KeychainManager.shared.saveCodable(key: .googleOAuthToken, value: token)
        }

        return token.accessToken
    }

    func signOut() {
        currentToken = nil
        try? KeychainManager.shared.delete(key: .googleOAuthToken)
        DispatchQueue.main.async {
            self.isAuthenticated = false
        }
        AppLogger.shared.info("Google OAuth signed out")
    }

    // MARK: - Token Exchange

    private func exchangeCodeForToken(code: String) async {
        let config = AppConfig.load()
        let url = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "code": code,
            "client_id": config.googleClientID,
            "client_secret": config.googleClientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                AppLogger.shared.error("Token exchange failed: \(body)")
                return
            }

            var token = try JSONDecoder().decode(GoogleOAuthToken.self, from: data)
            token.expirationDate = Date().addingTimeInterval(TimeInterval(token.expiresIn))

            try KeychainManager.shared.saveCodable(key: .googleOAuthToken, value: token)
            self.currentToken = token

            DispatchQueue.main.async {
                self.isAuthenticated = true
            }
            AppLogger.shared.info("Google OAuth token obtained successfully")
        } catch {
            AppLogger.shared.error("Token exchange error: \(error.localizedDescription)")
        }

        httpServer?.stop()
        httpServer = nil
    }

    private func refreshToken(_ token: GoogleOAuthToken) async throws -> GoogleOAuthToken {
        guard let refreshToken = token.refreshToken else {
            throw GoogleOAuthError.noRefreshToken
        }

        let config = AppConfig.load()
        let url = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": config.googleClientID,
            "client_secret": config.googleClientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GoogleOAuthError.tokenRefreshFailed
        }

        var newToken = try JSONDecoder().decode(GoogleOAuthToken.self, from: data)
        newToken.expirationDate = Date().addingTimeInterval(TimeInterval(newToken.expiresIn))

        // Preserve the refresh token if the new response doesn't include one
        if newToken.refreshToken == nil {
            newToken = GoogleOAuthToken(
                accessToken: newToken.accessToken,
                refreshToken: refreshToken,
                expiresIn: newToken.expiresIn,
                tokenType: newToken.tokenType,
                scope: newToken.scope,
                expirationDate: newToken.expirationDate
            )
        }

        AppLogger.shared.info("Google OAuth token refreshed")
        return newToken
    }

    // MARK: - Persistence

    private func loadToken() {
        do {
            currentToken = try KeychainManager.shared.retrieveCodable(key: .googleOAuthToken, type: GoogleOAuthToken.self)
            isAuthenticated = currentToken != nil
            AppLogger.shared.info("Loaded Google OAuth token from Keychain")
        } catch {
            isAuthenticated = false
        }
    }
}

// MARK: - Errors

enum GoogleOAuthError: LocalizedError {
    case notAuthenticated
    case noRefreshToken
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated with Google. Please sign in."
        case .noRefreshToken: return "No refresh token available. Please re-authenticate."
        case .tokenRefreshFailed: return "Failed to refresh Google OAuth token."
        }
    }
}

// MARK: - Minimal HTTP Server for OAuth Callback

final class HTTPOAuthServer {
    private let port: UInt16
    private let callback: (String) -> Void
    private var socketFD: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.therapyjournal.oauth-server")

    init(port: UInt16, callback: @escaping (String) -> Void) {
        self.port = port
        self.callback = callback
    }

    func start() {
        queue.async { [weak self] in
            self?.listen()
        }
    }

    func stop() {
        isRunning = false
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func listen() {
        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return }

        var opt: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bindPtr in
                bind(socketFD, bindPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else {
            AppLogger.shared.error("OAuth server bind failed")
            return
        }

        Foundation.listen(socketFD, 1)
        isRunning = true
        AppLogger.shared.info("OAuth callback server listening on port \(port)")

        while isRunning {
            let clientFD = accept(socketFD, nil, nil)
            guard clientFD >= 0 else { continue }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let requestString = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
                if let code = extractCode(from: requestString) {
                    let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html\r
                    \r
                    <html><body><h2>Authentication successful!</h2><p>You can close this tab and return to Therapy Journal.</p></body></html>
                    """
                    _ = response.withCString { ptr in
                        write(clientFD, ptr, strlen(ptr))
                    }
                    close(clientFD)
                    callback(code)
                    isRunning = false
                    return
                }
            }
            close(clientFD)
        }
    }

    private func extractCode(from request: String) -> String? {
        guard let line = request.split(separator: "\r\n").first,
              let urlPart = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(urlPart)),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        return code
    }
}
