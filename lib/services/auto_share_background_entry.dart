import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_logger.dart';
import 'auto_share_executor.dart';

@pragma('vm:entry-point')
Future<void> autoShareBackgroundEntry(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Hive.initFlutter();

  final gifticonId = args.isNotEmpty ? args.first : '';
  if (gifticonId.isEmpty) {
    await AppLogger.log(
      tag: 'AutoShareEntry',
      event: 'invalid_args',
    );
    return;
  }

  final executor = AutoShareExecutor();
  await executor.execute(gifticonId);
}