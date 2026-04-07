import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/app_logger.dart';

class ScreenshotAutoDetectSettingsPage extends StatefulWidget {
  const ScreenshotAutoDetectSettingsPage({
    super.key,
    required this.isEnabled,
    required this.onToggleChanged,
  });

  final bool isEnabled;
  final Future<void> Function(bool value) onToggleChanged;

  @override
  State<ScreenshotAutoDetectSettingsPage> createState() =>
      _ScreenshotAutoDetectSettingsPageState();
}

class _ScreenshotAutoDetectSettingsPageState
    extends State<ScreenshotAutoDetectSettingsPage> {
  late bool _isEnabled;
  bool _isExportingLogs = false;
  bool _isUpdating = false;

  static const Color _textPrimary = Color(0xFF1A1A1A);
  static const Color _textSecondary = Color(0xFF6B6B6B);
  static const Color _accent = Color(0xFF6155F5);

  @override
  void initState() {
    super.initState();
    _isEnabled = widget.isEnabled;
  }

  Future<void> _handleToggle(bool value) async {
    setState(() {
      _isEnabled = value;
      _isUpdating = true;
    });

    try {
      await widget.onToggleChanged(value);
    } finally {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
    }
  }

  Widget _buildGuideItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: _textSecondary,
          height: 1.6,
        ),
      ),
    );
  }

  Future<void> _handleExportLogs() async {
    if (_isExportingLogs) return;

    setState(() {
      _isExportingLogs = true;
    });

    try {
      await AppLogger.exportLogs();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그 파일을 내보냈어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그 내보내기에 실패했어요.\n$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isExportingLogs = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
          '스크린샷 자동 감지 설정',
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
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      '스크린샷 자동 감지',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                        height: 1.2,
                      ),
                    ),
                  ),
                  AbsorbPointer(
                    absorbing: _isUpdating,
                    child: Opacity(
                      opacity: _isUpdating ? 0.6 : 1,
                      child: CupertinoSwitch(
                        value: _isEnabled,
                        onChanged: _handleToggle,
                        activeTrackColor: _accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 72),
              const Text(
                '*스크린샷 자동 감지 모드 안내 사항',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 28),
              _buildGuideItem(
                '스크린샷 자동 감지를 켜면 기프티콘 이미지가 자동으로 인식될 수 있어요.',
              ),
              _buildGuideItem(
                '자동 감지 후 저장 전, 인식 결과를 확인하는 과정을 거칠 수 있어요.',
              ),
              _buildGuideItem(
                '일부 이미지에서는 인식이 정확하지 않을 수 있으니 직접 확인해주세요.',
              ),
              _buildGuideItem(
                '원하지 않을 경우 언제든지 이 설정에서 기능을 끌 수 있어요.',
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isExportingLogs ? null : _handleExportLogs,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: _accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isExportingLogs ? '로그 내보내는 중...' : '로그 내보내기',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}