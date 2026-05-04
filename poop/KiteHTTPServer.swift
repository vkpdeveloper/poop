import Foundation
import Network
import OSLog

final class KiteHTTPServer: @unchecked Sendable {
    static let shared = KiteHTTPServer()
    private init() {}

    private var listener: NWListener?
    private var isRunning = false
    private var onCallback: ((String) -> Void)?

    private let lock = NSLock()
    private let port: UInt16 = 23864
    private let callbackHost = "127.0.0.1"

    var callbackURL: String {
        "http://\(callbackHost):\(port)/callback"
    }

    func start(onReceiveRequestToken: @escaping (String) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else {
            Logger.kite.notice("Kite HTTP server already running")
            onCallback = onReceiveRequestToken
            return true
        }

        onCallback = onReceiveRequestToken

        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            guard let listenerPort = NWEndpoint.Port(rawValue: port) else {
                Logger.kite.error("Invalid Kite HTTP server port: \(self.port)")
                onCallback = nil
                return false
            }
            listener = try NWListener(using: parameters, on: listenerPort)
        } catch {
            Logger.kite.error("Failed to start Kite HTTP server: \(error.localizedDescription)")
            onCallback = nil
            return false
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.kite.info("Kite HTTP server ready on \(self?.callbackHost ?? "?"):\(self?.port ?? 0)")
            case .failed(let error):
                Logger.kite.error("Kite HTTP server failed: \(error.localizedDescription)")
                self?.stop()
            case .cancelled:
                Logger.kite.info("Kite HTTP server cancelled")
            default:
                break
            }
        }

        listener.start(queue: .main)
        isRunning = true
        Logger.kite.info("Started Kite HTTP server on \(self.callbackHost):\(self.port)")
        return true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }

        listener?.cancel()
        listener = nil
        isRunning = false
        onCallback = nil
        Logger.kite.info("Kite HTTP server stopped")
    }

    // MARK: - Private

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        let timeout = DispatchWorkItem {
            Logger.kite.warning("Kite connection timeout")
            connection.cancel()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)

        var receivedData = Data()
        let headerTerminator = Data("\r\n\r\n".utf8)
        var didProcessRequest = false

        func readNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
                guard !didProcessRequest else { return }

                timeout.cancel()

                if let error = error {
                    Logger.kite.error("Kite read error: \(error.localizedDescription)")
                    connection.cancel()
                    return
                }

                if let data = data {
                    receivedData.append(data)
                }

                if receivedData.range(of: headerTerminator) != nil {
                    didProcessRequest = true
                    self?.processRequest(receivedData, on: connection)
                } else if isComplete || data == nil || (data?.isEmpty == true) {
                    didProcessRequest = true
                    self?.processRequest(receivedData, on: connection)
                } else {
                    readNext()
                }
            }
        }

        readNext()
    }

    private func processRequest(_ data: Data, on connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(status: 400, body: "Bad Request", on: connection)
            connection.cancel()
            return
        }

        Logger.kite.debug("Received request:\n\(request.prefix(500))")

        // Parse the HTTP request line
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(status: 400, body: "Bad Request", on: connection)
            connection.cancel()
            return
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendResponse(status: 400, body: "Bad Request", on: connection)
            connection.cancel()
            return
        }

        let pathWithQuery = parts[1]

        guard let urlComponents = URLComponents(string: "http://\(callbackHost):\(port)\(pathWithQuery)"),
              urlComponents.path == "/callback" else {
            sendResponse(status: 404, body: "Not Found", on: connection)
            connection.cancel()
            return
        }

        guard let queryItems = urlComponents.queryItems,
              let requestToken = queryItems.first(where: { $0.name == "request_token" })?.value,
              !requestToken.isEmpty else {
            sendResponse(status: 400, body: "Missing request_token", on: connection)
            connection.cancel()
            return
        }

        Logger.kite.info("Received request_token: \(requestToken.prefix(8))...")

        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>Poop — Kite Login</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f5f5f5;color:#333">
        <div style="text-align:center">
        <h1 style="font-size:48px;margin:0">✅</h1>
        <h2>Login Successful</h2>
        <p>You can close this window and return to Poop.</p>
        </div>
        </body>
        </html>
        """

        sendResponse(status: 200, contentType: "text/html; charset=utf-8", body: html, on: connection)

        let callback = onCallback
        DispatchQueue.main.async { [weak self] in
            self?.stop()
            callback?(requestToken)
        }
    }

    private func sendResponse(
        status: Int,
        contentType: String = "text/plain",
        body: String,
        on connection: NWConnection
    ) {
        let statusText: String = {
            switch status {
            case 200: return "OK"
            case 400: return "Bad Request"
            case 404: return "Not Found"
            default: return "Unknown"
            }
        }()

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
