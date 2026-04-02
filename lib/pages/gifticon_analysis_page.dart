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
import '../services/gifticon_services.dart';
import '../services/gifticon_storage_service.dart';
import '../services/now_provider.dart';

class GifticonAnalysisPage extends StatefulWidget {
  const GifticonAnalysisPage({
    super.key,
    this.servicesOverride,
    this.nowProviderOverride,
  });

  final GifticonServices? servicesOverride;
  final NowProvider? nowProviderOverride;

  @override
  State<GifticonAnalysisPage> createState() => _GifticonAnalysisPageState();
}

class _GifticonAnalysisPageState extends State<GifticonAnalysisPage> {
  static const Color _primaryColor = Color(0xFF6155F5);
  static const Color _fieldFillColor = Color(0xFFF5F5F5);
  static const Color _guideBgColor = Color(0xFFEFEFEF);
  static const Color _textPrimaryColor = Color(0xFF1A1A1A);
  static const Color _textSecondaryColor = Color(0xFF444444);
  static const Color _textHintColor = Color(0xFF5A5A5A);

  GifticonServices? _services;
  GifticonPipelineService? _pipeline;
  RemoteGifticonAiParser? _aiParser;
  GifticonNotificationService? _notificationService;
  GifticonStorageService? _storageService;

  bool _initialized = false;
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
    final services = widget.servicesOverride ??
        await GifticonServices.create(
          nowProvider: widget.nowProviderOverride ?? SystemNowProvider(),
        );

    final storageService = services.storageService;
    await storageService.init();

    final notificationService = GifticonNotificationService(
      FlutterLocalNotificationsPlugin(),
    );
    await notificationService.init();

    final pipeline = GifticonPipelineService(
      imagePicker: GifticonImagePickerModule(),
      ocrModule: GifticonOcrModule(),
      barcodeModule: GifticonBarcodeModule(),
      detector: GifticonDetectorModule(),
    );

    final aiParser = RemoteGifticonAiParser(
      baseUrl: 'https://d42u-server.vercel.app',
    );

    if (!mounted) return;

    setState(() {
      _services = services;
      _storageService = storageService;
      _notificationService = notificationService;
      _pipeline = pipeline;
      _aiParser = aiParser;
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _itemNameController.dispose();
    _couponNumberController.dispose();
    _pipeline?.dispose();
    super.dispose();
  }

  Future<void> runAnalysis() async {
    if (_pipeline == null || _aiParser == null) return;

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
      final output = await _pipeline!.runFromGallery();

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

      final parsedInfo = await _aiParser!.parse(
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
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> saveGifticon() async {
    if (_selectedImage == null ||
        _parsedInfo == null ||
        _storageService == null ||
        _notificationService == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final editedInfo = _buildEditedInfo();

      if ((editedInfo.itemName ?? '').trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('상품명을 입력해 주세요.')),
        );
        setState(() {
          _saving = false;
        });
        return;
      }

      final result = await _storageService!.saveGifticon(
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

        Navigator.pop(context, false);
        return;
      }

      final scheduled = await _notificationService!.scheduleExpiryNotifications(
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

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
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
    return '$y.$m.$d';
  }

  bool get _showResultForm {
    return _selectedImage != null;
  }

  bool get _shouldConfirmBeforeLeaving {
    return _loading || _selectedImage != null;
  }

  Future<bool> _confirmLeaveIfNeeded() async {
    if (!_shouldConfirmBeforeLeaving) {
      return true;
    }

    final bool? shouldLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final description = '지금 나가면 분석 결과가 저장되지 않아요.\n정말 나가시겠어요?';

        return AlertDialog(
          title: const Text('분석 페이지 나가기'),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('아니오'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('네'),
            ),
          ],
        );
      },
    );

    return shouldLeave ?? false;
  }

  Future<void> _handleBackPressed() async {
    final canLeave = await _confirmLeaveIfNeeded();
    if (!mounted || !canLeave) return;
    Navigator.of(context).pop();
  }

