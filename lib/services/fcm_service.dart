import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'gifticon_sharing_service.dart';

/// 백그라운드 FCM 핸들러 — 최상위 함수여야 함
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM][Background] message received: ${message.messageId}');
  await _handleGifticonMessage(message);
}

Future<void> _handleGifticonMessage(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] as String?;

  debugPrint('[FCM] type=$type data=$data');

  switch (type) {
    case 'gifticon_received':
    // 매칭된 기프티콘 수신 — 로컬 저장은 FcmService.init() 이후 포그라운드에서 처리
    // 백그라운드에서는 Hive 접근이 불안정하므로 data만 로깅
      debugPrint('[FCM] gifticon_received: gifticonId=${data['gifticonId']}');
      break;

    case 'gifticon_used':
      debugPrint('[FCM] gifticon_used: gifticonId=${data['gifticonId']}');
      break;

    default:
      debugPrint('[FCM] unknown type: $type');
  }
}

class FcmService {
  FcmService({
    required this.sharingService,
    required FlutterLocalNotificationsPlugin notifications,
  }) : _notifications = notifications;

  final GifticonSharingService sharingService;
  final FlutterLocalNotificationsPlugin _notifications;

  Future<void> init() async {
    // 포그라운드 메시지 수신
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 앱이 백그라운드에 있다가 알림 탭으로 열린 경우
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 앱이 완전히 종료된 상태에서 알림 탭으로 열린 경우
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] launched from terminated via notification');
      await _onMessageOpenedApp(initial);
    }

    debugPrint('[FCM] FcmService initialized');
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM][Foreground] ${message.messageId}');

    final data = message.data;
    final type = data['type'] as String?;

    if (type == 'gifticon_received') {
      await _handleGifticonReceived(data);
    } else if (type == 'gifticon_used') {
      await _handleGifticonUsed(data);
    }

    // 포그라운드에서는 자동으로 알림이 안 뜨므로 직접 표시
    if (message.notification != null) {
      await _showLocalNotification(message);
    }
  }

  Future<void> _onMessageOpenedApp(RemoteMessage message) async {
    debugPrint('[FCM][OpenedApp] ${message.messageId}');

    final data = message.data;
    final type = data['type'] as String?;

    if (type == 'gifticon_received') {
      await _handleGifticonReceived(data);
    } else if (type == 'gifticon_used') {
      await _handleGifticonUsed(data);
    }
  }

  Future<void> _handleGifticonReceived(Map<String, dynamic> data) async {
    try {
      final gifticonId = data['gifticonId'] as String?;
      final imageUrl = data['imageUrl'] as String?;
      final ownerId = data['ownerId'] as String?;
      final expiresAtStr = data['expiresAt'] as String?;

      if (gifticonId == null || imageUrl == null || expiresAtStr == null) {
        debugPrint('[FCM] gifticon_received: missing required fields');
        return;
      }

      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt == null) {
        debugPrint('[FCM] gifticon_received: invalid expiresAt');
        return;
      }

      await sharingService.receiveSharedGifticon(
        gifticonId: gifticonId,
        imageUrl: imageUrl,
        ownerId: ownerId ?? '',
        merchantName: data['merchantName'] as String?,
        itemName: data['itemName'] as String?,
        couponNumber: data['couponNumber'] as String?,
        expiresAt: expiresAt,
      );
    } catch (e) {
      debugPrint('[FCM] _handleGifticonReceived error: $e');
    }
  }

  Future<void> _handleGifticonUsed(Map<String, dynamic> data) async {
    try {
      final gifticonId = data['gifticonId'] as String?;
      if (gifticonId == null) return;

      // 로컬 Hive에서 해당 기프티콘 사용 처리
      await sharingService.storageService.markAsUsedIfExists(gifticonId);
      debugPrint('[FCM] gifticon_used handled locally: id=$gifticonId');
    } catch (e) {
      debugPrint('[FCM] _handleGifticonUsed error: $e');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'gifticon_fcm',
      '기프티콘 알림',
      channelDescription: '공유 기프티콘 관련 알림',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notifications.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: jsonEncode(message.data),
    );
  }
}