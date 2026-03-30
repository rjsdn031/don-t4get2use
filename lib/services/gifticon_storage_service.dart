import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/gifticon_models.dart';
import '../models/stored_gifticon.dart';

/// [saveGifticon]의 반환값.
/// [isDuplicate]가 true이면 기존에 저장된 [gifticon]을 그대로 반환한 것.
class SaveGifticonResult {
  final StoredGifticon gifticon;
  final bool isDuplicate;

  const SaveGifticonResult({
    required this.gifticon,
    required this.isDuplicate,
  });
}

class GifticonStorageService {
  static const String _boxName = 'gifticons';
  final Uuid _uuid = const Uuid();

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  Future<SaveGifticonResult> saveGifticon({
    required String sourceImagePath,
    required GifticonInfo info,
  }) async {
    final existing = _findDuplicate(info);
    if (existing != null) {
      debugPrint(
        '[Gifticon][Storage] duplicate detected — skipping save. '
            'existing id=${existing.id}, '
            'couponNumber=${existing.couponNumber}, '
            'merchantName=${existing.merchantName}, '
            'itemName=${existing.itemName}, '
            'expiresAt=${existing.expiresAt}',
      );
      return SaveGifticonResult(gifticon: existing, isDuplicate: true);
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

    debugPrint(
      '[Gifticon][Storage] saved new gifticon id=$id, '
          'couponNumber=${info.couponNumber}, '
          'merchantName=${info.merchantName}, '
          'itemName=${info.itemName}, '
          'expiresAt=${info.expiresAt}',
    );

    return SaveGifticonResult(gifticon: stored, isDuplicate: false);
  }

  List<StoredGifticon> getAllGifticons() {
    final box = Hive.box(_boxName);

    return box.values
        .map((item) => StoredGifticon.fromJson(item as Map))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<StoredGifticon> markAsUsed(String id) async {
    final box = Hive.box(_boxName);
    final raw = box.get(id);
    if (raw == null) throw Exception('기프티콘을 찾을 수 없습니다: $id');

    final existing = StoredGifticon.fromJson(raw as Map);
    if (existing.isUsed) return existing; // 이미 사용됨

    final updated = existing.copyWith(usedAt: DateTime.now());
    await box.put(id, updated.toJson());

    debugPrint('[Gifticon][Storage] marked as used: id=$id');
    return updated;
  }

  /// 공유 완료 시 sharedAt 업데이트
  Future<void> markAsShared(String id) async {
    final box = Hive.box(_boxName);
    final raw = box.get(id);
    if (raw == null) return;

    final existing = StoredGifticon.fromJson(raw as Map);
    if (existing.sharedAt != null) return;

    final updated = existing.copyWith(sharedAt: DateTime.now());
    await box.put(id, updated.toJson());
    debugPrint('[Gifticon][Storage] marked as shared: id=$id');
  }

  /// FCM으로 공유받은 기프티콘을 로컬에 저장
  Future<StoredGifticon> saveReceivedGifticon({
    required String gifticonId,
    required String localImagePath,
    required String? merchantName,
    required String? itemName,
    required String? couponNumber,
    required DateTime expiresAt,
    required String receivedFrom,
  }) async {
    final box = Hive.box(_boxName);

    // 이미 있으면 그대로 반환
    final existing = box.get(gifticonId);
    if (existing != null) {
      return StoredGifticon.fromJson(existing as Map);
    }

    final savedImagePath = await _copyImageToAppDirectory(
      sourceImagePath: localImagePath,
      id: gifticonId,
    );

    final stored = StoredGifticon(
      id: gifticonId,
      imagePath: savedImagePath,
      merchantName: merchantName,
      itemName: itemName,
      expiresAt: expiresAt,
      couponNumber: couponNumber,
      createdAt: DateTime.now(),
      receivedFrom: receivedFrom,
    );

    await box.put(gifticonId, stored.toJson());
    debugPrint('[Gifticon][Storage] received gifticon saved: id=$gifticonId');
    return stored;
  }

  /// FCM gifticon_used 수신 시 — id가 있으면 로컬도 사용 처리
  Future<void> markAsUsedIfExists(String id) async {
    final box = Hive.box(_boxName);
    final raw = box.get(id);
    if (raw == null) return;

    final existing = StoredGifticon.fromJson(raw as Map);
    if (existing.isUsed) return;

    final updated = existing.copyWith(usedAt: DateTime.now());
    await box.put(id, updated.toJson());
    debugPrint('[Gifticon][Storage] markAsUsedIfExists: id=$id');
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
          debugPrint(
            '[Gifticon][Storage] duplicate matched by couponNumber: $normalizedCoupon',
          );
          return item;
        }
      }
    }

    final normalizedMerchant = _normalize(info.merchantName);
    final normalizedItem = _normalize(info.itemName);
    final normalizedExpiresAt = _normalizeDate(info.expiresAt);

    // 식별할 수 있는 필드가 하나도 없으면 중복 판정 불가
    if (normalizedMerchant == null &&
        normalizedItem == null &&
        normalizedExpiresAt == null) {
      debugPrint(
        '[Gifticon][Storage] all fields null — skipping fuzzy duplicate check',
      );
      return null;
    }

    for (final item in items) {
      final sameMerchant = _normalize(item.merchantName) == normalizedMerchant;
      final sameItem = _normalize(item.itemName) == normalizedItem;
      final sameExpiresAt = _normalizeDate(item.expiresAt) == normalizedExpiresAt;

      if (sameMerchant && sameItem && sameExpiresAt) {
        debugPrint(
          '[Gifticon][Storage] duplicate matched by merchant+item+expiresAt: '
              'merchant=$normalizedMerchant, item=$normalizedItem, expiresAt=$normalizedExpiresAt',
        );
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