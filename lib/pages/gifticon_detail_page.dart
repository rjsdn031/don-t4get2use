import 'dart:io';

import 'package:flutter/material.dart';

import '../models/stored_gifticon.dart';

class GifticonDetailPage extends StatelessWidget {
  final StoredGifticon item;

  const GifticonDetailPage({
    super.key,
    required this.item,
  });

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기프티콘 보기'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(item.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 240,
                  color: const Color(0xFFF2F2F2),
                  child: const Center(
                    child: Text('이미지를 불러올 수 없습니다.'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoTile('교환처', item.merchantName ?? '-'),
                    _buildInfoTile('상품명', item.itemName ?? '-'),
                    _buildInfoTile('유효기간', _formatDate(item.expiresAt)),
                    _buildInfoTile('쿠폰번호', item.couponNumber ?? '-'),
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