import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../modules/android_latest_image_finder_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_pipeline_service.dart';
import 'gifticon_storage_service.dart';
import 'screenshot_automation_service.dart';

class GifticonServices {
  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;
  final GifticonPipelineService pipelineService;
  final ScreenshotAutomationService automationService;

  const GifticonServices({
    required this.storageService,
    required this.notificationService,
    required this.pipelineService,
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

    final pipelineService = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      detector: GifticonDetectorModule(),
      aiParser: RemoteGifticonAiParser(
        baseUrl: 'https://d42u-server.vercel.app',
      ),
      storageService: storageService,
      notificationService: notificationService,
    );

    final automationService = ScreenshotAutomationService(
      latestImageFinder: AndroidLatestImageFinderModule(),
      pipeline: pipelineService,
    );

    return GifticonServices(
      storageService: storageService,
      notificationService: notificationService,
      pipelineService: pipelineService,
      automationService: automationService,
    );
  }
}