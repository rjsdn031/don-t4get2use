import 'dart:io';

import 'package:flutter/material.dart';

import '../models/stored_gifticon.dart';
import '../services/gifticon_notification_service.dart';
import '../services/gifticon_sharing_service.dart';
import '../services/gifticon_storage_service.dart';
import 'gifticon_edit_page.dart';

class GifticonDetailPage extends StatefulWidget {
  final StoredGifticon item;
  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;
  final GifticonSharingService? sharingService;

  const GifticonDetailPage({
    super.key,
    required this.item,
    required this.storageService,
    required this.notificationService,
    this.sharingService,
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

  String _displayOwner() {
    final owner = _item.ownerNickname ?? _item.receivedFrom;
    if (owner == null || owner.isEmpty) return '-';
    return '$owner님';
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

  List<Widget> _buildStatusBadges() {
    final badges = <Widget>[];

    if (_item.isUsed) {
      badges.add(_StatusBadge(label: '사용함', color: Colors.grey));
    } else if (_item.isExpired) {
      badges.add(_StatusBadge(label: '만료됨', color: Colors.red.shade300));
    }

    if (_item.isShared) {
      badges.add(_StatusBadge(label: '공유됨', color: Colors.blue.shade300));
    }

    if (_item.isReceived) {
      badges.add(_StatusBadge(label: '공유받음', color: Colors.purple.shade300));
    }

    return badges;
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
      final myNickname = await widget.sharingService
          ?.deviceIdService
          .getNickname();

      final updated = await widget.storageService.markAsUsed(
        _item.id,
        myNickname: myNickname,
      );
      await widget.notificationService.cancelExpiryNotifications(_item.id);

      if (widget.sharingService != null &&
          (_item.isShared || _item.isReceived)) {
        await widget.sharingService!.markAsUsedRemote(
          gifticonId: _item.id,
        );
      }

      if (!mounted) return;
      setState(() => _item = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용 처리되었습니다.')),
      );

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

  bool get _canEdit {
    return !_item.isShared && !_item.isReceived;
  }

  Future<void> _openEditPage() async {
    if (_item.isShared || _item.isReceived) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('공유된 기프티콘은 수정할 수 없어요.'),
        ),
      );
      return;
    }

    final previousItem = _item;

    final updated = await Navigator.push<StoredGifticon>(
      context,
      MaterialPageRoute(
        builder: (_) => GifticonEditPage(
          item: _item,
          storageService: widget.storageService,
        ),
      ),
    );

    if (!mounted || updated == null) return;

    final changedExpiry =
        _formatDate(previousItem.expiresAt) != _formatDate(updated.expiresAt);

    try {
      bool scheduled = true;

      if (changedExpiry) {
        await widget.notificationService.cancelExpiryNotifications(updated.id);

        if (!updated.isUsed) {
          scheduled =
          await widget.notificationService.scheduleExpiryNotifications(
            updated,
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _item = updated;
      });

      String message = '수정사항이 저장되었습니다.';

      if (changedExpiry && !updated.isUsed) {
        message = scheduled
            ? '수정사항이 저장되고 만료 알림이 다시 예약되었습니다.'
            : '수정사항은 저장되었지만 만료 알림을 다시 등록하지 못했습니다. 알림 권한 또는 기기 설정을 확인해 주세요.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _item = updated;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '수정사항은 저장되었지만 만료 알림을 다시 등록하지 못했습니다.\n$e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInactive = _item.isInactive;
    final statusBadges = _buildStatusBadges();

    return Scaffold(
      appBar: AppBar(
        title: const Text('기프티콘 보기'),
        actions: [
          if (_canEdit)
            IconButton(
              tooltip: '수정',
              onPressed: _openEditPage,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (statusBadges.isNotEmpty) ...[
                Wrap(spacing: 8, children: statusBadges),
                const SizedBox(height: 12),
              ],
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
                        child: const Center(child: Text('이미지를 불러올 수 없습니다.')),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfoTile('교환처', _item.merchantName ?? '-'),
                      _buildInfoTile('상품명', _item.itemName ?? '-'),
                      _buildInfoTile('유효기간', _formatDate(_item.expiresAt)),
                      _buildInfoTile('쿠폰번호', _item.couponNumber ?? '-'),
                      if (_item.isUsed) ...[
                        _buildInfoTile('사용일', _formatDate(_item.usedAt)),
                        if ((_item.usedByNickname ?? '').isNotEmpty)
                          _buildInfoTile('사용한 분', '${_item.usedByNickname}님'),
                      ],
                      if (_item.isShared)
                        _buildInfoTile('공유일', _formatDate(_item.sharedAt)),
                      if (_item.isReceived)
                        _buildInfoTile('공유한 분', _displayOwner()),
                    ],
                  ),
                ),
              ),
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
    return Container(
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
    );
  }
}