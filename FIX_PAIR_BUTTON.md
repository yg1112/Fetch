# 🔧 解决 Pair 按钮不工作的问题

## 🎯 问题分析

**症状：** 点击 Pair 按钮后，Gemini 对话框没有自动填入文字

**根本原因：** **辅助功能权限未授予**

Invoke 需要辅助功能权限来模拟键盘按键（Cmd+V），从而自动粘贴内容到浏览器。

---

## ✅ 解决方案（3 步）

### 步骤 1: 授予辅助功能权限

#### 方法 A：自动打开设置（推荐）
```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

#### 方法 B：手动打开
1. 打开 **系统设置** (System Settings)
2. 点击 **隐私与安全性** (Privacy & Security)
3. 点击 **辅助功能** (Accessibility)
4. 在列表中找到以下任一项：
   - **Invoke** （如果能看到）
   - **Terminal** （如果是从终端启动的）
   - **Visual Studio Code** （如果从 VS Code 启动）
5. 确保开关是 **ON（蓝色）**

📸 **截图参考：**
```
┌─────────────────────────────────────┐
│ Accessibility                        │
├─────────────────────────────────────┤
│ ✅ Terminal                          │
│ ✅ Invoke                            │
│ ⬜ Other App                         │
└─────────────────────────────────────┘
```

---

### 步骤 2: 验证权限

运行诊断脚本：
```bash
cd /Users/yukungao/github/Invoke
./diagnose_pair.sh
```

**预期输出（成功）：**
```
✅ Accessibility permission granted
✅ Google Chrome is running
✅ AppleScript executed successfully
```

**如果仍然显示 ❌**，可能需要：
- 重启终端
- 重新运行 Invoke
- 重启系统设置

---

### 步骤 3: 测试 Pair 功能

#### 方法 1: 使用调试模式（推荐）

在终端运行：
```bash
./run_debug.sh
```

这会启动 Invoke 并显示详细日志。

然后：
1. 在 Invoke 中选择项目
2. 打开 Chrome，访问 gemini.google.com
3. 点击 Invoke 的 **"Pair"** 按钮

**预期日志输出：**
```
🔗 Pair button clicked - preparing protocol...
📂 Project structure scanned: 45 lines
📋 Prompt copied to clipboard (2847 chars)
🎯 Calling MagicPaster...
🎯 MagicPaster: Attempting to paste to Google Chrome...
✅ MagicPaster: Paste command sent successfully
```

#### 方法 2: 普通启动

```bash
open /Users/yukungao/github/Invoke/Invoke.app
```

然后：
1. 选择项目
2. 打开 Chrome 并访问 Gemini
3. 点击 "Pair"
4. **观察 Chrome**：Gemini 的对话框应该自动填入一大段文字

---

## 🐛 故障排查

### 问题: 诊断脚本仍显示权限未授予

**解决：**
```bash
# 1. 完全退出 Invoke
pkill Invoke

# 2. 完全退出终端并重新打开

# 3. 重新运行诊断
./diagnose_pair.sh
```

### 问题: Chrome 没有自动打开或激活

**可能原因：** 浏览器名称不匹配

**检查你使用的浏览器：**
- ✅ Google Chrome （默认支持）
- ❌ Arc, Safari, Edge （需要修改配置）

**临时解决：** 确保 **Google Chrome** 正在运行并且是活动窗口

---

### 问题: 权限已授予，但还是不粘贴

**调试步骤：**

1. **测试 AppleScript：**
```bash
echo "HELLO FROM SCRIPT" | pbcopy

osascript <<EOF
tell application "Google Chrome"
    activate
end tell
delay 0.5
tell application "System Events"
    keystroke "v" using {command down}
end tell
EOF
```

如果这个命令能在 Chrome 中粘贴 "HELLO FROM SCRIPT"，说明权限和脚本都正常。

2. **查看详细错误：**
```bash
./run_debug.sh
# 点击 Pair，查看终端输出
```

3. **手动测试：**
   - 点击 Pair
   - 立即按 **Cmd+V** 手动粘贴
   - 如果能看到内容，说明复制成功，只是自动粘贴失败

---

## 📊 完整测试清单

- [ ] 1. 辅助功能权限已授予（Terminal 或 Invoke）
- [ ] 2. 诊断脚本显示全绿 ✅
- [ ] 3. Google Chrome 正在运行
- [ ] 4. Invoke 已启动并选择了项目
- [ ] 5. 访问了 gemini.google.com
- [ ] 6. 点击 Pair 按钮
- [ ] 7. Chrome 自动获得焦点
- [ ] 8. 对话框自动填入项目信息

**如果全部打勾，Pair 功能应该完美工作！** 🎉

---

## 🆘 紧急备用方案

如果自动粘贴始终不工作，可以使用**手动粘贴模式**：

1. 点击 Invoke 的 **"Pair"** 按钮
2. 内容会自动复制到剪贴板 ✅
3. 手动切换到 Chrome
4. 在 Gemini 对话框按 **Cmd+V** 粘贴

虽然不如自动化优雅，但功能完全一样！

---

## 📞 需要帮助？

如果按照上述步骤仍然不工作，运行以下命令生成诊断报告：

```bash
cd /Users/yukungao/github/Invoke

echo "=== DIAGNOSTIC REPORT ===" > diagnostic_report.txt
echo "" >> diagnostic_report.txt

echo "1. Accessibility Check:" >> diagnostic_report.txt
./diagnose_pair.sh >> diagnostic_report.txt 2>&1
echo "" >> diagnostic_report.txt

echo "2. Running Apps:" >> diagnostic_report.txt
pgrep -l "Chrome|Invoke" >> diagnostic_report.txt
echo "" >> diagnostic_report.txt

echo "3. Test Run:" >> diagnostic_report.txt
./run_debug.sh &
sleep 3
echo "Invoke started" >> diagnostic_report.txt

cat diagnostic_report.txt
```

分享这个报告以获得进一步帮助。
