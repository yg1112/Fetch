import SwiftUI

struct PrimaryButton: View {
    let title: String
    var color: Color?
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(isDisabled ? Color.primary.opacity(0.1) : (color ?? invokeTealColor))
                .foregroundColor(isDisabled ? Color.secondary : .white)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .focusable(false)
    }
}

struct HeaderTextView: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    @Binding var isGranted: Bool
    var accentColor: Color?
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isGranted ? .green : .primary)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            } else {
                Button("Allow") { action() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(accentColor ?? invokeTealColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((accentColor ?? invokeTealColor).opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Step Sidebar Row
struct SidebarStepRow: View {
    let step: OnboardingContainer.Step
    let currentStep: OnboardingContainer.Step
    var accentColor: Color?
    
    var isActive: Bool { currentStep == step }
    var isCompleted: Bool { currentStep.rawValue > step.rawValue }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(accentColor ?? invokeTealColor)
                } else {
                    Image(systemName: step.icon)
                        .foregroundColor(isActive ? (accentColor ?? invokeTealColor) : .secondary.opacity(0.5))
                }
            }
            .frame(width: 16)
            
            Text(step.title)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? .primary : .secondary)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isActive ? Color.black.opacity(0.05) : Color.clear)
        .cornerRadius(6)
    }
}
