import Foundation
import WebKit
import Combine

/// Native Gemini Bridge - 替代 Chrome Extension + proxy.py
/// 使用 WKWebView 直接与 gemini.google.com 通信
class GeminiWebManager: NSObject, ObservableObject {
    static let shared = GeminiWebManager()
    
    // MARK: - Published State
    @Published var isReady = false
    @Published var isLoggedIn = false
    @Published var isProcessing = false
    @Published var connectionStatus = "Initializing..."
    @Published var lastResponse: String = ""
    
    // MARK: - WebView
    private(set) var webView: WKWebView!
    private var pendingPromptId: String?
    private var responseCallback: ((String) -> Void)?
    
    // 最新 Chrome Mac User-Agent (深度伪装 - 不含 wv/Mobile 关键字)
    private let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    
    override init() {
        super.init()
        setupWebView()
    }
    
    // MARK: - Setup
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
        // 持久化 Cookie (登录态)
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // 深度伪装：设置 Application Name 为 Chrome
        config.applicationNameForUserAgent = "Chrome/131.0.0.0"
        
        // 启用开发者工具 (有时能绕过简单检查)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // 允许 JavaScript
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // 注入脚本 (包含浏览器特征伪装)
        let userScript = WKUserScript(
            source: Self.injectedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)
        
        // 注入浏览器指纹伪装脚本 (在 document start 时执行)
        let fingerprintScript = WKUserScript(
            source: Self.fingerprintMaskScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(fingerprintScript)
        
        // Swift <-> JS 消息通道
        config.userContentController.add(self, name: "geminiBridge")
        
        // 创建隐藏的 WebView (1x1)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.customUserAgent = chromeUserAgent
        webView.navigationDelegate = self
        
        // 允许检查元素 (调试用)
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif
        
        // 先恢复持久化的 Cookie，再加载 Gemini
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
    
    /// 发送 Prompt 给 Gemini，异步返回响应
    func sendPrompt(_ text: String, model: String = "default", completion: @escaping (String) -> Void) {
        guard isReady && isLoggedIn else {
            completion("Error: Gemini not ready or not logged in")
            return
        }
        
        isProcessing = true
        pendingPromptId = UUID().uuidString
        responseCallback = completion
        
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        
        let js = """
        window.__fetchBridge.sendPrompt("\(escapedText)", "\(model)", "\(pendingPromptId!)");
        """
        
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("❌ JS Error: \(error)")
                self.isProcessing = false
                completion("Error: \(error.localizedDescription)")
            }
        }
    }
    
    /// 检查登录状态
    func checkLoginStatus() {
        let js = "window.__fetchBridge ? window.__fetchBridge.checkLogin() : false;"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                self?.isLoggedIn = (result as? Bool) ?? false
                self?.connectionStatus = self?.isLoggedIn == true ? "🟢 Connected" : "🔴 Need Login"
            }
        }
    }
    
    // MARK: - Cookie Injection & Persistence
    
    /// Cookie 持久化存储的 UserDefaults Key
    private static let cookieStorageKey = "FetchGeminiCookies"
    
    /// 注入原始 Cookie 字符串 (从 Chrome 控制台 document.cookie 获取)
    func injectRawCookies(_ cookieString: String, completion: @escaping () -> Void) {
        let dataStore = WKWebsiteDataStore.default()
        let cookieStore = dataStore.httpCookieStore
        
        // 解析原始 Cookie 字符串 (key=value; key=value)
        let components = cookieString.components(separatedBy: ";")
        
        let group = DispatchGroup()
        var injectedCount = 0
        var cookiesToSave: [[String: Any]] = []
        
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                
                // 构建 HTTPCookie - Domain 必须设置正确
                let properties: [HTTPCookiePropertyKey: Any] = [
                    .domain: ".google.com",
                    .path: "/",
                    .name: name,
                    .value: value,
                    .secure: "TRUE",
                    .expires: Date(timeIntervalSinceNow: 31536000) // 1年后过期
                ]
                
                if let cookie = HTTPCookie(properties: properties) {
                    group.enter()
                    cookieStore.setCookie(cookie) {
                        injectedCount += 1
                        group.leave()
                    }
                    
                    // 保存到持久化存储
                    cookiesToSave.append([
                        "name": name,
                        "value": value,
                        "domain": ".google.com",
                        "path": "/",
                        "expires": Date(timeIntervalSinceNow: 31536000).timeIntervalSince1970
                    ])
                }
            }
        }
        
        // 完成后重新加载页面
        group.notify(queue: .main) { [weak self] in
            print("🍪 Injected \(injectedCount) cookies successfully")
            
            // 持久化保存到 UserDefaults
            UserDefaults.standard.set(cookiesToSave, forKey: Self.cookieStorageKey)
            print("💾 Saved \(cookiesToSave.count) cookies to persistent storage")
            
            self?.reloadPage()
            completion()
        }
    }
    
    /// 从持久化存储恢复 Cookie (App 启动时调用)
    func restoreCookiesFromStorage(completion: @escaping () -> Void) {
        guard let savedCookies = UserDefaults.standard.array(forKey: Self.cookieStorageKey) as? [[String: Any]],
              !savedCookies.isEmpty else {
            print("📭 No saved cookies found")
            completion()
            return
        }
        
        let dataStore = WKWebsiteDataStore.default()
        let cookieStore = dataStore.httpCookieStore
        let group = DispatchGroup()
        var restoredCount = 0
        
        for cookieData in savedCookies {
            guard let name = cookieData["name"] as? String,
                  let value = cookieData["value"] as? String,
                  let domain = cookieData["domain"] as? String,
                  let path = cookieData["path"] as? String,
                  let expiresTimestamp = cookieData["expires"] as? TimeInterval else {
                continue
            }
            
            // 检查是否过期
            if Date(timeIntervalSince1970: expiresTimestamp) < Date() {
                continue
            }
            
            let properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value,
                .secure: "TRUE",
                .expires: Date(timeIntervalSince1970: expiresTimestamp)
            ]
            
            if let cookie = HTTPCookie(properties: properties) {
                group.enter()
                cookieStore.setCookie(cookie) {
                    restoredCount += 1
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            print("🔄 Restored \(restoredCount) cookies from storage")
            completion()
        }
    }
    
    /// 重新加载 Gemini 页面
    func reloadPage() {
        connectionStatus = "Reloading..."
        if let url = URL(string: "https://gemini.google.com/app") {
            webView.load(URLRequest(url: url))
        }
    }
    
    /// 清除所有 Cookie (用于登出)
    func clearCookies(completion: @escaping () -> Void) {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let googleRecords = records.filter { $0.displayName.contains("google") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: googleRecords) {
                print("🗑️ Cleared Google cookies")
                completion()
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension GeminiWebManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ Page loaded: \(webView.url?.absoluteString ?? "")")
        
        // 等待页面完全渲染
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
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
            let id = body["id"] as? String ?? ""
            
            print("📥 Response received (id: \(id), length: \(content.count))")
            
            DispatchQueue.main.async { [weak self] in
                self?.isProcessing = false
                self?.lastResponse = content
                self?.responseCallback?(content)
                self?.responseCallback = nil
            }
            
        case "LOGIN_STATUS":
            let loggedIn = body["loggedIn"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in
                self?.isLoggedIn = loggedIn
                self?.connectionStatus = loggedIn ? "🟢 Connected" : "🔴 Need Login"
            }
            
        case "STATUS":
            let status = body["status"] as? String ?? ""
            print("📊 Bridge Status: \(status)")
            
        default:
            print("⚠️ Unknown message type: \(type)")
        }
    }
}

