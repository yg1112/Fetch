import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate { // 遵循 NSWindowDelegate
    var statusItem: NSStatusItem?
    var floatingPanel: FloatingPanel?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    
    // 用 UserDefaults 存储窗口坐标
    let posKeyX = "WindowPosX"
    let posKeyY = "WindowPosY"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ [APP] Launching Invoke")
        
        // 1. 设置菜单栏
        setupMenuBarIcon()
        
        // 2. 检查是否需要显示 onboarding
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            print("🎬 [APP] First run - showing onboarding")
            showOnboarding()
        } else {
            print("✅ [APP] Onboarding completed - showing main panel")
            setupFloatingPanel()
        }
    }
    
    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.rays.fill", accessibilityDescription: "Invoke")
            button.action = #selector(togglePanel)
            button.target = self
        }
    }
    
    private func setupFloatingPanel() {
        // 定义窗口大小
        let width: CGFloat = 280
        let height: CGFloat = 140 // 稍微加高一点以容纳更多信息
        
        // 1. 读取上次保存的位置，如果没有则默认在屏幕左下角稍微往上一点
        let savedX = UserDefaults.standard.double(forKey: posKeyX)
        let savedY = UserDefaults.standard.double(forKey: posKeyY)
        
        // 默认位置：屏幕左下角 (padding 50)
        let defaultX: CGFloat = 50
        let defaultY: CGFloat = 50
        
        let initialX = savedX != 0 ? CGFloat(savedX) : defaultX
        let initialY = savedY != 0 ? CGFloat(savedY) : defaultY
        
        let contentRect = NSRect(x: initialX, y: initialY, width: width, height: height)
        
        // 2. 创建面板
        floatingPanel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow], // HUD 风格更优雅
            backing: .buffered,
            defer: false
        )
        
        if let panel = floatingPanel {
            panel.delegate = self // 监听移动事件
            panel.level = .normal  // 默认不置顶，用户点图钉才置顶
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear // 完全透明，交给 SwiftUI 渲染背景
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true // 关键：允许通过背景拖拽！
            
            // 注入 AppUI
            let appUI = AppUI(
                onSettings: { [weak self] in self?.showSettings() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            
            // 使用 HostingView
            let hostingView = NSHostingView(rootView: appUI)
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            
            panel.contentView = hostingView
            panel.orderFront(nil)
        }
    }
    
    // 3. 监听窗口移动，实时保存位置
    func windowDidMove(_ notification: Notification) {
        if let panel = floatingPanel {
            UserDefaults.standard.set(Double(panel.frame.origin.x), forKey: posKeyX)
            UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: posKeyY)
        }
    }
    
    @objc private func togglePanel() {
        guard let panel = floatingPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func showSettings() {
        // (Settings Window Logic - 保持不变)
    }
    
    private func showOnboarding() {
        let onboardingView = OnboardingContainer()
            .environment(\.closeOnboarding, { [weak self] in
                print("✅ [APP] Onboarding completed")
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.setupFloatingPanel()
            })
        
        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        onboardingWindow?.center()
        onboardingWindow?.isReleasedWhenClosed = false
        onboardingWindow?.titlebarAppearsTransparent = true
        onboardingWindow?.titleVisibility = .hidden
        onboardingWindow?.contentView = NSHostingView(rootView: onboardingView)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// 保持 FloatingPanel 类不变，或者确保它允许交互
// ... (FloatingPanel class code below) ...

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
