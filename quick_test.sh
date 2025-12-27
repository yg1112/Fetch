#!/bin/bash

echo "🚀 Quick Test for Fetch.app"
echo "============================="
echo ""

# Check if Fetch.app exists
if [ ! -d "Fetch.app" ]; then
    echo "❌ Fetch.app not found!"
    echo "📦 Building it now..."
    ./build_app.sh
    echo ""
fi

echo "📱 Testing Fetch.app with full debug logging..."
echo ""
echo "📝 Instructions:"
echo "1. 应用会打开"
echo "2. 点击菜单栏的图标"
echo "3. 点击 'Select Project...' 按钮"
echo "4. 观察文件选择器："
echo "   - 哪些文件夹是灰色的？"
echo "   - 点击文件夹是否闪退？"
echo "5. 所有日志会保存到 invoke_debug.log"
echo ""
echo "按 Enter 开始测试..."
read

./Fetch.app/Contents/MacOS/Fetch 2>&1 | tee invoke_debug.log

echo ""
echo "📊 测试完成！"
echo "📄 日志已保存到: invoke_debug.log"
echo ""
echo "请检查日志中的关键信息："
echo "- 查找 [DEBUG] 开头的行"
echo "- 查找 Bundle ID 和权限信息"
echo "- 查找 NSOpenPanel 配置信息"
echo "- 查找任何错误或警告"
