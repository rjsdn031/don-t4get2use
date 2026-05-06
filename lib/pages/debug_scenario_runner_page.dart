import 'package:flutter/material.dart';

import '../services/gifticon_notification_service.dart';
import '../services/auto_share_settings_service.dart';
import '../services/app_logger.dart';

class NotificationTestPage extends StatefulWidget {
  const NotificationTestPage({
    super.key,
    required this.notificationService,
  });

  final GifticonNotificationService notificationService;

  @override
  State<NotificationTestPage> createState() => _NotificationTestPageState();
}

class _NotificationTestPageState extends State<NotificationTestPage> {
  bool _isAutoShareEnabled = false;
  bool _isLoading = true;

  static const Color _textPrimary = Color(0xFF1A1A1A);
  static const Color _textSecondary = Color(0xFF6B6B6B);
  static const Color _accent = Color(0xFF6155F5);
  static const Color _success = Color(0xFF10B981);
  static const Color _warning = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _loadAutoShareSettings();
  }

  Future<void> _loadAutoShareSettings() async {
    final service = AutoShareSettingsService();
    final enabled = await service.isAutoShareEnabled();

    setState(() {
      _isAutoShareEnabled = enabled;
      _isLoading = false;
    });
  }

  Future<void> _showThreeDaysBeforeNotification() async {
    await AppLogger.log(
      tag: 'NotificationTest',
      event: 'show_three_days_before',
      data: {
        'isAutoShareEnabled': _isAutoShareEnabled,
      },
    );

    await widget.notificationService.showTestExpiryNotification(
      daysRemaining: 3,
      merchantName: '스타벅스',
      itemName: '아메리카노 Tall',
      isAutoShareEnabled: _isAutoShareEnabled,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('3일 전 알림을 표시했어요'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showOneDayBeforeNotification() async {
    await AppLogger.log(
      tag: 'NotificationTest',
      event: 'show_one_day_before',
      data: {
        'isAutoShareEnabled': _isAutoShareEnabled,
      },
    );

    await widget.notificationService.showTestExpiryNotification(
      daysRemaining: 1,
      merchantName: '스타벅스',
      itemName: '아메리카노 Tall',
      isAutoShareEnabled: _isAutoShareEnabled,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('1일 전 알림을 표시했어요'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleAutoShare() async {
    final newValue = !_isAutoShareEnabled;

    setState(() {
      _isAutoShareEnabled = newValue;
    });

    final service = AutoShareSettingsService();
    await service.setAutoShareEnabled(newValue);

    await AppLogger.log(
      tag: 'NotificationTest',
      event: 'toggle_auto_share',
      data: {
        'newValue': newValue,
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newValue ? '자동 공유가 켜졌어요' : '자동 공유가 꺼졌어요',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTestCard({
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTest,
    required String expectedMessage,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: color.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        size: 16,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          expectedMessage,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: color,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: color.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  child: Text(
                    '알림 테스트',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_accent),
          ),
        ),
      );
    }

    final oneDayMessage = _isAutoShareEnabled
        ? '내일 아침 공유될 예정이에요. 오늘 꼭 사용해 보세요.'
        : '내일 만료됩니다. 오늘 꼭 사용해 보세요.';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 44,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: _textPrimary,
            size: 22,
          ),
        ),
        titleSpacing: 0,
        title: const Text(
          '알림 테스트',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            height: 1.2,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // 자동 공유 설정 토글
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.share_outlined,
                        color: _accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '자동 공유 시뮬레이션',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isAutoShareEnabled ? '켜짐' : '꺼짐',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _isAutoShareEnabled ? _success : _textSecondary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isAutoShareEnabled,
                      onChanged: (_) => _toggleAutoShare(),
                      activeColor: _accent,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                '만료 알림 테스트',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                  height: 1.2,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 16),

              _buildTestCard(
                title: '3일 전 알림',
                description: '만료 3일 전에 표시되는 알림입니다. 자동 공유 설정과 관계없이 동일한 메시지가 표시됩니다.',
                color: _warning,
                onTest: _showThreeDaysBeforeNotification,
                expectedMessage: '3일 남았어요. 사용을 잊지 마세요.',
              ),

              _buildTestCard(
                title: '1일 전 알림',
                description: '만료 1일 전에 표시되는 알림입니다. 자동 공유 설정에 따라 메시지가 달라집니다.',
                color: _isAutoShareEnabled ? _success : Colors.red,
                onTest: _showOneDayBeforeNotification,
                expectedMessage: oneDayMessage,
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _accent.withOpacity(0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: _accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '위 토글을 변경하면 1일 전 알림 메시지가 즉시 바뀝니다. 각 버튼을 눌러 실제 알림을 확인해보세요.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _accent,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}