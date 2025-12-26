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

/// Native Gemini Bridge - v19.0 (Polling State Machine & Swift Watchdog)
/// 核心修复：
/// 1. JS 改为轮询检测文本长度变化，不再单纯依赖 Stop 按钮，解决"无反应"问题。
/// 2. Swift 增加主动超时强制抓取 (Force Scrape)，防止队列永久堵塞。
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
    
    // 超时看门狗
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
                // 状态检查
                if !self.isReady { try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) }
                
                print("🚀 [Queue] Processing Request: \(request.prompt.prefix(20))...")
                
                // 执行请求
                do {
                    let response = try await self.performActualNetworkRequest(request.prompt, model: request.model)
                    request.continuation.resume(returning: response)
                } catch {
                    print("❌ [Queue] Failed: \(error)")
                    // 如果是超时，尝试一次页面刷新，防止彻底死死
                    if let err = error as? GeminiError, case .timeout = err { 
                        await self.reloadPageAsync() 
                    }
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
        
        // 注入脚本
        let userScript = WKUserScript(source: Self.injectedScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        
        let fingerprintScript = WKUserScript(source: Self.fingerprintMaskScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(fingerprintScript)
        config.userContentController.add(self, name: "geminiBridge")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        
        // 🚨 DEBUG WINDOW (保持开启，方便你观察)
        debugWindow = NSWindow(
            contentRect: NSRect(x: 50, y: 50, width: 1000, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        debugWindow?.title = "Fetch Debugger (v19 Polling)"
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
                
                // 1. 清理旧的回调和计时器
                self.watchdogTimer?.invalidate()
                self.responseCallback = nil
                
                // 2. 设置新的回调
                self.responseCallback = { response in
                    self.watchdogTimer?.invalidate()
                    self.isProcessing = false
                    
                    if response.hasPrefix("Error:") { 
                        continuation.resume(throwing: GeminiError.responseError(response)) 
                    } else { 
                        continuation.resume(returning: response) 
                    }
                }
                
                // 3. 启动 Swift 端看门狗 (30秒强制抓取，60秒彻底超时)
                self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                    print("⏰ [Watchdog] 30s elapsed. Forcing scrape...")
                    self?.forceScrape(id: promptId)
                }
                
                // 4. 发送 JS 指令
                let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
                                      .replacingOccurrences(of: "\n", with: "\\n")
                
                let js = "window.__fetchBridge.sendPrompt(\"\(escapedText)\", \"\(promptId)\");"
                self.webView.evaluateJavaScript(js) { _, _ in }
            }
        }
    }
    
    private func forceScrape(id: String) {
        // 强制 JS 立即返回当前它能找到的最好的文本
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
    func injectRawCookies(_ c: String, completion: @escaping () -> Void) { /* Placeholder */ }
    
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
                // 只有当有回调等待时才处理，防止多次触发
                if let callback = self?.responseCallback {
                    callback(content.isEmpty ? "Error: Empty response" : content)
                    self?.responseCallback = nil // 消费掉回调
                    
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

// MARK: - Injected Scripts (V19)
extension GeminiWebManager {
    static let fingerprintMaskScript = """
    (function() {
        if (navigator.webdriver) { delete navigator.webdriver; }
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined, configurable: true });
    })();
    """
    
    static let injectedScript = """
    (function() {
        console.log("🚀 Bridge v19 (Polling Machine) Initializing...");
        
        window.__fetchBridge = {
            log: function(msg) { this.postToSwift({ type: 'LOG', message: msg }); },

            sendPrompt: function(text, id) {
                this.log("Step 1: sendPrompt: " + text.substring(0, 10) + "...");
                this.lastSentText = text.trim();
                
                const input = document.querySelector('div[contenteditable="true"]');
                if (!input) {
                    this.log("❌ Input not found");
                    this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: "Error: Input box not found." });
                    return;
                }
                
                input.focus();
                document.execCommand('selectAll', false, null);
                document.execCommand('delete', false, null);
                document.execCommand('insertText', false, text);
                
                setTimeout(() => {
                    const sendBtn = document.querySelector('button[aria-label*="Send"], button[class*="send-button"]');
                    if (sendBtn) { sendBtn.click(); } 
                    else { 
                        const enter = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, keyCode: 13, key: 'Enter' });
                        input.dispatchEvent(enter);
                    }
                    this.startPolling(id);
                }, 500);
            },
            
            // 🔄 核心：轮询状态机
            startPolling: function(id) {
                const self = this;
                if (this.pollingTimer) clearInterval(this.pollingTimer);
                
                this.log("Step 2: Start Polling for response...");
                
                let lastTextLength = 0;
                let stableCount = 0; // 连续稳定次数
                let hasStarted = false;
                let startTime = Date.now();
                
                this.pollingTimer = setInterval(() => {
                    // 1. 检查是否超时 (45s)
                    if (Date.now() - startTime > 45000) {
                        self.finish(id, "timeout");
                        return;
                    }
                    
                    // 2. 尝试获取当前的最新回复文本
                    const currentText = self.extractText();
                    const currentLen = currentText.length;
                    
                    // 3. 判断状态
                    if (currentLen > 0 && currentLen > lastTextLength) {
                        // 文本正在增长...
                        if (!hasStarted) {
                            self.log("🌊 Detected stream start (Len: " + currentLen + ")");
                            hasStarted = true;
                        }
                        lastTextLength = currentLen;
                        stableCount = 0; // 重置稳定计数器
                    } 
                    else if (hasStarted && currentLen > 0 && currentLen === lastTextLength) {
                        // 文本长度没变
                        stableCount++;
                        // self.log("Waiting for stability... " + stableCount + "/4");
                        
                        // 连续 4 次检查 (约 2 秒) 没变化，且没有 Stop 按钮，认为结束
                        const stopBtn = document.querySelector('button[aria-label*="Stop"], button[aria-label*="停止"]');
                        if (!stopBtn && stableCount >= 4) {
                            self.finish(id, "completed");
                        }
                    }
                    else if (!hasStarted) {
                        // 还没开始，检查是否有 Stop 按钮作为辅助判断
                        const stopBtn = document.querySelector('button[aria-label*="Stop"], button[aria-label*="停止"]');
                        if (stopBtn) {
                             self.log("🌊 Detected stream start via Button");
                             hasStarted = true;
                        }
                    }
                    
                }, 500); // 每 500ms 检查一次
            },
            
            finish: function(id, reason) {
                if (this.pollingTimer) {
                    clearInterval(this.pollingTimer);
                    this.pollingTimer = null;
                }
                this.log("Step 3: Finishing (" + reason + ")");
                
                let text = this.extractText();
                if (!text) text = this.extractFallback();
                
                this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: text });
            },
            
            forceFinish: function(id) {
                this.log("⚠️ FORCE SCRAPE TRIGGERED BY SWIFT");
                this.finish(id, "force_scrape");
            },
            
            extractText: function() {
                // 暴力查找最新的一条非用户消息
                const candidates = document.querySelectorAll('.message-content, .model-response, div[data-message-author-role="model"], p');
                for (let i = candidates.length - 1; i >= 0; i--) {
                    const t = candidates[i].innerText.trim();
                    if (t.length < 5) continue;
                    if (this.lastSentText && t === this.lastSentText) continue; // 防复读
                    if (t.includes('Show drafts')) continue;
                    return t; // 找到倒数第一个符合条件的，直接返回
                }
                return "";
            },
            
            extractFallback: function() {
                const full = document.body.innerText;
                const snippet = full.slice(-3000);
                if (this.lastSentText) {
                    const parts = snippet.split(this.lastSentText);
                    if (parts.length > 1) return parts[parts.length - 1].trim();
                }
                return snippet;
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
