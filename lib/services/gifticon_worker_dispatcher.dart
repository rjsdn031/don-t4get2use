import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../modules/remote_gifticon_ai_parser.dart';
import 'app_logger.dart';
import 'auto_share_settings_service.dart';
import 'device_id_service.dart';
import 'exact_auto_share_service.dart';
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

    await AppLogger.log(
      tag: 'Worker',
      event: 'task_started',
      data: {
        'task': task,
      },
    );

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
          await AppLogger.log(
            tag: 'Worker',
            event: 'invalid_parse_input_data',
            data: {
              'hasRawText': rawText != null && rawText.isNotEmpty,
              'hasImagePath': imagePath != null && imagePath.isNotEmpty,
            },
          );
          return false;
        }

        final storageService = GifticonStorageService();
        final exactAutoShareService = ExactAutoShareService();
        final autoShareSettingsService = AutoShareSettingsService();

        await storageService.init();
        await notificationService.init();

        final parser = RemoteGifticonAiParser(
          baseUrl: kGifticonBaseUrl,
        );

        await AppLogger.log(
          tag: 'Worker',
          event: 'show_processing_notification',
        );
        await notificationService.showProcessingNotification();

        await AppLogger.log(
          tag: 'Worker',
          event: 'remote_parse_start',
          data: {
            'rawTextLength': rawText.length,
            'imagePath': imagePath,
          },
        );

        final sw = Stopwatch()..start();
        final info = await parser.parse(rawText: rawText);

        await AppLogger.log(
          tag: 'Worker',
          event: 'remote_parse_done',
          data: {
            'elapsedMs': sw.elapsedMilliseconds,
            'merchantName': info.merchantName,
            'itemName': info.itemName,
            'couponNumber': info.couponNumber,
            'expiresAt': info.expiresAt?.toIso8601String(),
          },
        );

        await AppLogger.log(
          tag: 'Worker',
          event: 'save_parsed_gifticon_start',
        );
        final result = await storageService.saveGifticon(
          sourceImagePath: imagePath,
          info: info,
        );

        if (result.isDuplicate) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'duplicate_skip_notification_schedule',
            data: {
              'existingId': result.gifticon.id,
            },
          );
          await notificationService.cancelProcessingNotification();
          await AppLogger.log(
            tag: 'Worker',
            event: 'processing_notification_cancelled_duplicate',
          );
          return true;
        }

        final stored = result.gifticon;

        await AppLogger.log(
          tag: 'Worker',
          event: 'schedule_expiry_notifications_start',
          data: {
            'gifticonId': stored.id,
          },
        );

        final scheduled =
        await notificationService.scheduleExpiryNotifications(stored);

        if (!scheduled) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'expiry_notifications_deferred_until_foreground',
            data: {
              'gifticonId': stored.id,
            },
          );
        }

        // 자동 공유 설정 확인
        final isAutoShareEnabled = await autoShareSettingsService.isAutoShareEnabled();
        final experimentGroup = await autoShareSettingsService.getExperimentGroup();

        await AppLogger.log(
          tag: 'Worker',
          event: 'check_auto_share_settings',
          data: {
            'gifticonId': stored.id,
            'isAutoShareEnabled': isAutoShareEnabled,
            'experimentGroup': experimentGroup,
          },
        );

        final expiresAt = stored.expiresAt;
        if (expiresAt != null && isAutoShareEnabled) {
          final autoShareAt = DateTime(
            expiresAt.year,
            expiresAt.month,
            expiresAt.day,
            8,
            0,
            0,
          );

          final now = DateTime.now();

          if (autoShareAt.isAfter(now)) {
            final delay = autoShareAt.difference(now);

            await AppLogger.log(
              tag: 'Worker',
              event: 'schedule_auto_share',
              data: {
                'gifticonId': stored.id,
                'autoShareAt': autoShareAt.toIso8601String(),
                'now': now.toIso8601String(),
                'delay': delay.toString(),
                'experimentGroup': experimentGroup,
              },
            );

            await exactAutoShareService.scheduleAutoShareAlarm(
              gifticonId: stored.id,
              triggerAt: autoShareAt,
            );
          } else {
            await AppLogger.log(
              tag: 'Worker',
              event: 'auto_share_time_passed_skip',
              data: {
                'gifticonId': stored.id,
                'autoShareAt': autoShareAt.toIso8601String(),
                'now': now.toIso8601String(),
              },
            );
          }
        } else if (expiresAt != null && !isAutoShareEnabled) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'auto_share_disabled_skip',
            data: {
              'gifticonId': stored.id,
              'experimentGroup': experimentGroup,
            },
          );
        }

        await AppLogger.log(
          tag: 'Worker',
          event: 'show_saved_notification',
          data: {
            'gifticonId': stored.id,
          },
        );
        await notificationService.showSavedNotificationFromStored(stored);

        await GifticonStorageService.markPendingRefresh();

        await notificationService.cancelProcessingNotification();
        await AppLogger.log(
          tag: 'Worker',
          event: 'processing_notification_cancelled_success',
        );

        await AppLogger.log(
          tag: 'Worker',
          event: 'parse_task_success',
          data: {
            'gifticonId': stored.id,
          },
        );
        return true;
      }

      if (task == kGifticonAutoShareTask) {
        final gifticonId = inputData?[kInputGifticonId] as String?;

        if (gifticonId == null || gifticonId.isEmpty) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'invalid_auto_share_input_data',
          );
          return false;
        }

        // 자동 공유 설정 확인 (A군인 경우 실행하지 않음)
        final autoShareSettingsService = AutoShareSettingsService();
        final isAutoShareEnabled = await autoShareSettingsService.isAutoShareEnabled();
        final experimentGroup = await autoShareSettingsService.getExperimentGroup();

        await AppLogger.log(
          tag: 'Worker',
          event: 'auto_share_task_settings_check',
          data: {
            'gifticonId': gifticonId,
            'isAutoShareEnabled': isAutoShareEnabled,
            'experimentGroup': experimentGroup,
          },
        );

        if (!isAutoShareEnabled) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'auto_share_skip_disabled',
            data: {
              'gifticonId': gifticonId,
              'experimentGroup': experimentGroup,
            },
          );
          return true;
        }

        final storageService = GifticonStorageService();
        await storageService.init();
        await notificationService.init();

        final stored = storageService.getGifticonById(gifticonId);
        if (stored == null) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'auto_share_target_not_found',
            data: {
              'gifticonId': gifticonId,
            },
          );
          return true;
        }

        if (stored.isShared) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'auto_share_skip_already_shared',
            data: {
              'gifticonId': gifticonId,
            },
          );
          return true;
        }

        if (stored.isUsed) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'auto_share_skip_already_used',
            data: {
              'gifticonId': gifticonId,
            },
          );
          return true;
        }

        if (stored.expiresAt == null) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'auto_share_skip_expires_at_null',
            data: {
              'gifticonId': gifticonId,
            },
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

        await AppLogger.log(
          tag: 'Worker',
          event: 'auto_share_upload_start',
          data: {
            'gifticonId': gifticonId,
            'experimentGroup': experimentGroup,
          },
        );

        final success = await sharingService.uploadForSharing(stored);

        if (!success) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'auto_share_upload_failed',
            data: {
              'gifticonId': gifticonId,
              'experimentGroup': experimentGroup,
            },
          );
          return true;
        }

        await AppLogger.log(
          tag: 'Worker',
          event: 'auto_share_upload_success',
          data: {
            'gifticonId': gifticonId,
            'experimentGroup': experimentGroup,
          },
        );

        final updated = storageService.getGifticonById(gifticonId);
        if (updated != null && updated.isShared) {
          await AppLogger.log(
            tag: 'Worker',
            event: 'show_shared_notification',
            data: {
              'gifticonId': gifticonId,
            },
          );
          await notificationService.showSharedNotificationFromStored(updated);
        }

        return true;
      }

      await AppLogger.log(
        tag: 'Worker',
        event: 'unknown_task_ignored',
        data: {
          'task': task,
        },
      );
      return true;
    } catch (e, st) {
      await AppLogger.log(
        tag: 'Worker',
        event: 'error',
        data: {
          'task': task,
          'error': '$e',
          'stack': '$st',
        },
      );

      try {
        await notificationService.cancelProcessingNotification();
        await AppLogger.log(
          tag: 'Worker',
          event: 'processing_notification_cancelled_on_error',
        );
      } catch (cancelError, cancelSt) {
        await AppLogger.log(
          tag: 'Worker',
          event: 'cancel_notification_error',
          data: {
            'error': '$cancelError',
            'stack': '$cancelSt',
          },
        );
      }

      return false;
    }
  });
}