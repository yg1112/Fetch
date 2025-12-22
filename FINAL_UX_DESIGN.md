# 🎯 Invoke 6.0 - 最终交互逻辑

## 📊 核心设计理念

**问题域：** AI 协同编程的"最后一公里" - 从 Gemini 对话到代码落地的自动化
**解决方案：** 双按钮 + 模式选择 + 自动监听

---

## 🎛️ 界面布局

```
┌─────────────────────────────────────┐
│ ● Invoke             Mode: [YOLO▼] │
├─────────────────────────────────────┤
│                                     │
│  f63e6e1 ↗  Update: cleanup.sh     │
│  a1b2c3d ↗  Fix: MagicPaster       │
│                                     │
├─────────────────────────────────────┤
│   [Pair]       │      [Review]      │
└─────────────────────────────────────┘
```

---

## 🔧 核心组件

### 1. **模式选择器** (Mode Selector)

位于顶部，两种模式：

#### YOLO 模式（默认）
- **行为：** 检测到代码 → 自动写入 → **直接 Push** 到 main
- **适用：** 个人项目、快速迭代、完全信任 AI
- **权限：** 需要 Git push 权限（Keychain 授权）

#### Safe 模式
- **行为：** 检测到代码 → 自动写入 → **创建分支 + Push** → 提示用户开 PR
- **适用：** 团队项目、需要 Code Review、生产环境
- **权限：** 需要 Git push 权限（Keychain 授权）

**设计决策：**
- 让用户**主动选择**权限级别，而不是系统强制
- 点击 "Always Allow" 后，1 小时内不再弹窗
- Safe 模式仍然是自动化的，只是多了一个 PR 环节

---

### 2. **Pair 按钮** - 发送通讯协议

#### 作用
建立 Gemini 的"通讯规则"，让 AI 知道如何格式化代码输出。

#### 执行流程
1. 扫描项目文件结构
2. 构造包含 Base64 协议的 Prompt
3. 复制到剪贴板
4. **自动粘贴**到 Gemini（如果有辅助功能权限）
5. Gemini 回复 "Ready? Await my instructions."

#### 发送的协议内容
```
You are my Senior AI Pair Programmer.
Current Project Context:
- Sources/Invoke/main.swift
- Sources/Invoke/Services/GitService.swift
...

【PROTOCOL - STRICTLY ENFORCE】:
1. When I ask for changes, DO NOT explain.
2. Output only the CHANGED files using this Base64 format:

```text
!!!B64_START!!! <relative_path>
<base64_string_of_full_file_content>
!!!B64_END!!!
```

3. If multiple files change, output multiple blocks.
4. I will auto-apply these changes.

Ready? Await my instructions.
```

#### 何时需要 Pair？

**✅ 需要 Pair 的场景：**
1. 第一次使用 Invoke
2. 关闭浏览器后重新打开
3. Gemini 开启新对话
4. Gemini 回复变成普通对话（忘记协议）

**❌ 不需要 Pair 的场景：**
- 在同一个对话中连续提问
- Gemini 仍然按 Base64 格式回复

**自动检测机制：**
- 如果剪贴板中没有 `!!!B64_START!!!` 标记
- 系统会在日志中提示："⚠️ No valid Base64 blocks found"
- 用户看到提示后，点击 Pair 重新建立协议

---

### 3. **自动监听** - 无需手动触发

#### 触发时机
**选择项目根目录后，自动开启监听** ✅

这是关键的 UX 优化！用户不需要记得点击 "Sync" 按钮。

#### 监听逻辑
```
每秒检测剪贴板 →
  发现 !!!B64_START!!! →
    解析文件路径和内容 →
      写入本地文件 →
        自动 Git add + commit →
          根据模式执行：
            YOLO → push
            Safe → create branch + push
```

#### 用户体验
1. 在 Gemini 中对话："请优化 MagicPaster.swift"
2. Gemini 回复 Base64 代码
3. **点击复制按钮**
4. **听到 "Glass" 音效** ✅
5. **看到 macOS 通知**："Pushed: Update MagicPaster.swift"
6. **Invoke 窗口显示新 commit**

