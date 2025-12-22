#!/bin/bash

# 简单快速测试脚本
echo "🚀 Quick Test: Copying Base64 content to clipboard..."

cat << 'EOF' | pbcopy
!!!B64_START!!! test_from_gemini.txt
VGhpcyBpcyBhIHRlc3QgZnJvbSBHZW1pbmkgQUk=
!!!B64_END!!!
EOF

echo "✅ Content copied!"
echo ""
echo "📌 Now check Invoke:"
echo "   1. Make sure 'Sync' button is GREEN"
echo "   2. You should hear a 'Glass' sound"
echo "   3. A new commit should appear in the list"
echo ""
echo "🔍 Verify file was created:"
echo "   cat test_from_gemini.txt"
echo ""
