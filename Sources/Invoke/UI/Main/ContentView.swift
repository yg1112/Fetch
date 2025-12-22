import SwiftUI

struct ContentView: View {
    @StateObject var logic = GeminiLinkLogic()
    
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
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        // Status Dot
                        Circle()
                            .fill(logic.isListening ? activeGreen : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .shadow(color: logic.isListening ? activeGreen.opacity(0.6) : .clear, radius: 4)
                        
                        // Project Path (Clickable Text)
                        Button(action: logic.selectProjectRoot) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10, weight: .bold))
                                Text(logic.projectRoot.isEmpty ? "Select Project..." : URL(fileURLWithPath: logic.projectRoot).lastPathComponent)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        // Close Button (Ghost Style)
                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                    }
                    
                    // Mode Selector
                    HStack(spacing: 8) {
                        Text("Mode:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $logic.gitMode) {
                            ForEach(GeminiLinkLogic.GitMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
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
                .background(Color.black.opacity(0.2)) // 底部稍微深一点，增加稳重感
            }
        }
        .cornerRadius(16) // 统一的大圆角
        // 加上极细的边框，提升精致感
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .frame(width: 300) // 紧凑宽度
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