**完全无缝！** 用户只需要点一次"复制"。

---

### 4. **Review 按钮** - 验证最后改动

#### 作用
让 Gemini 审查最后一次提交，形成"修复循环"。

#### 执行流程
1. 读取最后一个 commit 的 diff
2. 构造 Review Prompt
3. 自动粘贴到 Gemini
4. Gemini 分析代码：
   - ✅ **正确：** 回复 "Verified - changes look good!"
   - ❌ **有问题：** 给出新的 Base64 修复代码

#### Review Prompt 内容
```
Please REVIEW this commit I just made:

**Commit:** f63e6e1
**Summary:** Update: cleanup_unused.sh

**Changes:**
```diff
- old code
+ new code
```

**Task:**
1. Analyze if the changes are correct.
2. If CORRECT, reply: "✅ Verified - changes look good!"
3. If there are ISSUES, provide the FIX using Base64 Protocol.

Ready to review?
```

#### 修复循环
```
代码改动 → Review → 发现问题 → Gemini 给新代码 →
用户复制 → 自动写入 → 自动提交 → Review → ...
```

直到 Gemini 确认 "Verified"。

---

## 🎬 完整工作流演示

### 场景 1: 首次使用

1. **启动 Invoke**
   ```bash
   open Invoke.app
   ```

2. **选择项目**
   - 点击 "Select Project..."
   - 选择 `/Users/yukungao/github/Invoke`
   - ✅ 自动开启监听（绿点亮起）

3. **选择模式**
   - YOLO（个人项目，快速迭代）
   - Safe（团队项目，需要 PR）

4. **建立通讯协议**
   - 打开 Chrome → gemini.google.com
   - 点击 Invoke 的 **"Pair"** 按钮
   - Chrome 自动填入协议
   - Gemini 回复 "Ready? Await..."

5. **开始编程**
   ```
   你: 请优化 MagicPaster.swift，支持多浏览器
   
   Gemini: [输出 Base64 代码]
   
   你: [点击复制]
   
   Invoke: 🔍 检测到代码
          ✅ 写入文件
          🚀 Git commit & push (YOLO)
          🔔 通知: "Pushed: Update MagicPaster"
          🔊 Glass 音效
   ```

6. **验证改动**
   - 点击 Invoke 的 **"Review"** 按钮
   - Gemini 自动收到 diff
   - Gemini 分析："✅ Verified!"

7. **继续开发**
   ```
   你: 现在请添加 Safari 支持
   
   Gemini: [输出新的 Base64 代码]
   
   你: [点击复制]
   
   Invoke: 自动处理 → commit → push
   ```

---

### 场景 2: 断点续用

**第二天打开浏览器：**

1. Chrome 中打开昨天的 Gemini 对话
2. 继续提问："请修复昨天的 bug"
3. Gemini 回复普通文字（忘记协议）❌
4. **点击 Invoke 的 "Pair"** 重新建立协议
5. Gemini 回复 "Ready!"
6. 再次提问，Gemini 恢复 Base64 输出 ✅

**检测逻辑：**
- 用户点击复制
- Invoke 检测剪贴板
- 没有 `!!!B64_START!!!` 标记
- 日志提示："⚠️ No valid Base64 blocks found"
- 用户意识到需要重新 Pair

---

### 场景 3: Safe 模式 + Review 循环

1. **切换到 Safe 模式**
   - 点击顶部 Mode 选择器
   - 选择 "Safe"

2. **提出改动**
   ```
   你: 请重构 GitService.swift
   
   Gemini: [Base64 代码]
   
   你: [点击复制]
   
   Invoke: 🔍 检测到代码
          ✅ 写入文件
          🌿 创建分支: invoke-a1b2c3d
          🚀 Push 分支
          🔔 通知: "PR Ready - Branch: invoke-a1b2c3d"
   ```

