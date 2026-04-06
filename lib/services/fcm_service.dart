import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gifticon_sharing_service.dart';
import 'gifticon_storage_service.dart';

const String _pendingFcmEventsKey = 'gifticon_pending_fcm_events';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM][Background] message received: ${message.messageId}');
  await _enqueuePendingFcmEvent(message.data);
  await GifticonStorageService.markPendingRefresh();
}

Future<void> _enqueuePendingFcmEvent(Map<String, dynamic> data) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_pendingFcmEventsKey) ?? <String>[];

    current.add(jsonEncode(Map<String, dynamic>.from(data)));

    await prefs.setStringList(_pendingFcmEventsKey, current);
    debugPrint('[FCM][Background] pending event queued: type=${data['type']}');
  } catch (e) {
    debugPrint('[FCM][Background] failed to queue pending event: $e');
  }
}

Future<List<Map<String, dynamic>>> _consumePendingFcmEvents() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_pendingFcmEventsKey) ?? <String>[];

    if (rawList.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    await prefs.remove(_pendingFcmEventsKey);

    final events = <Map<String, dynamic>>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          events.add(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        debugPrint('[FCM] failed to decode pending event: $e');
      }
    }

    debugPrint('[FCM] consumed pending events: count=${events.length}');
    return events;
  } catch (e) {
    debugPrint('[FCM] failed to consume pending events: $e');
    return <Map<String, dynamic>>[];
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

    await _drainPendingEvents();

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] launched from terminated via notification');
      await _onMessageOpenedApp(initial);
    }

    debugPrint('[FCM] FcmService initialized');
  }

  Future<void> _drainPendingEvents() async {
    final pendingEvents = await _consumePendingFcmEvents();
    if (pendingEvents.isEmpty) return;

    for (final data in pendingEvents) {
      await _handleGifticonData(data, source: 'pending');
    }

    sharingService.storageService.emitItems();
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM][Foreground] ${message.messageId}');

    await _handleGifticonData(message.data, source: 'foreground');

    if (message.notification != null) {
      await _showLocalNotification(message);
    }
  }

  Future<void> _onMessageOpenedApp(RemoteMessage message) async {
    debugPrint('[FCM][OpenedApp] ${message.messageId}');
    await _handleGifticonData(message.data, source: 'opened_app');
  }

  Future<void> _handleGifticonData(
      Map<String, dynamic> data, {
        required String source,
      }) async {
    final type = data['type'] as String?;

    debugPrint('[FCM][$source] type=$type data=$data');

    if (type == 'gifticon_received') {
      await _handleGifticonReceived(data);
      return;
    }

    if (type == 'gifticon_used') {
      await _handleGifticonUsed(data);
      return;
    }

    debugPrint('[FCM][$source] unknown type: $type');
  }

  Future<void> _handleGifticonReceived(Map<String, dynamic> data) async {
    try {
      final gifticonId = data['gifticonId'] as String?;
      final imageUrl = data['imageUrl'] as String?;
      final ownerId = data['ownerId'] as String?;
      final ownerNickname = data['ownerNickname'] as String?;
      final expiresAtStr = data['expiresAt'] as String?;

      if (gifticonId == null ||
          imageUrl == null ||
          ownerId == null ||
          expiresAtStr == null) {
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
        ownerId: ownerId,
        ownerNickname: ownerNickname,
        merchantName: data['merchantName'] as String?,
        itemName: data['itemName'] as String?,
        couponNumber: data['couponNumber'] as String?,
        expiresAt: expiresAt,
      );

      debugPrint(
        '[FCM] gifticon_received handled locally: '
            'id=$gifticonId ownerNickname=$ownerNickname',
      );
    } catch (e) {
      debugPrint('[FCM] _handleGifticonReceived error: $e');
    }
  }

  Future<void> _handleGifticonUsed(Map<String, dynamic> data) async {
    try {
      final gifticonId = data['gifticonId'] as String?;
      final usedByNickname = data['usedByNickname'] as String?;
      if (gifticonId == null) {
        debugPrint('[FCM] gifticon_used: missing gifticonId');
        return;
      }

      await sharingService.storageService.markAsUsedIfExists(
        gifticonId,
        usedByNickname: usedByNickname,
      );

      debugPrint(
        '[FCM] gifticon_used handled locally: '
            'id=$gifticonId usedByNickname=$usedByNickname',
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