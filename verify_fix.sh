#!/bin/bash

echo "🧪 验证 Sparkle Framework 链接"
echo "=============================="
echo ""

# 1. 检查 framework 是否存在
echo "📦 Step 1: 检查 Sparkle framework..."
if [ -d "Invoke.app/Contents/Frameworks/Sparkle.framework" ]; then
    echo "✅ Sparkle.framework 存在"
    ls -lh Invoke.app/Contents/Frameworks/
else
    echo "❌ Sparkle.framework 缺失"
    exit 1
fi

echo ""
echo "📦 Step 2: 检查可执行文件的 rpath..."
otool -l Invoke.app/Contents/MacOS/Invoke | grep -A 2 "LC_RPATH" | grep "path"

echo ""
echo "📦 Step 3: 检查 Sparkle 依赖..."
otool -L Invoke.app/Contents/MacOS/Invoke | grep Sparkle

echo ""
echo "📦 Step 4: 验证 Sparkle framework 结构..."
if [ -f "Invoke.app/Contents/Frameworks/Sparkle.framework/Sparkle" ]; then
    echo "✅ Sparkle 主文件存在"
elif [ -f "Invoke.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" ]; then
    echo "✅ Sparkle 版本化文件存在"
else
    echo "❌ Sparkle 可执行文件缺失"
    echo "Framework 内容："
    ls -la Invoke.app/Contents/Frameworks/Sparkle.framework/
fi

echo ""
echo "📦 Step 5: 尝试启动应用（5秒测试）..."
./Invoke.app/Contents/MacOS/Invoke &
APP_PID=$!
sleep 2

if ps -p $APP_PID > /dev/null 2>&1; then
    echo "✅ 应用成功启动！进程 ID: $APP_PID"
    echo ""
    echo "🎉 修复成功！现在可以正常测试文件选择功能了"
    echo ""
    echo "💡 测试建议："
    echo "1. 在菜单栏找到 Invoke 图标"
    echo "2. 点击图标打开面板"
    echo "3. 点击 'Select Project...' 测试文件选择"
    echo ""
    echo "按 Ctrl+C 停止应用..."
    wait $APP_PID
else
    echo "❌ 应用启动失败"
    echo ""
    echo "尝试直接运行获取错误信息："
    ./Invoke.app/Contents/MacOS/Invoke
fi
