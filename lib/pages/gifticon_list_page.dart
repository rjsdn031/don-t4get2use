import 'dart:io';

import 'package:flutter/material.dart';

import '../models/stored_gifticon.dart';
import '../services/gifticon_storage_service.dart';
import 'gifticon_detail_page.dart';

class GifticonListPage extends StatefulWidget {
  const GifticonListPage({super.key});

  @override
  State<GifticonListPage> createState() => _GifticonListPageState();
}

class _GifticonListPageState extends State<GifticonListPage> {
  final GifticonStorageService _storageService = GifticonStorageService();

  bool _loading = true;
  List<StoredGifticon> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    await _storageService.init();
    final items = _storageService.getAllGifticons();

    if (!mounted) return;

    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _deleteItem(StoredGifticon item) async {
    await _storageService.deleteGifticon(item.id);
    await _loadItems();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기프티콘을 삭제했습니다.')),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _confirmDelete(StoredGifticon item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('이 기프티콘을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteItem(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('저장된 기프티콘'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
        child: Text('저장된 기프티콘이 없습니다.'),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];

          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Image.file(
                    File(item.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xFFF2F2F2),
                      child: Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
              title: Text(item.itemName ?? '상품명 없음'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(item.merchantName ?? '교환처 없음'),
                  const SizedBox(height: 2),
                  Text('유효기간: ${_formatDate(item.expiresAt)}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(item),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GifticonDetailPage(item: item),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}