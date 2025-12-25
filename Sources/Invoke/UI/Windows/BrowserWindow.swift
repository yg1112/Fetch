import SwiftUI
import WebKit

/// 浏览器登录窗口 - 当检测到未登录时显示
/// 用户在此窗口登录 Google，登录成功后自动关闭
class BrowserWindowController: NSObject, ObservableObject {
    static let shared = BrowserWindowController()
    
    private var window: NSWindow?
    @Published var isShowing = false
    
    func showLoginWindow() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        let webManager = GeminiWebManager.shared
        
        // 创建全尺寸 WebView 用于登录
        let hostingView = NSHostingView(rootView: BrowserWindowView(
            webView: webManager.webView,
            onClose: { [weak self] in
                self?.hideWindow()
            }
        ))
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Login to Google - Fetch"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.delegate = self
        
        self.window = newWindow
        self.isShowing = true
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hideWindow() {
        window?.close()
        window = nil
        isShowing = false
    }
    
    /// 自动检测登录状态，登录成功后关闭窗口
    func startLoginMonitor() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            let manager = GeminiWebManager.shared
            manager.checkLoginStatus()
            
            if manager.isLoggedIn && self?.isShowing == true {
                print("✅ Login detected, closing browser window")
                self?.hideWindow()
                timer.invalidate()
            }
        }
    }
}

extension BrowserWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
        isShowing = false
    }
}

// MARK: - SwiftUI View

struct BrowserWindowView: View {
    let webView: WKWebView
    let onClose: () -> Void
    
