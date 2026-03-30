import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'gifticon_sharing_service.dart';

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
      debugPrint(
        '[FCM] gifticon_received: gifticonId=${data['gifticonId']} ownerNickname=${data['ownerNickname']}',
      );
      break;

    case 'gifticon_used':
      debugPrint(
        '[FCM] gifticon_used: gifticonId=${data['gifticonId']} usedByNickname=${data['usedByNickname']}',
      );
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
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

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
      final ownerNickname = data['ownerNickname'] as String?;
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
        ownerNickname: ownerNickname,
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
      final usedByNickname = data['usedByNickname'] as String?;
      if (gifticonId == null) return;

      await sharingService.storageService.markAsUsedIfExists(
        gifticonId,
        usedByNickname: usedByNickname,
      );
      debugPrint(
        '[FCM] gifticon_used handled locally: id=$gifticonId usedByNickname=$usedByNickname',
      );
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
      id: message.hashCode.abs(),
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: jsonEncode(message.data),
    );
  }
}