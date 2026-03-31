import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/stored_gifticon.dart';
import '../modules/screenshot_event_listener_module.dart';
import '../services/gifticon_notification_service.dart';
import '../services/gifticon_services.dart';
import '../services/gifticon_storage_service.dart';
import '../services/now_provider.dart';
import '../services/screenshot_automation_service.dart';
import 'gifticon_analysis_page.dart';
import 'gifticon_detail_page.dart';

class GifticonListPage extends StatefulWidget {
  const GifticonListPage({
    super.key,
    this.servicesOverride,
    this.nowProviderOverride,
  });

  final GifticonServices? servicesOverride;
  final NowProvider? nowProviderOverride;

  @override
  State<GifticonListPage> createState() => _GifticonListPageState();
}

class _GifticonThumbnail extends StatefulWidget {
  const _GifticonThumbnail({
    required this.path,
    required this.muted,
    required this.onRetryTriggered,
  });

  final String path;
  final bool muted;
  final VoidCallback onRetryTriggered;

  @override
  State<_GifticonThumbnail> createState() => _GifticonThumbnailState();
}

class _GifticonThumbnailState extends State<_GifticonThumbnail> {
  int _retry = 0;
  bool _retryScheduled = false;

  void _scheduleRetry() {
    if (_retryScheduled || _retry >= 1) {
      debugPrint(
        '[Gifticon][Thumb][RetrySkip] '
        'path=${widget.path} retry=$_retry retryScheduled=$_retryScheduled',
      );
      return;
    }

    _retryScheduled = true;
    debugPrint('[Gifticon][Thumb][RetryScheduled] path=${widget.path}');

    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted) {
        debugPrint(
          '[Gifticon][Thumb][RetryAbort] unmounted path=${widget.path}',
        );
        return;
      }

      final provider = ResizeImage(FileImage(File(widget.path)), width: 160);

      debugPrint('[Gifticon][Thumb][RetryStart] path=${widget.path}');
      await provider.evict();
      debugPrint('[Gifticon][Thumb][RetryEvicted] path=${widget.path}');

      if (!mounted) return;

      setState(() {
        _retry += 1;
        _retryScheduled = false;
      });

      debugPrint(
        '[Gifticon][Thumb][RetrySetState] path=${widget.path} retry=$_retry',
      );

      widget.onRetryTriggered();
      debugPrint('[Gifticon][Thumb][RetryParentTriggered] path=${widget.path}');
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[Gifticon][Thumb][Build] '
      'path=${widget.path} retry=$_retry muted=${widget.muted}',
    );

    return ColorFiltered(
      colorFilter: widget.muted
          ? const ColorFilter.matrix([
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ])
          : const ColorFilter.mode(Colors.transparent, BlendMode.color),
      child: Image(
        key: ValueKey('${widget.path}_$_retry'),
        image: ResizeImage(FileImage(File(widget.path)), width: 160),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, error, __) {
          final file = File(widget.path);
          file.exists().then((exists) async {
            final length = exists ? await file.length() : -1;
            debugPrint(
              '[Gifticon][Thumb][Error] '
              'path=${widget.path} retry=$_retry '
              'exists=$exists length=$length error=$error',
            );
          });

          _scheduleRetry();

          return const ColoredBox(
            color: Color(0xFFF2F2F2),
            child: Icon(Icons.broken_image),
          );
        },
      ),
    );
  }
}

