import SwiftUI
import Combine
import AppKit

// MARK: - Data Models
struct ChangeLog: Identifiable, Codable {
    var id: String { commitHash }
    let commitHash: String
    let timestamp: Date
    let summary: String
    var isValidated: Bool = false
}

class GeminiLinkLogic: ObservableObject {
    // MARK: - Settings
    @Published var projectRoot: String = UserDefaults.standard.string(forKey: "ProjectRoot") ?? "" {
        didSet {
            UserDefaults.standard.set(projectRoot, forKey: "ProjectRoot")
            loadLogs()
            // 选择项目后自动开启监听
            if !projectRoot.isEmpty && !isListening {
                startListening()
            }
        }
    }
    
    // Git 模式：Local Only / Safe (PR) / YOLO (Direct Push)
    enum GitMode: String, CaseIterable {
        case localOnly = "Local Only"
        case safe = "Safe"
        case yolo = "YOLO"
        
        var description: String {
            switch self {
            case .localOnly: return "Local commits only"
            case .safe: return "Create PR"
            case .yolo: return "Direct Push"
            }
        }
    }
    
    @Published var gitMode: GitMode = GitMode(rawValue: UserDefaults.standard.string(forKey: "GitMode") ?? "yolo") ?? .yolo {
        didSet {
            UserDefaults.standard.set(gitMode.rawValue, forKey: "GitMode")
        }
    }
    
    @Published var isListening: Bool = false
    
    // MARK: - Data Source
    @Published var changeLogs: [ChangeLog] = []
    
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    
    // Protocol Markers
    private let markerStart = "!!!B64_START!!!"
    private let markerEnd = "!!!B64_END!!!"
    
    init() {
        if !projectRoot.isEmpty { loadLogs() }
    }
    
