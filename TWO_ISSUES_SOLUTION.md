# 🔧 两个问题的解决方案

## 问题诊断结果

### 1️⃣ Pair 按钮不自动粘贴

**症状**: 
- ✅ 剪贴板有协议文本
- ❌ 但没有自动插入到浏览器

**根本原因**:
- Invoke.app **没有 Accessibility 权限**
- MagicPaster 使用 `System Events keystroke` 需要这个权限

**解决方法**:
1. 打开系统设置:
   ```bash
   open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
   ```

2. 点击左下角 🔒 解锁

3. 点击 **+** 按钮

4. 导航到并选择:
   ```
   /Users/yukungao/github/Invoke/Invoke.app
   ```

5. 确保 Invoke.app 旁边的勾选框已打勾 ✅

6. 重启 Invoke:
   ```bash
   pkill Invoke && open Invoke.app
   ```

7. 再次测试 Pair 按钮 → 应该能自动粘贴了！

---

### 2️⃣ Onboarding 不显示

**症状**:
- 执行 `defaults delete` 显示 "Domain not found"
- 应用启动后直接进入主界面

**根本原因**:
- `hasCompletedOnboarding` 从未被设置过（首次运行时）
- OnboardingContainer 检查 `hasCompletedOnboarding == false`，但实际上它 **不存在**（nil）
- SwiftUI @AppStorage 的默认值是 `false`，所以条件永远不满足

**解决方法**:

```bash
# 强制设置为 false（这样就能触发 onboarding）
defaults write com.yukungao.invoke hasCompletedOnboarding -bool false

# 重启应用
pkill Invoke && open Invoke.app
```

现在应该能看到 onboarding 动画了！

---

## ✅ 验证步骤

### 验证 Accessibility 权限

```bash
# 方法 1: 使用 tccutil（可能需要 SIP 关闭）
tccutil list Accessibility | grep invoke

# 方法 2: 手动检查
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
# 查找列表中是否有 Invoke.app
```

### 验证 Onboarding 设置

```bash
# 查看当前值
defaults read com.yukungao.invoke hasCompletedOnboarding

# 应该输出: 0 (false)
```

### 测试 Pair 功能

1. 打开浏览器（Chrome/Arc/Safari 都可以）
2. 访问 Gemini
3. 点击 Invoke 的 **Pair** 按钮
4. 观察:
   - ✅ Invoke 窗口短暂消失（<1秒）
   - ✅ 浏览器获得焦点
   - ✅ Gemini 输入框自动填入协议文本

---

## 🎯 快速修复命令（一键执行）

```bash
# 1. 打开 Accessibility 设置
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'

# 2. 手动添加 Invoke.app（需要 GUI 操作）

# 3. 设置 onboarding 为未完成
defaults write com.yukungao.invoke hasCompletedOnboarding -bool false

# 4. 重启应用
pkill Invoke 2>/dev/null
sleep 1
open Invoke.app

# 5. 验证
echo "检查 onboarding 设置:"
defaults read com.yukungao.invoke hasCompletedOnboarding
```

---

## 📝 技术细节

### Accessibility 权限的必要性

MagicPaster 使用以下 AppleScript:

```applescript
tell application "System Events"
    keystroke "v" using {command down}
end tell
```

`System Events` 需要 Accessibility 权限才能模拟键盘输入。

### AppStorage 的陷阱

```swift
@AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
```

- 如果 key 不存在 → 返回默认值 `false`
- 如果 key 存在且值为 `false` → 返回 `false`
- **无法区分"不存在"和"值为 false"**

解决方案：
- 首次运行时显式写入 `false`
- 或者使用 optional: `@AppStorage("...") var x: Bool?`

---

## 🐛 常见问题

**Q: 添加了 Accessibility 权限但还是不能粘贴？**

A: 尝试：
1. 完全关闭 Invoke
2. 打开 Activity Monitor 确认进程已退出
3. 重新打开 Invoke.app
4. 如果还不行，重启 macOS

**Q: Onboarding 还是不显示？**

A: 检查：
```bash
defaults read com.yukungao.invoke
# 应该看到 hasCompletedOnboarding = 0;
```

如果看到 `hasCompletedOnboarding = 1`，说明被设置为已完成。
重新执行：
```bash
defaults write com.yukungao.invoke hasCompletedOnboarding -bool false
```

**Q: 从终端运行 `./Invoke.app/Contents/MacOS/Invoke` 能粘贴，但从 Finder 打开不行？**

A: 这是因为 Terminal 有 Accessibility 权限，但 Invoke.app 没有。
解决：给 Invoke.app 添加权限（见上文）。

---

## ✅ 状态检查清单

- [ ] Accessibility 权限已添加
- [ ] `defaults read com.yukungao.invoke hasCompletedOnboarding` 输出 0
- [ ] Pair 按钮能自动粘贴
- [ ] Onboarding 动画正常显示
- [ ] 三个模式选择器工作正常

---

**当前状态**: 
- ✅ `hasCompletedOnboarding` 已设置为 `false`
- ⏳ 等待添加 Accessibility 权限
- ✅ Invoke.app 正在运行 (PID 42301)
