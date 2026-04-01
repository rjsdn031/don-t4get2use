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
  static const Color _bg = Colors.white;
  static const Color _textPrimary = Color(0xFF1A1A1A);
  static const Color _textSecondary = Color(0xFF8E8E93);
  static const Color _fieldBg = Color(0xFFF6F6F6);
  static const Color _fieldBorder = Color(0xFFE5E5EA);
  static const Color _accent = Color(0xFF6155F5);

  static const Color _sharedBg = Color(0xFFFDD3D0);
  static const Color _sharedBorder = Color(0xFFEC221F);

  static const Color _receivedBg = Color(0xFFDBD8FF);
  static const Color _receivedBorder = Color(0xFF4034CD);

  static const Color _inactiveBg = Color(0xFFE3E3E3);
  static const Color _inactiveBorder = Color(0xFF767676);

  static const List<BoxShadow> _buttonShadows = [
    BoxShadow(
      color: Color(0x9CB9B5ED),
      offset: Offset(0, 6),
      blurRadius: 9.5,
    ),
    BoxShadow(
      color: Color(0x29000000),
      offset: Offset(0, -4),
      blurRadius: 21.7,
    ),
  ];

  late final ScrollController _scrollController;

  late StoredGifticon _item;
  bool _isMarkingUsed = false;

  @override
  void initState() {
    _scrollController = ScrollController();
    super.initState();
    _item = widget.item;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canEdit {
    return !_item.isShared &&
        !_item.isReceived &&
        !_item.isUsed;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y.$m.$d';
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '-';
    final y = (date.year % 100).toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$y.$m.$d $hh:$mm';
  }

  List<_DetailBadgeData> _badgeData() {
    final list = <_DetailBadgeData>[];

    if (_item.isReceived) {
      list.add(
        const _DetailBadgeData(
          text: '공유받음',
          bg: _receivedBg,
          border: _receivedBorder,
        ),
      );
    } else if (_item.isShared) {
      list.add(
        const _DetailBadgeData(
          text: '공유됨',
          bg: _sharedBg,
          border: _sharedBorder,
        ),
      );
    }

    if (_item.isUsed || _item.isExpired) {
      list.add(
        _DetailBadgeData(
          text: _item.isUsed ? '사용함' : '만료됨',
          bg: _inactiveBg,
          border: _inactiveBorder,
        ),
      );
    }

    return list;
  }

  Widget _buildSharedMessage() {
    final owner = (_item.ownerNickname ?? '').trim();
    final usedBy = (_item.usedByNickname ?? '').trim();
    final usedAt = _formatDateTime(_item.usedAt);

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A1A),
          height: 1.5,
        ),
        children: [
          TextSpan(text: '${owner.isEmpty ? '보낸 분' : owner}님의 쿠폰을 공유받은 '),
          TextSpan(
            text: usedBy.isEmpty ? '사용자' : usedBy,
            style: const TextStyle(color: Color(0xFF6155F5)),
          ),
          TextSpan(
            text: '님이\n$usedAt에 사용했어요!',
            style: const TextStyle(color: Color(0xFF6155F5)),
          ),
        ],
      ),
    );
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
      final myNickname = await widget.sharingService?.deviceIdService.getNickname();

      final updated = await widget.storageService.markAsUsed(
        _item.id,
        myNickname: myNickname,
      );
      await widget.notificationService.cancelExpiryNotifications(_item.id);

      if (widget.sharingService != null && (_item.isShared || _item.isReceived)) {
        await widget.sharingService!.markAsUsedRemote(
          gifticonId: _item.id,
        );
      }

      if (!mounted) return;

      setState(() {
        _item = updated;
      });

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
      if (mounted) {
        setState(() => _isMarkingUsed = false);
      }
    }
  }

  Future<void> _openEditPage() async {
    if (!_canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('상태 뱃지가 있는 기프티콘은 수정할 수 없어요.'),
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
          initialScrollOffset: _scrollController.hasClients
              ? _scrollController.offset
              : 0,
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
          await widget.notificationService.scheduleExpiryNotifications(updated);
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
            : '수정사항은 저장되었지만 만료 알림을 다시 등록하지 못했습니다.';
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
          content: Text('수정사항은 저장되었지만 만료 알림 등록에 실패했습니다.\n$e'),
        ),
      );
    }
  }

  Widget _buildBadgeSlot() {
    final badges = _badgeData();

    return SizedBox(
      height: 42,
      child: badges.isEmpty
          ? const SizedBox.shrink()
          : Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < badges.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _DetailStatusBadge(data: badges[i]),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildCustomAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(72),
      child: Container(
        color: Colors.white,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 22,
                        color: Color(0xFF1A1A1A),
                      ),
                      splashRadius: 20,
                    ),
                  ),
                  const Center(
                    child: Text(
                      '기프티콘 보기',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoField({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
                height: 1.2,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 48,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _fieldBorder),
              ),
              child: Text(
                value.isEmpty ? '-' : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: _textPrimary,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    if (_item.isInactive) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 60,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF6155F5),
          borderRadius: BorderRadius.circular(10),
          boxShadow: _buttonShadows,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _isMarkingUsed ? null : _markAsUsed,
            child: Center(
              child: _isMarkingUsed
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
                  : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    '사용했어요',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditButton() {
    return SizedBox(
      height: 60,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF4034CD),
            width: 1,
          ),
          boxShadow: _buttonShadows,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _openEditPage,
            child: const Center(
              child: Text(
                '정보 수정하기',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4034CD),
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInactive = _item.isInactive;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildCustomAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBadgeSlot(),
                    const SizedBox(height: 20),
                    if (_item.isShared && _item.isUsed) ...[
                      _buildSharedMessage(),
                      const SizedBox(height: 20),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: const Color(0xFFF3F3F3),
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
                            BlendMode.srcOver,
                          ),
                          child: Opacity(
                            opacity: isInactive ? 0.55 : 1,
                            child: Image.file(
                              File(_item.imagePath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                height: 320,
                                alignment: Alignment.center,
                                child: const Text(
                                  '이미지를 불러올 수 없습니다.',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildInfoField(
                      label: '교환처',
                      value: _item.merchantName ?? '-',
                    ),
                    _buildInfoField(
                      label: '상품명',
                      value: _item.itemName ?? '-',
                    ),
                    _buildInfoField(
                      label: '유효기간',
                      value: _formatDate(_item.expiresAt),
                    ),
                    _buildInfoField(
                      label: '쿠폰번호',
                      value: _item.couponNumber ?? '-',
                    ),
                    if (_canEdit) ...[
                      const SizedBox(height: 12),
                      _buildEditButton(),
                    ],
                  ],

                ),
              ),
            ),
            if (!_item.isInactive)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  8,
                  24,
                  16 + MediaQuery.of(context).viewPadding.bottom,
                ),
                child: _buildBottomButton(),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailBadgeData {
  final String text;
  final Color bg;
  final Color border;

  const _DetailBadgeData({
    required this.text,
    required this.bg,
    required this.border,
  });
}

class _DetailStatusBadge extends StatelessWidget {
  const _DetailStatusBadge({
    required this.data,
  });

  final _DetailBadgeData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: data.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: data.border, width: 1),
      ),
      child: Text(
        data.text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: data.border,
          height: 1.2,
        ),
      ),
    );
  }
}