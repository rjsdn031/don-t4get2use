import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/stored_gifticon.dart';
import 'exact_alarm_permission_service.dart';
import 'now_provider.dart';

class GifticonNotificationService {
  GifticonNotificationService(
      this._notifications, {
        ExactAlarmPermissionService? exactAlarmPermissionService,
        NowProvider? nowProvider,
      })  : _exactAlarmPermissionService =
      exactAlarmPermissionService ?? ExactAlarmPermissionService(),
        _nowProvider = nowProvider ?? SystemNowProvider();

  final FlutterLocalNotificationsPlugin _notifications;
  final ExactAlarmPermissionService _exactAlarmPermissionService;
  final NowProvider _nowProvider;

  static const String _pipelineChannelId = 'gifticon_pipeline';
  static const String _pipelineChannelName = '기프티콘 저장 알림';
  static const String _pipelineChannelDescription = '기프티콘 인식 및 저장 상태 알림';

  static const String _savedChannelId = 'gifticon_saved_v1';
  static const String _savedChannelName = '기프티콘 저장 완료 알림';
  static const String _savedChannelDescription = '기프티콘 저장 완료 알림';

  static const String _expiryChannelId = 'gifticon_expiry_v2';
  static const String _expiryChannelName = '기프티콘 만료 알림';
  static const String _expiryChannelDescription = '기프티콘 만료 전 사용 알림';

  static const int _processingNotificationId = 7001;
  static const int _savedNotificationId = 7002;
  static const int _sharedNotificationId = 7003;
  static const int _debugNowNotificationId = 999000;
  static const int _debugScheduledNotificationId = 999001;

