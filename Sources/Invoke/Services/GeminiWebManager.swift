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

/// Native Gemini Bridge - v28.0 (MutationObserver & Event Driven)
/// 核心升级：
/// 1. 弃用 Polling (轮询)，启用 MutationObserver (变动观察者)。
/// 2. 原理：监听 DOM 树的每一次微小变动。只有当变动完全停止 (Silence) 超过阈值时，才认定为响应结束。
/// 3. 这是浏览器底层最本质的"渲染感知"方式，比时间猜测准确度高 100倍。
@MainActor
class GeminiWebManager: NSObject, ObservableObject {
    static let shared = GeminiWebManager()
    
    @Published var isReady = false
    @Published var isLoggedIn = false
    @Published var isProcessing = false
    @Published var connectionStatus = "Initializing..."
    
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
        Task { @MainActor in
            debugWindow?.close()
        }
        watchdogTimer?.invalidate()
    }

    private func startRequestLoop() {
        let (stream, continuation) = AsyncStream<PendingRequest>.makeStream()
        self.requestStream = continuation
        
        self.requestTask = Task {
            for await request in stream {
                while !self.isReady { try? await Task.sleep(nanoseconds: 500_000_000) }
                
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
        
        debugWindow = NSWindow(
            contentRect: NSRect(x: 50, y: 50, width: 1100, height: 850),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        debugWindow?.title = "Fetch Debugger (v28 Mutation Engine)"
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { continuation.resume() }
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
                
                // 90秒兜底，防止 MutationObserver 彻底死锁（虽然极罕见）
                self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: false) { [weak self] _ in
                    print("⏰ Timeout. Force scrape...")
                    Task { @MainActor in
                        self?.forceScrape(id: promptId)
                    }
                }
                
                let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
                                      .replacingOccurrences(of: "\n", with: "\\n")
                
                let js = "window.__fetchBridge.sendPromptV28(\"\(escapedText)\", \"\(promptId)\");"
                self.webView.evaluateJavaScript(js) { _, _ in }
            }
        }
    }
    
    private func forceScrape(id: String) {
        let js = "window.__fetchBridge.forceFinish('\(id)');"
        webView.evaluateJavaScript(js, completionHandler: nil)
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
    
    func injectRawCookies(_ cookieString: String, completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        
        // 解析 cookie 字符串（支持多种格式）
        let cookies = parseCookieString(cookieString)
        
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) {
                group.leave()
            }
        }
        
        // 保存到 UserDefaults
        let cookieData = cookies.compactMap { cookie -> [String: Any]? in
            guard let properties = cookie.properties else { return nil }
            return [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
        }
        UserDefaults.standard.set(cookieData, forKey: Self.cookieStorageKey)
        
        group.notify(queue: .main) {
            // 重新加载页面以应用 cookies
            self.reloadPage()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                completion()
            }
        }
    }
    
    private func parseCookieString(_ cookieString: String) -> [HTTPCookie] {
        var cookies: [HTTPCookie] = []
        
        // 尝试解析 JSON 格式
        if let jsonData = cookieString.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            for item in jsonArray {
                if let cookie = parseCookieDict(item) {
                    cookies.append(cookie)
                }
            }
            return cookies
        }
        
        // 尝试解析 Netscape 格式或简单格式
        let lines = cookieString.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // 尝试解析 "name=value; domain=.example.com; path=/"
            let parts = trimmed.components(separatedBy: ";")
            guard let firstPart = parts.first,
                  let equalIndex = firstPart.firstIndex(of: "=") else { continue }
            
            let name = String(firstPart[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(firstPart[firstPart.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
            
            var domain = ".google.com"
            var path = "/"
            
            for part in parts.dropFirst() {
                let keyValue = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if keyValue.count == 2 {
                    let key = keyValue[0].lowercased()
                    let val = keyValue[1].trimmingCharacters(in: .whitespaces)
                    
                    if key == "domain" {
                        domain = val
                    } else if key == "path" {
                        path = val
                    }
                }
            }
            
            if let cookie = HTTPCookie(properties: [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value,
                .secure: "TRUE"
            ]) {
                cookies.append(cookie)
            }
        }
        
        return cookies
    }
    
    private func parseCookieDict(_ dict: [String: Any]) -> HTTPCookie? {
        guard let name = dict["name"] as? String,
              let value = dict["value"] as? String else { return nil }
        
        let domain = dict["domain"] as? String ?? ".google.com"
        let path = dict["path"] as? String ?? "/"
        
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value
        ]
        
        if let secure = dict["secure"] as? Bool, secure {
            properties[.secure] = "TRUE"
        }
        
        return HTTPCookie(properties: properties)
    }
    
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in 
            self?.isReady = true
            self?.checkLoginStatus() 
        }
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

// MARK: - Injected Scripts (V28 - Mutation Engine)
extension GeminiWebManager {
    static let fingerprintMaskScript = """
    (function() {
        if (navigator.webdriver) { delete navigator.webdriver; }
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined, configurable: true });
    })();
    """
    
