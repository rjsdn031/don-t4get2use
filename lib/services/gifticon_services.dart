import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../modules/android_latest_image_finder_module.dart';
import '../modules/barcode_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import 'app_logger.dart';
import 'auto_share_settings_service.dart';
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
  final AutoShareSettingsService autoShareSettingsService;

  const GifticonServices({
    required this.storageService,
    required this.notificationService,
    required this.pipelineService,
    required this.workService,
    required this.automationService,
    required this.deviceIdService,
    required this.sharingService,
    required this.fcmService,
    required this.autoShareSettingsService,
  });

  static Future<GifticonServices> create({
    NowProvider? nowProvider,
  }) async {
    await AppLogger.log(
      tag: 'Services',
      event: 'create_start',
    );

    final resolvedNowProvider = nowProvider ?? SystemNowProvider();

    final storageService = GifticonStorageService(
      nowProvider: resolvedNowProvider,
    );
    await storageService.init();

    await AppLogger.log(
      tag: 'Services',
      event: 'storage_initialized',
      data: {
        'gifticonCount': storageService.getAllGifticons().length,
      },
    );

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

    await AppLogger.log(
      tag: 'Services',
      event: 'notification_initialized',
    );

    final workService = GifticonWorkService();
    final autoShareSettingsService = AutoShareSettingsService();
    final isAutoShareEnabled =
    await autoShareSettingsService.isAutoShareEnabled();

    await notificationService.rescheduleAllExpiryNotifications(
      storageService.getAllGifticons(),
    );

    await AppLogger.log(
      tag: 'Services',
      event: 'expiry_rescheduled',
      data: {
        'gifticonCount': storageService.getAllGifticons().length,
      },
    );

    await _reschedulePendingAutoShareWorks(
      storageService: storageService,
      workService: workService,
      nowProvider: resolvedNowProvider,
      autoShareSettingsService: autoShareSettingsService,
    );

    final pipelineService = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      barcodeModule: GifticonBarcodeModule(),
      detector: GifticonDetectorModule(),
    );

    await AppLogger.log(
      tag: 'Services',
      event: 'pipeline_initialized',
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

    await deviceIdService.registerDevice(
      shareEnabled: isAutoShareEnabled,
    );
    await AppLogger.log(
      tag: 'Services',
      event: 'device_registered',
      data: {
        'shareEnabled': isAutoShareEnabled,
      },
    );

    await fcmService.init();
    await AppLogger.log(
      tag: 'Services',
      event: 'fcm_initialized',
    );

    await AppLogger.log(
      tag: 'Services',
      event: 'create_done',
    );

    return GifticonServices(
      storageService: storageService,
      notificationService: notificationService,
      pipelineService: pipelineService,
      workService: workService,
      automationService: automationService,
      deviceIdService: deviceIdService,
      sharingService: sharingService,
      fcmService: fcmService,
      autoShareSettingsService: autoShareSettingsService,
    );
  }

  static Future<void> _reschedulePendingAutoShareWorks({
    required GifticonStorageService storageService,
    required GifticonWorkService workService,
    required NowProvider nowProvider,
    required AutoShareSettingsService autoShareSettingsService,
  }) async {
    final now = nowProvider.now();
    final isAutoShareEnabled =
    await autoShareSettingsService.isAutoShareEnabled();

    await AppLogger.log(
      tag: 'Services',
      event: 'auto_share_reschedule_start',
      data: {
        'now': now.toIso8601String(),
        'gifticonCount': storageService.getAllGifticons().length,
        'isAutoShareEnabled': isAutoShareEnabled,
      },
    );

    if (!isAutoShareEnabled) {
      await AppLogger.log(
        tag: 'Services',
        event: 'auto_share_reschedule_skip_disabled',
      );
      return;
    }

    for (final stored in storageService.getAllGifticons()) {
      if (stored.isShared || stored.isUsed || stored.expiresAt == null) {
        await AppLogger.log(
          tag: 'Services',
          event: 'auto_share_reschedule_skip',
          data: {
            'gifticonId': stored.id,
            'isShared': stored.isShared,
            'isUsed': stored.isUsed,
            'hasExpiresAt': stored.expiresAt != null,
          },
        );
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
        await AppLogger.log(
          tag: 'Services',
          event: 'auto_share_reschedule_skip_past',
          data: {
            'gifticonId': stored.id,
            'autoShareAt': autoShareAt.toIso8601String(),
            'now': now.toIso8601String(),
          },
        );
        continue;
      }

      final delay = autoShareAt.difference(now);

      await AppLogger.log(
        tag: 'Services',
        event: 'auto_share_reschedule_schedule',
        data: {
          'gifticonId': stored.id,
          'expiresAt': stored.expiresAt!.toIso8601String(),
          'autoShareAt': autoShareAt.toIso8601String(),
          'delay': delay.toString(),
        },
      );

      await workService.scheduleAutoShareWork(
        gifticonId: stored.id,
        initialDelay: delay,
      );
    }

    await AppLogger.log(
      tag: 'Services',
      event: 'auto_share_reschedule_done',
    );
  }
}