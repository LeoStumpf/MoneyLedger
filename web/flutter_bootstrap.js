{{flutter_js}}
{{flutter_build_config}}

// G43: the app loads nothing from a CDN. CanvasKit comes from ./canvaskit/
// (build with --no-web-resources-cdn: useLocalCanvasKit in the build config),
// and the engine's font downloads — its default Roboto and the Noto fallback
// fonts for glyphs no bundled font has — go to ./fonts/ on this origin instead
// of https://fonts.gstatic.com/s/. Only Roboto is served there
// (web/fonts/roboto/…, tool/fonts/make_web_fonts.py); other fallback fonts
// simply aren't found, so such characters show as boxes.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: {
    fontFallbackBaseUrl: "fonts/",
  },
});
