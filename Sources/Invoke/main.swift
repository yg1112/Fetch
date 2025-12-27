import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 启动服务器
        LocalAPIServer.shared.start()
        
        // 2. 设置菜单栏
        setupMenuBar()
        
        // 3. 启动浏览器核心 (它会自动判断是否需要弹窗登录)
        GeminiCore.shared.load()
    }
    
    @MainActor
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Fetch")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Gemini Window", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        // 绑定状态更新
        GeminiCore.shared.onStatusChange = { [weak self] isLoggedIn in
            DispatchQueue.main.async {
                let symbol = isLoggedIn ? "brain.head.profile" : "exclamationmark.triangle"
                self?.statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                // 如果未登录，自动弹出窗口
                if !isLoggedIn { self?.showWindow() }
            }
        }
    }
    
    @MainActor
    @objc func showWindow() {
        GeminiCore.shared.showDebugWindow()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()