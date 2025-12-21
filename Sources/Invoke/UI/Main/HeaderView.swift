import SwiftUI

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.rays")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .cyan)
                .frame(width: 24, height: 24)
                .shadow(color: Color.cyan.opacity(0.5), radius: 6, x: 0, y: 0)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Invoke")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Ready")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    HeaderView()
}
