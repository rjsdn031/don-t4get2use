import 'dart:io';

import 'package:flutter/material.dart';

import '../models/stored_gifticon.dart';
import '../services/gifticon_storage_service.dart';

class GifticonEditPage extends StatefulWidget {
  const GifticonEditPage({
    super.key,
    required this.item,
    required this.storageService,
  });

  final StoredGifticon item;
  final GifticonStorageService storageService;

  @override
  State<GifticonEditPage> createState() => _GifticonEditPageState();
}

class _GifticonEditPageState extends State<GifticonEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _merchantController;
  late final TextEditingController _itemNameController;
  late final TextEditingController _couponNumberController;

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
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _itemNameController.dispose();
    _couponNumberController.dispose();
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
    return '$year-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('기프티콘 수정'),
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(widget.item.imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        height: 220,
                        alignment: Alignment.center,
                        color: const Color(0xFFF5F5F5),
                        child: const Text('이미지를 불러올 수 없습니다.'),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _merchantController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '교환처',
                    hintText: '예: 스타벅스',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _itemNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '상품명',
                    hintText: '예: 아메리카노 Tall',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return '상품명을 입력해 주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _isSaving ? null : _pickExpiryDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '유효기간',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDate(_expiresAt)),
                        const Icon(Icons.calendar_today),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _couponNumberController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '쿠폰 번호',
                    hintText: '예: 1234 5678 9012',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(_isSaving ? '저장 중...' : '수정사항 저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}