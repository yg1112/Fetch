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



