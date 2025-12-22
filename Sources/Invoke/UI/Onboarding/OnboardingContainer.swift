import SwiftUI

struct OnboardingContainer: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @StateObject private var permissions = PermissionsManager.shared
    @State private var currentStep = 0
    @State private var selectedMode: GeminiLinkLogic.GitMode = .localOnly
    
    var body: some View {
        VStack {
            if currentStep == 0 {
                welcomeView
            } else if currentStep == 1 {
                animationDemoView
            } else if currentStep == 2 {
                modeSelectionView
            } else if currentStep == 3 {
                permissionsView
            } else if currentStep == 4 {
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
                withAnimation { currentStep = selectedMode == .localOnly ? 4 : 3 }
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
                withAnimation {
                    hasCompletedOnboarding = true
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
            
            Button(action: { withAnimation { currentStep = selectedMode == .localOnly ? 2 : 3 } }) {
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
