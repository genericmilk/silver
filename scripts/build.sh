#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -quiet -project Silver.xcodeproj -scheme Silver -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build build
open build/Build/Products/Debug/Silver.app