  static const int _expiryThreeDaysSalt = 3000;
  static const int _expiryOneDaySalt = 1000;

  Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidInitSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidInitSettings);

    await _notifications.initialize(settings: initSettings);

    const pipelineChannel = AndroidNotificationChannel(
      _pipelineChannelId,
      _pipelineChannelName,
      description: _pipelineChannelDescription,
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    const savedChannel = AndroidNotificationChannel(
      _savedChannelId,
      _savedChannelName,
      description: _savedChannelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const expiryChannel = AndroidNotificationChannel(
      _expiryChannelId,
      _expiryChannelName,
      description: _expiryChannelDescription,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.createNotificationChannel(pipelineChannel);
    await android?.createNotificationChannel(savedChannel);
    await android?.createNotificationChannel(expiryChannel);
  }

  Future<bool> canScheduleExactAlarms() {
    return _exactAlarmPermissionService.canScheduleExactAlarms();
  }

  Future<bool> openExactAlarmSettings() {
    return _exactAlarmPermissionService.openExactAlarmSettings();
  }

  Future<bool> requestNotificationPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<bool> hasNotificationPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final granted = await android?.areNotificationsEnabled();
    return granted ?? false;
  }

  Future<void> showProcessingNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _pipelineChannelId,
      _pipelineChannelName,
      channelDescription: _pipelineChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      category: AndroidNotificationCategory.progress,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: _processingNotificationId,
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

  Future<void> showSharedNotificationFromStored(StoredGifticon stored) async {
    final body = _buildSharedBody(
      merchantName: stored.merchantName,
      itemName: stored.itemName,
    );

    const androidDetails = AndroidNotificationDetails(
      _expiryChannelId,
      _expiryChannelName,
      channelDescription: _expiryChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.status,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: _sharedNotificationId,
      title: '기프티콘 공유 완료',
      body: body,
      notificationDetails: details,
      payload: stored.id,
    );
  }

  Future<void> cancelProcessingNotification() async {
    await _notifications.cancel(id: _processingNotificationId);
  }

  Future<bool> scheduleExpiryNotifications(StoredGifticon stored) async {
    final expiresAt = stored.expiresAt;
    if (expiresAt == null) return false;

    final canSchedule = await canScheduleExactAlarms();
    if (!canSchedule) {
      debugPrint(
        '[Gifticon][Notification] skip schedule: exact alarm unavailable or denied (${stored.id})',
      );
      return false;
    }

    await cancelExpiryNotifications(stored.id);

    await _scheduleExpiryNotification(
      id: _threeDaysBeforeNotificationId(stored.id),
      scheduledAt: _at8am(expiresAt.subtract(const Duration(days: 3))),
      title: '기프티콘 만료 3일 전',
      body: _buildExpiryBody(
        merchantName: stored.merchantName,
        itemName: stored.itemName,
        suffix: '3일 남았어요. 사용을 잊지 마세요.',
      ),
      payload: stored.id,
    );

    await _scheduleExpiryNotification(
      id: _oneDayBeforeNotificationId(stored.id),
      scheduledAt: _at8am(expiresAt.subtract(const Duration(days: 1))),
      title: '기프티콘 만료 하루 전',
      body: _buildExpiryBody(
        merchantName: stored.merchantName,
        itemName: stored.itemName,
        suffix: '내일 아침 공유될 예정이에요. 오늘 꼭 사용해 보세요.',
      ),
      payload: stored.id,
    );

    return true;
  }

  Future<void> showDebugNowNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _expiryChannelId,
      _expiryChannelName,
      channelDescription: _expiryChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: _debugNowNotificationId,
      title: '기프티콘 알림 즉시 테스트',
      body: '이 알림이 보이면 표시 권한과 채널은 정상입니다.',
      notificationDetails: details,
      payload: 'debug_now',
    );
  }

  Future<void> cancelExpiryNotifications(String gifticonId) async {
    await _notifications.cancel(id: _threeDaysBeforeNotificationId(gifticonId));
    await _notifications.cancel(id: _oneDayBeforeNotificationId(gifticonId));
  }

  Future<void> rescheduleAllExpiryNotifications(
      List<StoredGifticon> gifticons,
      ) async {
    final canSchedule = await canScheduleExactAlarms();
    if (!canSchedule) {
      debugPrint(
        '[Gifticon][Notification] skip reschedule: exact alarm unavailable or denied',
      );
      return;
    }

    for (final stored in gifticons) {
      await scheduleExpiryNotifications(stored);
    }
  }

  Future<bool> scheduleDebugTestNotification({
    Duration delay = const Duration(seconds: 10),
  }) async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final notificationsEnabled = await android?.areNotificationsEnabled();
    final exactAllowed = await android?.canScheduleExactNotifications();

    debugPrint(
      '[Gifticon][Notification] notificationsEnabled=$notificationsEnabled, exactAllowed=$exactAllowed',
    );

    if (notificationsEnabled != true) {
      debugPrint(
        '[Gifticon][Notification] skip debug test schedule: notification permission/channel unavailable',
      );
      return false;
    }

    if (exactAllowed != true) {
      debugPrint(
        '[Gifticon][Notification] skip debug test schedule: exact alarm unavailable',
      );
      return false;
    }

    final scheduledAt = _nowProvider.now().add(delay);

    const androidDetails = AndroidNotificationDetails(
      _expiryChannelId,
      _expiryChannelName,
      channelDescription: _expiryChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.zonedSchedule(
      id: _debugScheduledNotificationId,
      title: '기프티콘 만료 알림 테스트',
      body: '10초 뒤 테스트 알림이 정상적으로 도착했어요.',
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'debug_test',
    );

    final pending = await _notifications.pendingNotificationRequests();
    debugPrint(
      '[Gifticon][Notification] debug test scheduled at $scheduledAt, pendingIds=${pending.map((e) => e.id).toList()}',
    );

    return true;
  }

  Future<void> cancelDebugTestNotification() async {
    await _notifications.cancel(id: _debugScheduledNotificationId);
  }

  Future<void> _scheduleExpiryNotification({
    required int id,
    required DateTime scheduledAt,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!scheduledAt.isAfter(_nowProvider.now())) return;

    const androidDetails = AndroidNotificationDetails(
      _expiryChannelId,
      _expiryChannelName,
      channelDescription: _expiryChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
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
      _savedChannelId,
      _savedChannelName,
      channelDescription: _savedChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.status,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: _savedNotificationId,
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

  String _buildSharedBody({
    required String? merchantName,
    required String? itemName,
  }) {
    final merchant = merchantName?.trim();
    final item = itemName?.trim();

    final parts = <String>[
      if (merchant != null && merchant.isNotEmpty) merchant,
      if (item != null && item.isNotEmpty) item,
    ];

    if (parts.isEmpty) {
      return '기프티콘이 공유되었어요.';
    }

    return '${parts.join(' ')}이 공유되었어요.';
  }

  String _buildExpiryBody({
    required String? merchantName,
    required String? itemName,
    required String suffix,
  }) {
    final merchant = merchantName?.trim();
    final item = itemName?.trim();

    final parts = <String>[
      if (merchant != null && merchant.isNotEmpty) merchant,
      if (item != null && item.isNotEmpty) item,
    ];

    if (parts.isEmpty) {
      return '저장한 기프티콘이 $suffix';
    }

    return '${parts.join(' ')}이 $suffix';
  }

  DateTime _at8am(DateTime date) {
    return DateTime(date.year, date.month, date.day, 8, 0, 0);
  }

  int _threeDaysBeforeNotificationId(String gifticonId) {
    return (gifticonId.hashCode & 0x7fffffff) + _expiryThreeDaysSalt;
  }

  int _oneDayBeforeNotificationId(String gifticonId) {
    return (gifticonId.hashCode & 0x7fffffff) + _expiryOneDaySalt;
  }
}