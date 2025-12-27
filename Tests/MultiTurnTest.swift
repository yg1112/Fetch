import Foundation
import WebKit

@MainActor
class MultiTurnStressTest {

    static func main() async {
        print("=== Multi-Turn Stress Test ===")
        print("Testing 5 consecutive turns without UI...")

        // Initialize GeminiWebManager
        let manager = GeminiWebManager.shared

        // Wait for initialization
        print("⏳ Waiting for WebView to be ready...")
        while !manager.isReady {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        if !manager.isLoggedIn {
            print("❌ Not logged in to Gemini. Please login first.")
            exit(1)
        }

        print("✅ Ready. Starting test...")

        let testMessages = [
            "What is 2+2?",
            "What color is the sky?",
            "Tell me a short joke",
            "What day comes after Monday?",
            "Count to 3"
        ]

        for (index, message) in testMessages.enumerated() {
            let turnNumber = index + 1
            print("\n📤 Turn \(turnNumber): \(message)")

            let startTime = Date()

            do {
                let response = try await manager.askGemini(prompt: message, isFromAider: false)
                let elapsed = Date().timeIntervalSince(startTime)

                print("✅ Turn \(turnNumber) SUCCESS (\(String(format: "%.2f", elapsed))s)")
                print("   Response length: \(response.count) chars")
                print("   Preview: \(response.prefix(100))...")

                // Small delay between turns
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                print("❌ Turn \(turnNumber) FAILED after \(String(format: "%.2f", elapsed))s")
                print("   Error: \(error)")

                // Check manager state
                print("   Manager state: isReady=\(manager.isReady), isLoggedIn=\(manager.isLoggedIn), isProcessing=\(manager.isProcessing)")

                exit(1)
            }
        }

        print("\n🎉 All 5 turns completed successfully!")
        exit(0)
    }
}

// Run on main thread
Task { @MainActor in
    await MultiTurnStressTest.main()
}

RunLoop.main.run()
