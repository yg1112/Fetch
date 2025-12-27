import Foundation
import Network

/// 本地 API Server (Fixed: Immediate Headers for Streaming)
class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()
    
    @Published var isRunning = false
    @Published var port: UInt16 = 3000
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.fetch.api-server")
    
    func start() {
        if isRunning && listener != nil { return }
        for tryPort in UInt16(3000)...UInt16(3010) {
            if startListener(on: tryPort) {
                self.port = tryPort
                self.isRunning = true
                print("✅ API Server on port \(tryPort)")
                return
            }
        }
    }
    
    private func startListener(on port: UInt16) -> Bool {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            newListener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
            newListener.start(queue: queue)
            self.listener = newListener
            return true
        } catch { return false }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let connID = UUID().uuidString.prefix(8)
        print("🔌 [LocalAPIServer] Connection \(connID) opened from \(connection.endpoint)")

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("   ✅ Connection \(connID) ready")
            case .failed(let error):
                print("   ❌ Connection \(connID) failed: \(error)")
            case .cancelled:
                print("   🚫 Connection \(connID) cancelled")
            default:
                break
            }
        }

        connection.start(queue: queue)

        // CRITICAL FIX: Continuously receive requests on this connection (HTTP keep-alive)
        self.receiveLoop(connection, connID: String(connID))
    }

    private func receiveLoop(_ connection: NWConnection, connID: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("   ⚠️ Connection \(connID) receive error: \(error)")
                connection.cancel()
                return
            }

            if let data = data, let req = String(data: data, encoding: .utf8) {
                print("   📥 Connection \(connID) received \(data.count) bytes")
                self?.processRequest(connection, req)

                // CRITICAL: Continue receiving on this connection (keep-alive)
                if !isComplete {
                    self?.receiveLoop(connection, connID: connID)
                } else {
                    print("   🔚 Connection \(connID) closed by client")
                    connection.cancel()
                }
            } else if isComplete {
                print("   🔚 Connection \(connID) closed (no data)")
                connection.cancel()
            } else {
                // Continue receiving
                self?.receiveLoop(connection, connID: connID)
            }
        }
    }
    
    private func processRequest(_ connection: NWConnection, _ rawRequest: String) {
        let lines = rawRequest.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return }
        
        let path = String(parts[1])
        var body = ""
        if let range = rawRequest.range(of: "\r\n\r\n") {
            body = String(rawRequest[range.upperBound...])
        }
        
        if path.contains("/chat/completions") {
            handleChatCompletion(connection, body)
        } else {
            // Keep-alive: don't cancel connection after sending response
            let response = "HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\n"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { error in
                if let error = error {
                    print("   ⚠️ Failed to send health check: \(error)")
                    connection.cancel()
                }
            })
        }
    }
    
    private func handleChatCompletion(_ connection: NWConnection, _ body: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return }
        
        var prompt = ""
        for msg in messages {
            if let content = msg["content"] as? String { prompt = content }
        }
        
        let stream = json["stream"] as? Bool ?? false

        // CRITICAL FIX: Force Task to run on MainActor for WebKit thread safety
        Task { @MainActor in
            print("🔧 [LocalAPIServer] Task started on MainActor for prompt: \(prompt.prefix(30))...")
            do {
                if stream {
                    // 1. 关键修复：立即发送 Header，防止客户端超时
                    let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
                    connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { error in
                        if let error = error {
                            print("❌ Failed to send headers: \(error)")
                            connection.cancel()
                        }
                    })
                }
                
                // 2. 执行耗时操作
                // CRITICAL FIX: Increase timeout to 120s (must be longer than WebView watchdog 90s)
                let responseText = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        return try await GeminiWebManager.shared.askGemini(prompt: prompt, isFromAider: true)
                    }
                    group.addTask {
                        // 120s timeout - allows watchdog (90s) + grace period
                        try await Task.sleep(nanoseconds: 120 * 1_000_000_000)
                        print("⏰ [LocalAPIServer] 120s timeout reached")
                        throw URLError(.timedOut)
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                
                if stream {
                    // 3. 发送实际内容（Header 已发送，只发送数据）
                    sendStreamChunk(connection, text: responseText)
                } else {
                    sendJSON(connection, ["choices": [["message": ["role": "assistant", "content": responseText]]]])
                }
            } catch {
                print("❌ Generation Error: \(error)")
                // 错误情况下也保持 keep-alive（让客户端决定是否重试）
                if !stream {
                    let errResp = "HTTP/1.1 500 Error\r\nConnection: keep-alive\r\n\r\n{\"error\": \"\(error.localizedDescription)\"}"
                    connection.send(content: errResp.data(using: .utf8), completion: .contentProcessed{ error in
                        if let error = error {
                            print("   ⚠️ Failed to send error response: \(error)")
                            connection.cancel()
                        }
                    })
                } else {
                    // Stream 模式下发生错误，发送错误内容
                    let errChunk = "data: {\"choices\":[{\"delta\":{\"content\":\" [Error: \(error.localizedDescription)]\"}}]}\n\ndata: [DONE]\n\n"
                    connection.send(content: errChunk.data(using: .utf8), completion: .contentProcessed{ error in
                        if let error = error {
                            print("   ⚠️ Failed to send error chunk: \(error)")
                            connection.cancel()
                        }
                    })
                }
            }
        }
    }
    
    private func sendJSON(_ connection: NWConnection, _ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        // Keep-alive: add Connection header and don't cancel after sending
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: keep-alive\r\n\r\n\(jsonStr)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { error in
            if let error = error {
                print("   ⚠️ Failed to send JSON response: \(error)")
                connection.cancel()
            }
        })
    }
    
    private func sendStreamChunk(_ connection: NWConnection, text: String) {
        // 注意：这里不再发送 Header，只发送 data
        var chunkData = ""
        let chunk = ["choices": [["delta": ["content": text]]]]
        if let data = try? JSONSerialization.data(withJSONObject: chunk),
           let jsonStr = String(data: data, encoding: .utf8) {
            chunkData += "data: \(jsonStr)\n\n"
        }
        chunkData += "data: [DONE]\n\n"

        // Keep-alive: don't cancel after sending (streaming mode already sent keep-alive header)
        connection.send(content: chunkData.data(using: .utf8), completion: .contentProcessed { error in
            if let error = error {
                print("   ⚠️ Failed to send stream chunk: \(error)")
                connection.cancel()
            }
        })
    }
}