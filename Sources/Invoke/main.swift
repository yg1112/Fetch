import Cocoa
import SwiftUI

// 应用入口：极致轻量
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动服务
        LocalAPIServer.shared.start()
        
        // 初始化 
        GeminiCore.shared.prepare()
        
        // 甚至不需要状态栏图标，除非出错
        // 或者只在 Menu Bar 显示一个极小的点
        // ...
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
                let symbol = state ? "circle.fill" : "exclamationmark.triangle"
                let color: NSColor = state ? .systemGreen : .systemRed
                
                let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
                self?.statusItem.button?.image = image
                
                // 如果掉线了，自动弹窗让用户处理，这就叫"直觉"
                if !state { self?.showWindow() }
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