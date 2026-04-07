import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/stored_gifticon.dart';
import 'app_logger.dart';
import 'exact_alarm_permission_service.dart';
import 'now_provider.dart';

class GifticonNotificationService {
  GifticonNotificationService(
      this._notifications, {
        ExactAlarmPermissionService? exactAlarmPermissionService,
        NowProvider? nowProvider,
        void Function()? onGifticonSaved,
      })  : _exactAlarmPermissionService =
      exactAlarmPermissionService ?? ExactAlarmPermissionService(),
        _nowProvider = nowProvider ?? SystemNowProvider(),
        _onGifticonSaved = onGifticonSaved;

  final FlutterLocalNotificationsPlugin _notifications;
  final ExactAlarmPermissionService _exactAlarmPermissionService;
  final NowProvider _nowProvider;

  final void Function()? _onGifticonSaved;

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
    final initSettings = InitializationSettings(android: androidInitSettings);

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

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

    await AppLogger.log(
      tag: 'Notification',
      event: 'initialized',
      data: {
        'timezone': 'Asia/Seoul',
      },
    );
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

    await AppLogger.log(
      tag: 'Notification',
      event: 'request_permission',
      data: {
        'granted': granted ?? false,
      },
    );

    return granted ?? false;
  }

  Future<bool> hasNotificationPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final granted = await android?.areNotificationsEnabled();

    await AppLogger.log(
      tag: 'Notification',
      event: 'check_permission',
      data: {
        'granted': granted ?? false,
      },
    );

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

    await AppLogger.log(
      tag: 'Notification',
      event: 'show_processing',
      data: {
        'id': _processingNotificationId,
      },
    );
  }

  Future<void> showSavedNotificationFromStored(StoredGifticon stored) async {
    await _showSavedNotification(
      merchantName: stored.merchantName,
      itemName: stored.itemName,
    );

    await AppLogger.log(
      tag: 'Notification',
      event: 'show_saved',
      data: {
        'gifticonId': stored.id,
        'merchantName': stored.merchantName,
        'itemName': stored.itemName,
      },
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

    await AppLogger.log(
      tag: 'Notification',
      event: 'show_shared',
      data: {
        'gifticonId': stored.id,
        'merchantName': stored.merchantName,
        'itemName': stored.itemName,
      },
    );
  }

  Future<void> cancelProcessingNotification() async {
    await _notifications.cancel(id: _processingNotificationId);

    await AppLogger.log(
      tag: 'Notification',
      event: 'cancel_processing',
      data: {
        'id': _processingNotificationId,
      },
    );
  }

  Future<bool> scheduleExpiryNotifications(StoredGifticon stored) async {
    final expiresAt = stored.expiresAt;
    if (expiresAt == null) {
      await AppLogger.log(
        tag: 'Notification',
        event: 'schedule_expiry_skip_no_expiry',
        data: {
          'gifticonId': stored.id,
        },
      );
      return false;
    }

    final canSchedule = await canScheduleExactAlarms();
    if (!canSchedule) {
      await AppLogger.log(
        tag: 'Notification',
        event: 'schedule_expiry_skip_exact_alarm_unavailable',
        data: {
          'gifticonId': stored.id,
        },
      );
      return false;
    }

    await cancelExpiryNotifications(stored.id);

    final threeDaysAt = _at8am(expiresAt.subtract(const Duration(days: 3)));
    final oneDayAt = _at8am(expiresAt.subtract(const Duration(days: 1)));

    await _scheduleExpiryNotification(
      id: _threeDaysBeforeNotificationId(stored.id),
      scheduledAt: threeDaysAt,
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
      scheduledAt: oneDayAt,
      title: '기프티콘 만료 하루 전',
      body: _buildExpiryBody(
        merchantName: stored.merchantName,
        itemName: stored.itemName,
        suffix: '내일 아침 공유될 예정이에요. 오늘 꼭 사용해 보세요.',
      ),
      payload: stored.id,
    );

    await AppLogger.log(
      tag: 'Notification',
      event: 'schedule_expiry_done',
      data: {
        'gifticonId': stored.id,
        'expiresAt': expiresAt.toIso8601String(),
        'threeDaysAt': threeDaysAt.toIso8601String(),
        'oneDayAt': oneDayAt.toIso8601String(),
      },
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

    await AppLogger.log(
      tag: 'Notification',
      event: 'show_debug_now',
      data: {
        'id': _debugNowNotificationId,
      },
    );
  }

  Future<void> cancelExpiryNotifications(String gifticonId) async {
    await _notifications.cancel(id: _threeDaysBeforeNotificationId(gifticonId));
    await _notifications.cancel(id: _oneDayBeforeNotificationId(gifticonId));

    await AppLogger.log(
      tag: 'Notification',
      event: 'cancel_expiry',
      data: {
        'gifticonId': gifticonId,
      },
    );
  }

  Future<void> rescheduleAllExpiryNotifications(
      List<StoredGifticon> gifticons,
      ) async {
    final canSchedule = await canScheduleExactAlarms();
    if (!canSchedule) {
      await AppLogger.log(
        tag: 'Notification',
        event: 'reschedule_all_skip_exact_alarm_unavailable',
      );
      return;
    }

    await AppLogger.log(
      tag: 'Notification',
      event: 'reschedule_all_start',
      data: {
        'count': gifticons.length,
      },
    );

    for (final stored in gifticons) {
      await scheduleExpiryNotifications(stored);
    }

    await AppLogger.log(
      tag: 'Notification',
      event: 'reschedule_all_done',
      data: {
        'count': gifticons.length,
      },
    );
  }

  Future<bool> scheduleDebugTestNotification({
    Duration delay = const Duration(seconds: 10),
  }) async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final notificationsEnabled = await android?.areNotificationsEnabled();
    final exactAllowed = await android?.canScheduleExactNotifications();

    await AppLogger.log(
      tag: 'Notification',
      event: 'debug_test_check',
      data: {
        'notificationsEnabled': notificationsEnabled,
        'exactAllowed': exactAllowed,
      },
    );

    if (notificationsEnabled != true) {
      await AppLogger.log(
        tag: 'Notification',
        event: 'debug_test_skip_permission',
      );
      return false;
    }

    if (exactAllowed != true) {
      await AppLogger.log(
        tag: 'Notification',
        event: 'debug_test_skip_exact_alarm',
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

    await AppLogger.log(
      tag: 'Notification',
      event: 'debug_test_scheduled',
      data: {
        'scheduledAt': scheduledAt.toIso8601String(),
        'pendingIds': pending.map((e) => e.id).toList(),
      },
    );

    return true;
  }

  Future<void> cancelDebugTestNotification() async {
    await _notifications.cancel(id: _debugScheduledNotificationId);

    await AppLogger.log(
      tag: 'Notification',
      event: 'cancel_debug_test',
      data: {
        'id': _debugScheduledNotificationId,
      },
    );
  }

  Future<void> _scheduleExpiryNotification({
    required int id,
    required DateTime scheduledAt,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!scheduledAt.isAfter(_nowProvider.now())) {
      await AppLogger.log(
        tag: 'Notification',
        event: 'schedule_expiry_item_skip_past',
        data: {
          'id': id,
          'scheduledAt': scheduledAt.toIso8601String(),
          'payload': payload,
          'title': title,
        },
      );
      return;
    }

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

    await AppLogger.log(
      tag: 'Notification',
      event: 'schedule_expiry_item_done',
      data: {
        'id': id,
        'scheduledAt': scheduledAt.toIso8601String(),
        'payload': payload,
        'title': title,
      },
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

  void _onNotificationResponse(NotificationResponse response) {
    AppLogger.log(
      tag: 'Notification',
      event: 'response',
      data: {
        'id': response.id,
        'payload': response.payload,
      },
    );

    if (response.id == _savedNotificationId ||
        response.id == _sharedNotificationId) {
      _onGifticonSaved?.call();
    }
  }
}

@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  AppLogger.log(
    tag: 'Notification',
    event: 'background_response',
    data: {
      'id': response.id,
      'payload': response.payload,
    },
  );
}