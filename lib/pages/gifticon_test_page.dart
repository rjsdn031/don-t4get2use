import 'package:flutter/material.dart';

import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../services/gifticon_notification_service.dart';
import '../services/gifticon_services.dart';

class GifticonTestPage extends StatefulWidget {
  const GifticonTestPage({super.key});

  @override
  State<GifticonTestPage> createState() => _GifticonTestPageState();
}

class _GifticonTestPageState extends State<GifticonTestPage>
    with WidgetsBindingObserver {
  GifticonServices? _services;
  GifticonNotificationService? _notificationService;

  bool _isInitializing = true;
  bool _isBusy = false;
  bool _canScheduleExactAlarms = false;
  bool _hasNotificationPermission = false;
  String _status = '초기화 중...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
    }
  }

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final status = await Permission.notification.status;
    if (status.isGranted) return;

    await Permission.notification.request();
  }

  Future<void> _init() async {
    await _ensureNotificationPermission();

    final services = await GifticonServices.create();

    if (!mounted) return;

    setState(() {
      _services = services;
      _notificationService = services.notificationService;
      _isInitializing = false;
      _status = '준비 완료';
    });

    await _refreshPermissionStatus();
  }

  Future<void> _refreshPermissionStatus() async {
    final notificationService = _notificationService;
    if (notificationService == null) return;

    final canSchedule = await notificationService.canScheduleExactAlarms();
    final hasNotificationPermission = await notificationService
        .hasNotificationPermission();

    if (!mounted) return;

    setState(() {
      _canScheduleExactAlarms = canSchedule;
      _hasNotificationPermission = hasNotificationPermission;

      if (!_hasNotificationPermission) {
        _status = '알림 권한이 필요합니다.';
      } else if (!_canScheduleExactAlarms) {
        _status = '정확 알람 권한이 필요합니다.';
      } else {
        _status = '알림 테스트 준비 완료';
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    final notificationService = _notificationService;
    if (notificationService == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '알림 권한 요청 중...';
    });

    final granted = await notificationService.requestNotificationPermission();

    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _hasNotificationPermission = granted;
      _status = granted ? '알림 권한이 허용되었습니다.' : '알림 권한이 허용되지 않았습니다.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted ? '알림 권한이 허용되었습니다.' : '알림 권한이 없어 노티가 보이지 않을 수 있어요.',
        ),
      ),
    );
  }

  Future<void> _openExactAlarmSettings() async {
    final notificationService = _notificationService;
    if (notificationService == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '정확 알람 설정 화면 여는 중...';
    });

    await notificationService.openExactAlarmSettings();

    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _status = '설정 화면을 열었습니다. 권한 허용 후 다시 돌아와 주세요.';
    });
  }

  Future<void> _schedule10SecTest() async {
    final notificationService = _notificationService;
    if (notificationService == null || _isBusy) return;

    if (!_hasNotificationPermission) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 알림 권한을 허용해 주세요.')));
      return;
    }

    if (!_canScheduleExactAlarms) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 정확 알람 권한을 허용해 주세요.')));
      return;
    }

    setState(() {
      _isBusy = true;
      _status = '10초 뒤 테스트 알림 예약 중...';
    });

    final scheduled = await notificationService.scheduleDebugTestNotification(
      delay: const Duration(seconds: 10),
    );

    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _status = scheduled ? '10초 뒤 테스트 알림을 예약했습니다.' : '테스트 알림 예약에 실패했습니다.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          scheduled ? '10초 뒤 테스트 알림이 울릴 예정입니다.' : '테스트 알림 예약에 실패했습니다.',
        ),
      ),
    );
  }

  Future<void> _cancel10SecTest() async {
    final notificationService = _notificationService;
    if (notificationService == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '테스트 알림 취소 중...';
    });

    await notificationService.cancelDebugTestNotification();

    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _status = '테스트 알림을 취소했습니다.';
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('테스트 알림을 취소했습니다.')));
  }

  Future<void> _rescheduleAllStoredGifticons() async {
    final services = _services;
    final notificationService = _notificationService;
    if (services == null || notificationService == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '저장된 기프티콘 전체 재예약 중...';
    });

    await notificationService.rescheduleAllExpiryNotifications(
      services.storageService.getAllGifticons(),
    );

    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _status = '저장된 기프티콘 전체 재예약을 시도했습니다.';
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('저장된 기프티콘 전체 재예약을 시도했습니다.')));
  }

  Future<void> _showNowTest() async {
    final notificationService = _notificationService;
    if (notificationService == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '즉시 알림 테스트 중...';
    });

    await notificationService.showDebugNowNotification();

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _status = '즉시 알림 테스트를 실행했습니다.';
    });
  }

  Widget _buildPermissionRow({required String label, required bool granted}) {
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle : Icons.error_outline,
          size: 18,
          color: granted ? Colors.green : Colors.orange,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('$label: ${granted ? '허용됨' : '허용되지 않음'}')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림 테스트')),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '권한 상태',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildPermissionRow(
                              label: '알림 권한',
                              granted: _hasNotificationPermission,
                            ),
                            const SizedBox(height: 8),
                            _buildPermissionRow(
                              label: '정확 알람 권한',
                              granted: _canScheduleExactAlarms,
                            ),
                            const SizedBox(height: 12),
                            Text(_status),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isBusy
                          ? null
                          : _requestNotificationPermission,
                      child: const Text('알림 권한 허용하기'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isBusy ? null : _openExactAlarmSettings,
                      child: const Text('정확 알람 권한 허용하러 가기'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isBusy ? null : _refreshPermissionStatus,
                      child: const Text('권한 상태 새로고침'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isBusy ? null : _showNowTest,
                      child: const Text('즉시 알림 테스트'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isBusy ? null : _schedule10SecTest,
                      child: const Text('10초 뒤 테스트 알림 예약'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _isBusy ? null : _cancel10SecTest,
                      child: const Text('테스트 알림 취소'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isBusy ? null : _rescheduleAllStoredGifticons,
                      child: const Text('저장된 기프티콘 전체 재예약'),
                    ),
                    const SizedBox(height: 24),
                    if (_isBusy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
    );
  }
}
