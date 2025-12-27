import Cocoa
import SwiftUI

// 应用入口：极致轻量
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 启动 Woz 的服务器
        LocalAPIServer.shared.start()
        
        // 2. 启动 Jobs 的浏览器核心
        GeminiCore.shared.prepare()
        
        // 3. 在菜单栏画一个小点
        setupStatusBar()
    }
    
    @MainActor
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // 初始状态：灰色（未就绪）
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Fetch")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Brain", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // 绑定状态：绿色=就绪，红色=需登录
        GeminiCore.shared.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                let symbol = state == .ready ? "circle.fill" : "exclamationmark.triangle"
                let color: NSColor = state == .ready ? .systemGreen : .systemRed
                
                let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
                self?.statusItem.button?.image = image
                
                // 如果掉线了，自动弹窗让用户处理，这就叫“直觉”
                if state == .needsLogin { self?.showWindow() }
            }
        }
    }
    
    @MainActor
    @objc func showWindow() {
        GeminiCore.shared.showWindow()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()