import 'dart:io';

import '../models/gifticon_models.dart';
import '../models/stored_gifticon.dart';
import 'device_id_service.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_sharing_service.dart';
import 'gifticon_storage_service.dart';

class DebugScenarioService {
  DebugScenarioService({
    required this.storageService,
    required this.notificationService,
    required this.sharingService,
    required this.deviceIdService,
  });

  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;
  final GifticonSharingService sharingService;
  final DeviceIdService deviceIdService;

  Future<String> getDeviceId() => deviceIdService.getDeviceId();

  Future<String?> getNickname() => deviceIdService.getNickname();

  List<StoredGifticon> getAllGifticons() => storageService.getAllGifticons();

  Future<StoredGifticon> seedGifticon({
    required DateTime expiresAt,
    String merchantName = '스타벅스',
    String itemName = '아메리카노',
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('gifticon_seed');
    final imageFile = File('${tempDir.path}/seed_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await imageFile.writeAsBytes(<int>[1, 2, 3, 4, 5, 6]);

    final result = await storageService.saveGifticon(
      sourceImagePath: imageFile.path,
      info: GifticonInfo(
        merchantName: merchantName,
        itemName: itemName,
        expiresAt: expiresAt,
        couponNumber: 'DEBUG-${DateTime.now().millisecondsSinceEpoch}',
        rawText: 'debug scenario seed',
      ),
    );

    return result.gifticon;
  }

  Future<void> triggerOneDayBeforeShare(StoredGifticon stored) async {
    await notificationService.scheduleExpiryNotifications(stored);
  }

  Future<void> directShare(StoredGifticon stored) async {
    await sharingService.uploadForSharing(stored);
  }

  Future<void> markUsedRemote(String gifticonId) async {
    await sharingService.markAsUsedRemote(gifticonId: gifticonId);
  }

  Future<void> markUsedLocal(String gifticonId) async {
    final nickname = await deviceIdService.getNickname();
    await storageService.markAsUsed(gifticonId, myNickname: nickname);
  }

  Future<void> refreshRemoteUsedIfExists({
    required String gifticonId,
    String? usedByNickname,
  }) {
    return storageService.markAsUsedIfExists(
      gifticonId,
      usedByNickname: usedByNickname,
    );
  }
}