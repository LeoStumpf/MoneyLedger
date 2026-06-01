#!/usr/bin/env bash
set -euo pipefail

FLUTTER="${FLUTTER:-flutter}"

echo "==> Regenerating code-gen (Drift + Riverpod)..."
"$FLUTTER" pub get
dart run build_runner build

echo "==> Running tests..."
"$FLUTTER" test --reporter compact

echo "==> Building web release..."
"$FLUTTER" build web --release

echo ""
echo "Build complete. Output: build/web/"
