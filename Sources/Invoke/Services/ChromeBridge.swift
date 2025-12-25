import Foundation
import AppKit

/// 多浏览器桥接器 - 通过 AppleScript "隔空取物" 获取 Cookie
/// 支持 Chrome, Arc, Brave, Edge - 自动检测当前运行的浏览器
class ChromeBridge: ObservableObject {
    static let shared = ChromeBridge()
    
    /// 权限状态 (心跳检测结果)
    @Published var permissionStatus: PermissionStatus = .unknown
    /// 当前检测到的浏览器名称
    @Published var detectedBrowser: String = "浏览器"
    
    enum PermissionStatus {
        case unknown
        case granted      // ✅ 系统权限和浏览器设置都 OK
        case systemDenied // ❌ macOS 系统权限未授予
        case chromeDenied // ⚠️ 浏览器的 JS 开关未开
        case chromeNotRunning // 没有支持的浏览器在运行
    }
    
    /// 支持的浏览器列表 (按优先级排序)
    private let supportedBrowsers: [(name: String, bundleId: String, displayName: String)] = [
        ("Google Chrome", "com.google.Chrome", "Chrome"),
        ("Arc", "company.thebrowser.Browser", "Arc"),
        ("Brave Browser", "com.brave.Browser", "Brave"),
        ("Microsoft Edge", "com.microsoft.edgemac", "Edge")
    ]
    
    /// 生成针对特定浏览器的 AppleScript
    private func cookieScript(for browser: String) -> String {
        // Arc 使用不同的 AppleScript 接口
        if browser == "Arc" {
            return """
            tell application "Arc"
                if (count of windows) = 0 then
                    return "ERROR:NoWindow"
                end if
                
                set activeTab to active tab of front window
                set tabUrl to URL of activeTab
                
                if tabUrl does not contain "google.com" then
                    return "ERROR:WrongSite:" & tabUrl
                end if
                
                -- 执行 JS 获取 Cookie
                try
                    tell activeTab to set cookieData to execute javascript "document.cookie"
                    if cookieData is "" then
                        return "ERROR:NoCookie"
                    end if
                    return cookieData
                on error errMsg
                    return "ERROR:JSDenied:" & errMsg
                end try
            end tell
            """
        }
        
        // Chrome/Brave/Edge 使用相同的 AppleScript 接口
        return """
        tell application "\(browser)"
            if (count of windows) = 0 then
                return "ERROR:NoWindow"
            end if
            
            set activeTab to active tab of front window
            set tabUrl to URL of activeTab
            
            if tabUrl does not contain "google.com" then
                return "ERROR:WrongSite:" & tabUrl
            end if
            
            -- 执行 JS 获取 Cookie
            try
                set cookieData to execute activeTab javascript "document.cookie"
                if cookieData is "" then
                    return "ERROR:NoCookie"
                end if
                return cookieData
            on error errMsg
                return "ERROR:JSDenied:" & errMsg
            end try
        end tell
        """
    }
    
    /// 检测当前运行的浏览器
    private func detectRunningBrowser() -> (name: String, displayName: String)? {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for browser in supportedBrowsers {
            if runningApps.contains(where: { $0.bundleIdentifier == browser.bundleId }) {
                return (browser.name, browser.displayName)
            }
        }
        return nil
    }
    
