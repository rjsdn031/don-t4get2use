import 'dart:io';
import 'package:flutter/foundation.dart';

import '../modules/latest_image_finder_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_pipeline_service.dart';
import 'gifticon_storage_service.dart';
import 'gifticon_work_service.dart';

class ScreenshotAutomationService {
  ScreenshotAutomationService({
    required this.latestImageFinder,
    required this.pipeline,
    required this.workService,
    required this.aiParser,
    required this.storageService,
    required this.notificationService,
  });

  final LatestImageFinderModule latestImageFinder;
  final GifticonPipelineService pipeline;
  final GifticonWorkService workService;
  final RemoteGifticonAiParser aiParser;
  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;

  String? _lastProcessedPath;
  bool _isProcessing = false;
  DateTime? _lastHandledAt;

  Future<bool> _waitUntilFileReady(
      String path, {
        Duration timeout = const Duration(seconds: 3),
        Duration interval = const Duration(milliseconds: 200),
      }) async {
    final file = File(path);
    final stopwatch = Stopwatch()..start();

    int lastLength = -1;
    int stableCount = 0;

    while (stopwatch.elapsed < timeout) {
      try {
        if (await file.exists()) {
          final length = await file.length();

          if (length > 0 && length == lastLength) {
            stableCount += 1;
            if (stableCount >= 2) {
              debugPrint(
                '[Gifticon][Automation] file ready: path=$path length=$length',
              );
              return true;
            }
          } else {
            stableCount = 0;
            lastLength = length;
          }

          debugPrint(
            '[Gifticon][Automation] waiting file... '
                'path=$path length=$length stableCount=$stableCount',
          );
        } else {
          debugPrint('[Gifticon][Automation] file not found yet: $path');
        }
      } catch (e) {
        debugPrint('[Gifticon][Automation] file check error: $e');
      }

      await Future<void>.delayed(interval);
    }

    debugPrint('[Gifticon][Automation] file not ready within timeout: $path');
    return false;
  }

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

      if (_lastProcessedPath == latestImage.path) {
        debugPrint('[Gifticon][Automation] duplicate image ignored');
        return null;
      }

      final ready = await _waitUntilFileReady(latestImage.path);
      if (!ready) {
        debugPrint(
          '[Gifticon][Automation] latest image not ready, skip: ${latestImage.path}',
        );
        return null;
      }

      final sw = Stopwatch()..start();
      final output = await pipeline.runFromImage(latestImage);
      debugPrint('[Gifticon][Automation] pipeline took ${sw.elapsedMilliseconds}ms');
      _lastProcessedPath = latestImage.path;

      if (!output.isGifticon) {
        return output;
      }

      debugPrint('[Gifticon][Automation] enqueue parse work');
      await workService.enqueueParseWork(
        rawText: output.ocr.rawText,
        imagePath: output.image.path,
      );

      if (!isBackground) {
        await notificationService.showProcessingNotification();
      }

      return output;
    } catch (e, st) {
      debugPrint('[Gifticon][Automation][Error] $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    } finally {
      _isProcessing = false;
    }
  }

  void resetLastProcessed() {
    _lastProcessedPath = null;
    _lastHandledAt = null;
  }
}