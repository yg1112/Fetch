import Foundation
import Network

// 定义 Gemini 返回的 JSON 数据结构
struct GeminiChange: Codable {
    let filename: String
    let search_content: String
    let replace_content: String
}

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
                self.port = tryPort; self.isRunning = true
                print("✅ API Server listening on port \(tryPort)")
                return
            }
        }
    }
    
    private func startListener(on port: UInt16) -> Bool {
        do {
            let params = NWParameters.tcp; params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            newListener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
            newListener.start(queue: queue); self.listener = newListener
            return true
        } catch { return false }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue); receiveLoop(connection)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if error != nil { connection.cancel(); return }
            if let data = data, let req = String(data: data, encoding: .utf8) {
                self?.processRequest(connection, req)
                if !isComplete { self?.receiveLoop(connection) }
            } else if isComplete { connection.cancel() }
        }
    }
    
    private func processRequest(_ connection: NWConnection, _ rawRequest: String) {
        let lines = rawRequest.components(separatedBy: "\r\n")
        if lines.first?.contains("/chat/completions") == true {
            var body = ""; if let range = rawRequest.range(of: "\r\n\r\n") { body = String(rawRequest[range.upperBound...]) }
            handleChatCompletion(connection, body)
        } else {
            let response = "HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\n"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
        }
    }
    
    private func handleChatCompletion(_ connection: NWConnection, _ body: String) {
        print("📨 Received Request from Aider...") // Debug log
        
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            print("❌ Failed to parse request body")
            return
        }

        let allContent = messages.compactMap { $0["content"] as? String }.joined(separator: "\n\n")
        
        // Prompt (同上一次，保持不变)
        let systemInstruction = """
        🔴 [SYSTEM ALERT]
        You are a code modification engine.
        You must output your response STRICTLY in a valid JSON array format.
        
        REQUIRED JSON STRUCTURE:
        [
          {
            "filename": "path/to/file.ext",
            "search_content": "exact code lines to be replaced (must match original file exactly)",
            "replace_content": "new code lines to insert"
          }
        ]
        
        RULES:
        1. DO NOT use Markdown code fences (```json). Output RAW JSON only.
        2. DO NOT provide any explanation.
        3. Ensure `search_content` matches the user's file content EXACTLY.
        
        USER REQUEST CONTEXT:
        """
        
        let robustPrompt = systemInstruction + "\n\n" + allContent

        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n"
        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed{_ in})

        Task.detached {
            print("⏳ Asking Gemini (Buffering Mode)...")
            var fullBuffer = ""
            let stream = await GeminiCore.shared.generate(prompt: robustPrompt)
            
            for await chunk in stream {
                fullBuffer += chunk
            }
            
            print("✅ Gemini Response Complete. Length: \(fullBuffer.count)")
            
            // 🔥 关键修复：处理空响应 🔥
            var outputToSend = ""
            if fullBuffer.isEmpty {
                print("⚠️ Warning: Empty buffer received from GeminiCore")
                // 发送一个伪造的错误信息给 Aider，让用户在终端能看到
                outputToSend = "⚠️ FETCH ERROR: Gemini returned NO content. Please check the 'Show Brain' window in Fetch App to ensure you are logged in."
            } else {
                // 正常转换
                outputToSend = self.convertJsonToAiderBlock(fullBuffer)
            }
            
            let responseJson = ["choices": [["delta": ["content": outputToSend]]]]
            if let data = try? JSONEncoder().encode(responseJson),
               let str = String(data: data, encoding: .utf8) {
                let sse = "data: \(str)\n\n"
                connection.send(content: sse.data(using: .utf8), completion: .contentProcessed{_ in})
            }
            
            connection.send(content: "data: [DONE]\n\n".data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    private func convertJsonToAiderBlock(_ rawInput: String) -> String {
        let cleanInput = rawInput
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanInput.data(using: .utf8) else { return rawInput }
        
        do {
            let changes = try JSONDecoder().decode([GeminiChange].self, from: data)
            if changes.isEmpty { return "Request processed. No code changes needed." }
            
            var output = ""
            for change in changes {
                output += "\(change.filename)\n"
                output += "<<<<<<< SEARCH\n"
                output += change.search_content + "\n"
                output += "=======\n"
                output += change.replace_content + "\n"
                output += ">>>>>>> Replace\n\n"
            }
            return output
        } catch {
            print("⚠️ JSON Parse Failed, returning raw text. Input was: \(cleanInput.prefix(50))...")
            return rawInput
        }
    }
}