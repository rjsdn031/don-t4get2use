import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_logger.dart';
import 'auto_share_settings_service.dart';
import 'device_id_service.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_sharing_service.dart';
import 'gifticon_storage_service.dart';

const String kGifticonBaseUrl = 'https://d42u-server.vercel.app';

class AutoShareExecutor {
  Future<bool> execute(String gifticonId) async {
    final autoShareSettingsService = AutoShareSettingsService();
    final isEnabled = await autoShareSettingsService.isAutoShareEnabled();
    final experimentGroup = await autoShareSettingsService.getExperimentGroup();

    await AppLogger.log(
      tag: 'AutoShareExecutor',
      event: 'start',
      data: {
        'gifticonId': gifticonId,
        'isAutoShareEnabled': isEnabled,
        'experimentGroup': experimentGroup,
      },
    );

    if (!isEnabled) {
      await AppLogger.log(
        tag: 'AutoShareExecutor',
        event: 'skip_disabled',
        data: {
          'gifticonId': gifticonId,
        },
      );
      return true;
    }

    final storageService = GifticonStorageService();
    await storageService.init();

    final stored = storageService.getGifticonById(gifticonId);
    if (stored == null) {
      await AppLogger.log(
        tag: 'AutoShareExecutor',
        event: 'skip_not_found',
        data: {
          'gifticonId': gifticonId,
        },
      );
      return true;
    }

    if (stored.isShared || stored.isUsed || stored.isReceived) {
      await AppLogger.log(
        tag: 'AutoShareExecutor',
        event: 'skip_ineligible',
        data: {
          'gifticonId': gifticonId,
          'isShared': stored.isShared,
          'isUsed': stored.isUsed,
          'isReceived': stored.isReceived,
        },
      );
      return true;
    }

    final expiresAt = stored.expiresAt;
    final now = DateTime.now();

    if (expiresAt == null) {
      await AppLogger.log(
        tag: 'AutoShareExecutor',
        event: 'skip_no_expiry',
        data: {
          'gifticonId': gifticonId,
        },
      );
      return true;
    }

    if (!expiresAt.isAfter(now)) {
      await AppLogger.log(
        tag: 'AutoShareExecutor',
        event: 'skip_expired',
        data: {
          'gifticonId': gifticonId,
          'expiresAt': expiresAt.toIso8601String(),
          'now': now.toIso8601String(),
        },
      );
      return true;
    }

    final deviceIdService = DeviceIdService(baseUrl: kGifticonBaseUrl);
    final sharingService = GifticonSharingService(
      baseUrl: kGifticonBaseUrl,
      storageService: storageService,
      deviceIdService: deviceIdService,
    );

    final success = await sharingService.uploadForSharing(stored);

    if (!success) {
      await AppLogger.log(
        tag: 'AutoShareExecutor',
        event: 'upload_failed',
        data: {
          'gifticonId': gifticonId,
        },
      );
      return false;
    }

    final updated = storageService.getGifticonById(gifticonId);
    if (updated != null && updated.isShared) {
      final notificationService = GifticonNotificationService(
        FlutterLocalNotificationsPlugin(),
      );
      await notificationService.init();
      await notificationService.showSharedNotificationFromStored(updated);

      await AppLogger.log(
        tag: 'AutoShareExecutor',
        event: 'upload_success',
        data: {
          'gifticonId': gifticonId,
        },
      );
    }

    return true;
  }
}