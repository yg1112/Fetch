# 🎯 Invoke 文件夹选择问题 - 系统排查方案

## 问题现象
1. 点击 "Select Project" 后，文件选择器中很多文件夹是灰色的
2. 点击文件夹后，选择窗口闪退
3. 无法成功选择 project 文件夹

## 根本原因分析

### 🔍 关键发现
**`swift build` vs `.app bundle` 的区别：**

| 特性 | `swift build` | `.app bundle` |
|------|---------------|---------------|
| 输出 | 纯可执行文件 | 完整应用包 |
| Info.plist | ❌ 不使用 | ✅ 使用 |
| Entitlements | ❌ 不使用 | ✅ 使用 |
| 代码签名 | ❌ 无 | ✅ 有 |
| 文件权限 | ⚠️ 受限 | ✅ 完整 |
| NSOpenPanel | ⚠️ 可能失败 | ✅ 正常工作 |

## ✅ 解决方案

### 方案1: 构建 .app Bundle（推荐）

```bash
cd /Users/yukungao/github/Invoke

# 构建
./build_app.sh

# 测试
./quick_test.sh
```

### 方案2: 分步测试

```bash
# Step 1: 构建
./build_app.sh

# Step 2: 运行并记录日志
./Invoke.app/Contents/MacOS/Invoke 2>&1 | tee invoke_debug.log

# Step 3: 测试文件选择
# - 点击菜单栏图标
# - 点击 "Select Project..." 按钮
# - 观察文件选择器行为

# Step 4: 分析日志
cat invoke_debug.log | grep DEBUG
```

## 📊 已添加的调试埋点

代码中已添加详细的日志输出，标记为：

1. **UI 层面** (`🔍 [UI]`)
   - 按钮点击事件
   - 用户交互追踪

2. **NSOpenPanel 配置** (`🔍 [DEBUG]`)
   - 线程信息
   - Bundle ID 和路径
   - Panel 配置参数
   - 窗口状态

3. **权限检查** (`✅ [DEBUG]`)
   - 文件访问权限
   - URL 有效性验证
   - 目录类型检查

4. **错误信息** (`❌ [DEBUG]`)
   - 失败原因
   - 异常状态

## 🧪 测试清单

### 测试 1: 验证 .app bundle
```bash
# 检查结构
ls -la Invoke.app/Contents/

# 检查签名
codesign -dv Invoke.app

# 检查 entitlements
codesign -d --entitlements :- Invoke.app
```

### 测试 2: 对比测试
```bash
# A. 使用 swift build（预期失败）
swift build
.build/debug/Invoke

# B. 使用 .app bundle（预期成功）
./Invoke.app/Contents/MacOS/Invoke
```

### 测试 3: 文件选择器
1. 启动应用
2. 点击 "Select Project..."
3. 观察：
   - [ ] 是否打开文件选择器？
   - [ ] 是否有灰色文件夹？
   - [ ] 点击文件夹是否闪退？
   - [ ] 能否成功选择？

## 📝 如何读懂日志

### 正常流程应该看到：
```
🔍 [UI] Project selection button clicked
🔍 [DEBUG] selectProjectRoot called
🔍 [DEBUG] Is main thread: true
🔍 [DEBUG] Bundle ID: com.yukungao.invoke
🔍 [DEBUG] Creating NSOpenPanel...
🔍 [DEBUG] Configuring panel properties...
🔍 [DEBUG] Panel configuration:
  - canChooseFiles: false
  - canChooseDirectories: true
  - treatsFilePackagesAsDirectories: true
🔍 [DEBUG] NSApp is active: true
🔍 [DEBUG] Opening panel with runModal...
🔍 [DEBUG] Panel returned with response: 1
✅ [DEBUG] URL selected: file:///path/to/folder/
✅ [DEBUG] Is directory: true
📂 Project root selected: folder
```

### 如果失败，可能看到：
```
❌ [DEBUG] Response was .OK but URL is nil!
⚠️ [DEBUG] No key window
⚠️ [DEBUG] No main window
```

## 🔧 故障排除

### 问题1: Bundle ID 不正确
```bash
# 检查 Info.plist
cat Invoke.app/Contents/Info.plist | grep -A1 CFBundleIdentifier
```

### 问题2: Entitlements 未应用
```bash
# 检查签名和权限
codesign -d --entitlements :- Invoke.app | grep -A5 "files"
```

### 问题3: 权限被拒绝
```bash
# 检查系统权限（可能需要在系统偏好设置中授权）
# 系统偏好设置 > 隐私与安全性 > 文件和文件夹
```

## 🎓 技术细节

### 为什么需要 .app bundle？

macOS 的安全模型要求：
1. **Info.plist** 声明应用的能力和权限请求
2. **Entitlements** 定义应用可以访问的系统资源
3. **Code Signing** 确保应用的完整性

纯可执行文件缺少这些元数据，macOS 会限制其权限。

### NSOpenPanel 的要求

`NSOpenPanel` 在以下情况下工作最好：
- 从正确签名的 .app bundle 运行
- 有适当的 entitlements
- 在主线程上运行
- 使用 `runModal()` 而不是异步方法

## 📚 相关文件

- `build_app.sh` - 构建 .app bundle
- `test_debug.sh` - 交互式测试脚本
- `quick_test.sh` - 快速测试脚本
- `DEBUG_GUIDE.md` - 详细调试指南
- `Entitlements.plist` - 权限配置
- `Info.plist` - 应用元数据
- `Sources/Invoke/Features/GeminiLinkLogic.swift` - 文件选择逻辑（含调试日志）

## 🚀 下一步

运行测试后，请提供：
1. `invoke_debug.log` 文件内容
2. 灰色文件夹的路径示例
3. 闪退时的最后几行日志
4. `.app bundle` vs `swift build` 的行为对比

这将帮助我精确定位问题并提供针对性修复。
