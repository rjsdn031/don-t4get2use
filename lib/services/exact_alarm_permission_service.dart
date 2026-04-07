import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_logger.dart';

class ExactAlarmPermissionService {
  static const MethodChannel _channel =
  MethodChannel('gifticon/exact_alarm');

  Future<bool> canScheduleExactAlarms() async {
    try {
      final result =
      await _channel.invokeMethod<bool>('canScheduleExactAlarms');
      return result ?? false;
    } on MissingPluginException {
      await AppLogger.log(
        tag: 'ExactAlarm',
        event: 'plugin_unavailable_can_schedule',
      );
      return false;
    } on PlatformException catch (e) {
      await AppLogger.log(
        tag: 'ExactAlarm',
        event: 'platform_exception_can_schedule',
        data: {
          'code': e.code,
          'message': e.message,
        },
      );
      return false;
    }
  }

  Future<bool> openExactAlarmSettings() async {
    try {
      final result =
      await _channel.invokeMethod<bool>('openExactAlarmSettings');
      return result ?? false;
    } on MissingPluginException {
      await AppLogger.log(
        tag: 'ExactAlarm',
        event: 'plugin_unavailable_open_settings',
      );
      return false;
    } on PlatformException catch (e) {
      await AppLogger.log(
        tag: 'ExactAlarm',
        event: 'platform_exception_open_settings',
        data: {
          'code': e.code,
          'message': e.message,
        },
      );
      return false;
    }
  }
}
