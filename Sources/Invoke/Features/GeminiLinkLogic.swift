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
            if !projectRoot.isEmpty { startListening() }
        }
    }
    
    // 🔥 模式定义
    enum GitMode: String, CaseIterable {
        case localOnly = "Local Only"
        case safe = "Safe"
        case yolo = "YOLO"
        
        var title: String {
            switch self {
            case .localOnly: return "Local Only"
            case .safe: return "PR Review"
            case .yolo: return "Auto Push"
            }
        }
        var icon: String {
            switch self {
            case .localOnly: return "lock.shield"
            case .safe: return "arrow.triangle.branch"
            case .yolo: return "bolt.fill"
            }
        }
        var description: String {
            switch self {
            case .localOnly: return "Private. Commit locally, no push."
            case .safe: return "Collaborate. Push branch & create PR."
            case .yolo: return "Fast. Directly push to main branch."
            }
        }
    }
    
    @Published var gitMode: GitMode = GitMode(rawValue: UserDefaults.standard.string(forKey: "GitMode") ?? "yolo") ?? .yolo {
        didSet { UserDefaults.standard.set(gitMode.rawValue, forKey: "GitMode") }
    }
    
    @Published var isListening: Bool = false
    @Published var isProcessing: Bool = false
    @Published var processingStatus: String = ""
    @Published var changeLogs: [ChangeLog] = []
    
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var lastUserClipboard: String = ""
    
    // MARK: - Smart Protocol Markers (Safety Lock Added)
    // 🔒 核心安全锁：只有以这个开头的剪贴板内容才会被处理
    private let magicHeader = ">>> INVOKE"
    
    private let fileHeader = ">>> FILE:"
    private let searchStart = "<<<<<<< SEARCH"
    private let replaceEnd = ">>>>>>> REPLACE"
    private let newFileStart = "<<<FILE>>>"
    private let newFileEnd = "<<<END>>>"
    
    init() {
        if !projectRoot.isEmpty {
            loadLogs()
            startListening()
        }
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
        if isListening && timer != nil { return }
        isListening = true
        lastChangeCount = pasteboard.changeCount
        
        if let currentContent = pasteboard.string(forType: .string) {
            lastUserClipboard = currentContent
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        print("👂 Listening service started (Safety Lock: ON)...")
    }
    
    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        guard let content = pasteboard.string(forType: .string) else { return }
        
        // 🛑 安全检查：如果不包含魔法头，直接忽略！
        // 这意味着你复制任何其他代码、聊天记录，Fetch 都会无视，体验大大提升。
        guard content.contains(magicHeader) else {
            // 只是记录一下，不做任何反应
            if !content.contains("@code") {
                lastUserClipboard = content
            }
            return
        }
        
        // 只有包含 >>> INVOKE 才会走到这里
        let hasSmartEdit = content.contains(searchStart)
        let hasNewFile = content.contains(newFileStart)
        
        if hasSmartEdit || hasNewFile {
            print("⚡️ Detected Protocol Content (Verified)")
            processAllChanges(content)
        }
    }
    
    // MARK: - Processing Logic
    private func processAllChanges(_ rawText: String) {
        restoreUserClipboardImmediately()
        setStatus("Processing...", isBusy: true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let normalizedText = rawText.replacingOccurrences(of: "\r\n", with: "\n")
            var modifiedFiles: Set<String> = []
            var warningFiles: [String] = []
            
            // 1. Full Overwrite
            let fullFiles = self.parseFullOverwrite(normalizedText)
            for file in fullFiles {
                if self.writeFile(path: file.path, content: file.content) {
                    modifiedFiles.insert(file.path)
                }
            }
            
            // 2. Smart Edit
            let smartEdits = self.parseSmartEdits(normalizedText)
            for edit in smartEdits {
                let result = self.applyPatches(to: edit.path, patchContent: edit.content)
                if result.modified {
                    modifiedFiles.insert(edit.path)
                }
                if !result.perfect {
                    warningFiles.append(edit.path)
                }
            }
            
            self.finalizeChanges(updatedFiles: Array(modifiedFiles), warningFiles: warningFiles)
        }
    }
    
    // MARK: - Parsers
    private struct FilePayload { let path: String; let content: String }
    
    private func parseFullOverwrite(_ text: String) -> [FilePayload] {
        let pattern = #"(?s)<<<FILE>>>\s*([^\n]+)\n(.*?)\n<<<END>>>"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        
        return matches.compactMap { match -> FilePayload? in
            guard let pathRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 2), in: text) else { return nil }
            
            let path = String(text[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            var content = String(text[contentRange])
            
            if content.hasPrefix("```") {
                content = content.replacingOccurrences(of: "^```\\w*\\n", with: "", options: .regularExpression)
                content = content.replacingOccurrences(of: "\n```$", with: "", options: .regularExpression)
            }
            
            return FilePayload(path: path, content: content)
        }
    }
    
    private func parseSmartEdits(_ text: String) -> [FilePayload] {
        let blocks = text.components(separatedBy: ">>> FILE")
        return blocks.compactMap { block -> FilePayload? in
            guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            
            let lines = block.components(separatedBy: .newlines)
            var firstLine = lines.first ?? ""
            if firstLine.hasPrefix(":") { firstLine.removeFirst() }
            
            let path = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !path.contains("<<<") else { return nil }
            
            let content = lines.dropFirst().joined(separator: "\n")
            guard content.contains(searchStart) else { return nil }
            
            return FilePayload(path: path, content: content)
        }
    }
    
    // MARK: - Patch Engine (Logic Skeleton Match)
    private func applyPatches(to relativePath: String, patchContent: String) -> (modified: Bool, perfect: Bool) {
        let fileURL = URL(fileURLWithPath: projectRoot).appendingPathComponent(relativePath)
        
        guard let fileData = try? Data(contentsOf: fileURL),
              var fileContent = String(data: fileData, encoding: .utf8) else {
            print("❌ File not found: \(relativePath)")
            return (false, false)
        }
        
        let pattern = #"(?s)<<<<<<< SEARCH\s*\n(.*?)\n=======\s*\n(.*?)\n>>>>>>> REPLACE"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: patchContent, range: NSRange(patchContent.startIndex..<patchContent.endIndex, in: patchContent))
        
        if matches.isEmpty { return (false, false) }
        
        var modified = false
        var perfect = true
        
        for match in matches.reversed() {
            guard let searchRange = Range(match.range(at: 1), in: patchContent),
                  let replaceRange = Range(match.range(at: 2), in: patchContent) else { continue }
            
            var searchBlock = String(patchContent[searchRange])
            let replaceBlock = String(patchContent[replaceRange])
            
            if searchBlock.hasPrefix("```") {
                searchBlock = searchBlock.replacingOccurrences(of: "```\\w*\\n", with: "", options: .regularExpression)
                searchBlock = searchBlock.replacingOccurrences(of: "```", with: "")
            }
            
            // Level 1: Exact
            if let range = fileContent.range(of: searchBlock) {
                fileContent.replaceSubrange(range, with: replaceBlock)
                modified = true
                continue
            }
            
            // Level 2: Fuzzy Line
            if let fuzzyRange = fuzzyMatchLines(searchBlock: searchBlock, in: fileContent) {
                fileContent.replaceSubrange(fuzzyRange, with: replaceBlock)
                modified = true
                continue
            }
            
            // Level 3: Token Stream
            if let tokenRange = tokenStreamMatch(searchBlock: searchBlock, in: fileContent) {
                fileContent.replaceSubrange(tokenRange, with: replaceBlock)
                modified = true
                continue
            }
            
            // Level 4: Logic Skeleton
            if let logicRange = logicSkeletonMatch(searchBlock: searchBlock, in: fileContent) {
                fileContent.replaceSubrange(logicRange, with: replaceBlock)
                modified = true
                print("🧠 Logic skeleton match applied: \(relativePath)")
                continue
            }
            
            print("❌ All strategies failed for block in \(relativePath)")
            perfect = false
        }
        
        if modified {
            _ = writeFile(path: relativePath, content: fileContent)
        }
        
        return (modified, perfect)
    }
    
    // Level 2
    private func fuzzyMatchLines(searchBlock: String, in content: String) -> Range<String.Index>? {
        let searchLines = searchBlock.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let pattern = searchLines.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "\\s*\\n\\s*")
        return content.range(of: pattern, options: .regularExpression)
    }
    
    // Level 3
    private func tokenStreamMatch(searchBlock: String, in content: String) -> Range<String.Index>? {
        let searchTokens = searchBlock.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if searchTokens.isEmpty { return nil }
        let escapedTokens = searchTokens.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = escapedTokens.joined(separator: "[\\s\\n]+")
        return content.range(of: pattern, options: .regularExpression)
    }
    
    // Level 4
    private func logicSkeletonMatch(searchBlock: String, in content: String) -> Range<String.Index>? {
        let cleanedSearch = stripComments(from: searchBlock)
        let searchTokens = cleanedSearch.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if searchTokens.isEmpty { return nil }
        let filler = "(?:\\s|//[^\\n]*|/\\*[\\s\\S]*?\\*/)+"
        let escapedTokens = searchTokens.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = escapedTokens.joined(separator: filler)
        return content.range(of: pattern, options: .regularExpression)
    }
    
    private func stripComments(from text: String) -> String {
        var newText = text
        newText = newText.replacingOccurrences(of: "//.*", with: "", options: .regularExpression)
        newText = newText.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
        return newText
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
    
    // MARK: - Finalize
    private func finalizeChanges(updatedFiles: [String], warningFiles: [String]) {
        DispatchQueue.main.async {
            if updatedFiles.isEmpty {
                self.setStatus("", isBusy: false)
                if !warningFiles.isEmpty { self.showNotification(title: "Update Failed", body: "Could not apply changes.") }
                return
            }
            let summary = "Update: \(updatedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))" + (warningFiles.isEmpty ? "" : " (⚠️ Partial)")
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
                } else if self.gitMode == .yolo {
                    _ = try GitService.shared.pushToRemote(in: self.projectRoot)
                    self.finishSuccess(hash: hash, summary: summary, title: "Pushed to Main")
                } else {
                    let branch = "fetch-\(hash)"
                    try GitService.shared.createBranch(in: self.projectRoot, name: branch)
                    _ = try GitService.shared.pushBranch(in: self.projectRoot, branch: branch)
                    self.finishSuccess(hash: hash, summary: summary, title: "PR Ready")
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
    
    func closePR(for log: ChangeLog) {
        if let index = changeLogs.firstIndex(where: { $0.id == log.id }) {
            changeLogs.remove(at: index)
            saveLogs()
        }
        let branchName = "fetch-\(log.commitHash)"
        DispatchQueue.global(qos: .background).async {
            GitService.shared.deleteBranch(in: self.projectRoot, branch: branchName)
        }
    }
    
    // MARK: - Helpers & Prompt v3.0 (Safety Lock)
    func copyGemSetupGuide() {
        // 🔥 Prompt 升级：告诉 Gemini 必须使用暗号
        let instruction = """
        [System Instruction: Fetch App Protocol]
        
        You are acting as a coding agent for the 'Fetch' desktop app.
        
        ⚠️ CRITICAL RULE:
        You MUST start every code response with this exact line:
        >>> INVOKE
        
        If you do not include ">>> INVOKE" at the very top, the app will IGNORE your response.
        
        --- FORMAT A: NEW FILE ---
        <<<FILE>>> path/to/new_file.ext
        (Put full file content here)
        <<<END>>>
        
        --- FORMAT B: SMART EDIT ---
        >>> FILE: path/to/existing_file.ext
        <<<<<<< SEARCH
        (Copy exact lines from original file. 
         Do NOT add new comments like '// old code' inside SEARCH block.
         Do NOT fix bugs inside SEARCH block. It must match the file EXACTLY.)
        =======
        (Put your new code here)
        >>>>>>> REPLACE
        
        --- RULES ---
        - Do NOT wrap blocks in markdown code fences (```).
        """
        pasteboard.clearContents(); pasteboard.setString(instruction, forType: .string)
        showNotification(title: "Setup Copied", body: "Paste to Gemini")
    }
    
    func copyProtocol() {
        pasteboard.clearContents()
        pasteboard.setString("@code", forType: .string)
        showNotification(title: "@code Copied", body: "Ready to pair")
    }
    
    func manualApplyFromClipboard() { checkClipboard() }
    
    func reviewLastChange() {
        guard let lastLog = changeLogs.first else { return }
        DispatchQueue.global().async {
            let diff = try? GitService.shared.run(args: ["show", lastLog.commitHash], in: self.projectRoot)
            let prompt = "Please review this commit diff:\n\n\(diff ?? "")"
            DispatchQueue.main.async {
                self.pasteboard.clearContents(); self.pasteboard.setString(prompt, forType: .string)
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
        notification.soundName = nil
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // Persistence
    private func getLogFileURL() -> URL? {
        guard !projectRoot.isEmpty else { return nil }
        let name = URL(fileURLWithPath: projectRoot).lastPathComponent
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".fetch_logs")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(name).json")
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