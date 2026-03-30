import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../modules/android_latest_image_finder_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/barcode_module.dart';
import 'device_id_service.dart';
import 'fcm_service.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_pipeline_service.dart';
import 'gifticon_sharing_service.dart';
import 'gifticon_storage_service.dart';
import 'gifticon_work_service.dart';
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

  static Future<GifticonServices> create() async {
    final storageService = GifticonStorageService();
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
      sharingService: sharingService,
    );
    await notificationService.init();

    await notificationService.rescheduleAllExpiryNotifications(
      storageService.getAllGifticons(),
    );

    final pipelineService = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      barcodeModule: GifticonBarcodeModule(),
      detector: GifticonDetectorModule(),
    );

    final workService = GifticonWorkService();

    final automationService = ScreenshotAutomationService(
      latestImageFinder: AndroidLatestImageFinderModule(),
      pipeline: pipelineService,
      workService: workService,
    );

    final fcmService = FcmService(
      sharingService: sharingService,
      notifications: notificationsPlugin,
    );

    // 기기 등록 (FCM 토큰 갱신 포함) — 실패해도 앱 실행 계속
    await deviceIdService.registerDevice();

    // FCM 포그라운드/탭 핸들러 등록
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
}