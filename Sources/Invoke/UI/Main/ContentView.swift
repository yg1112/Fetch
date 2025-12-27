import SwiftUI

struct ContentView: View {
    // 直接观测核心组件，不再需要中间商
    @StateObject private var webManager = GeminiWebManager.shared
    @StateObject private var server = LocalAPIServer.shared
    
    // 自动滚动日志
    @State private var logText = ""

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Status Header
            HStack(spacing: 16) {
                StatusIndicator(
                    label: "Gemini Link",
                    isActive: webManager.isReady && webManager.isLoggedIn,
                    color: .green
                )
                
                StatusIndicator(
                    label: "API Server (:3000)",
                    isActive: server.isRunning,
                    color: .blue
                )
                
                Spacer()
                
                // 便捷按钮：复制环境变量，方便用户去终端粘贴
                Button(action: copyEnvVars) {
                    HStack {
                        Image(systemName: "terminal")
                        Text("Copy Env Vars")
                    }
                }
                .help("Copy export commands for Terminal")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // MARK: - Server Logs
            // 这里建议连接到一个 LogStore，或者简单显示状态
            // 为了极简，我们暂时只显示静态提示，实际日志看 Xcode 控制台即可
            // 或者你可以做一个简单的 LogView
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Invisible Bridge Active").font(.headline).foregroundColor(.secondary)
                    Text("1. Keep this window open.")
                    Text("2. Open your favorite Terminal.")
                    Text("3. Run: export OPENAI_API_BASE=http://127.0.0.1:3000/v1")
                    Text("4. Run: aider --model openai/gemini-2.0-flash --no-auto-commits")
                    
                    if !webManager.isLoggedIn {
                        Text("⚠️ Gemini Not Logged In").foregroundColor(.red).bold()
                        Button("Login in WebView") {
                             // 简单的登录触发
                             let url = URL(string: "https://gemini.google.com")!
                             NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.8))
        }
        .frame(width: 400, height: 250)
        .onAppear {
            server.start()
        }
    }
    
    private func copyEnvVars() {
        let cmd = "export OPENAI_API_BASE=http://127.0.0.1:3000/v1 && export OPENAI_API_KEY=sk-bridge"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cmd, forType: .string)
    }
}

struct StatusIndicator: View {
    let label: String
    let isActive: Bool
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? color : Color.gray)
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? color.opacity(0.5) : .clear, radius: 4)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }
}