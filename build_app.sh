#!/bin/bash

set -e

echo "🔨 Building Invoke.app Bundle"
echo "=============================="

# 1. Build the executable
echo ""
echo "📦 Step 1: Building executable..."
swift build -c release

if [ ! -f .build/release/Invoke ]; then
    echo "❌ Build failed - executable not found"
    exit 1
fi

# 2. Create .app bundle structure
echo ""
echo "📦 Step 2: Creating .app bundle structure..."
APP_NAME="Invoke"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

# Remove old bundle if exists
rm -rf "$APP_BUNDLE"

# Create directories
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"

# 3. Copy executable
echo "📦 Step 3: Copying executable..."
cp .build/release/Invoke "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# 4. Copy Info.plist
echo "📦 Step 4: Copying Info.plist..."
cp Info.plist "$CONTENTS/"

# 5. Copy icon if exists
if [ -f "AppIcon.icns" ]; then
    echo "📦 Step 5: Copying icon..."
    cp AppIcon.icns "$RESOURCES/"
fi

# 6. Copy Sparkle framework
echo "📦 Step 6: Copying Sparkle framework..."
if [ -d ".build/release/Sparkle.framework" ]; then
    cp -R .build/release/Sparkle.framework "$FRAMEWORKS/"
    echo "✓ Sparkle framework copied"
else
    echo "⚠️  Warning: Sparkle.framework not found in .build/release/"
    # Try alternative location
    if [ -d ".build/debug/Sparkle.framework" ]; then
        cp -R .build/debug/Sparkle.framework "$FRAMEWORKS/"
        echo "✓ Sparkle framework copied from debug build"
    fi
fi

# 6.5. Fix rpath for frameworks
echo "📦 Step 6.5: Fixing runtime search paths..."
if [ -f "$MACOS/$APP_NAME" ]; then
    # Add rpath to find frameworks in the app bundle
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true
    echo "✓ Added @executable_path/../Frameworks to rpath"
    
    # Verify rpath
    echo "Current rpaths:"
    otool -l "$MACOS/$APP_NAME" | grep -A 2 LC_RPATH || echo "  (none found, but we just added one)"
fi

# 7. Sign the app (ad-hoc signature for local testing)
echo ""
echo "🔐 Step 7: Signing application..."
echo "Using entitlements: Entitlements.plist"

# Sign Sparkle framework first
if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
    codesign --force --deep --sign - "$FRAMEWORKS/Sparkle.framework"
fi

# Sign the app bundle with entitlements
codesign --force --deep --sign - --entitlements Entitlements.plist "$APP_BUNDLE"

# Verify signature
echo ""
echo "✅ Verifying signature..."
codesign -dv "$APP_BUNDLE"
echo ""
codesign -d --entitlements :- "$APP_BUNDLE"

echo ""
echo "🎉 Build complete!"
echo "📍 Location: $(pwd)/$APP_BUNDLE"
echo ""
echo "🚀 To run the app:"
echo "   open $APP_BUNDLE"
echo ""
echo "🧪 To run with debug logs:"
echo "   ./$APP_BUNDLE/Contents/MacOS/$APP_NAME 2>&1 | tee invoke_debug.log"