// MARK: - Injected JavaScript

extension GeminiWebManager {
    /// 浏览器指纹伪装脚本 (在页面加载前执行)
    static let fingerprintMaskScript = """
    (function() {
        // 伪装 Chrome 浏览器特征
        Object.defineProperty(navigator, 'webdriver', { get: () => false });
        Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
        Object.defineProperty(navigator, 'plugins', { get: () => [
            { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer' },
            { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai' },
            { name: 'Native Client', filename: 'internal-nacl-plugin' }
        ]});
        
        // 伪装 Chrome 特有属性
        window.chrome = {
            runtime: {},
            loadTimes: function() {},
            csi: function() {},
            app: {}
        };
        
        // 隐藏 WKWebView 特征 (重要!)
        // 注意：我们不能删除 window.webkit，因为我们需要它来通信
        // 但可以在 Google 检测前让它看起来不像 WKWebView
        
        // 伪装 WebGL 渲染器
        const getParameterProxy = WebGLRenderingContext.prototype.getParameter;
        WebGLRenderingContext.prototype.getParameter = function(param) {
            if (param === 37445) return 'Intel Inc.';
            if (param === 37446) return 'Intel Iris OpenGL Engine';
            return getParameterProxy.call(this, param);
        };
        
        console.log('🎭 Fingerprint mask applied');
    })();
    """
    
