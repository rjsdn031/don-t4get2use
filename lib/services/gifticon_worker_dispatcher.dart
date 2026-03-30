import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../modules/remote_gifticon_ai_parser.dart';
import 'device_id_service.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_sharing_service.dart';
import 'gifticon_storage_service.dart';

const String kGifticonParseTask = 'gifticon_parse_task';
const String kGifticonAutoShareTask = 'gifticon_auto_share_task';

const String kInputRawText = 'rawText';
const String kInputImagePath = 'imagePath';
const String kInputGifticonId = 'gifticonId';

const String kGifticonBaseUrl = 'https://d42u-server.vercel.app';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await Hive.initFlutter();

    debugPrint('[Gifticon][Worker] task=$task started');

    final notificationService = GifticonNotificationService(
      FlutterLocalNotificationsPlugin(),
    );

    try {
      if (task == kGifticonParseTask) {
        final rawText = inputData?[kInputRawText] as String?;
        final imagePath = inputData?[kInputImagePath] as String?;

        if (rawText == null ||
            rawText.isEmpty ||
            imagePath == null ||
            imagePath.isEmpty) {
          debugPrint('[Gifticon][Worker] invalid parse input data');
          return false;
        }

        final storageService = GifticonStorageService();
        await storageService.init();
        await notificationService.init();

        final parser = RemoteGifticonAiParser(
          baseUrl: kGifticonBaseUrl,
        );

        debugPrint('[Gifticon][Worker] show processing notification');
        await notificationService.showProcessingNotification();

        debugPrint('[Gifticon][Worker] start remote parse');
        final info = await parser.parse(rawText: rawText);

        debugPrint('[Gifticon][Worker] save parsed gifticon');
        final result = await storageService.saveGifticon(
          sourceImagePath: imagePath,
          info: info,
        );

        if (result.isDuplicate) {
          debugPrint(
            '[Gifticon][Worker] duplicate — skip notification schedule. '
                'existing id=${result.gifticon.id}',
          );
          await notificationService.cancelProcessingNotification();
          debugPrint(
            '[Gifticon][Worker] processing notification cancelled (duplicate)',
          );
          return true;
        }

        final stored = result.gifticon;

        debugPrint('[Gifticon][Worker] schedule expiry notifications');
        final scheduled =
        await notificationService.scheduleExpiryNotifications(stored);

        if (!scheduled) {
          debugPrint(
            '[Gifticon][Worker] expiry notifications were deferred until foreground app resumes',
          );
        }

        debugPrint('[Gifticon][Worker] show saved notification');
        await notificationService.showSavedNotificationFromStored(stored);

        await notificationService.cancelProcessingNotification();
        debugPrint('[Gifticon][Worker] processing notification cancelled');

        debugPrint('[Gifticon][Worker] parse task success');
        return true;
      }

      if (task == kGifticonAutoShareTask) {
        final gifticonId = inputData?[kInputGifticonId] as String?;

        if (gifticonId == null || gifticonId.isEmpty) {
          debugPrint('[Gifticon][Worker] invalid auto share input data');
          return false;
        }

        final storageService = GifticonStorageService();
        await storageService.init();

        final stored = storageService.getGifticonById(gifticonId);
        if (stored == null) {
          debugPrint(
            '[Gifticon][Worker] auto share target not found: id=$gifticonId',
          );
          return true;
        }

        if (stored.isShared) {
          debugPrint(
            '[Gifticon][Worker] already shared — skip auto share: id=$gifticonId',
          );
          return true;
        }

        if (stored.isUsed) {
          debugPrint(
            '[Gifticon][Worker] already used — skip auto share: id=$gifticonId',
          );
          return true;
        }

        if (stored.expiresAt == null) {
          debugPrint(
            '[Gifticon][Worker] expiresAt is null — skip auto share: id=$gifticonId',
          );
          return true;
        }

        final deviceIdService = DeviceIdService(
          baseUrl: kGifticonBaseUrl,
        );

        final sharingService = GifticonSharingService(
          baseUrl: kGifticonBaseUrl,
          storageService: storageService,
          deviceIdService: deviceIdService,
        );

        debugPrint(
          '[Gifticon][Worker] auto share upload start: id=$gifticonId',
        );
        await sharingService.uploadForSharing(stored);
        debugPrint(
          '[Gifticon][Worker] auto share upload done: id=$gifticonId',
        );

        return true;
      }

      debugPrint('[Gifticon][Worker] unknown task ignored');
      return true;
    } catch (e, st) {
      debugPrint('[Gifticon][Worker][Error] $e');
      debugPrintStack(stackTrace: st);

      try {
        await notificationService.cancelProcessingNotification();
        debugPrint(
          '[Gifticon][Worker] processing notification cancelled (on error)',
        );
      } catch (cancelError, cancelSt) {
        debugPrint(
          '[Gifticon][Worker][CancelNotificationError] $cancelError',
        );
        debugPrintStack(stackTrace: cancelSt);
      }

      return false;
    }
  });
}