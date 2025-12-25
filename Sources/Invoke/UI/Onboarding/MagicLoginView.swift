import SwiftUI

/// 魔法书签登录教程 - 一键自动登录
struct MagicLoginView: View {
    @Binding var isPresented: Bool
    @State private var showSuccess = false
    
    // 🎨 Colors
    let magicPurple = Color(red: 0.56, green: 0.27, blue: 0.68)
    
    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundColor(magicPurple)
                    .symbolEffect(.pulse, options: .repeating)
                
                Text("🪄 一键自动登录")
                    .font(.title2.bold())
                
                Text("无需写代码，只需 3 步")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 步骤说明
            VStack(alignment: .leading, spacing: 16) {
                MagicStepRow(number: 1, text: "点击下方按钮，打开魔法书签页面", icon: "hand.tap")
                MagicStepRow(number: 2, text: "把紫色按钮拖到 Chrome 书签栏", icon: "arrow.up.doc.on.clipboard")
                MagicStepRow(number: 3, text: "在 Gemini 页面点击该书签", icon: "sparkles")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // 获取书签按钮
            Button(action: openMagicBookmarkPage) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars.inverse")
                    Text("获取魔法书签")
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(magicPurple)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            // 提示
            VStack(spacing: 4) {
                Text("💡 提示")
                    .font(.caption.bold())
                Text("添加书签后，每次只需在 Gemini 页面点一下即可登录")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
            
            // 关闭按钮
            Button("稍后设置") {
                isPresented = false
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding(28)
        .frame(width: 420)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MagicLoginSuccess"))) { _ in
            showSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isPresented = false
            }
        }
        .overlay {
            if showSuccess {
                successOverlay
            }
        }
    }
    
    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("🎉 登录成功！")
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .transition(.opacity)
    }
    
    private func openMagicBookmarkPage() {
        // Bookmarklet: 获取 Cookie 并通过 URL Scheme 发送给 Fetch
        let bookmarkletCode = "javascript:(function(){var c=document.cookie;if(c){window.location.href='fetch-auth://login?cookie='+encodeURIComponent(c);}else{alert('请先登录 Google 账号');}})();"
        
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Fetch 魔法书签</title>
            <style>
                * { box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    min-height: 100vh;
                    margin: 0;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    padding: 20px;
                }
                .card {
                    background: white;
                    border-radius: 20px;
                    padding: 40px;
                    max-width: 500px;
                    text-align: center;
                    box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                }
                h1 { 
                    margin: 0 0 10px 0; 
                    font-size: 28px;
                }
                .subtitle {
                    color: #666;
                    margin-bottom: 30px;
                }
                .magic-btn {
                    display: inline-block;
                    background: linear-gradient(135deg, #8E44AD, #9B59B6);
                    color: white;
                    padding: 18px 36px;
                    text-decoration: none;
                    border-radius: 12px;
                    font-weight: bold;
                    font-size: 18px;
                    cursor: grab;
                    box-shadow: 0 8px 24px rgba(142, 68, 173, 0.4);
                    transition: transform 0.2s, box-shadow 0.2s;
                }
                .magic-btn:hover {
                    transform: translateY(-2px);
                    box-shadow: 0 12px 32px rgba(142, 68, 173, 0.5);
                }
                .magic-btn:active {
                    cursor: grabbing;
                }
                .instructions {
                    margin-top: 30px;
                    padding: 20px;
                    background: #f8f9fa;
                    border-radius: 12px;
                    text-align: left;
                }
                .step {
                    display: flex;
                    align-items: center;
                    margin: 10px 0;
                }
                .step-num {
                    background: #8E44AD;
                    color: white;
                    width: 24px;
                    height: 24px;
                    border-radius: 50%;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    font-size: 12px;
                    font-weight: bold;
                    margin-right: 12px;
                    flex-shrink: 0;
                }
                .tip {
                    margin-top: 20px;
                    color: #888;
                    font-size: 14px;
                }
                .arrow {
                    font-size: 24px;
                    margin: 20px 0;
                    animation: bounce 1s infinite;
                }
                @keyframes bounce {
                    0%, 100% { transform: translateY(0); }
                    50% { transform: translateY(-10px); }
                }
            </style>
        </head>
        <body>
            <div class="card">
                <h1>🪄 Fetch 魔法书签</h1>
                <p class="subtitle">一键连接 Gemini 到 Fetch App</p>
                
                <div class="arrow">⬇️</div>
                
                <a class="magic-btn" href="\(bookmarkletCode)">
                    ⚡️ Connect Fetch
                </a>
                
                <div class="instructions">
                    <div class="step">
                        <span class="step-num">1</span>
                        <span>把上面的紫色按钮 <strong>拖拽</strong> 到浏览器书签栏</span>
                    </div>
                    <div class="step">
                        <span class="step-num">2</span>
                        <span>打开 <a href="https://gemini.google.com" target="_blank">gemini.google.com</a> 并登录</span>
                    </div>
                    <div class="step">
                        <span class="step-num">3</span>
                        <span>点击书签栏中的 "Connect Fetch" 按钮</span>
                    </div>
                </div>
                
                <p class="tip">💡 Fetch App 会自动打开并完成登录</p>
            </div>
        </body>
        </html>
        """
        
        // 写入临时文件并打开
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fetch_magic_login.html")
        try? htmlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tempURL)
    }
}

// MARK: - Step Row

struct MagicStepRow: View {
    let number: Int
    let text: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.purple)
            }
            
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.purple)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13))
        }
    }
}

// MARK: - Preview

#Preview {
    MagicLoginView(isPresented: .constant(true))
}

