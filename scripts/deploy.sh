#!/bin/bash

# Deploy script for Invoke
# Builds and packages the app for distribution

set -e

APP_NAME="Invoke"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."
swift build -c release

echo "📦 Creating app bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "✅ Build complete!"
echo "App bundle: $APP_BUNDLE"
