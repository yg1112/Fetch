import Foundation
import WebKit
import Combine
import AppKit

// MARK: - InteractiveWebView 子类
/// 解决 WKWebView 在 SwiftUI 中无法接收键盘输入的问题
class InteractiveWebView: WKWebView {
    // 明确告诉系统这个 View 接受第一响应者状态
    override var acceptsFirstResponder: Bool { return true }
    
    // 处理鼠标点击事件，确保点击即聚焦
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        self.window?.makeFirstResponder(self)
    }
    
    override func becomeFirstResponder() -> Bool { return true }
}

/// Native Gemini Bridge - v12.0 (Final Stable)
/// 修复了 Test C 死锁问题：完善了窗口焦点的“借用-归还”机制
/// 修复了 Test A/B 噪音问题：增加了智能文本过滤
@MainActor
class GeminiWebManager: NSObject, ObservableObject {
    static let shared = GeminiWebManager()
    
    // MARK: - Published State
    @Published var isReady = false
    @Published var isLoggedIn = false
    @Published var isProcessing = false
    @Published var connectionStatus = "Initializing..."
    @Published var lastResponse: String = ""
    
    // MARK: - WebView & Window
    private(set) var webView: WKWebView!
    
    // 🔥 影子窗口：专门用于接收 MagicPaster 的粘贴指令
    private var shadowWindow: NSWindow! 
    
    private var pendingPromptId: String?
    private var responseCallback: ((String) -> Void)?
    
    // 使用最新的 macOS Safari UA
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    
    override init() {
        super.init()
        setupWebView()
    }
    
    // MARK: - Setup
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
        // 持久化 Cookie (登录态)
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.applicationNameForUserAgent = "Safari"
        
        // 启用开发者工具
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // 允许 JavaScript
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // 注入功能脚本 (包含智能降噪逻辑)
        let userScript = WKUserScript(
            source: Self.injectedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)
        