  bool get _canSave {
    return _isGifticon == true && _parsedInfo != null && _selectedImage != null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_shouldConfirmBeforeLeaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final canLeave = await _confirmLeaveIfNeeded();
        if (!mounted || !canLeave) return;

        Navigator.of(context).pop(result);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: !_initialized
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
          top: false,
          child: _showResultForm
              ? _buildResultBody(context)
              : _buildInitialBody(context),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
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
                      onPressed: _handleBackPressed,
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
                      '기프티콘 분석',
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

  Widget _buildInitialBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 28,
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Column(
              children: [
                const SizedBox(height: 18),
                const _BarcodeHero(),
                const SizedBox(height: 36),
                const Text(
                  '사용 예정인 기프티콘을 업로드해주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: _textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                _buildPrimaryButton(
                  text: _loading ? '분석 중...' : '이미지 선택 후 분석',
                  onTap: _loading ? null : runAnalysis,
                ),
                if (_statusText != '아직 실행 전') ...[
                  const SizedBox(height: 18),
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _textHintColor,
                    ),
                  ),
                ],
                const SizedBox(height: 44),
              ],
            ),
          ),
        ),
        _buildGuideSection(),
      ],
    );
  }

  Widget _buildResultBody(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 21,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        children: [
          _buildSelectedImageCard(),
          const SizedBox(height: 40),
          if (_canSave) ...[
            _buildInputSection(
              label: '교환처',
              child: _buildTextField(
                controller: _merchantController,
                hintText: '교환처를 입력해주세요',
              ),
            ),
            const SizedBox(height: 30),
            _buildInputSection(
              label: '상품명',
              child: _buildTextField(
                controller: _itemNameController,
                hintText: '상품명을 입력해주세요',
              ),
            ),
            const SizedBox(height: 30),
            _buildInputSection(
              label: '유효기간',
              child: _buildDateField(),
            ),
            const SizedBox(height: 30),
            _buildInputSection(
              label: '쿠폰번호',
              child: _buildTextField(
                controller: _couponNumberController,
                hintText: '쿠폰번호를 입력해주세요',
              ),
            ),
            const SizedBox(height: 34),
            Column(
              children: [
                const Text(
                  '*위 인식 내용을 확인해주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: _textHintColor,
                  ),
                ),
                const SizedBox(height: 17),
                _buildPrimaryButton(
                  text: _saved ? '저장됨' : (_saving ? '저장 중...' : '추가하기'),
                  onTap: (_saving || _saved) ? null : saveGifticon,
                ),
              ],
            ),
          ] else ...[
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildPrimaryButton(
              text: _loading ? '분석 중...' : '다시 분석하기',
              onTap: _loading ? null : runAnalysis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedImageCard() {
    return Container(
      width: 292,
      constraints: const BoxConstraints(minHeight: 466),
      decoration: BoxDecoration(
        border: Border.all(color: _primaryColor, width: 1),
        borderRadius: BorderRadius.circular(5),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: _selectedImage == null
          ? const SizedBox.shrink()
          : Image.file(
        _selectedImage!,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildStatusCard() {
    final bool isError = _statusText.startsWith('에러');
    final bool isNotGifticon = _isGifticon == false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError || isNotGifticon
              ? const Color(0xFFE57373)
              : _primaryColor.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        _statusText,
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
          color: _textSecondaryColor,
        ),
      ),
    );
  }

  Widget _buildInputSection({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textSecondaryColor,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: _fieldFillColor,
        border: Border.all(color: _primaryColor, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        enabled: !_saving,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: _textSecondaryColor,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: Color(0xFF9A9A9A),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 17,
            vertical: 19,
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _saving ? null : _pickExpiryDate,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: _fieldFillColor,
          border: Border.all(color: _primaryColor, width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _formatDate(_editedExpiresAt),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: _textSecondaryColor,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: _primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String text,
    required VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? _primaryColor : _primaryColor.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          boxShadow: enabled
              ? const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.16),
              offset: Offset(0, -4),
              blurRadius: 21.7,
            ),
            BoxShadow(
              color: Color.fromRGBO(185, 181, 237, 0.61),
              offset: Offset(0, 6),
              blurRadius: 9.5,
            ),
          ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuideSection() {
    return Container(
      width: double.infinity,
      color: _guideBgColor,
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '*이미지 분석 안내 사항',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _textPrimaryColor,
            ),
          ),
          SizedBox(height: 16),
          Text(
            '* 기프티콘이 잘 보이도록 전체 이미지를 업로드해주세요.\n\n'
                '* 바코드와 상품명, 유효기간이 선명할수록 인식 정확도가 높아집니다.\n\n'
                '* 분석 결과가 일부 다를 수 있으니 저장 전 내용을 꼭 확인해주세요.\n\n'
                '* 쿠폰번호가 자동으로 인식되지 않으면 직접 수정할 수 있습니다.\n\n'
                '* 저장 후 만료일 기준으로 알림이 예약됩니다.',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              fontWeight: FontWeight.w700,
              color: _textHintColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeHero extends StatelessWidget {
  const _BarcodeHero();

  static const Color _barColor = Color(0xFF4034CD);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 281,
      height: 196,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          _SingleBarcodeGroup(),
          _SingleBarcodeGroup(),
        ],
      ),
    );
  }
}

class _SingleBarcodeGroup extends StatelessWidget {
  const _SingleBarcodeGroup();

  static const Color _barColor = Color(0xFF4034CD);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110.3,
      height: 196.03,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBar(width: 4.3, blur: false),
          const SizedBox(width: 23),
          _buildBar(width: 17.1),
          const SizedBox(width: 14),
          _buildBar(width: 4.3, blur: false),
          const SizedBox(width: 11),
          _buildBar(width: 4.3, blur: false),
          const Spacer(),
          _buildBar(width: 17.1),
        ],
      ),
    );
  }

  Widget _buildBar({
    required double width,
    bool blur = false,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: _barColor.withValues(alpha: blur ? 0.65 : 1),
        borderRadius: BorderRadius.circular(2),
        boxShadow: blur
            ? const [
          BoxShadow(
            color: Color.fromRGBO(64, 52, 205, 0.45),
            blurRadius: 6,
          ),
        ]
            : null,
      ),
    );
  }
}