    static let injectedScript = """
    (function() {
        console.log("🚀 Bridge v28 (Mutation Engine) Initializing...");
        
        window.__fetchBridge = {
            log: function(msg) { this.postToSwift({ type: 'LOG', message: msg }); },
            
            // 核心变量
            observer: null,
            silenceTimer: null,
            preSendLength: 0,
            lastSentText: "",

            sendPromptV28: function(text, id) {
                this.log("Step 1: Snapshot & Prepare...");
                this.lastSentText = text.trim();
                
                // 1. 全量快照
                const container = document.querySelector('main') || document.body;
                this.preSendLength = container.innerText.length;
                
                const input = document.querySelector('div[contenteditable="true"]');
                if (!input) {
                    this.finish(id, "error", "Error: Input box not found");
                    return;
                }
                
                // 2. 强健输入 (Robust Input)
                input.focus();
                document.execCommand('selectAll', false, null);
                document.execCommand('delete', false, null);
                document.execCommand('insertText', false, text);
                
                // 3. 关闭弹窗 (Escape)
                input.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, keyCode: 27, key: 'Escape' }));
                
                // 4. 发送动作
                setTimeout(() => {
                    const sendBtn = document.querySelector('button[aria-label*="Send"], button[class*="send-button"]');
                    if (sendBtn && !sendBtn.disabled) {
                        sendBtn.click();
                        this.log("👆 Clicked Send Button");
                    } else {
                        const enter = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, keyCode: 13, key: 'Enter' });
                        input.dispatchEvent(enter);
                        this.log("⌨️ Hit Enter");
                    }
                    
                    // 5. 启动 MutationObserver 引擎
                    this.startMutationEngine(id);
                    
                }, 500);
            },
            
            startMutationEngine: function(id) {
                const self = this;
                const container = document.querySelector('main') || document.body;
                
                // 清理旧的
                if (this.observer) this.observer.disconnect();
                if (this.silenceTimer) clearTimeout(this.silenceTimer);
                
                this.log("⚡️ Mutation Engine Started. Waiting for activity...");
                
                // 定义观察者：只要有任何风吹草动 (childList, characterData, subtree)
                this.observer = new MutationObserver((mutations) => {
                    // 只要 DOM 变了，说明还没停，重置静默计时器
                    if (self.silenceTimer) clearTimeout(self.silenceTimer);
                    
                    // 设定静默阈值：1.5秒无变动 = 结束
                    self.silenceTimer = setTimeout(() => {
                        self.checkCompletion(id);
                    }, 1500);
                });
                
                // 开始监听
                this.observer.observe(container, {
                    childList: true,
                    subtree: true,
                    characterData: true
                });
                
                // 初始启动一个 timer，防止甚至连一开始的变动都没有
                self.silenceTimer = setTimeout(() => {
                    self.checkCompletion(id);
                }, 5000); // 宽容一点给它启动时间
            },
            
            checkCompletion: function(id) {
                const container = document.querySelector('main') || document.body;
                const currentLength = container.innerText.length;
                
                // 计算差量
                // 期望：全量长度 应该 显著大于 发送前长度
                // 阈值设为 lastSentText.length + 10，确保不仅仅是用户的话上屏了，而是有新回复
                if (currentLength > (this.preSendLength + this.lastSentText.length + 5)) {
                    
                    this.log("✅ Silence Detected & Length increased. Extracting...");
                    
                    // 提取新内容
                    let newContent = container.innerText.substring(this.preSendLength);
                    
                    // 再次清洗：去掉用户自己的话
                    if (newContent.includes(this.lastSentText)) {
                        const index = newContent.lastIndexOf(this.lastSentText);
                        if (index !== -1) {
                            newContent = newContent.substring(index + this.lastSentText.length);
                        }
                    }
                    
                    newContent = newContent.trim();
                    
                    if (newContent.length > 0 && newContent !== "Thinking...") {
                        // 成功！
                        if (this.observer) this.observer.disconnect();
                        this.finish(id, newContent);
                        return;
                    }
                }
                
                // 如果到了这里，说明虽然静默了，但没拿到有效内容 (或者还在 Thinking...)
                // 此时不应该结束，应该继续监听 (除非真的超时太久，由 Swift 控制)
                this.log("⚠️ Silence detected but no meaningful content yet. Resuming watch...");
            },
            
            finish: function(id, content, errorOverride) {
                if (this.observer) { this.observer.disconnect(); this.observer = null; }
                if (this.silenceTimer) { clearTimeout(this.silenceTimer); this.silenceTimer = null; }
                
                this.log("Step 3: Finishing. Content len: " + (content ? content.length : 0));
                
                if (errorOverride) {
                     this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: errorOverride });
                } else {
                     this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: content });
                }
            },
            
            forceFinish: function(id) {
                this.finish(id, "Error: Timeout (Force Finish)", "Error: Timeout");
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
