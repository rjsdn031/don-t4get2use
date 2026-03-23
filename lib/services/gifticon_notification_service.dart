import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/stored_gifticon.dart';

class GifticonNotificationService {
  GifticonNotificationService(this._notifications);

  final FlutterLocalNotificationsPlugin _notifications;

  static const String _channelId = 'gifticon_pipeline';
  static const String _channelName = '기프티콘 저장 알림';
  static const String _channelDescription = '기프티콘 인식 및 저장 상태 알림';
  static const int _notificationId = 7001;

  Future<void> init() async {
    const androidInitSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(
      android: androidInitSettings,
    );

    await _notifications.initialize(settings: initSettings);

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> showProcessingNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.progress,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: _notificationId,
      title: '기프티콘 저장',
      body: '기프티콘을 인식하여 저장 중입니다.',
      notificationDetails: details,
    );
  }

  Future<void> showSavedNotificationFromStored(StoredGifticon stored) async {
    await _showSavedNotification(
      merchantName: stored.merchantName,
      itemName: stored.itemName,
    );
  }

  Future<void> cancelProcessingNotification() async {
    await _notifications.cancel(id: _notificationId);
  }

  Future<void> _showSavedNotification({
    required String? merchantName,
    required String? itemName,
  }) async {
    final body = _buildSavedBody(
      merchantName: merchantName,
      itemName: itemName,
    );

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: false,
      category: AndroidNotificationCategory.status,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: _notificationId,
      title: '기프티콘 저장 완료',
      body: body,
      notificationDetails: details,
    );
  }

  String _buildSavedBody({
    required String? merchantName,
    required String? itemName,
  }) {
    final merchant = merchantName?.trim();
    final item = itemName?.trim();

    final resolvedItem = (item == null || item.isEmpty) ? '기프티콘' : item;
    final hasMerchant = merchant != null && merchant.isNotEmpty;

    if (hasMerchant) {
      return '$merchant $resolvedItem(이)가 보관함에 저장되었습니다.';
    }

    return '$resolvedItem(이)가 보관함에 저장되었습니다.';
  }
}