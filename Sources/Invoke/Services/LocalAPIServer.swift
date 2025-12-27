import Foundation
import Network

class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()
    
    @Published var isRunning = false
    @Published var port: UInt16 = 3000
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.fetch.api-server")
    
    func start() {
        if isRunning && listener != nil { return }
        // Removed auto-inject logic for better UX
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
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return }

        // 🔥 FIX 1: 拼接所有上下文 (修复 Context 被覆盖的 Bug)
        let allContent = messages.compactMap { $0["content"] as? String }.joined(separator: "\n\n")
        
        // 🔥 FIX 2: 系统指令 (防漂移)
        let systemInstruction = "🔴 [SYSTEM: Ignore previous history. Treat this as a NEW request.]\n\n"
        let robustPrompt = systemInstruction + allContent

        // 1. 抢先发送 Header (Latency Optimization)
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n"
        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed{_ in})

        Task.detached {
            // 2. 调用 
            let stream = await GeminiCore.shared.generate(prompt: robustPrompt)
            
            for await chunk in stream {
                // 3. 构建 OpenAI 格式的数据包
                let json = ["choices": [["delta": ["content": chunk]]]]
                if let data = try? JSONEncoder().encode(json),
                   let str = String(data: data, encoding: .utf8) {
                    let sse = "data: \(str)\n\n"
                    connection.send(content: sse.data(using: .utf8), completion: .contentProcessed{_ in})
                }
            }
            
            // 4. 发送结束信号
            connection.send(content: "data: [DONE]\n\n".data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}