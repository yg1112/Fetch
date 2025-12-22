#!/bin/bash

echo "🔍 Diagnosing Pair Function"
echo "=========================="
echo ""

# 1. 检查辅助功能权限
echo "1️⃣  Checking Accessibility Permission..."
ACCESSIBILITY_CHECK=$(osascript -e 'tell application "System Events" to keystroke "test"' 2>&1)

if [[ $ACCESSIBILITY_CHECK == *"not allowed"* ]] || [[ $ACCESSIBILITY_CHECK == *"denied"* ]]; then
    echo "❌ Accessibility permission NOT granted"
    echo ""
    echo "📌 ACTION REQUIRED:"
    echo "   1. Open System Settings"
    echo "   2. Go to Privacy & Security → Accessibility"
    echo "   3. Find 'Invoke' or 'Terminal' in the list"
    echo "   4. Toggle it ON"
    echo ""
    echo "   Alternative: Run this command to open System Settings:"
    echo "   open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
    echo ""
    exit 1
else
    echo "✅ Accessibility permission granted"
fi

echo ""

# 2. 检查 Chrome 是否运行
echo "2️⃣  Checking if Google Chrome is running..."
if pgrep -x "Google Chrome" > /dev/null; then
    echo "✅ Google Chrome is running"
else
    echo "⚠️  Google Chrome is NOT running"
    echo "   Starting Chrome..."
    open -a "Google Chrome" "https://gemini.google.com"
    sleep 2
fi

echo ""

# 3. 测试 AppleScript 自动化
echo "3️⃣  Testing AppleScript automation..."

# 先把测试内容复制到剪贴板
echo "TEST CONTENT FROM INVOKE DIAGNOSTIC" | pbcopy

# 尝试激活 Chrome 并粘贴
osascript <<EOF
tell application "Google Chrome"
    activate
end tell
delay 0.5
tell application "System Events"
    keystroke "v" using {command down}
end tell
EOF

if [ $? -eq 0 ]; then
    echo "✅ AppleScript executed successfully"
    echo "   Check Chrome - you should see the test content pasted"
else
    echo "❌ AppleScript failed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary:"
echo "   If all checks passed, Pair button should work!"
echo ""
echo "🎯 Next: Click 'Pair' in Invoke and watch Chrome"
echo ""
