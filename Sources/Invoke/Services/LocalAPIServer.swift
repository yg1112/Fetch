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
        
        // Prompt - 升级版（防止查询类问题报错）
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
        4. If no changes are needed, return an empty array: []

        USER REQUEST CONTEXT:
        """
        
        let robustPrompt = systemInstruction + "\n\n" + allContent

        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n"
        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed{_ in})

        Task.detached {
            print("⏳ Asking Gemini (Streaming Mode)...")

            // 流式状态反馈：发送初始思考状态
            self.sendSSEChunk(connection, content: "🧠 Analyzing request...")

            var fullBuffer = ""
            var lastHeartbeat = Date()
            let stream = await GeminiCore.shared.generate(prompt: robustPrompt)

            // 心跳任务：每 2 秒发送一个微小的进度更新
            let heartbeatTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 秒
                    let elapsed = Date().timeIntervalSince(lastHeartbeat)
                    if elapsed > 2 {
                        self.sendSSEChunk(connection, content: ".")
                    }
                }
            }

            // 流式收集响应
            for await chunk in stream {
                fullBuffer += chunk
                lastHeartbeat = Date()
            }

            heartbeatTask.cancel()

            print("✅ Gemini Response Complete. Length: \(fullBuffer.count)")

            // 🔥 关键修复：处理空响应 🔥
            var outputToSend = ""
            if fullBuffer.isEmpty {
                print("⚠️ Warning: Empty buffer received from GeminiCore")
                outputToSend = "⚠️ FETCH ERROR: Gemini returned NO content. Please check the 'Show Brain' window in Fetch App to ensure you are logged in."
            } else {
                // 正常转换
                outputToSend = self.convertJsonToAiderBlock(fullBuffer)
            }

            // 发送最终结果
            self.sendSSEChunk(connection, content: outputToSend)

            connection.send(content: "data: [DONE]\n\n".data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    // SSE 发送辅助方法
    private func sendSSEChunk(_ connection: NWConnection, content: String) {
        let responseJson = ["choices": [["delta": ["content": content]]]]
        if let data = try? JSONEncoder().encode(responseJson),
           let str = String(data: data, encoding: .utf8) {
            let sse = "data: \(str)\n\n"
            connection.send(content: sse.data(using: .utf8), completion: .contentProcessed{_ in})
        }
    }

    // 双模解析器：JSON + 启发式解析
    private func convertJsonToAiderBlock(_ rawInput: String) -> String {
        // 模式 1: 尝试 JSON 解析
        if let result = tryJsonParse(rawInput) {
            return result
        }

        // 模式 2: 启发式解析（从废话中提取代码块）
        print("⚙️ JSON parsing failed, trying heuristic parsing...")
        if let result = tryHeuristicParse(rawInput) {
            return result
        }

        // 模式 3: 完全失败，返回原始文本（至少 Aider 能看到）
        print("⚠️ All parsing failed, returning raw text")
        return rawInput
    }

    // JSON 解析器
    private func tryJsonParse(_ rawInput: String) -> String? {
        // 1. 清理 Markdown 围栏和前后废话
        var cleanInput = rawInput
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. 尝试提取 JSON 数组（处理前后有废话的情况）
        if let jsonStart = cleanInput.firstIndex(of: "["),
           let jsonEnd = cleanInput.lastIndex(of: "]") {
            cleanInput = String(cleanInput[jsonStart...jsonEnd])
        }

        guard let data = cleanInput.data(using: .utf8) else { return nil }

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
            print("⚠️ JSON parse error: \(error)")
            return nil
        }
    }

    // 启发式解析器：从自然语言中提取代码修改
    private func tryHeuristicParse(_ rawInput: String) -> String? {
        var results: [String] = []

        // 策略 1: 查找 "filename:" 或 "file:" 模式
        let lines = rawInput.components(separatedBy: .newlines)
        var currentFile: String?
        var searchBlock = ""
        var replaceBlock = ""
        var inSearchBlock = false
        var inReplaceBlock = false

        for line in lines {
            // 检测文件名
            if line.lowercased().contains("filename:") || line.lowercased().contains("file:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    currentFile = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "'", with: "")
                }
            }

            // 检测 SEARCH 块开始
            if line.contains("<<<<<<< SEARCH") || line.lowercased().contains("search_content") {
                inSearchBlock = true
                inReplaceBlock = false
                searchBlock = ""
                continue
            }

            // 检测 REPLACE 块开始
            if line.contains("=======") || line.lowercased().contains("replace_content") {
                inSearchBlock = false
                inReplaceBlock = true
                replaceBlock = ""
                continue
            }

            // 检测块结束
            if line.contains(">>>>>>> Replace") {
                if let file = currentFile, !searchBlock.isEmpty, !replaceBlock.isEmpty {
                    let block = "\(file)\n<<<<<<< SEARCH\n\(searchBlock)\n=======\n\(replaceBlock)\n>>>>>>> Replace\n"
                    results.append(block)
                }
                inSearchBlock = false
                inReplaceBlock = false
                searchBlock = ""
                replaceBlock = ""
                continue
            }

            // 收集内容
            if inSearchBlock {
                searchBlock += line + "\n"
            } else if inReplaceBlock {
                replaceBlock += line + "\n"
            }
        }

        if results.isEmpty {
            return nil
        }

        print("✅ Heuristic parser extracted \(results.count) change(s)")
        return results.joined(separator: "\n")
    }
}