        // 注入指纹伪装脚本
        let fingerprintScript = WKUserScript(
            source: Self.fingerprintMaskScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(fingerprintScript)
        
        // Swift <-> JS 消息通道
        config.userContentController.add(self, name: "geminiBridge")
        
        // 创建可交互的 WebView
        webView = InteractiveWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        
        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif
        
        // 🔥 创建影子窗口 (Shadow Window)
        shadowWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .miniaturizable], 
            backing: .buffered,
            defer: false
        )
        shadowWindow.title = "Gemini Engine"
        shadowWindow.contentView = webView
        shadowWindow.isReleasedWhenClosed = false // 关闭只是隐藏，不销毁
        shadowWindow.level = .floating // 浮动层级
        shadowWindow.alphaValue = 0.95 // 轻微透明
        
        // 确保它能跨越 Spaces，防止切换桌面导致找不到窗口而死锁
        shadowWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 初始状态：隐藏
        shadowWindow.orderOut(nil) 
        
        // 恢复 Cookie 并加载
        restoreCookiesFromStorage { [weak self] in
            self?.loadGemini()
        }
    }
    
    func loadGemini() {
        connectionStatus = "Loading Gemini..."
        if let url = URL(string: "https://gemini.google.com/app") {
            webView.load(URLRequest(url: url))
        }
    }
    
    // MARK: - Public API
    
    /// 发送 Prompt 给 Gemini
    func sendPrompt(_ text: String, model: String = "default", completion: @escaping (String) -> Void) {
        if !isLoggedIn {
             print("⚠️ Warning: Sending prompt while not fully logged in. Might fail.")
        }
        
        isProcessing = true
        pendingPromptId = UUID().uuidString
        responseCallback = completion
        
        // 统一输入流: 使用剪贴板 + 影子窗口 + MagicPaster
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 写入剪贴板
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            // 2. 🔥 强制借用焦点 (Fix Test C Freeze)
            // 必须先激活 App，再激活窗口，确保 MagicPaster 能打中目标
            NSApp.activate(ignoringOtherApps: true)
            self.shadowWindow.makeKeyAndOrderFront(nil)
            
            // 3. 给予充足的缓冲时间 (0.5s) 让 WindowServer 反应过来
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 清理弹窗
                self.cleanupPopups { [weak self] in
                    guard let self = self else { return }
                    
                    // 4. 执行粘贴
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // allowHide: false -> 保持在当前 App (影子窗口) 粘贴
                        MagicPaster.shared.pasteToBrowser(allowHide: false)
                        
                        // 开始等待响应
                        self.waitForResponse(id: self.pendingPromptId!)
                    }
                }
            }
        }
    }
    
    // 🔥 核心修复：安全归还焦点 (Safe Focus Restore)
    private func hideShadowWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("👻 Hiding Shadow Window & Restoring Focus")
            
            // 1. 隐藏影子窗口
            self.shadowWindow.orderOut(nil)
            
            // 2. ⚡️ 关键修复：延时归还焦点
            // 如果不延时，直接由 hide 触发 focus change 可能会导致死锁
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // 确保 App 处于活跃状态
                NSApp.activate(ignoringOtherApps: true)
                
                // 找到主窗口并归还 "Key Window" 状态
                // 排除影子窗口自己，找到第一个可见的普通窗口
                if let mainWindow = NSApp.windows.first(where: { 
                    $0 != self.shadowWindow && 
                    $0.isVisible && 
                    !$0.isMiniaturized &&
                    $0.title != "Gemini Engine"
                }) {
                    mainWindow.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    /// 清理干扰弹窗（通过JS）
    private func cleanupPopups(completion: @escaping () -> Void) {
        let cleanupScript = """
        (function() {
            // 尝试关闭 "Get access", "Sign in", "No thanks" 等阻挡型弹窗
            const btns = Array.from(document.querySelectorAll('button'));
            const closeBtns = btns.filter(b => {
                const t = (b.innerText || '').toLowerCase();
                const l = (b.getAttribute('aria-label') || '').toLowerCase();
                return t.includes('no thanks') || t.includes('not now') || 
                       t.includes('dismiss') || t.includes('close') || 
                       l.includes('close') || l.includes('dismiss');
            });
            closeBtns.forEach(b => { try { b.click(); } catch(e){} });
        })();
        """
        
        webView.evaluateJavaScript(cleanupScript) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                completion()
            }
        }
    }
    
    /// 等待Gemini响应完成
    private func waitForResponse(id: String) {
        let waitScript = """
        window.__fetchBridge.waitForResponse("\(id)");
        """
        
        webView.evaluateJavaScript(waitScript) { [weak self] _, error in
            if let error = error {
                print("❌ Wait script error: \(error)")
                self?.handleError("Script Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleError(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isProcessing = false
            self?.responseCallback?(msg)
            self?.responseCallback = nil
            self?.hideShadowWindow()
        }
    }
    
    // MARK: - Async API (for LocalAPIServer)
    
    func askGemini(prompt: String, model: String = "default") async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard self.isReady && self.isLoggedIn else {
                continuation.resume(throwing: GeminiError.notReady)
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.sendPrompt(prompt, model: model) { response in
                    if response.hasPrefix("Error:") {
                        continuation.resume(throwing: GeminiError.responseError(response))
                    } else {
                        continuation.resume(returning: response)
                    }
                }
            }
        }
    }
    
    enum GeminiError: LocalizedError {
        case notReady
        case responseError(String)
        
        var errorDescription: String? {
            switch self {
            case .notReady: return "Gemini WebView not ready or not logged in"
            case .responseError(let msg): return msg
            }
        }
    }
    
    /// 检查登录状态
    func checkLoginStatus() {
        let js = "window.__fetchBridge ? window.__fetchBridge.checkLogin() : false;"
        webView.evaluateJavaScript(js) { [weak self] result, error in
            DispatchQueue.main.async {
                if let loggedIn = result as? Bool {
                    self?.isLoggedIn = loggedIn
                    self?.connectionStatus = loggedIn ? "🟢 Connected" : "🔴 Need Login"
                } else if let dict = result as? [String: Any], let loggedIn = dict["loggedIn"] as? Bool {
                    self?.isLoggedIn = loggedIn
                    self?.connectionStatus = loggedIn ? "🟢 Connected" : "🔴 Need Login"
                }
                
                // URL double check
                self?.webView.evaluateJavaScript("window.location.href") { urlRes, _ in
                    if let s = urlRes as? String, s.contains("gemini.google.com") && !s.contains("accounts") && !s.contains("signin") {
                        if self?.isLoggedIn == false {
                            self?.isLoggedIn = true
                            self?.connectionStatus = "🟢 Connected"
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cookie Injection & Persistence
    
    private static let cookieStorageKey = "FetchGeminiCookies"
    
    func injectRawCookies(_ cookieString: String, completion: @escaping () -> Void) {
        let dataStore = WKWebsiteDataStore.default()
        let cookieStore = dataStore.httpCookieStore
        let components = cookieString.components(separatedBy: ";")
        
        let group = DispatchGroup()
        var cookiesToSave: [[String: Any]] = []
        
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                let properties: [HTTPCookiePropertyKey: Any] = [
                    .domain: ".google.com", .path: "/", .name: name, .value: value, .secure: "TRUE",
                    .expires: Date(timeIntervalSinceNow: 31536000)
                ]
                
                if let cookie = HTTPCookie(properties: properties) {
                    group.enter()
                    cookieStore.setCookie(cookie) { group.leave() }
                    cookiesToSave.append([
                        "name": name, "value": value, "domain": ".google.com", "path": "/",
                        "expires": Date(timeIntervalSinceNow: 31536000).timeIntervalSince1970
                    ])
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            UserDefaults.standard.set(cookiesToSave, forKey: Self.cookieStorageKey)
            self?.reloadPage()
            completion()
        }
    }
    
    func restoreCookiesFromStorage(completion: @escaping () -> Void) {
        guard let savedCookies = UserDefaults.standard.array(forKey: Self.cookieStorageKey) as? [[String: Any]] else {
            completion()
            return
        }
        
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        
        for cookieData in savedCookies {
            guard let name = cookieData["name"] as? String,
                  let value = cookieData["value"] as? String,
                  let domain = cookieData["domain"] as? String,
                  let path = cookieData["path"] as? String else { continue }
            
            let props: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: path, .name: name, .value: value, .secure: "TRUE"]
            
            if let cookie = HTTPCookie(properties: props) {
                group.enter()
                cookieStore.setCookie(cookie) { group.leave() }
            }
        }
        
        group.notify(queue: .main) { completion() }
    }
    
    func reloadPage() {
        if let url = URL(string: "https://gemini.google.com/app") {
            webView.load(URLRequest(url: url))
        }
    }
    
    func clearCookies(completion: @escaping () -> Void) {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let googleRecords = records.filter { $0.displayName.contains("google") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: googleRecords, completionHandler: completion)
        }
    }
}

// MARK: - WKNavigationDelegate

extension GeminiWebManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isReady = true
            self?.checkLoginStatus()
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ Navigation failed: \(error)")
        connectionStatus = "🔴 Load Failed"
    }
}

// MARK: - WKScriptMessageHandler

extension GeminiWebManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "geminiBridge",
              let body = message.body as? [String: Any] else { return }
        
        let type = body["type"] as? String ?? ""
        
        switch type {
        case "GEMINI_RESPONSE":
            let content = body["content"] as? String ?? ""
            print("📥 Received Content Length: \(content.count)")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.isProcessing = false
                self.lastResponse = content
                
                // 🔥 如果内容为空，返回错误提示
                if content.isEmpty {
                    self.responseCallback?("Error: Empty response from Gemini. The scraper missed the text.")
                } else {
                    self.responseCallback?(content)
                }
                
                self.responseCallback = nil
                self.hideShadowWindow() // 任务完成，归还焦点
                
                // Vibe Coding 逻辑
                if !content.isEmpty {
                    GeminiLinkLogic.shared.processResponse(content)
                }
            }
            
        case "LOGIN_STATUS":
            let loggedIn = body["loggedIn"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in
                self?.isLoggedIn = loggedIn
                self?.connectionStatus = loggedIn ? "🟢 Connected" : "🔴 Need Login"
            }
            
        case "STATUS":
            print("📊 Bridge Status: \(body["status"] as? String ?? "")")
            
        default:
            print("⚠️ Unknown message type: \(type)")
        }
    }
}

