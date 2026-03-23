import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/gifticon_models.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import '../services/gifticon_notification_service.dart';
import '../services/gifticon_pipeline_service.dart';
import '../services/gifticon_storage_service.dart';
import 'gifticon_list_page.dart';

class GifticonAnalysisPage extends StatefulWidget {
  const GifticonAnalysisPage({super.key});

  @override
  State<GifticonAnalysisPage> createState() => _GifticonAnalysisPageState();
}

class _GifticonAnalysisPageState extends State<GifticonAnalysisPage> {
  late final GifticonPipelineService _pipeline;
  final GifticonStorageService _storageService = GifticonStorageService();

  bool _loading = false;
  bool _saving = false;
  bool _saved = false;
  bool? _isGifticon;

  GifticonInfo? _parsedInfo;
  String _statusText = '아직 실행 전';
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _initPipeline();
  }

  Future<void> _initPipeline() async {
    final storageService = GifticonStorageService();
    await storageService.init();

    final notificationService = GifticonNotificationService(
      FlutterLocalNotificationsPlugin(),
    );
    await notificationService.init();

    _pipeline = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      detector: GifticonDetectorModule(),
      aiParser: RemoteGifticonAiParser(
        baseUrl: 'https://d42u-server.vercel.app',
      ),
      storageService: storageService,
      notificationService: notificationService,
    );

    setState(() {});
  }

  @override
  void dispose() {
    _pipeline.ocrModule.dispose();
    super.dispose();
  }

  Future<void> runAnalysis() async {
    setState(() {
      _loading = true;
      _saving = false;
      _saved = false;
      _isGifticon = null;
      _parsedInfo = null;
      _statusText = '처리 중...';
      _selectedImage = null;
    });

    try {
      final output = await _pipeline.runFromGallery();

      if (output == null) {
        setState(() {
          _statusText = '이미지 선택이 취소되었습니다.';
          _selectedImage = null;
        });
        return;
      }

      setState(() {
        _selectedImage = File(output.image.path);
      });

      if (!output.detection.isGifticon || output.parsedInfo == null) {
        setState(() {
          _isGifticon = false;
          _parsedInfo = null;
          _statusText = '기프티콘이 아닙니다.';
        });
        return;
      }

      setState(() {
        _isGifticon = true;
        _parsedInfo = output.parsedInfo;
        _statusText = '기프티콘입니다.';
      });
    } catch (e) {
      setState(() {
        _statusText = '에러 발생: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> saveGifticon() async {
    if (_selectedImage == null || _parsedInfo == null) return;

    setState(() {
      _saving = true;
    });

    try {
      await _storageService.saveGifticon(
        sourceImagePath: _selectedImage!.path,
        info: _parsedInfo!,
      );

      if (!mounted) return;

      setState(() {
        _saved = true;
        _statusText = '저장 완료';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('기프티콘이 저장되었습니다.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장 실패: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
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

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _isGifticon == true && _parsedInfo != null && _selectedImage != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Don\'t Forget to USE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GifticonListPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _loading ? null : runAnalysis,
              child: Text(_loading ? '처리 중...' : '이미지 선택 후 분석'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selectedImage != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isGifticon == true && _parsedInfo != null) ...[
                              _buildInfoTile('교환처', _parsedInfo?.merchantName ?? '-'),
                              _buildInfoTile('상품 이름', _parsedInfo?.itemName ?? '-'),
                              _buildInfoTile(
                                '유효기간',
                                _formatDate(_parsedInfo?.expiresAt),
                              ),
                              _buildInfoTile(
                                '쿠폰 번호',
                                _parsedInfo?.couponNumber ?? '-',
                              ),
                            ] else ...[
                              _buildInfoTile('판별 결과', _statusText),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (canSave) ...[
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: (_saving || _saved) ? null : saveGifticon,
                        child: Text(
                          _saved ? '저장됨' : (_saving ? '저장 중...' : '저장하기'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}