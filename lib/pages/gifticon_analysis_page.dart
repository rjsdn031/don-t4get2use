import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/gifticon_models.dart';
import '../modules/barcode_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import '../services/gifticon_notification_service.dart';
import '../services/gifticon_pipeline_service.dart';
import '../services/gifticon_storage_service.dart';

class GifticonAnalysisPage extends StatefulWidget {
  const GifticonAnalysisPage({super.key});

  @override
  State<GifticonAnalysisPage> createState() => _GifticonAnalysisPageState();
}

class _GifticonAnalysisPageState extends State<GifticonAnalysisPage> {
  late final GifticonPipelineService _pipeline;
  late final RemoteGifticonAiParser _aiParser;
  late final GifticonNotificationService _notificationService;
  final GifticonStorageService _storageService = GifticonStorageService();

  bool _loading = false;
  bool _saving = false;
  bool _saved = false;
  bool? _isGifticon;

  GifticonInfo? _parsedInfo;
  String _statusText = '아직 실행 전';
  File? _selectedImage;

  final TextEditingController _merchantController = TextEditingController();
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _couponNumberController = TextEditingController();

  DateTime? _editedExpiresAt;

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await _storageService.init();

    _notificationService = GifticonNotificationService(
      FlutterLocalNotificationsPlugin(),
    );
    await _notificationService.init();

    _pipeline = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      barcodeModule: GifticonBarcodeModule(),
      detector: GifticonDetectorModule(),
    );

    _aiParser = RemoteGifticonAiParser(
      baseUrl: 'https://d42u-server.vercel.app',
    );

    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _itemNameController.dispose();
    _couponNumberController.dispose();
    _pipeline.dispose();
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

      if (!output.isGifticon) {
        setState(() {
          _isGifticon = false;
          _parsedInfo = null;
          _statusText = '기프티콘이 아닙니다.';
        });
        return;
      }

      setState(() {
        _isGifticon = true;
        _statusText = '기프티콘 인식 완료. 상세 정보를 분석 중입니다...';
      });

      final parsedInfo = await _aiParser.parse(
        rawText: output.ocr.rawText,
      );

      setState(() {
        _parsedInfo = parsedInfo;
        _applyParsedInfoToForm(parsedInfo);
        _statusText = '기프티콘 분석이 완료되었습니다.';
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
      final editedInfo = _buildEditedInfo();

      if ((editedInfo.itemName ?? '').trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('상품 이름을 입력해 주세요.')),
        );
        setState(() {
          _saving = false;
        });
        return;
      }

      final result = await _storageService.saveGifticon(
        sourceImagePath: _selectedImage!.path,
        info: editedInfo,
      );

      if (!mounted) return;

      if (result.isDuplicate) {
        setState(() {
          _saved = true;
          _statusText = '이미 저장된 기프티콘입니다.';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 저장된 기프티콘입니다.')),
        );

        Navigator.pop(context, false); // 새로 저장된 게 아니므로 false
        return;
      }

      final scheduled = await _notificationService.scheduleExpiryNotifications(
        result.gifticon,
      );

      setState(() {
        _saved = true;
        _statusText = '저장 완료';
      });

      final snackBarMessage = scheduled
          ? '기프티콘이 저장되고 만료 알림이 예약되었습니다.'
          : '기프티콘이 저장되었습니다. 정확 알람 권한을 허용하면 만료 알림도 예약됩니다.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snackBarMessage)),
      );

      Navigator.pop(context, true); // 새로 저장됐으므로 true
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
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

  void _applyParsedInfoToForm(GifticonInfo info) {
    _merchantController.text = info.merchantName ?? '';
    _itemNameController.text = info.itemName ?? '';
    _couponNumberController.text = info.couponNumber ?? '';
    _editedExpiresAt = info.expiresAt;
  }

  GifticonInfo _buildEditedInfo() {
    final current = _parsedInfo!;
    return GifticonInfo(
      merchantName: _merchantController.text.trim().isEmpty
          ? null
          : _merchantController.text.trim(),
      itemName: _itemNameController.text.trim().isEmpty
          ? null
          : _itemNameController.text.trim(),
      expiresAt: _editedExpiresAt,
      couponNumber: _couponNumberController.text.trim().isEmpty
          ? null
          : _couponNumberController.text.trim(),
      rawText: current.rawText,
    );
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final initialDate = _editedExpiresAt ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
      helpText: '유효기간 선택',
      cancelText: '취소',
      confirmText: '확인',
    );

    if (picked == null) return;

    setState(() {
      _editedExpiresAt = picked;
    });
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
        title: const Text('기프티콘 분석'),
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
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
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewPadding.bottom + 16,
                  ),
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
                                const Text(
                                  '인식 결과를 확인하고 필요하면 수정해 주세요.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _merchantController,
                                  decoration: const InputDecoration(
                                    labelText: '교환처',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _itemNameController,
                                  decoration: const InputDecoration(
                                    labelText: '상품 이름',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: _saving ? null : _pickExpiryDate,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: '유효기간',
                                      border: OutlineInputBorder(),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_formatDate(_editedExpiresAt)),
                                        const Icon(Icons.calendar_today),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _couponNumberController,
                                  decoration: const InputDecoration(
                                    labelText: '쿠폰 번호',
                                    border: OutlineInputBorder(),
                                  ),
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
      ),
    );
  }
}