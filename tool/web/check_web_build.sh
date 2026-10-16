#!/usr/bin/env bash
# G43: checks a web release build (build/web by default) loads nothing from a
# CDN — run after `flutter build web --release --no-web-resources-cdn`
# (build.sh and CI do). Fails when:
#   - CanvasKit would come from www.gstatic.com (flag missing),
#   - the bootstrap doesn't point the engine's font downloads at our origin,
#   - the engine's Roboto path (a string in main.dart.js, changes with Flutter
#     upgrades) has no file under build/web/fonts/ — then re-run
#     `python3 -I tool/fonts/make_web_fonts.py --roboto-path <path>`.
set -euo pipefail

WEB="${1:-build/web}"
fail() { echo "check_web_build: $*" >&2; exit 1; }

boot="$WEB/flutter_bootstrap.js"
[[ -f "$boot" ]] || fail "$boot missing"
grep -q '"useLocalCanvasKit":true' "$boot" ||
  fail "CanvasKit would load from the CDN — build with --no-web-resources-cdn"
grep -q 'fontFallbackBaseUrl: "fonts/"' "$boot" ||
  fail "flutter_bootstrap.js doesn't set fontFallbackBaseUrl to fonts/"
# (flutter.js inside the bootstrap still contains the gstatic CanvasKit URL as
# a dead default — it is used only when useLocalCanvasKit is off.)
[[ -f "$WEB/canvaskit/canvaskit.wasm" ]] || fail "canvaskit/ not in the build"

roboto=$(grep -oE 'roboto/v[0-9]+/[A-Za-z0-9_-]+\.woff2' "$WEB/main.dart.js" | sort -u)
[[ -n "$roboto" ]] || fail "engine Roboto path not found in main.dart.js"
for path in $roboto; do
  [[ -f "$WEB/fonts/$path" ]] ||
    fail "engine wants fonts/$path — run tool/fonts/make_web_fonts.py --roboto-path $path"
done
echo "check_web_build: OK (local CanvasKit, fonts/ base, Roboto at fonts/$roboto)"