    /// 注入到 Gemini 页面的 JavaScript (移植自 content.js v7.3)
    static let injectedScript = """
    (function() {
        console.log("🚀 Fetch Bridge v8.0 (Native) Initializing...");
        
        // 全局桥接对象
        window.__fetchBridge = {
            pendingId: null,
            
            // 发送 Prompt
            sendPrompt: async function(text, model, id) {
                this.pendingId = id;
                
                try {
                    // 模型切换 (如果需要)
                    if (model && model !== 'default') {
                        await this.switchModel(model);
                    }
                    
                    // 找到输入框
                    const inputArea = await this.waitForElement([
                        'div[contenteditable="true"]',
                        'rich-textarea div p',
                        '[role="textbox"]'
                    ]);
                    
                    inputArea.focus();
                    await this.sleep(100);
                    
                    // 清空并输入
                    document.execCommand('selectAll', false, null);
                    document.execCommand('delete', false, null);
                    await this.sleep(50);
                    
                    // 拟人化逐字输入
                    for (const char of text) {
                        document.execCommand('insertText', false, char);
                        await this.sleep(Math.random() * 15 + 5);
                    }
                    
                    await this.sleep(300);
                    
                    // 发送
                    const sendBtn = document.querySelector('button[aria-label*="Send"], button[aria-label*="发送"], .send-button');
                    if (sendBtn && !sendBtn.disabled) {
                        sendBtn.click();
                    } else {
                        inputArea.dispatchEvent(new KeyboardEvent('keydown', {
                            keyCode: 13, key: 'Enter', code: 'Enter', bubbles: true
                        }));
                    }
                    
                    // 等待响应
                    await this.waitForResponse(id);
                    
                } catch (e) {
                    console.error("❌ Error:", e);
                    this.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: 'Error: ' + e.message });
                }
            },
            
            // 模型切换
            switchModel: async function(targetModel) {
                const MODEL_MAP = {
                    'flash': ['Flash', 'Fast', '2.0 Flash'],
                    'pro': ['Pro', '1.5 Pro', '2.5 Pro'],
                    'thinking': ['Thinking', 'Deep Research'],
                    'advanced': ['Advanced']
                };
                
                const targetKey = Object.keys(MODEL_MAP).find(k => targetModel.toLowerCase().includes(k));
                if (!targetKey) return;
                
                const labels = MODEL_MAP[targetKey];
                
                // 找下拉按钮
                const buttons = Array.from(document.querySelectorAll('button, [role="button"]'));
                const dropdown = buttons.find(btn => {
                    const text = (btn.innerText || "").trim();
                    return (text.includes("Gemini") || text.includes("Flash") || text.includes("Pro")) && text.length < 30;
                });
                
                if (!dropdown) return;
                
                dropdown.click();
                await this.sleep(800);
                
                const options = Array.from(document.querySelectorAll('[role="menuitem"], [role="option"], mat-option'));
                const target = options.find(opt => labels.some(l => opt.innerText.toLowerCase().includes(l.toLowerCase())));
                
                if (target) {
                    target.click();
                    await this.sleep(500);
                    
                    // 确认弹窗
                    const confirm = Array.from(document.querySelectorAll('button')).find(b => 
                        b.innerText.toLowerCase().includes('switch') || b.innerText.toLowerCase().includes('ok')
                    );
                    if (confirm) confirm.click();
                    
                    await this.sleep(1000);
                }
            },
            
            // 等待响应完成
            waitForResponse: function(id) {
                return new Promise((resolve) => {
                    let hasStarted = false;
                    let silenceTimer = null;
                    const startTime = Date.now();
                    const self = this;
                    
                    const observer = new MutationObserver(() => {
                        const stopBtn = document.querySelector('button[aria-label*="Stop"]');
                        
                        if (stopBtn) {
                            hasStarted = true;
                            if (silenceTimer) { clearTimeout(silenceTimer); silenceTimer = null; }
                        } else if (hasStarted) {
                            if (!silenceTimer) {
                                silenceTimer = setTimeout(() => finish(), 1500);
                            }
                        } else if (Date.now() - startTime > 15000) {
                            observer.disconnect();
                            self.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: 'Error: Timeout' });
                            resolve();
                        }
                    });
                    
                    const finish = () => {
                        observer.disconnect();
                        
                        let text = "";
                        const responses = document.querySelectorAll('model-response');
                        if (responses.length > 0) {
                            const last = responses[responses.length - 1];
                            const md = last.querySelector('.markdown');
                            text = md ? md.textContent : last.innerText;
                            text = text.replace(/Show thinking/g, '').replace(/Gemini can make mistakes.*$/gim, '').trim();
                        }
                        
                        self.postToSwift({ type: 'GEMINI_RESPONSE', id: id, content: text || 'Error: No response' });
                        resolve();
                    };
                    
                    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
                    setTimeout(() => { observer.disconnect(); if (hasStarted) finish(); else resolve(); }, 60000);
                });
            },
            
            // 检查登录状态
            checkLogin: function() {
                const loggedIn = !document.querySelector('a[href*="accounts.google.com"]');
                this.postToSwift({ type: 'LOGIN_STATUS', loggedIn: loggedIn });
                return loggedIn;
            },
            
            // 发送消息到 Swift
            postToSwift: function(data) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.geminiBridge) {
                    window.webkit.messageHandlers.geminiBridge.postMessage(data);
                }
            },
            
            // 工具函数
            sleep: function(ms) { return new Promise(r => setTimeout(r, ms)); },
            
            waitForElement: async function(selectors, timeout = 5000) {
                const start = Date.now();
                while (Date.now() - start < timeout) {
                    for (const sel of selectors) {
                        const el = document.querySelector(sel);
                        if (el) return el;
                    }
                    await this.sleep(100);
                }
                throw new Error("Element not found");
            }
        };
        
        // 初始化检查
        setTimeout(() => {
            window.__fetchBridge.checkLogin();
            window.__fetchBridge.postToSwift({ type: 'STATUS', status: 'ready' });
        }, 2000);
        
        console.log("✅ Fetch Bridge Ready");
    })();
    """
}

