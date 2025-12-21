import SwiftUI

struct AppUI: View {
    // 这里的回调暂时保留以兼容接口，但实际逻辑移交给 ContentView
    let onSettings: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        // 彻底移除原本的 HeaderView/FooterView 包裹
        // 让 ContentView 接管所有像素的渲染
        ContentView()
            .edgesIgnoringSafeArea(.all)
    }
}
