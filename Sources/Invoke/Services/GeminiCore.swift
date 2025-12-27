import WebKit
import AppKit

// 定义明确的错误类型，方便调试
enum BridgeError: Error {
    case timeout
    case notLoggedIn
    case domError(String)
}

// 状态定义
enum NeuralState {
    case idle       // 空闲 (绿点)
    case thinking   // 思考中 (闪烁/大脑)
    case error      // 错误/未登录 (红点)
}

// 使用 @MainActor class 但用锁保证原子性 (模拟 Actor 行为)
@MainActor
class GeminiCore: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = GeminiCore()
    
    private var webView: WKWebView!
    private var window: NSWindow?
    private var continuation: AsyncStream<String>.Continuation?
    private let lock = NSLock() // 原子锁
    private var isProcessing = false
    
    // 状态回调
    var onStateChange: ((NeuralState) -> Void)?
    
    // 当前状态
    private var currentState: NeuralState = .error {
        didSet {
            onStateChange?(currentState)
        }
    }
    
    // MARK: - 初始化
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
        // 🌟 注入脚本：Woz 的杰作 (见下文)
        let script = WKUserScript(source: Self.injectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.add(WeakScriptMessageHandler(delegate: self), name: "core")
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // 伪装 Safari Mac，防止被 Google 降权
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        
        // 预加载
        webView.load(URLRequest(url: URL(string: "https://gemini.google.com/app")!))
    }
    
    func prepare() {
        // Already prepared in init
    }
    
    // MARK: - 核心逻辑：原子化请求
    
    func generate(prompt: String) -> AsyncStream<String> {
        return AsyncStream { cont in
            Task {
                // 1. 锁：如果正在处理，直接报错 (原子性)
                self.lock.lock()
                if self.isProcessing {
                    self.lock.unlock()
                    cont.finish()
                    return
                }
                self.isProcessing = true
                self.lock.unlock()
                
                self.continuation = cont
                self.currentState = .thinking  // 设置为思考中
                
                do {
                    // 2. 检查登录
                    let url = self.webView.url?.absoluteString ?? ""
                    guard url.contains("gemini.google.com") else {
                        self.showDebugWindow() // 没登录就弹窗
                        throw BridgeError.notLoggedIn
                    }
                    
                    // 3. 🧼 清洗：每次必须重置！(Context Window 优化)
                    // 我们不等待 Reset 完成，直接链式调用 Submit，由 JS 队列保证顺序
                    
                    // 4. 发送指令
                    let safePrompt = prompt.replacingOccurrences(of: "\\", with: "\\\\")
                                           .replacingOccurrences(of: "\"", with: "\\\"")
                                           .replacingOccurrences(of: "\n", with: "\\n")
                                           .replacingOccurrences(of: "`", with: "\\`")
                    
                    // 调用 JS: Reset -> Input -> Send
                    self.webView.evaluateJavaScript("window.bridge.processTask(`\(safePrompt)`)")
                    
                } catch {
                    print("❌ Error: \(error)")
                    cont.finish()
                    self.lock.lock()
                    self.isProcessing = false
                    self.lock.unlock()
                    self.currentState = .error  // 设置为错误
                }
            }
        }
    }
    

    
    // MARK: - 消息处理 (Woz 的数据管道)
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["t"] as? String else { return }
        
        switch type {
        case "TXT":
            if let text = body["d"] as? String {
                continuation?.yield(text)
            }
        case "DONE":
            continuation?.finish()
            lock.lock()
            isProcessing = false
            lock.unlock()
            currentState = .idle  // 设置为空闲
            print("✅ Generation Complete")
        case "ERR":
            print("🚨 JS Error: \(body["d"] ?? "")")
            continuation?.finish()
            lock.lock()
            isProcessing = false
            lock.unlock()
            currentState = .error  // 设置为错误
        default: break
        }
    }
    
    // MARK: - JS 注入代码 (The Brain)
    // 把复杂的 DOM 逻辑全部封装在 JS 里，Swift 只管发命令
    private static let injectionScript = """
    window.bridge = {
        post: (t, d) => window.webkit.messageHandlers.core.postMessage({t:t, d:d}),
        
        // 重置上下文
        resetContext: () => {
            try {
                const newChatBtn = document.querySelector('div[data-test-id="new-chat-button"]') || 
                                   document.querySelector('a[href^="/app"]');
                if(newChatBtn) {
                    newChatBtn.click();
                }
            } catch(e) {
                console.error('Reset context failed:', e);
            }
        },
        
        // 核心任务流
        processTask: async (prompt) => {
            try {
                // 1. 尝试点击 "New Chat" (重置上下文)
                const newChatBtn = document.querySelector('div[data-test-id="new-chat-button"]') || 
                                   document.querySelector('a[href^="/app"]'); // 备选策略
                if(newChatBtn) {
                    newChatBtn.click();
                    // 等待 UI 切换 (SPA 很快，但需要一点缓冲)
                    await new Promise(r => setTimeout(r, 400));
                }
                
                // 2. 等待输入框出现 (轮询)
                let box = null;
                for(let i=0; i<50; i++) { // 最多等 5秒
                    box = document.querySelector('div[contenteditable="true"]');
                    if(box) break;
                    await new Promise(r => setTimeout(r, 100));
                }
                if(!box) throw "Input box not found";
                
                // 3. 填入文本
                box.focus();
                document.execCommand('selectAll', false, null); // 确保清空
                document.execCommand('insertText', false, prompt);
                
                // 4. 点击发送
                await new Promise(r => setTimeout(r, 200)); // 等文本渲染
                const sendBtn = document.querySelector('button[aria-label*="Send"]');
                if(!sendBtn) throw "Send button not found";
                sendBtn.click();
                
                // 5. 开始监听输出
                window.bridge.watchStream();
                
            } catch(e) {
                window.bridge.post('ERR', e.toString());
            }
        },
        
        watchStream: () => {
            let lastLen = 0;
            // 每次新对话，response index 可能会重置，所以我们要找最后一个
            const getResponse = () => {
                const els = document.querySelectorAll('.model-response-text');
                return els.length ? els[els.length-1] : null;
            };
            
            const obs = new MutationObserver(() => {
                const el = getResponse();
                if(!el) return;
                
                // 检查是否还在生成 (根据 UI 状态，例如 Stop 按钮存在与否)
                // 这里简化逻辑：只要有新字就发
                const txt = el.innerText;
                if(txt.length > lastLen) {
                    window.bridge.post('TXT', txt.substring(lastLen));
                    lastLen = txt.length;
                }
                
                // 🛑 结束检测：简单策略 - 如果 2秒没变动，或者检测到特定的结束标志
                // 更 Robust 的方法是检测 "Send" 按钮是否再次变回可用状态
                // 这里暂时省略复杂检测，依赖 Aider 自身的超时或 LocalAPIServer 的 [DONE]
            });
            
            obs.observe(document.body, {subtree:true, childList:true, characterData:true});
        }
    };
    """
    
    // MARK: - Debug Window (同之前)
    @MainActor
    func showDebugWindow() {
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
    
    @MainActor
    func showWindow() {
        showDebugWindow()
    }
    
    // 重置上下文
    func reset() {
        webView.evaluateJavaScript("window.bridge.resetContext()")
    }
    
    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        if url.contains("gemini.google.com/app") {
            print("Login Success")
            currentState = .idle  // 设置为空闲
            window?.close()
        } else if url.contains("accounts.google.com") {
            print("Needs Login")
            currentState = .error  // 设置为错误
        }
    }
}

// 辅助类：解决 ScriptMessageHandler 的循环引用导致内存泄漏
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}