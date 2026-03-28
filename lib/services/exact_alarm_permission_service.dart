import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExactAlarmPermissionService {
  static const MethodChannel _channel =
  MethodChannel('gifticon/exact_alarm');

  Future<bool> canScheduleExactAlarms() async {
    try {
      final result =
      await _channel.invokeMethod<bool>('canScheduleExactAlarms');
      return result ?? false;
    } on MissingPluginException {
      debugPrint(
        '[Gifticon][ExactAlarm] plugin unavailable in this isolate: canScheduleExactAlarms',
      );
      return false;
    } on PlatformException catch (e) {
      debugPrint(
        '[Gifticon][ExactAlarm] platform exception: ${e.code} ${e.message}',
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
      debugPrint(
        '[Gifticon][ExactAlarm] plugin unavailable in this isolate: openExactAlarmSettings',
      );
      return false;
    } on PlatformException catch (e) {
      debugPrint(
        '[Gifticon][ExactAlarm] platform exception: ${e.code} ${e.message}',
      );
      return false;
    }
  }
}
