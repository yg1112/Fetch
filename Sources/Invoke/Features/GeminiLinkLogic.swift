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
            if !projectRoot.isEmpty && !isListening {
                startListening()
            }
        }
    }
    
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
    @Published var isProcessing: Bool = false
    @Published var processingStatus: String = ""
    @Published var changeLogs: [ChangeLog] = []
    
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var lastUserClipboard: String = ""
    
    // MARK: - Smart Protocol Markers
    private let fileHeader = ">>> FILE:"
    private let searchStart = "<<<<<<< SEARCH"
    private let divider = "======="
    private let replaceEnd = ">>>>>>> REPLACE"
    private let newFileMarker = "<<<FILE>>>"
    
    init() {
        if !projectRoot.isEmpty { loadLogs() }
    }
    
    // MARK: - File Selection
    func selectProjectRoot() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Root"
            
            NSApp.activate(ignoringOtherApps: true)
            
            if panel.runModal() == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    self.projectRoot = url.path
                    print("📂 Project Root Set: \(self.projectRoot)")
                }
            }
        }
    }

    // MARK: - Listening Logic
    func startListening() {
        guard !isListening else { return }
        isListening = true
        lastChangeCount = pasteboard.changeCount
        
        if let currentContent = pasteboard.string(forType: .string) {
            lastUserClipboard = currentContent
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        guard let content = pasteboard.string(forType: .string) else { return }
        
        if content.contains(fileHeader) && content.contains(searchStart) && content.contains(replaceEnd) {
            print("⚡️ Detected Smart Edit Protocol")
            handleSmartEdit(content)
            return
        }
        
        if content.contains("<<<FILE>>>") && content.contains("<<<END>>>") {
            print("📄 Detected Full File Protocol")
            handleFullOverwrite(content)
            return
        }
        
        if !content.contains("@code") {
            lastUserClipboard = content
        }
    }
    
    // MARK: - Smart Edit Engine (Search & Replace + Fuzzy Match)
    
    private func handleSmartEdit(_ rawText: String) {
        restoreUserClipboardImmediately()
        setStatus("Applying Smart Edits...", isBusy: true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fileBlocks = rawText.components(separatedBy: self.fileHeader)
            var modifiedFiles: [String] = []
            var warningFiles: [String] = []
            
            for block in fileBlocks where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = block.components(separatedBy: .newlines)
                guard let pathLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !pathLine.isEmpty else { continue }
                
                let relativePath = pathLine
                let restOfBlock = lines.dropFirst().joined(separator: "\n")
                
                // 返回 (是否修改了文件, 是否完美匹配)
                let result = self.applyPatches(to: relativePath, patchContent: restOfBlock)
                
                if result.modified {
                    modifiedFiles.append(relativePath)
                }
                if !result.perfect {
                    warningFiles.append(relativePath)
                }
            }
            
            self.finalizeChanges(updatedFiles: modifiedFiles, warningFiles: warningFiles)
        }
    }
    
    /// 核心修复：支持 Partial Commit 和 Fuzzy Matching
    private func applyPatches(to relativePath: String, patchContent: String) -> (modified: Bool, perfect: Bool) {
        let fileURL = URL(fileURLWithPath: projectRoot).appendingPathComponent(relativePath)
        
        guard let fileData = try? Data(contentsOf: fileURL),
              var fileContent = String(data: fileData, encoding: .utf8) else {
            print("❌ File not found: \(relativePath)")
            return (false, false)
        }
        
        let pattern = #"(?s)<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)\n>>>>>>> REPLACE"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(patchContent.startIndex..<patchContent.endIndex, in: patchContent)
        let matches = regex.matches(in: patchContent, range: nsRange)
        
        if matches.isEmpty { return (false, false) }
        
        var modified = false
        var perfect = true
        
        // 倒序应用
        for match in matches.reversed() {
            guard let searchRange = Range(match.range(at: 1), in: patchContent),
                  let replaceRange = Range(match.range(at: 2), in: patchContent) else { continue }
            
            let searchBlock = String(patchContent[searchRange])
            let replaceBlock = String(patchContent[replaceRange])
            
            // 1. 尝试严格匹配
            if let range = fileContent.range(of: searchBlock) {
                fileContent.replaceSubrange(range, with: replaceBlock)
                modified = true
                print("✅ Strict match applied: \(relativePath)")
            } 
            // 2. 尝试模糊匹配 (忽略缩进)
            else if let fuzzyRange = fuzzyMatch(searchBlock: searchBlock, in: fileContent) {
                fileContent.replaceSubrange(fuzzyRange, with: replaceBlock)
                modified = true
                print("⚠️ Fuzzy match applied: \(relativePath)")
            } 
            // 3. 失败
            else {
                print("❌ Block match failed in \(relativePath)")
                print("   Missing:\n\(searchBlock.prefix(100))...")
                perfect = false
            }
        }
        
        if modified {
            do {
                try fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
                print("💾 Saved changes to: \(relativePath)")
            } catch {
                print("❌ Write failed: \(error)")
                return (false, false)
            }
        }
        
        return (modified, perfect)
    }
    
    /// 模糊匹配算法：将 Search Block 转换为允许任意缩进的 Regex
    private func fuzzyMatch(searchBlock: String, in content: String) -> Range<String.Index>? {
        let lines = searchBlock.components(separatedBy: .newlines)
        
        // 构建 Regex：每一行前面允许任意空白 (\s*)，且对原文本进行转义
        let patternParts = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "\\s*" } // 空行匹配任意空白
            return "\\s*" + NSRegularExpression.escapedPattern(for: trimmed)
        }
        
        let regexPattern = patternParts.joined(separator: "\\n")
        return content.range(of: regexPattern, options: .regularExpression)
    }
    
    // MARK: - Full Overwrite Engine
    
    private func handleFullOverwrite(_ rawText: String) {
        restoreUserClipboardImmediately()
        setStatus("Writing Files...", isBusy: true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let pattern = #"(?s)<<<FILE>>>\s+(.*?)\n(.*?)\n<<<END>>>"#
            let regex = try! NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
            let matches = regex.matches(in: rawText, range: nsRange)
            
            var updatedFiles: [String] = []
            
            for match in matches {
                guard let pathRange = Range(match.range(at: 1), in: rawText),
                      let contentRange = Range(match.range(at: 2), in: rawText) else { continue }
                
                let path = String(rawText[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let content = String(rawText[contentRange])
                
                if self.writeFile(path: path, content: content) {
                    updatedFiles.append(path)
                }
            }
            
            self.finalizeChanges(updatedFiles: updatedFiles, warningFiles: [])
        }
    }
    
    private func writeFile(path: String, content: String) -> Bool {
        let url = URL(fileURLWithPath: projectRoot).appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Commit & Finish
    
    private func finalizeChanges(updatedFiles: [String], warningFiles: [String]) {
        DispatchQueue.main.async {
            // 只要有文件更新了，就尝试提交，即使有警告
            if updatedFiles.isEmpty {
                self.setStatus("", isBusy: false)
                self.showNotification(title: "Failed", body: "No changes could be applied.")
                return
            }
            
            // 构造摘要
            let fileList = updatedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            var summary = "Update: \(fileList)"
            
            // 如果有警告，显示出来
            if !warningFiles.isEmpty {
                summary += " (⚠️ Partial)"
                self.showNotification(title: "Completed with Warnings", body: "Check logs for: \(warningFiles.first!)")
            }
            
            self.setStatus("Committing...", isBusy: true)
            self.autoCommitAndPush(message: summary, summary: summary)
        }
    }
    
    private func autoCommitAndPush(message: String, summary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try GitService.shared.commitChanges(in: self.projectRoot, message: message)
                let hash = (try? GitService.shared.run(args: ["rev-parse", "--short", "HEAD"], in: self.projectRoot)) ?? "done"
                
                if self.gitMode == .localOnly {
                    self.finishSuccess(hash: hash, summary: summary, title: "Local Commit")
                    return
                }
                
                if self.gitMode == .yolo {
                    _ = try GitService.shared.pushToRemote(in: self.projectRoot)
                    self.finishSuccess(hash: hash, summary: summary, title: "Pushed to Main")
                } else {
                    let branch = "invoke-\(hash)"
                    try GitService.shared.createBranch(in: self.projectRoot, name: branch)
                    _ = try GitService.shared.pushBranch(in: self.projectRoot, branch: branch)
                    self.finishSuccess(hash: hash, summary: summary, title: "PR Branch Pushed")
                }
            } catch {
                DispatchQueue.main.async {
                    self.setStatus("", isBusy: false)
                    self.showNotification(title: "Git Error", body: error.localizedDescription)
                }
            }
        }
    }
    
    private func finishSuccess(hash: String, summary: String, title: String) {
        DispatchQueue.main.async {
            self.setStatus("", isBusy: false)
            let log = ChangeLog(commitHash: hash, timestamp: Date(), summary: summary)
            self.changeLogs.insert(log, at: 0)
            self.saveLogs()
            self.showNotification(title: title, body: summary)
            NSSound(named: "Glass")?.play()
        }
    }
    
    // MARK: - Helper Methods
    
    func copyGemSetupGuide() {
        let instruction = """
        [System Instruction: Smart Edit Protocol]

        Trigger: When user says "@code" or asks for code changes.

        STRATEGY:
        1. FOR NEW FILES: Use FULL format.
        2. FOR EXISTING FILES: Use SEARCH/REPLACE blocks. DO NOT rewrite the whole file.

        FORMAT 1 - SEARCH & REPLACE (Preferred for edits):
        >>> FILE: <relative_path>
        <<<<<<< SEARCH
        <exact original lines to be replaced>
        =======
        <new lines to insert>
        >>>>>>> REPLACE

        FORMAT 2 - NEW FILE (Only for creation):
        <<<FILE>>> <relative_path>
        <full content>
        <<<END>>>

        RULES:
        - The SEARCH block must match the file content EXACTLY (including whitespace).
        - Include enough context in SEARCH block to be unique.
        - You can have multiple SEARCH/REPLACE blocks for one file.
        """
        
        pasteboard.clearContents()
        pasteboard.setString(instruction, forType: .string)
        showNotification(title: "Setup Copied", body: "Paste this to Gemini System Instructions")
    }
    
    func copyProtocol() {
        pasteboard.clearContents()
        pasteboard.setString("@code", forType: .string)
        showNotification(title: "@code Copied", body: "Paste to Gemini")
    }
    
    func manualApplyFromClipboard() {
        checkClipboard()
    }
    
    func reviewLastChange() {
        guard let lastLog = changeLogs.first else { return }
        DispatchQueue.global().async {
            let diff = try? GitService.shared.run(args: ["show", lastLog.commitHash], in: self.projectRoot)
            let prompt = "Please review this commit diff:\n\n\(diff ?? "")\n\nIf issues found, use the SEARCH/REPLACE format to fix."
            DispatchQueue.main.async {
                self.pasteboard.clearContents()
                self.pasteboard.setString(prompt, forType: .string)
                MagicPaster.shared.pasteToBrowser()
            }
        }
    }
    
    private func restoreUserClipboardImmediately() {
        if !lastUserClipboard.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.pasteboard.clearContents()
                self.pasteboard.setString(self.lastUserClipboard, forType: .string)
                self.lastChangeCount = self.pasteboard.changeCount
            }
        }
    }
    
    private func setStatus(_ text: String, isBusy: Bool) {
        self.processingStatus = text
        self.isProcessing = isBusy
    }
    
    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
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
        try? JSONEncoder().encode(changeLogs).write(to: url)
    }
    
    private func loadLogs() {
        guard let url = getLogFileURL(), let data = try? Data(contentsOf: url) else { changeLogs = []; return }
        changeLogs = (try? JSONDecoder().decode([ChangeLog].self, from: data)) ?? []
    }
}