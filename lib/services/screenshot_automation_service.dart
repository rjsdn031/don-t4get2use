import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../modules/latest_image_finder_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import 'app_logger.dart';
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
              await AppLogger.log(
                tag: 'Automation',
                event: 'file_ready',
                data: {
                  'path': path,
                  'length': length,
                },
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
          await AppLogger.log(
            tag: 'Automation',
            event: 'file_not_found_yet',
            data: {
              'path': path,
            },
          );
        }
      } catch (e) {
        await AppLogger.log(
          tag: 'Automation',
          event: 'file_check_error',
          data: {
            'path': path,
            'error': '$e',
          },
        );
      }

      await Future<void>.delayed(interval);
    }

    await AppLogger.log(
      tag: 'Automation',
      event: 'file_not_ready_timeout',
      data: {
        'path': path,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    return false;
  }

  Future<GifticonPipelineOutput?> handleScreenshotDetected({
    bool isBackground = false,
  }) async {
    await AppLogger.log(
      tag: 'Automation',
      event: 'screenshot_event_received',
      data: {
        'isBackground': isBackground,
      },
    );

    if (_isProcessing) {
      await AppLogger.log(
        tag: 'Automation',
        event: 'already_processing_skip',
      );
      return null;
    }

    final now = DateTime.now();

    if (_lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(milliseconds: 1200)) {
      await AppLogger.log(
        tag: 'Automation',
        event: 'debounce_skip',
        data: {
          'lastHandledAt': _lastHandledAt!.toIso8601String(),
          'now': now.toIso8601String(),
        },
      );
      return null;
    }

    _isProcessing = true;
    _lastHandledAt = now;

    try {
      final latestImage = await latestImageFinder.findLatestImage();
      if (latestImage == null) {
        await AppLogger.log(
          tag: 'Automation',
          event: 'latest_image_not_found',
        );
        return null;
      }

      await AppLogger.log(
        tag: 'Automation',
        event: 'latest_image_found',
        data: {
          'path': latestImage.path,
          'fileName': latestImage.fileName,
          'sizeBytes': latestImage.sizeBytes,
        },
      );

      if (_lastProcessedPath == latestImage.path) {
        await AppLogger.log(
          tag: 'Automation',
          event: 'duplicate_image_skip',
          data: {
            'path': latestImage.path,
          },
        );
        return null;
      }

      final ready = await _waitUntilFileReady(latestImage.path);
      if (!ready) {
        await AppLogger.log(
          tag: 'Automation',
          event: 'latest_image_not_ready_skip',
          data: {
            'path': latestImage.path,
          },
        );
        return null;
      }

      final sw = Stopwatch()..start();
      final output = await pipeline.runFromImage(latestImage);

      await AppLogger.log(
        tag: 'Automation',
        event: 'pipeline_done',
        data: {
          'elapsedMs': sw.elapsedMilliseconds,
          'path': latestImage.path,
          'isGifticon': output.isGifticon,
          'rawTextLength': output.ocr.rawText.length,
        },
      );

      _lastProcessedPath = latestImage.path;

      if (!output.isGifticon) {
        await AppLogger.log(
          tag: 'Automation',
          event: 'non_gifticon_skip',
          data: {
            'path': latestImage.path,
          },
        );
        return output;
      }

      await AppLogger.log(
        tag: 'Automation',
        event: 'enqueue_parse_work',
        data: {
          'imagePath': output.image.path,
          'rawTextLength': output.ocr.rawText.length,
        },
      );

      await workService.enqueueParseWork(
        rawText: output.ocr.rawText,
        imagePath: output.image.path,
      );

      if (!isBackground) {
        await AppLogger.log(
          tag: 'Automation',
          event: 'show_processing_notification',
        );
        await notificationService.showProcessingNotification();
      }

      return output;
    } catch (e, st) {
      await AppLogger.log(
        tag: 'Automation',
        event: 'error',
        data: {
          'error': '$e',
          'stack': '$st',
        },
      );
      rethrow;
    } finally {
      _isProcessing = false;

      await AppLogger.log(
        tag: 'Automation',
        event: 'processing_finished',
      );
    }
  }

  void resetLastProcessed() {
    _lastProcessedPath = null;
    _lastHandledAt = null;

    AppLogger.log(
      tag: 'Automation',
      event: 'reset_last_processed',
    );
  }
}