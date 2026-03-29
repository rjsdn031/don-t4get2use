import 'dart:io';

import 'package:flutter/material.dart';

import '../models/stored_gifticon.dart';
import '../services/gifticon_notification_service.dart';
import '../services/gifticon_storage_service.dart';

class GifticonDetailPage extends StatefulWidget {
  final StoredGifticon item;
  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;

  const GifticonDetailPage({
    super.key,
    required this.item,
    required this.storageService,
    required this.notificationService,
  });

  @override
  State<GifticonDetailPage> createState() => _GifticonDetailPageState();
}

class _GifticonDetailPageState extends State<GifticonDetailPage> {
  late StoredGifticon _item;
  bool _isMarkingUsed = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (_item.isUsed) {
      return _StatusBadge(label: '사용함', color: Colors.grey);
    }
    if (_item.isExpired) {
      return _StatusBadge(label: '만료됨', color: Colors.red.shade300);
    }
    return const SizedBox.shrink();
  }

  Future<void> _markAsUsed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('사용 확인'),
        content: const Text('이 기프티콘을 사용했나요?\n한번 사용 처리하면 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('사용했어요'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isMarkingUsed = true);

    try {
      final updated = await widget.storageService.markAsUsed(_item.id);

      // 만료 알림도 취소
      await widget.notificationService.cancelExpiryNotifications(_item.id);

      if (!mounted) return;
      setState(() => _item = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용 처리되었습니다.')),
      );

      // 리스트 갱신을 위해 true 반환
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isMarkingUsed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInactive = _item.isInactive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('기프티콘 보기'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상태 배지
            if (isInactive) ...[
              _buildStatusBadge(),
              const SizedBox(height: 12),
            ],

            // 이미지 (비활성이면 grayscale + 반투명)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColorFiltered(
                colorFilter: isInactive
                    ? const ColorFilter.matrix([
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0,      0,      0,      1, 0,
                ])
                    : const ColorFilter.mode(
                  Colors.transparent,
                  BlendMode.color,
                ),
                child: Opacity(
                  opacity: isInactive ? 0.5 : 1.0,
                  child: Image.file(
                    File(_item.imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 240,
                      color: const Color(0xFFF2F2F2),
                      child: const Center(
                        child: Text('이미지를 불러올 수 없습니다.'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 정보 카드
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoTile('교환처', _item.merchantName ?? '-'),
                    _buildInfoTile('상품명', _item.itemName ?? '-'),
                    _buildInfoTile('유효기간', _formatDate(_item.expiresAt)),
                    _buildInfoTile('쿠폰번호', _item.couponNumber ?? '-'),
                    if (_item.isUsed)
                      _buildInfoTile('사용일', _formatDate(_item.usedAt)),
                  ],
                ),
              ),
            ),

            // 사용함 버튼 (활성 상태일 때만)
            if (!_item.isInactive) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isMarkingUsed ? null : _markAsUsed,
                icon: _isMarkingUsed
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_isMarkingUsed ? '처리 중...' : '사용했어요'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}