3. **Review 发现问题**
   - 点击 **"Review"**
   - Gemini 分析："❌ 发现逻辑错误，修复如下..."
   - Gemini 给出新的 Base64 代码

4. **修复循环**
   ```
   你: [点击复制]
   
   Invoke: 再次自动处理
   
   点击 Review → Gemini: "✅ Verified!"
   ```

5. **去 GitHub 开 PR**
   - 点击 commit 编号（蓝色超链接）
   - 浏览器打开 GitHub
   - 看到新分支提示
   - 点击 "Create Pull Request"

---

## 🔍 关键技术细节

### 断点续用检测

**问题：** 如何判断 Gemini 是否还记得协议？

**方案：**
1. **不主动检测** - 让用户通过结果判断
2. 如果 Gemini 回复普通文字 → 用户复制 → Invoke 提示 "No Base64"
3. 用户看到提示 → 点击 Pair
4. 重新建立协议

**为什么不自动 Pair？**
- 无法判断 Gemini 当前状态（技术限制）
- 用户可能只是在普通对话
- 避免误触发

### 自动监听 vs 手动触发

**设计决策：选择项目后自动开启**

**理由：**
1. 减少用户操作步骤
2. "监听"是无成本的（只是检测剪贴板）
3. 用户已经选择了项目，意图明确
4. 绿点始终显示状态，不会误解

### Git 权限与 Keychain

**问题：** 每次 push 都弹 Keychain

**解决：**
1. 配置 credential helper 缓存（1 小时）
2. 引导用户点击 "Always Allow"
3. YOLO/Safe 模式让用户主动选择权限级别

**最佳实践：**
- 第一次弹窗时，点击 "Always Allow"
- 之后 1 小时内完全无感

---

## 📊 对比：旧版 vs 新版

| 功能 | 旧版 | 新版 |
|------|------|------|
| **监听触发** | 手动点击 Sync | 选择项目后自动 |
| **Git 操作** | 只支持 push | YOLO/Safe 两种模式 |
| **Review** | 每个 commit 单独验证 | 只验证最后一次 |
| **断点续用** | 不支持 | 提示用户重新 Pair |
| **Keychain** | 每次弹 2 次 | Always Allow 后不弹 |
| **按钮名称** | Sync（歧义） | Review（明确） |

---

## ✅ 用户操作清单

### 首次设置（一次性）
- [ ] 授予辅助功能权限
- [ ] 选择项目根目录
- [ ] 选择 Git 模式（YOLO/Safe）
- [ ] 点击 Pair 建立协议
- [ ] Keychain 弹窗点 "Always Allow"

### 日常使用（每次）
- [ ] 在 Gemini 对话："请修改 XXX"
- [ ] 点击复制按钮
- [ ] （等待自动处理）
- [ ] 点击 Review 验证
- [ ] （如有问题）继续修复循环

### 断点续用
- [ ] 打开之前的 Gemini 对话
- [ ] 点击 Pair 重新建立协议
- [ ] 继续开发

---

## 🎉 最终效果

**用户视角的完整体验：**

1. 打开 Invoke，选择项目 → ✅ 绿点亮起
2. 选择模式（YOLO/Safe）
3. 点击 Pair → Gemini 准备就绪
4. 对话 Gemini → 点击复制 → **魔法发生**
5. 听到音效 → 看到通知 → 代码已提交
6. 点击 Review → Gemini 验证
7. 如有问题 → 复制新代码 → 自动修复
8. 点击 commit 编号 → 浏览器查看 diff

**核心优势：**
- 🎯 **零学习成本** - 两个按钮，含义明确
- ⚡ **最少点击** - 只需点"复制"
- 🔄 **自动化** - 检测、写入、提交、推送
- 🛡️ **可控权限** - 用户选择 YOLO/Safe
- 🔗 **无缝集成** - Gemini → Invoke → GitHub

这就是 AI 协同编程的理想形态！🚀
