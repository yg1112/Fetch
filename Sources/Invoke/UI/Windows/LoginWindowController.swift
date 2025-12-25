import Cocoa
import WebKit

/// 纯 AppKit 登录窗口控制器 - 彻底解决 SwiftUI 生命周期导致的 WebKit 崩溃
/// 使用 NSWindowController 独立管理 WebView 生命周期
class LoginWindowController: NSWindowController, WKNavigationDelegate {
    static let shared = LoginWindowController()
    
    private var webView: WKWebView!
    private var hasTriggeredSuccess = false
    
    // Safari UA 策略
    private let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
    
    // Safari 精简版伪装脚本
    private static let safariStealthScript = """
    (function() {
        'use strict';
        Object.defineProperty(navigator, 'webdriver', { 
            get: () => undefined,
            configurable: true
        });
        delete navigator.webdriver;
        Object.defineProperty(navigator, 'languages', { 
            get: () => ['en-US', 'en'],
            configurable: true
        });
    })();
    """
    
    // MARK: - Init
    
    init() {
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Login to Gemini - Fetch"
        window.center()
        super.init(window: window)
        
        setupWebView()
        window.delegate = self
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    // MARK: - Setup
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "Chrome"
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // 注入伪装脚本
        let stealthScript = WKUserScript(
            source: Self.safariStealthScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(stealthScript)
        
        // 1. 初始化 WebView (Frame 设为 zero 即可，因为后面会设为 contentView)
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
        
        // 2. 设置 Safari UA (关键)
        self.webView.customUserAgent = safariUserAgent
        self.webView.allowsBackForwardNavigationGestures = true
        
        #if DEBUG
        if #available(macOS 13.3, *) {
            self.webView.isInspectable = true
        }
        #endif
        
        // 3. [关键修复] 直接设为 contentView，保证填满窗口
        self.window?.contentView = self.webView
        
        // 4. 增加加载指示器 (可选，方便调试)
        print("🌐 WebView setup complete. Ready to load.")
    }
    
    // MARK: - Public API
    
    func show() {
        self.hasTriggeredSuccess = false
        
        // 强制 Regular 策略以确保键盘可用
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
        self.window?.level = .floating
        
        // 加载登录页
        let url = URL(string: "https://accounts.google.com/ServiceLogin?continue=https://gemini.google.com/app")!
        webView.load(URLRequest(url: url))
    }
    
    // MARK: - Safe Teardown (核心修复)
    
    private func handleLoginSuccess() {
        guard !hasTriggeredSuccess else { return }
        hasTriggeredSuccess = true
        
        print("✅ Login detected. Initiating safe teardown...")
        NSSound(named: "Glass")?.play()
        
        // 1. 立即停止加载
        webView.stopLoading()
        
        // 2. 切断 Delegate 防止回调
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        
        // 3. 关键：将 WebView 从视图层级移除 (拔线)
        webView.removeFromSuperview()
        
        // 4. 关闭窗口
        self.close()
        
        // 5. 恢复菜单栏模式
        NSApp.setActivationPolicy(.accessory)
        
        // 6. 发送通知
        NotificationCenter.default.post(name: .loginSuccess, object: nil)
        
        // 7. 刷新主 WebView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            GeminiWebManager.shared.loadGemini()
        }
    }
    
    private func teardownAndClose() {
        // 安全销毁协议
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        
        self.close()
        NSApp.setActivationPolicy(.accessory)
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
        
        if let url = navigationAction.request.url?.absoluteString,
           url.contains("gemini.google.com/app") && !url.contains("signin") {
            print("✅ Login success URL detected: \(url)")
            
            // 1. 必须先告诉 WebKit "取消本次导航" (因为我们要关闭了)
            decisionHandler(.cancel)
            
            // 2. 关键修复：将销毁逻辑放入异步队列
            // 这允许当前的 WebKit 委托方法先安全退出栈帧，防止野指针崩溃
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
}

// MARK: - NSWindowDelegate

extension LoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口被用户关闭时，安全清理
        if !hasTriggeredSuccess {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
        }
        NSApp.setActivationPolicy(.accessory)
    }
}

