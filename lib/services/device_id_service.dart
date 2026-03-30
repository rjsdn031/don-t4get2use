import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static const String _deviceIdKey = 'device_id';
  static const String _fcmTokenKey = 'fcm_token';
  static const String _nicknameKey = 'nickname';

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

  /// 기기 ID 반환 — 없으면 새로 발급 후 저장
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final newId = const Uuid().v4();
    await prefs.setString(_deviceIdKey, newId);
    debugPrint('[DeviceId] new device id generated: $newId');
    return newId;
  }

  /// 저장된 nickname 반환
  Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nicknameKey);
  }

  /// 저장된 FCM 토큰 반환 (로컬 캐시)
  Future<String?> getCachedFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fcmTokenKey);
  }

  /// FCM 토큰 발급 + 서버 기기 등록
  /// 앱 시작 시 1회 호출
  Future<void> registerDevice() async {
    try {
      final deviceId = await getDeviceId();
      final token = await _getFcmToken();

      if (token == null) {
        debugPrint('[DeviceId] FCM token unavailable — skip registration');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString(_fcmTokenKey);
      final cachedNickname = prefs.getString(_nicknameKey);

      if (cachedToken == token &&
          cachedNickname != null &&
          cachedNickname.isNotEmpty) {
        debugPrint(
          '[DeviceId] FCM token unchanged and nickname cached — skip registration',
        );
        return;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/devices/register',
        data: {
          'deviceId': deviceId,
          'fcmToken': token,
        },
      );
      debugPrint('[DeviceId] register response: ${response.data}');

      final data = response.data ?? <String, dynamic>{};
      final nickname = data['nickname'] as String?;

      await prefs.setString(_fcmTokenKey, token);

      if (nickname != null && nickname.isNotEmpty) {
        await prefs.setString(_nicknameKey, nickname);
        debugPrint('[DeviceId] nickname saved: $nickname');
      } else {
        debugPrint(
          '[DeviceId] nickname missing in register response'
              ' — keep cached nickname: $cachedNickname',
        );
      }

      debugPrint('[DeviceId] device registered: deviceId=$deviceId');
    } catch (e) {
      debugPrint('[DeviceId] registration failed: $e');
    }
  }

  Future<String?> _getFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[DeviceId] notification permission denied');
        return null;
      }

      final token = await messaging.getToken();
      final preview = token == null
          ? 'null'
          : token.length <= 10
          ? token
          : '${token.substring(0, 10)}...';
      debugPrint('[DeviceId] FCM token: $preview');
      return token;
    } catch (e) {
      debugPrint('[DeviceId] FCM token fetch failed: $e');
      return null;
    }
  }
}