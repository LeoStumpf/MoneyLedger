# Third-party notices

MoneyLedger's own code is released under the GNU Affero General Public License,
version 3 or later (see [`LICENSE`](LICENSE)); that license covers MoneyLedger's
code only. The app builds on third-party open-source packages whose
copyright/license notices must be retained. This file collects them.

Flutter automatically aggregates the **full license text of every bundled
package** into the app's in-app licenses page (About → *Open-source licenses*,
via `LicenseRegistry` / `showLicensePage`), so end users can view them directly.
The version-exact list of all packages (direct and transitive) is in
[`pubspec.lock`](pubspec.lock).

## Bundled packages (direct runtime dependencies)

| Package | Version | License |
|---|---|---|
| `matrix` (Famedly Matrix SDK) | 7.2.2 | **AGPL-3.0** |
| `flutter_vodozemac` (E2EE bindings) | 0.6.0 | **AGPL-3.0** |
| `flutter`, `flutter_localizations` (SDK) | 3.44 | BSD-3-Clause |
| `go_router`, `intl`, `package_info_plus`, `path_provider`, `url_launcher`, `web` | see lock | BSD-3-Clause |
| `sqflite` | 2.4.2+1 | BSD-2-Clause |
| `app_links` | 6.4.1 | Apache-2.0 |
| `drift`, `drift_flutter`, `sqlite3_flutter_libs`, `flutter_riverpod`, `riverpod_annotation`, `file_picker`, `uuid`, `workmanager`, `cupertino_icons` | see lock | MIT |

### Native / compiled components

- **vodozemac** (Rust, `matrix-org/vodozemac` 0.9.0) — Apache-2.0. Compiled into
  the Android app by `flutter_vodozemac` (cargokit) and shipped prebuilt for the
  web in [`web/pkg/`](web/pkg) (`vodozemac_bindings_dart_bg.wasm`). Its Rust
  dependencies (RustCrypto crates, `flutter_rust_bridge`, …) are MIT and/or
  Apache-2.0.
- **SQLite** — public domain; bundled by `sqlite3_flutter_libs` (Android) and as
  [`web/sqlite3.wasm`](web/sqlite3.wasm) with Drift's
  [`web/drift_worker.js`](web/drift_worker.js) (MIT) on the web.

### Fonts

- **Manrope** (`assets/fonts/manrope/`, static instances of the variable
  font from [google/fonts](https://github.com/google/fonts/tree/main/ofl/manrope))
  — Copyright 2018 The Manrope Project Authors, **SIL Open Font License 1.1**
  ([`OFL.txt`](assets/fonts/manrope/OFL.txt)). Bundled with the app (never
  downloaded at runtime) and listed on the in-app licenses page.

### Logo and icons

The MoneyLedger logo, launcher icons, favicon and splash logo are MoneyLedger's
own artwork ([`assets/brand/`](assets/brand), rendered by
[`tool/brand/render_icons.py`](tool/brand/render_icons.py)), under the same
license as the app. The in-app icons are Flutter's bundled Material Icons
(Apache-2.0).

## Transitive and build-only dependencies

Build/dev-only tools (`build_runner`, `drift_dev`, `riverpod_generator`,
`flutter_lints`, `sqlite3` for tests) and all transitive dependencies are
permissive — MIT, BSD-2/3-Clause or Apache-2.0 — plus:

- `vodozemac` (Dart package, pulled in by `matrix`) — AGPL-3.0;
- `gtk` — MPL-2.0, Linux-desktop only (not shipped in the Android/web app).

## Compatibility

All of the above are compatible with distributing MoneyLedger under the
AGPL-3.0: the two AGPL-3.0 packages (`matrix`, `flutter_vodozemac`) are the
reason the app itself is AGPL-licensed; MIT, BSD, Apache-2.0 and MPL-2.0 code
may be combined with AGPL-3.0 code. **No incompatible license was found**
(checked against each package's `LICENSE` in the pub cache for the versions in
`pubspec.lock`).

Distributing the app (APK, Play Store, hosted web build) under the AGPL means
the corresponding source code must be offered to its users — the About page
links to <https://github.com/LeoStumpf/MoneyLedger>.
