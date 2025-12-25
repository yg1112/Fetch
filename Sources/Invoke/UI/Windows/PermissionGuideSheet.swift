import SwiftUI

/// 权限引导弹窗 - 当 macOS 阻止访问 Chrome 时显示
struct PermissionGuideSheet: View {
    @Binding var isPresented: Bool
    let onRetry: () -> Void
    
    @State private var isResetting = false
    @State private var resetSuccess = false
    @State private var showRestartHint = false
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("🔐 需要 Chrome 访问权限")
                    .font(.title2.bold())
                
                Text("macOS 安全机制阻止了 Fetch 访问 Chrome")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 解决方案
            VStack(alignment: .leading, spacing: 16) {
                Text("请按以下步骤操作：")
                    .font(.headline)
                
                // 方案 A
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("方案 A")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        Text("检查系统设置")
                            .font(.subheadline.bold())
                    }
                    
                    Text("1. 打开 系统设置 → 隐私与安全性 → 自动化\n2. 找到 Fetch → 勾选 Google Chrome")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        ChromeBridge.openAutomationSettings()
                    }) {
                        HStack {
                            Image(systemName: "gear")
                            Text("打开系统设置")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
                
                // 方案 B
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("方案 B")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        Text("重置权限 (后悔药)")
                            .font(.subheadline.bold())
                    }
                    
                    Text("如果在设置中看不到 Fetch，点击此按钮重置权限，然后重启 App 再试一次。")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack {
                        Button(action: resetPermissions) {
                            HStack {
                                if isResetting {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                Text(isResetting ? "重置中..." : "重置权限")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isResetting)
                        
                        if resetSuccess {
                            Text("✅ 已重置")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    if showRestartHint {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("请重启 Fetch App，然后再次尝试导入")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Button("使用其他登录方式") {
                    isPresented = false
                }
                .foregroundColor(.gray)
                
                Spacer()
                
                Button(action: {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onRetry()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重试导入")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
    
    private func resetPermissions() {
        isResetting = true
        
        ChromeBridge.resetPermissions { success in
            isResetting = false
            resetSuccess = success
            
            if success {
                withAnimation {
                    showRestartHint = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PermissionGuideSheet(isPresented: .constant(true), onRetry: {})
}

