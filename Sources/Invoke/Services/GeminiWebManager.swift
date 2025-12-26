import Foundation
import WebKit
import Combine
import AppKit

// MARK: - InteractiveWebView
class InteractiveWebView: WKWebView {
    override var acceptsFirstResponder: Bool { return true }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        self.window?.makeFirstResponder(self)
    }
    override func becomeFirstResponder() -> Bool { return true }
}

/// Native Gemini Bridge - v23.0 (Strict State-Sync)
/// 修复核心：
/// 1. 发送验证：3秒后检查用户气泡是否增加，快速失败。
/// 2. 严格抓取：forceFinish 必须检查是否有新内容，否则返回错误。
/// 3. 防止旧话重提：extractStrict 检查数量，杜绝抓取旧气泡。
@MainActor
class GeminiWebManager: NSObject, ObservableObject {
    static let shared = GeminiWebManager()
    
    @Published var isReady = false
    @Published var isLoggedIn = false
    @Published var isProcessing = false
    @Published var connectionStatus = "Initializing..."
    @Published var lastResponse: String = ""
    
    private(set) var webView: WKWebView!
    private var debugWindow: NSWindow?
    private var responseCallback: ((String) -> Void)?
    
    private struct PendingRequest {
        let prompt: String
        let model: String
        let continuation: CheckedContinuation<String, Error>
    }
    
    private var requestStream: AsyncStream<PendingRequest>.Continuation?
    private var requestTask: Task<Void, Never>?
    private var watchdogTimer: Timer?
    
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    
    override init() {
        super.init()
        setupWebView()
        startRequestLoop()
    }
    
    deinit {
        requestTask?.cancel()
        debugWindow?.close()
        watchdogTimer?.invalidate()
    }

