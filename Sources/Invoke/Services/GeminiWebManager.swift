import Foundation
import WebKit
import Combine
import AppKit

// MARK: - InteractiveWebView
/// 保留此公共类定义，防止项目中其他使用此类的组件（如 BrowserWindow）报错
class InteractiveWebView: WKWebView {
    override var acceptsFirstResponder: Bool { return true }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        self.window?.makeFirstResponder(self)
    }
    override func becomeFirstResponder() -> Bool { return true }
}

/// Native Gemini Bridge - v15.1 (Serialized & Robust & Build Fixed)
/// 纯后台 JS 注入架构，彻底解决主线程死锁问题，增加请求队列防止并发崩溃
@MainActor
class GeminiWebManager: NSObject, ObservableObject {
    static let shared = GeminiWebManager()
    
    // MARK: - Published State
    @Published var isReady = false
    @Published var isLoggedIn = false
    @Published var isProcessing = false
    @Published var connectionStatus = "Initializing..."
    @Published var lastResponse: String = ""
    
    // MARK: - Internal
    private(set) var webView: WKWebView!
    private var responseCallback: ((String) -> Void)?
    
    // 请求队列结构
    private struct PendingRequest {
        let prompt: String
        let model: String
        let continuation: CheckedContinuation<String, Error>
    }
    
    private var requestStream: AsyncStream<PendingRequest>.Continuation?
    private var requestTask: Task<Void, Never>?
    
    // 使用最新 macOS Safari UA
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    
    override init() {
        super.init()
        setupWebView()
        startRequestLoop()
    }
    
    deinit {
        requestTask?.cancel()
    }

    // MARK: - Queue Management
    
