import 'package:flutter/material.dart';

import '../services/gifticon_pipeline_service.dart';
import '../services/gifticon_services.dart';
import '../services/screenshot_automation_service.dart';

class GifticonTestPage extends StatefulWidget {
  const GifticonTestPage({super.key});

  @override
  State<GifticonTestPage> createState() => _GifticonTestPageState();
}

class _GifticonTestPageState extends State<GifticonTestPage> {
  GifticonServices? _services;
  GifticonPipelineOutput? _lastOutput;
  bool _isInitializing = true;
  bool _isRunning = false;
  String _status = '초기화 중...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final services = await GifticonServices.create();

    if (!mounted) return;

    setState(() {
      _services = services;
      _isInitializing = false;
      _status = '준비 완료';
    });
  }

  Future<void> _runFromGallery() async {
    final pipeline = _services?.pipelineService;
    if (pipeline == null || _isRunning) return;

    setState(() {
      _isRunning = true;
      _status = '갤러리 이미지 분석 중...';
    });

    final output = await pipeline.runFromGallery();

    if (!mounted) return;

    setState(() {
      _lastOutput = output;
      _isRunning = false;
      _status = output == null ? '이미지 선택 취소됨' : '갤러리 테스트 완료';
    });
  }

  Future<void> _runLatestScreenshot() async {
    final automation = _services?.automationService;
    if (automation == null || _isRunning) return;

    setState(() {
      _isRunning = true;
      _status = '최근 스크린샷 분석 중...';
    });

    final output = await automation.handleScreenshotDetected();

    if (!mounted) return;

    setState(() {
      _lastOutput = output;
      _isRunning = false;
      _status = output == null ? '처리된 결과 없음' : '스크린샷 테스트 완료';
    });
  }

  @override
  Widget build(BuildContext context) {
    final output = _lastOutput;

    return Scaffold(
      appBar: AppBar(
        title: const Text('기프티콘 테스트'),
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isRunning ? null : _runFromGallery,
              child: const Text('갤러리에서 테스트'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isRunning ? null : _runLatestScreenshot,
              child: const Text('최근 스크린샷 테스트'),
            ),
            const SizedBox(height: 24),
            if (_isRunning) const LinearProgressIndicator(),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  output == null
                      ? '아직 실행 결과가 없습니다.'
                      : '''
isGifticon: ${output.isGifticon}
isSaved: ${output.isSaved}
score: ${output.detection.score}
matchedSignals: ${output.detection.matchedSignals.join(', ')}

merchantName: ${output.parsedInfo?.merchantName}
itemName: ${output.parsedInfo?.itemName}
expiresAt: ${output.parsedInfo?.expiresAt}
couponNumber: ${output.parsedInfo?.couponNumber}

imagePath: ${output.image.path}
storedId: ${output.storedGifticon?.id}
storedImagePath: ${output.storedGifticon?.imagePath}

rawText:
${output.ocr.rawText}
''',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}