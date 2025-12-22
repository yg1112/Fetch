import SwiftUI

struct ContentView: View {
    @StateObject var logic = GeminiLinkLogic()
    @State private var isAlwaysOnTop = false
    
    // 颜色常量
    let glassBackground = NSVisualEffectView.Material.hudWindow // macOS 原生 HUD 材质
    let activeGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    let activeBlue = Color(red: 0.2, green: 0.6, blue: 1.0)
    
    var body: some View {
        ZStack {
            // 1. 底层：唯一的毛玻璃背景
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            // 2. 内容层
            VStack(spacing: 0) {
                
                // === HEADER (Status & Project & Mode) ===
                VStack(spacing: 12) { // 增加间距
                    HStack(spacing: 12) {
                        // Status Dot
                        Circle()
                            .fill(logic.isListening ? activeGreen : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8) // 稍微加大一点点
                            .shadow(color: logic.isListening ? activeGreen.opacity(0.6) : .clear, radius: 4)
                        
                        // Project Path (Clickable Text)
                        Button(action: logic.selectProjectRoot) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                Text(logic.projectRoot.isEmpty ? "Select Project..." : URL(fileURLWithPath: logic.projectRoot).lastPathComponent)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(logic.projectRoot.isEmpty ? .secondary : .primary)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        // Pin Button (置顶)
                        Button(action: toggleAlwaysOnTop) {
                            Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isAlwaysOnTop ? .blue : .secondary.opacity(0.5))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isAlwaysOnTop ? "取消置顶" : "窗口置顶")
                        
                        // Close Button
                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.5))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Mode Selector (UI 修复版)
                    Picker("", selection: $logic.gitMode) {
                        ForEach(GeminiLinkLogic.GitMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden() // 隐藏默认标签
                    .frame(maxWidth: .infinity) // 撑满宽度
                    .padding(.horizontal, 4) // 微调边距
                }
                .padding(16)
                
                // === BODY (Log Stream) ===
                // 没有任何背景色，直接显示在毛玻璃上
                VStack {
                    if logic.changeLogs.isEmpty {
                        EmptyStateView(isListening: logic.isListening)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(logic.changeLogs) { log in
                                    LogItemRow(log: log, logic: logic)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(height: 140) // 固定高度
                
                // === FOOTER (Two Big Actions) ===
                // 无缝分割线
                Divider()
                    .opacity(0.1)
                
                HStack(spacing: 0) {
                    // LEFT: PAIR
                    BigActionButton(
                        title: "Pair",
                        icon: "link",
                        color: activeBlue,
                        isActive: false
                    ) {
                        logic.copyProtocol()
                    }
                    
                    // Vertical Divider
                    Divider()
                        .frame(height: 20)
                        .opacity(0.2)
                    
                    // RIGHT: REVIEW
                    BigActionButton(
                        title: "Review",
                        icon: "checkmark.magnifyingglass",
                        color: .orange,
                        isActive: false
                    ) {
                        logic.reviewLastChange()
                    }
                }
                .frame(height: 50)
                .background(Color.black.opacity(0.2))
            }
        }
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .frame(width: 320) // 稍微加宽一点，让 Safe/Local Only 文字能放下
    }
    
    // MARK: - 置顶功能
    private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        
        // 查找当前窗口并设置 level
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            window.level = isAlwaysOnTop ? .floating : .normal
            print("🔝 Window level set to: \(isAlwaysOnTop ? "Always On Top" : "Normal")")
        }
    }
}

// MARK: - Subviews (The Building Blocks)

struct EmptyStateView: View {
    let isListening: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isListening ? "waveform" : "command")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.3))
                .symbolEffect(.pulse, isActive: isListening) // iOS17+/macOS14+ 动画
            
            Text(isListening ? "Waiting for Gemini..." : "Ready to Link")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
            Spacer()
        }
    }
}

struct LogItemRow: View {
    let log: ChangeLog
    @ObservedObject var logic: GeminiLinkLogic
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Commit Hash (Clickable Link)
            Button(action: {
                openCommitInBrowser()
            }) {
                HStack(spacing: 4) {
                    Text(log.commitHash)
                        .font(.system(size: 9, design: .monospaced))
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 8))
                }
                .foregroundColor(.blue)
                .padding(4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Open commit in browser")
            
            // Summary
            Text(log.summary)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
    
    /// 在浏览器中打开 commit 页面
    private func openCommitInBrowser() {
        guard let commitURL = GitService.shared.getCommitURL(for: log.commitHash, in: logic.projectRoot),
              let url = URL(string: commitURL) else {
            print("⚠️ Could not construct commit URL")
            return
        }
        
        print("🌐 Opening commit in browser: \(commitURL)")
        NSWorkspace.shared.open(url)
    }
}

struct BigActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 动态颜色：激活时用彩色，未激活时用默认色
            .foregroundColor(isActive ? color : (isHovering ? .primary : .secondary))
            .background(isActive ? color.opacity(0.1) : (isHovering ? Color.white.opacity(0.05) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hover
            }
        }
    }
}
