import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter/material.dart';

import '../modules/android_latest_image_finder_module.dart';
import '../modules/latest_image_finder_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import '../modules/screenshot_event_listener_module.dart';

import '../services/gifticon_pipeline_service.dart';
import '../models/local_image_data.dart';
import '../services/screenshot_automation_service.dart';

class GifticonTestPage extends StatefulWidget {
  const GifticonTestPage({super.key});

  @override
  State<GifticonTestPage> createState() => _GifticonTestPageState();
}

class _GifticonTestPageState extends State<GifticonTestPage> {
  late final GifticonPipelineService _pipeline;
  late final LatestImageFinderModule _latestImageFinder;
  late final ScreenshotAutomationService _automationService;
  late final ScreenshotEventListenerModule _screenshotEventListener;

  StreamSubscription<dynamic>? _screenshotSubscription;
  bool _isListeningScreenshotEvents = false;

  LocalImageData? _latestImage;
  GifticonPipelineOutput? _output;
  String _log = '';

  @override
  void initState() {
    super.initState();

    _pipeline = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      detector: GifticonDetectorModule(),
      aiParser: RemoteGifticonAiParser(
        baseUrl: 'https://d42u-server.vercel.app',
      ),
    );

    _latestImage = null;

    _latestImageFinder = AndroidLatestImageFinderModule();

    _automationService = ScreenshotAutomationService(
      latestImageFinder: _latestImageFinder,
      pipeline: _pipeline,
    );

