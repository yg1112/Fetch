# Three-Mode System Guide

## Overview

Invoke now supports **three Git modes** to match different workflow preferences and security requirements:

### 🔒 Local Only
- **What it does**: Commits changes locally without pushing to remote
- **Best for**: Privacy-conscious users, experimenting with code, offline work
- **Permissions needed**: None (no Git credentials required)
- **Workflow**: Gemini → Invoke → Local Git commit (stops here)

### 🔀 Safe (PR Mode)
- **What it does**: Creates a new branch and pushes for Pull Request
- **Best for**: Team environments, code review workflows
- **Permissions needed**: Git credentials (GitHub/GitLab access)
- **Workflow**: Gemini → Invoke → Branch → Push → PR ready

### ⚡ YOLO (Direct Push)
- **What it does**: Commits and pushes directly to main branch
- **Best for**: Personal projects, solo developers, rapid prototyping
- **Permissions needed**: Git credentials (GitHub/GitLab access)
- **Workflow**: Gemini → Invoke → Commit → Push to main

---

## Onboarding Experience

### New 5-Step Flow

1. **Welcome Screen**
   - Brief introduction to Invoke
   - "See How It Works" button to continue

2. **Animated Demo** ✨
   - Visual workflow demonstration
   - Shows: Gemini → Invoke → Code Editor
   - Animated "electricity flow" effect
   - Automatic loop every 5 seconds

3. **Mode Selection**
   - Choose your preferred Git workflow
   - Card-based UI with descriptions
   - Icons and color coding for each mode

4. **Permissions** (conditional)
   - Skipped if "Local Only" mode selected
   - Shows required permissions:
     - Accessibility (for auto-paste)
     - Git Credentials (for push/PR)
   - Real-time status checks

5. **Gemini GitHub Setup**
   - Instructions to connect Gemini with your repository
   - 5-step guide for using "Upload Repository" feature
   - Enables Gemini to see real-time code context

---

## Runtime Mode Switching

### Changing Modes in Use

You can switch modes at any time via the **Mode Picker** in the header:

```
[Local Only] [Safe] [YOLO]
```

**Dynamic Permission Elevation:**
- Switching from **Local Only** → **Safe/YOLO** will trigger permission requests
- Switching from **Safe** ↔ **YOLO** requires no additional permissions
- Downgrading to **Local Only** disables push operations immediately

---

## Technical Details

### Mode Detection Logic

```swift
enum GitMode: String, CaseIterable {
    case localOnly = "Local Only"
    case safe = "Safe"
    case yolo = "YOLO"
    
    var description: String {
        switch self {
        case .localOnly: return "Local commits only"
        case .safe: return "Create PR"
        case .yolo: return "Direct Push"
        }
    }
}
```

### Auto-Commit Behavior

```swift
private func autoCommitAndPush(message: String, summary: String) {
    // 1. Always commit locally first
    _ = try GitService.shared.commitChanges(...)
    
    // 2. Check mode and act accordingly
    if gitMode == .localOnly {
        // Stop here - no push
        showNotification(title: "Local Commit", body: summary)
        return
    }
    
    if gitMode == .yolo {
        // Direct push to main
        _ = try GitService.shared.pushToRemote(...)
    } else {
        // Create branch and push (PR workflow)
        let branchName = "invoke-\(commitHash)"
        try GitService.shared.createBranch(...)
        _ = try GitService.shared.pushBranch(...)
    }
}
```

---

## User Guidance

### When to Use Each Mode

| Scenario | Recommended Mode |
|----------|------------------|
| Learning to code | **Local Only** |
| Personal side project | **YOLO** |
| Open source contribution | **Safe** |
| Company/team project | **Safe** |
| Experimenting with AI code | **Local Only** |
| Rapid prototyping | **YOLO** |
| Need code review | **Safe** |

### Smart Re-Pairing Detection

**Problem**: How to know when to re-pair with Gemini?

**Solution**: Gemini's "Upload Repository" feature

1. Open your Gemini chat
2. Click the **+** icon → **Upload Repository**
3. Connect your GitHub account
4. Select your repository
5. Gemini now has real-time access to your codebase

**Benefits:**
- No need to manually re-sync project structure
- Gemini sees your latest code automatically
- More accurate code generation
- Reduced clipboard protocol overhead

---

## Animation Components

### WorkflowAnimationView

The onboarding animation demonstrates the full workflow:

```swift
struct WorkflowAnimationView: View {
    @State private var phase: Int = 0
    // Phase 0: Initial state
    // Phase 1: Show "Copy" action in Gemini
    // Phase 2: Show checkmark in Invoke
    // Phase 3: Show code being written
    // Loops every 5 seconds
}
```

**Animation Timing:**
- Phase 0 → 1: 0.5s (Gemini generates code)
- Phase 1 → 2: 1.5s (Invoke processes)
- Phase 2 → 3: 3.0s (Code written to editor)
- Phase 3 → 0: 5.0s (Loop restart)

### FlowAnimationView

Electricity effect between panels:

```swift
struct FlowAnimationView: View {
    // Animated gradient circle moving left to right
    // Creates "flowing electricity" visual
}
```

---

## Next Steps

### Planned Enhancements

1. **Dynamic Permission Prompts**
   - Modal dialog when upgrading mode mid-session
   - Guide users through System Settings if needed

2. **Smart Re-Pair Detection**
   - Check for Base64 markers before processing
   - Notify user if protocol format changes

3. **Mode Analytics**
   - Track which mode is most popular
   - Suggest mode based on usage patterns

4. **Onboarding Skip/Replay**
   - "Don't show again" option
   - Settings panel to replay onboarding

---

## FAQ

**Q: Can I switch modes without restarting the app?**  
A: Yes! Use the mode picker in the header.

**Q: Does Local Only mode require any permissions?**  
A: No. It works completely offline.

**Q: What happens if I switch from YOLO to Safe mid-session?**  
A: All future commits will create PRs instead of direct pushes. Past commits are unaffected.

**Q: Can I use different modes for different projects?**  
A: Currently, the mode is global across all projects. Per-project modes are a planned feature.

**Q: Why is the animation important?**  
A: It visually teaches users the workflow, reducing confusion about how Gemini, Invoke, and their editor interact.

---

## Feedback

If you have suggestions for improving the three-mode system or onboarding experience, please open an issue on GitHub!
