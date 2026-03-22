import 'dart:io';
import 'package:flutter/material.dart';

import 'models/gifticon_models.dart';
import 'modules/gifticon_detector_module.dart';
import 'modules/image_picker_module.dart';
import 'modules/ocr_module.dart';
import 'services/gifticon_pipeline_service.dart';
import 'modules/remote_gifticon_ai_parser.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Don\'t Forget to Use!',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const GifticonDemoPage(),
    );
  }
}

class GifticonDemoPage extends StatefulWidget {
  const GifticonDemoPage({super.key});

  @override
  State<GifticonDemoPage> createState() => _GifticonDemoPageState();
}

class _GifticonDemoPageState extends State<GifticonDemoPage> {
  late final GifticonPipelineService _pipeline;

  bool _loading = false;
  bool? _isGifticon;
  GifticonInfo? _parsedInfo;
  String _statusText = '아직 실행 전';
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _pipeline = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      detector: GifticonDetectorModule(),
      aiParser: RemoteGifticonAiParser(
        baseUrl: 'https://d42u-server.vercel.app/',
      ),
    );
  }

  @override
  void dispose() {
    _pipeline.ocrModule.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _isGifticon = null;
      _parsedInfo = null;
      _statusText = '처리 중...';
      _selectedImage = null;
    });

    try {
      final output = await _pipeline.run();

      if (output == null) {
        setState(() {
          _statusText = '이미지 선택이 취소되었습니다.';
          _selectedImage = null;
        });
        return;
      }

      setState(() {
        _selectedImage = File(output.pickedImage.path);
      });

      if (!output.detection.isGifticon) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Gifticon MVP Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _loading ? null : _run,
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
                              // _buildInfoTile('판별 결과', _statusText),
                              _buildInfoTile('교환처', _parsedInfo?.merchantName ?? '-'),
                              _buildInfoTile('상품 이름', _parsedInfo?.itemName ?? '-'),
                              _buildInfoTile('유효기간', _formatDate(_parsedInfo?.expiresAt)),
                              _buildInfoTile('쿠폰 번호', _parsedInfo?.couponNumber ?? '-'),
                            ] else ...[
                              _buildInfoTile('판별 결과', _statusText),
                            ],
                          ],
                        ),
                      ),
                    ),
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