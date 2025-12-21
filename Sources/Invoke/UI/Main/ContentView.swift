import SwiftUI

struct ContentView: View {
    @StateObject var logic = GeminiLinkLogic()
    
    var body: some View {
        VStack(spacing: 0) {
            // === 1. Top Bar: Project & Status ===
            HStack {
                Circle()
                    .fill(logic.isListening ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: logic.isListening ? .green : .clear, radius: 4)
                
                Text(logic.isListening ? "Listening" : "Paused")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(logic.isListening ? .green : .secondary)
                
                Spacer()
                
                Button(action: logic.selectProjectRoot) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text(logic.projectRoot.isEmpty ? "Select Project" : URL(fileURLWithPath: logic.projectRoot).lastPathComponent)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .padding(4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            
            // === 2. Middle: The Commit Log (Progress) ===
            ZStack {
                Color.black.opacity(0.8)
                
                if logic.changeLogs.isEmpty {
                    Text("No changes yet.\nCopy 'Protocol' to start.")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                } else {
                    List {
                        ForEach(logic.changeLogs) { log in
                            LogRows(log: log, onValidate: {
                                logic.validateCommit(log)
                            }, onToggleStatus: {
                                logic.toggleValidationStatus(for: log.id)
                            })
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(height: 140)
            
            // === 3. Bottom: The Workflow Buttons ===
            HStack(spacing: 0) {
                WorkflowButton(icon: "doc.text.fill", label: "1. Protocol", color: .blue) {
                    logic.copyProtocol()
                }
                
                Divider().frame(height: 20)
                
                WorkflowButton(
                    icon: logic.isListening ? "pause.fill" : "play.fill",
                    label: logic.isListening ? "Stop" : "2. Listen",
                    color: logic.isListening ? .green : .gray
                ) {
                    logic.toggleListening()
                }
            }
            .frame(height: 40)
            .background(Color.gray.opacity(0.1))
        }
        .frame(width: 320)
        .cornerRadius(12)
    }
}

// MARK: - Subviews

struct LogRows: View {
    let log: ChangeLog
    let onValidate: () -> Void
    let onToggleStatus: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(log.commitHash)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.yellow)
                .frame(width: 45, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(log.summary)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundColor(.white)
                Text(log.timestamp, style: .time)
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 0) {
                Button(action: onValidate) {
                    Image(systemName: "text.magnifyingglass")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Copy Validation Prompt")
                .padding(.trailing, 8)
                
                Button(action: onToggleStatus) {
                    Text(log.isValidated ? "YES" : "NO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(log.isValidated ? .green : .red)
                        .frame(width: 24)
                        .padding(2)
                        .background(log.isValidated ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }
}

struct WorkflowButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(color)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
