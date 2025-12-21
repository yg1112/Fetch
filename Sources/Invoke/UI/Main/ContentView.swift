import SwiftUI

struct ContentView: View {
    @StateObject var logic = GeminiLinkLogic()

    var body: some View {
        VStack(spacing: 0) {
            // === 1. Top Bar: Project & Status ===
            HStack {
                Circle()
                    .fill(logic.isListening ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: logic.isListening ? .green : .clear, radius: 4)

                Text(logic.isListening ? "Listening" : "Paused")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(logic.isListening ? .green : .secondary)

                Spacer()

                Button(action: logic.selectProjectRoot) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text(logic.projectRoot.isEmpty ? "Select Project" : URL(fileURLWithPath: logic.projectRoot).lastPathComponent)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .padding(4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
            }
            .padding(10)
            .background(.ultraThinMaterial)

            // === 2. Middle: The Commit Log (Progress) ===
            ZStack {
                Color.black.opacity(0.8)

                if logic.changeLogs.isEmpty {
                    Text("No changes yet.\nCopy 'Protocol' to start.")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                } else {
                    List {
                        ForEach(logic.changeLogs) { log in
                            LogRows(log: log, onValidate: {
                                logic.validateCommit(log)
                            }, onToggleStatus: {
                                logic.toggleValidationStatus(for: log.id)
                            })
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(height: 140)

            // === 3. Bottom: The Workflow Buttons ===
            HStack(spacing: 0) {
                WorkflowButton(icon: "doc.text.fill", label: "1. Protocol", color: .blue) {
                    logic.copyProtocol()
                }

                Divider().frame(height: 20)

                WorkflowButton(
                    icon: logic.isListening ? "pause.fill" : "play.fill",
                    label: logic.isListening ? "Stop" : "2. Listen",
                    color: logic.isListening ? .green : .gray
                ) {
                    logic.toggleListening()
                }
            }
            .frame(height: 40)
            .background(Color.gray.opacity(0.1))
        }
        .frame(width: 320)
        .cornerRadius(12)
    }
}

// MARK: - Subviews

struct LogRows: View {
    let log: ChangeLog
    let onValidate: () -> Void
    let onToggleStatus: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(log.commitHash)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.yellow)
                .frame(width: 45, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.summary)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundColor(.white)
                Text(log.timestamp, style: .time)
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            }

            Spacer()

            HStack(spacing: 0) {
                Button(action: onValidate) {
                    Image(systemName: "text.magnifyingglass")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Copy Validation Prompt")
                .padding(.trailing, 8)

                Button(action: onToggleStatus) {
                    Text(log.isValidated ? "YES" : "NO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(log.isValidated ? .green : .red)
                        .frame(width: 24)
                        .padding(2)
                        .background(log.isValidated ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }
}

struct WorkflowButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(color)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}import SwiftUI

struct ContentView: View {
    @StateObject var logic = GeminiLinkLogic()
    
    // 控制新手引导显示
    @AppStorage("HasShownTutorial") private var hasShownTutorial: Bool = false
    @State private var showTutorialOverlay: Bool = false
    
    var body: some View {
        ZStack {
            // === 主界面 ===
            VStack(spacing: 0) {
                // 1. 顶部状态栏 (Status Bar)
                HStack {
                    StatusIndicator(isListening: logic.isListening)
                    Spacer()
                    ProjectSelector(path: logic.projectRoot, action: logic.selectProjectRoot)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial) // 顶部毛玻璃
                
                // 2. 日志区域 (Log Area)
                LogConsole(logs: logic.logs)
                    .frame(height: 60) // 固定高度
                    .background(Color.black.opacity(0.8))
                
                // 3. 操作按钮网格 (Action Grid)
                HStack(spacing: 1) {
                    // Start 按钮
                    TileButton(
                        title: logic.isListening ? "STOP" : "START",
                        icon: logic.isListening ? "stop.fill" : "play.fill",
                        isActive: logic.isListening,
                        activeColor: .green,
                        action: logic.toggleListening
                    )
                    
                    // Prep 按钮 (复制 Prompt)
                    TileButton(
                        title: "PREP",
                        icon: "doc.on.doc.fill",
                        isActive: false,
                        action: {
                            logic.generateInitContext()
                            // 点击 Prep 后，如果还在教程模式，提示下一步
                        }
                    )
                    
                    // Magic 按钮 (自动粘贴)
                    TileButton(
                        title: "MAGIC",
                        icon: "wand.and.stars",
                        isActive: logic.magicPaste,
                        activeColor: .purple,
                        action: { logic.magicPaste.toggle() }
                    )
                    
                    // Auto Git 按钮
                    TileButton(
                        title: "GIT",
                        icon: "icloud.and.arrow.up",
                        isActive: logic.autoPush,
                        activeColor: .blue,
                        action: { logic.autoPush.toggle() }
                    )
                }
                .frame(height: 50)
            }
            .cornerRadius(16) // 整体圆角
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            .onAppear {
                // 启动时检查是否需要显示教程
                if !hasShownTutorial {
                    showTutorialOverlay = true
                }
            }
            
            // === 新手引导覆盖层 (Tutorial Overlay) ===
            if showTutorialOverlay {
                TutorialView {
                    hasShownTutorial = true
                    showTutorialOverlay = false
                }
            }
        }
        .frame(width: 280, height: 140)
    }
}

// MARK: - 子组件：精致的按钮 (Visual Feedback)
struct TileButton: View {
    let title: String
    let icon: String
    var isActive: Bool
    var activeColor: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // 扩大点击区域
        }
        .buttonStyle(ResponsiveButtonStyle(isActive: isActive, activeColor: activeColor))
    }
}

struct ResponsiveButtonStyle: ButtonStyle {
    var isActive: Bool
    var activeColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? .white : .secondary)
            .background(isActive ? activeColor : Color.gray.opacity(0.15))
            .overlay(Color.white.opacity(configuration.isPressed ? 0.2 : 0)) // 点击高亮
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 子组件：状态指示器
struct StatusIndicator: View {
    let isListening: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isListening ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: isListening ? .green.opacity(0.5) : .clear, radius: 4)
                .overlay(
                    // 呼吸灯动画
                    Circle()
                        .stroke(isListening ? Color.green : Color.clear)
                        .scaleEffect(isListening ? 1.5 : 1)
                        .opacity(isListening ? 0 : 1)
                        .animation(isListening ? Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false) : .default, value: isListening)
                )
            
            Text(isListening ? "LISTENING" : "PAUSED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isListening ? .primary : .secondary)
        }
    }
}

// MARK: - 子组件：项目选择
struct ProjectSelector: View {
    let path: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.secondary)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }
            .font(.system(size: 10))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 子组件：日志控制台
