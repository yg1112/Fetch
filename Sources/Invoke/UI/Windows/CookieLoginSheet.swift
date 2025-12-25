import SwiftUI

/// Cookie 手动登录弹窗 - 100% 成功率的备用方案
struct CookieLoginSheet: View {
    @Binding var isPresented: Bool
    @State private var cookieText: String = ""
    @State private var isInjecting = false
    @State private var statusMessage = ""
    
    // 🎨 Colors
    let neonGreen = Color(red: 0.0, green: 0.9, blue: 0.5)
    let neonOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Text("🍪")
                    .font(.system(size: 32))
                Text("Cookie 登录")
                    .font(.title2.bold())
            }
            
            Text("由于 Google 安全限制，请手动导入登录状态")
                .font(.caption)
                .foregroundColor(.gray)
            
            // 步骤说明
            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "在 Chrome 打开 gemini.google.com 并登录")
                StepRow(number: 2, text: "按 F12 (或 Cmd+Option+J) 打开控制台")
                StepRow(number: 3, text: "输入 document.cookie 并回车")
                StepRow(number: 4, text: "复制那串红色字符（去掉引号），粘贴到下面")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Cookie 输入框
            VStack(alignment: .leading, spacing: 4) {
                Text("Cookie 字符串:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                TextEditor(text: $cookieText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // 状态消息
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(statusMessage.contains("✅") ? neonGreen : neonOrange)
            }
            
            // 按钮
            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: injectCookies) {
                    HStack {
                        if isInjecting {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                        Text(isInjecting ? "注入中..." : "🚀 注入 Cookie 并登录")
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(neonGreen)
                .keyboardShortcut(.defaultAction)
                .disabled(cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInjecting)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
    
    private func injectCookies() {
        guard !cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isInjecting = true
        statusMessage = "正在注入 Cookie..."
        
        GeminiWebManager.shared.injectRawCookies(cookieText) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isInjecting = false
                
                // 检查登录状态
                GeminiWebManager.shared.checkLoginStatus()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if GeminiWebManager.shared.isLoggedIn {
                        statusMessage = "✅ 登录成功！"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isPresented = false
                        }
                    } else {
                        statusMessage = "⚠️ Cookie 可能无效，请确保复制完整"
                    }
                }
            }
        }
    }
}

// MARK: - Step Row

struct StepRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    CookieLoginSheet(isPresented: .constant(true))
}

