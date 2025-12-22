# Invoke 文件夹选择问题调试指南

## ⚠️ 重要发现

**问题根源**：`swift build` 只生成可执行文件，不生成 `.app` bundle，导致：
1. Info.plist 和 Entitlements.plist 不会被使用
2. macOS 不会给予应用正确的权限
3. NSOpenPanel 可能无法正常工作

**解决方案**：使用 `.app` bundle 而不是裸可执行文件

## 📋 测试步骤（推荐方式）

### 方法1: 使用 .app Bundle（强烈推荐✅）
```bash
cd /Users/yukungao/github/Invoke
./build_app.sh
```

这会：
1. 编译 release 版本
2. 创建完整的 .app bundle
3. 复制 Info.plist 和资源文件
4. 使用 Entitlements.plist 进行代码签名

然后运行：
```bash
# 方式1: 直接打开（正常使用）
open Invoke.app

# 方式2: 在终端运行（查看日志）
./Invoke.app/Contents/MacOS/Invoke 2>&1 | tee invoke_debug.log
```

### 方法2: 使用测试脚本
```bash
cd /Users/yukungao/github/Invoke
./test_debug.sh
```

选择选项 2 来构建和运行 .app bundle。

### 方法3: 快速测试（不推荐，仅用于对比）
```bash
swift build
.build/debug/Invoke
```

注意：这种方式可能权限不足！

## 🔍 测试内容

1. **启动应用**
   - 观察启动日志
   - 确认应用出现在菜单栏

2. **点击文件夹选择按钮**
   - 点击"Select Project..."按钮
   - 观察终端输出的日志
   
3. **在文件选择器中操作**
   - 尝试浏览不同的文件夹
   - 记录哪些文件夹是灰色的
   - 尝试点击选择一个文件夹
   - 观察是否闪退

## 📊 关键日志标记

查找以下标记的日志：

- `🔍 [UI]` - UI层面的操作
- `🔍 [DEBUG]` - 详细的调试信息
- `⚠️ [DEBUG]` - 警告信息
- `✅ [DEBUG]` - 成功操作
- `❌ [DEBUG]` - 错误信息

## 🐛 重点关注的问题

### 1. 权限相关
```
Bundle ID: ...
App path: ...
```

### 2. 窗口状态
```
Key window exists: ...
Main window exists: ...
NSApp is active: ...
```

### 3. NSOpenPanel配置
```
Panel configuration:
  - canChooseFiles: false
  - canChooseDirectories: true
  - treatsFilePackagesAsDirectories: true
```

### 4. 选择结果
```
Panel returned with response: ...
URL selected: ...
```

## 📝 如何报告问题

测试后，请提供：

1. **完整的日志输出** (invoke_debug.log文件内容)
2. **灰色文件夹的特征**：
   - 是哪些类型的文件夹（系统文件夹？普通文件夹？）
   - 路径位置（桌面？文档？根目录？）
3. **闪退发生的时机**：
   - 点击灰色文件夹时？
   - 点击普通文件夹时？
   - 双击还是单击选择？
4. **闪退后的日志**：
   - 最后几行日志是什么？
   - 是否有错误信息？

## 🔧 可能的解决方案测试

根据日志，我可能会建议尝试：

1. **权限问题** - 如果Bundle ID不正确
2. **窗口问题** - 如果没有key window或main window
3. **配置问题** - 如果NSOpenPanel配置不对
4. **签名问题** - 如果需要code signing

## 💡 额外测试

如果上述测试还是失败，可以尝试：

```bash
# 测试1: 使用不同的运行方式
open .build/debug/Invoke.app

# 测试2: 检查是否需要签名
codesign -dv .build/debug/Invoke

# 测试3: 检查权限
xattr -lr .build/debug/Invoke
```
