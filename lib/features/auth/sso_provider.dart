import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/url_helper.dart';

/// Stream of incoming SSO callback deep links (e.g. `moneyledger://sso-callback…`
/// on native). Empty on web, which receives the callback via page query params
/// on redirect instead. Overridden with an empty stream in widget tests so they
/// don't touch platform plugins.
final ssoCallbackProvider =
    StreamProvider<Uri>((ref) => incomingSsoLinks());
