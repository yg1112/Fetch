# Invoke

A macOS utility tool built with SwiftUI, leveraging proven patterns from Reso.

## Features

- Clean onboarding flow
- System permission management
- Modular MVVM architecture
- Floating panel UI
- Settings window

## Building

```bash
swift build -c release
```

## Architecture

See `docs/STRUCTURE.md` for detailed architecture documentation.

## Quick Start

1. Your custom logic goes in `Sources/Invoke/Features/ToolLogic.swift`
2. UI for your tool belongs in `Sources/Invoke/UI/Main/ContentView.swift`
3. Onboarding steps can be customized in `Sources/Invoke/UI/Onboarding/OnboardingContainer.swift`

## Requirements

- macOS 13.0+
- Swift 5.9+
