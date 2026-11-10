#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/prism dist/Prism.app/Contents/{MacOS,Resources}
swiftc -O -parse-as-library -emit-module -emit-library -static \
  -module-name PrismCore -emit-module-path .build/prism/PrismCore.swiftmodule \
  -o .build/prism/libPrismCore.a Sources/PrismCore/*.swift
swiftc -O -parse-as-library -I .build/prism -L .build/prism -lPrismCore \
  -o dist/Prism.app/Contents/MacOS/Prism Sources/Prism/*.swift
swift Packaging/Icon.swift .build/prism/Prism.iconset
iconutil -c icns .build/prism/Prism.iconset -o dist/Prism.app/Contents/Resources/Prism.icns
cp Packaging/Info.plist dist/Prism.app/Contents/Info.plist
codesign --force --sign - dist/Prism.app
codesign --verify --strict dist/Prism.app
printf 'Built %s\n' "$PWD/dist/Prism.app"
