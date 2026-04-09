import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'app_logger.dart';

class DeviceIdService {
  static const String _deviceIdKey = 'device_id';
  static const String _fcmTokenKey = 'fcm_token';
  static const String _nicknameKey = 'nickname';
  static const String _shareEnabledKey = 'share_enabled';

  final Dio _dio;

  DeviceIdService({required String baseUrl})
      : _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final newId = const Uuid().v4();
    await prefs.setString(_deviceIdKey, newId);
    await AppLogger.log(
      tag: 'DeviceId',
      event: 'new_device_id_generated',
      data: {
        'deviceId': newId,
      },
    );
    return newId;
  }

  Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nicknameKey);
  }

  Future<String?> getCachedFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fcmTokenKey);
  }

  Future<void> registerDevice({required bool shareEnabled}) async {
    try {
      final deviceId = await getDeviceId();
      final token = await _getFcmToken();

      if (token == null) {
        await AppLogger.log(
          tag: 'DeviceId',
          event: 'fcm_unavailable_skip_registration',
          data: {
            'shareEnabled': shareEnabled,
          },
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString(_fcmTokenKey);
      final cachedNickname = prefs.getString(_nicknameKey);
      final cachedShareEnabled = prefs.getBool(_shareEnabledKey);

      final shouldSkip =
          cachedToken == token &&
              cachedNickname != null &&
              cachedNickname.isNotEmpty &&
              cachedShareEnabled == shareEnabled;

      if (shouldSkip) {
        await AppLogger.log(
          tag: 'DeviceId',
          event: 'skip_registration_cached',
          data: {
            'shareEnabled': shareEnabled,
          },
        );
        return;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/devices/register',
        data: {
          'deviceId': deviceId,
          'fcmToken': token,
          'shareEnabled': shareEnabled,
        },
      );

      await AppLogger.log(
        tag: 'DeviceId',
        event: 'register_response',
        data: {
          'response': '${response.data}',
          'shareEnabled': shareEnabled,
        },
      );

      final data = response.data ?? <String, dynamic>{};
      final nickname = data['nickname'] as String?;

      await prefs.setString(_fcmTokenKey, token);
      await prefs.setBool(_shareEnabledKey, shareEnabled);

      if (nickname != null && nickname.isNotEmpty) {
        await prefs.setString(_nicknameKey, nickname);
        await AppLogger.log(
          tag: 'DeviceId',
          event: 'nickname_saved',
          data: {
            'nickname': nickname,
          },
        );
      } else {
        await AppLogger.log(
          tag: 'DeviceId',
          event: 'nickname_missing_keep_cached',
          data: {
            'cachedNickname': cachedNickname,
          },
        );
      }

      await AppLogger.log(
        tag: 'DeviceId',
        event: 'device_registered',
        data: {
          'deviceId': deviceId,
          'shareEnabled': shareEnabled,
        },
      );
    } catch (e) {
      await AppLogger.log(
        tag: 'DeviceId',
        event: 'registration_failed',
        data: {
          'error': '$e',
          'shareEnabled': shareEnabled,
        },
      );
      rethrow;
    }
  }

  Future<String?> _getFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        await AppLogger.log(
          tag: 'DeviceId',
          event: 'notification_permission_denied',
        );
        return null;
      }

      final token = await messaging.getToken();
      final preview = token == null
          ? 'null'
          : token.length <= 10
          ? token
          : '${token.substring(0, 10)}...';
      await AppLogger.log(
        tag: 'DeviceId',
        event: 'fcm_token_fetched',
        data: {
          'preview': preview,
        },
      );
      return token;
    } catch (e) {
      await AppLogger.log(
        tag: 'DeviceId',
        event: 'fcm_token_fetch_failed',
        data: {
          'error': '$e',
        },
      );
      return null;
    }
  }
}