    _screenshotEventListener = ScreenshotEventListenerModule();
  }

  void _appendLog(String msg) {
    debugPrint(msg);
    setState(() {
      _log = '$_log\n$msg';
    });
  }

  Future<void> _checkLatestImage() async {
    final granted = await _ensureMediaPermission();
    _appendLog('media permission granted: $granted');
    if (!granted) {
      _appendLog('❌ media permission denied');
      return;
    }

    _appendLog('--- checkLatestImage ---');

    final latest = await _latestImageFinder.findLatestImage();

    if (latest == null) {
      _appendLog('❌ latest image not found');
      return;
    }

    _appendLog('✅ latest image found');
    _appendLog('path: ${latest.path}');
    _appendLog('fileName: ${latest.fileName}');
    _appendLog('size: ${latest.sizeBytes}');

    setState(() {
      _latestImage = latest;
    });
  }

  Future<bool> _ensureMediaPermission() async {
    if (!Platform.isAndroid) return true;

    PermissionStatus status;

    if (await Permission.photos.isGranted) {
      return true;
    }

    if (await Permission.photos.isDenied) {
      status = await Permission.photos.request();
      return status.isGranted;
    }

    if (await Permission.storage.isGranted) {
      return true;
    }

    if (await Permission.storage.isDenied) {
      status = await Permission.storage.request();
      return status.isGranted;
    }

    return false;
  }

  Future<void> _analyzeLatestImage() async {
    _appendLog('--- analyzeLatestImage ---');

    if (_latestImage == null) {
      _appendLog('❌ latest image is null. run check first.');
      return;
    }

    final output = await _pipeline.runFromImage(_latestImage!);

    _appendLog('✅ analysis done');
    _appendLog('isGifticon: ${output.detection.isGifticon}');
    _appendLog('score: ${output.detection.score}');
    _appendLog('matched: ${output.detection.matchedSignals.join(', ')}');

    if (output.parsedInfo != null) {
      _appendLog('🎁 parsed: ${output.parsedInfo}');
    } else {
      _appendLog('parsed: null');
    }

    setState(() {
      _output = output;
    });
  }

  Future<void> _pickFromGallery() async {
    _appendLog('--- pickFromGallery ---');

    final output = await _pipeline.runFromGallery();

    if (output == null) {
      _appendLog('❌ pick cancelled');
      return;
    }

    _appendLog('✅ picked & analyzed');
    _appendLog('isGifticon: ${output.detection.isGifticon}');
    _appendLog('score: ${output.detection.score}');

    setState(() {
      _output = output;
    });
  }

  Future<void> _runAutomationOnce() async {
    final granted = await _ensureMediaPermission();
    _appendLog('media permission granted: $granted');
    if (!granted) {
      _appendLog('❌ media permission denied');
      return;
    }

    _appendLog('--- runAutomationOnce ---');

    final output = await _automationService.handleScreenshotDetected();

    if (output == null) {
      _appendLog('❌ automation returned null');
      return;
    }

    _appendLog('✅ automation completed');
    _appendLog('image path: ${output.image.path}');
    _appendLog('isGifticon: ${output.detection.isGifticon}');
    _appendLog('score: ${output.detection.score}');
    _appendLog('matched: ${output.detection.matchedSignals.join(', ')}');

    if (output.parsedInfo != null) {
      _appendLog('parsed: ${output.parsedInfo}');
    } else {
      _appendLog('parsed: null');
    }

    setState(() {
      _latestImage = output.image;
      _output = output;
    });
  }

  Future<void> _startListeningScreenshotEvents() async {
    if (_isListeningScreenshotEvents) {
      _appendLog('already listening screenshot events');
      return;
    }

    final granted = await _ensureMediaPermission();
    _appendLog('media permission granted: $granted');
    if (!granted) {
      _appendLog('❌ media permission denied');
      return;
    }

    _appendLog('--- startListeningScreenshotEvents ---');

    _screenshotSubscription = _screenshotEventListener.events.listen(
          (event) async {
        _appendLog('📸 screenshot event: $event');

        await Future.delayed(const Duration(milliseconds: 500));

        final output = await _automationService.handleScreenshotDetected();
        if (output == null) {
          _appendLog('automation ignored or returned null');
          return;
        }

        _appendLog('✅ auto automation completed');
        _appendLog('image path: ${output.image.path}');
        _appendLog('isGifticon: ${output.detection.isGifticon}');
        _appendLog('score: ${output.detection.score}');
        _appendLog('matched: ${output.detection.matchedSignals.join(', ')}');

        if (output.parsedInfo != null) {
          _appendLog('parsed: ${output.parsedInfo}');
        }

        if (!mounted) return;
        setState(() {
          _latestImage = output.image;
          _output = output;
        });
      },
      onError: (error) {
        _appendLog('❌ screenshot event error: $error');
      },
    );

    setState(() {
      _isListeningScreenshotEvents = true;
    });

    _appendLog('✅ screenshot event listening started');
  }

  Future<void> _stopListeningScreenshotEvents() async {
    await _screenshotSubscription?.cancel();
    _screenshotSubscription = null;

    setState(() {
      _isListeningScreenshotEvents = false;
    });

    _appendLog('🛑 screenshot event listening stopped');
  }

  @override
  void dispose() {
    _screenshotSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gifticon Test'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),

          /// 버튼 영역
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _checkLatestImage,
                  child: const Text('1. 최신 이미지 찾기'),
                ),
                ElevatedButton(
                  onPressed: _analyzeLatestImage,
                  child: const Text('2. 최신 이미지 분석'),
                ),
                ElevatedButton(
                  onPressed: _pickFromGallery,
                  child: const Text('3. 갤러리 선택 분석'),
                ),
                ElevatedButton(
                  onPressed: _runAutomationOnce,
                  child: const Text('4. 자동화 흐름 1회 실행'),
                ),
                ElevatedButton(
                  onPressed: _startListeningScreenshotEvents,
                  child: const Text('5. 스크린샷 이벤트 수신 시작'),
                ),
                ElevatedButton(
                  onPressed: _stopListeningScreenshotEvents,
                  child: const Text('6. 스크린샷 이벤트 수신 중지'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          /// 결과 표시
          if (_latestImage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Latest: ${_latestImage!.fileName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),

          if (_output != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Gifticon: ${_output!.detection.isGifticon}',
                style: const TextStyle(fontSize: 16),
              ),
            ),

          const Divider(),

          /// 로그 영역
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(
                _log,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}