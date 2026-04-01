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
import 'ScreenshotAutoDetectSettingsPage.dart';
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

  Future<void> _openScreenshotSettingsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScreenshotAutoDetectSettingsPage(
          isEnabled: _isListeningEnabled,
          onToggleChanged: (value) async {
            await _toggleListening(value);
          },
        ),
      ),
    );
  }

  // ── 색상 상수 ──────────────────────────────────────────
  static const Color _accent = Color(0xFF6155F5);
  static const Color _mutedText = Color(0xFF8E8E93);
  static const Color _shareReceivedBg = Color(0xFFDBD8FF);
  static const Color _shareReceivedBorder = Color(0xFF4034CD);
  static const Color _sharedBg = Color(0xFFFDD3D0);
  static const Color _sharedBorder = Color(0xFFEC221F);
  static const Color _inactiveBg = Color(0xFFE3E3E3);
  static const Color _inactiveBorder = Color(0xFF767676);

  int _selectedTab = 0; // 0 = 사용 전, 1 = 사용 완료/만료

  // ── 커스텀 헤더 ─────────────────────────────────────────
  PreferredSizeWidget _buildCustomAppBar() {
    const double topStripHeight = 55;
    const double infoHeaderHeight = 108;
    const double headerGap = 8;
    const double totalHeight = topStripHeight + headerGap + infoHeaderHeight;

    return PreferredSize(
      preferredSize: const Size.fromHeight(totalHeight),
      child: Container(
        color: Colors.white,
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _GifticonTopStrip(),
              Container(
                height: infoHeaderHeight,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(28, 20, 20, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEBEBEB).withValues(alpha: 0.25),
                      offset: const Offset(0, 4),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _myNickname ?? '사용자',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '보관 중인 기프티콘을 확인해보세요',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF5A5A5A),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _openScreenshotSettingsPage,
                      icon: const Icon(
                        Icons.more_horiz,
                        color: Color(0xFFB3B3B3),
                        size: 22,
                      ),
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
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

  // ── 탭바 ──────────────────────────────────────────────
  Widget _buildTabBar(int activeCount, int inactiveCount) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: _TabItem(
              label: '사용 전',
              count: activeCount,
              selected: _selectedTab == 0,
              onTap: () => setState(() => _selectedTab = 0),
              accent: _accent,
            ),
          ),
          Expanded(
            child: _TabItem(
              label: '사용 완료 / 만료',
              count: inactiveCount,
              selected: _selectedTab == 1,
              onTap: () => setState(() => _selectedTab = 1),
              accent: _accent,
            ),
          ),
        ],
      ),
    );
  }

  // ── 알람 권한 버튼 ──────────────────────────────────────
  Widget _buildExactAlarmPermissionButton() {
    return GestureDetector(
      onTap: _isCheckingExactAlarmPermission ? null : _openExactAlarmSettings,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.alarm_add, color: _accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '기프티콘 만료 알림을 받으려면 정확 알람 권한이 필요해요',
                style: TextStyle(
                  fontSize: 12,
                  color: _accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (_isCheckingExactAlarmPermission)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.chevron_right, color: _accent, size: 18),
          ],
        ),
      ),
    );
  }

  // ── 빈 화면 ──────────────────────────────────────────
  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_giftcard_outlined, size: 56, color: _mutedText),
            const SizedBox(height: 12),
            Text(
              '저장된 기프티콘이 없어요',
              style: TextStyle(
                fontSize: 16,
                color: _mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '+ 버튼을 눌러 기프티콘을 추가해보세요',
              style: TextStyle(fontSize: 13, color: _mutedText),
            ),
          ],
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
    final displayItems = _selectedTab == 0 ? activeItems : inactiveItems;
    final muted = _selectedTab == 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildCustomAppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _buildTabBar(activeItems.length, inactiveItems.length),
          const SizedBox(height: 24),
          if (!_isCheckingExactAlarmPermission && !_canScheduleExactAlarms)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildExactAlarmPermissionButton(),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (displayItems.isEmpty)
            _buildEmptyState()
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: displayItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 20),
                itemBuilder: (_, i) =>
                    _buildGifticonCard(displayItems[i], muted: muted),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: _RegisterFab(
            onTap: _openAnalysisPage,
          ),
        ),
      ),
    );
  }

  Widget _buildGifticonCard(StoredGifticon item, {required bool muted}) {
    final now = _nowProvider.now();
    final isExpired = item.isExpiredAt(now);
    final isUsed = item.isUsed;
    final isShared = item.isShared;
    final isReceived = item.isReceived;

    final List<_ImageLabel> imageLabels = [];
    if (isReceived) {
      imageLabels.add(
        const _ImageLabel(
          text: '공유받음',
          bg: _shareReceivedBg,
          border: _shareReceivedBorder,
        ),
      );
    } else if (isShared) {
      imageLabels.add(
        const _ImageLabel(text: '공유됨', bg: _sharedBg, border: _sharedBorder),
      );
    }

    if (isUsed || isExpired) {
      imageLabels.add(
        _ImageLabel(
          text: isUsed ? '사용함' : '만료됨',
          bg: _inactiveBg,
          border: _inactiveBorder,
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openDetailPage(item),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            width: 1,
            color: isReceived
                ? _shareReceivedBorder.withValues(alpha: 0.4)
                : isShared
                ? _sharedBorder.withValues(alpha: 0.4)
                : const Color(0xFFE5E5EA),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GifticonThumbnail(
                        path: item.imagePath,
                        muted: muted,
                        onRetryTriggered: () {
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      if (imageLabels.isNotEmpty)
                        Positioned.fill(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < imageLabels.length; i++) ...[
                                if (i > 0) const SizedBox(height: 6),
                                _buildImageLabel(imageLabels[i]),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.merchantName ?? '교환처 없음',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF8E8E93),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.itemName ?? '상품명 없음',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A1A),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '유효기간: ${_formatDate(item.expiresAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF1A1A1A),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 100,
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 22,
                      color: Color(0xFFC7C7CC),
                    ),
                    onPressed: () => _confirmDelete(item),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageLabel(_ImageLabel label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: label.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: label.border, width: 0.8),
      ),
      child: Text(
        label.text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: label.border,
        ),
      ),
    );
  }
}

