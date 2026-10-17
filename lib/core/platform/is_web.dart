import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// G75 (U31): "are we running in a browser?" — `kIsWeb`, as a provider so
/// widget tests can show the web-only UI.
final isWebProvider = Provider<bool>((ref) => kIsWeb);
