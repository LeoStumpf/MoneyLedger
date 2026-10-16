#!/usr/bin/env bash
set -euo pipefail

FLUTTER="${FLUTTER:-flutter}"

echo "==> Regenerating code-gen (Drift + Riverpod)..."
"$FLUTTER" pub get
dart run build_runner build

echo "==> Checking formatting (dart format)..."
# Generated files (*.g.dart, lib/l10n/app_localizations*.dart) are emitted
# already formatted, so the whole of lib/ + test/ is checked.
# Fix with: dart format lib test
dart format --output=none --set-exit-if-changed lib test

echo "==> Running tests..."
"$FLUTTER" test --reporter compact

echo "==> Building web release..."
"$FLUTTER" build web --release

echo ""
echo "Build complete. Output: build/web/"
