# 三模式系统使用指南

## 概述

Invoke 现在支持 **三种 Git 模式**，以匹配不同的工作流程和安全需求：

### 🔒 Local Only（仅本地）
- **功能**: 仅在本地提交更改，不推送到远程
- **适用场景**: 注重隐私、代码实验、离线工作
- **所需权限**: 无（不需要 Git 凭证）
- **工作流**: Gemini → Invoke → 本地 Git 提交（到此为止）

### 🔀 Safe（安全模式 - PR）
- **功能**: 创建新分支并推送，准备发起 Pull Request
- **适用场景**: 团队协作、代码审查流程
- **所需权限**: Git 凭证（GitHub/GitLab 访问权限）
- **工作流**: Gemini → Invoke → 创建分支 → 推送 → PR 就绪

### ⚡ YOLO（直推模式）
- **功能**: 直接提交并推送到主分支
- **适用场景**: 个人项目、独立开发者、快速原型开发
- **所需权限**: Git 凭证（GitHub/GitLab 访问权限）
- **工作流**: Gemini → Invoke → 提交 → 推送到 main

---

## Onboarding 体验

### 全新 5 步引导流程

1. **欢迎界面**
   - Invoke 简介
   - "查看工作原理"按钮继续

2. **动画演示** ✨
   - 可视化工作流程演示
   - 展示：Gemini → Invoke → 代码编辑器
   - 动态"电流流动"效果
   - 每 5 秒自动循环

3. **模式选择**
   - 选择你偏好的 Git 工作流
   - 卡片式 UI，带详细说明
   - 每个模式有独特图标和颜色标识

4. **权限授予**（条件性）
   - 如果选择"Local Only"则跳过
   - 显示所需权限：
     - 辅助功能（用于自动粘贴）
     - Git 凭证（用于推送/PR）
   - 实时状态检查

5. **Gemini GitHub 配置**
   - 连接 Gemini 与代码仓库的说明
   - 使用"上传仓库"功能的 5 步指南
   - 让 Gemini 能够实时查看代码上下文

---

## 运行时模式切换

### 使用中更改模式

你可以随时通过头部的 **Mode Picker** 切换模式：

```
[Local Only] [Safe] [YOLO]
```

**动态权限提升：**
- 从 **Local Only** → **Safe/YOLO** 会触发权限请求
- **Safe** ↔ **YOLO** 之间切换无需额外权限
- 降级到 **Local Only** 会立即禁用推送操作

---

## 技术细节

### 模式检测逻辑

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

### 自动提交行为

```swift
private func autoCommitAndPush(message: String, summary: String) {
    // 1. 总是先在本地提交
    _ = try GitService.shared.commitChanges(...)
    
    // 2. 根据模式执行相应操作
    if gitMode == .localOnly {
        // 到此为止 - 不推送
        showNotification(title: "本地提交", body: summary)
        return
    }
    
    if gitMode == .yolo {
        // 直接推送到 main
        _ = try GitService.shared.pushToRemote(...)
    } else {
        // 创建分支并推送（PR 工作流）
        let branchName = "invoke-\(commitHash)"
        try GitService.shared.createBranch(...)
        _ = try GitService.shared.pushBranch(...)
    }
}
```

---

## 使用建议

### 何时使用各个模式

| 场景 | 推荐模式 |
|------|---------|
| 学习编程 | **Local Only** |
| 个人业余项目 | **YOLO** |
| 开源贡献 | **Safe** |
| 公司/团队项目 | **Safe** |
| AI 代码实验 | **Local Only** |
| 快速原型开发 | **YOLO** |
| 需要代码审查 | **Safe** |

### 智能重新配对检测

**问题**: 如何判断何时需要重新与 Gemini 配对？

**解决方案**: Gemini 的"上传仓库"功能

1. 打开你的 Gemini 聊天
2. 点击 **+** 图标 → **上传仓库**
3. 连接你的 GitHub 账号
4. 选择你的代码仓库
5. Gemini 现在可以实时访问你的代码库

**优点：**
- 无需手动重新同步项目结构
- Gemini 自动看到最新代码
- 更准确的代码生成
- 减少剪贴板协议开销

---

## 动画组件

### WorkflowAnimationView

Onboarding 动画演示完整工作流：

```swift
struct WorkflowAnimationView: View {
    @State private var phase: Int = 0
    // Phase 0: 初始状态
    // Phase 1: 在 Gemini 中显示"复制"动作
    // Phase 2: 在 Invoke 中显示对勾
    // Phase 3: 显示代码正在写入
    // 每 5 秒循环一次
}
```

**动画时序：**
- Phase 0 → 1: 0.5 秒（Gemini 生成代码）
- Phase 1 → 2: 1.5 秒（Invoke 处理）
- Phase 2 → 3: 3.0 秒（代码写入编辑器）
- Phase 3 → 0: 5.0 秒（循环重启）

### FlowAnimationView

面板之间的电流效果：

```swift
struct FlowAnimationView: View {
    // 动态渐变圆圈从左向右移动
    // 创造"流动电流"的视觉效果
}
```

---

## 下一步计划

### 计划中的增强功能

1. **动态权限提示**
   - 会话中升级模式时的模态对话框
   - 如果需要，引导用户到系统设置

2. **智能重新配对检测**
   - 处理前检查 Base64 标记
   - 如果协议格式更改则通知用户

3. **模式分析**
   - 追踪哪个模式最受欢迎
   - 根据使用模式推荐模式

4. **Onboarding 跳过/重播**
   - "不再显示"选项
   - 设置面板重播 onboarding

---

## 常见问题

**问：可以在不重启应用的情况下切换模式吗？**  
答：可以！使用头部的模式选择器。

**问：Local Only 模式需要任何权限吗？**  
答：不需要。它完全离线工作。

**问：如果我在会话中从 YOLO 切换到 Safe，会发生什么？**  
答：所有未来的提交将创建 PR 而不是直接推送。过去的提交不受影响。

**问：可以为不同项目使用不同模式吗？**  
答：目前，模式在所有项目中是全局的。每个项目的模式是计划中的功能。

**问：为什么动画很重要？**  
答：它直观地教用户工作流程，减少关于 Gemini、Invoke 和编辑器如何交互的困惑。

---

## 反馈

如果你对改进三模式系统或 onboarding 体验有建议，请在 GitHub 上开 issue！
