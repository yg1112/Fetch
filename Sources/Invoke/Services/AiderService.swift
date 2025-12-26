import Foundation
import Combine

/// Aider Service v3.2 - Stable Pipe & Throttled UI & Full Config Support
@MainActor
class AiderService: ObservableObject {
    static let shared = AiderService()
    
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var isRunning = false
    @Published var currentProject: String = ""
    @Published var initializationStatus: String = "Ready"
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    // UI 节流器
    private let uiThrottler = Throttler(minimumDelay: 0.1)
    private var pendingOutputBuffer = ""
    
    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        let content: String
        let isUser: Bool
        let timestamp = Date()
    }
    
    // MARK: - Aider Process Management
    
    /// 完整的路径查找逻辑 (Config > Shell > Common Paths)
    private func findAiderPath() -> String? {
        // 1. 优先从配置文件读取
        let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.yukungao.fetch")
        let configFile = configDir?.appendingPathComponent("config.json")
        
        if let configFile = configFile,
           let data = try? Data(contentsOf: configFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = json["aiderPath"] as? String,
           FileManager.default.fileExists(atPath: path) {
            return path
        }
        
        // 2. Shell 动态查找
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        whichProcess.arguments = ["-c", "which aider"]
        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()
        
        let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty, FileManager.default.fileExists(atPath: output) {
            return output
        }
        
        // 3. 常见路径回退
        let home = NSHomeDirectory()
        let paths = [
            "/usr/local/bin/aider",
            "/opt/homebrew/bin/aider",
            "\(home)/.local/bin/aider",
            "/usr/bin/aider",
            "\(home)/anaconda3/bin/aider",
            "\(home)/miniconda3/bin/aider"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        
        return nil
    }
    
    func startAider(projectPath: String) {
        stop()
        
        currentProject = projectPath
        initializationStatus = "Starting Local API..."
        
        // 确保 API Server 启动
        LocalAPIServer.shared.start()
        
        guard let aiderPath = findAiderPath() else {
            appendSystemMessage("❌ Aider executable not found. Please install: pip install aider-chat")
            return
        }
        
        initializationStatus = "Launching Aider..."
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aiderPath)
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        
        var env = ProcessInfo.processInfo.environment
        env["AIDER_NO_AUTO_COMMIT"] = "1"
        env["TERM"] = "xterm-256color"
        env["PYTHONIOENCODING"] = "utf-8"
        process.environment = env
        
        // 连接到 Local API
        process.arguments = [
            "--model", "openai/gemini-2.0-flash",
            "--openai-api-base", "http://127.0.0.1:\(LocalAPIServer.shared.port)/v1",
            "--openai-api-key", "sk-dummy-key",
            "--no-git",
            "--yes",
            "--no-show-model-warnings",
            "--dark-mode"
        ]
        
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe() // 分离管道
        
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        self.inputPipe = inPipe
        self.outputPipe = outPipe
        self.errorPipe = errPipe
        
        // Stdout -> Throttled UI
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            if let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.pendingOutputBuffer += str
                    self.uiThrottler.throttle {
                        self.flushOutputBuffer()
                    }
                }
            }
        }
        
        // Stderr -> Log (防止阻塞)
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                // print("[Aider Error] \(str)") // 可选：打印日志
            }
        }
        
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isThinking = false
                self?.initializationStatus = "Stopped"
                self?.appendSystemMessage("Aider process terminated.")
            }
        }
        
        do {
            try process.run()
            self.process = process
            self.isRunning = true
            self.initializationStatus = "Running"
            appendSystemMessage("🚀 Aider connected on \(projectPath)")
        } catch {
            appendSystemMessage("❌ Failed to launch: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Messaging
    
    func sendUserMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        messages.append(ChatMessage(content: text, isUser: true))
        isThinking = true
        
        if let pipe = inputPipe, isRunning {
            let cleanText = text.replacingOccurrences(of: "\n", with: " ")
            if let data = "\(cleanText)\n".data(using: .utf8) {
                try? pipe.fileHandleForWriting.write(contentsOf: data)
            }
        } else {
            appendSystemMessage("⚠️ Aider is not running.")
            isThinking = false
        }
    }
    
    // MARK: - Output Throttling
    
    private func flushOutputBuffer() {
        guard !pendingOutputBuffer.isEmpty else { return }
        let text = pendingOutputBuffer
        pendingOutputBuffer = ""
        
        // 清理 ANSI
        let cleanText = text.replacingOccurrences(
            of: "\\x1B(?:\\[[0-9;]*[mK]?)",
            with: "",
            options: .regularExpression
        )
        
        if cleanText.isEmpty { return }
        
        if cleanText.contains("> ") || cleanText.contains("? ") {
            isThinking = false
        } else {
            isThinking = true
        }
        
        if var lastMsg = messages.last, !lastMsg.isUser {
            let newContent = lastMsg.content + cleanText
            messages[messages.count - 1] = ChatMessage(content: newContent, isUser: false)
        } else {
            messages.append(ChatMessage(content: cleanText, isUser: false))
        }
    }
    
    // MARK: - Lifecycle
    
    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        process?.terminate()
        process = nil
        isRunning = false
        isThinking = false
        
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }
    
    private func appendSystemMessage(_ text: String) {
        messages.append(ChatMessage(content: text, isUser: false))
    }
    
    func clearMessages() {
        messages.removeAll()
    }
}

// 节流器工具类
class Throttler {
    private var workItem: DispatchWorkItem = DispatchWorkItem(block: {})
    private var previousRun: Date = Date.distantPast
    private let queue: DispatchQueue
    private let minimumDelay: TimeInterval

    init(minimumDelay: TimeInterval, queue: DispatchQueue = DispatchQueue.main) {
        self.minimumDelay = minimumDelay
        self.queue = queue
    }

    func throttle(_ block: @escaping () -> Void) {
        workItem.cancel()
        workItem = DispatchWorkItem() { [weak self] in
            self?.previousRun = Date()
            block()
        }
        let delay = previousRun.timeIntervalSinceNow > -minimumDelay ? minimumDelay : 0
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}