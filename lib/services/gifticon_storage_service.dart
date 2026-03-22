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
    await Hive.openBox(_boxName);
  }

  Future<StoredGifticon> saveGifticon({
    required String sourceImagePath,
    required GifticonInfo info,
  }) async {
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