class _GifticonListPageState extends State<GifticonListPage>
    with WidgetsBindingObserver {
  late final GifticonServices _services;
  late final GifticonStorageService _storageService;
  late final ScreenshotAutomationService _automationService;
  late final ScreenshotEventListenerModule _screenshotEventListener;
  late final GifticonNotificationService _notificationService;
  late final NowProvider _nowProvider =
      widget.nowProviderOverride ?? SystemNowProvider();

  StreamSubscription<dynamic>? _screenshotSubscription;
  StreamSubscription<List<StoredGifticon>>? _itemsSubscription;

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  bool _loading = true;
  bool _isListeningEnabled = true;
  bool _isListeningActive = false;
  bool _isProcessingScreenshot = false;
  bool _isInitialized = false;
  bool _isCheckingExactAlarmPermission = false;
  bool _canScheduleExactAlarms = false;

  List<StoredGifticon> _items = const [];
  String? _myNickname;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screenshotSubscription?.cancel();
    _itemsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleResumedRefresh() async {
    if (!_isInitialized) return;

    debugPrint(
      '[Gifticon][ListPage][Lifecycle] resumed -> reopen & reload start',
    );

    await _itemsSubscription?.cancel();
    debugPrint('[Gifticon][ListPage][Lifecycle] items subscription cancelled');

    await _storageService.reopenBox();
    debugPrint('[Gifticon][ListPage][Lifecycle] storage box reopened');

    _listenToItems();
    debugPrint('[Gifticon][ListPage][Lifecycle] items subscription restarted');

    await _loadItems();

    debugPrint(
      '[Gifticon][ListPage][Lifecycle] resumed -> reopen & reload done',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      '[Gifticon][ListPage][Lifecycle] '
      'from=$_appLifecycleState to=$state initialized=$_isInitialized',
    );

    _appLifecycleState = state;

    if (state == AppLifecycleState.resumed && _isInitialized) {
      _handleResumedRefresh();
      debugPrint(
        '[Gifticon][ListPage][Lifecycle] resumed -> refresh permission',
      );

      _refreshExactAlarmPermissionStatus();

      if (_isListeningEnabled && !_isListeningActive) {
        debugPrint(
          '[Gifticon][ListPage][Lifecycle] resumed -> restart listener',
        );
        _startListeningScreenshotEvents();
      }
    }
  }

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final status = await Permission.notification.status;
    if (status.isGranted) return;

    await Permission.notification.request();
  }

  void _listenToItems() {
    _itemsSubscription?.cancel();
    _itemsSubscription = _storageService.watchGifticons().listen((items) {
      debugPrint(
        '[Gifticon][ListPage][ItemsStream] received items=${items.length}',
      );

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });

      debugPrint(
        '[Gifticon][ListPage][ItemsStream] setState complete items=${_items.length}',
      );
    });
  }

  Future<void> _initialize() async {
    try {
      await _ensureNotificationPermission();

      _services =
          widget.servicesOverride ??
          await GifticonServices.create(nowProvider: _nowProvider);
      _storageService = _services.storageService;
      _listenToItems();
      _automationService = _services.automationService;
      _screenshotEventListener = ScreenshotEventListenerModule();
      _notificationService = _services.notificationService;

      if (!mounted) return;

      _isInitialized = true;
      await _loadMyNickname();
      await _loadItems();
      await _refreshExactAlarmPermissionStatus();

      if (_isListeningEnabled) {
        await _startListeningScreenshotEvents();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('초기화 중 오류가 발생했습니다: $e')));
    }
  }

  Future<void> _refreshExactAlarmPermissionStatus() async {
    if (!_isInitialized) return;

    setState(() {
      _isCheckingExactAlarmPermission = true;
    });

    try {
      final canSchedule = await _services.notificationService
          .canScheduleExactAlarms();

      if (!mounted) return;
      setState(() {
        _canScheduleExactAlarms = canSchedule;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('정확 알람 권한 상태를 확인하지 못했습니다: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isCheckingExactAlarmPermission = false;
      });
    }
  }

  Future<void> _openExactAlarmSettings() async {
    try {
      await _services.notificationService.openExactAlarmSettings();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정확 알람 설정 화면을 열었습니다. 허용 후 앱으로 돌아와 주세요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('정확 알람 설정 화면을 열지 못했습니다: $e')));
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
    if (_isListeningActive) {
      debugPrint('[Gifticon][List] screenshot listener already active');
      return;
    }

    debugPrint('[Gifticon][List] requesting media permission...');
    final granted = await _ensureMediaPermission();
    debugPrint('[Gifticon][List] media permission granted=$granted');

    if (!granted) {
      debugPrint('[Gifticon][List] media permission denied');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미지 접근 권한이 필요합니다.')));
      return;
    }

    debugPrint('[Gifticon][List] start screenshot event subscription');

    _screenshotSubscription = _screenshotEventListener.events.listen(
      (event) async {
        debugPrint(
          '[Gifticon][ListPage][ScreenshotEvent] '
          'event=$event enabled=$_isListeningEnabled processing=$_isProcessingScreenshot '
          'lifecycle=$_appLifecycleState',
        );

        if (!_isListeningEnabled || _isProcessingScreenshot) return;

        _isProcessingScreenshot = true;

        try {
          final isBackground =
              _appLifecycleState == AppLifecycleState.paused ||
              _appLifecycleState == AppLifecycleState.detached ||
              _appLifecycleState == AppLifecycleState.hidden;

          debugPrint(
            '[Gifticon][ListPage][ScreenshotEvent] handle start isBackground=$isBackground',
          );

          final output = await _automationService.handleScreenshotDetected(
            isBackground: isBackground,
          );

          debugPrint(
            '[Gifticon][ListPage][ScreenshotEvent] handle done output=$output',
          );

          debugPrint('[Gifticon][List] automation output=$output');

          if (output == null) return;
          if (!output.isGifticon) return;

          if (!mounted) return;

          if (!isBackground) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('기프티콘을 인식했습니다. 저장 중...')),
            );
          }
        } catch (e) {
          debugPrint('[Gifticon][List][Error] $e');
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('스크린샷 처리 중 오류가 발생했습니다: $e')));
        } finally {
          _isProcessingScreenshot = false;
        }
      },
      onError: (error) {
        debugPrint('[Gifticon][List][StreamError] $error');
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('스크린샷 이벤트 수신 오류: $error')));
      },
    );

    if (!mounted) return;
    setState(() {
      _isListeningActive = true;
    });

    debugPrint('[Gifticon][List] screenshot listener active');
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
    debugPrint('[Gifticon][ListPage][LoadItems] fetched items=${items.length}');

    if (!mounted) return;

    setState(() {
      _items = items;
      _loading = false;
    });

    debugPrint(
      '[Gifticon][ListPage][LoadItems] setState complete items=${_items.length}',
    );
  }

  Future<void> _loadMyNickname() async {
    final nickname = await _services.deviceIdService.getNickname();
    if (!mounted) return;
    setState(() {
      _myNickname = nickname;
    });
  }

  Future<void> _deleteItem(StoredGifticon item) async {
    await _notificationService.cancelExpiryNotifications(item.id);
    await _storageService.deleteGifticon(item.id);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('기프티콘을 삭제했습니다.')));
  }

  Future<void> _openDetailPage(StoredGifticon item) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GifticonDetailPage(
          item: item,
          storageService: _storageService,
          notificationService: _notificationService,
          sharingService: _services.sharingService,
        ),
      ),
    );

    if (!mounted) return;
  }

  Future<void> _openAnalysisPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GifticonAnalysisPage(
          servicesOverride: _services,
          nowProviderOverride: _nowProvider,
        ),
      ),
    );

    if (!mounted) return;
    await _refreshExactAlarmPermissionStatus();
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

  Widget _buildExactAlarmPermissionButton() {
    final isGranted = _canScheduleExactAlarms;
    final icon = isGranted ? Icons.alarm_on : Icons.alarm_add;
    final title = isGranted ? '정확 알람 권한 허용됨' : '정확 알람 권한 허용하기';
    final subtitle = isGranted
        ? '만료 3일 전 / 하루 전 오전 9시 알림을 예약할 수 있어요.'
        : '기프티콘 만료 알림을 정확한 시간에 받으려면 권한이 필요해요.';

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isCheckingExactAlarmPermission ? null : _openExactAlarmSettings,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_isCheckingExactAlarmPermission)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  isGranted ? Icons.check_circle : Icons.chevron_right,
                  color: isGranted
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddCard() {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openAnalysisPage,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(radius: 22, child: Icon(Icons.add)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '기프티콘 추가',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('기프티콘 직접 추가하기'),
                  ],
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[Gifticon][ListPage][Build] '
      'items=${_items.length} loading=$_loading initialized=$_isInitialized',
    );

    final now = _nowProvider.now();
    final activeItems = _items.where((e) => !e.isInactiveAt(now)).toList();
    final inactiveItems = _items.where((e) => e.isInactiveAt(now)).toList();

    Widget listSection;

    if (_loading) {
      listSection = const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_items.isEmpty) {
      listSection = const Expanded(
        child: Center(child: Text('저장된 기프티콘이 없습니다.')),
      );
    } else {
      listSection = Expanded(
        child: ListView(
          padding: const EdgeInsets.only(top: 12),
          children: [
            // ── 활성 섹션 ──
            ...activeItems.map(
              (item) => _buildGifticonCard(item, muted: false),
            ),

            // ── 비활성 섹션 헤더 ──
            if (inactiveItems.isNotEmpty) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '사용 완료 / 만료',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              ...inactiveItems.map(
                (item) => _buildGifticonCard(item, muted: true),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('꺼내먹어요')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_myNickname ?? '사용자'}님, 안녕하세요',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '보관 중인 기프티콘을 확인해보세요',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            listSection,
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAnalysisPage,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isCheckingExactAlarmPermission ||
                  !_canScheduleExactAlarms) ...[
                _buildExactAlarmPermissionButton(),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isListeningActive ? '스크린샷 자동 감지 켜짐' : '스크린샷 자동 감지 꺼짐',
                    ),
                  ),
                  Switch(
                    value: _isListeningEnabled,
                    onChanged: _toggleListening,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGifticonCard(StoredGifticon item, {required bool muted}) {
    debugPrint(
      '[Gifticon][Card][Build] '
      'id=${item.id} path=${item.imagePath} muted=$muted '
      'itemName=${item.itemName} expiresAt=${item.expiresAt}',
    );

    final now = _nowProvider.now();

    final statusLabel = item.isUsed
        ? '사용함'
        : item.isExpiredAt(now)
        ? '만료됨'
        : null;

    final shareLabel = item.isReceived
        ? '공유받음'
        : item.isShared
        ? '공유됨'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: muted ? 0.45 : 1.0,
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            title: Row(
              children: [
                Expanded(child: Text(item.itemName ?? '상품명 없음')),
                if (shareLabel != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (item.isReceived ? Colors.purple : Colors.blue)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      shareLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: item.isReceived
                            ? Colors.purple.shade400
                            : Colors.blue.shade400,
                      ),
                    ),
                  ),
                ],
                if (statusLabel != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (item.isUsed ? Colors.grey : Colors.red)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: item.isUsed
                            ? Colors.grey.shade600
                            : Colors.red.shade400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
            onTap: () => _openDetailPage(item),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: _GifticonThumbnail(
                  path: item.imagePath,
                  muted: muted,
                  onRetryTriggered: () {
                    debugPrint(
                      '[Gifticon][ListPage][RetryParentSetState] path=${item.imagePath}',
                    );
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
