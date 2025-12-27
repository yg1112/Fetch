import WebKit
import SwiftUI

@MainActor
class GeminiCore: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = GeminiCore()
    
    // 状态回调
    var onStatusChange: ((Bool) -> Void)?
    
    private var webView: WKWebView!
    private var window: NSWindow?
    private var streamContinuation: CheckedContinuation<String, Error>?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "Safari" // 伪装
        
        // 注入核心 JS (轮询逻辑)
        let js = """
        window.activeStream = null;
        window.bridge = {
            post: (t, d) => window.webkit.messageHandlers.core.postMessage({t:t, d:d}),
            generate: (p) => {
                // 1. 极速轮询找输入框
                let i = 0;
                const timer = setInterval(() => {
                    const box = document.querySelector('div[contenteditable="true"]');
                    if(box) {
                        clearInterval(timer);
                        box.focus(); document.execCommand('insertText', false, p);
                        setTimeout(() => {
                            const btn = document.querySelector('button[aria-label*="Send"]');
                            if(btn) btn.click();
                            window.bridge.watch();
                        }, 100);
                    }
                    if(i++ > 50) { clearInterval(timer); window.bridge.post('ERR', 'No Input'); }
                }, 100);
            },
            watch: () => {
                // 2. 监听输出
                let lastLen = 0;
                const obs = new MutationObserver(() => {
                    const els = document.querySelectorAll('.model-response-text');
                    if(els.length === 0) return;
                    const txt = els[els.length-1].innerText;
                    if(txt.length > lastLen) {
                        window.bridge.post('CHK', txt.substring(lastLen));
                        lastLen = txt.length;
                    }
                    // 检测生成结束 (简单的停止按钮消失检测)
                    // ... (可添加更复杂的结束检测逻辑)
                });
                obs.observe(document.body, {subtree:true, childList:true, characterData:true});
            }
        };
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.add(self, name: "core")
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // 关键：复用同一个 UA，避免被 Google 风控踢出
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    }
    
    func load() {
        // 直接加载 Gemini，如果 Cookie 还在，就自动登录了
        webView.load(URLRequest(url: URL(string: "https://gemini.google.com/app")!))
    }
    
    // MARK: - 窗口逻辑 (按需显示)
    
    func showDebugWindow() {
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
            window?.title = "Gemini Bridge"
            window?.center()
            window?.isReleasedWhenClosed = false // 关闭只是隐藏
        }
        // 关键：把 WebView 拍到窗口上
        window?.contentView = webView 
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - 业务逻辑 (Ask)
    
    func ask(_ prompt: String) async throws -> AsyncStream<String> {
        // 确保已登录
        guard let url = webView.url?.absoluteString, url.contains("gemini.google.com") else {
            showDebugWindow() // 强制弹窗登录
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please login"])
        }
        
        // 简单的 Prompt 转义
        let safePrompt = prompt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        
        return AsyncStream { continuation in
            // JS 调用
            webView.evaluateJavaScript("window.bridge.generate(\"\(safePrompt)\")")
            
            // 这里我们需要一种机制把 scriptMessageHandler 的回调转给 stream
            // 简单起见，可以用一个临时闭包变量 (生产环境可以用 Actor 或 Map 管理多个请求)
            self.streamHandler = { type, data in
                if type == "CHK" { continuation.yield(data) }
                else if type == "ERR" { continuation.finish(); } // Handle error
                // 需要完善 DONE 信号
            }
        }
    }
    
    private var streamHandler: ((String, String) -> Void)?
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["t"] as? String,
              let data = body["d"] as? String else { return }
        
        if type == "LOGIN_STATUS" {
            // 可以在 JS 里检测是否在登录页，传回 Swift 更新状态栏
        } else {
            streamHandler?(type, data)
        }
    }
    
    // MARK: - Navigation Delegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        // 简单的状态判断：是在 App 里还是在 登录页
        let isLoggedIn = url.contains("gemini.google.com/app")
        onStatusChange?(isLoggedIn)
    }
}