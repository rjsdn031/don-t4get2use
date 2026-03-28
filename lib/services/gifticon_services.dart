import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../modules/android_latest_image_finder_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/barcode_module.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_pipeline_service.dart';
import 'gifticon_storage_service.dart';
import 'gifticon_work_service.dart';
import 'screenshot_automation_service.dart';

class GifticonServices {
  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;
  final GifticonPipelineService pipelineService;
  final GifticonWorkService workService;
  final ScreenshotAutomationService automationService;

  const GifticonServices({
    required this.storageService,
    required this.notificationService,
    required this.pipelineService,
    required this.workService,
    required this.automationService,
  });

  static Future<GifticonServices> create() async {
    final storageService = GifticonStorageService();
    await storageService.init();

    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    final notificationService = GifticonNotificationService(
      notificationsPlugin,
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

    return GifticonServices(
      storageService: storageService,
      notificationService: notificationService,
      pipelineService: pipelineService,
      workService: workService,
      automationService: automationService,
    );
  }
}