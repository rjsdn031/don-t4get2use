import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/gifticon_models.dart';
import '../models/stored_gifticon.dart';

class GifticonStorageService {
  static const String _boxName = 'gifticons';
  final Uuid _uuid = const Uuid();

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  Future<StoredGifticon> saveGifticon({
    required String sourceImagePath,
    required GifticonInfo info,
  }) async {
    final existing = _findDuplicate(info);
    if (existing != null) {
      return existing;
    }

    final id = _uuid.v4();
    final savedImagePath = await _copyImageToAppDirectory(
      sourceImagePath: sourceImagePath,
      id: id,
    );

    final stored = StoredGifticon(
      id: id,
      imagePath: savedImagePath,
      merchantName: info.merchantName,
      itemName: info.itemName,
      expiresAt: info.expiresAt,
      couponNumber: info.couponNumber,
      createdAt: DateTime.now(),
    );

    final box = Hive.box(_boxName);
    await box.put(id, stored.toJson());

    return stored;
  }

  List<StoredGifticon> getAllGifticons() {
    final box = Hive.box(_boxName);

    return box.values
        .map((item) => StoredGifticon.fromJson(item as Map))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> deleteGifticon(String id) async {
    final box = Hive.box(_boxName);
    final raw = box.get(id);

    if (raw != null) {
      final stored = StoredGifticon.fromJson(raw as Map);
      final file = File(stored.imagePath);

      if (await file.exists()) {
        await file.delete();
      }
    }

    await box.delete(id);
  }

  StoredGifticon? _findDuplicate(GifticonInfo info) {
    final items = getAllGifticons();

    final normalizedCoupon = _normalize(info.couponNumber);
    if (normalizedCoupon != null) {
      for (final item in items) {
        final existingCoupon = _normalize(item.couponNumber);
        if (existingCoupon != null && existingCoupon == normalizedCoupon) {
          return item;
        }
      }
    }

    final normalizedMerchant = _normalize(info.merchantName);
    final normalizedItem = _normalize(info.itemName);
    final normalizedExpiresAt = _normalizeDate(info.expiresAt);

    for (final item in items) {
      final sameMerchant =
          _normalize(item.merchantName) == normalizedMerchant;
      final sameItem =
          _normalize(item.itemName) == normalizedItem;
      final sameExpiresAt =
          _normalizeDate(item.expiresAt) == normalizedExpiresAt;

      if (sameMerchant && sameItem && sameExpiresAt) {
        return item;
      }
    }

    return null;
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.toLowerCase();
  }

  String? _normalizeDate(DateTime? value) {
    if (value == null) return null;
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<String> _copyImageToAppDirectory({
    required String sourceImagePath,
    required String id,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final gifticonDir = Directory('${appDir.path}/gifticons');

    if (!await gifticonDir.exists()) {
      await gifticonDir.create(recursive: true);
    }

    final sourceFile = File(sourceImagePath);
    final extension = _getExtension(sourceImagePath);
    final targetPath = '${gifticonDir.path}/gifticon_$id$extension';

    final copied = await sourceFile.copy(targetPath);
    return copied.path;
  }

  String _getExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1) return '.jpg';
    return path.substring(dotIndex);
  }
}