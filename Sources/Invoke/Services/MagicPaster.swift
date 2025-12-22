import Foundation
import AppKit

class MagicPaster {
    static let shared = MagicPaster()
    
    // 保存用户原始剪贴板内容
    private var savedClipboard: String?
    
    // 支持的目标浏览器和 URL
    private let targetBrowsers = ["Google Chrome", "Safari", "Arc", "Brave Browser", "Microsoft Edge"]
    private let targetURLPattern = "gemini.google.com"
    
    /// 智能粘贴 - 只粘贴到 Gemini 网页
    func pasteToBrowser() {
        print("🎯 MagicPaster: Smart Paste initiating...")
        
        // 检查 Accessibility 权限
        guard AXIsProcessTrusted() else {
            print("⚠️ Accessibility permission denied!")
            requestAccessibilityPermissionWithAlert()
            return
        }
        
        // 检测当前浏览器和 URL
        guard let browserInfo = detectFrontmostBrowser() else {
            print("⚠️ No supported browser detected in foreground")
            showNotification(title: "Browser Not Found", body: "Please open Gemini in Chrome/Safari first")
            return
        }
        
        print("🌐 Detected browser: \(browserInfo.browser)")
        print("🔗 Current URL: \(browserInfo.url)")
        
        // 验证是否在 Gemini 页面
        guard browserInfo.url.contains(targetURLPattern) else {
            print("⚠️ Not on Gemini page, aborting paste")
            showNotification(title: "Wrong Page", body: "Please navigate to gemini.google.com first")
            return
        }
        
        print("✅ Gemini page confirmed, proceeding with paste...")
        
        // 最小化 Invoke 窗口
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                window.miniaturize(nil)
            }
        }
        
        // 延迟后发送粘贴命令
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.sendPasteCommand()
            
            // 恢复窗口
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let window = NSApplication.shared.windows.first(where: { $0.isMiniaturized }) {
                    window.deminiaturize(nil)
                }
            }
        }
    }
    
    /// 检测前台浏览器和当前 URL
    private func detectFrontmostBrowser() -> (browser: String, url: String)? {
        // 尝试 Chrome
        if let url = getChromeURL() {
            return ("Google Chrome", url)
        }
        
        // 尝试 Safari
        if let url = getSafariURL() {
            return ("Safari", url)
        }
        
        // 尝试 Arc
        if let url = getArcURL() {
            return ("Arc", url)
        }
        
        return nil
    }
    
    private func getChromeURL() -> String? {
        let script = """
        tell application "System Events"
            if exists process "Google Chrome" then
                tell application "Google Chrome"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
            end if
        end tell
        return ""
        """
        return runAppleScript(script)
    }
    
    private func getSafariURL() -> String? {
        let script = """
        tell application "System Events"
            if exists process "Safari" then
                tell application "Safari"
                    if (count of windows) > 0 then
                        return URL of current tab of front window
                    end if
                end tell
            end if
        end tell
        return ""
        """
        return runAppleScript(script)
    }
    
    private func getArcURL() -> String? {
        let script = """
        tell application "System Events"
            if exists process "Arc" then
                tell application "Arc"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
            end if
        end tell
        return ""
        """
        return runAppleScript(script)
    }
    
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            if error == nil, let stringValue = result.stringValue, !stringValue.isEmpty {
                return stringValue
            }
        }
        return nil
    }
    
    private func sendPasteCommand() {
        let script = """
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            _ = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("❌ MagicPaste Error: \(error)")
            } else {
                print("✅ MagicPaster: Paste sent to Gemini")
            }
        }
    }
    
    // MARK: - 剪贴板保护
    
    /// 保存用户当前剪贴板（在写入协议前调用）
    func saveUserClipboard() {
        savedClipboard = NSPasteboard.general.string(forType: .string)
        if savedClipboard != nil {
            print("💾 User clipboard saved")
        }
    }
    
    /// 恢复用户剪贴板（在操作完成后调用）
    func restoreUserClipboard() {
        guard let saved = savedClipboard else { return }
        
        // 延迟恢复，确保粘贴操作已完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
            print("♻️ User clipboard restored")
            self.savedClipboard = nil
        }
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
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
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
        }
    }
}