    private func startRequestLoop() {
        let (stream, continuation) = AsyncStream<PendingRequest>.makeStream()
        self.requestStream = continuation
        
        self.requestTask = Task {
            for await request in stream {
                if !self.isReady { try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) }
                
                print("🚀 [Queue] Processing: \(request.prompt.prefix(15))...")
                
                do {
                    let response = try await self.performActualNetworkRequest(request.prompt, model: request.model)
                    request.continuation.resume(returning: response)
                } catch {
                    print("❌ [Queue] Failed: \(error)")
                    if let err = error as? GeminiError, case .timeout = err { await self.reloadPageAsync() }
                    request.continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.applicationNameForUserAgent = "Safari"
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let userScript = WKUserScript(source: Self.injectedScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        
        let fingerprintScript = WKUserScript(source: Self.fingerprintMaskScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(fingerprintScript)
        config.userContentController.add(self, name: "geminiBridge")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        
        // 🚨 保持调试窗口开启，方便你确认"幽灵消息"
        debugWindow = NSWindow(
            contentRect: NSRect(x: 50, y: 50, width: 1100, height: 850),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        debugWindow?.title = "Fetch Debugger (v23 Strict State-Sync)"
        debugWindow?.contentView = webView
        debugWindow?.makeKeyAndOrderFront(nil)
        debugWindow?.level = .floating 
        
        restoreCookiesFromStorage { [weak self] in self?.loadGemini() }
    }
    
    func loadGemini() {
        if let url = URL(string: "https://gemini.google.com/app") { webView.load(URLRequest(url: url)) }
    }
    
    private func reloadPageAsync() async {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.reloadPage()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { continuation.resume() }
            }
        }
    }
    
    func askGemini(prompt: String, model: String = "default") async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let req = PendingRequest(prompt: prompt, model: model, continuation: continuation)
            if let stream = self.requestStream { stream.yield(req) } 
            else { continuation.resume(throwing: GeminiError.systemError("Stream Error")) }
        }
    }
    
    private func performActualNetworkRequest(_ text: String, model: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.isProcessing = true
                let promptId = UUID().uuidString
                
                self.watchdogTimer?.invalidate()
                self.responseCallback = nil
                
                self.responseCallback = { response in
                    self.watchdogTimer?.invalidate()
                    self.isProcessing = false
                    
                    if response.hasPrefix("Error:") { 
                        continuation.resume(throwing: GeminiError.responseError(response)) 
                    } else { 
                        continuation.resume(returning: response) 
                    }
                }
                
                // 延长超时到 50s，因为 Aider 可能会先发一条幽灵消息
                self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 50.0, repeats: false) { [weak self] _ in
                    print("⏰ Timeout. Force scrape...")
                    self?.forceScrape(id: promptId)
                }
                
                let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
                                      .replacingOccurrences(of: "\n", with: "\\n")
                
                let js = "window.__fetchBridge.sendPromptStrict(\"\(escapedText)\", \"\(promptId)\");"
                self.webView.evaluateJavaScript(js) { _, _ in }
            }
        }
    }
    
    private func forceScrape(id: String) {
        let js = "window.__fetchBridge.forceFinish('\(id)');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func handleError(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            self?.watchdogTimer?.invalidate()
            self?.isProcessing = false
            self?.responseCallback?(msg)
            self?.responseCallback = nil
        }
    }
    
    enum GeminiError: LocalizedError {
        case notReady, timeout, responseError(String), systemError(String)
        var errorDescription: String? {
            switch self {
            case .notReady: return "Not ready"
            case .timeout: return "Timeout"
            case .responseError(let m): return m
            case .systemError(let m): return m
            }
        }
    }
    
    // MARK: - Cookie / Helper
    private static let cookieStorageKey = "FetchGeminiCookies"
    func injectRawCookies(_ c: String, completion: @escaping () -> Void) { /* ... */ }
    
    func restoreCookiesFromStorage(completion: @escaping () -> Void) {
        guard let saved = UserDefaults.standard.array(forKey: Self.cookieStorageKey) as? [[String: Any]] else { completion(); return }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        for d in saved {
            guard let n = d["name"] as? String, let v = d["value"] as? String, let dom = d["domain"] as? String, let p = d["path"] as? String else { continue }
            if let c = HTTPCookie(properties: [.domain: dom, .path: p, .name: n, .value: v, .secure: "TRUE"]) {
                group.enter(); store.setCookie(c) { group.leave() }
            }
        }
        group.notify(queue: .main) { completion() }
    }
    
    func reloadPage() { if let url = URL(string: "https://gemini.google.com/app") { webView.load(URLRequest(url: url)) } }
    
    func checkLoginStatus() {
        let js = "window.__fetchBridge ? window.__fetchBridge.checkLogin() : false;"
        webView.evaluateJavaScript(js) { [weak self] result, error in
            DispatchQueue.main.async {
                if let loggedIn = result as? Bool {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.isReady = true; self?.checkLoginStatus() }
    }
    
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "geminiBridge", let body = message.body as? [String: Any] else { return }
        let type = body["type"] as? String ?? ""
        
        switch type {
        case "LOG":
            print("🖥️ [JS] \(body["message"] as? String ?? "")")
        case "GEMINI_RESPONSE":
            let content = body["content"] as? String ?? ""
            DispatchQueue.main.async { [weak self] in
                if let callback = self?.responseCallback {
                    callback(content.isEmpty ? "Error: Empty response" : content)
                    self?.responseCallback = nil
                    
                    if !content.isEmpty && !content.hasPrefix("Error:") { 
                        GeminiLinkLogic.shared.processResponse(content) 
                    }
                }
            }
        case "LOGIN_STATUS":
            let loggedIn = body["loggedIn"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in self?.isLoggedIn = loggedIn; self?.connectionStatus = loggedIn ? "🟢 Connected" : "🔴 Need Login" }
        default: break
        }
    }
}

// MARK: - Injected Scripts (V23 - Strict State-Sync)
extension GeminiWebManager {
    static let fingerprintMaskScript = """
    (function() {
        if (navigator.webdriver) { delete navigator.webdriver; }
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined, configurable: true });
    })();
    """
    
