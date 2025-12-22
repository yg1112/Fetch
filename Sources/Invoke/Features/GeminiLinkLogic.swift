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

    // MARK: - Core Flow (Sync)
    func toggleListening() {
        isListening.toggle()
        if isListening {
            print("👂 Listen mode ACTIVATED - monitoring clipboard...")
            lastChangeCount = pasteboard.changeCount
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkClipboard()
            }
            showNotification(title: "Sync Started", body: "Monitoring clipboard for changes")
        } else {
            print("🛑 Listen mode DEACTIVATED")
            timer?.invalidate()
            timer = nil
            showNotification(title: "Sync Stopped", body: "No longer monitoring clipboard")
        }
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
        print("🚀 Starting Git commit & push...")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try GitService.shared.pushChanges(in: self.projectRoot, message: message)
                let commitHash = (try? GitService.shared.run(args: ["rev-parse", "--short", "HEAD"], in: self.projectRoot)) ?? "unknown"
                
                print("✅ Git push successful: \(commitHash)")
                
                DispatchQueue.main.async {
                    let newLog = ChangeLog(commitHash: commitHash, timestamp: Date(), summary: summary)
                    self.changeLogs.insert(newLog, at: 0)
                    self.saveLogs()
                    self.showNotification(title: "Sync Complete", body: summary)
                    NSSound(named: "Glass")?.play()
                }
            } catch {
                print("❌ Git Error: \(error)")
                DispatchQueue.main.async {
                    self.showNotification(title: "Sync Failed", body: error.localizedDescription)
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
    
    func validateCommit(_ log: ChangeLog) {
        DispatchQueue.global().async {
            let diff = try? GitService.shared.run(args: ["show", log.commitHash], in: self.projectRoot)
            
            let prompt = """
            Please VALIDATE this specific commit: \(log.commitHash).
            Here is the `git show` output:
            
            \(diff ?? "Error reading diff")
            
            Task:
            1. Review logic errors.
            2. If CORRECT, reply: "Verified".
            3. If WRONG, output the FIX using the Base64 Protocol.
            """
            
            DispatchQueue.main.async {
                self.pasteboard.clearContents()
                self.pasteboard.setString(prompt, forType: .string)
                
                // 同样触发自动粘贴
                MagicPaster.shared.pasteToBrowser()
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
