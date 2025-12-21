# Invoke - Project Architecture

## Overview
Invoke is a macOS utility app built with SwiftUI. It uses modular MVVM architecture adapted from Reso's proven patterns.

## Directory Structure

```
Sources/Invoke/
├── main.swift                 # Application entry point (AppDelegate, window setup)
├── InvokeApp.swift            # SwiftUI App protocol (if needed)
├── Features/
│   └── ToolLogic.swift       # Core tool functionality (your custom logic here)
├── UI/
│   ├── Main/
│   │   ├── HeaderView.swift       # Top bar with app icon (hand.rays)
│   │   ├── ContentView.swift      # Main tool interface placeholder
│   │   └── FooterView.swift       # Bottom controls (settings, quit)
│   ├── Onboarding/
│   │   ├── OnboardingContainer.swift  # Master onboarding state machine
│   │   ├── WelcomeStep.swift         # Welcome screen
│   │   ├── PermissionStep.swift      # Permission requests
│   │   └── ReadyStep.swift           # Final "all set" screen
│   └── Components/
│       ├── VisualEffectView.swift    # macOS blur effects
│       ├── PrimaryButton.swift       # Standard button style
│       └── ...
├── Services/
│   └── PermissionsManager.swift  # System permission handling
└── SharedTypes.swift            # Enums, constants, shared models
```

## Data Flow

```
main.swift (AppDelegate)
    ↓
    ├─ Check if onboarding needed
    │  ├─ Yes → Show OnboardingView
    │  │        → finishLaunch() on completion
    │  └─ No  → finishLaunch()
    ↓
finishLaunch()
    ├─ Initialize PermissionsManager
    ├─ Setup StatusBarController (menu)
    ├─ Create FloatingPanel with main UI
    └─ Show/hide panel based on app state
```

## Key Files

### Entry Point
- **main.swift**: AppDelegate + NSApplication.shared setup
  - Shows onboarding on first launch
  - Creates floating panel window
  - Manages menu bar integration

### Onboarding Flow
- **OnboardingContainer.swift**: Master state machine (Step enum)
- **WelcomeStep.swift**: Intro screen with `hand.rays` icon
- **PermissionStep.swift**: Requests necessary permissions
- **ReadyStep.swift**: Completion screen

### Main UI
- **HeaderView.swift**: Icon + title bar
- **ContentView.swift**: Your tool's main interface (empty initially)
- **FooterView.swift**: Settings + Quit buttons

### Services
- **PermissionsManager.swift**: Handles system permissions (microphone, accessibility, etc.)

## Development Workflow

### Adding a New Feature
1. Create `Features/YourFeature.swift` with the business logic
2. Create corresponding UI component in `UI/` if needed
3. Wire it into `ContentView.swift` for display
4. Update `SharedTypes.swift` if you need shared models

### Modifying Onboarding
1. Edit `OnboardingContainer.swift` to add/remove steps
2. Create new step views as needed (e.g., `CustomStep.swift`)
3. Keep each step view under 200 lines

### Changing Visual Style
1. Main app window: `UI/Main/HeaderView.swift`
2. Button styling: `UI/Components/PrimaryButton.swift`
3. App-wide colors: Define in `SharedTypes.swift`

## Notable Design Decisions

### Why Modular?
- Easy to test individual components
- Simple to swap UI without affecting logic
- Clear responsibility separation (SOLID principles)

### Why MVVM?
- Publishers/Subscribers for reactive updates
- Views stay simple, state lives in ViewModels
- Easy to debug (state is explicit)

### Why Copy Reso's Patterns?
- Proven on macOS 13+
- Clean onboarding flow
- Professional window management

## Quick Checklist for Adding Permissions

If your tool needs a new permission (e.g., Calendar, Contacts):

1. Add to `PermissionsManager.swift`:
   ```swift
   @Published var customPermission: PermissionStatus = .notDetermined
   func requestCustomPermission() { ... }
   ```

2. Add step to `OnboardingContainer.swift`:
   ```swift
   enum Step { case welcome, permissions, custom, ready }
   ```

3. Create `CustomPermissionStep.swift` in `UI/Onboarding/`

4. Update `main.swift` check:
   ```swift
   let needsOnboarding = !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") || !PermissionsManager.shared.areAllGranted()
   ```

## Next Steps

1. Implement your core tool logic in `Features/ToolLogic.swift`
2. Build UI for it in `UI/Main/ContentView.swift`
3. Wire into the onboarding flow if setup is needed
4. Test on macOS 13+
