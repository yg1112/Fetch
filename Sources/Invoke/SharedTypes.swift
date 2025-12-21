import SwiftUI

// MARK: - Colors
let accentColor = Color(red: 0.2, green: 0.8, blue: 0.8) // Cyan/Teal

// MARK: - Permission Status
enum PermissionStatus {
    case notDetermined, granted, denied
    
    var isGranted: Bool {
        self == .granted
    }
}

// MARK: - Window Sizes
struct WindowSize {
    static let onboarding = NSSize(width: 720, height: 440)
    static let main = NSSize(width: 280, height: 40)
}

// MARK: - UI Constants
struct UIConstants {
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 12
}

// MARK: - Notifications
extension NSNotification.Name {
    static let permissionsGranted = NSNotification.Name("permissionsGranted")
    static let onboardingCompleted = NSNotification.Name("onboardingCompleted")
}
