import SwiftUI

// Environment key for closing onboarding
struct CloseOnboardingKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var closeOnboarding: () -> Void {
        get { self[CloseOnboardingKey.self] }
        set { self[CloseOnboardingKey.self] = newValue }
    }
}

struct OnboardingContainer: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @StateObject private var permissions = PermissionsManager.shared
    @State private var currentStep = 0
    @State private var selectedMode: GeminiLinkLogic.GitMode = .localOnly
    @Environment(\.closeOnboarding) var closeOnboarding
    
    var body: some View {
        VStack {
            if currentStep == 0 {
                welcomeView
            } else if currentStep == 1 {
                animationDemoView
            } else if currentStep == 2 {
                modeSelectionView
            } else if currentStep == 3 {
                accessibilityPermissionView  // 独立的 Accessibility 步骤
            } else if currentStep == 4 {
                gitPermissionsView           // Git 权限步骤（条件性）
            } else if currentStep == 5 {
                geminiSetupView
            }
        }
        .frame(width: 600, height: 520)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Step 0: Welcome
    var welcomeView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "sparkles")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.bounce, value: currentStep)
            
            VStack(spacing: 12) {
                Text("Welcome to Invoke")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("AI-powered coding assistant\nSeamlessly integrated with Gemini")
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { withAnimation { currentStep = 1 } }) {
                Text("See How It Works")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 60)
            
            Spacer().frame(height: 20)
        }
        .padding()
    }
    
    // MARK: - Step 1: Animation Demo
    var animationDemoView: some View {
        VStack(spacing: 20) {
            Text("How Invoke Works")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Watch the magic flow")
                .font(.callout)
                .foregroundColor(.secondary)
            
            Spacer().frame(height: 10)
            
            // 动画演示区域
            WorkflowAnimationView()
                .frame(height: 280)
            
            Spacer()
            
            Button(action: { withAnimation { currentStep = 2 } }) {
                HStack {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 60)
            
            Button(action: { withAnimation { currentStep = 0 } }) {
                Text("Back")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer().frame(height: 10)
        }
        .padding()
    }
    
    // MARK: - Step 2: Mode Selection
    var modeSelectionView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                Text("Choose Your Mode")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("You can change this anytime")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                ModeOptionCard(
                    mode: .localOnly,
                    selected: selectedMode == .localOnly,
                    onSelect: { selectedMode = .localOnly }
                )
                
                ModeOptionCard(
                    mode: .safe,
                    selected: selectedMode == .safe,
                    onSelect: { selectedMode = .safe }
                )
                
                ModeOptionCard(
                    mode: .yolo,
                    selected: selectedMode == .yolo,
                    onSelect: { selectedMode = .yolo }
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                withAnimation { currentStep = 3 }  // 总是先去 Accessibility 步骤
            }) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 60)
            
            Button(action: { withAnimation { currentStep = 1 } }) {
                Text("Back")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer().frame(height: 10)
        }
        .padding()
    }
    
    // MARK: - Step 3: Permissions
    var permissionsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "hand.raised.square.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 70, height: 70)
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Git Access Required")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Mode: \(selectedMode.rawValue)")
                    .font(.callout)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                Text("Invoke needs accessibility permission to auto-paste in browser")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                PermissionRow(
                    icon: "keyboard",
                    title: "Accessibility Access",
                    description: "Required to auto-paste code in browser",
                    isGranted: permissions.accessibilityPermission.isGranted
                )
            }
            .padding()
            .background(Color.black.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            if permissions.accessibilityPermission.isGranted {
                Button(action: {
                    withAnimation { currentStep = 4 }
                }) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal, 60)
            } else {
                Button(action: {
                    permissions.requestAccessibilityPermission()
                }) {
                    Text("Grant Access")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 60)
                
                Text("Will open System Settings")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Button(action: { withAnimation { currentStep = 2 } }) {
                Text("Back")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer().frame(height: 20)
        }
        .padding()
        .onAppear {
            permissions.checkAccessibilityPermission()
        }
    }
    
    // MARK: - Step 4: Gemini Setup
    var geminiSetupView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            HStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                
                Image(systemName: "link")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("One More Thing")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Connect Gemini with your repository")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(number: "1", text: "Open gemini.google.com")
                InstructionRow(number: "2", text: "Start a new conversation")
                InstructionRow(number: "3", text: "Click the attachment icon (📎)")
                InstructionRow(number: "4", text: "Select 'Add GitHub repository'")
                InstructionRow(number: "5", text: "Connect your project repository")
            }
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Text("✨ This allows Gemini to see your latest code changes automatically")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                // 保存选择的模式
                UserDefaults.standard.set(selectedMode.rawValue, forKey: "GitMode")
                hasCompletedOnboarding = true
                
                // 关闭 onboarding window 并显示主面板
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    closeOnboarding()
                }
            }) {
                HStack {
                    Text("Start Coding")
                    Image(systemName: "arrow.right.circle.fill")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .padding(.horizontal, 60)
            
            Button(action: { withAnimation { currentStep = selectedMode == .localOnly ? 3 : 4 } }) {
                Text("Back")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer().frame(height: 10)
        }
        .padding()
    }
    
    // MARK: - Step 3: Accessibility Permission (Required for All)
    var accessibilityPermissionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "hand.raised.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 70, height: 70)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.bounce, value: permissions.accessibilityPermission.isGranted)
            
            VStack(spacing: 8) {
                Text("Accessibility Required")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Essential for auto-paste functionality")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: permissions.accessibilityPermission.isGranted ? "checkmark.circle.fill" : "keyboard")
                        .font(.title2)
                        .foregroundColor(permissions.accessibilityPermission.isGranted ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permission")
                            .fontWeight(.semibold)
                        Text("Allows Invoke to auto-paste code into browser")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if permissions.accessibilityPermission.isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            if permissions.accessibilityPermission.isGranted {
                Button(action: {
                    withAnimation { 
                        currentStep = selectedMode.needsGitPermission ? 4 : 5 
                    }
                }) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal, 60)
            } else {
                Button(action: {
                    permissions.requestAccessibilityPermission()
                    // 给用户一点时间去设置权限
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        permissions.checkAccessibilityPermission()
                    }
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Grant Access")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 60)
                
                Text("Will open System Settings → Privacy & Security → Accessibility")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(action: { withAnimation { currentStep = 2 } }) {
                Text("Back")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer().frame(height: 10)
        }
        .padding()
        .onAppear {
            // 每次显示时检查权限状态
            permissions.checkAccessibilityPermission()
        }
    }
    
    // MARK: - Step 4: Git Permissions (Conditional)
    var gitPermissionsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "key.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 70, height: 70)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("Git Access Required")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Mode: \(selectedMode.rawValue)")
                    .font(.callout)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                Text("Your selected mode requires Git credentials to push changes")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GitHub/GitLab Credentials")
                            .fontWeight(.semibold)
                        Text("Required for push operations (\(selectedMode.description))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .background(Color.black.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Text("Git credentials will be requested when you first push changes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                withAnimation { currentStep = 5 }
            }) {
                HStack {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 60)
            
            Button(action: { withAnimation { currentStep = 3 } }) {
                Text("Back")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer().frame(height: 10)
        }
        .padding()
    }
}
