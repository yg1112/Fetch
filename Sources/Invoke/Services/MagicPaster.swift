import Foundation
import AppKit

class MagicPaster {
    static let shared = MagicPaster()
    
    func pasteToBrowser() {
        print("🎯 MagicPaster: Executing Universal Paste...")
        
        // 1. 隐藏 Invoke 自身
        // 这会让焦点自动回到用户刚才使用的窗口（即浏览器）
        DispatchQueue.main.async {
            NSApp.hide(nil)
        }
        
        // 2. 稍作延迟，等待窗口切换完成，然后发送 Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let scriptSource = """
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
                    print("✅ MagicPaster: Paste command sent to frontmost app")
                }
            }
        }
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
