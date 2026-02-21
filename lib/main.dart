import 'package:flutter/material.dart';
import 'package:empty_player/frame.dart';
import 'package:media_kit/media_kit.dart';
import 'package:empty_player/v2/app_shell/bootstrap_v2.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    await AppBootstrapV2.initialize();
  } catch (error, stackTrace) {
    debugPrint('V2 bootstrap failed: $error');
    debugPrint('$stackTrace');
  }
  runApp(const Frame());
}
