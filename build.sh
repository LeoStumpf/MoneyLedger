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

echo "==> Building web release (no CDN — G43)..."
# --no-web-resources-cdn: CanvasKit is served from build/web/canvaskit/
# instead of www.gstatic.com; web/flutter_bootstrap.js keeps the engine's
# font downloads on our origin too. The check fails if anything still points
# at a CDN.
"$FLUTTER" build web --release --no-web-resources-cdn
tool/web/check_web_build.sh build/web

echo ""
echo "Build complete. Output: build/web/"
