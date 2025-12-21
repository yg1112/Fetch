import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                
                Text("Your Tool Here")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onTapGesture {
                // Your tool logic here
            }
        }
    }
}

#Preview {
    ContentView()
}
