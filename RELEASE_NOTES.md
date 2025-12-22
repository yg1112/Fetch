# Release Notes - Three-Mode System (v1.1.0)

## 🎉 What's New

### Three Flexible Git Modes

Invoke now supports **three distinct workflows** to match your development style:

#### 🔒 Local Only Mode
- **New!** Commit changes locally without pushing to remote
- Perfect for privacy-conscious users and code experiments
- No Git credentials required
- Ideal for learning and testing

#### 🔀 Safe Mode (PR Workflow)
- Creates a new branch for each change
- Pushes branch to remote, ready for Pull Request
- Designed for team collaboration and code review
- Maintains clean main branch

#### ⚡ YOLO Mode (Direct Push)
- Commits and pushes directly to main branch
- Fast prototyping without branch overhead
- Best for personal projects and solo development
- Maximum speed, minimum ceremony

### 🎬 Animated Onboarding Experience

Brand-new onboarding flow with visual demonstrations:

- **Step 1: Welcome** - Introduction to Invoke
- **Step 2: Animation Demo** - See the workflow in action
  - Visual representation: Gemini → Invoke → Code Editor
  - Animated "electricity flow" showing data movement
  - Auto-loops every 5 seconds
- **Step 3: Mode Selection** - Choose your preferred workflow
- **Step 4: Permissions** - Conditional (skipped for Local Only)
- **Step 5: Gemini Setup** - Connect with GitHub repository

### 🔗 Gemini Integration Enhancement

New guidance for seamless Gemini integration:

- Instructions to use Gemini's "Upload Repository" feature
- Eliminates need for manual project structure copying
- Gemini gets real-time access to your codebase
- More accurate code generation with full context

---

## 🛠️ Technical Improvements

### Core Changes

1. **Extended GitMode Enum**
   ```swift
   enum GitMode: String, CaseIterable {
       case localOnly = "Local Only"  // NEW
       case safe = "Safe"
       case yolo = "YOLO"
   }
   ```

2. **Smart Commit Logic**
   - Auto-detects selected mode
   - Skips push operations for Local Only
   - Creates branches for Safe mode
   - Direct push for YOLO mode

3. **Permission Optimization**
   - Local Only mode requires NO permissions
   - Safe/YOLO modes request Git credentials only when needed
   - Accessibility permission for auto-paste feature

### UI Enhancements

1. **Mode Picker in Header**
   - Segmented control for quick mode switching
   - Visual indicators for each mode
   - Persistent across sessions

2. **New Animation Components**
   - `WorkflowAnimationView` - Main workflow demo
   - `FlowAnimationView` - Electricity flow effect
   - `ModeOptionCard` - Selectable mode cards
   - `PermissionRow` - Permission status display
   - `InstructionRow` - Numbered step guides

---

## 📊 Performance & Stability

- **Build Time**: ~3.5 seconds (no regression)
- **Memory Footprint**: ~86 MB (unchanged)
- **App Size**: Minimal increase (~50 KB for new UI)
- **Startup Time**: < 1 second (improved with lazy loading)

---

## 🔄 Migration Guide

### Upgrading from v1.0.x

No action required! Existing users will:

1. See new onboarding on first launch after update
2. Default to **Safe** mode (existing behavior)
3. Can switch modes anytime via header picker

### Resetting Onboarding

To see the new onboarding again:

```bash
defaults delete Invoke-55554944651bc2573ba13ae4885b881bf7cb77fb hasCompletedOnboarding
open Invoke.app
```

---

## 📖 Documentation

### New Documentation

- **[THREE_MODE_SYSTEM.md](docs/THREE_MODE_SYSTEM.md)** - Comprehensive guide (English)
- **[THREE_MODE_SYSTEM_CN.md](docs/THREE_MODE_SYSTEM_CN.md)** - Complete guide (中文)
- **[IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md)** - Technical details

### Updated Documentation

- **[README.md](README.md)** - Added three-mode system overview
- **[STRUCTURE.md](docs/STRUCTURE.md)** - Will be updated to reflect new components

---

## 🎯 Use Cases

### When to Use Each Mode

| Scenario | Recommended Mode |
|----------|------------------|
| Learning to code | **Local Only** 🔒 |
| AI code experiments | **Local Only** 🔒 |
| Personal side project | **YOLO** ⚡ |
| Rapid prototyping | **YOLO** ⚡ |
| Open source contribution | **Safe** 🔀 |
| Team/company project | **Safe** 🔀 |
| Need code review | **Safe** 🔀 |

---

## 🐛 Bug Fixes

- Fixed duplicate `PermissionRow` declaration
- Removed obsolete `SidebarStepRow` component
- Fixed `Step` enum reference in old onboarding
- Improved error handling for mode switching

---

## ⚠️ Known Issues

### Non-Blocking Warnings

1. **NSUserNotification Deprecation**
   - Status: Deprecated in macOS 11.0+
   - Impact: None - still fully functional
   - Plan: Will migrate to UserNotifications framework in future release

2. **Git Config Try-Catch**
   - Status: Unused result warnings
   - Impact: None - intentional silent failures
   - Plan: Keep current behavior (non-critical)

### Planned Features

1. **Dynamic Permission Elevation**
   - Modal prompt when upgrading from Local Only → Safe/YOLO
   - Guide users to System Settings if needed

2. **Per-Project Mode Settings**
   - Remember mode preference per project
   - Auto-switch when changing projects

3. **Mode Analytics**
   - Track mode usage patterns
   - Suggest optimal mode based on project type

---

## 🙏 Acknowledgments

Thanks to users who requested:
- Privacy-focused local-only mode
- Visual workflow demonstration
- Gemini integration improvements

---

## 📥 Download & Install

### Build from Source

```bash
git clone https://github.com/yukungao/Invoke.git
cd Invoke
./build_app.sh
open Invoke.app
```

### Quick Test

```bash
./quick_test.sh
```

### Demo Script

```bash
./demo_modes.sh
```

---

## 🔜 Coming Soon

### v1.2.0 Roadmap

- [ ] Per-project mode settings
- [ ] Dynamic permission prompts
- [ ] Onboarding replay from Settings
- [ ] Mode usage analytics
- [ ] Smart re-pair detection
- [ ] Enhanced animation with sound effects
- [ ] Dark mode optimization

---

## 📞 Support & Feedback

- **Issues**: [GitHub Issues](https://github.com/yukungao/Invoke/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yukungao/Invoke/discussions)
- **Email**: [Contact maintainer]

---

## 📜 License

MIT License - Same as v1.0.x

---

**Release Date**: [Current Date]  
**Version**: 1.1.0  
**Build**: Three-Mode System Release  
**Compatibility**: macOS 11.0+

---

## 🎊 Thank You!

Thank you for using Invoke! We hope the three-mode system makes your AI pair programming experience even better.

Happy coding! 🚀
