import Foundation
import Network

// ⚡️ LocalAPIServer: The Invisible Pipe
class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()
    
    @Published var isRunning = false
    @Published var port: UInt16 = 3000
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.fetch.api-server")
    
    func start() {
        if isRunning && listener != nil { return }
        
        // 🚀 启动时自动尝试从 Chrome 偷 Cookie (无感登录)
        Task { @MainActor in
            if !GeminiWebManager.shared.isLoggedIn {
                ChromeBridge.shared.fetchCookiesFromChrome { result in
                    if case .success(let cookies) = result {
                        print("🍪 Auto-injected cookies from Chrome/Arc")
                        GeminiWebManager.shared.injectRawCookies(cookies) {
                            GeminiWebManager.shared.loadGemini()
                        }
                    }
                }
            }
        }

        for tryPort in UInt16(3000)...UInt16(3010) {
            if startListener(on: tryPort) {
                self.port = tryPort
                self.isRunning = true
                print("✅ API Server listening on port \(tryPort)")
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
        connection.start(queue: queue)
        receiveLoop(connection)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error { connection.cancel(); return }
            
            if let data = data, let req = String(data: data, encoding: .utf8) {
                self?.processRequest(connection, req)
                if !isComplete { self?.receiveLoop(connection) } // Keep-alive
            } else if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(_ connection: NWConnection, _ rawRequest: String) {
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        
        if firstLine.contains("/chat/completions") {
            // 提取 Body
            var body = ""
            if let range = rawRequest.range(of: "\r\n\r\n") {
                body = String(rawRequest[range.upperBound...])
            }
            handleChatCompletion(connection, body)
        } else {
            // Health check
            let response = "HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\n"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
        }
    }
    
    private func handleChatCompletion(_ connection: NWConnection, _ body: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return }

        // ✅ FIX: 正确拼接所有上下文
        let allContent = messages.compactMap { $0["content"] as? String }.joined(separator: "\n\n")
        
        // ✅ FIX: 注入系统指令，防止上下文漂移
        // 告诉 Gemini：忽略你之前的记忆，这是一次全新的、无状态的请求。
        let systemInstruction = "🔴 [SYSTEM INSTRUCTION: Ignore all previous conversation history in this web session. Treat the following text as a completely NEW request with full context provided.]\n\n"
        
        let robustPrompt = systemInstruction + allContent

        Task { @MainActor in
            print("📡 [Server] Handling Request (Length: \(robustPrompt.count))")
            
            // 1. 立即发送 SSE Header，防止 Aider 超时
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
            connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in })

            do {
                // 2. 流式传输
                try await GeminiWebManager.shared.streamAskGemini(prompt: robustPrompt) { chunk in
                    // OpenAI SSE Format
                    let chunkID = UUID().uuidString.prefix(8)
                    let sseChunk: [String: Any] = [
                        "id": "chatcmpl-\(chunkID)",
                        "object": "chat.completion.chunk",
                        "created": Int(Date().timeIntervalSince1970),
                        "model": "gemini-2.0-flash",
                        "choices": [[
                            "index": 0,
                            "delta": ["content": chunk],
                            "finish_reason": NSNull()
                        ]]
                    ]
                    
                    if let chunkData = try? JSONSerialization.data(withJSONObject: sseChunk),
                       let chunkJSON = String(data: chunkData, encoding: .utf8) {
                        let sseMessage = "data: \(chunkJSON)\n\n"
                        connection.send(content: sseMessage.data(using: .utf8), completion: .contentProcessed { _ in })
                    }
                }
                
                // 3. 结束标记
                let done = "data: [DONE]\n\n"
                connection.send(content: done.data(using: .utf8), completion: .contentProcessed { _ in })
                print("   ✅ Request Completed")
                
            } catch {
                print("   ❌ Error: \(error)")
                let errChunk = "data: {\"choices\":[{\"delta\":{\"content\":\" [Error: \(error.localizedDescription)]\"}}]}\n\ndata: [DONE]\n\n"
                connection.send(content: errChunk.data(using: .utf8), completion: .contentProcessed { _ in })
            }
        }
    }
}