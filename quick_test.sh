#!/bin/bash
echo "🚀 Quick Test for Fetch (Invisible Mode)"
echo "========================================"

# 1. 启动 App (如果没启动)
if ! pgrep -x "Fetch" > /dev/null; then
    echo "⚡️ Starting Fetch..."
    open -a Fetch
    sleep 2
else
    echo "✅ Fetch is running."
fi

# 2. 测试 API 端口 (这是 Woz 关心的)
echo "🔍 Checking Port 3000..."
if lsof -i :3000 > /dev/null; then
    echo "✅ Port 3000 is active. The Ear is listening."
else
    echo "❌ Port 3000 is CLOSED. The Server is down."
    exit 1
fi

# 3. 模拟一次 Aider 请求 (这是 Jobs 关心的体验)
echo "🧪 Sending a test thought..."
curl -v http://127.0.0.1:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.0-flash",
    "messages": [{"role": "user", "content": "Say EXACTLY one word: ALIVE"}]
  }'

echo ""
echo "========================================"
echo "👀 观察："
echo "1. 菜单栏的绿点是否闪烁？(如果有实现状态变化)"
echo "2. 终端是否输出了 'ALIVE'？"
echo "3. 如果成功，说明隐形桥梁已打通."
