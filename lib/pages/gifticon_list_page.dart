import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/stored_gifticon.dart';
import '../modules/screenshot_event_listener_module.dart';
import '../services/gifticon_services.dart';
import '../services/gifticon_storage_service.dart';
import '../services/screenshot_automation_service.dart';
import 'gifticon_detail_page.dart';

class GifticonListPage extends StatefulWidget {
  const GifticonListPage({super.key});

  @override
  State<GifticonListPage> createState() => _GifticonListPageState();
}

class _GifticonListPageState extends State<GifticonListPage> {
  late final GifticonServices _services;
  late final GifticonStorageService _storageService;
  late final ScreenshotAutomationService _automationService;
  late final ScreenshotEventListenerModule _screenshotEventListener;

  StreamSubscription<dynamic>? _screenshotSubscription;

  bool _loading = true;
  bool _isListeningEnabled = true;
  bool _isListeningActive = false;
  bool _isAutoSaving = false;

  List<StoredGifticon> _items = const [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _screenshotSubscription?.cancel();
    super.dispose();
  }

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final status = await Permission.notification.status;
    if (status.isGranted) return;

    await Permission.notification.request();
  }

  Future<void> _initialize() async {
    try {
      await _ensureNotificationPermission();

      _services = await GifticonServices.create();
      _storageService = _services.storageService;
      _automationService = _services.automationService;
      _screenshotEventListener = ScreenshotEventListenerModule();

      await _loadItems();

      if (_isListeningEnabled) {
        await _startListeningScreenshotEvents();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초기화 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Future<bool> _ensureMediaPermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.photos.isGranted) return true;
    if (await Permission.storage.isGranted) return true;

    final photosStatus = await Permission.photos.request();
    if (photosStatus.isGranted) return true;

    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  Future<void> _startListeningScreenshotEvents() async {
    if (_isListeningActive) return;

    final granted = await _ensureMediaPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지 접근 권한이 필요합니다.')),
      );
      return;
    }

    _screenshotSubscription = _screenshotEventListener.events.listen(
          (event) async {
        if (!_isListeningEnabled || _isAutoSaving) return;

        _isAutoSaving = true;

        try {
          await Future<void>.delayed(const Duration(milliseconds: 500));

          final output = await _automationService.handleScreenshotDetected();
          if (output == null) return;
          if (!output.isSaved) return;

          await _loadItems();

          if (!mounted) return;

          final saved = output.storedGifticon;
          final itemName = saved?.itemName?.trim();
          final resolvedName =
          (itemName == null || itemName.isEmpty) ? '기프티콘' : itemName;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$resolvedName 저장 완료')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('자동 저장 중 오류가 발생했습니다: $e')),
          );
        } finally {
          _isAutoSaving = false;
        }
      },
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('스크린샷 이벤트 수신 오류: $error')),
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _isListeningActive = true;
    });
  }

  Future<void> _stopListeningScreenshotEvents() async {
    await _screenshotSubscription?.cancel();
    _screenshotSubscription = null;

    if (!mounted) return;
    setState(() {
      _isListeningActive = false;
    });
  }

  Future<void> _toggleListening(bool value) async {
    if (value) {
      if (!mounted) return;
      setState(() {
        _isListeningEnabled = true;
      });
      await _startListeningScreenshotEvents();
      return;
    }

    await _stopListeningScreenshotEvents();

    if (!mounted) return;
    setState(() {
      _isListeningEnabled = false;
    });
  }

  Future<void> _loadItems() async {
    final items = _storageService.getAllGifticons();

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _deleteItem(StoredGifticon item) async {
    await _storageService.deleteGifticon(item.id);
    await _loadItems();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기프티콘을 삭제했습니다.')),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _confirmDelete(StoredGifticon item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('이 기프티콘을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteItem(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('저장된 기프티콘'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
        child: Text('저장된 기프티콘이 없습니다.'),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];

          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Image.file(
                    File(item.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xFFF2F2F2),
                      child: Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
              title: Text(item.itemName ?? '상품명 없음'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(item.merchantName ?? '교환처 없음'),
                  const SizedBox(height: 2),
                  Text('유효기간: ${_formatDate(item.expiresAt)}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(item),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GifticonDetailPage(item: item),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isListeningActive
                      ? '스크린샷 자동 감지 켜짐'
                      : '스크린샷 자동 감지 꺼짐',
                ),
              ),
              Switch(
                value: _isListeningEnabled,
                onChanged: _toggleListening,
              ),
            ],
          ),
        ),
      ),
    );
  }
}