// MARK: - ⚠️ 智能降噪抓取脚本 (Smart Noise Filtering)

extension GeminiWebManager {
    static let fingerprintMaskScript = """
    (function() {
        if (navigator.webdriver) { delete navigator.webdriver; }
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined, configurable: true });
        const originalQuery = window.Permissions.prototype.query;
        if (originalQuery) {
            window.Permissions.prototype.query = (parameters) => (
                parameters.name === 'notifications' ? Promise.resolve({ state: Notification.permission }) : originalQuery(parameters)
            );
        }
    })();
    """
    
    static let injectedScript = """
    (function() {
        console.log("🚀 Bridge v12 (Focus Fix + Noise Filter) Initializing...");
        
        window.__fetchBridge = {
            waitForResponse: function(id) {
                const self = this;
                let hasStarted = false;
                let silenceTimer = null;
                const startTime = Date.now();
                
                // 🔥 噪音过滤器：识别无效信息
                const isNoise = (text) => {
                    if (!text) return true;
                    const t = text.toLowerCase();
                    // 排除登录提示、Upsell广告、纯Thinking标签
                    if (t.includes('sign in') && t.includes('google account')) return true;
                    if (t.includes('get access to all gemini models')) return true;
                    if (t.includes('upgrade to gemini advanced')) return true;
                    if (t.includes('show thinking') && t.length < 20) return true;
                    return false;
                };
                
                const observer = new MutationObserver(() => {
                    // 只要有“停止”按钮，说明正在生成
                    const stopBtn = document.querySelector('button[aria-label*="Stop"], button[aria-label*="停止"]');
                    if (stopBtn) {
                        hasStarted = true;
                        if (silenceTimer) { clearTimeout(silenceTimer); silenceTimer = null; }
                    } else if (hasStarted) {
                        // 按钮消失了，说明生成结束，倒计时 1.5秒 收网
                        if (!silenceTimer) silenceTimer = setTimeout(() => finish(), 1500);
                    } else if (Date.now() - startTime > 35000) {
                        // 35秒超时保护
                        finish('timeout');
                    }
                });
                
                const finish = (reason) => {
                    observer.disconnect();
                    let text = "";
                    
                    // 策略 A: 查找标准容器 (Gemini 常用)
                    const selectors = [
                        '.model-response', 'model-response', 
                        '.message-content', 'message-content',
                        '.text-content', 'text-content',
                        'div[role="textbox"]'
                    ];
                    
                    // 倒序查找（找最新的）
                    for (const sel of selectors) {
                        const els = document.querySelectorAll(sel);
                        // 从最后一个往前找，直到找到非噪音内容
                        for (let i = els.length - 1; i >= 0; i--) {
                            const candidate = els[i].innerText;
                            if (!isNoise(candidate) && candidate.length > 5) {
                                text = candidate;
                                console.log("✅ Found valid text via selector: " + sel);
                                break;
                            }
                        }
                        if (text) break;
                    }
                    
                    // 策略 B: 智能暴力查找 (Smart Fallback)
                    if (!text || text.length < 5) {
                        console.log("⚠️ Selector failed, trying smart brute force...");
                        // 找所有包含大量文本的 div
                        const candidates = Array.from(document.querySelectorAll('div, p')).filter(d => {
                            const t = d.innerText || "";
                            // 过滤条件：长度足够、没有textarea、子元素少、且不是噪音
                            return t.length > 20 && 
                                   !d.querySelector('textarea') && 
                                   d.children.length < 10 &&
                                   !isNoise(t);
                        });
                        
                        if (candidates.length > 0) {
                            text = candidates[candidates.length - 1].innerText; // 取最后一个有效的
                            console.log("✅ Smart brute force found text block");
                        }
                    }
                    
                    // 最后的清理
                    text = (text || "").replace(/^\\s*Show thinking\\s*/gi, '')
                                       .replace(/Gemini can make mistakes.*/gi, '')
                                       .trim();
                    
                    if (reason === 'timeout' && !text) {
                        text = "Error: Timeout waiting for Gemini response";
                    }
                    
                    console.log("📤 Sending text length: " + text.length);
                    self.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: text });
                };
                
                observer.observe(document.body, { childList: true, subtree: true, characterData: true });
                
                // 硬超时保护 (40秒)
                setTimeout(() => { 
                    observer.disconnect(); 
                    if (hasStarted) finish(); 
                    else finish('timeout');
                }, 40000);
            },
            
            checkLogin: function() {
                const loggedIn = window.location.href.includes('gemini.google.com') && 
                                 !!document.querySelector('div[contenteditable="true"]');
                this.postToSwift({ type: 'LOGIN_STATUS', loggedIn: loggedIn });
                return loggedIn;
            },
            
            postToSwift: function(data) {
                if (window.webkit && window.webkit.messageHandlers.geminiBridge) {
                    window.webkit.messageHandlers.geminiBridge.postMessage(data);
                }
            }
        };
        
        setTimeout(() => window.__fetchBridge.checkLogin(), 2000);
    })();
    """
}