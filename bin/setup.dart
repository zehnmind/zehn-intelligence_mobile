// dart run zehn_intelligence:setup <code>
//
// Adds Zehn Intelligence to the Flutter app in the current folder: the app's
// file and one line in main() (lib/src/setup/setup.dart). `--remove` puts
// every file back.
import 'dart:io';

import 'package:zehn_intelligence/src/setup/setup.dart';

Future<void> main(List<String> args) async {
  exitCode = await runSetup(args);
}