// ── 탭 아이템 위젯 ──────────────────────────────────────────
class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: selected ? accent : const Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 2,
              width: double.infinity,
              color: selected ? accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 이미지 라벨 데이터 클래스 ───────────────────────────────
class _ImageLabel {
  const _ImageLabel({
    required this.text,
    required this.bg,
    required this.border,
  });

  final String text;
  final Color bg;
  final Color border;
}

class _GifticonTopStrip extends StatelessWidget {
  const _GifticonTopStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 55,
      width: double.infinity,
      color: const Color(0xFFE9E8F5),
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(left: 20, top: 0, bottom: 0, child: _StripeGroup()),
          Positioned(right: 20, top: 0, bottom: 0, child: _StripeGroup()),
          Text(
            '꺼내먹어요',
            style: TextStyle(
              fontFamily: 'BM KIRANGHAERANG',
              fontSize: 28,
              fontWeight: FontWeight.w400,
              height: 31 / 28,
              color: Color(0xFF382EAC),
            ),
          ),
        ],
      ),
    );
  }
}

class _StripeGroup extends StatelessWidget {
  const _StripeGroup();

  @override
  Widget build(BuildContext context) {
    const Color color = Color(0xFF4034CD);

    return SizedBox(
      width: 25,
      height: 55,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _StripeLine(width: 1.2, color: color),
          ),
          Positioned(
            left: 7.14,
            top: 0,
            bottom: 0,
            child: _StripeLine(width: 4.8, color: color),
          ),
          Positioned(
            left: 12.5,
            top: 0,
            bottom: 0,
            child: _StripeLine(width: 1.2, color: color),
          ),
          Positioned(
            left: 16.07,
            top: 0,
            bottom: 0,
            child: _StripeLine(width: 1.2, color: color),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _StripeLine(width: 4.8, color: color),
          ),
        ],
      ),
    );
  }
}

class _StripeLine extends StatelessWidget {
  const _StripeLine({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: width, color: color);
  }
}

class _RegisterFab extends StatelessWidget {
  const _RegisterFab({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB9B5ED).withValues(alpha: 0.61),
            offset: const Offset(0, 6),
            blurRadius: 9.5,
          ),
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.16),
            offset: const Offset(0, -4),
            blurRadius: 21.7,
          ),
        ],
      ),
      child: Material(
        color: const Color(0xFF6155F5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: const SizedBox(
            height: 60,
            width: double.infinity,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 26,
                  ),
                  SizedBox(width: 14),
                  Text(
                    '등록하기',
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
}