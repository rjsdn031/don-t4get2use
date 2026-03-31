import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/gifticon_models.dart';
import '../models/stored_gifticon.dart';
import 'now_provider.dart';

// WorkManager isolate → 메인 isolate 갱신 신호용 키
const String kPendingRefreshKey = 'gifticon_pending_refresh';

class SaveGifticonResult {
  final StoredGifticon gifticon;
  final bool isDuplicate;

  const SaveGifticonResult({
    required this.gifticon,
    required this.isDuplicate,
  });
}

class GifticonStorageService {
  GifticonStorageService({
    NowProvider? nowProvider,
  }) : _nowProvider = nowProvider ?? SystemNowProvider();

  static const String _boxName = 'gifticons';
  final Uuid _uuid = const Uuid();
  final NowProvider _nowProvider;
  final StreamController<List<StoredGifticon>> _itemsController =
  StreamController<List<StoredGifticon>>.broadcast();

  Stream<List<StoredGifticon>> watchGifticons() => _itemsController.stream;

  /// 외부에서 스트림 갱신을 트리거할 때 사용 (알림 콜백 등)
  void emitItems() => _emitItems();

  void _emitItems() {
    if (_itemsController.isClosed) return;
    _itemsController.add(getAllGifticons());
  }

  void _emitItemsWithFollowUps() {
    _emitItems();

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      _emitItems();
    });

    Future<void>.delayed(const Duration(seconds: 1), () {
      _emitItems();
    });
  }


  void dispose() {
    _itemsController.close();
  }

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    _emitItems();
  }

  Future<void> reopenBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      await Hive.box(_boxName).close();
      debugPrint('[Gifticon][Storage] box closed: $_boxName');
    }

    await Hive.openBox(_boxName);
    debugPrint('[Gifticon][Storage] box reopened: $_boxName');

    _emitItems();
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
      _emitItemsWithFollowUps();
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
      createdAt: _nowProvider.now(),
    );

    final box = Hive.box(_boxName);
    await box.put(id, stored.toJson());
    _emitItemsWithFollowUps();

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

  StoredGifticon? getGifticonById(String id) {
    final box = Hive.box(_boxName);
    final raw = box.get(id);
    if (raw == null) return null;
    return StoredGifticon.fromJson(raw as Map);
  }

  Future<StoredGifticon> markAsUsed(String id, {String? myNickname}) async {
    final box = Hive.box(_boxName);
    final raw = box.get(id);
    if (raw == null) throw Exception('기프티콘을 찾을 수 없습니다: $id');

    final existing = StoredGifticon.fromJson(raw as Map);
    if (existing.isUsed) return existing;

    final updated = existing.copyWith(
      usedAt: _nowProvider.now(),
      usedByNickname: myNickname ?? existing.usedByNickname,
    );
    await box.put(id, updated.toJson());
    _emitItemsWithFollowUps();

    debugPrint('[Gifticon][Storage] marked as used: id=$id nickname=$myNickname');
    return updated;
  }

  Future<void> markAsShared(String id) async {
    final box = Hive.box(_boxName);
    final raw = box.get(id);
    if (raw == null) return;

    final existing = StoredGifticon.fromJson(raw as Map);
    if (existing.sharedAt != null) return;

    final updated = existing.copyWith(sharedAt: _nowProvider.now());
    await box.put(id, updated.toJson());
    _emitItems();
    debugPrint('[Gifticon][Storage] marked as shared: id=$id');
  }

  Future<StoredGifticon> saveReceivedGifticon({
    required String gifticonId,
    required String localImagePath,
    required String? merchantName,
    required String? itemName,
    required String? couponNumber,
    required DateTime expiresAt,
    required String receivedFrom,
    String? ownerNickname,
  }) async {
    final box = Hive.box(_boxName);

    final existing = box.get(gifticonId);
    if (existing != null) {
      final stored = StoredGifticon.fromJson(existing as Map);

      if (stored.ownerNickname == ownerNickname || ownerNickname == null) {
        return stored;
      }

      final updated = stored.copyWith(ownerNickname: ownerNickname);
      await box.put(gifticonId, updated.toJson());
      _emitItems();
      return updated;
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
      createdAt: _nowProvider.now(),
      receivedFrom: receivedFrom,
      ownerNickname: ownerNickname,
    );

    await box.put(gifticonId, stored.toJson());
    _emitItemsWithFollowUps();
    debugPrint('[Gifticon][Storage] received gifticon saved: id=$gifticonId');
    return stored;
  }

  Future<StoredGifticon> updateGifticon(StoredGifticon item) async {
    final box = Hive.box(_boxName);
    final raw = box.get(item.id);

    if (raw == null) {
      throw Exception('수정할 기프티콘을 찾을 수 없습니다: ${item.id}');
    }

    await box.put(item.id, item.toJson());
    _emitItems();
    debugPrint('[Gifticon][Storage] updated gifticon: id=${item.id}');
    return item;
  }

  Future<void> markAsUsedIfExists(
      String id, {
        String? usedByNickname,
      }) async {
    final box = Hive.box(_boxName);
    final raw = box.get(id);
    if (raw == null) return;

    final existing = StoredGifticon.fromJson(raw as Map);

    if (existing.isUsed && existing.usedByNickname == usedByNickname) {
      return;
    }

    final updated = existing.copyWith(
      usedAt: existing.usedAt ?? _nowProvider.now(),
      usedByNickname: usedByNickname ?? existing.usedByNickname,
    );

    await box.put(id, updated.toJson());
    _emitItems();
    debugPrint(
      '[Gifticon][Storage] markAsUsedIfExists: id=$id usedByNickname=$usedByNickname',
    );
  }

  /// WorkManager isolate에서 저장 완료 후 호출 — 메인 isolate에 갱신 신호 전달
  static Future<void> markPendingRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPendingRefreshKey, true);
    debugPrint('[Gifticon][Storage] pendingRefresh set');
  }

  /// 메인 isolate에서 polling 시 호출 — 플래그가 있으면 true 반환 후 초기화
  static Future<bool> consumePendingRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(kPendingRefreshKey) ?? false;
    if (pending) {
      await prefs.remove(kPendingRefreshKey);
      debugPrint('[Gifticon][Storage] pendingRefresh consumed');
    }
    return pending;
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
    _emitItems();
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
    final targetFile = File(targetPath);

    final bytes = await sourceFile.readAsBytes();
    await targetFile.writeAsBytes(bytes, flush: true);

    await _waitUntilDecodable(targetFile);

    debugPrint(
      '[Gifticon][Storage] image ready '
          'source=$sourceImagePath target=$targetPath bytes=${bytes.length}',
    );

    return targetFile.path;
  }

  Future<void> _waitUntilDecodable(
      File file, {
        Duration timeout = const Duration(seconds: 3),
        Duration interval = const Duration(milliseconds: 150),
      }) async {
    final sw = Stopwatch()..start();

    while (sw.elapsed < timeout) {
      try {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            await instantiateImageCodec(bytes);
            return;
          }
        }
      } catch (_) {
        // 아직 디코딩 가능한 상태가 아니면 재시도
      }

      await Future<void>.delayed(interval);
    }

    debugPrint('[Gifticon][Storage] waitUntilDecodable timeout: ${file.path}');
  }

  String _getExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1) return '.jpg';
    return path.substring(dotIndex);
  }
}