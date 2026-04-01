import 'dart:io';

import 'package:flutter/material.dart';

import '../models/stored_gifticon.dart';
import '../services/gifticon_storage_service.dart';

class GifticonEditPage extends StatefulWidget {
  const GifticonEditPage({
    super.key,
    required this.item,
    required this.storageService,
    this.initialScrollOffset = 0,
  });

  final StoredGifticon item;
  final GifticonStorageService storageService;
  final double initialScrollOffset;

  @override
  State<GifticonEditPage> createState() => _GifticonEditPageState();
}

class _GifticonEditPageState extends State<GifticonEditPage> {
  static const Color _bg = Colors.white;
  static const Color _textPrimary = Color(0xFF1A1A1A);
  static const Color _textSecondary = Color(0xFF8E8E93);
  static const Color _fieldBg = Color(0xFFF6F6F6);
  static const Color _fieldBorder = Color(0xFFE5E5EA);
  static const Color _accent = Color(0xFF6155F5);

  static const List<BoxShadow> _buttonShadows = [
    BoxShadow(
      color: Color(0x9CB9B5ED),
      offset: Offset(0, 6),
      blurRadius: 9.5,
    ),
    BoxShadow(
      color: Color(0x29000000),
      offset: Offset(0, -4),
      blurRadius: 21.7,
    ),
  ];

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _merchantController;
  late final TextEditingController _itemNameController;
  late final TextEditingController _couponNumberController;
  late final ScrollController _scrollController;

  DateTime? _expiresAt;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController(
      text: widget.item.merchantName ?? '',
    );
    _itemNameController = TextEditingController(
      text: widget.item.itemName ?? '',
    );
    _couponNumberController = TextEditingController(
      text: widget.item.couponNumber ?? '',
    );
    _expiresAt = widget.item.expiresAt;
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialScrollOffset,
    );
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _itemNameController.dispose();
    _couponNumberController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final initialDate = _expiresAt ?? now;

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
      _expiresAt = picked;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedItem = widget.item.copyWith(
        merchantName: _merchantController.text.trim().isEmpty
            ? widget.item.merchantName
            : _merchantController.text.trim(),
        itemName: _itemNameController.text.trim(),
        couponNumber: _couponNumberController.text.trim().isEmpty
            ? widget.item.couponNumber
            : _couponNumberController.text.trim(),
        expiresAt: _expiresAt,
      );

      final savedItem = await widget.storageService.updateGifticon(updatedItem);

      if (!mounted) return;
      Navigator.pop(context, savedItem);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('수정 중 오류가 발생했습니다.\n$e'),
        ),
      );
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '선택 안 함';
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year.$month.$day';
  }

  PreferredSizeWidget _buildCustomAppBar() {
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
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 22,
                        color: _textPrimary,
                      ),
                      splashRadius: 20,
                    ),
                  ),
                  const Center(
                    child: Text(
                      '기프티콘 수정',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
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

  Widget _buildRowTextField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
                height: 1.2,
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              textInputAction: textInputAction,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: _textPrimary,
                height: 1.2,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  fontSize: 16,
                  color: _textSecondary,
                ),
                filled: true,
                fillColor: _fieldBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: _accent,
                    width: 1.2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowDateField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 78,
            child: Text(
              '유효기간',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
                height: 1.2,
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSaving ? null : _pickExpiryDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: _fieldBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _fieldBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatDate(_expiresAt),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: _expiresAt == null
                                ? _textSecondary
                                : _textPrimary,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: _textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 60,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: _buttonShadows,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _isSaving ? null : _save,
            child: Center(
              child: _isSaving
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
                  : const Text(
                '수정 완료',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildCustomAppBar(),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 420,
                          color: const Color(0xFFF3F3F3),
                          alignment: Alignment.center,
                          child: Image.file(
                            File(widget.item.imagePath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) {
                              return const Center(
                                child: Text(
                                  '이미지를 불러올 수 없습니다.',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _textSecondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildRowTextField(
                        label: '교환처',
                        controller: _merchantController,
                        hintText: '예: 스타벅스',
                        textInputAction: TextInputAction.next,
                      ),
                      _buildRowTextField(
                        label: '상품명',
                        controller: _itemNameController,
                        hintText: '예: 아메리카노 Tall',
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return '상품명을 입력해 주세요.';
                          }
                          return null;
                        },
                      ),
                      _buildRowDateField(),
                      _buildRowTextField(
                        label: '쿠폰번호',
                        controller: _couponNumberController,
                        hintText: '예: 1234 5678 9012',
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                8,
                24,
                16 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: _buildSaveButton(),
            ),
          ],
        ),
      ),
    );
  }
}