import Foundation
import AppKit

class MagicPaster {
    static let shared = MagicPaster()
    
    // 默认浏览器，稍后可以在 UI 里做成设置项
    var targetBrowser: String = "Google Chrome"
    
    func pasteToBrowser() {
        print("🎯 MagicPaster: Attempting to paste to \(targetBrowser)...")
        
        // 检测浏览器是否在运行
        let runningApps = NSWorkspace.shared.runningApplications
        let isBrowserRunning = runningApps.contains { $0.localizedName == targetBrowser }
        
        if !isBrowserRunning {
            print("⚠️ Warning: \(targetBrowser) is not running")
        }
        
        let scriptSource = """
        tell application "\(targetBrowser)"
            activate
        end tell
        delay 0.5
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: scriptSource) {
            _ = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("❌ MagicPaste Error: \(error)")
            } else {
                print("✅ MagicPaster: Paste command sent successfully")
            }
        }
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
