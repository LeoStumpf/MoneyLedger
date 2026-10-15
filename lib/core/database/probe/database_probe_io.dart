import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Native: drift_flutter stores `<name>.sqlite` in the app documents dir.
Future<bool> databaseExists(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}$name.sqlite').exists();
}
