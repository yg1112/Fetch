import SwiftUI

struct ContentView: View {
    @StateObject private var webManager = GeminiWebManager.shared
    @StateObject private var server = LocalAPIServer.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Fetch Bridge")
                    .font(.title2).bold()
                Spacer()
                StatusBadge(label: "Gemini", isActive: webManager.isReady && webManager.isLoggedIn)
                StatusBadge(label: "Server :\(server.port)", isActive: server.isRunning)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("🚀 How to connect Aider:").font(.headline)
                
                CodeBlock(code: "export OPENAI_API_BASE=http://127.0.0.1:\(server.port)/v1")
                CodeBlock(code: "export OPENAI_API_KEY=sk-bridge")
                CodeBlock(code: "aider --model openai/gemini-2.0-flash --no-auto-commits")
            }
            .padding()
            
            Spacer()
            
            // Actions
            if !webManager.isLoggedIn {
                HStack {
                    Text("🔴 Not Logged In").foregroundColor(.red)
                    Button("Inject Cookies (Chrome)") {
                        ChromeBridge.shared.fetchCookiesFromChrome { res in
                            if case .success(let cookies) = res {
                                webManager.injectRawCookies(cookies) { webManager.loadGemini() }
                            }
                        }
                    }
                    Button("Open Browser") {
                        webManager.loadGemini() // 会在 WebView 显示
                        // 这里可以加一个 Window 展示 WebView 的逻辑，或者就让它在后台跑
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 350)
        .onAppear {
            server.start()
        }
    }
}

struct StatusBadge: View {
    let label: String
    let isActive: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(isActive ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .padding(6)
        .background(Capsule().fill(Color.gray.opacity(0.1)))
    }
}

struct CodeBlock: View {
    let code: String
    var body: some View {
        HStack {
            Text(code).font(.system(.caption, design: .monospaced))
            Spacer()
            Button(action: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(6)
    }
}