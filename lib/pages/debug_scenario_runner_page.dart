import 'package:flutter/material.dart';

import '../models/stored_gifticon.dart';
import '../services/debug_now_provider.dart';
import '../services/debug_scenario_service.dart';
import '../services/debug_time_controller.dart';
import '../services/gifticon_services.dart';
import 'gifticon_list_page.dart';

class DebugScenarioRunnerPage extends StatefulWidget {
  const DebugScenarioRunnerPage({
    super.key,
    required this.services,
    required this.debugTimeController,
  });

  final GifticonServices services;
  final DebugTimeController debugTimeController;

  @override
  State<DebugScenarioRunnerPage> createState() => _DebugScenarioRunnerPageState();
}

class _DebugScenarioRunnerPageState extends State<DebugScenarioRunnerPage> {
  late final DebugScenarioService _runner;
  final List<String> _logs = <String>[];

  bool _busy = false;
  String? _deviceId;
  String? _nickname;
  List<StoredGifticon> _items = const <StoredGifticon>[];

  DateTime? _oneDayBeforeAt9am(StoredGifticon? item) {
    final expiresAt = item?.expiresAt;
    if (expiresAt == null) return null;

    final target = expiresAt.subtract(const Duration(days: 1));
    return DateTime(target.year, target.month, target.day, 9, 0, 0);
  }

