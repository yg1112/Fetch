import SwiftUI

struct AppUI: View {
    let onSettings: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            
            Divider()
                .opacity(0.1)
            
            ContentView()
                .frame(maxHeight: .infinity, alignment: .center)
            
            Divider()
                .opacity(0.1)
            
            FooterView(onSettings: onSettings, onQuit: onQuit)
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

#Preview {
    AppUI(onSettings: {}, onQuit: {})
}
