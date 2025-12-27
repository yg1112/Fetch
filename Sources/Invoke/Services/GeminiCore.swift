import WebKit
import Cocoa

enum CoreState { case initializing, needsLogin, ready }

@MainActor
class GeminiCore: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = GeminiCore()
    
    var onStateChange: ((CoreState) -> Void)?
    private var webView: WKWebView!
    private var window: NSWindow?
    
    // 用于流式传输的 Continuation
    private var activeContinuation: AsyncStream<String>.Continuation?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
        // Woz 的魔法脚本：极其稳健的注入
        // 我们不猜时间，我们监听 DOM。
        let js = """
        window.bridge = {
            log: (msg) => window.webkit.messageHandlers.core.postMessage({t:'LOG', d:msg}),
            stream: (txt) => window.webkit.messageHandlers.core.postMessage({t:'TXT', d:txt}),
            
            // 动作：点击【新对话】按钮
            reset: () => {
                // 1. 查找侧边栏的 "New chat" 按钮
                // 注意：Selector 可能会变，我们要找得聪明点
                const buttons = Array.from(document.querySelectorAll('span, div, a'));
                const newChatBtn = buttons.find(el => el.innerText === 'New chat' || el.innerText === 'New conversation');
                
                if (newChatBtn) {
                    newChatBtn.click();
                    return true;
                }
                
                // 备选：直接访问 URL (会触发页面加载，作为兜底)
                // window.location.href = 'https://gemini.google.com/app'; 
                return false;
            },
            
            // 核心任务：输入 Prompt 并点击发送
            submit: (p) => {
                const tryClick = () => {
                    const box = document.querySelector('div[contenteditable="true"]');
                    if(!box) return false;
                    box.focus();
                    // 清空当前框内残留文本 (虽然 Reset 后应该为空)
                    document.execCommand('selectAll', false, null);
                    document.execCommand('delete', false, null);
                    
                    // 粘贴新内容
                    document.execCommand('insertText', false, p);
                    
                    // 等待发送按钮变绿
                    setTimeout(() => {
                        const btn = document.querySelector('button[aria-label*="Send"]');
                        if(btn) { btn.click(); window.bridge.watch(); }
                        else { 
                            // 兜底：模拟回车
                            box.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', keyCode:13, bubbles:true}));
                            window.bridge.watch();
                        }
                    }, 50); 
                    return true;
                };
                
                // 轮询直到输入框出现（处理页面懒加载）
                let attempts = 0;
                const timer = setInterval(() => {
                    if(tryClick() || attempts++ > 50) clearInterval(timer);
                }, 100);
            },
            
            // 核心任务：监听回答
            watch: () => {
                let lastTxt = "";
                const obs = new MutationObserver(() => {
                    // 找到最新的回答块
                    const els = document.querySelectorAll('.model-response-text');
                    if(els.length === 0) return;
                    
                    const newTxt = els[els.length-1].innerText;
                    if(newTxt.length > lastTxt.length) {
                        // 只发送增量部分，节省带宽
                        window.bridge.stream(newTxt.substring(lastTxt.length));
                        lastTxt = newTxt;
                    }
                });
                obs.observe(document.body, {subtree:true, childList:true, characterData:true});
            }
        };
        """
        
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "core")
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // 伪装成 Safari Mac，防止被 Google 降级
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15"
    }
    
    func prepare() {
        // 加载页面。如果 Cookie 还在，它会自动登录。
        webView.load(URLRequest(url: URL(string: "https://gemini.google.com/app")!))
    }
    
    // MARK: - 外部接口 (Called by LocalAPIServer)
    
    func generate(prompt: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            self.activeContinuation = continuation
            
            // 安全转义 Prompt
            let safePrompt = prompt.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "\"", with: "\\\"")
                                   .replacingOccurrences(of: "\n", with: "\\n")
            
            // 策略：每次都新建对话。保证质量，牺牲一点速度。
            let script = """
            (function() {
                // 查找并点击 "New Chat" (通常是侧边栏第一个主要按钮)
                // 这里用更底层的 DOM 触发，避免 UI 动画等待
                const buttons = Array.from(document.querySelectorAll('span, div, a'));
                const newChatBtn = buttons.find(el => el.innerText === 'New chat' || el.innerText === 'New conversation');
                if(newChatBtn) newChatBtn.click();
                
                // 给 UI 一点反应时间 (SPA 很快，300ms 足够)
                setTimeout(() => {
                    window.bridge.submit(`\(safePrompt)`);
                }, 300);
            })();
            """
            
            // 执行注入
            webView.evaluateJavaScript(script)
        }
    }
    
    // MARK: - WKScriptMessageHandler (Woz 的数据管道)
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["t"] as? String else { return }
        
        if type == "TXT", let text = body["d"] as? String {
            activeContinuation?.yield(text)
        }
    }
    
    // MARK: - 状态管理 (Jobs 的用户体验)
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        if url.contains("gemini.google.com/app") {
            print("Login Success")
            onStateChange?(.ready)
            window?.close() // 登录成功？把窗口关了。别打扰用户。
        } else if url.contains("accounts.google.com") {
            print("Needs Login")
            onStateChange?(.needsLogin)
            // 这里不自动弹窗，状态栏会变红，由用户点击弹出，没那么突兀
        }
    }
    
    func showWindow() {
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable],
                            backing: .buffered, defer: false)
            window?.center()
            window?.title = "Gemini Bridge"
            window?.contentView = webView
            window?.isReleasedWhenClosed = false
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}