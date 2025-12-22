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
    private let markerStart = "!!!B64_START!!!"
    private let markerEnd = "!!!B64_END!!!"
    
    init() {
        if !projectRoot.isEmpty { loadLogs() }
    }
    
    // MARK: - File Selection
    func selectProjectRoot() {
        print("🔍 [DEBUG] selectProjectRoot called")
        print("🔍 [DEBUG] Thread: \(Thread.current)")
        print("🔍 [DEBUG] Is main thread: \(Thread.isMainThread)")
        
        // Run on main thread
        guard Thread.isMainThread else {
            print("⚠️ [DEBUG] Not on main thread, dispatching to main")
            DispatchQueue.main.async { [weak self] in
                self?.selectProjectRoot()
            }
            return
        }
        
        print("🔍 [DEBUG] Creating NSOpenPanel...")
        let panel = NSOpenPanel()
        
        // Log app bundle info
        if let bundleID = Bundle.main.bundleIdentifier {
            print("🔍 [DEBUG] Bundle ID: \(bundleID)")
        }
        print("🔍 [DEBUG] App path: \(Bundle.main.bundlePath)")
        
        // Basic configuration
        print("🔍 [DEBUG] Configuring panel properties...")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        
        // Important: Allow selecting packages as directories (like .app bundles)
        panel.treatsFilePackagesAsDirectories = true
        
        // Set user-friendly labels
        panel.message = "Choose a project folder to monitor for Git changes"
        panel.prompt = "Select"
        panel.title = "Select Project Folder"
        
        // Don't restrict to specific file types - allow all directories
        panel.allowsOtherFileTypes = true
        
        // Log current window info
        if let window = NSApp.keyWindow {
            print("🔍 [DEBUG] Key window exists: \(window)")
        } else {
            print("⚠️ [DEBUG] No key window")
        }
        
        if let window = NSApp.mainWindow {
            print("🔍 [DEBUG] Main window exists: \(window)")
        } else {
            print("⚠️ [DEBUG] No main window")
        }
        
        print("🔍 [DEBUG] NSApp is active: \(NSApp.isActive)")
        print("🔍 [DEBUG] Activating app...")
        NSApp.activate(ignoringOtherApps: true)
        
        print("🔍 [DEBUG] Opening panel with runModal...")
        print("🔍 [DEBUG] Panel configuration:")
        print("  - canChooseFiles: \(panel.canChooseFiles)")
        print("  - canChooseDirectories: \(panel.canChooseDirectories)")
        print("  - allowsMultipleSelection: \(panel.allowsMultipleSelection)")
        print("  - treatsFilePackagesAsDirectories: \(panel.treatsFilePackagesAsDirectories)")
        print("  - allowsOtherFileTypes: \(panel.allowsOtherFileTypes)")
        
        // Try to get current directory
        if let currentDir = FileManager.default.currentDirectoryPath as String? {
            print("🔍 [DEBUG] Current directory: \(currentDir)")
        }
        
        print("🔍 [DEBUG] Calling panel.runModal()...")
        let response = panel.runModal()
        print("🔍 [DEBUG] Panel returned with response: \(response.rawValue)")
        
        // Process response
        if response == .OK {
            print("🔍 [DEBUG] Response is .OK")
            if let url = panel.url {
                print("✅ [DEBUG] URL selected: \(url)")
                print("✅ [DEBUG] URL path: \(url.path)")
                print("✅ [DEBUG] URL exists: \(FileManager.default.fileExists(atPath: url.path))")
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    print("✅ [DEBUG] Is directory: \(isDirectory.boolValue)")
                }
                
                self.projectRoot = url.path
                print("📂 Project root selected: \(url.lastPathComponent)")
                print("📁 Full path: \(url.path)")
            } else {
                print("❌ [DEBUG] Response was .OK but URL is nil!")
            }
        } else if response == .cancel {
            print("🔍 [DEBUG] User cancelled selection")
        } else {
            print("⚠️ [DEBUG] Unexpected response: \(response.rawValue)")
        }
        
        print("🔍 [DEBUG] selectProjectRoot completed")
    }

    // MARK: - Core Flow
    func toggleListening() {
        isListening.toggle()
        if isListening {
            lastChangeCount = pasteboard.changeCount
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkClipboard()
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        guard let content = pasteboard.string(forType: .string),
              content.contains(markerStart) else { return }
        
        processClipboardContent(content)
    }
    
    private func processClipboardContent(_ rawText: String) {
        let pattern = try! NSRegularExpression(
            pattern: "\(NSRegularExpression.escapedPattern(for: markerStart))\\s+(.*?)\\s+(.*?)\\s+\(NSRegularExpression.escapedPattern(for: markerEnd))",
            options: .dotMatchesLineSeparators
        )
        let matches = pattern.matches(in: rawText, options: [], range: NSRange(rawText.startIndex..<rawText.endIndex, in: rawText))
        
        if matches.isEmpty { return }
        
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
        guard let data = Data(base64Encoded: base64Content) else { return false }
        let fullURL = URL(fileURLWithPath: projectRoot).appendingPathComponent(relativePath)
        do {
            try FileManager.default.createDirectory(at: fullURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fullURL)
            return true
        } catch {
            print("Write error: \(error)")
            return false
        }
    }
    
    // MARK: - Git & Logging Logic
    private func autoCommitAndPush(message: String, summary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try GitService.shared.pushChanges(in: self.projectRoot, message: message)
                
                // Try to get hash, fallback to "unknown" if fails
                let commitHash = (try? GitService.shared.run(args: ["rev-parse", "--short", "HEAD"], in: self.projectRoot)) ?? "unknown"
                
                DispatchQueue.main.async {
                    let newLog = ChangeLog(commitHash: commitHash, timestamp: Date(), summary: summary)
                    self.changeLogs.insert(newLog, at: 0)
                    self.saveLogs()
                    NSSound(named: "Glass")?.play()
                }
            } catch {
                print("Git Error: \(error)")
            }
        }
    }
    
    // MARK: - Protocol & Validation
    func copyProtocol() {
        let structure = "(Project structure omitted)"
        let prompt = """
        You are my Senior AI Pair Programmer.
        Current Project Structure:
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
        
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
    }
    
    func validateCommit(_ log: ChangeLog) {
        DispatchQueue.global().async {
            let diff = try? GitService.shared.run(args: ["show", log.commitHash], in: self.projectRoot)
            
            let prompt = """
            Please VALIDATE this specific commit: \(log.commitHash).
            
            I have just applied these changes locally. Here is the `git show` output:
            
            \(diff ?? "Error reading diff")
            
            Task:
            1. Review the code changes for logic errors or bugs.
            2. If CORRECT, reply: "Commit \(log.commitHash) Verified: [Short Summary]"
            3. If WRONG, output the FIX using the Base64 Protocol immediately.
            """
            
            DispatchQueue.main.async {
                self.pasteboard.clearContents()
                self.pasteboard.setString(prompt, forType: .string)
            }
        }
    }
    
    func toggleValidationStatus(for id: String) {
        if let index = changeLogs.firstIndex(where: { $0.id == id }) {
            changeLogs[index].isValidated.toggle()
            saveLogs()
        }
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