    @State private var showCookieSheet = false
    @State private var showMagicSheet = false
    @State private var showPermissionGuide = false
    @State private var isImporting = false
    @State private var chromeError: ChromeBridge.ChromeError?
    @State private var showSuccess = false
    @State private var permissionResetMessage = ""
    @State private var permissionStatus: ChromeBridge.PermissionStatus = .unknown
    @State private var isCheckingPermission = true
    @State private var showAlternatives = false  // 折叠备选方案
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 顶部操作栏
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in to Google")
                                .font(.headline)
                            Text("Choose a login method below")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            GeminiWebManager.shared.loadGemini()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                    }
                    
                    // 🔮 一键导入按钮 (主推) - 带状态指示和浏览器名称
                    Button(action: importFromChrome) {
                        HStack(spacing: 8) {
                            if isImporting || isCheckingPermission {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: importButtonIcon)
                                    .font(.system(size: 18))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(importButtonTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(importButtonSubtitle)
                                    .font(.system(size: 10))
                                    .opacity(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .opacity(0.5)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: importButtonColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting || isCheckingPermission)
                    .onAppear {
                        checkPermission()
                    }
                    
                    // 仅在权限出错时显示修复按钮
                    if permissionStatus == .systemDenied || permissionStatus == .chromeDenied {
                        HStack(spacing: 8) {
                            Button(action: {
                                ChromeBridge.openAutomationSettings()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "gear")
                                    Text("打开系统设置")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.15))
                                .foregroundColor(.gray)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                ChromeBridge.resetPermissions { success in
                                    if success {
                                        permissionResetMessage = "✅ 权限已重置，请重新授权"
                                        checkPermission()
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("重置权限")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                    }
                    
                    // 折叠式备用方案
                    VStack(spacing: 8) {
                        // "其他方式" 展开链接
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAlternatives.toggle() } }) {
                            HStack(spacing: 4) {
                                Text("其他登录方式")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Image(systemName: showAlternatives ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // 展开后显示备用按钮
                        if showAlternatives {
                            HStack(spacing: 8) {
                                Button(action: { showMagicSheet = true }) {
                                    HStack(spacing: 4) {
                                        Text("🪄")
                                        Text("书签登录")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.purple.opacity(0.15))
                                    .foregroundColor(.purple)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { showCookieSheet = true }) {
                                    HStack(spacing: 4) {
                                        Text("🍪")
                                        Text("手动输入")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { ChromeBridge.shared.openGeminiInChrome() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "globe")
                                        Text("打开 \(browserName)")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // WebView
                WebViewRepresentable(webView: webView)
            }
            
            // 成功动画覆盖层
            if showSuccess {
                successOverlay
            }
        }
        .sheet(isPresented: $showCookieSheet) {
            CookieLoginSheet(isPresented: $showCookieSheet)
        }
        .sheet(isPresented: $showMagicSheet) {
            MagicLoginView(isPresented: $showMagicSheet)
        }
        .sheet(isPresented: $showPermissionGuide) {
            PermissionGuideSheet(isPresented: $showPermissionGuide, onRetry: importFromChrome)
        }
        .alert(item: $chromeError) { error in
            if error.isSystemPermissionError {
                // 系统权限错误 - 使用专门的引导页面
                return Alert(
                    title: Text("🔐 需要系统权限"),
                    message: Text("macOS 阻止了 Fetch 访问 Chrome。请在系统设置中允许。"),
                    primaryButton: .default(Text("查看解决方案"), action: {
                        showPermissionGuide = true
                    }),
                    secondaryButton: .cancel(Text("取消"))
                )
            } else if error.isChromeSettingError {
                // Chrome 内部设置错误 - 直接提示
                return Alert(
                    title: Text("⚠️ Chrome 需要开启权限"),
                    message: Text(error.localizedDescription),
                    primaryButton: .default(Text("我已开启，重试"), action: {
                        importFromChrome()
                    }),
                    secondaryButton: .cancel(Text("取消"))
                )
            } else {
                return Alert(
                    title: Text("导入失败"),
                    message: Text(error.localizedDescription),
                    primaryButton: .default(Text(error.recoveryAction), action: {
                        handleErrorRecovery(error)
                    }),
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }
    
    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("🎉 登录成功！")
                .font(.title2.bold())
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7))
        .transition(.opacity)
    }
    
    private func importFromChrome() {
        isImporting = true
        
        ChromeBridge.shared.fetchCookiesFromChrome { result in
            isImporting = false
            
            switch result {
            case .success(let cookies):
                print("🔮 Telepathy success via \(browserName)!")
                GeminiWebManager.shared.injectRawCookies(cookies) {
                    // 播放成功音效
                    playSuccessSound()
                    
                    // 显示成功动画
                    withAnimation {
                        showSuccess = true
                    }
                    
                    // 发送成功通知
                    NotificationCenter.default.post(name: .loginSuccess, object: nil)
                    
                    // 延迟关闭窗口
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        onClose()
                    }
                }
                
            case .failure(let error):
                chromeError = error
            }
        }
    }
    
    /// 播放成功音效 (系统音效 "Glass" 或 "Hero")
    private func playSuccessSound() {
        NSSound(named: "Glass")?.play()
    }
    
    // MARK: - Import Button State
    
    private var browserName: String {
        ChromeBridge.shared.detectedBrowser
    }
    
    private var importButtonTitle: String {
        switch permissionStatus {
        case .unknown: return "🔮 检测浏览器中..."
        case .granted: return "🔮 从 \(browserName) 一键导入"
        case .systemDenied: return "⚠️ 需要系统授权"
        case .chromeDenied: return "⚠️ 需要 \(browserName) 设置"
        case .chromeNotRunning: return "🔮 一键导入登录状态"
        }
    }
    
    private var importButtonSubtitle: String {
        switch permissionStatus {
        case .unknown: return "正在检测..."
        case .granted: return "已在 \(browserName) 登录? 点此自动导入状态"
        case .systemDenied: return "点击查看解决方案"
        case .chromeDenied: return "点击查看 \(browserName) 设置方法"
        case .chromeNotRunning: return "请先打开浏览器 (Chrome/Arc/Brave) 并登录 Gemini"
        }
    }
    
    private var importButtonIcon: String {
        switch permissionStatus {
        case .granted, .chromeNotRunning, .unknown: return "arrow.triangle.2.circlepath.circle.fill"
        case .systemDenied, .chromeDenied: return "exclamationmark.triangle.fill"
        }
    }
    
    private var importButtonColors: [Color] {
        switch permissionStatus {
        case .granted, .chromeNotRunning, .unknown: return [Color.green, Color.green.opacity(0.8)]
        case .systemDenied: return [Color.orange, Color.orange.opacity(0.8)]
        case .chromeDenied: return [Color.yellow, Color.yellow.opacity(0.8)]
        }
    }
    
    private func checkPermission() {
        isCheckingPermission = true
        ChromeBridge.shared.checkPermissionStatus { status in
            self.permissionStatus = status
            self.isCheckingPermission = false
        }
    }
    
    private func handleErrorRecovery(_ error: ChromeBridge.ChromeError) {
        switch error {
        case .chromeNotRunning, .wrongWebsite:
            ChromeBridge.shared.openGeminiInChrome()
        case .notLoggedIn:
            ChromeBridge.shared.openGeminiInChrome()
        case .systemPermissionDenied:
            // 打开系统设置 - 自动化
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        case .chromeJSDisabled:
            // 显示说明书签登录
            showMagicSheet = true
        case .scriptError:
            break
        }
    }
}

// MARK: - WKWebView Wrapper

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    
    func makeNSView(context: Context) -> WKWebView {
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebView 已由 GeminiWebManager 管理
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 登录成功通知 - Cookie 注入完成后发送
    static let loginSuccess = Notification.Name("FetchLoginSuccess")
}