    static let injectedScript = """
    (function() {
        console.log("🚀 Bridge v23 (Strict State-Sync) Initializing...");
        
        window.__fetchBridge = {
            log: function(msg) { this.postToSwift({ type: 'LOG', message: msg }); },

            sendPromptStrict: function(text, id) {
                this.log("Step 1: Preparing to send...");
                this.lastSentText = text.trim();
                
                // 1. 记录初始状态 (关键：记录当前有多少个气泡)
                this.initialModelCount = document.querySelectorAll('div[data-message-author-role="model"]').length;
                this.initialUserCount = document.querySelectorAll('div[data-message-author-role="user"]').length;
                
                const input = document.querySelector('div[contenteditable="true"]');
                if (!input) {
                    this.finish(id, "error", "Error: Input box not found (DOM Changed?)");
                    return;
                }
                
                // 2. 暴力写入 (清除 -> 写入 -> 事件)
                input.focus();
                document.execCommand('selectAll', false, null);
                document.execCommand('delete', false, null);
                input.textContent = text; 
                input.dispatchEvent(new Event('input', { bubbles: true }));
                
                // 3. 点击发送 & 验证发送是否成功
                setTimeout(() => {
                    const sendBtn = document.querySelector('button[aria-label*="Send"], button[class*="send-button"]');
                    if (sendBtn) {
                        sendBtn.click();
                        this.log("👆 Clicked Send Button");
                    } else {
                        const enter = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, keyCode: 13, key: 'Enter' });
                        input.dispatchEvent(enter);
                        this.log("⌨️ Hit Enter");
                    }
                    
                    // 🚨 关键修复：发送验证 (3秒后检查用户气泡是否增加)
                    setTimeout(() => {
                        const newUserCount = document.querySelectorAll('div[data-message-author-role="user"]').length;
                        if (newUserCount <= this.initialUserCount) {
                            // 发送失败！不要干等50秒，直接报错，防止 App 挂起或抓取旧数据
                            this.log("❌ Critical: Message NOT sent (User bubble count did not increase)");
                            this.finish(id, "error", "Error: Send failed. Input stuck.");
                        } else {
                            this.log("✅ Message sent verified. Waiting for reply...");
                            this.startPolling(id);
                        }
                    }, 3000);
                    
                }, 800);
            },
            
            startPolling: function(id) {
                const self = this;
                if (this.pollingTimer) clearInterval(this.pollingTimer);
                
                let stableCount = 0;
                let lastTextLen = 0;
                const startTime = Date.now();
                
                this.pollingTimer = setInterval(() => {
                    // 超时由 Swift 控制，JS 侧只需负责检测完成
                    if (Date.now() - startTime > 60000) return; 
                    
                    const modelBubbles = document.querySelectorAll('div[data-message-author-role="model"]');
                    const currentCount = modelBubbles.length;
                    
                    // 只有当 Model 气泡真的增加了，才认为是新回复
                    if (currentCount > self.initialModelCount) {
                        const lastBubble = modelBubbles[currentCount - 1];
                        const text = lastBubble.innerText.trim();
                        
                        // 垃圾过滤
                        if (text.length < 1) return;
                        if (text === "Thinking...") return; 
                        
                        // 稳定性检查 (防止只抓到一半)
                        if (text.length === lastTextLen) {
                            stableCount++;
                            if (stableCount > 4) { // 2s 稳定 (增加从容度，防止截断)
                                self.finish(id, "completed");
                            }
                        } else {
                            stableCount = 0;
                            lastTextLen = text.length;
                        }
                    }
                }, 500);
            },
            
            finish: function(id, reason, errorOverride) {
                if (this.pollingTimer) { clearInterval(this.pollingTimer); this.pollingTimer = null; }
                this.log("Step 3: Finishing via " + reason);
                
                if (errorOverride) {
                     this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: errorOverride });
                     return;
                }
                
                const text = this.extractStrict();
                this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: text });
            },
            
            forceFinish: function(id) {
                // 强制抓取时，必须检查是否真的有新内容，否则报错
                const currentCount = document.querySelectorAll('div[data-message-author-role="model"]').length;
                // 如果气泡没增加，说明超时了也没生成出来，必须返回 Error
                if (currentCount <= this.initialModelCount) {
                     this.finish(id, "timeout_empty", "Error: Timeout - No new response generated.");
                } else {
                     this.finish(id, "force_scrape");
                }
            },
            
            extractStrict: function() {
                const modelBubbles = document.querySelectorAll('div[data-message-author-role="model"]');
                
                // 再次双重检查数量
                if (modelBubbles.length <= this.initialModelCount) {
                    return "Error: No new response found (Count mismatch)";
                }
                
                const t = modelBubbles[modelBubbles.length - 1].innerText.trim();
                
                // 防止把用户的输入当成模型输出 (Echo 检查)
                if (this.lastSentText && t === this.lastSentText) {
                    return "Error: Echo detected (Scraper grabbed user text)";
                }
                
                return t;
            },
            
            checkLogin: function() {
                const loggedIn = window.location.href.includes('gemini.google.com') && !!document.querySelector('div[contenteditable="true"]');
                this.postToSwift({ type: 'LOGIN_STATUS', loggedIn: loggedIn });
                return loggedIn;
            },
            postToSwift: function(data) { if (window.webkit) window.webkit.messageHandlers.geminiBridge.postMessage(data); }
        };
        setTimeout(() => window.__fetchBridge.checkLogin(), 2000);
    })();
    """
}
