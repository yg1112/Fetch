import Foundation
import Network

/// 本地 OpenAI 兼容 API 服务器
/// Aider CLI -> localhost:3000 -> Fetch -> Gemini WebView
class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()
    
    @Published var isRunning = false
    @Published var port: UInt16 = 3000
    @Published var requestCount = 0
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.fetch.api-server", qos: .userInitiated)
    
    // MARK: - Start/Stop
    
    func start() {
        guard !isRunning else { return }
        
        // 尝试端口 3000-3010
        for tryPort in UInt16(3000)...UInt16(3010) {
            if tryStart(on: tryPort) {
                DispatchQueue.main.async {
                    self.port = tryPort
                    self.isRunning = true
                }
                print("🌐 API Server started on http://127.0.0.1:\(tryPort)")
                return
            }
        }
        
        print("❌ Failed to start API server on any port")
    }
    
    private func tryStart(on port: UInt16) -> Bool {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("✅ Listener ready on port \(port)")
                case .failed(let error):
                    print("❌ Listener failed: \(error)")
                    self?.stop()
                case .cancelled:
                    print("🛑 Listener cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
            return true
            
        } catch {
            print("⚠️ Port \(port) unavailable: \(error)")
            return false
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
        print("🛑 API Server stopped")
    }
    
    // MARK: - Connection Handling
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receiveHTTP(connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
    
    private func receiveHTTP(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            
            guard let request = String(data: data, encoding: .utf8) else {
                self.sendError(connection, status: 400, message: "Invalid request")
                return
            }
            
            // 解析 HTTP 请求
            self.routeRequest(connection, rawRequest: request)
            
            if !isComplete {
                self.receiveHTTP(connection)
            }
        }
    }
    
    // MARK: - HTTP Routing
    
    private func routeRequest(_ connection: NWConnection, rawRequest: String) {
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(connection, status: 400, message: "Empty request")
            return
        }
        
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendError(connection, status: 400, message: "Malformed request line")
            return
        }
        
        let method = String(parts[0])
        let path = String(parts[1])
        
        // 提取 Body (在空行之后)
        var body = ""
        if let emptyLineIndex = rawRequest.range(of: "\r\n\r\n") {
            body = String(rawRequest[emptyLineIndex.upperBound...])
        }
        
        print("📨 \(method) \(path)")
        
        // 路由
        switch (method, path) {
        case ("GET", "/"):
            sendJSON(connection, ["status": "Fetch API Server", "version": "2.0"])
            
        case ("GET", "/v1/models"):
            handleListModels(connection)
            
        case ("POST", "/v1/chat/completions"):
            handleChatCompletions(connection, body: body)
            
        case ("OPTIONS", _):
            // CORS preflight
            sendCORS(connection)
            
        default:
            sendError(connection, status: 404, message: "Not Found: \(path)")
        }
    }
    
    // MARK: - API Handlers
    
    private func handleListModels(_ connection: NWConnection) {
        let models: [[String: Any]] = [
            ["id": "gemini-2.0-flash", "object": "model", "owned_by": "google"],
            ["id": "gemini-1.5-pro", "object": "model", "owned_by": "google"],
            ["id": "gemini-2.0-flash-thinking", "object": "model", "owned_by": "google"]
        ]
        sendJSON(connection, ["object": "list", "data": models])
    }
    
    private func handleChatCompletions(_ connection: NWConnection, body: String) {
        DispatchQueue.main.async {
            self.requestCount += 1
        }
        
        // 解析请求体
        guard let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            sendError(connection, status: 400, message: "Invalid JSON body")
            return
        }
        
        let model = json["model"] as? String ?? "gemini-2.0-flash"
        let stream = json["stream"] as? Bool ?? false
        
        // 提取最后一条用户消息
        var prompt = ""
        for msg in messages {
            if let role = msg["role"] as? String,
               let content = msg["content"] as? String {
                if role == "user" {
                    prompt = content
                } else if role == "system" {
                    prompt = content + "\n\n" + prompt
                }
            }
        }
        
        print("🧠 Prompt: \(prompt.prefix(100))...")
        
        // 调用 Gemini
        Task {
            do {
                let response = try await GeminiWebManager.shared.askGemini(prompt: prompt)
                
                print("🟢 [API Debug] Sending response to Aider. Length: \(response.count)")
                
                if stream {
                    self.sendStreamResponse(connection, content: response, model: model)
                } else {
                    self.sendChatResponse(connection, content: response, model: model)
                }
            } catch {
                self.sendError(connection, status: 500, message: "Gemini error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Response Helpers
    
    private func sendChatResponse(_ connection: NWConnection, content: String, model: String) {
        let response: [String: Any] = [
            "id": "chatcmpl-\(UUID().uuidString.prefix(8))",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": content
                    ],
                    "finish_reason": "stop"
                ]
            ],
            "usage": [
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0
            ]
        ]
        
        sendJSON(connection, response)
    }
    
    private func sendStreamResponse(_ connection: NWConnection, content: String, model: String) {
        // SSE 格式
        var sseData = ""
        
        // 分块发送
        let chunks = content.split(separator: " ").map(String.init)
        for (i, chunk) in chunks.enumerated() {
            let delta: [String: Any] = [
                "id": "chatcmpl-\(UUID().uuidString.prefix(8))",
                "object": "chat.completion.chunk",
                "created": Int(Date().timeIntervalSince1970),
                "model": model,
                "choices": [
                    [
                        "index": 0,
                        "delta": ["content": chunk + (i < chunks.count - 1 ? " " : "")],
                        "finish_reason": NSNull()
                    ]
                ]
            ]
            
            if let json = try? JSONSerialization.data(withJSONObject: delta),
               let jsonStr = String(data: json, encoding: .utf8) {
                sseData += "data: \(jsonStr)\n\n"
            }
        }
        
        // 结束标记
        sseData += "data: [DONE]\n\n"
        
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r
        
        """
        
        let responseData = (headers + sseData).data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendJSON(_ connection: NWConnection, _ dict: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            sendError(connection, status: 500, message: "JSON encoding failed")
            return
        }
        
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization\r
        Connection: close\r
        \r
        \(jsonString)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendError(_ connection: NWConnection, status: Int, message: String) {
        let statusText: String
        switch status {
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Error"
        }
        
        let errorBody = """
        {"error": {"message": "\(message)", "type": "api_error", "code": \(status)}}
        """
        
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(errorBody.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(errorBody)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendCORS(_ connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization\r
        Access-Control-Max-Age: 86400\r
        Connection: close\r
        \r
        
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

