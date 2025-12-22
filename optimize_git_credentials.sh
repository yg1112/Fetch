#!/bin/bash

echo "🔧 Optimizing Git Credentials for Invoke"
echo "========================================"
echo ""

cd /Users/yukungao/github/Invoke

echo "1️⃣  Configuring Git credential helper..."
git config credential.helper osxkeychain
echo "✅ Set to use osxkeychain"
echo ""

echo "2️⃣  Setting credential cache timeout (1 hour)..."
git config --global credential.helper "cache --timeout=3600"
echo "✅ Credentials will be cached for 1 hour"
echo ""

echo "3️⃣  Testing current remote URL..."
REMOTE_URL=$(git config --get remote.origin.url)
echo "   Remote: $REMOTE_URL"
echo ""

if [[ $REMOTE_URL == git@github.com:* ]]; then
    echo "✅ Using SSH - No keychain prompts needed!"
elif [[ $REMOTE_URL == https://github.com/* ]]; then
    echo "⚠️  Using HTTPS - Will need GitHub token"
    echo ""
    echo "📌 Recommendation: Add GitHub token to keychain"
    echo "   When prompted next time:"
    echo "   1. Click 'Always Allow' instead of 'Allow'"
    echo "   2. This prevents future prompts"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Next Step:"
echo "   Run: open ./Invoke.app"
echo "   The first push might still ask for keychain"
echo "   Click 'Always Allow' to prevent future prompts"
echo ""
