import Cocoa
import SwiftUI

// 应用入口：极致轻量
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 启动服务
        LocalAPIServer.shared.start()
        
        // 2. 初始化核心
        GeminiCore.shared.prepare()
        
        // 3. 🔥【关键修复】初始化 UI (菜单栏图标)
        // 必须显式调用这个方法，图标才会出现！
        setupStatusBar()
    }
    
    // 这个方法需要确保在主线程执行
    @MainActor
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // 初始状态：灰色（未就绪）
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Fetch")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Brain", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Reset Context", action: #selector(resetContext), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Force Reload WebView", action: #selector(forceReload), keyEquivalent: "R"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // 绑定状态：绿色=就绪，红色=需登录
        GeminiCore.shared.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                let (symbol, color): (String, NSColor) = switch state {
                case .idle:
                    ("circle.fill", .systemGreen)
                case .thinking:
                    ("brain", .systemBlue)  // 或闪烁动画
                case .error:
                    ("exclamationmark.triangle.fill", .systemRed)
                }
                
                let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
                self?.statusItem.button?.image = image
                
                // 如果掉线了，自动弹窗让用户处理
                if case .error = state { self?.showWindow() }
            }
        }
    }
    
    @MainActor
    @objc func showWindow() {
        GeminiCore.shared.showWindow()
    }
    
    @MainActor
    @objc func resetContext() {
        GeminiCore.shared.reset()
    }

    @MainActor
    @objc func forceReload() {
        print("🔄 Force reloading WebView...")
        GeminiCore.shared.forceReload()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()