    // MARK: - File Selection (Fixed & Async)
    func selectProjectRoot() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Root"
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            
            NSApp.activate(ignoringOtherApps: true)
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    DispatchQueue.main.async {
                        self.projectRoot = url.path
                        print("📂 Project Root Set: \(self.projectRoot)")
                    }
                }
            }
        }
    }

    // MARK: - Core Flow (自动监听)
    
    /// 启动自动监听（选择项目后自动调用）
    func startListening() {
        guard !isListening else { return }
        isListening = true
        print("👂 Auto-listening ACTIVATED - monitoring clipboard...")
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        showNotification(title: "Ready", body: "Monitoring clipboard for Gemini code")
    }
    
    /// 停止监听（一般不需要手动调用）
    func stopListening() {
        guard isListening else { return }
        isListening = false
        print("🛑 Listen mode STOPPED")
        timer?.invalidate()
        timer = nil
    }
    
    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        guard let content = pasteboard.string(forType: .string) else { return }
        
        // 检测到剪贴板变化
        if content.contains(markerStart) {
            print("🔍 Detected Base64 protocol in clipboard!")
            showNotification(title: "Code Detected", body: "Processing changes...")
            processClipboardContent(content)
        }
    }
    
    private func processClipboardContent(_ rawText: String) {
        let pattern = try! NSRegularExpression(
            pattern: "\(NSRegularExpression.escapedPattern(for: markerStart))\\s+(.*?)\\s+(.*?)\\s+\(NSRegularExpression.escapedPattern(for: markerEnd))",
            options: .dotMatchesLineSeparators
        )
        let matches = pattern.matches(in: rawText, options: [], range: NSRange(rawText.startIndex..<rawText.endIndex, in: rawText))
        
        if matches.isEmpty {
            print("⚠️ No valid Base64 blocks found in clipboard")
            return
        }
        
        print("✅ Found \(matches.count) file(s) to update")
        var updatedFiles: [String] = []
        
        for match in matches {
            if let pathRange = Range(match.range(at: 1), in: rawText),
               let contentRange = Range(match.range(at: 2), in: rawText) {
                let relPath = String(rawText[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let b64Content = String(rawText[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if writeToFile(relativePath: relPath, base64Content: b64Content) {
                    updatedFiles.append(relPath)
                }
            }
        }
        
        if !updatedFiles.isEmpty {
            let summary = "Update: \(updatedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))"
            autoCommitAndPush(message: summary, summary: summary)
        }
    }
    
    private func writeToFile(relativePath: String, base64Content: String) -> Bool {
        guard let data = Data(base64Encoded: base64Content) else {
            print("❌ Invalid Base64 for: \(relativePath)")
            return false
        }
        let fullURL = URL(fileURLWithPath: projectRoot).appendingPathComponent(relativePath)
        do {
            try FileManager.default.createDirectory(at: fullURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fullURL)
            print("✅ Wrote: \(relativePath)")
            return true
        } catch {
            print("❌ Write error: \(error)")
            return false
        }
    }
    
    private func autoCommitAndPush(message: String, summary: String) {
        print("🚀 Starting Git operation (\(gitMode.rawValue) mode)...")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 1. Commit 本地改动
                _ = try GitService.shared.commitChanges(in: self.projectRoot, message: message)
                let commitHash = (try? GitService.shared.run(args: ["rev-parse", "--short", "HEAD"], in: self.projectRoot)) ?? "unknown"
                
                // 2. Local Only 模式：只提交不推送
                if self.gitMode == .localOnly {
                    print("✅ Local commit completed: \(commitHash)")
                    DispatchQueue.main.async {
                        let newLog = ChangeLog(commitHash: commitHash, timestamp: Date(), summary: summary)
                        self.changeLogs.insert(newLog, at: 0)
                        self.saveLogs()
                        self.showNotification(title: "Local Commit", body: summary)
                        NSSound(named: "Glass")?.play()
                    }
                    return
                }
                
                // 3. 根据模式执行推送操作
                if self.gitMode == .yolo {
                    // YOLO 模式：直接 push
                    _ = try GitService.shared.pushToRemote(in: self.projectRoot)
                    print("✅ Git push successful: \(commitHash)")
                    
                    DispatchQueue.main.async {
                        let newLog = ChangeLog(commitHash: commitHash, timestamp: Date(), summary: summary)
                        self.changeLogs.insert(newLog, at: 0)
                        self.saveLogs()
                        self.showNotification(title: "Pushed", body: summary)
                        NSSound(named: "Glass")?.play()
                    }
                } else {
                    // Safe 模式：创建 PR
                    let branchName = "invoke-\(commitHash)"
                    try GitService.shared.createBranch(in: self.projectRoot, name: branchName)
                    _ = try GitService.shared.pushBranch(in: self.projectRoot, branch: branchName)
                    
                    print("✅ Branch created and pushed: \(branchName)")
                    
                    DispatchQueue.main.async {
                        let newLog = ChangeLog(commitHash: commitHash, timestamp: Date(), summary: summary)
                        self.changeLogs.insert(newLog, at: 0)
                        self.saveLogs()
                        self.showNotification(title: "PR Ready", body: "Branch: \(branchName)")
                        NSSound(named: "Glass")?.play()
                    }
                }
            } catch {
                print("❌ Git Error: \(error)")
                DispatchQueue.main.async {
                    self.showNotification(title: "Git Failed", body: error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Protocol & Validation (The Brain)
    
    func copyProtocol() {
        print("🔗 Pair button clicked - preparing protocol...")
        
        // 1. 生成真实的项目结构 (Real Context Injection)
        let structure = scanProjectStructure()
        print("📂 Project structure scanned: \(structure.split(separator: "\n").count) lines")
        
        let prompt = """
        You are my Senior AI Pair Programmer.
        Current Project Context:
        \(structure)

        【PROTOCOL - STRICTLY ENFORCE】:
        1. When I ask for changes, DO NOT explain.
        2. Output only the CHANGED files using this Base64 format:
        
        ```text
        \(markerStart) <relative_path>
        <base64_string_of_full_file_content>
        \(markerEnd)
        ```
        
        3. If multiple files change, output multiple blocks sequentially.
        4. I will auto-apply these changes.
        
        Ready? Await my instructions.
        """
        
        // 2. 写入剪贴板
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        print("📋 Prompt copied to clipboard (\(prompt.count) chars)")
        
        // 3. ✨ 触发魔法粘贴 (Magic Paste)
        // 检查辅助功能权限
        let hasPermission = AXIsProcessTrusted()
        if hasPermission {
            print("🎯 Calling MagicPaster...")
            MagicPaster.shared.pasteToBrowser()
        } else {
            print("⚠️ Accessibility permission not granted! Cannot auto-paste.")
            print("   User needs to manually paste (Cmd+V) in browser")
            showNotification(title: "Manual Paste Required", body: "Press Cmd+V in Gemini to paste the protocol")
        }
    }
    
    /// Review 最后一次改动（点击 Review 按钮）
    func reviewLastChange() {
        guard let lastLog = changeLogs.first else {
            print("⚠️ No commits to review")
            showNotification(title: "Nothing to Review", body: "No recent changes")
            return
        }
        
        print("🔍 Reviewing commit: \(lastLog.commitHash)")
        
        DispatchQueue.global().async {
            let diff = try? GitService.shared.run(args: ["show", lastLog.commitHash], in: self.projectRoot)
            
            let prompt = """
            Please REVIEW this commit I just made:
            
            **Commit:** \(lastLog.commitHash)
            **Summary:** \(lastLog.summary)
            
            **Changes:**
            ```
            \(diff ?? "Error reading diff")
            ```
            
            **Task:**
            1. Analyze if the changes are correct and complete.
            2. If CORRECT, reply: "✅ Verified - changes look good!"
            3. If there are ISSUES, provide the FIX using the Base64 Protocol:
            
            ```text
            \(self.markerStart) <relative_path>
            <base64_string_of_full_file_content>
            \(self.markerEnd)
            ```
            
            Ready to review?
            """
            
            DispatchQueue.main.async {
                self.pasteboard.clearContents()
                self.pasteboard.setString(prompt, forType: .string)
                
                // 检查权限并粘贴
                let hasPermission = AXIsProcessTrusted()
                if hasPermission {
                    print("🎯 Auto-pasting review request...")
                    MagicPaster.shared.pasteToBrowser()
                } else {
                    print("⚠️ Manual paste required")
                    self.showNotification(title: "Review Request Ready", body: "Press Cmd+V in Gemini")
                }
            }
        }
    }
    
    func toggleValidationStatus(for id: String) {
        if let index = changeLogs.firstIndex(where: { $0.id == id }) {
            changeLogs[index].isValidated.toggle()
            saveLogs()
        }
    }
    
    // MARK: - Helper: File Scanner
    private func scanProjectStructure() -> String {
        guard !projectRoot.isEmpty else { return "(No project selected)" }
        let rootURL = URL(fileURLWithPath: projectRoot)
        var output = ""
        
        let fileManager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        
        // 使用 Enumerator 进行递归扫描
        if let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: options) {
            for case let fileURL as URL in enumerator {
                let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                
                // 🛡️ 智能过滤 (Smart Filter) - 关键！
                // 忽略垃圾文件，防止 Context 爆炸
                if relativePath.contains("node_modules") ||
                   relativePath.contains(".git") ||
                   relativePath.contains("build") ||
                   relativePath.contains(".DS_Store") ||
                   relativePath.hasSuffix(".lock") {
                    enumerator.skipDescendants() // 跳过该目录的内容
                    continue
                }
                
                output += "- \(relativePath)\n"
                
                // 简单限制一下长度，防止超大项目卡死
                if output.count > 10000 {
                    output += "... (truncated)\n"
                    break
                }
            }
        }
        return output.isEmpty ? "(Empty Project)" : output
    }
    
    // MARK: - Notification Helper
    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = nil // 已经有 Glass 音效了
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // MARK: - Persistence
    private func getLogFileURL() -> URL? {
        guard !projectRoot.isEmpty else { return nil }
        let projectName = URL(fileURLWithPath: projectRoot).lastPathComponent
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".invoke_logs")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(projectName).json")
    }
    
    private func saveLogs() {
        guard let url = getLogFileURL() else { return }
        if let data = try? JSONEncoder().encode(changeLogs) {
            try? data.write(to: url)
        }
    }
    
    private func loadLogs() {
        guard let url = getLogFileURL(),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([ChangeLog].self, from: data) else {
            changeLogs = []
            return
        }
        changeLogs = loaded
    }
}