    /// 从浏览器获取 Cookie (通过 AppleScript，仅用于辅助功能)
    /// 注意：此方法无法获取 HttpOnly Cookie，不能用于持久化登录
    func fetchCookiesFromChrome(completion: @escaping (Result<String, ChromeError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. 检测运行中的浏览器
            guard let browser = self.detectRunningBrowser() else {
                DispatchQueue.main.async {
                    self.detectedBrowser = "浏览器"
                    completion(.failure(.chromeNotRunning))
                }
                return
            }
            
            DispatchQueue.main.async {
                self.detectedBrowser = browser.displayName
            }
            
            print("🔍 检测到浏览器: \(browser.name)")
            
            // 2. 生成对应的 AppleScript
            let scriptSource = self.cookieScript(for: browser.name)
            var error: NSDictionary?
            
            guard let scriptObject = NSAppleScript(source: scriptSource) else {
                DispatchQueue.main.async {
                    completion(.failure(.scriptError("Failed to create AppleScript")))
                }
                return
            }
            
            let output = scriptObject.executeAndReturnError(&error)
            
            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                    let errorNum = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                    print("❌ AppleScript Error [\(errorNum)]: \(errorMsg)")
                    
                    // 检查是否是权限问题
                    // -1743: Not authorized to send Apple events
                    // -1744: 浏览器未启用 Allow JavaScript from Apple Events
                    if errorNum == -1743 || errorMsg.contains("not authorized") || errorMsg.contains("Not authorized") {
                        completion(.failure(.systemPermissionDenied))
                    } else if errorNum == -1744 || errorMsg.contains("not allowed") {
                        completion(.failure(.chromeJSDisabled))
                    } else if errorMsg.contains("permission") {
                        completion(.failure(.systemPermissionDenied))
                    } else {
                        completion(.failure(.scriptError(errorMsg)))
                    }
                    return
                }
                
                guard let resultStr = output.stringValue else {
                    completion(.failure(.scriptError("No output from script")))
                    return
                }
                
                // 解析结果
                if resultStr.starts(with: "ERROR:NoWindow") {
                    completion(.failure(.chromeNotRunning))
                } else if resultStr.starts(with: "ERROR:WrongSite") {
                    let url = resultStr.replacingOccurrences(of: "ERROR:WrongSite:", with: "")
                    completion(.failure(.wrongWebsite(url)))
                } else if resultStr.starts(with: "ERROR:NoCookie") {
                    completion(.failure(.notLoggedIn))
                } else if resultStr.starts(with: "ERROR:JSDenied") {
                    completion(.failure(.chromeJSDisabled))
                } else {
                    // 成功！
                    print("🔮 Telepathy success via \(browser.displayName)! Cookie length: \(resultStr.count)")
                    completion(.success(resultStr))
                }
            }
        }
    }
    
    // MARK: - Heartbeat Check (心跳检测)
    
    /// 静默检测权限状态 (不获取 Cookie，只测试能否访问浏览器)
    func checkPermissionStatus(completion: @escaping (PermissionStatus) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 检测运行中的浏览器
            guard let browser = self.detectRunningBrowser() else {
                DispatchQueue.main.async {
                    self.detectedBrowser = "浏览器"
                    self.permissionStatus = .chromeNotRunning
                    completion(.chromeNotRunning)
                }
                return
            }
            
            DispatchQueue.main.async {
                self.detectedBrowser = browser.displayName
            }
            
            // 生成测试脚本
            let testScript: String
            if browser.name == "Arc" {
                testScript = """
                tell application "Arc"
                    if (count of windows) = 0 then
                        return "NO_WINDOW"
                    end if
                    return URL of active tab of front window
                end tell
                """
            } else {
                testScript = """
                tell application "\(browser.name)"
                    if (count of windows) = 0 then
                        return "NO_WINDOW"
                    end if
                    return URL of active tab of front window
                end tell
                """
            }
            
            var error: NSDictionary?
            
            guard let scriptObject = NSAppleScript(source: testScript) else {
                DispatchQueue.main.async {
                    self.permissionStatus = .systemDenied
                    completion(.systemDenied)
                }
                return
            }
            
            let output = scriptObject.executeAndReturnError(&error)
            
            DispatchQueue.main.async {
                if let error = error {
                    let errorNum = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                    
                    if errorNum == -1743 || errorNum == -10000 {
                        self.permissionStatus = .systemDenied
                        completion(.systemDenied)
                    } else if errorNum == -1744 {
                        self.permissionStatus = .chromeDenied
                        completion(.chromeDenied)
                    } else {
                        self.permissionStatus = .chromeNotRunning
                        completion(.chromeNotRunning)
                    }
                    return
                }
                
                if let result = output.stringValue {
                    if result == "NO_WINDOW" {
                        self.permissionStatus = .chromeNotRunning
                        completion(.chromeNotRunning)
                    } else {
                        self.permissionStatus = .granted
                        completion(.granted)
                    }
                } else {
                    self.permissionStatus = .granted
                    completion(.granted)
                }
            }
        }
    }
    
    /// 打开浏览器并导航到 Gemini (优先使用检测到的浏览器)
    func openGeminiInChrome() {
        // 优先使用已检测到的浏览器，否则使用 Chrome
        let browserName = detectRunningBrowser()?.name ?? "Google Chrome"
        
        let script: String
        if browserName == "Arc" {
            script = """
            tell application "Arc"
                activate
                if (count of windows) = 0 then
                    make new window
                end if
                tell front window
                    make new tab with properties {URL:"https://gemini.google.com"}
                end tell
            end tell
            """
        } else {
            script = """
            tell application "\(browserName)"
                activate
                if (count of windows) = 0 then
                    make new window
                end if
                set URL of active tab of front window to "https://gemini.google.com"
            end tell
            """
        }
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("⚠️ Failed to open \(browserName): \(error)")
            }
        }
    }
    
    // MARK: - Permission Helpers
    
    /// 打开系统设置 - 自动化页面
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 重置 AppleEvents 权限 (后悔药)
    static func resetPermissions(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "AppleEvents"]
            
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0)
                }
            } catch {
                print("❌ Failed to reset permissions: \(error)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - Error Types
    
    enum ChromeError: Error, LocalizedError, Identifiable {
        case chromeNotRunning
        case wrongWebsite(String)
        case notLoggedIn
        case chromeJSDisabled
        case systemPermissionDenied
        case scriptError(String)
        
        var id: String { localizedDescription }
        
        var errorDescription: String? {
            let browserName = ChromeBridge.shared.detectedBrowser
            switch self {
            case .chromeNotRunning:
                return "请先打开浏览器 (Chrome/Arc/Brave/Edge)，并访问 gemini.google.com"
            case .wrongWebsite(let url):
                return "\(browserName) 当前页面不是 Gemini\n\n当前页面: \(url)\n\n请打开 gemini.google.com"
            case .notLoggedIn:
                return "请先在 \(browserName) 中登录你的 Google 账号"
            case .chromeJSDisabled:
                return """
                ⚠️ \(browserName) 需要开启 JavaScript 访问权限
                
                请在 \(browserName) 菜单栏操作：
                View → Developer → Allow JavaScript from Apple Events ✓
                
                (中文: 视图 → 开发者 → 允许来自 Apple 事件的 JavaScript)
                """
            case .systemPermissionDenied:
                return """
                macOS 系统限制：Fetch 需要获得控制 \(browserName) 的权限。
                
                如果在设置中看不到 Fetch，请点击"重置权限"按钮后重试。
                """
            case .scriptError(let msg):
                return "执行错误: \(msg)"
            }
        }
        
        var recoveryAction: String {
            switch self {
            case .chromeNotRunning, .wrongWebsite:
                return "打开 Gemini"
            case .notLoggedIn:
                return "去浏览器登录"
            case .chromeJSDisabled:
                return "查看设置方法"
            case .systemPermissionDenied:
                return "打开系统设置"
            case .scriptError:
                return "重试"
            }
        }
        
        /// 是否是系统权限错误 (需要打开系统设置)
        var isSystemPermissionError: Bool {
            switch self {
            case .systemPermissionDenied:
                return true
            default:
                return false
            }
        }
        
        /// 是否是浏览器设置错误 (需要在浏览器中操作)
        var isChromeSettingError: Bool {
            switch self {
            case .chromeJSDisabled:
                return true
            default:
                return false
            }
        }
        
        /// 兼容旧代码
        var isPermissionError: Bool {
            isSystemPermissionError
        }
    }
}

