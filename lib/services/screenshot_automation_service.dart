import 'package:flutter/foundation.dart';

import '../modules/latest_image_finder_module.dart';
import 'gifticon_pipeline_service.dart';
import 'gifticon_work_service.dart';

class ScreenshotAutomationService {
  ScreenshotAutomationService({
    required this.latestImageFinder,
    required this.pipeline,
    required this.workService,
  });

  final LatestImageFinderModule latestImageFinder;
  final GifticonPipelineService pipeline;
  final GifticonWorkService workService;

  String? _lastProcessedPath;
  bool _isProcessing = false;
  DateTime? _lastHandledAt;

  Future<GifticonPipelineOutput?> handleScreenshotDetected({
    bool isBackground = false,
  }) async {
    debugPrint('[Gifticon][Automation] screenshot event received');
    debugPrint('[Gifticon][Automation] isBackground=$isBackground');

    if (_isProcessing) {
      debugPrint('[Gifticon][Automation] already processing, ignored');
      return null;
    }

    final now = DateTime.now();
    debugPrint('[Gifticon][Automation] now=$now');
    debugPrint('[Gifticon][Automation] lastHandledAt=$_lastHandledAt');

    if (_lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(milliseconds: 1200)) {
      debugPrint('[Gifticon][Automation] debounce ignored');
      return null;
    }

    _isProcessing = true;
    _lastHandledAt = now;

    try {
      debugPrint('[Gifticon][Automation] finding latest image...');
      final latestImage = await latestImageFinder.findLatestImage();

      if (latestImage == null) {
        debugPrint('[Gifticon][Automation] latest image not found');
        return null;
      }

      debugPrint('[Gifticon][Automation] latest image path=${latestImage.path}');
      debugPrint('[Gifticon][Automation] lastProcessedPath=$_lastProcessedPath');

      if (_lastProcessedPath == latestImage.path) {
        debugPrint('[Gifticon][Automation] duplicate image ignored');
        return null;
      }

      debugPrint('[Gifticon][Automation] entering pipeline...');
      final output = await pipeline.runFromImage(latestImage);

      _lastProcessedPath = latestImage.path;

      debugPrint(
        '[Gifticon][Automation] pipeline completed: '
            'isGifticon=${output.isGifticon}',
      );

      if (!output.isGifticon) {
        return output;
      }

      debugPrint('[Gifticon][Automation] enqueue parse work...');
      await workService.enqueueParseWork(
        rawText: output.ocr.rawText,
        imagePath: output.image.path,
      );
      debugPrint('[Gifticon][Automation] parse work enqueued');

      return output;
    } catch (e, st) {
      debugPrint('[Gifticon][Automation][Error] $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    } finally {
      _isProcessing = false;
      debugPrint('[Gifticon][Automation] processing finished');
    }
  }

  void resetLastProcessed() {
    _lastProcessedPath = null;
    _lastHandledAt = null;
    debugPrint('[Gifticon][Automation] reset last processed path');
  }
}