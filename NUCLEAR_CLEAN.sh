#!/bin/bash
set -e

echo "🧹 Nuclear Clean for Xcode..."

# Kill Xcode
echo "1. Killing Xcode..."
killall Xcode 2>/dev/null || true

# Remove derived data
echo "2. Removing derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Remove module cache  
echo "3. Removing module cache..."
rm -rf ~/Library/Caches/com.apple.dt.Xcode/*

# Remove workspace data
echo "4. Removing workspace data..."
rm -rf /Users/yslim0622/ClearSplit/ios/ClearSplit/ClearSplit.xcodeproj/project.xcworkspace/xcuserdata/*
rm -rf /Users/yslim0622/ClearSplit/ios/ClearSplit/ClearSplit.xcodeproj/xcuserdata/*

# Remove build folder
echo "5. Removing build folder..."
cd /Users/yslim0622/ClearSplit/ios/ClearSplit
rm -rf build/

echo "Clean complete!"
echo "Now open Xcode and build again."
