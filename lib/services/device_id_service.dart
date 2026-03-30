import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static const String _deviceIdKey = 'device_id';
  static const String _fcmTokenKey = 'fcm_token';

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

  /// FCM 토큰 발급 + Firestore 기기 등록
  /// 앱 시작 시 1회 호출
  Future<void> registerDevice() async {
    try {
      final deviceId = await getDeviceId();
      final token = await _getFcmToken();

      if (token == null) {
        debugPrint('[DeviceId] FCM token unavailable — skip registration');
        return;
      }

      // 이전 토큰과 같으면 재등록 스킵
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString(_fcmTokenKey);
      if (cachedToken == token) {
        debugPrint('[DeviceId] FCM token unchanged — skip registration');
        return;
      }

      await _dio.post<void>(
        '/api/devices/register',
        data: {
          'deviceId': deviceId,
          'fcmToken': token,
        },
      );

      await prefs.setString(_fcmTokenKey, token);
      debugPrint('[DeviceId] device registered: deviceId=$deviceId');
    } catch (e) {
      // 등록 실패는 앱 실행을 막지 않음
      debugPrint('[DeviceId] registration failed: $e');
    }
  }

  /// 저장된 FCM 토큰 반환 (로컬 캐시)
  Future<String?> getCachedFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fcmTokenKey);
  }

  Future<String?> _getFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // 권한 요청 (iOS 대응, Android 13+)
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[DeviceId] notification permission denied');
        return null;
      }

      final token = await messaging.getToken();
      debugPrint('[DeviceId] FCM token: ${token?.substring(0, 10)}...');
      return token;
    } catch (e) {
      debugPrint('[DeviceId] FCM token fetch failed: $e');
      return null;
    }
  }
}