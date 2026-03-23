import 'package:flutter/foundation.dart';

import '../modules/latest_image_finder_module.dart';
import 'gifticon_pipeline_service.dart';

class ScreenshotAutomationService {
  ScreenshotAutomationService({
    required this.latestImageFinder,
    required this.pipeline,
  });

  final LatestImageFinderModule latestImageFinder;
  final GifticonPipelineService pipeline;

  String? _lastProcessedPath;
  bool _isProcessing = false;
  DateTime? _lastHandledAt;

  Future<GifticonPipelineOutput?> handleScreenshotDetected() async {
    debugPrint('[Gifticon][Automation] screenshot event received');

    if (_isProcessing) {
      debugPrint('[Gifticon][Automation] already processing, ignored');
      return null;
    }

    final now = DateTime.now();
    if (_lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(milliseconds: 1200)) {
      debugPrint('[Gifticon][Automation] debounce ignored');
      return null;
    }

    _isProcessing = true;
    _lastHandledAt = now;

    try {
      final latestImage = await latestImageFinder.findLatestImage();
      if (latestImage == null) {
        debugPrint('[Gifticon][Automation] latest image not found');
        return null;
      }

      debugPrint(
        '[Gifticon][Automation] latest image path=${latestImage.path}',
      );

      if (_lastProcessedPath == latestImage.path) {
        debugPrint('[Gifticon][Automation] duplicate image ignored');
        return null;
      }

      final output = await pipeline.runFromImage(latestImage);

      _lastProcessedPath = latestImage.path;

      debugPrint(
        '[Gifticon][Automation] pipeline completed: '
            'isGifticon=${output.detection.isGifticon}',
      );

      return output;
    } finally {
      _isProcessing = false;
    }
  }

  void resetLastProcessed() {
    _lastProcessedPath = null;
    _lastHandledAt = null;
    debugPrint('[Gifticon][Automation] reset last processed path');
  }
}