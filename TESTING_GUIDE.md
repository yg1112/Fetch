# 🎯 Invoke 完整测试指南 - 确保 100% 工作

## 📋 前置条件检查

### 1. 启动 Invoke
```bash
open /Users/yukungao/github/Invoke/Invoke.app
```

### 2. 完成 Onboarding（如果是第一次）
- 点击 "Get Started"
- 点击 "Grant Access" 授予辅助功能权限
- 系统会打开设置，确保 **Invoke** 在辅助功能列表中并已开启
- 返回 Invoke，点击 "Start Coding"

---

## 🔄 测试 Gemini 同步流程

### 步骤 1: 选择项目根目录
1. 在 Invoke 窗口，点击顶部的 **"Select Project..."**
2. 选择: `/Users/yukungao/github/Invoke`
3. 确认顶部显示 "Invoke" 项目名

### 步骤 2: 激活 Sync 模式
1. 点击右下角的 **"Sync"** 按钮
2. 按钮应该变成 **"Syncing"** 并变为绿色
3. 左上角的状态点应该显示为**绿色**
4. ✅ 此时 Invoke 正在监听剪贴板

### 步骤 3: 测试剪贴板检测
打开终端，运行以下命令创建测试内容：

```bash
cat << 'EOF' | pbcopy
!!!B64_START!!! test_from_gemini.txt
VGhpcyBpcyBhIHRlc3QgZnJvbSBHZW1pbmkgQUk=
!!!B64_END!!!
EOF
```

**预期结果：**
- 在 Invoke 窗口中，应该立即看到一条新的 commit 记录
- 文件 `test_from_gemini.txt` 应该被创建在项目根目录
- 听到 "Glass" 音效
- 看到 macOS 通知："Sync Complete"

### 步骤 4: 验证文件
```bash
cat /Users/yukungao/github/Invoke/test_from_gemini.txt
# 应该输出: This is a test from Gemini AI
```

### 步骤 5: 验证 Git 提交
```bash
cd /Users/yukungao/github/Invoke
git log -1 --oneline
# 应该看到最新的提交: Update: test_from_gemini.txt
```

---

## 🐛 故障排查

### 问题: 点击 Sync 后没有变绿

**原因：** 项目根目录未选择

**解决：** 点击顶部 "Select Project..." 选择项目文件夹

---

### 问题: 复制内容后没有任何反应

**可能原因 1：Sync 未激活**
- 确认按钮显示 "Syncing"（绿色）

**可能原因 2：内容格式不对**
- 必须包含 `!!!B64_START!!!` 和 `!!!B64_END!!!` 标记
- Base64 内容必须有效

**可能原因 3：权限未授予**
- 系统设置 → 隐私与安全性 → 辅助功能
- 确保 Invoke 已开启

---

### 问题: 文件被创建但没有 Git 提交

**可能原因：** 项目不是 Git 仓库或没有远程

**解决：**
```bash
cd /Users/yukungao/github/Invoke
git status
git remote -v
```

---

## 🎬 完整的 Gemini 工作流

1. **启动 Invoke** → 选择项目 → 激活 Sync
2. **打开 Chrome** → 访问 gemini.google.com
3. **点击 Pair** → Gemini 自动收到项目结构
4. **对话 Gemini**："请优化 MagicPaster.swift"
5. **Gemini 回复** Base64 格式的代码
6. **点击复制按钮** → Invoke 自动检测
7. **文件自动更新** → Git 自动提交 & Push
8. **查看 Invoke** → 新的 commit 出现在列表中

---

## 📊 调试模式

如果需要查看详细日志：

```bash
# 关闭当前的 Invoke
pkill Invoke

# 在终端启动（带日志）
/Users/yukungao/github/Invoke/Invoke.app/Contents/MacOS/Invoke
```

**正常日志应该显示：**
```
📂 Project Root Set: /Users/yukungao/github/Invoke
👂 Listen mode ACTIVATED - monitoring clipboard...
🔍 Detected Base64 protocol in clipboard!
✅ Found 1 file(s) to update
✅ Wrote: test_from_gemini.txt
🚀 Starting Git commit & push...
✅ Git push successful: a1b2c3d
```

---

## ✅ 成功标志

- ✅ Sync 按钮变绿
- ✅ 状态点变绿
- ✅ 复制后听到音效
- ✅ 看到 macOS 通知
- ✅ 文件出现在项目中
- ✅ Git 日志显示新 commit
- ✅ Invoke 窗口显示 commit 记录

---

## 🎯 测试清单

- [ ] Onboarding 完成
- [ ] 辅助功能权限已授予
- [ ] 项目根目录已选择
- [ ] Sync 按钮已激活（绿色）
- [ ] 测试剪贴板内容已复制
- [ ] 文件成功创建
- [ ] Git 提交成功
- [ ] 看到通知和音效

**如果所有项目都打勾，恭喜！Invoke 已经 100% 正常工作！** 🎉
