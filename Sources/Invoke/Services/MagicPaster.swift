import Foundation
import AppKit

class MagicPaster {
    static let shared = MagicPaster()
    
    func pasteToBrowser() {
        print("🎯 MagicPaster: Executing Universal Paste...")
        
        // 检查 Accessibility 权限
        guard AXIsProcessTrusted() else {
            print("⚠️ Accessibility permission denied!")
            requestAccessibilityPermissionWithAlert()
            return
        }
        
        print("✅ Accessibility permission granted, proceeding...")
        
        // 1. 安全地最小化窗口而不隐藏整个应用
        DispatchQueue.main.async {
            if let windows = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                windows.miniaturize(nil)
            }
        }
        
        // 2. 稍作延迟，等待窗口切换完成，然后发送 Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
            
            // 3. 恢复窗口显示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let windows = NSApplication.shared.windows.first(where: { $0.isMiniaturized }) {
                    windows.deminiaturize(nil)
                }
            }
        }
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func requestAccessibilityPermissionWithAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要 Accessibility 权限"
            alert.informativeText = "Invoke 需要 Accessibility 权限才能自动粘贴到浏览器。\n\n重要提醒：\n• 如果 Accessibility 列表中已有其他 Invoke 条目，请先删除它们\n• 只保留最新的 Invoke 条目以避免冲突\n\n点击 '打开设置' 前往 System Preferences > Security & Privacy > Accessibility"
            alert.addButton(withTitle: "打开设置")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 打开 Accessibility 设置并请求权限
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
        }
    }
}
