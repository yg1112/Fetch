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
    private var requestCounter: Int = 0 // Context 轮替计数器
    
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

                    // 3. 🧼 Context 自动轮替：每 8 回合重置一次
                    self.requestCounter += 1
                    let shouldReset = (self.requestCounter % 8 == 0)
                    if shouldReset {
                        print("🔄 Auto-rotating context (request #\(self.requestCounter))")
                    }

                    // 4. 发送指令
                    let safePrompt = prompt.replacingOccurrences(of: "\\", with: "\\\\")
                                           .replacingOccurrences(of: "\"", with: "\\\"")
                                           .replacingOccurrences(of: "\n", with: "\\n")
                                           .replacingOccurrences(of: "`", with: "\\`")
                    
                    // 调用 JS: 传递 prompt 和 shouldReset 标志
                    self.webView.evaluateJavaScript("window.bridge.processTask(`\(safePrompt)`, \(shouldReset))")
                    
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
        case "LOG":
            // JavaScript 日志回显
            if let logMsg = body["d"] as? String {
                print("📡 [JS]: \(logMsg)")
            }
        default: break
        }
    }
    
    // MARK: - JS 注入代码 (The Brain) - 工业级增强版
    // 实现了智能等待、状态机心跳、错误检测
    private static let injectionScript = """
    window.bridge = {
        post: (t, d) => window.webkit.messageHandlers.core.postMessage({t:t, d:d}),
        log: (msg) => window.bridge.post('LOG', msg),

        // 智能 DOM 等待器 (替代 setTimeout)
        waitForElement: async (selector, timeout = 10000) => {
            window.bridge.log(`Waiting for element: ${selector}`);
            const startTime = Date.now();

            while (Date.now() - startTime < timeout) {
                const el = document.querySelector(selector);
                if (el) {
                    window.bridge.log(`Found element: ${selector}`);
                    return el;
                }
                await new Promise(r => setTimeout(r, 100));
            }

            throw `Element not found: ${selector} (timeout ${timeout}ms)`;
        },

        // 检测错误状态
        detectErrors: () => {
            // 检测 Rate Limit 错误
            const rateLimitText = document.body.innerText;
            if (rateLimitText.includes('Try again later') ||
                rateLimitText.includes('Too many requests') ||
                rateLimitText.includes('rate limit')) {
                return 'RATE_LIMIT';
            }

            // 检测网络错误
            if (rateLimitText.includes('network error') ||
                rateLimitText.includes('connection failed')) {
                return 'NETWORK_ERROR';
            }

            return null;
        },

        // 重置上下文
        resetContext: async () => {
            try {
                window.bridge.log('Resetting context...');
                const newChatBtn = document.querySelector('div[data-test-id="new-chat-button"]') ||
                                   document.querySelector('a[href^="/app"]');
                if(newChatBtn) {
                    newChatBtn.click();
                    await new Promise(r => setTimeout(r, 400));
                }
            } catch(e) {
                window.bridge.log('Reset context failed: ' + e);
            }
        },

        // 核心任务流 - 工业级增强版
        processTask: async (prompt, shouldReset = true) => {
            try {
                window.bridge.log('Starting processTask...');

                // 1. 检测初始错误状态
                const initialError = window.bridge.detectErrors();
                if (initialError) {
                    throw `Pre-flight error detected: ${initialError}`;
                }

                // 2. 重置上下文 (如果需要)
                if (shouldReset) {
                    const newChatBtn = document.querySelector('div[data-test-id="new-chat-button"]') ||
                                       document.querySelector('a[href^="/app"]');
                    if(newChatBtn) {
                        window.bridge.log('Clicking New Chat button');
                        newChatBtn.click();
                        await new Promise(r => setTimeout(r, 400));
                    }
                }

                // 3. 智能等待输入框（替代轮询）
                const box = await window.bridge.waitForElement('div[contenteditable="true"]', 10000);

                // 4. 填入文本
                window.bridge.log('Filling in prompt...');
                box.focus();
                document.execCommand('selectAll', false, null);
                document.execCommand('insertText', false, prompt);

                // 5. 智能等待发送按钮并点击
                await new Promise(r => setTimeout(r, 200));
                const sendBtn = await window.bridge.waitForElement('button[aria-label*="Send"]', 5000);
                window.bridge.log('Clicking Send button');
                sendBtn.click();

                // 6. 开始监听输出流
                window.bridge.watchStream();

            } catch(e) {
                window.bridge.post('ERR', e.toString());
            }
        },

        // 流式监听 - 带心跳和智能结束检测
        watchStream: () => {
            window.bridge.log('Starting stream watch...');
            let lastLen = 0;
            let stableCount = 0;
            let lastCheckTime = Date.now();

            const getResponse = () => {
                const els = document.querySelectorAll('.model-response-text');
                return els.length ? els[els.length-1] : null;
            };

            // 检测是否完成生成
            const isGenerationComplete = () => {
                // 方法1: 检测停止按钮是否消失
                const stopBtn = document.querySelector('button[aria-label*="Stop"]');
                if (!stopBtn) return true;

                // 方法2: 检测发送按钮是否重新激活
                const sendBtn = document.querySelector('button[aria-label*="Send"]');
                if (sendBtn && !sendBtn.disabled) return true;

                return false;
            };

            const obs = new MutationObserver(() => {
                try {
                    // 心跳：检测错误状态
                    const error = window.bridge.detectErrors();
                    if (error) {
                        window.bridge.post('ERR', `Generation error: ${error}`);
                        obs.disconnect();
                        return;
                    }

                    const el = getResponse();
                    if(!el) return;

                    const txt = el.innerText;

                    // 发送增量文本
                    if(txt.length > lastLen) {
                        window.bridge.post('TXT', txt.substring(lastLen));
                        lastLen = txt.length;
                        stableCount = 0; // 重置稳定计数
                        lastCheckTime = Date.now();
                    } else {
                        stableCount++;
                    }

                    // 智能结束检测
                    const timeSinceLastUpdate = Date.now() - lastCheckTime;

                    // 如果检测到生成完成标志，立即结束
                    if (isGenerationComplete()) {
                        window.bridge.log('Generation complete (detected completion signal)');
                        window.bridge.post('DONE', '');
                        obs.disconnect();
                        return;
                    }

                    // 或者：如果文本稳定超过 3 秒，也认为结束
                    if (timeSinceLastUpdate > 3000 && stableCount > 20 && lastLen > 0) {
                        window.bridge.log('Generation complete (stable timeout)');
                        window.bridge.post('DONE', '');
                        obs.disconnect();
                        return;
                    }

                } catch(e) {
                    window.bridge.post('ERR', 'Watch stream error: ' + e.toString());
                    obs.disconnect();
                }
            });

            obs.observe(document.body, {subtree:true, childList:true, characterData:true});

            // 超时保护：30 秒绝对超时
            setTimeout(() => {
                if (lastLen === 0) {
                    window.bridge.post('ERR', 'Timeout: No response after 30 seconds');
                } else {
                    window.bridge.log('Forcing completion due to 30s timeout');
                    window.bridge.post('DONE', '');
                }
                obs.disconnect();
            }, 30000);
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

    // 强制重新加载 WebView（一键自愈）
    @MainActor
    func forceReload() {
        lock.lock()
        isProcessing = false
        lock.unlock()
        continuation?.finish()
        continuation = nil
        currentState = .error
        webView.reload()
        print("🔄 WebView force reloaded")
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