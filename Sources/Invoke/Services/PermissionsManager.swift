import Foundation
import AVFoundation
import ApplicationServices
import SwiftUI

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()
    
    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var accessibilityPermission: PermissionStatus = .notDetermined
    
    private init() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
    }
    
    func areAllGranted() -> Bool {
        return microphonePermission.isGranted && accessibilityPermission.isGranted
    }
    
    // MARK: - Microphone
    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .granted
        case .denied, .restricted:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .denied
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void = { _ in }) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.microphonePermission = granted ? .granted : .denied
                if granted {
                    self.checkAllPermissionsGranted()
                }
                completion(granted)
            }
        }
    }
    
    // MARK: - Accessibility
    func checkAccessibilityPermission() {
        accessibilityPermission = AXIsProcessTrusted() ? .granted : .denied
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func checkAllPermissionsGranted() {
        if areAllGranted() {
            NotificationCenter.default.post(name: .permissionsGranted, object: nil)
        }
    }
}
