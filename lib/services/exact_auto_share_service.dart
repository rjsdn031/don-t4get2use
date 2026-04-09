import 'package:flutter/services.dart';
import 'app_logger.dart';

class ExactAutoShareService {
  static const _channel = MethodChannel('gifticon/auto_share_alarm');

  Future<void> scheduleAutoShareAlarm({
    required String gifticonId,
    required DateTime triggerAt,
  }) async {
    await AppLogger.log(
      tag: 'ExactAutoShare',
      event: 'schedule_alarm',
      data: {
        'gifticonId': gifticonId,
        'triggerAt': triggerAt.toIso8601String(),
      },
    );

    await _channel.invokeMethod('scheduleAutoShareAlarm', {
      'gifticonId': gifticonId,
      'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
    });
  }

  Future<void> cancelAutoShareAlarm(String gifticonId) async {
    await AppLogger.log(
      tag: 'ExactAutoShare',
      event: 'cancel_alarm',
      data: {
        'gifticonId': gifticonId,
      },
    );

    await _channel.invokeMethod('cancelAutoShareAlarm', {
      'gifticonId': gifticonId,
    });
  }
}