    private func startRequestLoop() {
        let (stream, continuation) = AsyncStream<PendingRequest>.makeStream()
        self.requestStream = continuation
        
        self.requestTask = Task {
            for await request in stream {
                // 确保 Web 环境就绪
                if !self.isReady {
                    // 简单的重试等待逻辑
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                }
                
                if !self.isReady || !self.isLoggedIn {
                    request.continuation.resume(throwing: GeminiError.notReady)
                    continue
                }
                
                do {
                    let response = try await self.performActualNetworkRequest(request.prompt, model: request.model)
                    request.continuation.resume(returning: response)
                } catch {
                    print("❌ Request failed: \(error.localizedDescription)")
                    // 如果是超时，尝试刷新页面恢复
                    if let err = error as? GeminiError, case .timeout = err {
                        print("🔄 Timeout detected, reloading page...")
                        await self.reloadPageAsync()
                    }
                    request.continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
        // 数据持久化
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.applicationNameForUserAgent = "Safari"
        
        // 开发者选项
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // 注入功能脚本
        let userScript = WKUserScript(
            source: Self.injectedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)
        
        // 注入指纹伪装
        let fingerprintScript = WKUserScript(
            source: Self.fingerprintMaskScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(fingerprintScript)
        
        // 注册回调
        config.userContentController.add(self, name: "geminiBridge")
        
        // Headless 模式：0x0 大小，无窗口，纯后台运行
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        
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
    
    private func reloadPageAsync() async {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.reloadPage()
                // 简单延迟等待加载，或者等待 didFinish
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Async / Await API (Public)
    
    func askGemini(prompt: String, model: String = "default") async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let req = PendingRequest(prompt: prompt, model: model, continuation: continuation)
            if let stream = self.requestStream {
                stream.yield(req)
            } else {
                continuation.resume(throwing: GeminiError.systemError("Request stream not initialized"))
            }
        }
    }
    
    // MARK: - Internal Execution
    
    private func performActualNetworkRequest(_ text: String, model: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.isProcessing = true
                let promptId = UUID().uuidString
                
                // 设置一次性回调
                self.responseCallback = { response in
                    self.isProcessing = false
                    if response.hasPrefix("Error: Timeout") {
                         continuation.resume(throwing: GeminiError.timeout)
                    } else if response.hasPrefix("Error:") {
                        continuation.resume(throwing: GeminiError.responseError(response))
                    } else {
                        continuation.resume(returning: response)
                    }
                }
                
                // 转义字符，防止 JS 注入错误
                let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
                                      .replacingOccurrences(of: "\n", with: "\\n")
                
                // 直接调用 JS 函数
                let js = "window.__fetchBridge.sendPrompt(\"\(escapedText)\", \"\(promptId)\");"
                
                self.webView.evaluateJavaScript(js) { [weak self] result, error in
                    if let error = error {
                        print("❌ JS Injection Failed: \(error)")
                        self?.handleError("Failed to send prompt: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func handleError(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isProcessing = false
            self?.responseCallback?(msg)
            self?.responseCallback = nil
        }
    }
    
    enum GeminiError: LocalizedError {
        case notReady
        case timeout
        case responseError(String)
        case systemError(String)
        
        var errorDescription: String? {
            switch self {
            case .notReady: return "Gemini WebView not ready or not logged in"
            case .timeout: return "Request timed out"
            case .responseError(let msg): return msg
            case .systemError(let msg): return msg
            }
        }
    }
    
    // MARK: - Cookie Persistence
    
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
            }
        }
    }
}

// MARK: - Delegates

extension GeminiWebManager: WKNavigationDelegate, WKScriptMessageHandler {
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
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "geminiBridge",
              let body = message.body as? [String: Any] else { return }
        
        let type = body["type"] as? String ?? ""
        
        switch type {
        case "GEMINI_RESPONSE":
            let content = body["content"] as? String ?? ""
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 这里不再直接处理 isProcessing，而是交给 callback 处理
                // 只有当有回调时才处理，避免无关消息
                
                if let callback = self.responseCallback {
                    self.lastResponse = content
                    if content.isEmpty {
                        callback("Error: Empty response from Gemini.")
                    } else {
                        callback(content)
                    }
                    self.responseCallback = nil
                }
                
                // 触发 Vibe Coding 逻辑
                // 修正：移除 await，因为 processResponse 内部已经是异步的
                if !content.isEmpty && !content.hasPrefix("Error:") {
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

// MARK: - Injected Scripts

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
        console.log("🚀 Bridge v15.1 (Headless/Queue) Initializing...");
        
        window.__fetchBridge = {
            sendPrompt: function(text, id) {
                const input = document.querySelector('div[contenteditable="true"]');
                if (!input) {
                    console.error("Input not found");
                    this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: "Error: Input box not found. Please log in." });
                    return;
                }
                
                input.focus();
                document.execCommand('selectAll', false, null);
                document.execCommand('delete', false, null);
                document.execCommand('insertText', false, text);
                
                setTimeout(() => {
                    const sendBtn = document.querySelector('button[aria-label*="Send"], button[class*="send-button"]');
                    if (sendBtn) {
                        sendBtn.click();
                        this.waitForResponse(id);
                    } else {
                        const enter = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, keyCode: 13, key: 'Enter' });
                        input.dispatchEvent(enter);
                        this.waitForResponse(id);
                    }
                }, 500);
            },
            
            waitForResponse: function(id) {
                const self = this;
                let hasStarted = false;
                let silenceTimer = null;
                const startTime = Date.now();
                
                const isNoise = (text) => {
                    if (!text) return true;
                    const t = text.toLowerCase();
                    if (t.includes('sign in') && t.includes('google account')) return true;
                    if (t.includes('get access') && t.includes('gemini advanced')) return true;
                    if (t.includes('show thinking') && t.length < 20) return true;
                    return false;
                };
                
                const observer = new MutationObserver(() => {
                    const stopBtn = document.querySelector('button[aria-label*="Stop"], button[aria-label*="停止"]');
                    if (stopBtn) {
                        hasStarted = true;
                        if (silenceTimer) { clearTimeout(silenceTimer); silenceTimer = null; }
                    } else if (hasStarted) {
                        if (!silenceTimer) silenceTimer = setTimeout(() => finish(), 1500);
                    } else if (Date.now() - startTime > 45000) {
                        finish('timeout');
                    }
                });
                
                const finish = (reason) => {
                    observer.disconnect();
                    let text = "";
                    
                    const selectors = ['.model-response', '.message-content', 'div[role="textbox"]'];
                    for (const sel of selectors) {
                        const els = document.querySelectorAll(sel);
                        for (let i = els.length - 1; i >= 0; i--) {
                            const candidate = els[i].innerText;
                            if (!isNoise(candidate) && candidate.length > 5) {
                                text = candidate;
                                break;
                            }
                        }
                        if (text) break;
                    }
                    
                    text = (text || "").replace(/^\\s*Show thinking\\s*/gi, '').trim();
                    
                    if (reason === 'timeout' && !text) {
                        text = "Error: Timeout waiting for Gemini response";
                    }
                    
                    self.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: text });
                };
                
                observer.observe(document.body, { childList: true, subtree: true, characterData: true });
                
                setTimeout(() => { 
                    observer.disconnect(); 
                    if (hasStarted) finish(); else finish('timeout');
                }, 46000);
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