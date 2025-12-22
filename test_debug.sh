#!/bin/bash

echo "🧪 Testing Invoke with Debug Logs"
echo "=================================="
echo ""
echo "选择测试方式:"
echo "1) 直接运行可执行文件 (快速，但可能缺少权限)"
echo "2) 构建并运行 .app bundle (完整，推荐)"
echo ""
read -p "请选择 [1/2]: " choice

if [ "$choice" = "2" ]; then
    echo ""
    echo "🔨 构建 .app bundle..."
    ./build_app.sh
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🚀 运行 Invoke.app 并记录日志..."
        echo "📝 所有日志将保存到 invoke_debug.log"
        echo "-------------------------------------------"
        echo ""
        ./Invoke.app/Contents/MacOS/Invoke 2>&1 | tee invoke_debug.log
    else
        echo "❌ 构建失败!"
        exit 1
    fi
else
    echo ""
    echo "Building..."
    swift build
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Build successful!"
        echo ""
        echo "🚀 Running Invoke with debug output..."
        echo "📝 Watch for debug logs starting with [DEBUG]"
        echo "-------------------------------------------"
        echo ""
        .build/debug/Invoke 2>&1 | tee invoke_debug.log
    else
        echo ""
        echo "❌ Build failed!"
        exit 1
    fi
fi
