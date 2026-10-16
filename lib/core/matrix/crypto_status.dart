import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the end-to-end encryption backend (vodozemac) initialised at
/// startup (G33). `main()` overrides it with `false` when `vod.init()`
/// throws: the Matrix SDK then runs with encryption disabled, every send
/// fails with `TransportUnavailableException`, and the groups page shows a
/// persistent banner instead of the failure only reaching the log.
final cryptoAvailableProvider = Provider<bool>((ref) => true);
