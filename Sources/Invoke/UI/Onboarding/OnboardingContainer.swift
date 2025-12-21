import SwiftUI
import AVFoundation
import ApplicationServices

struct OnboardingContainer: View {
    var onFinish: () -> Void
    
    enum Step: Int, CaseIterable {
        case welcome = 0
        case permissions
        case ready
        
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .ready: return "Ready"
            }
        }
        
        var icon: String {
            switch self {
            case .welcome: return "hand.rays.fill"
            case .permissions: return "lock.shield.fill"
            case .ready: return "checkmark.seal.fill"
            }
        }
    }
    
    @State private var currentStep: Step = .welcome
    @State private var micPermission = PermissionsManager.shared.microphonePermission.isGranted
    @State private var accessibilityPermission = PermissionsManager.shared.accessibilityPermission.isGranted
    
    private let hermesBlue = Color(red: 0.2, green: 0.8, blue: 0.8)
    private let sidebarBg = Color.black.opacity(0.03)
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            HStack(spacing: 0) {
                // Left Sidebar
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Step.allCases, id: \.self) { step in
                            SidebarStepRow(step: step, currentStep: currentStep)
                        }
                    }
                    .padding(.horizontal, 12)
                    
                    Spacer()
                    
                    Text("Invoke v1.0")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(20)
                }
                .frame(width: 220)
                .background(sidebarBg)
                .border(width: 0.5, edges: [.trailing], color: Color.black.opacity(0.05))
                
                // Right Content
                ZStack {
                    switch currentStep {
                    case .welcome:
                        WelcomeStep(action: nextStep, color: hermesBlue)
                    case .permissions:
                        PermissionStep(mic: $micPermission, acc: $accessibilityPermission, next: nextStep, color: hermesBlue)
                    case .ready:
                        ReadyStep(action: onFinish, color: hermesBlue)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
        }
        .frame(width: 720, height: 440)
        .onAppear {
            micPermission = PermissionsManager.shared.microphonePermission.isGranted
            accessibilityPermission = PermissionsManager.shared.accessibilityPermission.isGranted
        }
    }
    
    func nextStep() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let next = Step(rawValue: currentStep.rawValue + 1) {
                currentStep = next
            }
        }
    }
}

// MARK: - Step Views
struct WelcomeStep: View {
    var action: () -> Void
    var color: Color
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "hand.rays")
                .font(.system(size: 100))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, color)
                .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 8) {
                Text("Invoke")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .multilineTextAlignment(.center)
                
                Text("Power at your fingertips.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            PrimaryButton(title: "Get Started", color: color, action: action)
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }
}

struct PermissionStep: View {
    @Binding var mic: Bool
    @Binding var acc: Bool
    var next: () -> Void
    var color: Color
    
    var body: some View {
        VStack(spacing: 24) {
            HeaderTextView(title: "Permissions", subtitle: "Grant access for optimal experience.")
            
            VStack(spacing: 12) {
                PermissionRow(icon: "mic.fill", title: "Microphone", isGranted: $mic, accentColor: color) {
                    PermissionsManager.shared.requestMicrophonePermission { granted in
                        withAnimation { mic = granted }
                    }
                }
                PermissionRow(icon: "keyboard.fill", title: "Accessibility", isGranted: $acc, accentColor: color) {
                    PermissionsManager.shared.requestAccessibilityPermission()
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                        if AXIsProcessTrusted() {
                            withAnimation { acc = true }
                            timer.invalidate()
                        }
                    }
                }
            }
            
            Spacer()
            PrimaryButton(title: "Continue", color: color, isDisabled: !(mic && acc), action: next)
        }
    }
}

struct ReadyStep: View {
    var action: () -> Void
    var color: Color
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 12) {
                Text("All Set!")
                    .font(.system(size: 24, weight: .bold))
                
                Text("You're ready to go.")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            PrimaryButton(title: "Launch Invoke", color: color, action: action)
        }
    }
}

// MARK: - Helper
extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat = 0, y: CGFloat = 0, w: CGFloat = 0, h: CGFloat = 0
            switch edge {
            case .top: x = rect.minX; y = rect.minY; w = rect.width; h = width
            case .bottom: x = rect.minX; y = rect.maxY - width; w = rect.width; h = width
            case .leading: x = rect.minX; y = rect.minY; w = width; h = rect.height
            case .trailing: x = rect.maxX - width; y = rect.minY; w = width; h = rect.height
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}