  String _fmtDateTime(DateTime? value) {
    if (value == null) return '-';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  @override
  void initState() {
    super.initState();
    _runner = DebugScenarioService(
      storageService: widget.services.storageService,
      notificationService: widget.services.notificationService,
      sharingService: widget.services.sharingService,
      deviceIdService: widget.services.deviceIdService,
    );
    _load();
  }

  void _log(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');

    setState(() {
      _logs.insert(0, '[$hh:$mm:$ss] $message');
    });
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final deviceId = await _runner.getDeviceId();
      final nickname = await _runner.getNickname();
      final items = _runner.getAllGifticons();

      if (!mounted) return;
      setState(() {
        _deviceId = deviceId;
        _nickname = nickname;
        _items = items;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _run(String label, Future<void> Function() task) async {
    setState(() => _busy = true);
    _log('$label 시작');
    try {
      await task();
      _log('$label 완료');
      await _load();
    } catch (e) {
      _log('$label 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _scheduleBackgroundAutoShare(StoredGifticon item) async {
    await widget.services.workService.scheduleAutoShareWork(
      gifticonId: item.id,
      initialDelay: const Duration(seconds: 10),
    );
  }

  StoredGifticon? get _latestItem => _items.isEmpty ? null : _items.first;

  DateTime get _appNow => widget.debugTimeController.now();

  @override
  Widget build(BuildContext context) {
    final latest = _latestItem;

    final oneDayBefore = _oneDayBeforeAt9am(latest);
    final appNow = _appNow;
    final isBeforeBoundary =
    oneDayBefore?.isAfter(appNow);

    return Scaffold(
      appBar: AppBar(
        title: const Text('디버그 시나리오 러너'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            title: '현재 상태',
            children: [
              Text('앱 기준 시각: ${widget.debugTimeController.label}'),
              Text('기기 ID: ${_deviceId ?? '-'}'),
              Text('닉네임: ${_nickname ?? '-'}'),
              Text('기프티콘 수: ${_items.length}'),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: '시간 프리셋',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () {
                      widget.debugTimeController.setFixedNow(
                        DateTime(2026, 3, 30, 8, 59),
                      );
                      _log('고정 시간 설정: 2026-03-30 08:59');
                      setState(() {});
                    },
                    child: const Text('2026-03-30 08:59'),
                  ),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () {
                      widget.debugTimeController.setFixedNow(
                        DateTime(2026, 3, 30, 9, 0),
                      );
                      _log('고정 시간 설정: 2026-03-30 09:00');
                      setState(() {});
                    },
                    child: const Text('2026-03-30 09:00'),
                  ),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () {
                      widget.debugTimeController.setFixedNow(
                        DateTime(2026, 3, 30, 9, 1),
                      );
                      _log('고정 시간 설정: 2026-03-30 09:01');
                      setState(() {});
                    },
                    child: const Text('2026-03-30 09:01'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                      widget.debugTimeController.clear();
                      _log('고정 시간 해제');
                      setState(() {});
                    },
                    child: const Text('시간 해제'),
                  ),
                  ElevatedButton(
                    onPressed: _busy || latest == null
                        ? null
                        : () => _run(
                      '경계값 테스트 실행',
                          () async {
                        final boundary = _oneDayBeforeAt9am(latest);
                        final allowed =
                        boundary != null ? boundary.isAfter(_appNow) : false;

                        _log(
                          'boundary check: appNow=${_fmtDateTime(_appNow)}, '
                              'boundary=${_fmtDateTime(boundary)}, '
                              'isAfter=$allowed',
                        );

                        await _runner.triggerOneDayBeforeShare(latest);

                        _log(
                          'boundary trigger requested: id=${latest.id}, '
                              'expectedByCurrentLogic=${allowed ? 'TRIGGER' : 'SKIP'}',
                        );
                      },
                    ),
                    child: const Text('경계값 테스트 실행'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: '시나리오 액션',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                      '내일 만료 기프티콘 생성',
                          () async {
                        final seeded = await _runner.seedGifticon(
                          expiresAt: DateTime(
                            _appNow.year,
                            _appNow.month,
                            _appNow.day + 1,
                          ),
                        );
                        _log(
                          'seed created: id=${seeded.id} expiresAt=${seeded.expiresAt}',
                        );
                      },
                    ),
                    child: const Text('내일 만료 기프티콘 생성'),
                  ),
                  ElevatedButton(
                    onPressed: _busy || latest == null
                        ? null
                        : () => _run(
                      '1일 전 공유 트리거',
                          () async {
                        await _runner.triggerOneDayBeforeShare(latest);
                        _log('share trigger requested: id=${latest.id}');
                      },
                    ),
                    child: const Text('1일 전 공유 트리거'),
                  ),
                  ElevatedButton(
                    onPressed: _busy || latest == null
                        ? null
                        : () => _run(
                      '직접 공유',
                          () async {
                        await _runner.directShare(latest);
                        _log('direct share requested: id=${latest.id}');
                      },
                    ),
                    child: const Text('직접 공유'),
                  ),
                  ElevatedButton(
                    onPressed: _busy || latest == null
                        ? null
                        : () => _run(
                      '백그라운드 공유 작업 예약(10초)',
                          () async {
                        await _scheduleBackgroundAutoShare(latest);
                        _log(
                          'background auto share scheduled: '
                              'id=${latest.id}, delay=10s',
                        );
                      },
                    ),
                    child: const Text('백그라운드 공유 예약(10초)'),
                  ),
                  ElevatedButton(
                    onPressed: _busy || latest == null
                        ? null
                        : () => _run(
                      '로컬 사용 처리',
                          () async {
                        await _runner.markUsedLocal(latest.id);
                        _log('local used: id=${latest.id}');
                      },
                    ),
                    child: const Text('로컬 사용 처리'),
                  ),
                  ElevatedButton(
                    onPressed: _busy || latest == null
                        ? null
                        : () => _run(
                      '원격 사용 처리',
                          () async {
                        await _runner.markUsedRemote(latest.id);
                        _log('remote used requested: id=${latest.id}');
                      },
                    ),
                    child: const Text('원격 사용 처리'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GifticonListPage(
                            servicesOverride: widget.services,
                            nowProviderOverride:
                            DebugNowProvider(widget.debugTimeController),
                          ),
                        ),
                      );
                    },
                    child: const Text('보관함 열기'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: '최신 기프티콘',
            children: [
              if (latest == null)
                const Text('없음')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('id: ${latest.id}'),
                    Text('상품: ${latest.itemName ?? '-'}'),
                    Text('브랜드: ${latest.merchantName ?? '-'}'),
                    Text('만료일: ${latest.expiresAt ?? '-'}'),
                    Text('sharedAt: ${latest.sharedAt ?? '-'}'),
                    Text('receivedFrom: ${latest.receivedFrom ?? '-'}'),
                    Text('ownerNickname: ${latest.ownerNickname ?? '-'}'),
                    Text('usedAt: ${latest.usedAt ?? '-'}'),
                    Text('usedByNickname: ${latest.usedByNickname ?? '-'}'),
                    Text('앱 기준 시각: ${_fmtDateTime(appNow)}'),
                    Text('1일 전 기준 시각: ${_fmtDateTime(oneDayBefore)}'),
                    Text(
                      '현재 구현 기준 공유 트리거 가능: '
                          '${isBeforeBoundary == null ? '-' : isBeforeBoundary ? 'YES' : 'NO'}',
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: '로그',
            children: [
              if (_logs.isEmpty)
                const Text('아직 로그가 없습니다.')
              else
                ..._logs.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(e),
                )),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}