struct LogConsole: View {
    let logs: [GeminiLinkLogic.LogEntry]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { log in
                        HStack(alignment: .top, spacing: 4) {
                            Text(log.time, style: .time)
                                .foregroundColor(.gray)
                            Text(log.message)
                                .foregroundColor(color(for: log.type))
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .id(log.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: logs.count) { _ in
                // 自动滚动到底部/顶部
                if let first = logs.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
        }
    }
    
    func color(for type: GeminiLinkLogic.LogType) -> Color {
        switch type {
        case .info: return .white
        case .success: return .green
        case .error: return .red
        case .warning: return .yellow
        }
    }
}

// MARK: - 新手引导覆盖层
struct TutorialView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture(perform: onDismiss)
            
            VStack(spacing: 20) {
                Text("🚀 Quick Start")
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 12) {
                    StepRow(num: "1", text: "Select your project folder ↗️")
                    StepRow(num: "2", text: "Click 'PREP' to copy prompt")
                    StepRow(num: "3", text: "Paste into Gemini web")
                    StepRow(num: "4", text: "Click 'START' & 'MAGIC'")
                }
                
                Button("Got it!") {
                    onDismiss()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(20)
            }
            .padding()
        }
    }
    
    struct StepRow: View {
        let num: String
        let text: String
        var body: some View {
            HStack {
                Circle().fill(Color.white).frame(width: 20, height: 20)
                    .overlay(Text(num).font(.caption).bold().foregroundColor(.black))
                Text(text)
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }
}
