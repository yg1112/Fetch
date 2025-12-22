#!/bin/bash

echo "🚀 Starting Invoke in Debug Mode"
echo "================================"
echo ""
echo "📌 This will show detailed logs when you click Pair or Sync"
echo ""

# 关闭现有的 Invoke
pkill -9 Invoke 2>/dev/null

# 在前台启动并显示日志
echo "🔍 Logs will appear below..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

/Users/yukungao/github/Invoke/Invoke.app/Contents/MacOS/Invoke
