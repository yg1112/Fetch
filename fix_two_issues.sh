#!/bin/bash

echo "🔧 修复 Invoke 的两个问题"
echo "=========================="
echo ""

echo "问题 1: Pair 按钮不粘贴"
echo "原因: Invoke.app 没有 Accessibility 权限"
echo "解决: 需要手动添加 Invoke.app 到 Accessibility 列表"
echo ""

echo "问题 2: Onboarding 无法重置"
echo "原因: @AppStorage 使用默认 suite，但 UserDefaults 在不同位置"
echo "当前 UserDefaults 内容:"
defaults read com.yukungao.invoke 2>&1 | head -10
echo ""

echo "=========================="
echo "🎯 修复步骤："
echo "=========================="
echo ""

echo "1️⃣ 添加 Invoke.app 到 Accessibility："
echo "   open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
echo "   然后点击 + 号，选择: $(pwd)/Invoke.app"
echo ""

echo "2️⃣ 重置 Onboarding（修复后的命令）："
echo "   defaults write com.yukungao.invoke hasCompletedOnboarding -bool false"
echo "   # 或者直接删除整个设置："
echo "   rm ~/Library/Preferences/com.yukungao.invoke.plist"
echo ""

echo "3️⃣ 测试 Pair 功能："
echo "   1. 重启 Invoke:"
echo "      pkill Invoke && open Invoke.app"
echo "   2. 打开 Gemini 网页"
echo "   3. 点击 Invoke 的 Pair 按钮"
echo "   4. 应该看到:"
echo "      • Invoke 窗口短暂消失"
echo "      • Gemini 输入框自动填入协议文本"
echo ""

echo "=========================="
echo "🚀 快速修复命令："
echo "=========================="
echo ""
echo "# 打开系统设置（Accessibility）"
echo "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
echo ""
echo "# 重置 onboarding"
echo "defaults write com.yukungao.invoke hasCompletedOnboarding -bool false"
echo ""
echo "# 重启应用"
echo "pkill Invoke && sleep 1 && open Invoke.app"
echo ""

echo "=========================="
echo "📝 验证："
echo "=========================="
echo ""
echo "验证 Accessibility 权限:"
if tccutil list Accessibility 2>/dev/null | grep -q "com.yukungao.invoke"; then
    echo "✅ Invoke.app 有 Accessibility 权限"
else
    echo "❌ Invoke.app 没有 Accessibility 权限"
fi
echo ""

echo "验证 hasCompletedOnboarding:"
if defaults read com.yukungao.invoke hasCompletedOnboarding 2>/dev/null; then
    echo "当前值: $(defaults read com.yukungao.invoke hasCompletedOnboarding)"
else
    echo "❌ 未找到 hasCompletedOnboarding（说明从未设置过）"
fi
