import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../modules/android_latest_image_finder_module.dart';
import '../modules/barcode_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import 'device_id_service.dart';
import 'fcm_service.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_pipeline_service.dart';
import 'gifticon_sharing_service.dart';
import 'gifticon_storage_service.dart';
import 'gifticon_work_service.dart';
import 'now_provider.dart';
import 'screenshot_automation_service.dart';

const String _baseUrl = 'https://d42u-server.vercel.app';

class GifticonServices {
  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;
  final GifticonPipelineService pipelineService;
  final GifticonWorkService workService;
  final ScreenshotAutomationService automationService;
  final DeviceIdService deviceIdService;
  final GifticonSharingService sharingService;
  final FcmService fcmService;

  const GifticonServices({
    required this.storageService,
    required this.notificationService,
    required this.pipelineService,
    required this.workService,
    required this.automationService,
    required this.deviceIdService,
    required this.sharingService,
    required this.fcmService,
  });

  static Future<GifticonServices> create({
    NowProvider? nowProvider,
  }) async {
    final resolvedNowProvider = nowProvider ?? SystemNowProvider();

    final storageService = GifticonStorageService(
      nowProvider: resolvedNowProvider,
    );
    await storageService.init();

    final deviceIdService = DeviceIdService(baseUrl: _baseUrl);

    final sharingService = GifticonSharingService(
      baseUrl: _baseUrl,
      storageService: storageService,
      deviceIdService: deviceIdService,
    );

    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    final notificationService = GifticonNotificationService(
      notificationsPlugin,
      nowProvider: resolvedNowProvider,
      onGifticonSaved: storageService.emitItems,
    );
    await notificationService.init();

    final workService = GifticonWorkService();

    await notificationService.rescheduleAllExpiryNotifications(
      storageService.getAllGifticons(),
    );

    await _reschedulePendingAutoShareWorks(
      storageService: storageService,
      workService: workService,
      nowProvider: resolvedNowProvider,
    );

    final pipelineService = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      barcodeModule: GifticonBarcodeModule(),
      detector: GifticonDetectorModule(),
    );

    final aiParser = RemoteGifticonAiParser(
      baseUrl: _baseUrl,
    );

    final automationService = ScreenshotAutomationService(
      latestImageFinder: AndroidLatestImageFinderModule(),
      pipeline: pipelineService,
      workService: workService,
      aiParser: aiParser,
      storageService: storageService,
      notificationService: notificationService,
    );

    final fcmService = FcmService(
      sharingService: sharingService,
      notifications: notificationsPlugin,
    );

    await deviceIdService.registerDevice();
    await fcmService.init();

    return GifticonServices(
      storageService: storageService,
      notificationService: notificationService,
      pipelineService: pipelineService,
      workService: workService,
      automationService: automationService,
      deviceIdService: deviceIdService,
      sharingService: sharingService,
      fcmService: fcmService,
    );
  }

  static Future<void> _reschedulePendingAutoShareWorks({
    required GifticonStorageService storageService,
    required GifticonWorkService workService,
    required NowProvider nowProvider,
  }) async {
    final now = nowProvider.now();

    for (final stored in storageService.getAllGifticons()) {
      if (stored.isShared || stored.isUsed || stored.expiresAt == null) {
        continue;
      }

      final autoShareAt = DateTime(
        stored.expiresAt!.year,
        stored.expiresAt!.month,
        stored.expiresAt!.day,
        8,
        0,
        0,
      );

      if (!autoShareAt.isAfter(now)) {
        continue;
      }

      await workService.scheduleAutoShareWork(
        gifticonId: stored.id,
        initialDelay: autoShareAt.difference(now),
      );
    }
  }
}