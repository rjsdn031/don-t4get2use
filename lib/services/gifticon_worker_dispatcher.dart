import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../modules/remote_gifticon_ai_parser.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_storage_service.dart';

const String kGifticonParseTask = 'gifticon_parse_task';
const String kInputRawText = 'rawText';
const String kInputImagePath = 'imagePath';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await Hive.initFlutter();

    debugPrint('[Gifticon][Worker] task=$task started');

    if (task != kGifticonParseTask) {
      debugPrint('[Gifticon][Worker] unknown task ignored');
      return true;
    }

    final rawText = inputData?[kInputRawText] as String?;
    final imagePath = inputData?[kInputImagePath] as String?;

    if (rawText == null ||
        rawText.isEmpty ||
        imagePath == null ||
        imagePath.isEmpty) {
      debugPrint('[Gifticon][Worker] invalid input data');
      return false;
    }

    final notificationService = GifticonNotificationService(
      FlutterLocalNotificationsPlugin(),
    );

    try {
      final storageService = GifticonStorageService();
      await storageService.init();

      await notificationService.init();

      final parser = RemoteGifticonAiParser(
        baseUrl: 'https://d42u-server.vercel.app',
      );

      debugPrint('[Gifticon][Worker] show processing notification');
      await notificationService.showProcessingNotification();

      debugPrint('[Gifticon][Worker] start remote parse');
      final info = await parser.parse(rawText: rawText);

      debugPrint('[Gifticon][Worker] save parsed gifticon');
      final stored = await storageService.saveGifticon(
        sourceImagePath: imagePath,
        info: info,
      );

      debugPrint('[Gifticon][Worker] show saved notification');
      await notificationService.showSavedNotificationFromStored(stored);

      debugPrint('[Gifticon][Worker] task success');
      return true;
    } catch (e, st) {
      debugPrint('[Gifticon][Worker][Error] $e');
      debugPrintStack(stackTrace: st);

      try {
        await notificationService.init();
        await notificationService.cancelProcessingNotification();
        debugPrint('[Gifticon][Worker] processing notification cancelled');
      } catch (cancelError, cancelSt) {
        debugPrint('[Gifticon][Worker][CancelNotificationError] $cancelError');
        debugPrintStack(stackTrace: cancelSt);
      }

      return false;
    }
  });
}