import Cocoa
import WebKit

// 1. 自定义 Panel 以支持键盘输入
class LoginPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class LoginWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {
    static let shared = LoginWindowController()
    
    private var webView: WKWebView!
    private var hasTriggeredSuccess = false
    
    // Safari UA 策略
    private let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
    
    init() {
        // 2. 使用 NSPanel 而不是 NSWindow
        // styleMask 必须包含 .nonactivatingPanel 以避免抢夺焦点导致的闪烁
        let panel = LoginPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Login to Gemini"
        panel.center()
        panel.level = .floating // 保证在最上层
        panel.isFloatingPanel = true
        
        super.init(window: panel)
        setupWebView()
        panel.delegate = self
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "Chrome"
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // 注入脚本 (使用 GeminiWebManager 的脚本)
        let stealthScript = WKUserScript(
            source: GeminiWebManager.fingerprintMaskScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(stealthScript)
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
        // 保持 Safari UA
        self.webView.customUserAgent = safariUserAgent
        self.webView.allowsBackForwardNavigationGestures = true
        
        #if DEBUG
        if #available(macOS 13.3, *) {
            self.webView.isInspectable = true
        }
        #endif
        
        // 3. 布局修复：使用 Auto Layout 而不是直接赋值 contentView
        // 直接赋值 contentView 在 Panel 中有时会导致布局失效
        let contentView = NSView()
        self.window?.contentView = contentView
        
        self.webView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(self.webView)
        
        NSLayoutConstraint.activate([
            self.webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            self.webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            self.webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            self.webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        
        print("🌐 WebView setup complete. Ready to load.")
    }
    
    private func clearCookiesAndCache(completion: @escaping () -> Void) {
        let dataStore = WKWebsiteDataStore.default()
        // 清理所有类型的缓存数据
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let date = Date(timeIntervalSince1970: 0)
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: date) {
            print("🧹 WebView cache and cookies cleared.")
            completion()
        }
    }
    
    func show() {
        self.hasTriggeredSuccess = false
        
        // 1. 先清理脏数据
        clearCookiesAndCache { [weak self] in
            guard let self = self else { return }
            
            // 2. 复活 WebView 逻辑 (保持不变)
            if self.webView.superview == nil {
                if let container = self.window?.contentView {
                    container.addSubview(self.webView)
                    self.webView.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        self.webView.topAnchor.constraint(equalTo: container.topAnchor),
                        self.webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                        self.webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                        self.webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
                    ])
                }
            }
            
            self.webView.navigationDelegate = self
            
            // 3. 窗口激活 (保持不变)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            self.showWindow(nil)
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.level = .floating
            
            // 4. [关键策略] 使用 YouTube 跳板登录
            // YouTube 的风控阈值较低，登录成功后 Cookie 是 Google 全域共享的
            let youtubeLogin = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com")!
            self.webView.load(URLRequest(url: youtubeLogin))
        }
    }
    
    // MARK: - Safe Teardown
    private func handleLoginSuccess() {
        guard !hasTriggeredSuccess else { return }
        hasTriggeredSuccess = true
        
        print("✅ Login Success")
        NSSound(named: "Glass")?.play()
        
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        self.close()
        
        NotificationCenter.default.post(name: .loginSuccess, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            GeminiWebManager.shared.loadGemini()
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        print("📍 Navigation finished: \(url)")
        
        // 检测是否已到达 Gemini 主页面（登录成功）
        if url.contains("gemini.google.com") && !url.contains("signin") && !url.contains("accounts.google") {
            // 异步执行销毁逻辑，防止 WebKit 回调时访问无效内存
            DispatchQueue.main.async { [weak self] in
                self?.handleLoginSuccess()
            }
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 如果已经触发了成功逻辑，直接取消后续请求
        if hasTriggeredSuccess {
            decisionHandler(.cancel)
            return
        }
        
        guard let urlStr = navigationAction.request.url?.absoluteString else {
            decisionHandler(.allow)
            return
        }
        
        // 1. 检测是否登录成功并跳转到了 YouTube
        if urlStr.contains("youtube.com") && !urlStr.contains("accounts.google") {
            print("✅ YouTube Login Success! Redirecting to Gemini...")
            decisionHandler(.cancel)
            
            // 跳转到 Gemini
            let geminiURL = URL(string: "https://gemini.google.com/app")!
            webView.load(URLRequest(url: geminiURL))
            return
        }
        
        // 2. 检测是否最终到达 Gemini (登录完成)
        if urlStr.contains("gemini.google.com/app") && !urlStr.contains("accounts.google") && !urlStr.contains("signin") {
            print("🎉 Gemini Loaded! Safe teardown.")
            decisionHandler(.cancel)
            DispatchQueue.main.async { [weak self] in
                self?.handleLoginSuccess()
            }
            return
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ Navigation failed: \(error.localizedDescription)")
    }
    
    // 添加错误监控
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView Load Error: \(error.localizedDescription)")
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // 窗口被用户关闭时，安全清理
        if !hasTriggeredSuccess {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
        }
        // 不再调用 setActivationPolicy
    }
}
