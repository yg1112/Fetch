import SwiftUI

struct FooterView: View {
    let onSettings: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            
            Button(action: onSettings) {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
            
            Button(action: onQuit) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    FooterView(onSettings: {}, onQuit: {})
}
